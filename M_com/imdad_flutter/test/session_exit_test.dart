import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الخروج الصريح من التطبيق ينهي الجلسة: لا دخولَ تلقائيًّا عند فتحه من جديد.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('الجلسة تُستعاد بعد إعادة التشغيل ما لم يكن الخروج صريحًا', () async {
    final first = AuthService(db);
    await first.createAdmin(username: 'admin', password: 'Test@12345');
    await first.login('admin', 'Test@12345');

    // «إعادة تشغيل» بلا خروج صريح (انهيار/قتل عملية): الجلسة تبقى.
    expect((await AuthService(db).restoreSession())?.username, 'admin');
  });

  test('الخروج الصريح (logout عند الإغلاق) يمنع الدخول التلقائي بعد فتح التطبيق', () async {
    final first = AuthService(db);
    await first.createAdmin(username: 'admin', password: 'Test@12345');
    await first.login('admin', 'Test@12345');

    // هذا ما يفعله `_shutdown` عند زر الإغلاق أو «خروج».
    await first.logout();

    expect(await AuthService(db).restoreSession(), isNull,
        reason: 'التطبيق دخل بلا كلمة مرور بعد الإغلاق');
  });
}
