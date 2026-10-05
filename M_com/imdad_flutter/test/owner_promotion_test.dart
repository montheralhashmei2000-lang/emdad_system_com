import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/owner_promotion.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/features/settings/device_activation_screen.dart' show deviceAccess;
import 'package:shared_preferences/shared_preferences.dart';

/// ترقية المالك التلقائية + من يملك ماذا في تفعيل الأجهزة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late UsersRepo repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    repo = UsersRepo(db);
  });

  tearDown(() => db.close());

  Future<String> roleOf(String username) async =>
      (await (db.select(db.users)..where((t) => t.username.equals(username))).getSingle()).role;

  Future<List<AuditLog>> promotionAudits() => (db.select(db.auditLogs)
        ..where((t) => t.action.equals(OwnerPromotion.autoPromotedAction)))
      .get();

  Future<void> insertAdmin(String id, String username) => db.into(db.users).insert(UsersCompanion.insert(
        id: id,
        username: username,
        role: const Value(UserRole.admin),
      ));

  group('createAdmin لم يتغيّر', () {
    test('كل حساب يُنشأ «admin» — المالك لا يُنشأ مباشرة', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      expect(await roleOf('root'), UserRole.admin);
      expect(auth.currentUser!.role, UserRole.admin);
    });
  });

  group('الترقية التلقائية — أربع حالات', () {
    test('1) مدير واحد محلي (local-) ⇒ يُرقّى مالكًا مع سجل تدقيق عالي الخطورة', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');

      final r = await OwnerPromotion.run(db);
      expect(r.outcome, OwnerPromotionOutcome.promoted);
      expect(r.userId, 'local-root');
      expect(await roleOf('root'), UserRole.owner);

      final audits = await promotionAudits();
      expect(audits, hasLength(1));
      expect(audits.single.risk, AuditRepo.riskHigh);
      expect(audits.single.summary, contains('root'));
    });

    test('1ب) مرةً واحدة: التشغيل الثاني لا يكرّر ولا يُسجّل', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await OwnerPromotion.run(db);
      final again = await OwnerPromotion.run(db);
      expect(again.outcome, OwnerPromotionOutcome.alreadyHasOwner);
      expect(await promotionAudits(), hasLength(1));
    });

    test('1ج) تتم عند الدخول: login يُرقّي الحساب ويفتح الجلسة بدور المالك', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      final res = await AuthService(db).login('root', 'Test@12345');
      expect(res.isOk, isTrue, reason: res.message);
      expect(res.user!.role, UserRole.owner);
    });

    test('2) مديران ⇒ لا ترقية، ويُطلب تحديد المالك', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await repo.createUser(username: 'second', password: 'Test@12345', name: 's', isAdmin: true);

      final r = await OwnerPromotion.run(db);
      expect(r.outcome, OwnerPromotionOutcome.ambiguous);
      expect(r.adminCount, 2);
      expect(await roleOf('root'), UserRole.admin);
      expect(await roleOf('second'), UserRole.admin);
      expect(await promotionAudits(), isEmpty);
      expect(await OwnerPromotion.needsSelection(db), isTrue);
      expect(await AuthService(db).ownerSelectionNeeded(), isTrue);
      // الدخول لا يُرقّي أيضًا.
      final res = await AuthService(db).login('root', 'Test@12345');
      expect(res.user!.role, UserRole.admin);
    });

    test('3) مدير واحد غير محلي ⇒ لا ترقية', () async {
      await insertAdmin('srv-1', 'remote');
      final r = await OwnerPromotion.run(db);
      expect(r.outcome, OwnerPromotionOutcome.notLocal);
      expect(await roleOf('remote'), UserRole.admin);
      expect(await promotionAudits(), isEmpty);
      expect(await OwnerPromotion.needsSelection(db), isFalse);
    });

    test('4) لا مدير ⇒ لا شيء (والمستخدم العادي لا يُرقّى)', () async {
      expect((await OwnerPromotion.run(db)).outcome, OwnerPromotionOutcome.noAdmin);
      await repo.createUser(username: 'clerk', password: 'Test@12345', name: 'c');
      expect((await OwnerPromotion.run(db)).outcome, OwnerPromotionOutcome.noAdmin);
      expect(await roleOf('clerk'), UserRole.user);
      expect(await OwnerPromotion.needsSelection(db), isFalse);
    });
  });

  group('حالات حدّية', () {
    test('جهاز فرع لا يُرقّي ولو رأى مديرًا محليًا واحدًا', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      final r = await OwnerPromotion.run(db, isBranchDevice: true);
      expect(r.outcome, OwnerPromotionOutcome.skippedBranch);
      expect(await roleOf('root'), UserRole.admin);
      // ولا يطلب تحديد مالك في الفرع.
      final branch = AuthService(db, isBranchDevice: () async => true);
      expect(await branch.ownerSelectionNeeded(), isFalse);
      final res = await branch.login('root', 'Test@12345');
      expect(res.user!.role, UserRole.admin);
    });

    test('عطبٌ في معرفة نوع الجهاز ⇒ فشلٌ مغلق: لا ترقية', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      final broken = AuthService(db, isBranchDevice: () async => throw StateError('x'));
      final res = await broken.login('root', 'Test@12345');
      expect(res.isOk, isTrue); // الدخول لا يفشل
      expect(res.user!.role, UserRole.admin);
    });

    test('وجود مالكٍ يمنع أي ترقية لاحقة', () async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await OwnerPromotion.run(db);
      await insertAdmin('local-late', 'late');
      expect((await OwnerPromotion.run(db)).outcome, OwnerPromotionOutcome.alreadyHasOwner);
      expect(await roleOf('late'), UserRole.admin);
    });
  });

  group('تحديد المالك يدويًا (مديران فأكثر)', () {
    Future<AuthService> twoAdmins() async {
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await repo.createUser(username: 'second', password: 'Test@12345', name: 's', isAdmin: true);
      final a = AuthService(db);
      expect((await a.login('root', 'Test@12345')).isOk, isTrue);
      return a;
    }

    test('كلمة مرور خاطئة ⇒ يُرفض ولا يتغيّر شيء', () async {
      final a = await twoAdmins();
      expect(await a.assignOwner(userId: 'local-second', confirmPassword: 'wrong'), isFalse);
      expect(await roleOf('second'), UserRole.admin);
    });

    test('صحيح ⇒ يصير المختار مالكًا ويُسجَّل بخطورة عالية، وبعدها لا إعادة تحديد', () async {
      final a = await twoAdmins();
      expect(await a.assignOwner(userId: 'local-second', confirmPassword: 'Test@12345'), isTrue);
      expect(await roleOf('second'), UserRole.owner);
      expect(await roleOf('root'), UserRole.admin);
      final audits = await (db.select(db.auditLogs)..where((t) => t.action.equals(OwnerPromotion.assignedAction))).get();
      expect(audits, hasLength(1));
      expect(audits.single.risk, AuditRepo.riskHigh);
      expect(await a.assignOwner(userId: 'local-root', confirmPassword: 'Test@12345'), isFalse);
      expect(await OwnerPromotion.needsSelection(db), isFalse);
    });

    test('مديرٌ يحدّد نفسه: تتحدّث جلسته فورًا', () async {
      final a = await twoAdmins();
      expect(await a.assignOwner(userId: 'local-root', confirmPassword: 'Test@12345'), isTrue);
      expect(a.currentUser!.role, UserRole.owner);
    });

    test('مستخدم عادي أو جهاز فرع لا يحدّدان', () async {
      await twoAdmins();
      await repo.createUser(username: 'clerk', password: 'Test@12345', name: 'c');
      final clerk = AuthService(db);
      await clerk.login('clerk', 'Test@12345');
      expect(await clerk.assignOwner(userId: 'local-second', confirmPassword: 'Test@12345'), isFalse);

      final branch = AuthService(db, isBranchDevice: () async => true);
      await branch.login('root', 'Test@12345');
      expect(await branch.assignOwner(userId: 'local-second', confirmPassword: 'Test@12345'), isFalse);
      expect(await OwnerPromotion.needsSelection(db), isTrue);
    });

    test('لا يُحدَّد مستخدمٌ عادي مالكًا', () async {
      final a = await twoAdmins();
      await repo.createUser(username: 'clerk', password: 'Test@12345', name: 'c');
      expect(await a.assignOwner(userId: 'local-clerk', confirmPassword: 'Test@12345'), isFalse);
      expect(await roleOf('clerk'), UserRole.user);
    });
  });

  group('من يفعل ماذا في تفعيل الأجهزة', () {
    test('جهاز جديد بلا حسابات (بوابة): الكل مفتوح — لا طريق غيره للتفعيل الأول', () {
      final a = deviceAccess(standalone: true, hasUsers: false, owner: false);
      expect(a.enterToken, isTrue);
      expect(a.manage, isTrue);
      expect(a.bootstrap, isTrue);
    });

    test('البوابة وفيها حسابات: الرمز فقط، بلا إدارة ولا تهيئة', () {
      final a = deviceAccess(standalone: true, hasUsers: true, owner: false);
      expect(a.enterToken, isTrue);
      expect(a.manage, isFalse);
      expect(a.bootstrap, isFalse);
    });

    test('داخل الإعدادات: المالك وحده يُدير، ولا تهيئة أبدًا', () {
      final owner = deviceAccess(standalone: false, hasUsers: true, owner: true);
      expect(owner.enterToken, isTrue);
      expect(owner.manage, isTrue);
      expect(owner.bootstrap, isFalse);
    });

    test('داخل الإعدادات: غير المالك لا شيء — حتى مع بقاء الجهاز بلا حسابات', () {
      for (final hasUsers in [true, false]) {
        final a = deviceAccess(standalone: false, hasUsers: hasUsers, owner: false);
        expect(a.enterToken, isFalse, reason: 'hasUsers=$hasUsers');
        expect(a.manage, isFalse, reason: 'hasUsers=$hasUsers');
        expect(a.bootstrap, isFalse, reason: 'hasUsers=$hasUsers');
      }
    });
  });
}
