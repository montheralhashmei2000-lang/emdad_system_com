import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// المالك و`sys.*`: الأساس. المالك وحده يملك `sys.*`، ولا شيء مخزَّن يمنحها لغيره.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الأدوار', () {
    test('المالك والمدير كلاهما «مدير» لصلاحيات الصفحات، والمالك وحده «مالك»', () {
      expect(UserRole.isAdmin(UserRole.owner), isTrue);
      expect(UserRole.isAdmin(UserRole.admin), isTrue);
      expect(UserRole.isAdmin(UserRole.user), isFalse);
      expect(UserRole.isAdmin(null), isFalse);
      expect(UserRole.isOwner(UserRole.owner), isTrue);
      expect(UserRole.isOwner(UserRole.admin), isFalse);
      expect(UserRole.label(UserRole.owner), 'المالك');
      expect(UserRole.label('نص غريب'), 'مستخدم');
    });
  });

  group('AccessControl.can مع sys.*', () {
    test('المالك وحده', () {
      for (final key in SysPerm.all) {
        expect(AccessControl.can(isAdmin: true, isOwner: true, permissions: const {}, page: key), isTrue, reason: key);
        expect(AccessControl.can(isAdmin: true, permissions: const {}, page: key), isFalse, reason: 'admin $key');
        expect(AccessControl.can(isAdmin: false, permissions: const {}, page: key), isFalse, reason: 'user $key');
      }
    });

    test('مفتاحٌ sys.* داخل الصلاحيات المخزَّنة لا أثر له (فشلٌ مغلق)', () {
      final injected = {
        for (final k in SysPerm.all) k: {'view': true, 'edit': true, 'create': true},
      };
      for (final key in SysPerm.all) {
        expect(AccessControl.can(isAdmin: false, permissions: injected, page: key), isFalse, reason: key);
        expect(AccessControl.can(isAdmin: true, permissions: injected, page: key), isFalse, reason: 'admin $key');
      }
    });

    test('صفحات العمل العادية لا تتأثر', () {
      expect(AccessControl.can(isAdmin: true, permissions: const {}, page: 'items'), isTrue);
      expect(AccessControl.can(isAdmin: false, permissions: const {}, page: 'items'), isFalse);
    });

    test('ستة مفاتيح بأسماء مقروءة', () {
      expect(SysPerm.all, hasLength(6));
      for (final k in SysPerm.all) {
        expect(k, startsWith('sys.'));
        expect(SysPerm.labels[k]!.trim(), isNotEmpty);
      }
    });
  });

  group('مع حسابات حقيقية', () {
    late AppDatabase db;
    late AuthService auth;
    late UsersRepo repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      auth = AuthService(db);
      repo = UsersRepo(db);
      await auth.createAdmin(username: 'root', password: 'Test@12345');
    });

    tearDown(() => db.close());

    Future<void> loginAs(String user, {String role = UserRole.admin}) async {
      await (db.update(db.users)..where((t) => t.username.equals(user))).write(UsersCompanion(role: Value(role)));
      final r = await auth.login(user, 'Test@12345');
      expect(r.isOk, isTrue, reason: r.message);
    }

    test('المالك يملك sys.* ويملك كل صفحات العمل', () async {
      await loginAs('root', role: UserRole.owner);
      final perm = Perm(auth);
      expect(perm.owner, isTrue);
      expect(perm.admin, isTrue);
      for (final k in SysPerm.all) {
        expect(perm.sys(k), isTrue, reason: k);
        expect(perm.has(k), isTrue, reason: k);
      }
      expect(perm.has('items', PermAction.delete), isTrue);
      expect(auth.can(auth.currentUser!, SysPerm.backup), isTrue);
      expect(auth.warehouseScopeOf(auth.currentUser!), isNull);
    });

    test('المدير: كل الصفحات وبلا sys.*', () async {
      // مديران ⇒ لا ترقية تلقائية عند الدخول، فيبقى root مديرًا.
      await repo.createUser(username: 'second', password: 'Test@12345', name: 's', isAdmin: true);
      await loginAs('root'); // role = admin
      final perm = Perm(auth);
      expect(perm.admin, isTrue);
      expect(perm.owner, isFalse);
      for (final k in SysPerm.all) {
        expect(perm.sys(k), isFalse, reason: k);
        expect(perm.has(k), isFalse, reason: k);
      }
      expect(perm.has('items', PermAction.delete), isTrue);
      expect(auth.can(auth.currentUser!, SysPerm.devices), isFalse);
    });

    test('مستخدمٌ عاديٌّ مخزَّنٌ له sys.* يدويًا: لا يملكها', () async {
      await repo.createUser(
        username: 'sneaky',
        password: 'Test@12345',
        name: 'x',
        permissions: {
          for (final k in SysPerm.all) k: {'view': true, 'edit': true},
          'items': {'view': true},
        },
      );
      final r = await auth.login('sneaky', 'Test@12345');
      expect(r.isOk, isTrue, reason: r.message);
      final perm = Perm(auth);
      for (final k in SysPerm.all) {
        expect(perm.sys(k), isFalse, reason: k);
        expect(perm.has(k, PermAction.edit), isFalse, reason: k);
      }
      expect(perm.has('items'), isTrue);
    });

    group('حماية حساب المالك', () {
      Future<String> makeOwner() async {
        await (db.update(db.users)..where((t) => t.username.equals('root')))
            .write(const UsersCompanion(role: Value(UserRole.owner)));
        return (await (db.select(db.users)..where((t) => t.username.equals('root'))).getSingle()).id;
      }

      test('لا يتغيّر دوره ولا يُعطَّل', () async {
        final id = await makeOwner();
        await expectLater(repo.updateUser(id: id, isAdmin: false), throwsArgumentError);
        await expectLater(repo.updateUser(id: id, isAdmin: true), throwsArgumentError);
        await expectLater(repo.updateUser(id: id, active: false), throwsArgumentError);
        final after = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
        expect(after.role, UserRole.owner);
        expect(after.active, isTrue);
      });

      test('تعديل غير الدور والتفعيل مسموح (الاسم)', () async {
        final id = await makeOwner();
        await repo.updateUser(id: id, name: 'اسم جديد');
        final after = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
        expect(after.name, 'اسم جديد');
      });

      test('لا يُحذف ولو وُجد مدير آخر', () async {
        final id = await makeOwner();
        await repo.createUser(username: 'second', password: 'Test@12345', name: 's', isAdmin: true);
        expect(await repo.deleteUser(id), isFalse);
        expect((await db.select(db.users).get()).length, 2);
      });

      test('المدير الآخر يُحذف ما دام المالك باقيًا (المالك يُحسب مديرًا)', () async {
        await makeOwner();
        final adminId = await repo.createUser(username: 'second', password: 'Test@12345', name: 's', isAdmin: true);
        expect(await repo.deleteUser(adminId), isTrue);
      });

      test('آخر مديرٍ (دون مالك) لا يُحذف كما كان', () async {
        final id = (await db.select(db.users).get()).single.id;
        expect(await repo.deleteUser(id), isFalse);
      });
    });
  });

  test('كل مفتاح sys.* في الكود معرَّف في SysPerm (لا أخطاء إملائية)', () {
    final lit = RegExp(r"""['"](sys\.\w+)['"]""");
    final known = SysPerm.all.toSet();
    final unknown = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      for (final m in lit.allMatches(f.readAsStringSync())) {
        if (!known.contains(m.group(1))) unknown.add('${m.group(1)} (${f.path})');
      }
    }
    expect(unknown, isEmpty);
  });
}
