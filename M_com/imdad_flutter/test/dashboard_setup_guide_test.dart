import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/home/dashboard_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إرشاد أول استخدام: يظهر ما دام شيءٌ ناقصًا، ويختفي من تلقائه عند اكتمال
/// التهيئة — فلا يزاحم من أتمّها على مساحة لوحته.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
    await auth.login('admin', 'Test@12345');
  });

  tearDown(() => db.close());

  String? lastPage;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    lastPage = null;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((p) => lastPage = p, () => 'dashboard')),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: DashboardScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  testWidgets('قاعدة فارغة: الإرشاد يظهر بالخطوات الأربع ناقصة', (tester) async {
    await pump(tester);
    expect(find.text('خطوات التهيئة'), findsOneWidget);
    expect(find.textContaining('بقي ٤ من ٤'), findsOneWidget);
    expect(find.text('عرّف مستودعًا'), findsOneWidget);
  });

  testWidgets('بعد تعريف مستودع: العدد ينقص والخطوة تُشطب', (tester) async {
    await tester.runAsync(() => CatalogRepo(db).saveWarehouse(code: 'W1', name: 'الرئيسي'));
    await pump(tester);
    expect(find.textContaining('بقي ٣ من ٤'), findsOneWidget);
    // الخطوة المنجزة تبقى معروضةً مشطوبةً، فيرى المستخدم تقدّمه لا نقصه فقط.
    expect(find.text('عرّف مستودعًا'), findsOneWidget);
  });

  testWidgets('زر «افتح» ينقل إلى شاشة الخطوة', (tester) async {
    await pump(tester);
    final row = find.ancestor(of: find.text('أضف الأصناف'), matching: find.byType(Row)).last;
    await tester.tap(find.descendant(of: row, matching: find.text('افتح')));
    await tester.pump();
    expect(lastPage, 'items');
  });

  testWidgets('تهيئةٌ مكتملة: الإرشاد يختفي كليًّا', (tester) async {
    await tester.runAsync(() async {
      final cat = CatalogRepo(db);
      await cat.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await cat.saveItem(
        code: 'R1',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await cat.saveUnit(code: 'U1', name: 'السرية الأولى');
      await cat.saveSupplier(name: 'مؤسسة النور');
    });
    await pump(tester);
    expect(find.text('خطوات التهيئة'), findsNothing);
  });
}
