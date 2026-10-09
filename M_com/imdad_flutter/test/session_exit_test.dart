import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الخروج من التطبيق ينهي الجلسة: لا دخولَ تلقائيًّا عند فتحه من جديد —
/// صريحًا كان الخروج أو قسريًّا (انظر الاختبار الأول).
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('الجلسة لا تُستعاد بعد إنهاءٍ غير نظيف', () async {
    final first = AuthService(db);
    await first.createAdmin(username: 'admin', password: 'Test@12345');
    await first.login('admin', 'Test@12345');

    // قرار 2026-10-01 (الاحتفاظ بالجلسة بعد انهيار) نُقض 2026-10-09.
    // السبب: ثغرة أمنية في السياق العسكري/الحكومي (جهاز مسروق = 12h).
    // الاختبار الجديد للسلوك: session_unclean_exit_test.dart.
    //
    // ونصُّ القرار المنقوض يُحفظ كما كُتب يومه، شاهدًا على ما كان:
    // «إعادة تشغيل» بلا خروج صريح (انهيار/قتل عملية): الجلسة تبقى.
    expect(await AuthService(db).restoreSession(), isNull,
        reason: 'الجلسة نجت من إنهاءٍ قسري، فيُفتح النظام بلا كلمة مرور');
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
