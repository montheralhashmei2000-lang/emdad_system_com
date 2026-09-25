import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/doc_numbering.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/repos/stocktake_repo.dart';

/// ترقيم السندات برمز الجهاز وعدّاد مخزَّن.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late String rice;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    final catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    rice = await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() => db.close());

  Future<String> receive({String refNo = ''}) async {
    final r = await mv.saveReceipt(
      warehouse: 'الرئيسي',
      supplier: 'المورد',
      date: '2026-09-20',
      refNo: refNo,
      lines: [DocLineInput(itemId: rice, itemCode: 'R1', itemName: 'أرز', unitName: 'كجم', factor: 1, qty: 1)],
    );
    expect(r.ok, isTrue, reason: r.error);
    return r.refNo;
  }

  test('المرجع يحمل رمز الجهاز ويبدأ من 1', () async {
    final code = await DocNumbering(db).deviceCode();
    expect(code, matches(RegExp(r'^[2-9A-Z]{4}$')));
    expect(await mv.nextRef('receipts', 'و-'), 'و-$code-000001');
  });

  test('عرض الرقم لا يستهلكه، والحفظ يثبّته', () async {
    final code = await DocNumbering(db).deviceCode();
    final shown = await mv.nextRef('receipts', 'و-');
    expect(await mv.nextRef('receipts', 'و-'), shown, reason: 'فتح الشاشة وإغلاقها لا يترك فجوة');

    expect(await receive(refNo: shown), shown);
    expect(await mv.nextRef('receipts', 'و-'), 'و-$code-000002');
    expect(await receive(), 'و-$code-000002', reason: 'الحفظ بلا مرجع يأخذ التالي');
    expect(await mv.nextRef('receipts', 'و-'), 'و-$code-000003');
  });

  test('التسلسل مستقل لكل نوع سند', () async {
    final code = await DocNumbering(db).deviceCode();
    await receive();
    await receive();
    expect(await mv.nextRef('issues', 'ص-'), 'ص-$code-000001');
  });

  test('سندات جهاز آخر لا تحرّك عدّاد هذا الجهاز', () async {
    final code = await DocNumbering(db).deviceCode();
    final other = code == 'ZZZZ' ? 'YYYY' : 'ZZZZ';
    await receive(); // يبذر العدّاد ويثبت 1
    await receive(refNo: 'و-$other-000500'); // وصل بالمزامنة أو أُدخل يدويًا
    expect(await mv.nextRef('receipts', 'و-'), 'و-$code-000002');
  });

  test('جهاز فيه سندات بالصيغة القديمة يُكمل من أعلى رقم فيها', () async {
    await db.into(db.receipts).insert(ReceiptsCompanion.insert(id: 'old-1', refNo: const Value('و-000041')));
    final code = await DocNumbering(db).deviceCode();
    expect(await mv.nextRef('receipts', 'و-'), 'و-$code-000042');
  });

  test('العدّاد خارج المزامنة: لا يُسجَّل له أثر في sync_marks', () async {
    await receive();
    final marks = await db
        .customSelect("SELECT COUNT(*) AS c FROM sync_marks WHERE entity = 'doc_counters'")
        .getSingle();
    expect(marks.read<int>('c'), 0);
  });

  test('أوامر الجرد تحمل رمز الجهاز وتُكمل من الصيغة القديمة', () async {
    final year = DateTime.now().year;
    await db.into(db.stocktakes).insert(StocktakesCompanion.insert(
          id: 'st-old',
          orderNo: Value('STK-$year-007'),
          status: const Value('CLOSED'),
          warehouse: const Value('الرئيسي'),
        ));
    final code = await DocNumbering(db).deviceCode();
    final id = await StocktakeRepo(db).createOrder(warehouse: 'الرئيسي', date: '2026-09-20');
    final order = await (db.select(db.stocktakes)..where((t) => t.id.equals(id))).getSingle();
    expect(order.orderNo, 'STK-$year-$code-008');
  });
}
