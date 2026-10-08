import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/password_hash.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/selfcheck_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اسمُ دخولٍ واحدٌ لحسابين: من يُصادَق؟
///
/// لا قيد تفرّد على `users.username` — وإضافته لجدولٍ قائم تُسقط مشغّلات
/// المزامنة المعلّقة عليه، وقاعدةٌ فيها تكرارٌ سابق لن تُفتح بعدها. والتكرار
/// واقعيٌّ لا نظري: جهازٌ هيّأ `local-admin` محليًّا ووصله `admin` بمعرّفٍ آخر
/// بالمزامنة. فكان `login` يأخذ `matches.first` من استعلامٍ **بلا `ORDER BY`**،
/// فأيُّ الحسابين يُصادَق غيرُ محدَّد. هذه الاختبارات تثبّت الاختيار وتكشف التكرار.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
  });

  tearDown(() => db.close());

  /// حسابٌ باسمٍ وكلمة مرور ومعرّفٍ صريح.
  Future<void> seed({
    required String id,
    required String username,
    required String password,
    String role = 'admin',
    DateTime? updatedAt,
  }) async {
    final ph = await PasswordHash.create(password);
    await db.into(db.users).insert(UsersCompanion.insert(
          id: id,
          username: username,
          role: Value(role),
          saltHex: Value(ph.saltHex),
          hashHex: Value(ph.hashHex),
          iterations: Value(ph.iterations),
          warehouseScope: const Value('ALL'),
          updatedAt: Value(updatedAt),
        ));
  }

  test('الحساب المحلي يُقدَّم على الوارد بالمزامنة عند تكرار الاسم', () async {
    // الوارد أحدثُ تعديلًا — ومع ذلك المحلي أحقُّ بالدخول على جهازه.
    await seed(id: 'remote-9', username: 'admin', password: 'remote-pass-1');
    await seed(
      id: 'local-admin',
      username: 'admin',
      password: 'local-pass-1',
      updatedAt: DateTime(2020),
    );

    final ok = await auth.login('admin', 'local-pass-1');
    expect(ok.isOk, isTrue, reason: 'كلمة مرور الحساب المحلي لم تُقبل');
    expect(ok.user!.id, 'local-admin');

    // وكلمة مرور الحساب الآخر لا تفتح الجلسة: حسابٌ واحد هو المقصود بالاسم.
    final other = await AuthService(db).login('admin', 'remote-pass-1');
    expect(other.isOk, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('بلا حسابٍ محلي يفوز الأحدث تعديلًا — والاختيار ثابت لا عشوائي', () async {
    await seed(id: 'b-old', username: 'nasser', password: 'old-pass-11', updatedAt: DateTime(2021));
    await seed(id: 'a-new', username: 'nasser', password: 'new-pass-11', updatedAt: DateTime(2026));

    // يُعاد بخدماتٍ جديدة: لو كان الاختيار رهنَ ترتيب الصفوف لتبدّل. ثلاثُ
    // مرات لا عشر — كل دخولٍ اشتقاقُ PBKDF2 بـ٣١٠ ألف دورة.
    for (var i = 0; i < 3; i++) {
      final r = await AuthService(db).login('nasser', 'new-pass-11');
      expect(r.isOk, isTrue);
      expect(r.user!.id, 'a-new', reason: 'الاختيار تبدّل في المحاولة $i');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('تهيئة مدير باسمٍ مستعمل تُرفض (ولو باختلاف حالة الأحرف)', () async {
    await auth.createAdmin(username: 'Admin', password: 'first-pass-1');

    await expectLater(
      () => AuthService(db).createAdmin(username: 'admin', password: 'second-pass-1'),
      throwsA(isA<ArgumentError>()),
    );
    expect((await db.select(db.users).get()).length, 1);
  });

  test('فحص السلامة يكشف الاسم المكرّر ويسكت عن المفرد', () async {
    await seed(id: 'local-admin', username: 'admin', password: 'pass-aaaa-1');
    var res = await SelfCheckRepo(db).runAll();
    expect(res.firstWhere((r) => r.id == 'dupUsernames').ok, isTrue);

    // اسمٌ ثانٍ بحالة أحرفٍ مختلفة — المطابقة في الدخول غير حساسة، فهو تكرار.
    await seed(id: 'remote-1', username: 'ADMIN', password: 'pass-bbbb-1');
    res = await SelfCheckRepo(db).runAll();
    final dup = res.firstWhere((r) => r.id == 'dupUsernames');
    expect(dup.ok, isFalse);
    expect(dup.note, contains('admin'));
  });
}
