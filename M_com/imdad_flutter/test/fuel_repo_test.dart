import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/domain/fuel.dart';

/// قسم المحروقات على قاعدة حقيقية.
///
/// **الرصيد محسوبٌ لا مخزَّن**، فهذه الاختبارات تحرس أن كل سندٍ يحرّكه في
/// اتجاهه الصحيح — وأن الجرد لا يمسّه حتى يُرحَّل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FuelRepo repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FuelRepo(db);
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1',
          name: 'مستودع الوقود',
          isMain: const Value(true),
          fuelCapacityLiters: const Value(20000),
        ));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرعي'));
    await db.into(db.beneficiaryUnits).insert(
        BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'الكتيبة الأولى'));
  });

  tearDown(() => db.close());

  Future<double> diesel([String wh = 'مستودع الوقود']) =>
      repo.available(wh, FuelType.diesel);

  Future<void> supply(double liters, {String wh = 'مستودع الوقود'}) async {
    final res = await repo.saveSupply(
      date: '2026-01-01',
      fuelType: FuelType.diesel,
      warehouse: wh,
      quantityLiters: liters,
      supplierName: 'مورّد الوقود',
    );
    expect(res.ok, isTrue, reason: res.error);
  }

  Future<String> allocation({
    double qty = 1000,
    String period = FuelPeriod.monthly,
    bool disbursable = true,
  }) async {
    final res = await repo.saveAllocation(
      unitId: 'u1',
      unitName: 'الكتيبة الأولى',
      fuelType: FuelType.diesel,
      periodType: period,
      quantityPerPeriod: qty,
      startDate: '2026-01-01',
      disbursable: disbursable,
    );
    expect(res.ok, isTrue, reason: res.error);
    return (await repo.allocations()).single.allocation.id;
  }

  group('الرصيد يتحرّك باتجاه سنده', () {
    test('التوريد يزيد والصرف ينقص', () async {
      await supply(5000);
      expect(await diesel(), 5000);

      final id = await allocation(qty: 4000);
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 1200,
        allocationId: id,
        driverName: 'سائق',
        chassisNo: 'SH-1',
      );
      expect(res.ok, isTrue, reason: res.error);
      expect(await diesel(), 3800);
    });

    test('التحويل ينقص من المصدر ويزيد الهدف', () async {
      await supply(5000);
      final res = await repo.saveTransfer(
        date: '2026-01-06',
        fuelType: FuelType.diesel,
        fromWarehouse: 'مستودع الوقود',
        toWarehouse: 'الفرعي',
        quantityLiters: 2000,
      );
      expect(res.ok, isTrue, reason: res.error);
      expect(await diesel(), 3000);
      expect(await diesel('الفرعي'), 2000);
    });

    test('الرصيد الافتتاحي يدخل الحساب', () async {
      await repo.saveOpening(
        warehouse: 'مستودع الوقود',
        fuelType: FuelType.diesel,
        liters: 800,
        asOfDate: '2026-01-01',
      );
      expect(await diesel(), 800);
    });

    test('نوعٌ لا يخلط بنوع', () async {
      await supply(5000);
      expect(await repo.available('مستودع الوقود', FuelType.petrol), 0,
          reason: 'ديزلٌ ظهر في رصيد البترول');
    });
  });

  group('حدود الصرف', () {
    test('الصرف فوق رصيد المستودع يُمنع', () async {
      await supply(100);
      final id = await allocation(qty: 5000);
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 500,
        allocationId: id,
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('100'));
      expect(await diesel(), 100, reason: 'الصرف المرفوض حرّك الرصيد');
    });

    test('الصرف فوق استحقاق التفريدة يُمنع ولو كفى الرصيد', () async {
      await supply(50000);
      final id = await allocation(qty: 1000);
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 4000,
        allocationId: id,
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('المتبقي'));
    });

    test('التفريدة الموقوفة عن الصرف تُمنع', () async {
      await supply(5000);
      final id = await allocation(disbursable: false);
      final res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 10,
        allocationId: id,
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('القائد'));
    });

    test('الأمر الاستثنائي يلزمه مبرر وجهة أمر', () async {
      await supply(5000);
      var res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 100,
        source: FuelSource.exceptional,
      );
      expect(res.error, contains('مبرر'));

      res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 100,
        source: FuelSource.exceptional,
        justification: 'مهمة عاجلة',
      );
      expect(res.error, contains('جهة الأمر'));

      res = await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 100,
        source: FuelSource.exceptional,
        justification: 'مهمة عاجلة',
        orderAuthority: 'مكتب القائد',
        beneficiaryName: 'سرية الإسناد',
      );
      expect(res.ok, isTrue, reason: res.error);
      expect(await diesel(), 4900);
    });

    test('الأمر الاستثنائي يُسجَّل عالي الخطورة', () async {
      await supply(5000);
      await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 100,
        source: FuelSource.exceptional,
        justification: 'مهمة',
        orderAuthority: 'مكتب القائد',
      );
      final logs = await db.select(db.auditLogs).get();
      final entry = logs.firstWhere((l) => l.action == 'fuel.issue');
      expect(entry.risk, 'high',
          reason: 'صرفٌ خارج التفريدة يجب أن يُميَّز في سجل التدقيق');
    });
  });

  group('التفريدة', () {
    test('الاستحقاق يتراكم والمتبقي ينقص بالصرف', () async {
      await supply(50000);
      final id = await allocation(qty: 1000);
      await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 400,
        allocationId: id,
      );
      final row = (await repo.allocations(asOf: DateTime(2026, 3, 1))).single;
      expect(row.entitled, 3000);
      expect(row.issued, 400);
      expect(row.remaining, 2600);
    });

    test('التفريدة المصروف عليها لا تُحذف', () async {
      await supply(50000);
      final id = await allocation();
      await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 10,
        allocationId: id,
      );
      final res = await repo.deleteAllocation(id);
      expect(res.ok, isFalse);
      expect(res.error, contains('أوقفها'));
    });

    test('النهاية قبل البداية تُرفض', () async {
      final res = await repo.saveAllocation(
        unitId: 'u1',
        unitName: 'الكتيبة الأولى',
        fuelType: FuelType.diesel,
        periodType: FuelPeriod.monthly,
        quantityPerPeriod: 100,
        startDate: '2026-06-01',
        endDate: '2026-01-01',
      );
      expect(res.ok, isFalse);
    });
  });

  group('الجرد', () {
    Future<String> openTake() async {
      await supply(5000);
      final res = await repo.openStocktake(
        date: '2026-02-01',
        warehouse: 'مستودع الوقود',
        committee: 'لجنة الجرد',
      );
      expect(res.ok, isTrue, reason: res.error);
      return (await repo.stocktakes()).single.id;
    }

    test('الفتح يلتقط الرصيد الدفتري وقتَه', () async {
      final id = await openTake();
      final lines = await repo.stocktakeLines(id);
      final line = lines.firstWhere((l) => l.fuelType == FuelType.diesel);
      expect(line.bookLiters, 5000);
      expect(line.counted, isFalse);
    });

    test('العدّ لا يمسّ الرصيد قبل الترحيل', () async {
      final id = await openTake();
      final lines = await repo.stocktakeLines(id);
      final line = lines.firstWhere((l) => l.fuelType == FuelType.diesel);
      await repo.countLine(lineId: line.id, counted: 4800);
      expect(await diesel(), 5000,
          reason: 'عدٌّ لم يُراجع بعد غيّر الرصيد');
    });

    test('الترحيل يُدخل الفرق في الرصيد', () async {
      final id = await openTake();
      for (final l in await repo.stocktakeLines(id)) {
        await repo.countLine(
            lineId: l.id, counted: l.fuelType == FuelType.diesel ? 4800 : 0);
      }
      // مفتوح ← عدّ ← تحليل ← مرحّل
      for (var i = 0; i < 3; i++) {
        final res = await repo.advanceStocktake(id);
        expect(res.ok, isTrue, reason: res.error);
      }
      expect((await repo.stocktakes()).single.status,
          FuelStocktakeStatus.posted);
      expect(await diesel(), 4800, reason: 'العجز لم يدخل الرصيد بعد الترحيل');
    });

    test('لا يُرحَّل جرد فيه صنف لم يُعدّ', () async {
      final id = await openTake();
      await repo.advanceStocktake(id);
      await repo.advanceStocktake(id);
      final res = await repo.advanceStocktake(id);
      expect(res.ok, isFalse);
      expect(res.error, contains('لم يُعدّ'),
          reason: 'خزّانٌ لم يُفتح كان سيصير عجزًا كاملًا');
    });

    test('المرحّل لا مرحلة بعده', () async {
      final id = await openTake();
      for (final l in await repo.stocktakeLines(id)) {
        await repo.countLine(lineId: l.id, counted: l.bookLiters);
      }
      for (var i = 0; i < 3; i++) {
        await repo.advanceStocktake(id);
      }
      expect((await repo.advanceStocktake(id)).ok, isFalse);
    });
  });

  group('سجل الشاصيات والتنبيهات', () {
    test('الشاصي يجمع صرفه ولو تعدّد سائقوه', () async {
      await supply(50000);
      final id = await allocation(qty: 5000);
      for (final driver in ['أحمد', 'سالم']) {
        await repo.saveIssue(
          date: '2026-01-05',
          fuelType: FuelType.diesel,
          warehouse: 'مستودع الوقود',
          quantityLiters: 100,
          allocationId: id,
          driverName: driver,
          vehicleType: 'شاص',
          chassisNo: 'SH-9',
        );
      }
      final logs = await repo.chassisLogs();
      expect(logs, hasLength(1));
      expect(logs.single.count, 2);
      expect(logs.single.liters, 200);
    });

    test('الصرف بلا شاصي لا يدخل السجل', () async {
      await supply(5000);
      await repo.saveIssue(
        date: '2026-01-05',
        fuelType: FuelType.diesel,
        warehouse: 'مستودع الوقود',
        quantityLiters: 10,
        source: FuelSource.exceptional,
        justification: 'م',
        orderAuthority: 'ج',
      );
      expect(await repo.chassisLogs(), isEmpty);
    });

    test('النفاد والانخفاض يظهران في التنبيهات', () async {
      await supply(500); // من سعة ٢٠ ألفًا = ٢٫٥٪
      final alerts = await repo.alerts();
      expect(alerts.any((a) => a.title.contains('نفاد بترول')), isTrue);
      expect(alerts.any((a) => a.title.contains('رصيد منخفض')), isTrue);
    });
  });

  test('جداول المحروقات كلها داخل المزامنة', () {
    for (final t in [
      'fuel_allocations',
      'fuel_issues',
      'fuel_supplies',
      'fuel_openings',
      'fuel_transfers',
      'fuel_stocktakes',
      'fuel_stocktake_lines',
    ]) {
      expect(SyncMarks.entities.containsKey(t), isTrue,
          reason: '$t خارج المزامنة — تبقى بياناته حبيسة جهازها');
    }
  });
}
