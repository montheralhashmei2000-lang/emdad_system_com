import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/camp_ledger_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/domain/camp_ledger.dart';
import 'package:imdad/domain/main_warehouse.dart';
import 'package:imdad/domain/stock_alert.dart';
import 'package:imdad/domain/variance_tracker.dart';

/// سجل حساب المعسكر: الرصيدان، والانحراف، والتنبيه، والتصفية، وقيد المخزن
/// الرئيسي.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('معادلة الاستحقاق', () {
    test('المقرر شهري فيُقسم على ثلاثين قبل الضرب في مجموع القوى', () {
      // ٣٠ كجم شهريًا للفرد ⇒ ١ كجم يوميًا. قوة ١٠٠ لثلاثين يومًا ⇒ ٣٠٠٠ كجم.
      // ضربُ المقرر الشهري في مجموع القوى مباشرةً — كما يُكتب أحيانًا — يعطي
      // ٩٠٬٠٠٠ أي ثلاثين ضعفًا، فيصير كل معسكر دائنًا بأرقام خيالية.
      final v = CampLedgerCalc.entitlementOf(
        monthlyQtyPerPerson: 30,
        measureFactor: 1,
        strengthSum: 100 * 30,
      );
      expect(v, 3000);
    });

    test('وحدة القياس تُحوَّل إلى وحدة الأساس', () {
      // كيسان شهريًا والكيس ٤٠ كجم ⇒ ٨٠ كجم شهريًا ⇒ ٢٫٦٦٧ يوميًا.
      final v = CampLedgerCalc.entitlementOf(
        monthlyQtyPerPerson: 2,
        measureFactor: 40,
        strengthSum: 30,
      );
      expect(v, closeTo(80, 0.01));
    });

    test('المتوسط يُحسب من الأيام المسجّلة وحدها', () {
      expect(CampLedgerCalc.averageStrength([100, 100, 0]), 100);
      expect(CampLedgerCalc.averageStrength([]), 0);
    });
  });

  group('الرصيدان', () {
    test('رصيد الاستحقاق يقيس المُسلَّم لا المستهلك في المطبخ', () {
      // معسكر استحقاقه ١٠٠٠، سُلّم له ١٠٠٠، وطبخ ٤٠٠ فقط.
      // استحقاقه مطابق (أخذ حقه)، ومخزونه ٦٠٠. وقياس الاستحقاق بالمطبخ يجعله
      // دائنًا بـ٦٠٠ فيُطالَب بأن يستلم حقه مرتين.
      const a = LedgerAmounts(
        entitlementTotal: 1000,
        transferredIn: 1000,
        consumedKitchen: 400,
      );
      expect(a.delivered, 1000);
      expect(a.entitlementBalance, 0);
      expect(a.entitlementStatus, LedgerStatus.balanced);
      expect(a.stockBalance, 600);
    });

    test('المرتجع يخصم من المُسلَّم فيزيد رصيد الاستحقاق', () {
      const a = LedgerAmounts(
        entitlementTotal: 1000,
        transferredIn: 1000,
        returnedQty: 200,
      );
      expect(a.delivered, 800);
      expect(a.entitlementBalance, 200);
      expect(a.entitlementStatus, LedgerStatus.credit);
    });

    test('استلام أكثر من الاستحقاق يجعله مدينًا', () {
      const a = LedgerAmounts(entitlementTotal: 500, issuedDirect: 700);
      expect(a.entitlementBalance, -200);
      expect(a.entitlementStatus, LedgerStatus.debit);
    });

    test('المُرحَّل يدخل الرصيدين كلًّا من بابه', () {
      const a = LedgerAmounts(
        openingEntitled: 100,
        openingStock: 50,
        entitlementTotal: 1000,
        transferredIn: 900,
        consumedKitchen: 700,
      );
      expect(a.entitlementBalance, 200);
      expect(a.stockBalance, 250);
    });

    test('مخزون سالب يُعلَّم مستحيلًا', () {
      const a = LedgerAmounts(transferredIn: 100, consumedKitchen: 300);
      expect(a.stockImpossible, isTrue);
    });

    test('الإجماليات تفصل الدائن عن المدين', () {
      final t = CampLedgerCalc.totals(const [
        LedgerAmounts(entitlementTotal: 100),
        LedgerAmounts(entitlementTotal: 50, issuedDirect: 80),
      ]);
      expect(t.credit, 100);
      expect(t.debit, 30);
      expect(t.net, 70);
    });
  });

  group('الانحراف اليومي', () {
    test('القوة فوق المتوسط ⇒ له، ودونه ⇒ عليه', () {
      final s = VarianceTracker.series(
        strengthByDay: const {
          '2026-03-01': 100,
          '2026-03-02': 120,
          '2026-03-03': 80,
        },
        monthlyQtyPerPerson: 30, // ⇒ ١ كجم يوميًا
        measureFactor: 1,
      );
      expect(s, hasLength(3));
      expect(s[0].average, 100);
      expect(s[1].variance, 20);
      expect(s[1].isCredit, isTrue);
      expect(s[2].variance, -20);
      expect(s[2].isDebit, isTrue);
      expect(s.last.cumulative, 0, reason: 'الصافي يقارب الصفر بحكم التعريف');
    });

    test('الأيام غير المسجّلة لا تدخل السلسلة', () {
      final s = VarianceTracker.series(
        strengthByDay: const {'2026-03-01': 100, '2026-03-02': 0},
        monthlyQtyPerPerson: 30,
        measureFactor: 1,
      );
      expect(s, hasLength(1));
    });

    test('الخلاصة تُبرز الطرفين لا المجموع', () {
      final s = VarianceTracker.series(
        strengthByDay: const {
          '2026-03-01': 100,
          '2026-03-02': 200,
          '2026-03-03': 60,
        },
        monthlyQtyPerPerson: 30,
        measureFactor: 1,
      );
      final sum = VarianceTracker.summary(s);
      expect(sum.maxCredit!.date, '2026-03-02');
      expect(sum.maxDebit!.date, '2026-03-03');
    });
  });

  group('تنبيه المخزون', () {
    StockAlert alert({
      double current = 100,
      double min = 20,
      double rate = 10,
      int days = 2,
      double max = 200,
    }) =>
        StockAlert(
          campId: 'c1',
          campName: 'المعسكر',
          itemId: 'i1',
          itemName: 'رز',
          unitName: 'كجم',
          current: current,
          minStock: min,
          maxStock: max,
          dailyConsumption: rate,
          alertDaysBefore: days,
        );

    test('أيام الكفاية حتى الحد الأدنى لا حتى الصفر', () {
      expect(alert().daysLeft, 8);
    });

    test('بلوغ الحد الأدنى ⇒ صفر وحرج', () {
      final a = alert(current: 15);
      expect(a.daysLeft, 0);
      expect(a.level, AlertLevel.critical);
      expect(a.shouldAlert, isTrue);
    });

    test('بلا استهلاك مسجّل لا تُقدَّر الأيام', () {
      final a = alert(rate: 0);
      expect(a.daysLeft, isNull, reason: 'اللانهاية تتسرّب إلى الفرز والعرض');
      expect(a.level, AlertLevel.ok);
      expect(alert(rate: 0, current: 10).level, AlertLevel.critical);
    });

    test('المقترح يملأ إلى الحد الأعلى ولا يتجاوزه', () {
      expect(alert(current: 50, max: 200).suggestedTransfer, 150);
      expect(alert(current: 250, max: 200).suggestedTransfer, 0);
    });

    test('المعدل يُقسم على أيام الاستهلاك لا على طول النافذة', () {
      // صنف طُبخ يومين فقط: ٤٠ كجم في يومين ⇒ ٢٠ يوميًا لا ٥٫٧ (٤٠÷٧).
      final rate = StockAlertEngine.dailyConsumption(const [
        (date: '2026-03-01', baseQty: 20),
        (date: '2026-03-04', baseQty: 20),
      ]);
      expect(rate, 20);
    });

    test('الترتيب يضع الأحرج أولًا', () {
      final sorted = StockAlertEngine.sorted([
        alert(current: 100),
        alert(current: 10),
        alert(current: 25),
      ]);
      expect(sorted.first.level, AlertLevel.critical);
    });
  });

  group('قيد المخزن الرئيسي', () {
    const main = WarehouseRef(id: 'w1', name: 'الرئيسي', isMain: true);
    const other = WarehouseRef(id: 'w2', name: 'الفرعي');

    test('التحويل إلى معسكر من غير الرئيسي يُمنع', () {
      final e = MainWarehouse.validate(
        fromWarehouse: 'الفرعي',
        destWarehouse: 'معسكر أ',
        toCamp: true,
        warehouses: const [main, other],
      );
      expect(e, isNotNull);
      expect(e, contains('الرئيسي'));
    });

    test('من الرئيسي مسموح', () {
      expect(
        MainWarehouse.validate(
          fromWarehouse: 'الرئيسي',
          destWarehouse: 'معسكر أ',
          toCamp: true,
          warehouses: const [main, other],
        ),
        isNull,
      );
    });

    test('التحويل بين مخزنين عاديين لا يخضع للقيد', () {
      expect(
        MainWarehouse.validate(
          fromWarehouse: 'الفرعي',
          destWarehouse: 'مخزن ثالث',
          toCamp: false,
          warehouses: const [main, other],
        ),
        isNull,
      );
    });

    test('بلا مخزن رئيسي معيَّن لا يتوقف الميدان', () {
      // المنع لغياب إعداد لم يضبطه أحد يوقف العمل بلا ذنب.
      expect(
        MainWarehouse.validate(
          fromWarehouse: 'الفرعي',
          destWarehouse: 'معسكر أ',
          toCamp: true,
          warehouses: const [other],
        ),
        isNull,
      );
    });

    test('القيد مفروض في طبقة الحفظ لا في الشاشة وحدها', () async {
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(id: 'w1', name: 'الرئيسي', isMain: const Value(true)),
          );
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(id: 'w2', name: 'الفرعي'),
          );
      final res = await MovementsRepo(db).saveTransfer(
        fromWarehouse: 'الفرعي',
        toWarehouse: 'معسكر أ',
        date: '2026-03-01',
        campId: 'camp-1',
        lines: const [
          DocLineInput(
            itemId: 'i1',
            itemCode: 'X1',
            itemName: 'رز',
            unitName: 'كجم',
            factor: 1,
            qty: 10,
          ),
        ],
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('الرئيسي'));
    });
  });

  group('المخزن الرئيسي واحد', () {
    test('تعيين مخزن رئيسيًا يُلغي السابق', () async {
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(id: 'w1', name: 'أ', isMain: const Value(true)),
          );
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(id: 'w2', name: 'ب'));

      final repo = CampLedgerRepo(db);
      await repo.setMainWarehouse('w2');

      final mains = (await db.select(db.warehouses).get()).where((w) => w.isMain).toList();
      expect(mains, hasLength(1));
      expect(mains.single.id, 'w2');
      expect((await repo.mainWarehouse())!.name, 'ب');
    });
  });

  group('بناء السجل والتصفية', () {
    Future<void> seed() async {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp1',
            name: 'معسكر الأول',
            type: const Value('camp'),
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
            itemName: Value(item.name),
            qtyPerPerson: const Value(30), // ⇒ ١ كجم يوميًا
            measureFactor: const Value(1),
          ));
      // تفريدة يومين بقوة ١٠٠.
      for (final d in ['2026-01-01', '2026-01-02']) {
        await db.into(db.strengths).insert(StrengthsCompanion.insert(
              id: 'st-$d',
              unitId: 'camp1',
              campId: const Value('camp1'),
              strengthDate: d,
              total: const Value(100),
            ));
      }
    }

    test('السجل يُبنى من المصادر بالمعادلة الصحيحة', () async {
      await seed();
      final repo = CampLedgerRepo(db);
      final n = await repo.rebuild(year: 2026, month: 1);
      expect(n, 1);

      final rows = await repo.ledgers(year: 2026, month: 1);
      expect(rows.single.amounts.entitlementTotal, 200,
          reason: 'يومان × ١٠٠ فرد × ١ كجم');
      expect(rows.single.ledger.strengthDays, 2);
      expect(rows.single.amounts.entitlementStatus, LedgerStatus.credit);
    });

    test('لا يُصفّى شهر لم ينتهِ', () async {
      await seed();
      final now = DateTime.now();
      final res = await CampLedgerRepo(db).closeMonth(year: now.year, month: now.month);
      expect(res.ok, isFalse);
      expect(res.error, contains('لم ينتهِ'));
    });

    test('التصفية تُغلق الشهر وتُرحّل رصيديه', () async {
      await seed();
      final repo = CampLedgerRepo(db);
      await repo.rebuild(year: 2026, month: 1);
      final res = await repo.closeMonth(year: 2026, month: 1, actor: 'admin');

      expect(res.ok, isTrue, reason: res.error);
      expect(res.nextMonth, 2);

      final closed = await repo.ledgers(year: 2026, month: 1);
      expect(closed.single.ledger.status, 'CLOSED');

      final next = await repo.ledgers(year: 2026, month: 2);
      expect(next.single.amounts.openingEntitled, 200,
          reason: 'لم يُرحَّل رصيد الاستحقاق');
    });

    test('لا تُصفّى مرتين', () async {
      await seed();
      final repo = CampLedgerRepo(db);
      await repo.rebuild(year: 2026, month: 1);
      await repo.closeMonth(year: 2026, month: 1);
      final again = await repo.closeMonth(year: 2026, month: 1);
      expect(again.ok, isFalse);
      expect(again.error, contains('مُصفّى'));
    });

    test('الشهر المُغلق لا يُعاد بناؤه', () async {
      await seed();
      final repo = CampLedgerRepo(db);
      await repo.rebuild(year: 2026, month: 1);
      await repo.closeMonth(year: 2026, month: 1);

      // تفريدة إضافية بأثر رجعي: لو أُعيد البناء لتبدّل أساس الشهر التالي.
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 'st-extra',
            unitId: 'camp1',
            campId: const Value('camp1'),
            strengthDate: '2026-01-03',
            total: const Value(100),
          ));
      await repo.rebuild(year: 2026, month: 1);

      final rows = await repo.ledgers(year: 2026, month: 1);
      expect(rows.single.amounts.entitlementTotal, 200,
          reason: 'تغيّر شهر مُصفّى فانكسرت سلسلة الترحيل');
    });

    test('سطر بلا حركة ولا استحقاق لا يُنشأ', () async {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp2',
            name: 'معسكر بلا نشاط',
            isCamp: const Value(true),
          ));
      await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
            itemId: 'ghost',
            qtyPerPerson: const Value(30),
          ));
      final n = await CampLedgerRepo(db).rebuild(year: 2026, month: 5);
      expect(n, 0, reason: 'امتلأ الجدول بأصفار لا تُقرأ');
    });
  });

  group('نسبة المرتجع إلى وحدته', () {
    test('بالمعرّف ولو اختلف إملاء الاسم', () async {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp1',
            name: 'معسكر الأول',
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
            strengthDate: '2026-04-01',
            total: const Value(100),
          ));
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(id: 'wh1', name: 'الرئيسي'),
          );
      await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: 'ob1',
            itemId: item.id,
            warehouse: const Value('الرئيسي'),
            qty: const Value(1000),
          ));

      await MovementsRepo(db).saveReturn(
        warehouse: 'الرئيسي',
        // الاسم مختلف الإملاء عمدًا — الربط بالمعرّف.
        party: 'معسكرالاول',
        beneficiaryUnitId: 'camp1',
        beneficiaryUnitName: 'معسكر الأول',
        date: '2026-04-05',
        lines: [
          DocLineInput(
            itemId: item.id,
            itemCode: 'X1',
            itemName: 'رز',
            unitName: 'كجم',
            factor: 1,
            qty: 40,
          ),
        ],
      );

      await CampLedgerRepo(db).rebuild(year: 2026, month: 4);
      final rows = await CampLedgerRepo(db).ledgers(year: 2026, month: 4);
      expect(rows.single.amounts.returnedQty, 40,
          reason: 'سقط المرتجع لاختلاف الإملاء — والربط يجب أن يكون بالمعرّف');
    });

    test('سطر قديم بلا معرّف يُنسب بالاسم', () async {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp1',
            name: 'معسكر الأول',
            isCamp: const Value(true),
          ));
      await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
            itemId: 'i1',
            qtyPerPerson: const Value(30),
          ));
      // سطر كُتب قبل عمود المعرّف (v11).
      await db.into(db.returns).insert(ReturnsCompanion.insert(
            id: 're-old',
            date: const Value('2026-04-05'),
            itemId: const Value('i1'),
            baseQty: const Value(25),
            party: const Value('معسكر الأول'),
            type: const Value('FROM_UNIT'),
          ));

      await CampLedgerRepo(db).rebuild(year: 2026, month: 4);
      final rows = await CampLedgerRepo(db).ledgers(year: 2026, month: 4);
      expect(rows.single.amounts.returnedQty, 25,
          reason: 'انكسر التوافق مع السطور السابقة للعمود');
    });
  });

  group('المزامنة', () {
    test('الجداول الثلاثة مسجّلة', () {
      for (final t in ['camp_ledgers', 'camp_stock_limits', 'monthly_settlements']) {
        expect(SyncMarks.entities.containsKey(t), isTrue, reason: '$t خارج المزامنة');
      }
    });
  });
}
