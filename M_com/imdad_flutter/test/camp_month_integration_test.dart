import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/camp_ledger_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/date_span.dart';

/// سيناريو شهر كامل: ثلاثة معسكرات × ثلاثة أصناف × ٣١ يومًا.
///
/// يمرّ على الدورة كلها: تفريدة يومية متغيّرة، تحويل على دفعات من المخزن
/// الرئيسي، استهلاك في المطابخ، مرتجع، ثم تصفية وترحيل إلى الشهر التالي.
/// الغرض أن تنكسر الحسابات هنا لا في الميدان بعد ثلاثين يومًا من العمل.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  // يناير ٢٠٢٦ — واحد وثلاثون يومًا.
  const year = 2026;
  const month = 1;
  const days = 31;

  /// قوة كل معسكر في كل يوم — متغيّرة كما في الواقع.
  const strengthPlan = <String, List<int>>{
    'camp1': [5000, 4000, 4500],
    'camp2': [4000, 3000, 5500],
    'camp3': [3000, 5000, 4000],
  };

  /// المقرر الشهري للفرد بوحدة الأساس.
  const scales = <String, double>{'rice': 3.0, 'oil': 0.6, 'sugar': 0.9};

  late Map<String, String> itemIds; // المفتاح المنطقي ⇦ معرّف الصنف
  late Map<String, double> campStrengthSum;

  Future<void> seed() async {
    // المخزن الرئيسي وثلاثة معسكرات.
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(id: 'wh-main', name: 'الرئيسي', isMain: const Value(true)),
        );
    for (final c in strengthPlan.keys) {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: c,
            name: 'معسكر $c',
            type: const Value('camp'),
            isCamp: const Value(true),
          ));
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(id: 'wh-$c', name: 'مخزن $c'),
          );
    }

    // الأصناف ومقرراتها.
    final catalog = CatalogRepo(db);
    itemIds = {};
    for (final e in scales.entries) {
      await catalog.saveItem(
        code: e.key,
        name: e.key,
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
    }
    for (final i in await catalog.items()) {
      itemIds[i.code] = i.id;
    }
    for (final e in scales.entries) {
      await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
            itemId: itemIds[e.key]!,
            itemName: Value(e.key),
            // المقرر شهري: القيمة اليومية × ٣٠.
            qtyPerPerson: Value(e.value * 30),
            measureFactor: const Value(1),
          ));
    }

    // تفريدة كل يوم لكل معسكر — القوة تدور على الأنماط الثلاثة.
    campStrengthSum = {for (final c in strengthPlan.keys) c: 0};
    for (var d = 1; d <= days; d++) {
      final date = DateSpan.ymd(DateTime(year, month, d));
      for (final entry in strengthPlan.entries) {
        final total = entry.value[(d - 1) % entry.value.length].toDouble();
        campStrengthSum[entry.key] = campStrengthSum[entry.key]! + total;
        await db.into(db.strengths).insert(StrengthsCompanion.insert(
              id: Ids.next('st'),
              unitId: entry.key,
              campId: Value(entry.key),
              strengthDate: date,
              total: Value(total),
              mode: const Value('detail'),
            ));
      }
    }
  }

  test('الاستحقاق يساوي المعدل اليومي × مجموع القوى لكل معسكر وصنف', () async {
    await seed();
    final repo = CampLedgerRepo(db);
    final written = await repo.rebuild(year: year, month: month);
    expect(written, 9, reason: 'ثلاثة معسكرات × ثلاثة أصناف');

    for (final camp in strengthPlan.keys) {
      final rows = await repo.ledgers(year: year, month: month, campId: camp);
      expect(rows, hasLength(3));
      for (final r in rows) {
        final key = r.ledger.itemName;
        final expected = scales[key]! * campStrengthSum[camp]!;
        expect(
          r.amounts.entitlementTotal,
          closeTo(expected, 0.5),
          reason: 'استحقاق $key في $camp',
        );
      }
    }
  });

  test('دورة شهر كاملة: تحويل واستهلاك ومرتجع ثم تصفية وترحيل', () async {
    await seed();
    final repo = CampLedgerRepo(db);
    final movements = MovementsRepo(db);

    // مرفق (مطبخ) لكل معسكر، مربوط به ليُنسب استهلاكه إليه.
    for (final camp in strengthPlan.keys) {
      await db.into(db.facilities).insert(FacilitiesCompanion.insert(
            id: 'fac-$camp',
            name: 'مطبخ $camp',
          ));
      await (db.update(db.beneficiaryUnits)..where((t) => t.id.equals(camp)))
          .write(BeneficiaryUnitsCompanion(facilityIds: Value('["fac-$camp"]')));
    }

    // رصيد افتتاحي في المخزن الرئيسي — بدونه يرفض النظام التحويل بحق:
    // لا يُحوَّل ما لا يُملك.
    const batch = <String, double>{'rice': 200000, 'oil': 40000, 'sugar': 60000};
    for (final e in batch.entries) {
      await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: Ids.next('ob'),
            itemId: itemIds[e.key]!,
            itemCode: Value(e.key),
            itemName: Value(e.key),
            warehouse: const Value('الرئيسي'),
            qty: Value(e.value * 3),
            date: Value(DateSpan.ymd(DateTime(year, month, 1))),
          ));
    }

    for (final day in [15, 30]) {
      for (final camp in strengthPlan.keys) {
        final res = await movements.saveTransfer(
          fromWarehouse: 'الرئيسي',
          toWarehouse: 'مخزن $camp',
          date: DateSpan.ymd(DateTime(year, month, day)),
          campId: camp,
          campName: 'معسكر $camp',
          lines: [
            for (final e in batch.entries)
              DocLineInput(
                itemId: itemIds[e.key]!,
                itemCode: e.key,
                itemName: e.key,
                unitName: 'كجم',
                factor: 1,
                qty: e.value / 2,
              ),
          ],
        );
        expect(res.ok, isTrue, reason: res.error);
      }
    }

    // استهلاك يومي في المطابخ.
    for (var d = 1; d <= days; d++) {
      final date = DateSpan.ymd(DateTime(year, month, d));
      for (final camp in strengthPlan.keys) {
        for (final e in scales.entries) {
          await db.into(db.kitchenLogs).insert(KitchenLogsCompanion.insert(
                id: Ids.next('kl'),
                facilityId: 'fac-$camp',
                date: date,
                itemId: Value(itemIds[e.key]!),
                itemName: Value(e.key),
                qty: const Value(100),
                baseQty: const Value(100),
              ));
        }
      }
    }

    // مرتجع من معسكر واحد — يجب أن يخصم من المُسلَّم.
    await movements.saveReturn(
      warehouse: 'الرئيسي',
      // الاسم مكتوب خطأً عمدًا: الربط بالمعرّف لا بالإملاء.
      party: 'معسكر  camp1 ',
      beneficiaryUnitId: 'camp1',
      beneficiaryUnitName: 'معسكر camp1',
      date: DateSpan.ymd(DateTime(year, month, 28)),
      lines: [
        DocLineInput(
          itemId: itemIds['rice']!,
          itemCode: 'rice',
          itemName: 'rice',
          unitName: 'كجم',
          factor: 1,
          qty: 5000,
        ),
      ],
    );

    await repo.rebuild(year: year, month: month);
    final rows = await repo.ledgers(year: year, month: month);
    expect(rows, hasLength(9));

    final rice1 = rows.firstWhere(
      (r) => r.ledger.campId == 'camp1' && r.ledger.itemName == 'rice',
    );
    expect(rice1.amounts.transferredIn, 200000, reason: 'دفعتان × ١٠٠٬٠٠٠');
    expect(rice1.amounts.returnedQty, 5000,
        reason: 'لم يُنسب المرتجع إلى معسكره رغم صحة معرّفه');
    expect(rice1.amounts.delivered, 195000, reason: 'المرتجع يُخصم من المُسلَّم');
    expect(rice1.amounts.consumedKitchen, 3100, reason: '٣١ يومًا × ١٠٠');
    expect(
      rice1.amounts.stockBalance,
      closeTo(195000 - 3100, 0.5),
      reason: 'رصيد المخزون = المُسلَّم − المستهلك',
    );

    // التصفية وترحيل الرصيدين.
    final settled = await repo.closeMonth(year: year, month: month, actor: 'مدير');
    expect(settled.ok, isTrue, reason: settled.error);
    expect(settled.camps, 3);
    expect(settled.items, 3);
    expect(settled.nextMonth, 2);
    expect(settled.nextYear, year);

    final next = await repo.ledgers(year: year, month: 2, campId: 'camp1');
    final nextRice = next.firstWhere((r) => r.ledger.itemName == 'rice');
    expect(nextRice.amounts.openingEntitled, rice1.amounts.entitlementBalance);
    expect(nextRice.amounts.openingStock, rice1.amounts.stockBalance);

    // الشهر المُصفّى مثبّت.
    final closed = await repo.ledgers(year: year, month: month);
    expect(closed.every((r) => r.ledger.status == 'CLOSED'), isTrue);
  });

  test('تصفية ديسمبر تُرحّل إلى يناير من السنة التالية', () async {
    await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
          id: 'camp1',
          name: 'معسكر',
          isCamp: const Value(true),
        ));
    await CatalogRepo(db).saveItem(
      code: 'X1',
      name: 'رز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    final item = (await CatalogRepo(db).items()).single;
    await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
          itemId: item.id,
          qtyPerPerson: const Value(30),
        ));
    await db.into(db.strengths).insert(StrengthsCompanion.insert(
          id: 'st1',
          unitId: 'camp1',
          campId: const Value('camp1'),
          strengthDate: '2025-12-15',
          total: const Value(100),
        ));

    final repo = CampLedgerRepo(db);
    await repo.rebuild(year: 2025, month: 12);
    final res = await repo.closeMonth(year: 2025, month: 12);

    expect(res.ok, isTrue, reason: res.error);
    expect(res.nextMonth, 1);
    expect(res.nextYear, 2026, reason: 'لم تنتقل السنة عند تصفية ديسمبر');
    expect(await repo.ledgers(year: 2026, month: 1), hasLength(1));
  });

  test('شهر فبراير الكبيس ينتهي في التاسع والعشرين', () async {
    // ٢٠٢٤ سنة كبيسة. الاعتماد على «٣٠ يومًا» يُسقط يومًا من التفريدة.
    final span = CampLedgerRepo.monthSpan(2024, 2);
    expect(span.end, '2024-02-29');
    expect(span.days, 29);
    expect(CampLedgerRepo.monthSpan(2026, 2).days, 28);
    expect(CampLedgerRepo.monthSpan(2026, 1).days, 31);
  });
}
