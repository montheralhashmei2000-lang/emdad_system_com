import 'package:drift/native.dart';
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
}
