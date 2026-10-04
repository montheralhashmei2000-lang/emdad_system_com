import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/error_log.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/warehouse_scope.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';

/// نطاق المستودعات فشلُه مغلق: التالف ⇒ لا مستودعات، لا «كل المستودعات».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() {
    ErrorLogger.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
  });
  tearDown(() async {
    ErrorLogger.reset();
    await db.close();
  });

  Future<User> user(String id, String scope, {String role = 'user'}) async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: id,
          username: id,
          role: Value(role),
          warehouseScope: Value(scope),
        ));
    return (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
  }

  group('قيم صحيحة لا تتأثر', () {
    test('ALL ⇒ كل المستودعات (null)، بأي حالة أحرف وبفراغات حولها', () async {
      for (final v in ['ALL', 'all', ' ALL ']) {
        final u = await user('u${v.hashCode}', v);
        expect(auth.warehouseScopeOf(u), isNull, reason: v);
        expect(UsersRepo.scopeOf(u), isNull, reason: v);
      }
      expect(ErrorLogger.recent, isEmpty, reason: 'لا خطأ يُسجَّل لقيمة صحيحة');
    });

    test('قائمة أسماء ⇒ هي نفسها، والقائمة الفارغة المقصودة تبقى فارغة', () async {
      final u = await user('a', '["المخزن الرئيسي","مخزن ٢"]');
      expect(auth.warehouseScopeOf(u), ['المخزن الرئيسي', 'مخزن ٢']);
      expect(UsersRepo.scopeOf(u), ['المخزن الرئيسي', 'مخزن ٢']);

      final none = await user('b', '[]');
      expect(auth.warehouseScopeOf(none), isEmpty);
      expect(ErrorLogger.recent, isEmpty);
    });

    test('المدير كل المستودعات حتى لو تلف نطاقه (الدور هو الحاكم)', () async {
      final admin = await user('adm', '{bad', role: 'admin');
      expect(auth.warehouseScopeOf(admin), isNull);
    });
  });

  group('JSON تالف ⇒ فشل مغلق', () {
    const corrupt = ['{bad json', '', '"ALL-ISH"', '{"a":1}', 'null', '[unterminated', '42'];

    test('كل قيمة تالفة تُرجع قائمة فارغة لا null، في المسارين', () async {
      for (var i = 0; i < corrupt.length; i++) {
        final u = await user('c$i', corrupt[i]);
        expect(auth.warehouseScopeOf(u), isNotNull, reason: 'تالف «${corrupt[i]}» فُتح على كل المستودعات');
        expect(auth.warehouseScopeOf(u), isEmpty, reason: corrupt[i]);
        expect(UsersRepo.scopeOf(u), isNotNull, reason: corrupt[i]);
        expect(UsersRepo.scopeOf(u), isEmpty, reason: corrupt[i]);
      }
    });

    test('التلف يُسجَّل خطأً حرجًا بمصدره', () async {
      final persisted = <LoggedError>[];
      ErrorLogger.sink = (e) async => persisted.add(e);

      auth.warehouseScopeOf(await user('x', '{bad'));
      UsersRepo.scopeOf(await user('y', '{bad'));

      expect(persisted.map((e) => e.source), containsAll(['auth.warehouseScope', 'users.scopeJson']));
      expect(persisted.every((e) => e.critical), isTrue);
    });

    test('نتيجة الفشل تنعكس في وصف النطاق: «بدون مستودعات» لا «كل المستودعات»', () async {
      final u = await user('z', '{bad');
      expect(UsersRepo.scopeLabel(u), 'بدون مستودعات');
    });
  });

  test('parseWarehouseScope مباشرة', () {
    expect(parseWarehouseScope('ALL', source: 't'), isNull);
    expect(parseWarehouseScope('["أ"]', source: 't'), ['أ']);
    expect(parseWarehouseScope('###', source: 't'), isEmpty);
  });
}
