import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/contract_print.dart';
import 'package:imdad/core/print/custody_sheet_print.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/domain/arabic_words.dart';
import 'package:imdad/domain/custody_sheet.dart';
import 'package:imdad/features/linkages/contract_editor.dart';
import 'package:imdad/features/linkages/custody_sheet_editor.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// عقد الشراء ومسير العهدة: التفقيط، الحسابات، الطباعة، ومحرّراهما.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('التفقيط', () {
    test('أعداد أساسية', () {
      expect(arabicNumberWords(0), 'صفر');
      expect(arabicNumberWords(3), 'ثلاثة');
      expect(arabicNumberWords(11), 'أحد عشر');
      expect(arabicNumberWords(21), 'واحد وعشرون');
      expect(arabicNumberWords(100), 'مئة');
      expect(arabicNumberWords(215), 'مئتان وخمسة عشر');
    });
    test('الآلاف والملايين', () {
      expect(arabicNumberWords(1000), 'ألف');
      expect(arabicNumberWords(2000), 'ألفان');
      expect(arabicNumberWords(2200), 'ألفان ومئتان');
      expect(arabicNumberWords(3000), 'ثلاثة آلاف');
      expect(arabicNumberWords(11000), 'أحد عشر ألف');
      expect(arabicNumberWords(1250000), 'مليون ومئتان وخمسون ألف');
    });
    test('المبلغ بعملته وكسره', () {
      expect(amountInWords(2200, major: 'ريال يمني'), 'ألفان ومئتان ريال يمني فقط لا غير');
      expect(amountInWords(3.51, major: 'ريال سعودي', minor: 'هللة'), 'ثلاثة ريال سعودي وواحد وخمسون هللة فقط لا غير');
      // التقريب لا يُنتج هللات خاطئة.
      expect(amountInWords(0.999, major: 'ريال سعودي'), 'واحد ريال سعودي فقط لا غير');
    });
  });

  group('حسابات مسير العهدة', () {
    test('المنصرف اليمني يُقسم على سعر الصرف كمعادلة F÷G في Excel', () {
      const r = CustodyRowValues(spentYer: 135000, rate: 410);
      expect(r.spentInSar, closeTo(329.27, 0.01));
      // بلا يمني يؤخذ السعودي المكتوب.
      expect(const CustodyRowValues(spentSar: 343, rate: 410).spentInSar, 343);
      // اليمني يغلب السعودي القديم.
      expect(const CustodyRowValues(spentSar: 1, spentYer: 4100, rate: 410).spentInSar, 10);
      // سعر صرف صفر لا يقسم.
      expect(const CustodyRowValues(spentSar: 5, spentYer: 100, rate: 0).spentInSar, 5);
    });
    test('الإجماليات والمتبقي = العهدة − المنصرف', () {
      final t = custodyTotals(const [
        CustodyRowValues(grantSar: 30000, spentSar: 3905),
        CustodyRowValues(spentYer: 135000, rate: 410),
        CustodyRowValues(returnSar: 10),
      ]);
      expect(t.granted, 30000);
      expect(t.spent, closeTo(3905 + 329.27, 0.01));
      expect(t.returned, 10);
      expect(t.remaining, closeTo(30000 - 3905 - 329.27, 0.01));
    });
    test('الفواتير المكررة: الفارغ لا يُعدّ تكرارًا والمقارنة بلا فروق حالة وفراغ', () {
      expect(duplicateInvoiceNos(['سند استلام', ' سند استلام ', '274', '', '', 'A', 'a']), {'سند استلام', 'a'});
      expect(duplicateInvoiceNos(['1', '2', '3']), isEmpty);
    });
  });

  group('الطباعة', () {
    late AppDatabase db;
    late LinkageRepo repo;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LinkageRepo(db);
    });
    tearDown(() => db.close());

    int pageCount(List<int> pdf) => RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(pdf)).length;

    Future<LinkPurchaseContract> contract(String id, int n, {String cur = 'sar', double rate = 0}) async {
      final items = [
        for (var i = 1; i <= n; i++)
          ContractItem(name: 'صنف $i', unit: 'كيس', qty: 2, price: 100, total: 200, invoiceNo: '${i + 270}', date: '2026-08-12'),
      ];
      await repo.insertContract(LinkPurchaseContractsCompanion(
        id: Value(id),
        title: const Value('مواد غذائية'),
        supplier: const Value('محلات الوفي'),
        currency: Value(cur),
        exchangeRate: Value(rate),
        listDate: const Value('2026-08-12'),
        itemsJson: Value(ContractItem.encode(items)),
        amount: Value(ContractItem.sum(items)),
      ));
      return (await repo.contracts()).firstWhere((c) => c.id == id);
    }

    test('عقد قصير: صفحة واحدة، وعقد طويل: صفحتان فأكثر', () async {
      final short = await ContractPrint.build(db, await contract('a', 3));
      expect(String.fromCharCodes(short.take(5)), '%PDF-');
      expect(pageCount(short), 1);

      final long = await ContractPrint.build(db, await contract('b', 40));
      expect(pageCount(long), greaterThan(1));
    });

    test('سطر المقابل بالسعودي للعملة اليمنية وبسعر صرف فقط', () async {
      expect(ContractPrint.showsSarEquivalent(await contract('s', 1)), isFalse);
      expect(ContractPrint.showsSarEquivalent(await contract('y0', 1, cur: 'yer')), isFalse, reason: 'بلا سعر صرف');
      expect(ContractPrint.showsSarEquivalent(await contract('y', 1, cur: 'yer', rate: 410)), isTrue);
    });

    test('أصناف العقد نصٌّ حر وتُحفظ وتُقرأ كما كُتبت', () async {
      final c = await contract('t', 2);
      final back = ContractItem.decode(c.itemsJson);
      expect(back.map((e) => e.name), ['صنف 1', 'صنف 2']);
      expect(back.first.date, '2026-08-12');
      expect(ContractItem.autoTotal(0, 2200), 2200, reason: 'الكمية الفارغة تُعدّ واحدًا');
      expect(ContractItem.autoTotal(3, 100), 300);
    });

    test('مسير العهدة: حفظ وقراءة وطباعة PDF أفقي، والإجماليات صحيحة', () async {
      final id = await repo.saveCustodySheet(sheetNo: '2', title: 'عهدة', defaultRate: 410, notes: '', rows: [
        const LinkCustodySheetRowsCompanion(date: Value('2026-05-15'), grantSar: Value(30000)),
        const LinkCustodySheetRowsCompanion(date: Value('2026-05-16'), spentYer: Value(135000), rate: Value(410), invoiceNo: Value('9')),
        const LinkCustodySheetRowsCompanion(date: Value('2026-05-17'), spentSar: Value(100), invoiceNo: Value('9')),
      ]);
      final rows = await repo.sheetRows(id);
      expect(rows.map((r) => r.seq), [0, 1, 2]);
      final sheet = (await repo.custodySheets()).single;
      final bytes = await CustodySheetPrint.build(db, sheet, rows);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(pageCount(bytes), 1);

      // إعادة الحفظ تستبدل الأسطر ولا تكرّرها.
      await repo.saveCustodySheet(id: id, sheetNo: '2', title: 'عهدة', defaultRate: 410, notes: '', rows: [
        const LinkCustodySheetRowsCompanion(grantSar: Value(1)),
      ]);
      expect(await repo.sheetRows(id), hasLength(1));
      await repo.deleteCustodySheet(sheet);
      expect(await db.select(db.linkCustodySheetRows).get(), isEmpty);
    });

    test('مئة سطر تُقسَّم على صفحات برأسٍ متكرر ولا تُقصّ', () async {
      final id = await repo.saveCustodySheet(sheetNo: '3', title: '', defaultRate: 410, notes: '', rows: [
        for (var i = 0; i < 100; i++) LinkCustodySheetRowsCompanion(date: const Value('2026-05-15'), spentSar: Value(i.toDouble() + 1)),
      ]);
      final sheet = (await repo.custodySheets()).single;
      final bytes = await CustodySheetPrint.build(db, sheet, await repo.sheetRows(id));
      expect(pageCount(bytes), greaterThan(1));
    });
  });

  group('المحرران', () {
    late AppDatabase db;
    late AuthService auth;

    Future<void> pump(WidgetTester tester, Widget editor, Size size) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db.close());
      auth = AuthService(db);
      await tester.runAsync(() async {
        await auth.createAdmin(username: 'admin', password: 'Test@12345');
        await auth.login('admin', 'Test@12345');
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SafeArea(child: editor))),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    const sizes = [Size(1280, 800), Size(800, 1280), Size(360, 740), Size(320, 568)];

    for (final size in sizes) {
      testWidgets('محرر المسير يُبنى بلا فيض ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await pump(tester, const CustodySheetEditor(initial: null, initialRows: [], actor: 'a', canPrint: true), size);
        expect(tester.takeException(), isNull);
        expect(find.text('حفظ المسير'), findsWidgets);
      });

      testWidgets('محرر العقد يُبنى بلا فيض ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await pump(tester, const ContractEditor(initial: null, actor: 'a', canPrint: true), size);
        expect(tester.takeException(), isNull);
        expect(find.text('حفظ العقد'), findsWidgets);
      });
    }

    testWidgets('سعر الصرف لا يظهر إلا عند اختيار العملة اليمنية', (tester) async {
      await pump(tester, const ContractEditor(initial: null, actor: 'a', canPrint: false), const Size(1280, 800));
      expect(find.textContaining('سعر الصرف *', findRichText: true), findsNothing);
      expect(find.textContaining('ما يقابل بالريال السعودي', findRichText: true), findsNothing);
    });

    testWidgets('العقد بعملة يمنية يعرض سعر الصرف والمقابل بالسعودي', (tester) async {
      final yer = LinkPurchaseContract(
        id: 'x',
        contractNo: '',
        title: 'بهارات',
        supplier: 'تاجر',
        currency: 'yer',
        exchangeRate: 410,
        listDate: '2026-08-12',
        itemsJson: ContractItem.encode(const [ContractItem(name: 'كمون', price: 4100, total: 4100)]),
        amount: 4100,
        endDate: '',
        status: 'open',
        notes: '',
        createdBy: '',
        createdAt: DateTime(2026),
      );
      await pump(tester, ContractEditor(initial: yer, actor: 'a', canPrint: false), const Size(1280, 800));
      expect(find.textContaining('سعر الصرف *', findRichText: true), findsOneWidget);
      expect(find.textContaining('ما يقابل بالريال السعودي', findRichText: true), findsOneWidget);
      expect(find.text('10.00'), findsOneWidget, reason: '4100 ÷ 410');
    });

    testWidgets('مسير العهدة: اليمني يحسب السعودي ويقفل خليته، والتكرار ينبّه', (tester) async {
      await pump(tester, const CustodySheetEditor(initial: null, initialRows: [], actor: 'a', canPrint: false), const Size(1500, 900));
      final fields = find.byType(TextField);
      // 0..3 رأس المسير؛ ثم أعمدة السطر الأول: عهدة، مرتجع س، مرتجع ي، منصرف س، منصرف ي، صرف، …، رقم الفاتورة(14)
      await tester.enterText(fields.at(4), '1000');
      await tester.enterText(fields.at(8), '41000');
      await tester.pump();
      expect((tester.widget(fields.at(7)) as TextField).controller!.text, '100', reason: '41000 ÷ 410');
      expect((tester.widget(fields.at(7)) as TextField).readOnly, isTrue);
      expect(find.text('1,000.00 ر.س.'), findsOneWidget);

      await tester.tap(find.text('إضافة سطر'));
      await tester.pump();
      expect(find.textContaining('أرقام فواتير مكررة'), findsNothing);
      await tester.enterText(find.byType(TextField).at(14), '55');
      await tester.enterText(find.byType(TextField).at(14 + 13), '55');
      await tester.pump();
      expect(find.textContaining('أرقام فواتير مكررة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
