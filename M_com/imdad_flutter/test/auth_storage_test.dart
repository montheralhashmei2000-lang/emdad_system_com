import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// قفل الدخول والجلسة محفوظان في القاعدة المشفّرة لا في SharedPreferences،
/// مع ترحيل القديم دون إسقاط الجلسات القائمة.
void main() {
  late AppDatabase db;

  Future<void> addUser(String id, String name) => db.into(db.users).insert(UsersCompanion.insert(
        id: id,
        username: name,
        name: Value(name),
      ));

  Future<Set<String>> prefKeys() async => (await SharedPreferences.getInstance()).getKeys();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('مفاتيح القفل والجلسة محلية للجهاز: لا تُصدَّر ولا تُستورد', () {
    expect(SettingsRepo.localOnlyKeys, containsAll(['authSession', 'authLocks']));
  });

  group('قفل الدخول', () {
    test('خمس محاولات خاطئة تقفل، والعدّاد في القاعدة لا في SharedPreferences', () async {
      final auth = AuthService(db);
      AuthResult? last;
      for (var i = 0; i < AuthService.maxAttempts; i++) {
        last = await auth.login('ghost', 'wrong-pass-$i');
      }
      expect(last!.status, AuthStatus.locked);

      expect((await SettingsRepo(db).read('authLocks')).keys, contains('ghost'));
      expect((await prefKeys()).where((k) => k.startsWith('imdad.auth.lock.')), isEmpty);

      // «إعادة تشغيل»: نسخة جديدة من الخدمة تقرأ القفل نفسه.
      expect((await AuthService(db).login('ghost', 'anything-else')).status, AuthStatus.locked);
    });

    test('قفلٌ قديم في SharedPreferences يُحترم ثم يُنقل إلى القاعدة ويُمسح', () async {
      final until = DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'imdad.auth.lock.ghost': '{"fails":0,"until":$until}',
      });

      expect((await AuthService(db).login('Ghost', 'whatever-pass')).status, AuthStatus.locked);

      expect((await SettingsRepo(db).read('authLocks'))['ghost'], isA<Map>());
      expect(await prefKeys(), isNot(contains('imdad.auth.lock.ghost')));
    });
  });

  group('الجلسة', () {
    test('جلسة قديمة سارية في SharedPreferences تُستعاد وتُنقل إلى القاعدة', () async {
      await addUser('u1', 'sara');
      final started = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'imdad.session.userId': 'u1',
        'imdad.session.startedAt': started,
      });

      expect((await AuthService(db).restoreSession())?.username, 'sara');

      final keys = await prefKeys();
      expect(keys, isNot(contains('imdad.session.userId')));
      expect(keys, isNot(contains('imdad.session.startedAt')));
      final stored = await SettingsRepo(db).read('authSession');
      expect(stored['userId'], 'u1');
      expect(stored['startedAt'], started, reason: 'وقت البدء الأصلي يبقى فلا تتمدّد الجلسة');

      // وبعدها تُستعاد من القاعدة وحدها.
      expect((await AuthService(db).restoreSession())?.username, 'sara');
    });

    test('جلسة قديمة منتهية (أكثر من ١٢ ساعة) لا تُستعاد', () async {
      await addUser('u1', 'sara');
      SharedPreferences.setMockInitialValues({
        'imdad.session.userId': 'u1',
        'imdad.session.startedAt': DateTime.now().subtract(const Duration(hours: 13)).millisecondsSinceEpoch,
      });
      expect(await AuthService(db).restoreSession(), isNull);
      expect(await prefKeys(), isNot(contains('imdad.session.userId')));
    });

    test('الخروج يمسح الجلسة من القاعدة', () async {
      await addUser('u1', 'sara');
      await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
            key: 'authSession',
            value: Value('{"userId":"u1","startedAt":${DateTime.now().millisecondsSinceEpoch}}'),
          ));
      final auth = AuthService(db);
      expect((await auth.restoreSession())?.username, 'sara');

      await auth.logout();

      expect(await SettingsRepo(db).read('authSession'), isEmpty);
      expect(await AuthService(db).restoreSession(), isNull);
    });
  });
}
