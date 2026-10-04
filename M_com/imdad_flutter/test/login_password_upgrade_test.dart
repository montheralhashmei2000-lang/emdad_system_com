import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/print_preview.dart' show imdNavigatorKey;
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/password_hash.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/auth/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بعد رفع الحد الأدنى إلى ٨ أحرف تبقى حسابات قديمة بكلمات أقصر. الدخول لا
/// يُمنع عنها، لكن يُعرض تنبيه بتغييرها — لغير المديرين.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  var signedIn = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    signedIn = 0;
  });
  tearDown(() => db.close());

  Future<void> addUser(WidgetTester tester, String name, String password, {String role = 'user'}) async {
    final ph = await tester.runAsync(() => PasswordHash.create(password));
    await db.into(db.users).insert(UsersCompanion.insert(
          id: 'local-$name',
          username: name,
          role: Value(role),
          saltHex: Value(ph!.saltHex),
          hashHex: Value(ph.hashHex),
          iterations: Value(ph.iterations),
        ));
  }

  Future<void> loginAs(WidgetTester tester, String user, String pass) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: AuthService(db)),
      ],
      child: MaterialApp(
        navigatorKey: imdNavigatorKey,
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LoginScreen(onSignedIn: () => signedIn++),
        ),
      ),
    ));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), user);
    await tester.enterText(fields.at(1), pass);
    await tester.tap(find.text('دخول'));
    await tester.pump();
    // اشتقاق PBKDF2 (٣١٠ ألف دورة) في Isolate — ننتظر حتى يكتمل الدخول.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && signedIn == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('مستخدم عادي بكلمة أقصر من ٨ ⇒ يدخل ويظهر تنبيه الترقية', (tester) async {
    await addUser(tester, 'sara', 'abc123');
    await loginAs(tester, 'sara', 'abc123');

    expect(signedIn, 1, reason: 'التنبيه لا يمنع الدخول');
    expect(find.text('غيّرها الآن'), findsOneWidget);
    expect(find.text('لاحقًا'), findsOneWidget);

    await tester.tap(find.text('لاحقًا'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('غيّرها الآن'), findsNothing, reason: '«لاحقًا» يُغلق التنبيه');
  });

  testWidgets('«غيّرها الآن» يفتح نافذة التغيير ويرفض الإدخال الخاطئ', (tester) async {
    await addUser(tester, 'sara', 'abc123');
    await loginAs(tester, 'sara', 'abc123');

    await tester.tap(find.text('غيّرها الآن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);

    // أقصر من ٨ ⇒ رفض.
    final dialogFields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(dialogFields.at(0), 'abc123');
    await tester.enterText(dialogFields.at(1), 'short');
    await tester.enterText(dialogFields.at(2), 'short');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('8 أحرف على الأقل'), findsOneWidget);

    // غير متطابقتين ⇒ رفض (دون اشتقاق باهظ). الحفظ الفعلي يمرّ بـ
    // UsersRepo.resetPassword وكلفته ٣١٠ ألف دورة ×٢ — أبطأ من أن يدخل هذا الاختبار.
    await tester.enterText(dialogFields.at(1), 'a-much-longer-pass');
    await tester.enterText(dialogFields.at(2), 'another-different');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('غير متطابقتين'), findsOneWidget);
  });

  test('قاعدة التنبيه: أقصر من ٨ وغير مدير فقط', () {
    bool f(String role, String pw) =>
        AuthService.shouldSuggestPasswordChange(role: role, password: pw);
    expect(f('user', 'abc123'), isTrue);
    expect(f('user', 'abcd123'), isTrue, reason: '٧ أحرف');
    expect(f('user', 'abcd1234'), isFalse, reason: '٨ أحرف كافية');
    expect(f('admin', 'abc123'), isFalse, reason: 'المدير لا يُنبَّه');
  });
}
