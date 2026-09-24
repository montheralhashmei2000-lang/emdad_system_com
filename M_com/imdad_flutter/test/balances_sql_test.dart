import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// حساب الأرصدة انتقل من الذاكرة إلى SUM/GROUP BY داخل قاعدة البيانات.
/// هذه الاختبارات تقارن المخرجين على البيانات نفسها: أي اختلاف بينهما خطأ،
/// لأن `StockLedger` هو المرجع المنقول حرفيًا عن `stock-ledger.js`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late CatalogRepo catalog;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    catalog = CatalogRepo(db);
  });

  tearDown(() => db.close());

  Future<String> item(String code, String name) => catalog.saveItem(
        code: code,
        name: name,
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

  DocLineInput line(String id, String code, String name, double qty) => DocLineInput(
        itemId: id,
        itemCode: code,
        itemName: name,
        unitName: 'كجم',
        factor: 1,
        qty: qty,
      );

  /// يقارن الحساب داخل القاعدة بالحساب المرجعي في الذاكرة.
  Future<void> expectSameAsLedger({String? warehouse, List<String>? scope}) async {
    final sql = await mv.balances(warehouse: warehouse, scope: scope);
    final memory = (await mv.ledger()).balances(warehouse: warehouse, scope: scope);
    expect(sql, memory, reason: 'مستودع: $warehouse — نطاق: $scope');
  }

  group('تكافؤ حساب الأرصدة', () {
    test('وارد وصادر ومرتجع وتحويل — المستودع والإجمالي والنطاق', () async {
      final rice = await item('1001', 'أرز');
      final oil = await item('1002', 'زيت');
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await catalog.saveWarehouse(code: 'W2', name: 'الفرع');

      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-01',
        lines: [line(rice, '1001', 'أرز', 100), line(oil, '1002', 'زيت', 50)],
      );
      await mv.saveIssue(
        warehouse: 'الرئيسي',
        recipientDisplay: 'سرية الإسناد',
        date: '2026-09-02',
        lines: [line(rice, '1001', 'أرز', 30)],
      );
      await mv.saveReturn(
        warehouse: 'الرئيسي',
        party: 'سرية الإسناد',
        date: '2026-09-03',
        lines: [line(rice, '1001', 'أرز', 5)],
      );
      await mv.saveTransfer(
        fromWarehouse: 'الرئيسي',
        toWarehouse: 'الفرع',
        date: '2026-09-04',
        lines: [line(oil, '1002', 'زيت', 20)],
      );

      await expectSameAsLedger(warehouse: 'الرئيسي');
      await expectSameAsLedger(warehouse: 'الفرع');
      await expectSameAsLedger();
      await expectSameAsLedger(scope: const ['الرئيسي']);
    });

    test('المسودات والأوامر المعلقة لا تدخل الحساب في الطريقتين', () async {
      final rice = await item('2001', 'طحين');
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');

      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-01',
        lines: [line(rice, '2001', 'طحين', 80)],
      );
      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-02',
        draft: true,
        lines: [line(rice, '2001', 'طحين', 999)],
      );

      final sql = await mv.balances(warehouse: 'الرئيسي');
      expect(sql[rice], 80);
      await expectSameAsLedger(warehouse: 'الرئيسي');
    });

    test('المرتجع التالف لا يزيد الرصيد في الطريقتين', () async {
      final rice = await item('3001', 'عدس');
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');

      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-01',
        lines: [line(rice, '3001', 'عدس', 40)],
      );
      await mv.saveReturn(
        warehouse: 'الرئيسي',
        party: 'سرية',
        date: '2026-09-02',
        condition: 'تالفة',
        lines: [line(rice, '3001', 'عدس', 10)],
      );

      expect((await mv.balances(warehouse: 'الرئيسي'))[rice], 40);
      await expectSameAsLedger(warehouse: 'الرئيسي');
    });

    test('قاعدة فارغة تعطي خريطة فارغة في الطريقتين', () async {
      await expectSameAsLedger();
      await expectSameAsLedger(warehouse: 'لا يوجد');
    });

    test('الصنف الذي خرج كل رصيده يبقى بصفر لا يختفي', () async {
      final sugar = await item('4001', 'سكر');
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');

      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-01',
        lines: [line(sugar, '4001', 'سكر', 25)],
      );
      await mv.saveIssue(
        warehouse: 'الرئيسي',
        recipientDisplay: 'سرية الإسناد',
        date: '2026-09-02',
        lines: [line(sugar, '4001', 'سكر', 25)],
      );

      final sql = await mv.balances(warehouse: 'الرئيسي');
      expect(sql[sugar], 0);
      await expectSameAsLedger(warehouse: 'الرئيسي');
    });
  });
}
