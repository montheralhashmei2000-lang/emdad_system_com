import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الجلسة لا تنجو من إنهاءٍ قسري.
///
/// كل مسارات الخروج المقصود تُنهي الجلسة قبل إغلاق النافذة (`_shutdown`)، فما
/// كان يبلغ `restoreSession` إلا تطبيقٌ **لم يُغلق**: قُتل من مدير المهام، أو
/// سُحب من قائمة تطبيقات أندرويد، أو انهار. وكان يدخل بلا كلمة مرور ١٢ ساعة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  final salt = 'ab' * 16;
  const password = 'Test@12345';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(UsersCompanion.insert(
          id: 'u1',
          username: 'sara',
          saltHex: Value(salt),
          hashHex: Value(Pbkdf2.deriveHex(password, salt, iterations: 1000)),
          iterations: const Value(1000),
        ));
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> stored() => SettingsRepo(db).read('authSession');
  Future<List<AuditLog>> uncleanAudits() => (db.select(db.auditLogs)
        ..where((t) => t.action.equals('auth.session.unclean')))
      .get();

  /// إقلاعٌ جديد: خدمةٌ جديدة على القاعدة نفسها، كما يفعل `main`.
  Future<User?> reboot() => AuthService(db).restoreSession();

  test('الدخول يضع علامة «مفتوحة» في صفّ الجلسة', () async {
    await AuthService(db).login('sara', password);
    expect((await stored())[AuthService.sessionOpenKey], isTrue);
  });

  test('إنهاءٌ قسري (العلامة باقية) ⇒ لا تُستعاد الجلسة وتُمحى', () async {
    await AuthService(db).login('sara', password);
    // لا `logout`: هكذا تبدو القاعدة بعد قتل العملية.
    expect(await reboot(), isNull, reason: 'فُتح النظام بلا كلمة مرور بعد إنهاءٍ قسري');
    expect(await stored(), isEmpty, reason: 'الجلسة بقيت فتُستعاد في الإقلاع التالي');
    expect(await uncleanAudits(), hasLength(1));
  });

  test('خروجٌ نظيف ثم إقلاع ⇒ لا جلسة (كما كان) وبلا شاهد إنهاءٍ قسري', () async {
    final auth = AuthService(db);
    await auth.login('sara', password);
    await auth.logout(); // ما يفعله `_shutdown` عند إغلاق النافذة
    expect(await reboot(), isNull);
    expect(await uncleanAudits(), isEmpty, reason: 'خروجٌ نظيف سُجّل إنهاءً قسريًّا');
  });

  test('الإقلاع بعد الإنهاء القسري لا يترك أثرًا يُستعاد منه ثانيًا', () async {
    await AuthService(db).login('sara', password);
    await reboot();
    expect(await reboot(), isNull);
    expect(await uncleanAudits(), hasLength(1), reason: 'شاهدٌ لكل إقلاع لا لكل إنهاء');
  });

  test('جلسةٌ كتبها إصدارٌ أقدم (بلا علامة) تُستعاد — توافقٌ لمرةٍ واحدة', () async {
    await SettingsRepo(db).write('authSession', {
      'userId': 'u1',
      'startedAt': DateTime.now().millisecondsSinceEpoch,
    });
    expect((await reboot())?.username, 'sara');
    expect(await uncleanAudits(), isEmpty);
  });

  test('العلامة لا تُسقط جلسةً جارية (`sessionExpired` يقيس العمر وحده)', () async {
    final auth = AuthService(db);
    await auth.login('sara', password);
    expect(await auth.sessionExpired(), isFalse);
  });

  test('جلسةٌ مفتوحةٌ ومنتهيةُ العمر تُمحى كذلك', () async {
    await SettingsRepo(db).write('authSession', {
      'userId': 'u1',
      'startedAt': DateTime.now().subtract(const Duration(hours: 13)).millisecondsSinceEpoch,
      AuthService.sessionOpenKey: true,
    });
    expect(await reboot(), isNull);
    expect(await stored(), isEmpty);
  });

  test('حسابٌ حُذف بعد الإنهاء القسري: لا يسقط الإقلاع ويُمحى الصف', () async {
    await AuthService(db).login('sara', password);
    await (db.delete(db.users)..where((t) => t.id.equals('u1'))).go();
    expect(await reboot(), isNull);
    expect(await stored(), isEmpty);
    expect(await uncleanAudits(), hasLength(1), reason: 'الشاهد يُكتب وإن غاب الحساب');
  });
}
