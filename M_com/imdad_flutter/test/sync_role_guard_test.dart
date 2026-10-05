import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/core/security/owner_signature.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// حماية المزامنة (G): صفٌّ وارد يرفع دورًا إلى مدير/مالك أو يفكّ حجبًا بلا توقيع
/// مالكٍ صحيح يُرفض ويُدقَّق. الاستعادة من ملف مستثناة (`sys.backup`) ومدقَّقة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String ownerPub;
  late String ownerPriv;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final pair = ESign.generateKeyPair();
    ownerPub = pair.publicB64;
    ownerPriv = pair.privateHex;
    dir = Directory.systemTemp.createTempSync('imdad_g');
  });

  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // يبقى مقفلًا أحيانًا على ويندوز.
    }
  });

  LegacyImporter importer() => LegacyImporter(db, ownerPublicKey: ownerPub);

  String sign(Uint8List digest) => base64Url.encode(ESign.signRawWithKey(privateHex: ownerPriv, digest: digest));

  String roleSig(String id, String role, int sec) =>
      sign(OwnerSignature.roleDigest(userId: id, role: role, updatedAtSec: sec));
  String sectionsSig(String id, String json, int sec) =>
      sign(OwnerSignature.sectionsDigest(userId: id, blockedJson: json, updatedAtSec: sec));

  const sec = 1790000000;

  Map<String, dynamic> row(
    String id,
    String role, {
    Map<String, String>? sigs,
    String? blocked,
    int? at = sec,
  }) =>
      {
        'id': id,
        'username': id,
        'role': role,
        'saltHex': 'aa',
        'hashHex': 'bb',
        if (at != null) 'updatedAt': at,
        if (blocked != null) 'sectionBlocked': blocked,
        if (sigs != null) 'ownerSig': OwnerSignature.encode(sigs),
      };

  /// علامات دمجٍ واردة أحدث من المحلية: وإلا تجاوز الدمج صفوفًا قائمة محليًّا (المحلي «أحدث»).
  List<Map<String, dynamic>> marks(Iterable<String> ids) => [
        for (final id in ids) {'entity': 'users', 'rowId': id, 'updatedAt': 99999999999999},
      ];

  Future<User?> user(String id) => (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<List<AuditLog>> audits(String action) =>
      (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get();

  group('الحالات الخمس المطلوبة', () {
    test('1) user بلا توقيع ⇒ يُقبل', () async {
      final r = await importer().importJson({'users': [row('u1', 'user')]});
      expect(r.rejectedUsers, isEmpty);
      expect((await user('u1'))?.role, 'user');
      expect(await audits('sync.role_rejected'), isEmpty);
    });

    test('2) admin بلا توقيع ⇒ يُرفض ويُدقَّق بخطورة عالية', () async {
      final r = await importer().importJson({'users': [row('a1', 'admin')]});
      expect(await user('a1'), isNull, reason: 'لم يُكتب');
      expect(r.rejectedUsers, hasLength(1));
      expect(r.rejectedUsers.single.kind, 'role');
      final log = await audits('sync.role_rejected');
      expect(log, hasLength(1));
      expect(log.single.risk, 'high');
      expect(log.single.details, contains('"incomingRole":"admin"'));
    });

    test('3) owner بلا توقيع ⇒ يُرفض', () async {
      final r = await importer().importJson({'users': [row('o1', 'owner')]});
      expect(await user('o1'), isNull);
      expect(r.rejectedUsers.single.reason, contains('owner'));
      expect(await audits('sync.role_rejected'), hasLength(1));
    });

    test('4) owner مع توقيع صحيح ⇒ يُقبل ويُخزَّن توقيعه وختمه', () async {
      final r = await importer().importJson({
        'users': [row('o1', 'owner', sigs: {'r': roleSig('o1', 'owner', sec)})]
      });
      expect(r.rejectedUsers, isEmpty);
      final u = (await user('o1'))!;
      expect(u.role, 'owner');
      expect(OwnerSignature.seconds(u.updatedAt!), sec, reason: 'الختم يُحفظ ليتحقق منه الجهاز التالي');
      expect(OwnerSignature.parse(u.ownerSig)['r'], isNotEmpty);
      expect(await audits('sync.role_rejected'), isEmpty);
    });

    test('5) owner مع توقيع منقول لصفٍّ آخر ⇒ يُرفض', () async {
      final r = await importer().importJson({
        'users': [row('mallory', 'owner', sigs: {'r': roleSig('boss', 'owner', sec)})]
      });
      expect(await user('mallory'), isNull);
      expect(r.rejectedUsers.single.id, 'mallory');
    });
  });

  group('حالات حدّية للدور', () {
    test('توقيع مدير لا يرفع صاحبه إلى مالك', () async {
      final r = await importer().importJson({
        'users': [row('x', 'owner', sigs: {'r': roleSig('x', 'admin', sec)})]
      });
      expect(r.rejectedUsers, hasLength(1));
    });

    test('توقيعٌ بوقتٍ مختلف أو بمفتاحٍ آخر ⇒ يُرفض', () async {
      final r = await importer().importJson({
        'users': [
          row('t1', 'admin', sigs: {'r': roleSig('t1', 'admin', sec)}, at: sec + 1),
          row('t2', 'admin', sigs: {'r': roleSig('t2', 'admin', sec)}, at: null),
        ]
      });
      expect(r.rejectedUsers.map((e) => e.id), containsAll(['t1', 't2']));
      final other = LegacyImporter(db, ownerPublicKey: ESign.generateKeyPair().publicB64);
      final r2 = await other.importJson({
        'users': [row('t3', 'admin', sigs: {'r': roleSig('t3', 'admin', sec)})]
      });
      expect(r2.rejectedUsers, hasLength(1), reason: 'مفتاحٌ عامٌّ آخر');
    });

    test('مديرٌ قائم محليًّا يصله صفُّه بلا توقيع ⇒ يُقبل (لا رفع)', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'a1', username: 'a1', role: const Value('admin')));
      final r = await importer().importJson({'users': [row('a1', 'admin')], 'syncMarks': marks(['a1'])});
      expect(r.rejectedUsers, isEmpty);
    });

    test('الخفض بلا توقيع مقبول (مالك/مدير ← مستخدم)', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'a1', username: 'a1', role: const Value('admin')));
      final r = await importer().importJson({'users': [row('a1', 'user')], 'syncMarks': marks(['a1'])});
      expect(r.rejectedUsers, isEmpty);
      expect((await user('a1'))!.role, 'user');
    });

    test('مستخدم عادي يُرفع إلى مدير بلا توقيع ⇒ يُرفض ويبقى مستخدمًا', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u1', username: 'u1'));
      final r = await importer().importJson({'users': [row('u1', 'admin')], 'syncMarks': marks(['u1'])});
      expect(r.rejectedUsers, hasLength(1));
      expect((await user('u1'))!.role, 'user');
    });
  });

  group('فكّ الحجب', () {
    Future<void> seedBlocked(String blocked) => db.into(db.users).insert(
        UsersCompanion.insert(id: 'u1', username: 'u1', sectionBlocked: Value(blocked)));

    test('فكّ بلا توقيع ⇒ يُرفض ويبقى الحجب', () async {
      await seedBlocked('["fuel"]');
      final r = await importer().importJson({'users': [row('u1', 'user', blocked: '[]')], 'syncMarks': marks(['u1'])});
      expect(r.rejectedUsers.single.kind, 'unblock');
      expect((await user('u1'))!.sectionBlocked, '["fuel"]');
      expect(await audits('sync.role_rejected'), hasLength(1));
    });

    test('فكّ بتوقيعٍ صحيح ⇒ يُقبل', () async {
      await seedBlocked('["fuel"]');
      final r = await importer().importJson({
        'users': [row('u1', 'user', blocked: '[]', sigs: {'s': sectionsSig('u1', '[]', sec)})],
        'syncMarks': marks(['u1']),
      });
      expect(r.rejectedUsers, isEmpty);
      expect((await user('u1'))!.sectionBlocked, '[]');
    });

    test('فكّ بتوقيعٍ منقول من حسابٍ آخر أو لقيمةٍ أخرى ⇒ يُرفض', () async {
      await seedBlocked('["fuel","supply"]');
      final r = await importer().importJson({
        'users': [
          row('u1', 'user', blocked: '["supply"]', sigs: {'s': sectionsSig('other', '["supply"]', sec)}),
        ],
        'syncMarks': marks(['u1']),
      });
      expect(r.rejectedUsers, hasLength(1), reason: 'حساب آخر');
      final r2 = await importer().importJson({
        'users': [
          row('u1', 'user', blocked: '["supply"]', sigs: {'s': sectionsSig('u1', '[]', sec)}),
        ],
        'syncMarks': marks(['u1']),
      });
      expect(r2.rejectedUsers, hasLength(1), reason: 'قيمة أخرى');
      expect((await user('u1'))!.sectionBlocked, '["fuel","supply"]');
    });

    test('إضافة حجبٍ بلا توقيع ⇒ تُقبل، وغياب الحقل (نظيرٌ أقدم) لا يمسّ الحجب القائم', () async {
      await seedBlocked('["fuel"]');
      final add = await importer().importJson({'users': [row('u1', 'user', blocked: '["fuel","supply"]')], 'syncMarks': marks(['u1'])});
      expect(add.rejectedUsers, isEmpty);
      expect((await user('u1'))!.sectionBlocked, '["fuel","supply"]');

      final old = await importer().importJson({'users': [row('u1', 'user')], 'syncMarks': marks(['u1'])}); // بلا sectionBlocked
      expect(old.rejectedUsers, isEmpty);
      expect((await user('u1'))!.sectionBlocked, '["fuel","supply"]', reason: 'الغياب ليس فكًّا');
    });
  });

  group('الاستعادة من ملف مستثناة ومدقَّقة', () {
    test('مديرٌ بلا توقيع يُستعاد من ملف، ويُسجَّل backup.restore بالاسم والعدد', () async {
      final f = File(p.join(dir.path, 'نسخة-أكتوبر.imdbk'))
        ..writeAsStringSync(jsonEncode({
          'users': [row('a1', 'admin'), row('u1', 'user')],
        }));
      final r = await importer().importFile(f, actorEmail: 'boss@x');

      expect(r.rejectedUsers, isEmpty, reason: 'الاستعادة موثوقة (sys.backup)');
      expect((await user('a1'))!.role, 'admin');

      final log = await audits('backup.restore');
      expect(log, hasLength(1));
      expect(log.single.risk, 'high');
      expect(log.single.actorEmail, 'boss@x');
      expect(log.single.details, contains('نسخة-أكتوبر.imdbk'));
      expect(log.single.details, contains('"users":2'));
      expect(log.single.details, contains('"rejected":0'));
    });

    test('الصفوف التي تجاوزها الدمج (المحلي أحدث) تُحصى في التدقيق لا كرفضٍ أمني', () async {
      // الصفّ المحلي له علامة دمجٍ بحكم المشغّل؛ والحمولة بلا علامةٍ له ⇒ المحلي أحدث ويُتجاوز.
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u1', username: 'u1'));
      final f = File(p.join(dir.path, 'b.imdbk'))..writeAsStringSync(jsonEncode({'users': [row('u1', 'user'), row('u2', 'user')]}));
      final r = await importer().importFile(f);

      expect(r.usersSkipped, 1);
      expect(r.rejectedUsers, isEmpty);
      final log = (await audits('backup.restore')).single;
      expect(log.details, contains('"skipped":1'));
      expect(log.details, contains('"rejected":0'));
    });
  });

  group('من الإصدار إلى الاستقبال (طرفٌ لطرف)', () {
    test('مديرٌ يوقّعه المالك على جهاز الإدارة يقبله جهازٌ جديدٌ بالمزامنة', () async {
      // جهاز الإدارة: مفتاح المالك مستورَد.
      final adminDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(adminDb.close);
      final act = DeviceActivation(adminDb, ownerPublicKey: ownerPub);
      expect(await act.importPrivateKey(ownerPriv), isTrue);
      final repo = UsersRepo(adminDb);
      await repo.createUser(
          username: 'boss', password: 'Test@12345', name: 'م', isAdmin: true, actorRole: UserRole.owner);
      // مفتاح المالك على هذا الجهاز ⇒ وُقِّع دورُ المدير الجديد عند إنشائه.
      final created = (await (adminDb.select(adminDb.users)..where((t) => t.id.equals('local-boss'))).getSingle());
      expect(OwnerSignature.parse(created.ownerSig)['r'], isNotEmpty);
      // ومديرٌ قديمٌ بلا توقيعٍ ولا ختم يُوقَّع بالدفعة (مرةً بعد الترقية إلى v25).
      await adminDb.into(adminDb.users).insert(UsersCompanion.insert(id: 'old-admin', username: 'old', role: const Value('admin')));
      expect(await repo.signPrivilegedUsers(actorRole: UserRole.owner, activation: act), 1);
      expect(await repo.signPrivilegedUsers(actorRole: UserRole.owner, activation: act), 0, reason: 'إعادة الدفعة لا تغيّر شيئًا');

      final exported = await DataExporter(adminDb).toMap(includeUsers: true);
      final r = await importer().importJson(exported);
      expect(r.rejectedUsers, isEmpty, reason: 'صفوفٌ موقَّعة صحيحة');
      expect((await user('local-boss'))!.role, 'admin');
      expect((await user('old-admin'))!.role, 'admin');

      // وبلا توقيعٍ على المصدر يُرفض عند المستقبِل.
      final unsigned = await DataExporter(adminDb).toMap(includeUsers: true);
      for (final u in unsigned['users'] as List) {
        (u as Map)['ownerSig'] = '';
        u['id'] = 'copy-${u['id']}';
        u['username'] = 'copy-${u['username']}';
      }
      final r2 = await importer().importJson(unsigned);
      expect(r2.rejectedUsers, hasLength(2));
    });

    test('تجديد التوقيع بعد تعديل الحساب يُبقيه صالحًا (updatedAt جزءٌ من البصمة)', () async {
      final act = DeviceActivation(db, ownerPublicKey: ownerPub);
      await act.importPrivateKey(ownerPriv);
      final repo = UsersRepo(db);
      await repo.createUser(username: 'adm', password: 'Test@12345', name: 'م', isAdmin: true, actorRole: UserRole.owner);
      await repo.signPrivilegedUsers(actorRole: UserRole.owner, activation: act);
      final before = (await user('local-adm'))!;
      final sigBefore = OwnerSignature.parse(before.ownerSig)['r']!;
      expect(
        OwnerSignature.verifyRole(
            sigB64: sigBefore,
            userId: before.id,
            role: before.role,
            updatedAtSec: OwnerSignature.seconds(before.updatedAt!),
            publicKey: ownerPub),
        isTrue,
      );
      final used = await audits('sys.sign.used');
      expect(used, isNotEmpty);
      expect(used.first.risk, 'high');
    });
  });

  group('تحديث المستخدم الحالي في الذاكرة', () {
    test('تغيّر دوره أو حجب أقسامه في القاعدة يُحدّث currentUser ويرفع userVersion', () async {
      final auth = AuthService(db);
      await auth.createAdmin(username: 'root', password: 'Test@12345');
      await UsersRepo(db).createUser(username: 'ops', password: 'Test@12345', name: 'م');
      expect((await auth.login('ops', 'Test@12345')).status, AuthStatus.ok);
      expect(auth.currentUser!.sectionBlocked, '[]');
      final v0 = auth.userVersion.value;

      // يصل حجبٌ بالمزامنة (كتابةٌ في القاعدة لا عبر المستودع).
      await (db.update(db.users)..where((t) => t.username.equals('ops')))
          .write(const UsersCompanion(sectionBlocked: Value('["fuel"]')));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(auth.currentUser!.sectionBlocked, '["fuel"]');
      expect(auth.userVersion.value, greaterThan(v0));
      expect(auth.can(auth.currentUser!, 'fuelMoves'), isFalse, reason: 'الحجب نافذٌ فورًا');

      // تعديل لا يمسّ الدور ولا الحجب لا يرفع النسخة (لا إعادة بناء بلا داعٍ).
      final v1 = auth.userVersion.value;
      await (db.update(db.users)..where((t) => t.username.equals('ops')))
          .write(const UsersCompanion(name: Value('اسم جديد')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(auth.userVersion.value, v1);

      await auth.logout();
    });
  });
}
