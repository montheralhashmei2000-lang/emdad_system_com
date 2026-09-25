import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/settings/device_activation_screen.dart';
import 'package:imdad/main.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('بوابة الجهاز', () {
    test('جهاز بلا أي حساب ⇒ بوابة التفعيل، ولو قُبل رمزه', () {
      // قبول الرمز لا يُنشئ حسابًا: الإخراج إلى شاشة الدخول هنا يعني
      // «اسم المستخدم أو كلمة المرور غير صحيحة» إلى الأبد.
      expect(gateFor(fresh: true), GateTarget.activation);
    });

    test('جهاز فيه حسابات ⇒ شاشة الدخول، ولا يُقفل ولو لم يُفعَّل', () {
      expect(gateFor(fresh: false), GateTarget.login);
    });
  });

  group('ما الذي يجعل الجهاز «جديدًا»', () {
    test('حساب وصل بالمزامنة يكفي — لا يُشترط أن يكون محليًا', () async {
      final auth = AuthService(db);
      expect(await auth.hasAnyUser(), isFalse);

      await db.into(db.users).insert(
            UsersCompanion.insert(id: 'srv-7', username: 'ahmad', name: const Value('أحمد')),
          );

      expect(await auth.hasAnyUser(), isTrue, reason: 'الجهاز صار عنده حساب يدخل به');
      expect(await auth.needsBootstrap(), isTrue, reason: 'ومع ذلك لا حساب مدير محلي');
    });
  });

  group('طريق استقبال الحسابات بالمزامنة', () {
    test('جهاز غير مفعَّل لا يُعرض له — رمز الاقتران ليس بديلًا عن بطاقة التفعيل', () {
      expect(
        showsReceiveAccounts(activated: false, hasUsers: false, canBootstrap: false),
        isFalse,
      );
    });

    test('جهاز فرع مفعَّل بلا حسابات ⇒ يُعرض له', () {
      expect(
        showsReceiveAccounts(activated: true, hasUsers: false, canBootstrap: false),
        isTrue,
      );
    });

    test('جهاز الإدارة يُنشئ حسابه ولا ينتظر مزامنة', () {
      expect(
        showsReceiveAccounts(activated: true, hasUsers: false, canBootstrap: true),
        isFalse,
      );
    });

    test('جهاز وصلته الحسابات لا يبقى في الانتظار', () {
      expect(
        showsReceiveAccounts(activated: true, hasUsers: true, canBootstrap: false),
        isFalse,
      );
    });
  });

  /// جهاز فيه حسابات يعمل اليوم — يجب ألّا يُقفل بأثر رجعي بعد التحديث.
  testWidgets('الجهاز العامل لا يُقفل ويعرض شاشة الدخول', (tester) async {
    // التجزئة تعمل في Isolate حقيقي، والوقت داخل testWidgets وهمي حتى runAsync.
    await tester.runAsync(() => AuthService(db).createAdmin(username: 'admin', password: 'Test@12345', name: 'admin'));

    await tester.pumpWidget(ImdadApp(db: db, auth: AuthService(db), signedIn: false));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    expect(find.text('دخول إلى النظام'), findsOneWidget);
    expect(find.text('إدخال رمز التفعيل'), findsNothing);
  });
}
