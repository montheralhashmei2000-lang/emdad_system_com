import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';

/// إعادة تسمية مستودع.
///
/// كل حركةٍ تشير إلى مستودعها **بنصّ اسمه** لا بمعرّفه (ثلاثة عشر جدولًا)، فكان
/// تغييرُ الاسم يُيتّم ما أشار إليه بلا أي تحذير: رصيدٌ يظهر صفرًا، وحركاتٌ
/// باسمٍ لا مستودعَ له، ونطاقُ مستخدمٍ مقيَّد يفرغ. والمحروقات تمنعه منذ البداية
/// (`FuelRepo.saveWarehouse`)، والإمداد كان يسمح به.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CatalogRepo repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CatalogRepo(db);
  });

  tearDown(() => db.close());

  Future<String> makeWarehouse([String name = 'المخزن الرئيسي']) =>
      repo.saveWarehouse(code: 'W1', name: name);

  Future<String?> rename(String id, String to) async {
    try {
      await repo.saveWarehouse(id: id, code: 'W1', name: to);
      return null;
    } on WarehouseBlocked catch (e) {
      return e.message;
    }
  }

  Future<String> nameOf(String id) async =>
      (await (db.select(db.warehouses)..where((t) => t.id.equals(id))).getSingle()).name;

  test('مستودعٌ بلا أي ارتباط: الاسم يُغيَّر', () async {
    final id = await makeWarehouse();
    expect(await rename(id, 'مخزن الإعاشة'), isNull);
    expect(await nameOf(id), 'مخزن الإعاشة');
  });

  test('رسالة الرفض تذكر الاسم القديم وتدلّ على البديل', () async {
    final id = await makeWarehouse();
    await db.into(db.receipts).insert(
        ReceiptsCompanion.insert(id: 'r1', warehouse: const Value('المخزن الرئيسي')));
    final msg = await rename(id, 'مخزن الإعاشة');
    expect(msg, contains('المخزن الرئيسي'));
    expect(msg, contains('أنشئ مستودعًا'));
    expect(await nameOf(id), 'المخزن الرئيسي', reason: 'الاسم تغيّر رغم الرفض');
  });

  group('كل مرجعٍ بالاسم يمنع التسمية', () {
    /// سجلٌّ واحد في كل جدولٍ يشير إلى المستودع بالاسم.
    final seeds = <String, Future<void> Function(AppDatabase, String)>{
      'receipts': (d, w) =>
          d.into(d.receipts).insert(ReceiptsCompanion.insert(id: 'r1', warehouse: Value(w))),
      'issues': (d, w) => d.into(d.issues).insert(IssuesCompanion.insert(id: 'i1', warehouse: Value(w))),
      'transfers': (d, w) =>
          d.into(d.transfers).insert(TransfersCompanion.insert(id: 't1', warehouse: Value(w))),
      'transfers.dest': (d, w) =>
          d.into(d.transfers).insert(TransfersCompanion.insert(id: 't2', destWarehouse: Value(w))),
      'returns': (d, w) => d.into(d.returns).insert(ReturnsCompanion.insert(id: 'n1', warehouse: Value(w))),
      'adjustments': (d, w) =>
          d.into(d.adjustments).insert(AdjustmentsCompanion.insert(id: 'a1', warehouse: Value(w))),
      'opening_balances': (d, w) => d
          .into(d.openingBalances)
          .insert(OpeningBalancesCompanion.insert(id: 'o1', itemId: 'it1', warehouse: Value(w))),
      'stocktakes': (d, w) =>
          d.into(d.stocktakes).insert(StocktakesCompanion.insert(id: 's1', warehouse: Value(w))),
      'facilities': (d, w) => d
          .into(d.facilities)
          .insert(FacilitiesCompanion.insert(id: 'f1', name: 'مطبخ', warehouse: Value(w))),
      'meal_plans': (d, w) => d
          .into(d.mealPlans)
          .insert(MealPlansCompanion.insert(id: 'm1', name: 'خطة', warehouse: Value(w))),
      'assets': (d, w) =>
          d.into(d.assets).insert(AssetsCompanion.insert(id: 'as1', name: 'مولّد', warehouse: Value(w))),
      'ration_orders.requesting': (d, w) => d.into(d.rationOrders).insert(
          RationOrdersCompanion.insert(id: 'ro1', requestingWarehouse: Value(w))),
      'ration_orders.supplying': (d, w) => d.into(d.rationOrders).insert(
          RationOrdersCompanion.insert(id: 'ro2', supplyingWarehouse: Value(w))),
      'archive_files': (d, w) => d.into(d.archiveFiles).insert(ArchiveFilesCompanion.insert(
          id: 'ar1',
          title: 'سند',
          fileName: 'a.pdf',
          storedPath: '/tmp/a.pdf',
          sizeBytes: 1,
          warehouse: Value(w))),
      'warehouse_stock_limits': (d, w) => d.into(d.warehouseStockLimits).insert(
          WarehouseStockLimitsCompanion.insert(
              id: 'wl1', warehouseId: 'wh-x', itemId: 'it1', warehouseName: Value(w))),
      'users.warehouse_scope': (d, w) => d.into(d.users).insert(UsersCompanion.insert(
          id: 'u1', username: 'clerk', warehouseScope: Value('["$w"]'))),
    };

    for (final e in seeds.entries) {
      test(e.key, () async {
        final id = await makeWarehouse();
        await e.value(db, 'المخزن الرئيسي');
        expect(await rename(id, 'مخزن آخر'), isNotNull, reason: '${e.key} لم يمنع التسمية');
        expect(await nameOf(id), 'المخزن الرئيسي');
      });
    }

    test('القائمة تغطي كل أعمدة الاسم المعلنة (تفشل إذا أُضيف مرجعٌ ولم يُختبر)', () {
      final declared = {
        for (final e in CatalogRepo.warehouseNameRefs.entries)
          for (final col in e.value) '${e.key}.$col',
      };
      final covered = {
        for (final k in seeds.keys)
          if (k.contains('.')) k else '$k.warehouse',
      };
      // الأسماء المختصرة في `seeds` تُبسَط إلى `جدول.عمود` كما تُعلَن.
      const aliases = {
        'transfers.dest': 'transfers.dest_warehouse',
        'ration_orders.requesting': 'ration_orders.requesting_warehouse',
        'ration_orders.supplying': 'ration_orders.supplying_warehouse',
        'warehouse_stock_limits.warehouse': 'warehouse_stock_limits.warehouse_name',
      };
      final normalized = {for (final c in covered) aliases[c] ?? c};
      expect(declared.difference(normalized), isEmpty,
          reason: 'مرجعٌ معلَنٌ بلا اختبار: ${declared.difference(normalized).join('، ')}');
    });
  });

  test('تعديل بقية الحقول مسموح على مستودعٍ مستعمل (الاسم وحده المحظور)', () async {
    final id = await makeWarehouse();
    await db.into(db.issues).insert(IssuesCompanion.insert(id: 'i1', warehouse: const Value('المخزن الرئيسي')));
    await repo.saveWarehouse(
        id: id, code: 'W9', name: 'المخزن الرئيسي', manager: 'أبو بكر', location: 'المقر');
    final row = await (db.select(db.warehouses)..where((t) => t.id.equals(id))).getSingle();
    expect((row.code, row.manager, row.location), ('W9', 'أبو بكر', 'المقر'));
  });

  test('المسافات الزائدة لا تُعدّ تسميةً (نفس الاسم)', () async {
    final id = await makeWarehouse();
    await db.into(db.issues).insert(IssuesCompanion.insert(id: 'i1', warehouse: const Value('المخزن الرئيسي')));
    expect(await rename(id, '  المخزن الرئيسي  '), isNull);
  });

  test('نطاقٌ تالف لا يمنع التسمية بالخطأ (فشلٌ مغلق يُرجع قائمة فارغة)', () async {
    final id = await makeWarehouse();
    await db.into(db.users).insert(
        UsersCompanion.insert(id: 'u1', username: 'clerk', warehouseScope: const Value('{ليس JSON')));
    expect(await rename(id, 'مخزن آخر'), isNull);
  });

  test('ALL لا يمنع: المستخدم غير مقيَّد بمستودعٍ بعينه', () async {
    final id = await makeWarehouse();
    await db.into(db.users).insert(
        UsersCompanion.insert(id: 'u1', username: 'boss', warehouseScope: const Value('ALL')));
    expect(await rename(id, 'مخزن آخر'), isNull);
  });
}
