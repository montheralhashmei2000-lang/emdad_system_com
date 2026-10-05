import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/sys_notice.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/domain/permission_impact.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// قواعد المالك والمدير في إدارة الحسابات + تنبيه الانتقال + تقرير الأثر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late UsersRepo repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = UsersRepo(db);
    // مالك + مدير + مستخدم، بإنشاءٍ داخلي موثوق (بلا actorRole).
    await repo.createUser(username: 'boss', password: 'Test@12345', name: 'b', isAdmin: true);
    await repo.createUser(username: 'adm', password: 'Test@12345', name: 'a', isAdmin: true);
    await repo.createUser(username: 'clerk', password: 'Test@12345', name: 'c');
    await (db.update(db.users)..where((t) => t.username.equals('boss')))
        .write(const UsersCompanion(role: Value(UserRole.owner)));
  });

  tearDown(() => db.close());

  Future<User> byName(String n) => (db.select(db.users)..where((t) => t.username.equals(n))).getSingle();

  group('المدير (admin)', () {
    const as = UserRole.admin;

    test('ينشئ «مستخدمًا» بقالبٍ جاهز', () async {
      final id = await repo.createUser(
          username: 'new1', password: 'Test@12345', name: 'n', roleIds: ['data_entry'], actorRole: as);
      final u = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
      expect(u.role, UserRole.user);
      expect(UsersRepo.rolesOf(u), ['data_entry']);
      expect(u.permissions, contains('stocktake'));
    });

    test('لا يمنح دور مدير ولا يخصّص صلاحيات ولا نطاقًا ولا يستعمل قالبًا مجهولًا', () async {
      await expectLater(
          repo.createUser(username: 'x1', password: 'Test@12345', name: 'x', isAdmin: true, actorRole: as),
          throwsArgumentError);
      await expectLater(
          repo.createUser(
              username: 'x2',
              password: 'Test@12345',
              name: 'x',
              permissions: {
                'items': {'view': true}
              },
              actorRole: as),
          throwsArgumentError);
      await expectLater(
          repo.createUser(username: 'x3', password: 'Test@12345', name: 'x', warehouseScope: ['w'], actorRole: as),
          throwsArgumentError);
      await expectLater(
          repo.createUser(username: 'x4', password: 'Test@12345', name: 'x', roleIds: ['nope'], actorRole: as),
          throwsArgumentError);
    });

    test('يعدّل اسم مستخدمٍ عادي ويفعّله، ولا يعطّله ولا يعدّل صلاحياته أو دوره أو نطاقه', () async {
      final clerk = await byName('clerk');
      await repo.updateUser(id: clerk.id, name: 'جديد', actorRole: as);
      await repo.updateUser(id: clerk.id, active: true, actorRole: as);
      expect((await byName('clerk')).name, 'جديد');
      await expectLater(repo.updateUser(id: clerk.id, active: false, actorRole: as), throwsArgumentError);
      await expectLater(
          repo.updateUser(
              id: clerk.id,
              permissions: {
                'items': {'view': true}
              },
              actorRole: as),
          throwsArgumentError);
      await expectLater(repo.updateUser(id: clerk.id, isAdmin: true, actorRole: as), throwsArgumentError);
      await expectLater(repo.updateUser(id: clerk.id, allWarehouses: true, actorRole: as), throwsArgumentError);
      await expectLater(repo.updateUser(id: clerk.id, warehouseScope: ['w'], actorRole: as), throwsArgumentError);
    });

    test('لا يمسّ حساب مديرٍ أو مالك', () async {
      for (final name in ['adm', 'boss']) {
        final t = await byName(name);
        await expectLater(repo.updateUser(id: t.id, name: 'x', actorRole: as), throwsArgumentError, reason: name);
      }
    });

    test('لا يحذف أحدًا', () async {
      final clerk = await byName('clerk');
      await expectLater(repo.deleteUser(clerk.id, actorRole: as), throwsArgumentError);
      expect((await db.select(db.users).get()).length, 3);
    });
  });

  group('المالك (owner)', () {
    const as = UserRole.owner;

    test('يمنح دور المدير ويخصّص الصلاحيات والنطاق ويعطّل', () async {
      await repo.createUser(username: 'adm3', password: 'Test@12345', name: 'x', isAdmin: true, actorRole: as);
      final clerk = await byName('clerk');
      await repo.updateUser(
          id: clerk.id,
          permissions: {
            'items': {'view': true}
          },
          actorRole: as);
      await repo.updateUser(id: clerk.id, allWarehouses: true, actorRole: as);
      await repo.updateUser(id: clerk.id, active: false, actorRole: as);
      expect((await byName('clerk')).active, isFalse);
      expect((await byName('adm3')).role, UserRole.admin);
    });

    test('يحذف مستخدمًا عاديًا، ولا يحذف نفسه', () async {
      final clerk = await byName('clerk');
      expect(await repo.deleteUser(clerk.id, actorRole: as), isTrue);
      expect(await repo.deleteUser((await byName('boss')).id, actorRole: as), isFalse);
    });
  });

  test('مستخدم عادي لا يدير حسابات إطلاقًا', () async {
    final clerk = await byName('clerk');
    await expectLater(repo.updateUser(id: clerk.id, name: 'x', actorRole: UserRole.user), throwsArgumentError);
    await expectLater(
        repo.createUser(username: 'z', password: 'Test@12345', name: 'z', actorRole: UserRole.user),
        throwsArgumentError);
  });

  test('الاستدعاء الداخلي الموثوق (بلا actorRole) لا يخضع للقواعد', () async {
    final clerk = await byName('clerk');
    await repo.updateUser(
        id: clerk.id,
        permissions: {
          'items': {'view': true}
        },
        isAdmin: true);
    expect((await byName('clerk')).role, UserRole.admin);
  });

  group('تنبيه الانتقال', () {
    test('يظهر مرةً واحدة لكل مدير غير مالك، ولا يظهر للمالك ولا للمستخدم', () async {
      final notice = SysTransitionNotice(db);
      final adm = await byName('adm');
      expect(await notice.shouldShow(adm), isTrue);
      await notice.markSeen(adm);
      expect(await notice.shouldShow(adm), isFalse);
      expect(await notice.shouldShow(await byName('boss')), isFalse);
      expect(await notice.shouldShow(await byName('clerk')), isFalse);
    });

    test('مديرٌ آخر يراه رغم أن الأول رآه، ويبقى «مرئيًا» بعد إعادة بناء الخدمة', () async {
      await repo.createUser(username: 'adm2', password: 'Test@12345', name: 'a2', isAdmin: true);
      await SysTransitionNotice(db).markSeen(await byName('adm'));
      expect(await SysTransitionNotice(db).shouldShow(await byName('adm')), isFalse);
      expect(await SysTransitionNotice(db).shouldShow(await byName('adm2')), isTrue);
    });

    test('الرسالة نصّها المتّفق عليه', () {
      expect(SysTransitionNotice.message, 'النسخ الاحتياطي والتفعيل والمزامنة انتقلت للمالك. تواصل معه.');
    });
  });

  group('تقرير الأثر', () {
    test('يصنّف المستخدمين بلا تعديل أي حساب', () async {
      final a = await byName('clerk');
      await (db.update(db.users)..where((t) => t.id.equals(a.id))).write(const UsersCompanion(
        permissions: Value(
            '{"settings":{"edit":true},"usersAccess":{"view":true},"suppliers":{"create":true},"stores":{"create":true,"edit":true},"items":{"create":true}}'),
      ));
      final report = PermissionImpact.build(await db.select(db.users).get());
      List<String> names(String id) => [for (final u in report.firstWhere((i) => i.id == id).users) u.username];
      expect(names('admins'), ['adm']);
      expect(names('settingsEditors'), ['clerk']);
      expect(names('usersAccess'), ['clerk']);
      expect(names('suppliersCreateOnly'), ['clerk']);
      expect(names('storesCreateOnly'), isEmpty); // لديه edit أيضًا
      expect(names('importInherit'), ['clerk']);
      // قراءةٌ فقط.
      expect((await byName('clerk')).role, UserRole.user);
    });

    test('import صريح يُخرج المستخدم من «يرث»', () async {
      final a = await byName('clerk');
      await (db.update(db.users)..where((t) => t.id.equals(a.id)))
          .write(const UsersCompanion(permissions: Value('{"items":{"create":true,"import":false}}')));
      final r = PermissionImpact.build(await db.select(db.users).get());
      expect(r.firstWhere((i) => i.id == 'importInherit').users, isEmpty);
    });
  });
}
