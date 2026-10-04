import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/domain/custody_sheet.dart';
import 'package:imdad/domain/finance.dart';
import 'package:imdad/features/linkages/clearance_form.dart';
import 'package:imdad/features/linkages/custody_sheet_editor.dart';
import 'package:imdad/features/linkages/finance_statement.dart';
import 'package:imdad/features/linkages/custody_form.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// المرحلة 1 من النظام المالي: العهدة (الأرقام، المنع، التحويل، الترحيل، النموذج).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('قواعد نقية', () {
    test('التحويل بين العملتين بسعر الصرف، وبلا سعرٍ لا يُخمَّن', () {
      expect(convertAmount(4100, from: 'yer', to: 'sar', rate: 410), 10);
      expect(convertAmount(10, from: 'sar', to: 'yer', rate: 410), 4100);
      expect(convertAmount(5, from: 'sar', to: 'sar', rate: 0), 5);
      expect(convertAmount(5, from: 'yer', to: 'sar', rate: 0), isNull);
    });

    test('إجماليات المسير بعملته: اليمني يقرأ عمود العهدة اليمني وحوّل بسعر السطر', () {
      const rows = [
        CustodyRowValues(grantYer: 100000, spentYer: 41000, rate: 400),
        CustodyRowValues(spentSar: 10, rate: 400), // 10 سعودي = 4000 يمني
      ];
      final y = custodyTotalsIn(rows, 'yer');
      expect((y.granted, y.spent, y.remaining), (100000, 45000, 55000));
      final s = custodyTotalsIn(rows, 'sar');
      expect(s.granted, 0, reason: 'لا خلط بين العمودين');
      expect(s.spent, closeTo(112.5, 0.001), reason: '41000÷400 + 10');
      // سعرٌ غير صالح لا يُخمَّن: السعودي لا يُحوَّل إلى يمني.
      expect(const CustodyRowValues(spentSar: 10, rate: 0).spentIn('yer'), 0);
    });

    test('الفرق: مطابق وفائض وعجز وصياغته بحسب نوع العهدة', () {
      expect(CustodyDiff.of(granted: 100, spent: 100).type, CustodyOutcome.matched);
      expect(CustodyDiff.of(granted: 100, spent: 100.001).type, CustodyOutcome.matched, reason: 'تقريب');
      final sur = CustodyDiff.of(granted: 100, spent: 60);
      expect((sur.type, sur.amount), (CustodyOutcome.surplus, 40));
      final def = CustodyDiff.of(granted: 100, spent: 130);
      expect((def.type, def.amount), (CustodyOutcome.deficit, 30));

      expect(sur.phrase(custodyKind: CustodyKind.received), 'متبقٍّ لك عند المالية');
      expect(def.phrase(custodyKind: CustodyKind.received), 'متبقٍّ عليك للمالية');
      expect(sur.phrase(custodyKind: CustodyKind.delivered, counterparty: 'أحمد'), 'متبقٍّ لي عند أحمد');
      expect(def.phrase(custodyKind: CustodyKind.delivered, counterparty: 'أحمد'), 'متبقٍّ على أحمد لي');
    });
  });

  group('المستودع', () {
    late AppDatabase db;
    late LinkageRepo repo;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LinkageRepo(db);
    });
    tearDown(() => db.close());

    LinkFinCustodiesCompanion custody(String id, {String no = '', double amount = 1000, String cur = 'sar', double rate = 0}) =>
        LinkFinCustodiesCompanion(
          id: Value(id),
          custodyNo: Value(no),
          title: const Value('شراء مواد'),
          amount: Value(amount),
          currency: Value(cur),
          exchangeRate: Value(rate),
        );

    Future<LinkFinCustody> byId(String id) async => (await repo.custodies()).firstWhere((c) => c.id == id);

    test('الرقم الفارغ يُولَّد بالتسلسل، والمكرر يُرفض', () async {
      await repo.insertCustody(custody('a'));
      await repo.insertCustody(custody('b'));
      expect((await byId('a')).custodyNo, 'عهدة-00001');
      expect((await byId('b')).custodyNo, 'عهدة-00002');
      expect(await repo.nextCustodyNo(), 'عهدة-00003');

      await repo.insertCustody(custody('c', no: 'خاص-7'));
      expect((await byId('c')).custodyNo, 'خاص-7');
      await expectLater(() => repo.insertCustody(custody('d', no: ' خاص-7 ')), throwsA(isA<LinkBlocked>()));
      // التعديل إلى رقم عهدةٍ أخرى يُرفض، وإلى رقمها هي مسموح.
      final a = await byId('a');
      await expectLater(() => repo.updateCustody(a, const LinkFinCustodiesCompanion(custodyNo: Value('خاص-7'))), throwsA(isA<LinkBlocked>()));
      await repo.updateCustody(a, const LinkFinCustodiesCompanion(custodyNo: Value('عهدة-00001')));
    });

    test('الحذف يُمنع مع عقدٍ أو مسيرٍ أو إخلاء، ويجوز بدونها', () async {
      await repo.insertCustody(custody('x'));
      await repo.insertCustody(custody('y'));
      await repo.insertCustody(custody('z'));
      await repo.insertContract(const LinkPurchaseContractsCompanion(id: Value('k1'), title: Value('ت'), custodyId: Value('x')));
      await db.into(db.linkCustodySheets).insert(const LinkCustodySheetsCompanion(id: Value('s1'), custodyId: Value('y')));

      expect((await repo.custodyLinks('x')), ['1 عقد']);
      await expectLater(() async => repo.deleteCustody(await byId('x')), throwsA(isA<LinkBlocked>()));
      await expectLater(() async => repo.deleteCustody(await byId('y')), throwsA(isA<LinkBlocked>()));

      await repo.deleteCustody(await byId('z'));
      expect((await repo.custodies()).map((c) => c.id), isNot(contains('z')));
    });

    test('العهدة المُخلَّاة لا يتغير مبلغها ولا تُلغى', () async {
      await repo.insertCustody(custody('q'));
      await (db.update(db.linkFinCustodies)..where((t) => t.id.equals('q')))
          .write(const LinkFinCustodiesCompanion(status: Value(CustodyStatus.cleared), cleared: Value(true)));
      final q = await byId('q');
      await expectLater(() => repo.updateCustody(q, const LinkFinCustodiesCompanion(amount: Value(5))), throwsA(isA<LinkBlocked>()));
      await expectLater(() => repo.updateCustody(q, const LinkFinCustodiesCompanion(status: Value(CustodyStatus.canceled))), throwsA(isA<LinkBlocked>()));
    });

    test('المستهلك = مجموع العقود المرتبطة بعملة العهدة', () async {
      await repo.insertCustody(custody('u', amount: 1000, cur: 'sar'));
      await repo.insertCustody(custody('v', amount: 500000, cur: 'yer', rate: 400));
      Future<void> contract(String id, String cust, String cur, double amount, double rate) => repo.insertContract(LinkPurchaseContractsCompanion(
            id: Value(id),
            title: const Value('ت'),
            custodyId: Value(cust),
            currency: Value(cur),
            amount: Value(amount),
            exchangeRate: Value(rate),
          ));
      await contract('c1', 'u', 'sar', 100, 0);
      await contract('c2', 'u', 'yer', 41000, 410); // = 100 سعودي
      await contract('c3', 'u', 'yer', 999, 0); // بلا سعر: لا يُخمَّن
      await contract('c4', 'v', 'sar', 10, 0); // سعودي إلى يمني بسعر العهدة 400 = 4000

      final usage = await repo.custodyUsage();
      expect(usage['u']!.consumed, 200);
      expect(usage['u']!.contracts, 3);
      expect(usage['u']!.unconvertible, 1);
      expect(usage['v']!.consumed, 4000);
    });

    test('ربط العقد بعهدة: قيد الإخلاء فقط، وعقد واحد لعهدة واحدة', () async {
      await repo.insertCustody(custody('a'));
      await repo.insertCustody(custody('b'));
      await (db.update(db.linkFinCustodies)..where((t) => t.id.equals('b')))
          .write(const LinkFinCustodiesCompanion(status: Value(CustodyStatus.cleared), cleared: Value(true)));

      LinkPurchaseContractsCompanion k(String id, String cust) =>
          LinkPurchaseContractsCompanion(id: Value(id), title: const Value('ت'), contractNo: Value('K-$id'), custodyId: Value(cust), amount: const Value(100));
      await repo.insertContract(k('k1', 'a'));
      expect((await repo.contractsOfCustody('a')).map((c) => c.id), ['k1']);
      await expectLater(() => repo.insertContract(k('k2', 'b')), throwsA(isA<LinkBlocked>()), reason: 'مُخلَّاة');
      await expectLater(() => repo.insertContract(k('k3', 'nope')), throwsA(isA<LinkBlocked>()), reason: 'غير موجودة');

      // نقل العقد من عهدةٍ إلى أخرى: يتبع الحقل المفرد فلا يكون في عهدتين.
      await repo.insertCustody(custody('c'));
      final k1 = (await repo.contracts()).firstWhere((x) => x.id == 'k1');
      await repo.updateContract(k1, const LinkPurchaseContractsCompanion(custodyId: Value('c')));
      expect(await repo.contractsOfCustody('a'), isEmpty);
      expect((await repo.contractsOfCustody('c')).length, 1);
      // الاستعمال مسجَّل في التدقيق.
      final logs = await db.select(db.auditLogs).get();
      expect(logs.where((l) => l.action == 'linkage.custody.contract_linked').length, 2);
    });

    test('عقدٌ مرتبط بعهدة مُخلَّاة لا يتغير مبلغه ولا يُحذف', () async {
      await repo.insertCustody(custody('a'));
      await repo.insertContract(const LinkPurchaseContractsCompanion(id: Value('k'), title: Value('ت'), custodyId: Value('a'), amount: Value(50)));
      await (db.update(db.linkFinCustodies)..where((t) => t.id.equals('a')))
          .write(const LinkFinCustodiesCompanion(status: Value(CustodyStatus.cleared), cleared: Value(true)));
      final k = (await repo.contracts()).single;
      await expectLater(() => repo.updateContract(k, const LinkPurchaseContractsCompanion(amount: Value(60))), throwsA(isA<LinkBlocked>()));
      await expectLater(() => repo.deleteContract(k), throwsA(isA<LinkBlocked>()));
      // تعديل غير مالي (ملاحظات) مسموح.
      await repo.updateContract(k, const LinkPurchaseContractsCompanion(notes: Value('ملاحظة')));
    });

    test('المسير يخص عهدةً قيد الإخلاء، وتعديل عقده يحدّث سطره ما لم يُعدَّل يدويًّا', () async {
      await repo.insertCustody(custody('a', amount: 100000, cur: 'yer', rate: 400));
      await repo.insertContract(const LinkPurchaseContractsCompanion(
        id: Value('k'),
        title: Value('بهارات'),
        supplier: Value('الوكيل'),
        currency: Value('yer'),
        exchangeRate: Value(400),
        listDate: Value('2026-10-01'),
        invoiceNo: Value('INV-1'),
        amount: Value(40000),
        custodyId: Value('a'),
      ));
      LinkCustodySheetRowsCompanion row({required double spentYer, String shop = 'الوكيل', String category = 'بهارات'}) => LinkCustodySheetRowsCompanion(
            date: const Value('2026-10-01'),
            invoiceNo: const Value('inv-1'),
            category: Value(category),
            shop: Value(shop),
            spentYer: Value(spentYer),
            spentSar: Value(spentYer / 400),
            rate: const Value(400),
          );
      final id = await repo.saveCustodySheet(
          sheetNo: 'عهدة-00001', title: 'سالم', defaultRate: 400, notes: '', custodyId: 'a', currency: 'yer', holderName: 'سالم', rows: [row(spentYer: 40000)]);
      var k = (await repo.contracts()).single;
      await repo.updateContract(k, const LinkPurchaseContractsCompanion(amount: Value(50000), supplier: Value('الوكيل الجديد')));
      var r = (await repo.sheetRows(id)).single;
      expect((r.spentYer, r.spentSar, r.shop), (50000, 125, 'الوكيل الجديد'), reason: 'سطر لم يُعدَّل يتبع العقد');

      // سطرٌ عدّله المستخدم يدويًّا (المحل) لا يُكتب فوقه.
      await repo.saveCustodySheet(
          id: id, sheetNo: 'عهدة-00001', title: 'سالم', defaultRate: 400, notes: '', custodyId: 'a', currency: 'yer', holderName: 'سالم', rows: [row(spentYer: 50000, shop: 'محل آخر')]);
      k = (await repo.contracts()).single;
      await repo.updateContract(k, const LinkPurchaseContractsCompanion(amount: Value(60000)));
      r = (await repo.sheetRows(id)).single;
      expect((r.spentYer, r.shop), (50000, 'محل آخر'));

      // العهدة المُخلَّاة تجمّد مسيرها.
      await (db.update(db.linkFinCustodies)..where((t) => t.id.equals('a')))
          .write(const LinkFinCustodiesCompanion(status: Value(CustodyStatus.cleared), cleared: Value(true)));
      final sheet = (await repo.custodySheets()).single;
      await expectLater(() => repo.deleteCustodySheet(sheet), throwsA(isA<LinkBlocked>()));
      expect(
          () => repo.saveCustodySheet(id: id, sheetNo: 'x', title: '', defaultRate: 400, notes: '', custodyId: 'a', currency: 'yer', rows: []),
          throwsA(isA<LinkBlocked>()));
      // ولا يُفتح مسير جديد لعهدة مُخلَّاة.
      expect(
          () => repo.saveCustodySheet(sheetNo: 'y', title: '', defaultRate: 400, notes: '', custodyId: 'a', currency: 'yer', rows: []),
          throwsA(isA<LinkBlocked>()));
    });

    Future<void> sheet(String custodyId, String cur, {double spentSar = 0, double spentYer = 0, double returnSar = 0, double rate = 400}) =>
        repo.saveCustodySheet(
          sheetNo: 'S-$custodyId',
          title: 't',
          defaultRate: rate,
          notes: '',
          custodyId: custodyId,
          currency: cur,
          rows: [LinkCustodySheetRowsCompanion(spentSar: Value(spentSar), spentYer: Value(spentYer), returnSar: Value(returnSar), rate: Value(rate))],
        );

    test('دورة الإخلاء: مسودة لا تُغلق، الاعتماد يُغلق ويكتب الدفتر، والحذف يعكس', () async {
      await repo.insertCustody(custody('a', amount: 1000).copyWith(receiverName: const Value('سالم'), giverName: const Value('المالية')));
      await sheet('a', 'sar', spentSar: 600);
      final st = (await repo.custodySettlement('a'))!;
      expect((st.granted, st.spent, st.diff.type, st.diff.amount), (1000, 600, CustodyOutcome.surplus, 400));
      expect(st.diff.phrase(custodyKind: CustodyKind.received), 'متبقٍّ لك عند المالية');

      // مسودة: لا تُغلق العهدة ولا تكتب الدفتر.
      var cl = await repo.saveCustodyClearance(custodyId: 'a', clearanceDate: '2026-10-05', workflow: LinkageRepo.wfDraft);
      expect(cl.clearanceNo, matches(RegExp(r'^إخلاء-[A-Z0-9]{4}-\d{6}-00001$')));
      expect((cl.grantedAmount, cl.spentAmount, cl.diffType, cl.surplusAmount), (1000, 600, CustodyOutcome.surplus, 400));
      expect((await byId('a')).status, CustodyStatus.open);
      expect(await db.select(db.linkFinanceLedger).get(), isEmpty);

      // إخلاءٌ ثانٍ للعهدة نفسها مرفوض.
      await expectLater(() => repo.saveCustodyClearance(custodyId: 'a', clearanceDate: '2026-10-05'), throwsA(isA<LinkBlocked>()));

      // الاعتماد: العهدة «تم الإخلاء» بنتيجة فائض، والدفتر +400 لصاحبها.
      cl = await repo.saveCustodyClearance(id: cl.id, custodyId: 'a', clearanceDate: '2026-10-06', workflow: LinkageRepo.wfApproved, docNo: 'ص-77');
      final a = await byId('a');
      expect((a.status, a.cleared, a.outcome, a.outcomeAmount, a.clearedDate), (CustodyStatus.cleared, true, CustodyOutcome.surplus, 400, '2026-10-06'));
      var ledger = await db.select(db.linkFinanceLedger).get();
      expect((ledger.single.partyName, ledger.single.delta, ledger.single.entryKind), ('سالم', 400, 'surplus'));
      expect((await repo.partyBalances())['سالم'], {'sar': 400});

      // المُعتمد لا يعود مسودة، وأرقامه مجمَّدة ولو تغيّر المسير بعده.
      await expectLater(() => repo.saveCustodyClearance(id: cl.id, custodyId: 'a', clearanceDate: '2026-10-06', workflow: LinkageRepo.wfDraft), throwsA(isA<LinkBlocked>()));
      await expectLater(() => sheet('a', 'sar', spentSar: 900), throwsA(isA<LinkBlocked>()), reason: 'المسير مجمَّد');
      await repo.saveCustodyClearance(id: cl.id, custodyId: 'a', clearanceDate: '2026-10-06', workflow: LinkageRepo.wfApproved, adminNotes: 'روجع');
      cl = (await repo.clearances()).single;
      expect((cl.spentAmount, cl.adminNotes), (600, 'روجع'));

      // حذف الإخلاء: تُعاد فتح العهدة ويُعكس القيد بقيدٍ مضاد (الأثر باقٍ).
      await repo.deleteClearance(cl);
      expect((await byId('a')).status, CustodyStatus.open);
      expect((await byId('a')).outcome, '');
      ledger = await db.select(db.linkFinanceLedger).get();
      expect(ledger.map((e) => e.delta).fold<double>(0, (x, y) => x + y), 0);
      expect(ledger.map((e) => e.entryKind).toSet(), {'surplus', 'reversal'});
      expect((await repo.partyBalances())['سالم'], {'sar': -1000 + 0}, reason: 'العهدة المستلمة قائمة من جديد: مدين');
    });

    test('عجز في عهدة مسلَّمة يمنية: قيد سالب على المستلم وصياغة الطرف المقابل', () async {
      await repo.insertCustody(custody('d', amount: 100000, cur: 'yer', rate: 400)
          .copyWith(kind: const Value(CustodyKind.delivered), giverName: const Value('أنا'), receiverName: const Value('أحمد')));
      await sheet('d', 'yer', spentYer: 130000);
      final st = (await repo.custodySettlement('d'))!;
      expect((st.diff.type, st.diff.amount, st.counterparty), (CustodyOutcome.deficit, 30000, 'أحمد'));
      expect(st.diff.phrase(custodyKind: CustodyKind.delivered, counterparty: st.counterparty), 'متبقٍّ على أحمد لي');
      final cl = await repo.saveCustodyClearance(custodyId: 'd', clearanceDate: '2026-10-05');
      expect((cl.deficitAmount, cl.surplusAmount, cl.counterpartyName, cl.currency), (30000, 0, 'أحمد', 'yer'));
      final stmt = await repo.partyStatement('أحمد');
      expect(stmt.balance, {'yer': -30000});
      expect(stmt.lines.single.kind, 'deficit');
    });

    test('مطابق لا يكتب قيدًا، والمرتجع يُخصم من الفرق، والعهد القائمة تدخل الرصيد', () async {
      await repo.insertCustody(custody('m', amount: 500).copyWith(receiverName: const Value('خالد')));
      await sheet('m', 'sar', spentSar: 400, returnSar: 100);
      final st = (await repo.custodySettlement('m'))!;
      expect((st.spent, st.returned, st.diff.type), (400, 100, CustodyOutcome.matched));
      await repo.saveCustodyClearance(custodyId: 'm', clearanceDate: '2026-10-05');
      expect(await db.select(db.linkFinanceLedger).get(), isEmpty);
      expect((await byId('m')).outcome, CustodyOutcome.matched);

      // عهدة مسلَّمة قائمة: دائن، ومستلمة قائمة: مدين.
      await repo.insertCustody(custody('p', amount: 200).copyWith(kind: const Value(CustodyKind.delivered), receiverName: const Value('خالد')));
      await repo.insertCustody(custody('q', amount: 50).copyWith(receiverName: const Value('خالد')));
      expect((await repo.partyBalances())['خالد'], {'sar': 150});
    });

    test('مسودة إخلاء لعهدة أُلغيت بعدها لا تُعتمد', () async {
      await repo.insertCustody(custody('x'));
      final cl = await repo.saveCustodyClearance(custodyId: 'x', clearanceDate: '2026-10-05', workflow: LinkageRepo.wfDraft);
      await repo.updateCustody(await byId('x'), const LinkFinCustodiesCompanion(status: Value(CustodyStatus.canceled)));
      await expectLater(
          () => repo.saveCustodyClearance(id: cl.id, custodyId: 'x', clearanceDate: '2026-10-06', workflow: LinkageRepo.wfApproved), throwsA(isA<LinkBlocked>()));
      expect((await byId('x')).status, CustodyStatus.canceled);
      expect(await db.select(db.linkFinanceLedger).get(), isEmpty);
    });

    test('تعارض المزامنة: إخلاءان للعهدة نفسها يُكشفان', () async {
      await repo.insertCustody(custody('z'));
      await repo.saveCustodyClearance(custodyId: 'z', clearanceDate: '2026-10-05', workflow: LinkageRepo.wfDraft);
      // يحاكي وصول إخلاء ثانٍ من جهاز آخر عبر المزامنة (لا يمرّ بالمنع المحلي).
      await db.into(db.linkClearances).insert(const LinkClearancesCompanion(
          id: Value('remote'), kind: Value(LinkClearanceKind.custody), refId: Value('z'), clearanceNo: Value('إخلاء-ABCD-202610-00009')));
      final dups = await repo.duplicateClearances();
      expect(dups.keys, ['z']);
      expect(dups['z']!.length, 2);
    });

    test('ترحيل العهد القديمة: الحالة والمبلغ والجهة، بلا فقد', () async {
      // صفوف بصيغة ما قبل v24: الأعمدة الجديدة بقيمها الافتراضية.
      await db.customStatement(
          "INSERT INTO link_fin_custodies (id, custody_no, holder, title, value_amount, cleared, cleared_date) VALUES ('o1','5','المطبخ','مطبخ ميداني',750,1,'2026-01-01')");
      await db.customStatement("INSERT INTO link_fin_custodies (id, custody_no, holder, title, value_amount) VALUES ('o2','6','',  'بلا جهة',0)");
      await db.backfillFinance();
      final o1 = await byId('o1');
      expect(o1.status, CustodyStatus.cleared);
      expect(o1.amount, 750);
      expect(o1.kind, CustodyKind.delivered);
      expect(o1.receiverName, 'المطبخ');
      expect(o1.holder, 'المطبخ', reason: 'الحقل القديم باقٍ');
      expect(o1.valueAmount, 750);
      final o2 = await byId('o2');
      expect(o2.status, CustodyStatus.open);
      expect(o2.kind, CustodyKind.received);
    });
  });

  group('النموذج', () {
    late AppDatabase db;
    late AuthService auth;

    Future<void> pump(WidgetTester tester, Widget form, Size size, {Future<void> Function(AppDatabase)? seed}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db.close());
      auth = AuthService(db);
      if (seed != null) await tester.runAsync(() => seed(db));
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SafeArea(child: SingleChildScrollView(child: form)))),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final size in const [Size(1280, 800), Size(360, 740), Size(320, 568)]) {
      testWidgets('نموذج العهدة بلا فيض ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await pump(tester, const CustodyForm(names: ['أحمد'], initial: null, actor: 'a', userName: 'سالم'), size);
        expect(tester.takeException(), isNull);
        expect(find.text('حفظ العهدة'), findsOneWidget);
      });
    }

    testWidgets('محرر المسير: عهدة يمنية، سحب عقدها، فتح السطر التالي، وتحديث المتبقي', (tester) async {
      final sheet = LinkCustodySheet(
        id: 's1',
        sheetNo: 'عهدة-00001',
        title: 'سالم',
        custodyId: 'a',
        currency: 'yer',
        holderName: 'سالم',
        defaultRate: 400,
        notes: '',
        createdBy: '',
        createdAt: DateTime(2026),
      );
      const row = LinkCustodySheetRow(
        id: 'r1', sheetId: 's1', seq: 0, date: '', grantSar: 0, grantYer: 100000, returnSar: 0, returnYer: 0, spentSar: 0, spentYer: 0, rate: 400,
        person: '', statement: '', category: '', entryNo: '', invoiceNo: '', shop: '', notes: '',
      );
      await pump(
        tester,
        CustodySheetEditor(initial: sheet, initialRows: const [row], actor: 'a', canPrint: false),
        const Size(1500, 900),
        seed: (db) async {
          final repo = LinkageRepo(db);
          await repo.insertCustody(const LinkFinCustodiesCompanion(
              id: Value('a'), title: Value('شراء'), amount: Value(100000), currency: Value('yer'), exchangeRate: Value(400)));
          await repo.insertContract(const LinkPurchaseContractsCompanion(
            id: Value('k'), title: Value('بهارات'), supplier: Value('الوكيل'), currency: Value('yer'), exchangeRate: Value(400),
            listDate: Value('2026-10-01'), invoiceNo: Value('INV-1'), amount: Value(41000), custodyId: Value('a'),
          ));
          // عقدٌ لعهدةٍ أخرى: يُرفض سحبه إلى هذا المسير.
          await repo.insertCustody(const LinkFinCustodiesCompanion(id: Value('b'), title: Value('أخرى'), amount: Value(5)));
          await repo.insertContract(const LinkPurchaseContractsCompanion(
              id: Value('k2'), title: Value('غيره'), invoiceNo: Value('OTHER-9'), amount: Value(10), custodyId: Value('b')));
        },
      );
      await tester.pump(const Duration(milliseconds: 300));
      final before = find.byType(TextField).evaluate().length;
      String t(int i) => (tester.widget(find.byType(TextField).at(i)) as TextField).controller!.text;
      // السطر الأول (المبلغ 100000) + سطر فارغ تالٍ؛ رقم الفاتورة في السطر الثاني = 14+13.
      await tester.enterText(find.byType(TextField).at(27), 'inv-1');
      await tester.pump();
      expect(t(21), '41000', reason: 'المنصرف يمني من العقد');
      expect(find.byType(TextField).evaluate().length, before + 13, reason: 'فُتح سطرٌ ثالث');
      expect(find.textContaining('59,000.00 ر.ي'), findsWidgets, reason: 'المتبقي من العهدة');

      // عقد عهدةٍ أخرى لا يُسحب.
      await tester.enterText(find.byType(TextField).at(27 + 13), 'other-9');
      await tester.pump();
      expect(t(34), '', reason: 'لم يُسحب');
      expect(tester.takeException(), isNull);
    });

    for (final size in const [Size(1280, 800), Size(360, 740), Size(320, 568)]) {
      testWidgets('نموذج الإخلاء وكشف الحساب بلا فيض ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        late LinkFinCustody c;
        await pump(
          tester,
          Builder(builder: (ctx) {
            c = LinkFinCustody(
              id: 'a', custodyNo: 'عهدة-00001', holder: '', title: 'شراء', serialNo: '', qty: 1, unit: '', valueAmount: 0, custodyDate: '2026-10-01',
              dueDate: '', cleared: false, clearedDate: '', clearanceNotes: '', notes: '', createdBy: '', createdAt: DateTime(2026),
              kind: 'received', amount: 1000, currency: 'sar', exchangeRate: 0, giverName: 'المالية', receiverName: 'سالم', status: 'open',
              outcome: '', outcomeAmount: 0, sourceDocNo: '', costCenter: '', attachmentsJson: '[]',
            );
            return Column(children: [
              ClearanceForm(openCustodies: [c], openContracts: const [], kind: 'custody', refId: 'a', actor: 'x', canApprove: true),
              FinanceStatement(repo: LinkageRepo(ctx.read<AppDatabase>()), names: const ['سالم'], party: 'سالم'),
            ]);
          }),
          size,
          seed: (db) => LinkageRepo(db).insertCustody(const LinkFinCustodiesCompanion(
              id: Value('a'), title: Value('شراء'), amount: Value(1000), receiverName: Value('سالم'))),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('تسجيل الإخلاء'), findsOneWidget);
        expect(find.textContaining('متبقٍّ لك عند المالية'), findsWidgets, reason: 'لا مسير ⇒ المصروف صفر ⇒ فائض');
        expect(find.textContaining('الرصيد'), findsWidgets);
      });
    }

    testWidgets('المستلمة: المُسلِّم المالية والمستلم أنا؛ وسعر الصرف لليمني فقط', (tester) async {
      await pump(tester, const CustodyForm(names: [], initial: null, actor: 'a', userName: 'سالم'), const Size(1280, 800));
      String v(int i) => (tester.widget(find.byType(TextField).at(i)) as TextField).controller!.text;
      // الحقول: رقم، مبلغ، (سعر الصرف مخفي)، مُسلِّم، مستلم، …
      final texts = [for (var i = 0; i < 6; i++) v(i)];
      expect(texts, containsAll(['المالية', 'سالم']));
      expect(find.textContaining('سعر الصرف *'), findsNothing);
    });
  });
}
