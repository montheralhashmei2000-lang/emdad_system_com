import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// البندان H-1 وH-7 في تدقيق 2026-10-10: سجلٌّ له مفتاحٌ طبيعيٌّ فريد (سجل معسكرٍ
/// لشهر، تصفية شهر، حدّ مخزون، وحدة محروقات باسمها، رصيدٌ افتتاحي) يُنشئه جهازان
/// قبل أن يتزامنا بمعرّفين مختلفين.
///
/// كان الدمج يصطدم بالفهرس الفريد فيُجهض الاستيراد كله في كل دورة — توقّفت
/// المزامنة بين الجهازين لكل البيانات. والرصيد الافتتاحي بلا فهرس: يبقى صفّان
/// فيُحتسب الرصيد مرتين.
void main() {
  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// تبادلٌ كامل في الاتجاهين كما تفعله دورة المزامنة.
  Future<(LegacyImportResult, LegacyImportResult)> exchange() async {
    final toB = await LegacyImporter(b).importJson(await DataExporter(a).toMap());
    final toA = await LegacyImporter(a).importJson(await DataExporter(b).toMap());
    return (toB, toA);
  }

  Future<void> ledger(AppDatabase db, String id) => db.into(db.campLedgers).insert(CampLedgersCompanion.insert(
        id: id,
        campId: 'camp-1',
        itemId: 'itm-1',
        year: 2026,
        month: 9,
        entitlementTotal: Value(id == 'cld-a' ? 10 : 20),
      ));

  test('سجل المعسكر نفسه بمعرّفين لا يوقف المزامنة، ويلتقي الجهازان على صفٍّ واحد', () async {
    await ledger(a, 'cld-a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ledger(b, 'cld-b'); // الأحدث

    final (toB, toA) = await exchange();
    expect(toB.failedRows, 0);
    expect(toA.failedRows, 0);

    final rowsA = await a.select(a.campLedgers).get();
    final rowsB = await b.select(b.campLedgers).get();
    expect(rowsA.map((r) => r.id), ['cld-b']);
    expect(rowsB.map((r) => r.id), ['cld-b']);
    expect(rowsA.single.entitlementTotal, 20);
  });

  test('تصفية الشهر نفسه على جهازين لا تتصادم', () async {
    for (final (db, id) in [(a, 'stl-a'), (b, 'stl-b')]) {
      await db.into(db.monthlySettlements).insert(MonthlySettlementsCompanion.insert(id: id, year: 2026, month: 9));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final (toB, toA) = await exchange();
    expect(toB.failedRows + toA.failedRows, 0);
    expect((await a.select(a.monthlySettlements).get()).map((r) => r.id), ['stl-b']);
    expect((await b.select(b.monthlySettlements).get()).map((r) => r.id), ['stl-b']);
  });

  test('وحدة محروقات بالاسم نفسه: يبقى صفٌّ واحد وتتحوّل مراجع الخاسر إليه', () async {
    await a.into(a.fuelUnits).insert(FuelUnitsCompanion.insert(id: 'fun-a', name: 'الكتيبة الأولى'));
    await a.into(a.fuelAllocations).insert(FuelAllocationsCompanion.insert(
          id: 'fal-a',
          unitId: const Value('fun-a'),
          unitName: const Value('الكتيبة الأولى'),
        ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.into(b.fuelUnits).insert(FuelUnitsCompanion.insert(id: 'fun-b', name: 'الكتيبة الأولى'));

    final (toB, toA) = await exchange();
    expect(toB.failedRows + toA.failedRows, 0);
    expect((await a.select(a.fuelUnits).get()).map((u) => u.id), ['fun-b']);
    final alloc = await (a.select(a.fuelAllocations)..where((t) => t.id.equals('fal-a'))).getSingle();
    expect(alloc.unitId, 'fun-b', reason: 'بقيت التفريدة تشير إلى وحدةٍ حُذفت');
  });

  test('الرصيد الافتتاحي يُثبَّت على جهازين فيبقى واحدًا لا يُجمع (H-7)', () async {
    final id = await CatalogRepo(a).saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await LegacyImporter(b).importJson(await DataExporter(a).toMap());
    final itemA = (await CatalogRepo(a).items()).single;
    final itemB = (await CatalogRepo(b).items()).single;

    await CatalogRepo(a).setOpeningBalance(itemA, 'الرئيسي', 100, 'a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await CatalogRepo(b).setOpeningBalance(itemB, 'الرئيسي', 120, 'b');
    await exchange();

    for (final db in [a, b]) {
      final rows = await db.select(db.openingBalances).get();
      expect(rows, hasLength(1));
      expect((await MovementsRepo(db).balances(warehouse: 'الرئيسي'))[id], 120);
    }
  });

  test('صفّا رصيدٍ افتتاحي من إصدارٍ أقدم بمعرّفين عشوائيين يُحسمان بالدمج', () async {
    for (final (db, rid, qty) in [(a, 'opb-old-a', 30.0), (b, 'opb-old-b', 45.0)]) {
      await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: rid,
            itemId: 'itm-9',
            warehouse: const Value('الرئيسي'),
            qty: Value(qty),
          ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await exchange();
    for (final db in [a, b]) {
      final rows = await db.select(db.openingBalances).get();
      expect(rows.map((r) => r.id), ['opb-old-b']);
    }
  });

  test('جدولٌ يتعثّر دمجه لا يُجهض بقية الحمولة ولا تُثبَّت علاماته', () async {
    final payload = await DataExporter(a).toMap();
    payload['items'] = [
      {'id': 'itm-ok', 'code': 'OK', 'name': 'صنف سليم', 'units': '[]'},
    ];
    payload['cables'] = [
      {'id': 'cab-broken'}, // ينقصه ما يلزم البرقية فيرمي عند البناء
    ];
    payload['syncMarks'] = [
      {'entity': 'items', 'rowId': 'itm-ok', 'updatedAt': 1},
      {'entity': 'cables', 'rowId': 'cab-broken', 'updatedAt': 1},
    ];

    final res = await LegacyImporter(b).importJson(payload);
    expect(res.failedRows, greaterThan(0));
    expect((await CatalogRepo(b).items()).map((i) => i.code), contains('OK'));
    final marks = await SyncMarks(b).snapshot();
    expect(marks['cables/cab-broken'], isNull, reason: 'ثُبّتت علامة سجلٍّ لم يُكتب');
  });
}
