import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// الأسطوانة أصل ثابت: تدخل جديدة مرة واحدة، وما بعدها تعبئة أو استبدال —
/// الأسطوانة نفسها تخرج فارغة وتعود ممتلئة فلا يتغيّر عددها في المستودع.
///
/// كان دفتر الأرصدة يتجاهل نوع العملية كليًا فيضيف كل توريد إلى الرصيد، فينتفخ
/// عدد الأسطوانات مع كل تعبئة. هذه الاختبارات تحرس القاعدة الجديدة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late CatalogRepo catalog;
  late String gas;
  late String rice;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    gas = await catalog.saveItem(
      code: 'G1',
      name: 'أسطوانة غاز',
      baseUnit: 'أسطوانة',
      units: const [ItemUnit(name: 'أسطوانة', factor: 1, isBase: true)],
      isRefillable: true,
    );
    rice = await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() => db.close());

  DocLineInput line(String id, String code, String name, String unit, double qty,
          {String cy = ''}) =>
      DocLineInput(
        itemId: id,
        itemCode: code,
        itemName: name,
        unitName: unit,
        factor: 1,
        qty: qty,
        cylinderAction: cy,
      );

  Future<void> receive(double qty, {String cy = ''}) => mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'شركة الغاز',
        date: '2026-09-20',
        lines: [line(gas, 'G1', 'أسطوانة غاز', 'أسطوانة', qty, cy: cy)],
      );

  Future<void> issue(double qty, {String cy = ''}) => mv.saveIssue(
        warehouse: 'الرئيسي',
        recipientDisplay: 'سرية الإسناد',
        date: '2026-09-20',
        lines: [line(gas, 'G1', 'أسطوانة غاز', 'أسطوانة', qty, cy: cy)],
      );

  Future<double> balance() async => (await mv.balances(warehouse: 'الرئيسي'))[gas] ?? 0;

  group('الأسطوانات أصول ثابتة', () {
    test('التوريد الجديد وحده يزيد العدد، والتعبئة لا تزيده', () async {
      await receive(50, cy: 'RECEIVE_FULL');
      expect(await balance(), 50);

      // ثلاث عمليات تعبئة متتالية — العدد يجب أن يبقى ٥٠.
      await receive(20, cy: 'REFILL');
      await receive(20, cy: 'REFILL');
      await receive(10, cy: 'REFILL');

      expect(await balance(), 50, reason: 'التعبئة تُعيد أسطوانات موجودة أصلًا');
    });

    test('توريد أسطوانات فارغة جديدة يزيد العدد', () async {
      await receive(30, cy: 'RECEIVE_FULL');
      await receive(5, cy: 'RECEIVE_EMPTY');

      expect(await balance(), 35);
    });

    test('الاستبدال لا ينقص العدد: فارغة تدخل وممتلئة تخرج', () async {
      await receive(50, cy: 'RECEIVE_FULL');
      await issue(12, cy: 'EXCHANGE');
      await issue(8, cy: 'EXCHANGE');

      expect(await balance(), 50);
    });

    test('الصرف النهائي ينقص العدد فعلًا', () async {
      await receive(50, cy: 'RECEIVE_FULL');
      await issue(6, cy: 'ISSUE_FULL');
      await issue(4, cy: 'ISSUE_EMPTY');
      await issue(2, cy: 'CONSUME');

      expect(await balance(), 38);
    });

    test('دورة حياة كاملة: توريد ثم استبدالات ثم تعبئة ثم صرف نهائي', () async {
      await receive(100, cy: 'RECEIVE_FULL'); // 100
      await issue(40, cy: 'EXCHANGE'); //  ثابت
      await receive(40, cy: 'REFILL'); //  ثابت
      await issue(10, cy: 'ISSUE_FULL'); //  90
      await receive(25, cy: 'RECEIVE_FULL'); // 115

      expect(await balance(), 115);
    });

    test('الأصناف العادية لا تتأثر بقاعدة الأسطوانات', () async {
      // القيمة تُخزَّن فارغة لغير القابل للتعبئة، فيجب أن يُجمع كل توريد.
      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-20',
        lines: [line(rice, 'R1', 'أرز', 'كجم', 100)],
      );
      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-20',
        lines: [line(rice, 'R1', 'أرز', 'كجم', 50)],
      );

      expect((await mv.balances(warehouse: 'الرئيسي'))[rice], 150);
    });

    test('الحساب في القاعدة يطابق الحساب المرجعي في الذاكرة', () async {
      await receive(60, cy: 'RECEIVE_FULL');
      await receive(20, cy: 'REFILL');
      await issue(15, cy: 'EXCHANGE');
      await issue(5, cy: 'ISSUE_FULL');

      final sql = await mv.balances(warehouse: 'الرئيسي');
      final memory = (await mv.ledger()).balances(warehouse: 'الرئيسي');

      expect(sql, memory);
      expect(sql[gas], 55);
    });
  });
}
