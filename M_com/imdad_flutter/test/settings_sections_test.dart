import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/settings/settings_screen.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// أقسام الإعدادات: الهوية والنماذج والمستخدمون والمزامنة والتفعيل والتحقق صارت
/// أقسامًا داخل شاشة الإعدادات نفسها، لا بنودًا مستقلة في القائمة الجانبية.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late AutoSyncService autoSync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    autoSync = AutoSyncService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
  });

  tearDown(() => db.close());

  Widget host(String section) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<AutoSyncService>.value(value: autoSync),
          ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
          Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'settings')),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SettingsScreen(initialSection: section)),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, String section) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(section));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  /// قسم → نصٌّ يخصّ الشاشة المضمَّنة فيه.
  const sections = {
    'company': 'الشعار',
    'forms': 'معاينة النموذج',
    'users': 'المستخدمون',
    'sync': 'مزامنة',
    'devices': 'معرّف هذا الجهاز',
    'verify': 'رمز التحقق',
  };

  for (final e in sections.entries) {
    testWidgets('قسم «${e.key}» يعرض شاشته مضمَّنةً بلا انهيار ولا زر رجوع', (tester) async {
      await pump(tester, e.key);

      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      expect(find.textContaining(e.value), findsWidgets, reason: 'محتوى القسم ${e.key} غائب');
      expect(find.text('رجوع إلى الإعدادات'), findsNothing,
          reason: 'الزر يظهر داخل قسمٍ مضمَّن');
    });
  }

  testWidgets('الأقسام الستة في قائمة أقسام الإعدادات', (tester) async {
    await pump(tester, 'general');
    for (final name in [
      'هوية النظام والشعار',
      'رأس وتذييل النماذج',
      'المستخدمون والصلاحيات',
      'تفعيل الأجهزة',
      'التحقق من التوقيع',
      'المزامنة والتوقيع',
    ]) {
      expect(find.text(name), findsWidgets, reason: name);
    }
  });

  testWidgets('مستخدمٌ بلا صلاحية القسم يرى رسالة لا الشاشة', (tester) async {
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    final a = AuthService(other);
    // اشتقاق كلمة المرور يعمل في Isolate، فلا يُنتظر داخل الزمن الوهمي للاختبار.
    await tester.runAsync(() async {
      await a.createAdmin(username: 'admin', password: 'Test@12345');
      // مستخدمٌ عاديّ بلا صلاحيات.
      await UsersRepo(other).createUser(username: 'clerk', password: 'Clerk@12345', name: 'كاتب');
      await a.login('clerk', 'Clerk@12345');
    });

    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: other),
        Provider<AuthService>.value(value: a),
        ChangeNotifierProvider<AutoSyncService>.value(value: AutoSyncService(other)),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'settings')),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SettingsScreen(initialSection: 'devices')),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(find.textContaining('لا تملك صلاحية'), findsWidgets);
    expect(find.textContaining('معرّف هذا الجهاز'), findsNothing);
  });
}
