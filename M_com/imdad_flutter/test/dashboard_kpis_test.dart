import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_layout.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/home/dashboard_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخصيص بطاقات المؤشرات: الاختيار والترتيب محفوظان لكل مستخدم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    // `createAdmin` يفتح جلسةً فيقرأ التخزين، فتُهيَّأ محاكاته قبله.
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
    await auth.login('admin', 'Test@12345');
  });

  tearDown(() => db.close());

  /// التفضيل يُقرأ في `initState`، فيُكتب قبل البناء لا بعده — وعبر المسار
  /// الحقيقي لا بإعادة المحاكاة، فإعادتها تمسح جلسة المستخدم معها.
  Future<void> savedKpis(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('imdad.dashboard.kpis.${auth.currentUser!.id}', ids);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'dashboard')),
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

  List<String> labels(WidgetTester tester) =>
      tester.widgetList<ImdKpi>(find.byType(ImdKpi)).map((k) => k.label).toList();

  testWidgets('بلا تفضيل محفوظ: الترتيب الافتراضي كاملًا', (tester) async {
    await pump(tester);
    final l = labels(tester);
    expect(l.first, 'إجمالي الأصناف');
    expect(l.length, 6);
  });

  testWidgets('تفضيل محفوظ: يُحترم الاختيار والترتيب معًا', (tester) async {
    await savedKpis(['openStk', 'items']);
    await pump(tester);
    expect(labels(tester), ['جلسات جرد مفتوحة', 'إجمالي الأصناف']);
  });

  testWidgets('معرّفٌ محفوظٌ لم يعد موجودًا يُسقَط بلا انهيار', (tester) async {
    await savedKpis(['items', 'مؤشرٌ أُزيل', 'openStk']);
    await pump(tester);
    expect(labels(tester), ['إجمالي الأصناف', 'جلسات جرد مفتوحة']);
    expect(tester.takeException(), isNull);
  });
}
