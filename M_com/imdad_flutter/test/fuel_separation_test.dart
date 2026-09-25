import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/domain/fuel.dart';

/// فصل قسم المحروقات عن الإمداد.
///
/// **الخطر في الفصل ليس الشاشات بل البيانات**: سندات الوقود تشير إلى المستودع
/// **بالاسم**، فدليلٌ جديد لا يحمل تلك الأسماء يترك كل سندٍ مسجَّل معلّقًا
/// بمستودعٍ لا وجود له — ويظهر رصيده صفرًا وهو ممتلئ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الترحيل ينقل ما يخصّ الوقود', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('imdad_fuel_sep');
      file = File('${dir.path}/db.sqlite');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // يبقى مقفلًا أحيانًا على ويندوز.
      }
    });

    test('مستودعات الإعاشة التي عليها حركة وقود تُنسخ إلى دليله', () async {
      // قاعدة كما كانت قبل الفصل: الوقود في دليل الإعاشة.
      final before = AppDatabase.forTesting(NativeDatabase(file));
      await before.into(before.warehouses).insert(WarehousesCompanion.insert(
            id: 'wh1',
            name: 'خزان الديزل',
            fuelCapacityLiters: const Value(15000),
          ));
      await before
          .into(before.warehouses)
          .insert(WarehousesCompanion.insert(id: 'wh2', name: 'مخزن الطحين'));
      await before.into(before.beneficiaryUnits).insert(
          BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'الكتيبة الأولى'));
      await before
          .into(before.beneficiaryUnits)
          .insert(BeneficiaryUnitsCompanion.insert(id: 'u2', name: 'وحدة طعام'));
      await before.into(before.fuelAllocations).insert(
          FuelAllocationsCompanion.insert(
              id: 'a1',
              unitId: const Value('u1'),
              unitName: const Value('الكتيبة الأولى')));
      // أفرغ دليلي المحروقات ثم أعد الطابَع، كأن الفصل لم يجرِ بعد.
      await before.customStatement('DELETE FROM fuel_warehouses');
      await before.customStatement('DELETE FROM fuel_units');
      await before.customStatement('PRAGMA user_version = 17');
      await before.close();

      final after = AppDatabase.forTesting(NativeDatabase(file));
      final repo = FuelRepo(after);
      final warehouses = await repo.warehouses();
      final units = await repo.units();
      await after.close();

      expect(warehouses.map((w) => w.name), contains('خزان الديزل'),
          reason: 'مستودع وقود لم يُنقل، فسنداته تعلّق باسمٍ بلا دليل');
      expect(warehouses.map((w) => w.name), isNot(contains('مخزن الطحين')),
          reason: 'مخزن إعاشة دخل دليل المحروقات');
      expect(warehouses.firstWhere((w) => w.name == 'خزان الديزل').capacityLiters,
          15000,
          reason: 'السعة ضاعت في النقل فلا تنبيه نسبة بعده');

      expect(units.map((u) => u.name), contains('الكتيبة الأولى'));
      expect(units.map((u) => u.name), isNot(contains('وحدة طعام')),
          reason: 'وحدة لا تفريدة وقود لها دخلت دليل المحروقات');
    });

    test('المستودع المذكور في سندٍ ينتقل ولو بلا سعة', () async {
      final before = AppDatabase.forTesting(NativeDatabase(file));
      await before
          .into(before.warehouses)
          .insert(WarehousesCompanion.insert(id: 'wh9', name: 'خزان الطوارئ'));
      await before.into(before.fuelSupplies).insert(FuelSuppliesCompanion.insert(
            id: 'sup1',
            warehouse: const Value('خزان الطوارئ'),
            quantityLiters: const Value(500),
            date: const Value('2026-01-01'),
          ));
      await before.customStatement('DELETE FROM fuel_warehouses');
      await before.customStatement('PRAGMA user_version = 17');
      await before.close();

      final after = AppDatabase.forTesting(NativeDatabase(file));
      final warehouses = await FuelRepo(after).warehouses();
      // الرصيد يجب أن يُقرأ بعد النقل، لا أن يظهر صفرًا.
      final stock = await FuelRepo(after).available('خزان الطوارئ', FuelType.diesel);
      await after.close();

      expect(warehouses.map((w) => w.name), contains('خزان الطوارئ'));
      expect(stock, 500, reason: 'السند علّق بمستودعٍ لم يُنقل فظهر رصيده صفرًا');
    });
  });

  group('الدليلان مستقلان فعلًا', () {
    late AppDatabase db;
    late FuelRepo repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = FuelRepo(db);
    });

    tearDown(() => db.close());

    test('مستودع إعاشة لا يظهر في دليل المحروقات', () async {
      await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(id: 'w1', name: 'مخزن الأرز'));
      expect(await repo.warehouses(), isEmpty,
          reason: 'دليل الإعاشة تسرّب إلى المحروقات');
      expect(await repo.stocks(), isEmpty);
    });

    test('وحدة إعاشة لا تظهر في دليل المحروقات', () async {
      await db.into(db.beneficiaryUnits).insert(
          BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'سرية الإعاشة'));
      expect(await repo.units(), isEmpty);
    });

    test('الاسم المكرر يُرفض في كل دليل على حدة', () async {
      expect((await repo.saveWarehouse(name: 'خزان')).ok, isTrue);
      expect((await repo.saveWarehouse(name: 'خزان')).ok, isFalse);
      // والاسم نفسه في دليل الإعاشة لا يمنع، فالدليلان مستقلان.
      await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(id: 'w1', name: 'خزان'));
      expect((await repo.saveWarehouse(name: 'خزان الثاني')).ok, isTrue);
    });

    test('مستودع عليه حركة لا يُحذف ولا يُعاد تسميته', () async {
      final res = await repo.saveWarehouse(name: 'خزان العمليات');
      await repo.saveSupply(
        date: '2026-01-01',
        fuelType: FuelType.diesel,
        warehouse: 'خزان العمليات',
        quantityLiters: 900,
      );
      final id = (await repo.warehouses()).single.id;
      expect(res.ok, isTrue);

      expect((await repo.deleteWarehouse(id)).error, contains('عطّله'));
      // السندات تشير بالاسم، فتغييره يقطع صلتها به.
      final renamed = await repo.saveWarehouse(id: id, name: 'اسم آخر');
      expect(renamed.ok, isFalse);
      expect(renamed.error, contains('حركة'));
    });

    test('وحدة لها تفريدة لا تُحذف', () async {
      final unit = await repo.saveUnit(name: 'كتيبة المدرعات');
      await repo.saveWarehouse(name: 'خزان');
      await repo.saveAllocation(
        unitId: unit.refNo,
        unitName: 'كتيبة المدرعات',
        fuelType: FuelType.diesel,
        periodType: FuelPeriod.monthly,
        quantityPerPeriod: 500,
        startDate: '2026-01-01',
      );
      expect((await repo.deleteUnit(unit.refNo)).error, contains('عطّلها'));
    });
  });

  group('الإعدادات', () {
    late AppDatabase db;
    late FuelRepo repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = FuelRepo(db);
      await repo.saveWarehouse(name: 'خزان', capacityLiters: 10000);
    });

    tearDown(() => db.close());

    test('تُنشأ بقيمها الافتراضية عند أول قراءة', () async {
      final s = await repo.settings();
      expect(s.lowStockPercent, 20);
      expect(s.allowExceptional, isTrue);
      expect(s.requireChassis, isFalse);
    });

    test('حد التنبيه المضبوط هو ما تستعمله التنبيهات', () async {
      await repo.saveSupply(
        date: '2026-01-01',
        fuelType: FuelType.diesel,
        warehouse: 'خزان',
        quantityLiters: 3000, // 30٪ من السعة
      );
      expect((await repo.alerts()).any((a) => a.title.contains('رصيد منخفض')),
          isFalse);

      await repo.saveSettings(
        lowStockPercent: 40,
        defaultDailyLiters: 200,
        defaultWeeklyLiters: 1000,
        defaultMonthlyLiters: 4000,
      );
      expect((await repo.alerts()).any((a) => a.title.contains('رصيد منخفض')),
          isTrue,
          reason: 'الحد المضبوط من الإعدادات لم يُستعمل');
    });

    test('نسبة خارج المئة تُرفض', () async {
      final res = await repo.saveSettings(
        lowStockPercent: 150,
        defaultDailyLiters: 0,
        defaultWeeklyLiters: 0,
        defaultMonthlyLiters: 0,
      );
      expect(res.ok, isFalse);
    });

    test('اشتراط الشاصي يمنع الصرف بدونه', () async {
      await repo.saveSupply(
          date: '2026-01-01',
          fuelType: FuelType.diesel,
          warehouse: 'خزان',
          quantityLiters: 5000);
      await repo.saveSettings(
        lowStockPercent: 20,
        defaultDailyLiters: 200,
        defaultWeeklyLiters: 1000,
        defaultMonthlyLiters: 4000,
        requireChassis: true,
      );
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'خزان',
        quantityLiters: 50,
        source: FuelSource.exceptional,
        justification: 'م',
        orderAuthority: 'ج',
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('الشاصي'));
    });

    test('تعطيل الاستثنائي يمنعه', () async {
      await repo.saveSupply(
          date: '2026-01-01',
          fuelType: FuelType.diesel,
          warehouse: 'خزان',
          quantityLiters: 5000);
      await repo.saveSettings(
        lowStockPercent: 20,
        defaultDailyLiters: 200,
        defaultWeeklyLiters: 1000,
        defaultMonthlyLiters: 4000,
        allowExceptional: false,
      );
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'خزان',
        quantityLiters: 50,
        source: FuelSource.exceptional,
        justification: 'م',
        orderAuthority: 'ج',
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('معطَّل'));
    });
  });

  group('المساحات بعد الفصل', () {
    test('مساحة المحروقات لا تتضمن أدلة الإعاشة', () {
      final fuel = AppSpace.pages[AppSpace.fuel]!;
      expect(fuel, isNot(contains('stores')));
      expect(fuel, isNot(contains('units')));
      expect(fuel, contains('fuelWarehouses'));
      expect(fuel, contains('fuelUnits'));
    });

    test('من له دليل مستودعات الوقود وحده يملك مساحة المحروقات', () {
      expect(AppSpace.availableFor((p) => p == 'fuelWarehouses'),
          [AppSpace.fuel]);
    });
  });
}
