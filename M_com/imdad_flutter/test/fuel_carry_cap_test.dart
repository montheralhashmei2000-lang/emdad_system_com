import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/db/pre_migration_backup.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// البند H-6 في تدقيق 2026-10-10، وقرار المالك في 2026-10-11: الاستحقاق
/// يتراكم **بسقف**، مع خيار **تصفير**، ولا صرف بتاريخٍ قادم.
///
/// كان المتبقي يُحسب حتى تاريخ السند الذي يُدخله المستخدم: سندٌ مؤرّخ في آخر
/// السنة يتيح الآن صرف استحقاق السنة كلها. وكان التراكم بلا حدّ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الحساب', () {
    const monthly = FuelAllocationCalc(
      periodType: FuelPeriod.monthly,
      quantityPerPeriod: 1000,
      startDate: '2026-01-01',
      carryCapPeriods: 3,
    );
    final oct = DateTime(2026, 10, 10);

    test('ما لم يُصرف يتراكم ولا يُتاح منه أكثر من السقف', () {
      expect(Fuel.entitledLiters(monthly, oct), 10000);
      expect(Fuel.remainingLiters(allocation: monthly, issued: 0, asOf: oct), 3000);
      expect(Fuel.remainingLiters(allocation: monthly, issued: 8500, asOf: oct), 1500);
    });

    test('سقفٌ صفر ⇒ بلا سقف، والفترة المحددة لا تتراكم أصلًا', () {
      const free = FuelAllocationCalc(
          periodType: FuelPeriod.monthly, quantityPerPeriod: 1000, startDate: '2026-01-01');
      expect(Fuel.remainingLiters(allocation: free, issued: 0, asOf: oct), 10000);
      expect(Fuel.carryCap(const FuelAllocationCalc(
        periodType: FuelPeriod.custom,
        quantityPerPeriod: 0,
        totalQuantity: 500,
        startDate: '2026-01-01',
        carryCapPeriods: 3,
      )), isNull);
    });

    test('المشطوب بالتصفير يُطرح من المستحق', () {
      const reset = FuelAllocationCalc(
        periodType: FuelPeriod.monthly,
        quantityPerPeriod: 1000,
        startDate: '2026-01-01',
        writtenOff: 9500,
      );
      expect(Fuel.entitledLiters(reset, oct), 500);
    });

    test('تاريخٌ قادم يُرفض، ولا يُحسب الاستحقاق بعد اليوم', () {
      expect(
        Fuel.issueBlock(allocation: monthly, date: '2026-12-31', qty: 10, alreadyIssued: 0, now: oct),
        contains('المستقبل'),
      );
      expect(Fuel.issueBlock(allocation: monthly, date: '2026-10-10', qty: 3000, alreadyIssued: 0, now: oct), isNull);
      expect(Fuel.issueBlock(allocation: monthly, date: '2026-10-10', qty: 3001, alreadyIssued: 0, now: oct),
          isNotNull);
    });
  });

  group('المستودع', () {
    late AppDatabase db;
    late FuelRepo repo;
    late String allocationId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = FuelRepo(db);
      await repo.saveWarehouse(name: 'مستودع الوقود', capacityLiters: 100000);
      final unitId = (await repo.saveUnit(name: 'الكتيبة الأولى')).refNo;
      await repo.saveSupply(
        date: '2026-01-01',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 50000,
        supplierName: 'مورّد',
      );
      // شهرية منذ أكثر من سنة: المتراكم بلا سقف يفوق العشرة آلاف.
      final start = DateTime.now().subtract(const Duration(days: 400));
      await repo.saveAllocation(
        unitId: unitId,
        unitName: 'الكتيبة الأولى',
        fuelType: FuelType.diesel,
        periodType: FuelPeriod.monthly,
        quantityPerPeriod: 1000,
        startDate: '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
      );
      allocationId = (await repo.allocations()).single.allocation.id;
    });

    tearDown(() => db.close());

    String today([int addDays = 0]) {
      final d = DateTime.now().add(Duration(days: addDays));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    Future<FuelResult> issue(double liters, {String? date}) => repo.saveIssue(
          date: date ?? today(),
          fuelType: FuelType.diesel,
          warehouse: 'مستودع الوقود',
          quantityLiters: liters,
          allocationId: allocationId,
          driverName: 'سائق',
          chassisNo: 'SH-1',
        );

    test('الصرف بتاريخٍ قادم يُرفض في المستودع نفسه لا في الشاشة وحدها', () async {
      final res = await issue(100, date: today(30));
      expect(res.ok, isFalse);
      expect(res.error, contains('المستقبل'));
    });

    test('السقف الافتراضي ثلاث فترات: صرف ما فوقه يُرفض', () async {
      expect((await repo.settings()).carryCapPeriods, 3);
      expect((await issue(3001)).ok, isFalse);
      expect((await issue(3000)).ok, isTrue);
    });

    test('السقف يُضبط من الإعدادات، وصفرٌ يرفعه', () async {
      final s = await repo.settings();
      await repo.saveSettings(
        lowStockPercent: s.lowStockPercent,
        defaultDailyLiters: s.defaultDailyLiters,
        defaultWeeklyLiters: s.defaultWeeklyLiters,
        defaultMonthlyLiters: s.defaultMonthlyLiters,
        carryCapPeriods: 0,
      );
      expect((await issue(9000)).ok, isTrue);
    });

    test('التصفير يشطب المتبقي فيصير صفرًا ويُدقَّق', () async {
      final before = (await repo.allocations()).single;
      expect(before.remaining, greaterThan(0));
      final res = await repo.resetCarry(allocationId, actor: 'fuel@imdad.local');
      expect(res.ok, isTrue, reason: res.error);
      final after = (await repo.allocations()).single;
      expect(after.remaining, 0);
      expect(after.allocation.writtenOffLiters, greaterThan(0));
      expect((await issue(1)).ok, isFalse);
      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('fuel.allocation.reset'))).get();
      expect(audit.single.risk, 'high');
      expect((await repo.resetCarry(allocationId)).ok, isFalse, reason: 'لا رصيد بعد التصفير');
    });
  });

  group('ترحيل v26', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('imdad_v26');
      file = File(p.join(dir.path, 'imdad.sqlite'));
      PreMigrationBackup.directoryProvider = () async => dir;
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // يبقى مقفلًا أحيانًا على ويندوز.
      }
    });

    test('قاعدة v25 تكسب العمودين بقيمتيهما، وتُؤخذ نسخةٌ قبل الترحيل', () async {
      final seed = AppDatabase.forTesting(NativeDatabase(file));
      await FuelRepo(seed).settings();
      await seed.close();
      final raw = sql.sqlite3.open(file.path);
      raw.execute('ALTER TABLE fuel_settings_rows DROP COLUMN carry_cap_periods');
      raw.execute('ALTER TABLE fuel_allocations DROP COLUMN written_off_liters');
      raw.execute('PRAGMA user_version = 25');
      raw.dispose();

      final db = AppDatabase.forTesting(NativeDatabase(
        file,
        setup: (r) => PreMigrationBackup.createIfNeeded(r, file),
      ));
      expect((await FuelRepo(db).settings()).carryCapPeriods, 3);
      final cols = {
        for (final r in await db.customSelect('PRAGMA table_info(fuel_allocations)').get()) r.read<String>('name'),
      };
      expect(cols, contains('written_off_liters'));
      await db.close();

      final copies = [
        for (final e in dir.listSync())
          if (e is File && p.basename(e.path).contains('.pre-v26-') && !e.path.endsWith('.json')) e,
      ];
      expect(copies, hasLength(1), reason: 'لم تُؤخذ نسخة قبل ترحيل v26');
    });
  });
}
