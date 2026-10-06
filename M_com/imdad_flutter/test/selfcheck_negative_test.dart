import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/repos/selfcheck_repo.dart';

/// الأرصدة السالبة: لا تُمنع عند الحفظ بل تنشأ بعد دمج جهازين، فيكشفها فحص السلامة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> item(String code, String name) => CatalogRepo(db).saveItem(
        code: code,
        name: name,
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

  /// صرفٌ مكتوب مباشرةً كما يصل بالدمج، متجاوزًا فحص الرصيد عند الحفظ.
  Future<void> mergedIssue(String itemId, String warehouse, double qty) =>
      db.into(db.issues).insert(IssuesCompanion.insert(
            id: Ids.next('is'),
            warehouse: Value(warehouse),
            itemId: Value(itemId),
            qty: Value(qty),
            baseQty: Value(qty),
          ));

  Future<SelfCheckResult> check() async =>
      (await SelfCheckRepo(db).runAll()).singleWhere((r) => r.id == 'negativeStock');

  test('قاعدة بلا حركات: البند سليم', () async {
    final r = await check();
    expect(r.ok, isTrue);
    expect(r.note, contains('لا توجد'));
  });

  test('صرفان دُمجا على رصيد لا يكفي أحدهما: البند يفشل ويسمّي الصنف والمستودع', () async {
    final id = await item('S1', 'سكر');
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: id,
          warehouse: const Value('الرئيسي'),
          qty: const Value(10),
        ));
    await mergedIssue(id, 'الرئيسي', 8);
    await mergedIssue(id, 'الرئيسي', 8); // الجهاز الآخر صرف الرصيد نفسه ⇒ −6

    final r = await check();
    expect(r.ok, isFalse);
    expect(r.note, contains('سكر'));
    expect(r.note, contains('الرئيسي'));

    final negatives = await MovementsRepo(db).negativeBalances();
    expect(negatives.single.qty, -6);
  });

  test('الصفر والرصيد الموجب لا يُعدّان سالبًا، والنطاق يحصر المستودعات', () async {
    final id = await item('S1', 'سكر');
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: id,
          warehouse: const Value('أ'),
          qty: const Value(5),
        ));
    await mergedIssue(id, 'أ', 5); // ⇒ 0
    await mergedIssue(id, 'ب', 3); // ⇒ −3 في مستودع آخر

    final repo = MovementsRepo(db);
    expect((await repo.negativeBalances()).map((n) => n.warehouse), ['ب']);
    expect(await repo.negativeBalances(scope: ['أ']), isEmpty, reason: 'خارج نطاق المستخدم');
  });
}
