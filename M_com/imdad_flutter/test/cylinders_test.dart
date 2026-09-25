import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/cylinders_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/cylinders.dart';

/// دورة الأسطوانة كاملة كما تجري في الميدان، عبر دوال الحفظ الحقيقية: شراء،
/// تحويل لمستودع فرعي، عهدة لمطبخ ولوحدة، استبدال، إرسال للتعبئة وعودتها،
/// استهلاك داخلي، وإرجاع عهدة. في كل خطوة يجب أن يطابق مجموعُ حالات المستودع
/// رصيدَه في دفتر الأرصدة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late String gas;

  const main = 'الرئيسي';
  const branch = 'الفرعي';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    final catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: main);
    await catalog.saveWarehouse(code: 'W2', name: branch);
    gas = await catalog.saveItem(
      code: 'G1',
      name: 'أسطوانة غاز',
      baseUnit: 'أسطوانة',
      units: const [ItemUnit(name: 'أسطوانة', factor: 1, isBase: true)],
      isRefillable: true,
    );
    await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'السرية الأولى'));
    await db.into(db.facilities).insert(FacilitiesCompanion.insert(id: 'k1', name: 'مطبخ الفرعي'));
  });

  tearDown(() => db.close());

  DocLineInput line(double qty, String action) => DocLineInput(
      itemId: gas, itemCode: 'G1', itemName: 'أسطوانة غاز', unitName: 'أسطوانة', factor: 1, qty: qty, cylinderAction: action);

  Future<void> ok(Future<SaveResult> f) async {
    final r = await f;
    expect(r.ok, isTrue, reason: r.error);
  }

  Future<CylStock> at(String wh) async => (await CylindersRepo(db).position()).stock[gas]?[wh] ?? CylStock();

  Future<double> custody(String key) async =>
      (await CylindersRepo(db).position()).custody[gas]?[key]?.count ?? 0;

  /// مجموع الحالات = رصيد دفتر الأرصدة، في كل مستودع.
  Future<void> consistent() async {
    for (final wh in [main, branch]) {
      expect((await at(wh)).total, await mv.balanceOf(gas, warehouse: wh), reason: 'مستودع $wh');
    }
  }

  test('الدورة الكاملة', () async {
    // ١) شراء ١٠ ممتلئة و٥ فارغة للرئيسي.
    await ok(mv.saveReceipt(warehouse: main, supplier: 'شركة الغاز', date: '2026-09-01', lines: [
      line(10, CylAction.receiveFull),
      line(5, CylAction.receiveEmpty),
    ]));
    var s = await at(main);
    expect((s.full, s.empty), (10, 5));
    await consistent();

    // ٢) تحويل ٤ ممتلئة للفرعي: معلّقة ثم مستلمة.
    final tr = await mv.saveTransfer(
        fromWarehouse: main, toWarehouse: branch, date: '2026-09-02', lines: [line(4, CylAction.transferFull)]);
    expect(tr.ok, isTrue, reason: tr.error);
    s = await at(main);
    expect((s.full, s.inTransit), (6, 4));
    await mv.receiveTransfer(tr.refNo);
    expect((await at(branch)).full, 4);
    await consistent();

    // ٣) الفرعي يسلّم مطبخه ٢ ممتلئة عهدة.
    await ok(mv.saveIssue(
        warehouse: branch,
        recipientDisplay: 'مطبخ الفرعي',
        date: '2026-09-03',
        targetType: 1,
        facilityId: 'k1',
        lines: [line(2, CylAction.issueFull)]));
    expect((await at(branch)).full, 2);
    expect(await custody('facility:k1'), 2);

    // ٤) الرئيسي يسلّم السرية ٣ ممتلئة عهدة.
    await ok(mv.saveIssue(
        warehouse: main,
        recipientDisplay: 'السرية الأولى',
        date: '2026-09-03',
        unitId: 'u1',
        lines: [line(3, CylAction.issueFull)]));
    expect(await custody('unit:u1'), 3);
    await consistent();

    // ٥) السرية تستبدل ٢: تعيد فارغتين وتأخذ ممتلئتين — عهدتها لا تتغير.
    await ok(mv.saveIssue(
        warehouse: main,
        recipientDisplay: 'السرية الأولى',
        date: '2026-09-10',
        unitId: 'u1',
        lines: [line(2, CylAction.exchange)]));
    s = await at(main);
    expect((s.full, s.empty), (1, 7));
    expect(await custody('unit:u1'), 3);
    await consistent();

    // ٦) إرسال ٦ فارغة للمورد للتعبئة ثم عودتها ممتلئة.
    await ok(mv.saveIssue(
        warehouse: main,
        recipientDisplay: 'شركة الغاز',
        date: '2026-09-11',
        targetType: 2,
        lines: [line(6, CylAction.sendRefill)]));
    s = await at(main);
    expect((s.empty, s.atRefill), (1, 6));
    expect(await mv.balanceOf(gas, warehouse: main), 8, reason: 'عند المورد وما زالت ملك المستودع');
    await ok(mv.saveReceipt(
        warehouse: main, supplier: 'شركة الغاز', date: '2026-09-12', lines: [line(6, CylAction.refill)]));
    s = await at(main);
    expect((s.full, s.empty, s.atRefill), (7, 1, 0));
    await consistent();

    // ٧) استهلاك داخلي (صرف نهائي): تخرج أسطوانة من الرصيد.
    await ok(mv.saveIssue(
        warehouse: main,
        recipientDisplay: 'مطبخ المستودع',
        date: '2026-09-13',
        targetType: 2,
        lines: [line(1, CylAction.consume)]));
    s = await at(main);
    expect((s.full, s.empty), (6, 1));
    expect(await mv.balanceOf(gas, warehouse: main), 7);

    // ٨) السرية ترجع أسطوانة فارغة من عهدتها.
    await ok(mv.saveReturn(
        warehouse: main,
        party: 'السرية الأولى',
        beneficiaryUnitId: 'u1',
        beneficiaryUnitName: 'السرية الأولى',
        date: '2026-09-14',
        lines: [line(1, CylAction.returnEmpty)]));
    expect((await at(main)).empty, 2);
    expect(await custody('unit:u1'), 2);
    await consistent();

    // الموقف الإجمالي: ٨ + ٢ في المستودعين، و٤ عهدة = ١٥ اشتُريت − ١ استُهلكت.
    final p = await CylindersRepo(db).position();
    expect(p.totalFor(gas).total + p.custodyTotal(gas), 14);
  });

  test('الإرجاع التالف يُسقط من العهدة ولا يدخل الرصيد', () async {
    await ok(mv.saveReceipt(
        warehouse: main, supplier: 'م', date: '2026-09-01', lines: [line(3, CylAction.receiveFull)]));
    await ok(mv.saveIssue(
        warehouse: main, recipientDisplay: 'السرية الأولى', date: '2026-09-02', unitId: 'u1', lines: [line(3, CylAction.issueFull)]));
    await ok(mv.saveReturn(
        warehouse: main,
        party: 'السرية الأولى',
        beneficiaryUnitId: 'u1',
        condition: 'تالفة',
        date: '2026-09-03',
        lines: [line(1, CylAction.returnEmpty)]));
    expect(await custody('unit:u1'), 2);
    expect((await at(main)).total, 0);
    await consistent();
  });

  group('بيانات ما قبل تتبع الحالة', () {
    test('الافتتاحي بلا حالة، والصرف منه يُؤخذ من غير المسجّلة', () {
      final p = CylinderPosition.from(const [
        CylMove(kind: CylMoveKind.opening, itemId: 'g', warehouse: 'W', qty: 10),
        CylMove(kind: CylMoveKind.receipt, itemId: 'g', warehouse: 'W', qty: 2, action: CylAction.receiveFull),
        CylMove(kind: CylMoveKind.issue, itemId: 'g', warehouse: 'W', qty: 5, action: CylAction.issueFull),
      ]);
      final s = p.stock['g']!['W']!;
      expect((s.full, s.unknown, s.total), (0, 7, 7));
    });

    test('عودة من التعبئة بلا إرسال مسجّل تحوّل الفارغة', () {
      final p = CylinderPosition.from(const [
        CylMove(kind: CylMoveKind.receipt, itemId: 'g', warehouse: 'W', qty: 4, action: CylAction.receiveEmpty),
        CylMove(kind: CylMoveKind.receipt, itemId: 'g', warehouse: 'W', qty: 3, action: CylAction.refill),
      ]);
      final s = p.stock['g']!['W']!;
      expect((s.full, s.empty, s.total), (3, 1, 4));
    });

    test('المسودات والملغى لا تُحسب', () {
      final p = CylinderPosition.from(const [
        CylMove(kind: CylMoveKind.receipt, itemId: 'g', warehouse: 'W', qty: 4, action: CylAction.receiveFull),
        CylMove(
            kind: CylMoveKind.issue, itemId: 'g', warehouse: 'W', qty: 2, action: CylAction.issueFull, status: 'DRAFT'),
      ]);
      expect(p.stock['g']!['W']!.full, 4);
    });
  });

  test('نطاق المستخدم يحصر المستودعات المعروضة', () async {
    await ok(mv.saveReceipt(warehouse: main, supplier: 'م', date: '2026-09-01', lines: [line(3, CylAction.receiveFull)]));
    await ok(mv.saveReceipt(warehouse: branch, supplier: 'م', date: '2026-09-01', lines: [line(2, CylAction.receiveFull)]));
    final p = await CylindersRepo(db).position(scope: [branch]);
    expect(p.stock[gas]!.keys, [branch]);
  });

  test('الأعمدة الجديدة تُحفظ في التحويل والمرتجع', () async {
    await ok(mv.saveReceipt(warehouse: main, supplier: 'م', date: '2026-09-01', lines: [line(3, CylAction.receiveEmpty)]));
    await ok(mv.saveTransfer(
        fromWarehouse: main, toWarehouse: branch, date: '2026-09-02', lines: [line(1, CylAction.transferEmpty)]));
    expect((await db.select(db.transfers).getSingle()).cylinderAction, CylAction.transferEmpty);
    await db.into(db.returns).insert(ReturnsCompanion.insert(id: 'x', cylinderAction: const Value('RETURN_FULL')));
    expect((await db.select(db.returns).getSingle()).cylinderAction, 'RETURN_FULL');
  });
}
