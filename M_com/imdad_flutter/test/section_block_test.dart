import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/core/security/owner_signature.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/domain/section_block.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حجب الأقسام (v25): النموذج، التطبيق fail-closed، المستودع والتوقيع، والقشرة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SectionBlock — النموذج', () {
    test('انتماء الصفحات: المحروقات والإمداد والأقسام الإدارية والمحايدة', () {
      expect(SectionBlock.sectionOf('fuelMoves'), SectionBlock.fuel);
      expect(SectionBlock.sectionOf('fuelDashboard'), SectionBlock.fuel);
      expect(SectionBlock.sectionOf('items'), SectionBlock.supply);
      expect(SectionBlock.sectionOf('reportMoves'), SectionBlock.supply);
      expect(SectionBlock.sectionOf('usersAccess'), SectionBlock.adminUsers);
      expect(SectionBlock.sectionOf('lanSync'), SectionBlock.adminSync, reason: 'قبل تطبيعها إلى sys.sync');
      expect(SectionBlock.sectionOf('deviceActivation'), SectionBlock.adminDevices);
      expect(SectionBlock.sectionOf('branding'), SectionBlock.adminSettings);
      expect(SectionBlock.sectionOf('supplyAudit'), SectionBlock.adminAudit);
      expect(SectionBlock.sectionOf('auditTrail'), SectionBlock.adminAudit);
      expect(SectionBlock.sectionOf('dash'), isNull);
      expect(SectionBlock.sectionOf('settings'), isNull, reason: 'تُرشَّح أقسامها الداخلية لا الشاشة');
    });

    test('أقسام الإعدادات الداخلية تتبع الحجب كما حدّدتَ', () {
      expect(SectionBlock.settingsSections['company'], SectionBlock.adminSettings);
      expect(SectionBlock.settingsSections['forms'], SectionBlock.adminSettings);
      expect(SectionBlock.settingsSections['verify'], SectionBlock.adminSettings);
      expect(SectionBlock.settingsSections['backup'], SectionBlock.adminSettings);
      expect(SectionBlock.settingsSections['users'], SectionBlock.adminUsers);
      expect(SectionBlock.settingsSections['sync'], SectionBlock.adminSync);
      expect(SectionBlock.settingsSections['devices'], SectionBlock.adminDevices);
      expect(SectionBlock.settingsSections.containsKey('general'), isFalse);
    });

    test('القراءة: فارغ = لا حجب، والتالف يحجب الكل (فشل مغلق)، والمجهول يُهمل', () {
      expect(SectionBlock.parse(''), isEmpty);
      expect(SectionBlock.parse('[]'), isEmpty);
      expect(SectionBlock.parse(null), isEmpty);
      expect(SectionBlock.parse('["fuel","bogus"]'), {SectionBlock.fuel});
      expect(SectionBlock.parse('{not json'), SectionBlock.all.toSet(), reason: 'JSON تالف ⇒ كل شيء محجوب');
      expect(SectionBlock.parse('{"a":1}'), SectionBlock.all.toSet(), reason: 'ليست قائمة ⇒ كل شيء محجوب');
    });

    test('الترميز حتميّ ومرتّب بلا تكرار (التوقيع يُحسب على نصّه)', () {
      expect(SectionBlock.encode(['fuel', 'supply', 'fuel']), '["supply","fuel"]');
      expect(SectionBlock.encode({'fuel', 'supply'}), SectionBlock.encode(['supply', 'fuel']));
      expect(SectionBlock.encode(['nope']), '[]');
    });

    test('المالك لا يُحجب عنه شيء حتى لو خُزِّن له حجب', () {
      for (final page in ['fuelMoves', 'items', 'usersAccess']) {
        expect(SectionBlock.blocksPage(role: 'owner', blockedJson: '["supply","fuel","admin.users"]', page: page),
            isFalse);
      }
      expect(SectionBlock.blocksSection(role: 'owner', blockedJson: '["fuel"]', section: 'fuel'), isFalse);
      expect(SectionBlock.blocksPage(role: 'admin', blockedJson: '["fuel"]', page: 'fuelMoves'), isTrue,
          reason: 'والمدير يُحجب');
    });

    test('AccessControl.can: المدير المحجوب عن قسمٍ لا يدخله، وغير المحجوب يدخل', () {
      bool can(String page, {bool owner = false, String? blocked}) => AccessControl.can(
            isAdmin: true,
            isOwner: owner,
            permissions: const {},
            page: page,
            sectionBlocked: blocked,
          );
      expect(can('fuelMoves'), isTrue);
      expect(can('fuelMoves', blocked: '["fuel"]'), isFalse);
      expect(can('items', blocked: '["fuel"]'), isTrue, reason: 'قسم آخر لا يتأثر');
      expect(can('fuelMoves', owner: true, blocked: '["fuel"]'), isTrue);
    });
  });

  group('المستودع والتوقيع', () {
    late AppDatabase db;
    late UsersRepo repo;
    late String ownerPub;
    late String ownerPriv;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = UsersRepo(db);
      final pair = ESign.generateKeyPair();
      ownerPub = pair.publicB64;
      ownerPriv = pair.privateHex;
      await db.into(db.users).insert(UsersCompanion.insert(id: 'o1', username: 'boss', role: const Value('owner')));
      await db.into(db.users).insert(UsersCompanion.insert(id: 'a1', username: 'adm', role: const Value('admin')));
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u1', username: 'ali'));
    });

    tearDown(() => db.close());

    DeviceActivation withKey() => DeviceActivation(db, ownerPublicKey: ownerPub);
    Future<User> user(String id) => (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
    Future<List<AuditLog>> audits(String action) =>
        (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get();

    test('المالك وحده يحجب: المدير والمستخدم يُرفضان', () async {
      for (final role in [UserRole.admin, UserRole.user]) {
        await expectLater(
          repo.setSectionBlocked(id: 'u1', blocked: {SectionBlock.fuel}, actorRole: role),
          throwsA(isA<ArgumentError>()),
          reason: role,
        );
      }
      expect((await user('u1')).sectionBlocked, '[]');
    });

    test('لا يُحجب عن المالك شيء', () async {
      await expectLater(
        repo.setSectionBlocked(id: 'o1', blocked: {SectionBlock.fuel}, actorRole: UserRole.owner),
        throwsA(isA<ArgumentError>()),
      );
      expect((await user('o1')).sectionBlocked, '[]');
    });

    test('إضافة الحجب بلا توقيع وتُدقَّق بخطورة عالية', () async {
      final r = await repo.setSectionBlocked(
        id: 'u1',
        blocked: {SectionBlock.fuel, SectionBlock.adminUsers},
        actorRole: UserRole.owner,
        actorEmail: 'boss@x',
        activation: withKey(), // حتى مع وجود مفتاح: الإضافة لا تُوقَّع
      );
      expect(r.changed, isTrue);
      expect(r.added, {SectionBlock.fuel, SectionBlock.adminUsers});
      expect(r.signed, isFalse);
      expect(r.unsignedUnblock, isFalse);

      final u = await user('u1');
      expect(u.sectionBlocked, SectionBlock.encode({SectionBlock.fuel, SectionBlock.adminUsers}));
      expect(u.ownerSig, '');

      final log = await audits('user.section_blocked.changed');
      expect(log, hasLength(1));
      expect(log.single.risk, 'high');
      expect(log.single.actorEmail, 'boss@x');
      expect(await audits('sys.sign.used'), isEmpty, reason: 'لا مفتاح استُعمل');
    });

    test('بلا تغيير ⇒ لا كتابة ولا تدقيق', () async {
      final r = await repo.setSectionBlocked(id: 'u1', blocked: const {}, actorRole: UserRole.owner);
      expect(r.changed, isFalse);
      expect(await audits('user.section_blocked.changed'), isEmpty);
    });

    test('فكّ الحجب مع مفتاح المالك: يُوقَّع ويُتحقَّق منه بالمفتاح العام ويُدقَّق sys.sign.used', () async {
      await repo.setSectionBlocked(
          id: 'u1', blocked: {SectionBlock.fuel, SectionBlock.supply}, actorRole: UserRole.owner);

      final act = withKey();
      expect(await act.importPrivateKey(ownerPriv), isTrue);
      final r = await repo.setSectionBlocked(
        id: 'u1',
        blocked: {SectionBlock.supply}, // فُكّ fuel
        actorRole: UserRole.owner,
        actorEmail: 'boss@x',
        activation: act,
      );
      expect(r.removed, {SectionBlock.fuel});
      expect(r.signed, isTrue);
      expect(r.unsignedUnblock, isFalse);

      final u = await user('u1');
      final sig = OwnerSignature.parse(u.ownerSig)[OwnerSignature.sectionsKey]!;
      bool verify({String? json, String? id, int? at}) => OwnerSignature.verifySections(
            sigB64: sig,
            userId: id ?? u.id,
            blockedJson: json ?? u.sectionBlocked,
            updatedAtSec: at ?? OwnerSignature.seconds(u.updatedAt!),
            publicKey: ownerPub,
          );
      expect(verify(), isTrue, reason: 'التوقيع صحيح على userId|section_blocked|updatedAt');
      expect(verify(json: '[]'), isFalse, reason: 'قيمة أخرى');
      expect(verify(id: 'u2'), isFalse, reason: 'حساب آخر');
      expect(verify(at: OwnerSignature.seconds(u.updatedAt!) + 1), isFalse, reason: 'وقت آخر');
      expect(
        OwnerSignature.verifySections(
          sigB64: sig,
          userId: u.id,
          blockedJson: u.sectionBlocked,
          updatedAtSec: OwnerSignature.seconds(u.updatedAt!),
          publicKey: ESign.generateKeyPair().publicB64,
        ),
        isFalse,
        reason: 'مفتاح عام آخر',
      );

      final used = await audits('sys.sign.used');
      expect(used, hasLength(1));
      expect(used.single.risk, 'high');
    });

    test('فكّ الحجب بلا مفتاح: يُنفَّذ محليًّا بلا توقيع ويُنبَّه بأنه لن ينتشر', () async {
      await repo.setSectionBlocked(id: 'u1', blocked: {SectionBlock.fuel}, actorRole: UserRole.owner);

      final r = await repo.setSectionBlocked(
        id: 'u1',
        blocked: const {},
        actorRole: UserRole.owner,
        activation: withKey(), // لا مفتاح خاصًّا مستورَدًا
      );
      expect(r.changed, isTrue);
      expect(r.signed, isFalse);
      expect(r.unsignedUnblock, isTrue);

      final u = await user('u1');
      expect(u.sectionBlocked, '[]', reason: 'التغيير المحلي نافذ');
      expect(OwnerSignature.parse(u.ownerSig), isEmpty);
      expect(await audits('sys.sign.used'), isEmpty);
      final log = (await audits('user.section_blocked.changed')).last;
      expect(log.details, contains('"unsignedUnblock":true'));
    });

    test('إضافة حجبٍ بعد فكٍّ موقَّع تُسقط توقيع الأقسام القديم وتُبقي توقيع الدور', () async {
      final act = withKey();
      await act.importPrivateKey(ownerPriv);
      await repo.setSectionBlocked(id: 'u1', blocked: {SectionBlock.fuel}, actorRole: UserRole.owner);
      await repo.setSectionBlocked(id: 'u1', blocked: const {}, actorRole: UserRole.owner, activation: act);
      // توقيع دورٍ موجود (من الخطوة 3 مستقبلًا) يجب أن يبقى.
      final signed = await user('u1');
      await (db.update(db.users)..where((t) => t.id.equals('u1')))
          .write(UsersCompanion(ownerSig: Value(OwnerSignature.encode({...OwnerSignature.parse(signed.ownerSig), 'r': 'ROLESIG'}))));

      await repo.setSectionBlocked(id: 'u1', blocked: {SectionBlock.supply}, actorRole: UserRole.owner, activation: act);
      final sigs = OwnerSignature.parse((await user('u1')).ownerSig);
      expect(sigs.containsKey(OwnerSignature.sectionsKey), isFalse, reason: 'غطّى محتوىً قديمًا');
      expect(sigs['r'], 'ROLESIG');
    });
  });

  group('القشرة', () {
    late AppDatabase db;
    late AuthService auth;
    late String ownerId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      auth = AuthService(db);
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await auth.login('root', 'Test@12345');
      ownerId = auth.currentUser!.id;
    });

    tearDown(() => db.close());

    /// يُنشئ مديرًا عاديًّا (غير مالك) ويحجب عنه [blocked] ثم يُدخله.
    Future<void> loginAdminBlocked(Set<String> blocked, {String space = AppSpace.supply}) async {
      final id = await UsersRepo(db).createUser(
        username: 'ops',
        password: 'Test@12345',
        name: 'مدير',
        isAdmin: true,
        actorRole: UserRole.owner,
      );
      await UsersRepo(db).setSectionBlocked(id: id, blocked: blocked, actorRole: UserRole.owner);
      await auth.logout();
      await auth.login('ops', 'Test@12345');
      SharedPreferences.setMockInitialValues({'imdad.space.${auth.currentUser!.id}': space});
    }

    Widget host() => MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            Provider<AuthService>.value(value: auth),
            ChangeNotifierProvider<AutoSyncService>.value(value: AutoSyncService(db)),
            ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            home: Directionality(textDirection: TextDirection.rtl, child: HomeShell(onSignOut: () async {})),
          ),
        );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();
    }

    testWidgets('حجب fuel: المدير لا يرى القسم ولو كان محفوظًا، وصفحاته مرفوضة بالتنقّل المباشر', (tester) async {
      await tester.runAsync(() => loginAdminBlocked({SectionBlock.fuel}, space: AppSpace.fuel));
      final me = auth.currentUser!;
      expect(me.role, UserRole.admin);
      expect(auth.can(me, 'fuelMoves'), isFalse, reason: 'التنقل المباشر/الصلاحية مرفوضان');
      expect(auth.can(me, 'items'), isTrue, reason: 'الإمداد غير محجوب');

      await pump(tester);
      expect(tester.takeException(), isNull);
      // الاختيار المحفوظ (المحروقات) لا يُفتح: يسقط إلى الإمداد.
      expect(find.text('العمليات المخزنية'), findsWidgets);
      expect(find.text('حركة المحروقات'), findsNothing);
      expect(find.text('ادخل'), findsNothing, reason: 'قسمٌ واحد متاح ⇒ لا شاشة اختيار');
    });

    testWidgets('حجب supply: يبقى المحروقات وحده والإمداد مرفوض', (tester) async {
      await tester.runAsync(() => loginAdminBlocked({SectionBlock.supply}));
      expect(auth.can(auth.currentUser!, 'items'), isFalse);
      expect(auth.can(auth.currentUser!, 'fuelMoves'), isTrue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('حركة المحروقات'), findsWidgets);
      expect(find.text('العمليات المخزنية'), findsNothing);
    });

    testWidgets('حجب admin.users: قسم «المستخدمون» يختفي من داخل الإعدادات وبقية الأقسام تبقى', (tester) async {
      await tester.runAsync(() => loginAdminBlocked({SectionBlock.adminUsers}));
      await pump(tester);

      // التنقّل البرمجي كما تفعل الشاشات الأخرى (ImdNav) — قسم الإعدادات مطويٌّ في الشريط.
      Provider.of<ImdNav>(tester.element(find.byType(Scaffold).first), listen: false).go('settings');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('هوية النظام والشعار'), findsWidgets, reason: 'قسمٌ غير محجوب يبقى');
      expect(find.text('المستخدمون والصلاحيات'), findsNothing, reason: 'admin.users مخفيّ');
    });

    testWidgets('لا حجب للمالك: يرى كل الأقسام ولو خُزِّن له حجب', (tester) async {
      // حجبٌ مخزَّن مباشرةً في صف المالك (مزامنةٌ/تلاعب): لا أثر له.
      await tester.runAsync(() async {
        await (db.update(db.users)..where((t) => t.id.equals(ownerId)))
            .write(UsersCompanion(sectionBlocked: Value(SectionBlock.encode(SectionBlock.all))));
        await auth.logout();
        await auth.login('root', 'Test@12345');
      });
      SharedPreferences.setMockInitialValues({'imdad.space.${auth.currentUser!.id}': AppSpace.supply});
      expect(auth.currentUser!.role, UserRole.owner);
      expect(auth.can(auth.currentUser!, 'fuelMoves'), isTrue);
      expect(auth.can(auth.currentUser!, 'items'), isTrue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('العمليات المخزنية'), findsWidgets);

      // التنقّل البرمجي كما تفعل الشاشات الأخرى (ImdNav) — قسم الإعدادات مطويٌّ في الشريط.
      Provider.of<ImdNav>(tester.element(find.byType(Scaffold).first), listen: false).go('settings');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.text('المستخدمون والصلاحيات'), findsWidgets);
    });
  });
}
