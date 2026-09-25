import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/alerts_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/stock_forecast.dart';
import 'package:imdad/domain/strength.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime(2026, 9, 20);

  group('الحساب', () {
    test('الأيام الباقية وتاريخ النفاد من الصرف الفعلي', () {
      final f = StockForecasting.forecast(
        const [ForecastInput(itemId: 'rice', balance: 100, consumed: 300, windowDays: 30)],
        today,
      ).single;
      expect(f.actualDaily, 10);
      expect(f.daysLeft, 10);
      expect(f.stockoutDate, DateTime(2026, 9, 30));
      expect(f.fromPlan, isFalse);
    });

    test('المقرر الأكبر من الصرف يُعتمد للتحذير المبكر', () {
      final f = StockForecasting.forecast(
        const [ForecastInput(itemId: 'rice', balance: 100, consumed: 30, windowDays: 30, plannedDaily: 25)],
        today,
      ).single;
      expect(f.daily, 25);
      expect(f.fromPlan, isTrue);
      expect(f.daysLeft, 4);
    });

    test('بلا صرف ولا مقرر لا توقّع، والنافد يظهر أولًا', () {
      final out = StockForecasting.forecast(const [
        ForecastInput(itemId: 'idle', balance: 50, consumed: 0, windowDays: 30),
        ForecastInput(itemId: 'slow', balance: 90, consumed: 30, windowDays: 30),
        ForecastInput(itemId: 'gone', balance: 0, consumed: 30, windowDays: 30),
      ], today);
      expect([for (final f in out) f.itemId], ['gone', 'slow']);
      expect(out.first.daysLeft, 0);
    });

    test('الحاجة المقررة: (الشهري × معامل وحدته) ÷ ٣٠ × القوة', () {
      // كيس (٥٠ كجم) للفرد شهريًا، ٦٠ فردًا ⇒ ١٠٠ كجم يوميًا.
      expect(StockForecasting.plannedDaily(monthlyPerPerson: 1, measureFactor: 50, strength: 60), 100);
    });

    test('القوة الحالية = مجموع المعسكرات في آخر يوم حُصر', () {
      final calc = StrengthCalculator(
        records: const [
          StrengthRecord(unitId: 'c1', campId: 'c1', date: '2026-09-18', total: 100, mode: 'camp'),
          StrengthRecord(unitId: 'c1', campId: 'c1', date: '2026-09-19', total: 120, mode: 'camp'),
          StrengthRecord(unitId: 'c2', campId: 'c2', date: '2026-09-19', total: 80, mode: 'camp'),
          StrengthRecord(unitId: 'c1', campId: 'c1', date: '2026-09-25', total: 999, mode: 'camp'),
        ],
        units: const [UnitNode(id: 'c1', isCamp: true), UnitNode(id: 'c2', isCamp: true)],
      );
      expect(StockForecasting.currentStrength(calc, '2026-09-20'), 200, reason: 'يوم المستقبل لا يُحسب');
    });
  });

  group('AlertsRepo.forecast', () {
    late AppDatabase db;
    late MovementsRepo mv;
    late String rice;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      mv = MovementsRepo(db);
      final catalog = CatalogRepo(db);
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await catalog.saveWarehouse(code: 'W2', name: 'الفرعي');
      rice = await catalog.saveItem(
        code: 'R1',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
    });

    tearDown(() => db.close());

    DocLineInput line(double qty) =>
        DocLineInput(itemId: rice, itemCode: 'R1', itemName: 'أرز', unitName: 'كجم', factor: 1, qty: qty);

    Future<void> issue(String date, double qty, {String status = 'COMPLETED', String wh = 'الرئيسي'}) async {
      final r = await mv.saveIssue(warehouse: wh, recipientDisplay: 'س', date: date, lines: [line(qty)], status: status);
      expect(r.ok, isTrue, reason: r.error);
    }

    test('المسودات والأوامر وما خارج الفترة لا تُحسب استهلاكًا', () async {
      await mv.saveReceipt(warehouse: 'الرئيسي', supplier: 'م', date: '2026-07-01', lines: [line(1000)]);
      await issue('2026-07-15', 300); // خارج آخر ٣٠ يومًا
      await issue('2026-09-01', 150);
      await issue('2026-09-10', 150);
      await issue('2026-09-12', 500, status: 'DRAFT');
      await issue('2026-09-13', 500, status: 'ORDER');

      final f = (await AlertsRepo(db).forecast(today: today)).single;
      expect(f.actualDaily, 10, reason: '300 في 30 يومًا');
      expect(f.balance, 400);
      expect(f.daysLeft, 40);
    });

    test('نظام حديث: القسمة على عمره لا على الفترة كلها', () async {
      await mv.saveReceipt(warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-11', lines: [line(500)]);
      await issue('2026-09-11', 100);
      final f = (await AlertsRepo(db).forecast(today: today)).single;
      expect(f.actualDaily, 10, reason: '100 في 10 أيام، لا في 30');
    });

    test('المقرر مع القوة لمن نطاقه الكل، والصرف الفعلي وحده للنطاق المحدود', () async {
      await mv.saveReceipt(warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(600)]);
      await issue('2026-09-10', 30);
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp1',
            name: 'المعسكر',
            isCamp: const Value(true),
            type: const Value('camp'),
          ));
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 's1',
            unitId: 'camp1',
            campId: const Value('camp1'),
            strengthDate: '2026-09-19',
            total: const Value(300),
            mode: const Value('camp'),
          ));
      await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
            itemId: rice,
            qtyPerPerson: const Value(3), // ٣ كجم للفرد شهريًا ⇒ ٣٠ كجم يوميًا لـ٣٠٠ فرد
            measureUnitName: const Value('كجم'),
          ));

      final all = (await AlertsRepo(db).forecast(today: today)).single;
      expect(all.plannedDaily, 30);
      expect(all.fromPlan, isTrue);
      expect(all.daysLeft, 19);

      final scoped = (await AlertsRepo(db).forecast(scope: ['الرئيسي'], today: today)).single;
      expect(scoped.plannedDaily, isNull);
      expect(scoped.fromPlan, isFalse);
    });
  });
}
