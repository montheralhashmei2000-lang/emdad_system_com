import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اسمٌ غير موجود يمرّ بمسار PBKDF2 كما تمرّ كلمة مرورٍ خاطئة لحسابٍ موجود، فلا
/// يُكشف الموجود بفارق زمن الرد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.logout();
    AuthService.dummyVerifications = 0;
  });
  tearDown(() => db.close());

  test('اسم غير موجود يشغّل الاشتقاق الوهمي ويفشل بالرسالة نفسها', () async {
    final unknown = await auth.login('ghost', 'Whatever@123');
    expect(AuthService.dummyVerifications, 1);
    expect(unknown.status, AuthStatus.badCredentials);

    final wrong = await auth.login('admin', 'Wrong@12345');
    expect(AuthService.dummyVerifications, 1, reason: 'الحساب الموجود يمرّ بالاشتقاق الحقيقي لا الوهمي');
    expect(wrong.status, AuthStatus.badCredentials);
    // الرسالة نفسها بصيغتها (عدا العدّاد): لا فرق يكشف وجود الاسم.
    expect(unknown.message.replaceAll(RegExp(r'\d'), ''), wrong.message.replaceAll(RegExp(r'\d'), ''));
  });

  test('الدخول الصحيح لا يمرّ بالمسار الوهمي', () async {
    final ok = await auth.login('admin', 'Test@12345');
    expect(ok.isOk, isTrue);
    expect(AuthService.dummyVerifications, 0);
  });
  _roundsGroup();
}

/// دورات الاشتقاق الوهمي تُحاكي أسرعَ حسابٍ في القاعدة لا المعيارَ الحالي.
///
/// حسابٌ قديم (٤٥ ألف دورة) يردّ أسرع بكثير من ٣١٠ ألفًا. فلو ثُبّت المسار
/// الوهميُّ على المعيار لصار بطءُ الردّ قرينةً على أن الاسم **غير موجود** —
/// وهو تسريبُ الوجود نفسه مقلوبًا.
void _roundsGroup() {
  group('دورات المسار الوهمي', () {
    test('قاعدةٌ فيها حسابٌ قديم ⇒ الوهميُّ بدوراته هو', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'u1',
            username: 'legacy',
            saltHex: Value('aa' * 16),
            hashHex: Value('bb' * 32),
            iterations: const Value(Pbkdf2.legacyIterations),
          ));

      final sw = Stopwatch()..start();
      await AuthService(db).login('لا-وجود-له', 'كلمة-مرور-طويلة');
      final unknown = sw.elapsedMilliseconds;

      sw.reset();
      await AuthService(db).login('legacy', 'كلمة-مرور-خاطئة');
      final wrong = sw.elapsedMilliseconds;

      // النسبة لا الفرق المطلق: الآلة تتفاوت. قبل الإصلاح كانت ≈٧×.
      expect(unknown, lessThan(wrong * 4 + 400),
          reason: 'الاسم المجهول ($unknown م.ث) أبطأ بكثير من الخاطئ ($wrong م.ث) — يُكشف بالتوقيت');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('قاعدةٌ فارغة تعود إلى المعيار الحالي', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final before = AuthService.dummyVerifications;
      await AuthService(db).login('أحد', 'كلمة-مرور-طويلة');
      expect(AuthService.dummyVerifications, before + 1);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
