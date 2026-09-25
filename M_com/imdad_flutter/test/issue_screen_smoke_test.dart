import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/issue_drafts_view.dart';
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة الصرف بعد فصل قواعدها ومسوداتها: تُبنى وتعرض لوحة التحقق ورقم السند
/// برمز الجهاز، وتبويب المسودات يعرض المسودة ويعتمدها.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthService(db);
    await tester.runAsync(() async {
      await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
      final catalog = CatalogRepo(db);
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      final rice = await catalog.saveItem(
        code: 'R1',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final mv = MovementsRepo(db);
      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'المورد',
        date: '2026-09-01',
        lines: [DocLineInput(itemId: rice, itemCode: 'R1', itemName: 'أرز', unitName: 'كجم', factor: 1, qty: 50)],
      );
      await mv.saveIssue(
        warehouse: 'الرئيسي',
        recipientDisplay: 'السرية الأولى',
        date: '2026-09-02',
        status: 'DRAFT',
        lines: [DocLineInput(itemId: rice, itemCode: 'R1', itemName: 'أرز', unitName: 'كجم', factor: 1, qty: 20)],
      );
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'issue')),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: screen)),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  testWidgets('نموذج الصرف يُبنى بلا أخطاء ويعرض رقمًا برمز الجهاز', (tester) async {
    await pump(tester, const IssueScreen());
    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'ص-[2-9A-Z]{4}-000002')), findsWidgets);
  });

  testWidgets('تبويب المسودات يعرض المسودة ويعتمدها من رصيد مستودعها', (tester) async {
    await pump(tester, const IssueDraftsView());
    expect(find.text('السرية الأولى'), findsOneWidget);

    await tester.tap(find.text('اعتماد وصرف الرصيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد').last);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    final rows = await tester.runAsync(() => db.select(db.issues).get());
    expect(rows!.single.status, 'COMPLETED');
    expect(find.text('السرية الأولى'), findsNothing);
  });
}
