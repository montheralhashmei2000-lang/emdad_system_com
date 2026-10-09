import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/data/sync/sync_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ما يحمله جهازٌ مقترن ولا يمرّ بحارس الحسابات: شواهد الحذف، وسجل التدقيق،
/// وانتحال اسم الدخول. الختم في كل ذلك بيد المرسِل، فكل اختبارٍ هنا يرسل ختمًا
/// من المستقبل — وإلا رفض «الأحدث يفوز» الحمولةَ قبل أن تبلغ الحارس المُختبَر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String ownerPub;
  late String ownerPriv;

  /// ختمٌ بعيد في المستقبل (سنة ٢٠٩٦).
  const future = 4000000000000;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final pair = ESign.generateKeyPair();
    ownerPub = pair.publicB64;
    ownerPriv = pair.privateHex;
  });

  tearDown(() => db.close());

  LegacyImporter importer([AppDatabase? on]) => LegacyImporter(on ?? db, ownerPublicKey: ownerPub);

  Map<String, dynamic> tombstone(String entity, String rowId) =>
      {'entity': entity, 'rowId': rowId, 'updatedAt': future, 'deletedAt': future};

  Future<User?> user(String id) => (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<List<AuditLog>> audits(String action) =>
      (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get();
  Future<SyncMark?> markOf(String entity, String rowId) async =>
      (await SyncMarks(db).snapshot())['$entity/$rowId'];

  group('شواهد الحذف', () {
    test('حذف المالك ⇒ مرفوض والصف باقٍ', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'o1', username: 'boss', role: const Value('owner')));
      final r = await importer().importJson({'syncMarks': [tombstone('users', 'o1')]});
      expect(await user('o1'), isNotNull);
      expect(r.warnings.join(), contains('رُفض'));
      expect(await audits('sync.tombstone_rejected'), hasLength(1));
    });

    test('حذف مدير ⇒ مرفوض، وعلامته المحلية لا تأخذ ختم الشاهد', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'a1', username: 'a1', role: const Value('admin')));
      final before = await markOf('users', 'a1');
      await importer().importJson({'syncMarks': [tombstone('users', 'a1')]});
      expect(await user('a1'), isNotNull);
      final after = await markOf('users', 'a1');
      expect(after?.isDeleted, isFalse, reason: 'الشاهد المرفوض ثُبِّت محليًّا فسيسافر إلى غيرنا');
      expect(after?.updatedAt, before?.updatedAt);
    });

    test('حذف مستخدم عادي ⇒ ينتشر كما كان (الموظف المفصول لا يبقى يدخل)', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u1', username: 'clerk'));
      await importer().importJson({'syncMarks': [tombstone('users', 'u1')]});
      expect(await user('u1'), isNull);
      expect(await audits('sync.tombstone_rejected'), isEmpty);
    });

    test('حذف صف تدقيق ⇒ مرفوض صامتًا (تقليم الأجهزة الأخرى شرعيٌّ فلا يُدقَّق)', () async {
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: 'al1', action: 'sync.role_rejected', risk: const Value('high')));
      await importer().importJson({'syncMarks': [tombstone('audit_logs', 'al1')]});
      expect(await (db.select(db.auditLogs)..where((t) => t.id.equals('al1'))).getSingleOrNull(), isNotNull);
      expect(await audits('sync.tombstone_rejected'), isEmpty);
    });

    for (final key in ['sync', 'device', 'esign', 'authLocks']) {
      test('حذف مفتاح الإعدادات المحلي «$key» ⇒ مرفوض', () async {
        await SettingsRepo(db).write(key, {'x': 1});
        await importer().importJson({'syncMarks': [tombstone('app_settings', key)]});
        expect(await SettingsRepo(db).read(key), {'x': 1});
        expect(await audits('sync.tombstone_rejected'), hasLength(1));
      });
    }

    test('سجلّ الثقة يبقى بعد شاهد حذفه، والمزامنة تجد أقرانها', () async {
      await SyncTrust(db).remember(TrustedPeer(deviceId: 'HQ000001', key: _fakeKey(7)));
      await importer().importJson({'syncMarks': [tombstone('app_settings', SyncTrust.settingsKey)]});
      expect((await SyncTrust(db).peers()).single.deviceId, 'HQ000001');
    });

    test('إعدادٌ مزامَن عادي يُحذف بشاهده كما كان', () async {
      await SettingsRepo(db).write('org', {'name': 'الوحدة'});
      await importer().importJson({'syncMarks': [tombstone('app_settings', 'org')]});
      expect(await SettingsRepo(db).read('org'), isEmpty);
    });

    test('ألف شاهد مرفوض ⇒ صفُّ تدقيقٍ واحد لا ألف (المحمي لا يُقلَّم)', () async {
      for (var i = 0; i < 20; i++) {
        await db.into(db.users).insert(UsersCompanion.insert(id: 'a$i', username: 'a$i', role: const Value('admin')));
      }
      await importer().importJson({
        'syncMarks': [for (var i = 0; i < 20; i++) tombstone('users', 'a$i')],
      });
      expect(await audits('sync.tombstone_rejected'), hasLength(1));
    });
  });

  group('سجل التدقيق', () {
    test('صفٌّ قائم لا يُعاد كتابته بختمٍ من المستقبل', () async {
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: 'al1', action: 'backup.restore', summary: const Value('الأصل'), risk: const Value('high')));
      await importer().importJson({
        'auditLogs': [
          {'id': 'al1', 'action': 'noop', 'summary': 'مزوَّر', 'risk': 'normal'},
        ],
        'syncMarks': [
          {'entity': 'audit_logs', 'rowId': 'al1', 'updatedAt': future},
        ],
      });
      final row = await (db.select(db.auditLogs)..where((t) => t.id.equals('al1'))).getSingle();
      expect((row.action, row.summary, row.risk), ('backup.restore', 'الأصل', 'high'));
    });

    test('الصف الجديد يُدرَج كما كان (تجميع نشاط الوحدة عند الإدارة)', () async {
      await importer().importJson({
        'auditLogs': [
          {'id': 'al9', 'action': 'ISSUE_CREATED', 'summary': 'من الفرع'},
        ],
      });
      expect(await (db.select(db.auditLogs)..where((t) => t.id.equals('al9'))).getSingleOrNull(), isNotNull);
    });
  });

  group('انتزاع اسم الدخول', () {
    test('حسابٌ عاديٌّ باسم المدير بمعرّف local- وختمٍ من المستقبل ⇒ يُرفض، ويدخل المدير بكلمته', () async {
      final auth = AuthService(db);
      await auth.createAdmin(username: 'admin', password: 'RealPass123');
      await auth.logout();

      final r = await importer().importJson({
        'users': [
          {
            'id': 'local-x',
            'username': 'Admin',
            'role': 'user',
            'saltHex': '00' * 16,
            'hashHex': '11' * 32,
            'iterations': 310000,
            'updatedAt': future ~/ 1000,
          },
        ],
        'syncMarks': [
          {'entity': 'users', 'rowId': 'local-x', 'updatedAt': future},
        ],
      });

      expect(r.rejectedUsers.single.kind, 'username');
      expect(await user('local-x'), isNull);
      final login = await auth.login('admin', 'RealPass123');
      expect(login.isOk, isTrue, reason: 'المدير الحقيقي رُدّ بعد وصول الدخيل');
    });

    test('مستخدمٌ عاديٌّ يحمل اسم مستخدمٍ عادي آخر ⇒ لا يُمسّ (الحارس للمميَّز وحده)', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u1', username: 'clerk'));
      final r = await importer().importJson({
        'users': [
          {'id': 'u2', 'username': 'clerk', 'role': 'user'},
        ],
      });
      expect(r.rejectedUsers, isEmpty);
    });
  });

  group('حذف مدير بين جهازين: تقاعدٌ موقَّع ثم حذف', () {
    late AppDatabase branch;

    setUp(() => branch = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => branch.close());

    Future<void> syncToBranch() async =>
        importer(branch).importJson(await DataExporter(db).toMap(includeUsers: true));

    Future<User?> onBranch(String id) => (branch.select(branch.users)..where((t) => t.id.equals(id))).getSingleOrNull();

    test('الحذف الأول يُقاعد في كل مكان، والثاني يحذف في كل مكان', () async {
      expect(await DeviceActivation(db, ownerPublicKey: ownerPub).importPrivateKey(ownerPriv), isTrue);
      final repo = UsersRepo(db);
      await repo.createUser(username: 'keep', password: 'Test@12345', name: 'k', isAdmin: true);
      final gone = await repo.createUser(username: 'gone', password: 'Test@12345', name: 'g', isAdmin: true);
      await syncToBranch();
      expect((await onBranch(gone))?.role, 'admin');

      // الحذف الأول: تقاعد — الصف باقٍ معطَّلًا مخفوضًا، موقَّعًا.
      await Future<void>.delayed(const Duration(seconds: 1)); // الختم بالثواني في التوقيع
      expect(await repo.deleteUser(gone), isTrue);
      final retired = (await repo.byId(gone))!;
      expect((retired.role, retired.active), ('user', false));
      expect((await (db.select(db.auditLogs)..where((t) => t.action.equals('USER_RETIRED'))).get()), hasLength(1));

      await syncToBranch();
      final there = (await onBranch(gone))!;
      expect((there.role, there.active), ('user', false), reason: 'التقاعد الموقَّع لم يصل إلى الفرع');

      // الحذف الثاني: حسابٌ عادي ينتشر شاهده.
      expect(await repo.deleteUser(gone), isTrue);
      expect(await repo.byId(gone), isNull);
      await syncToBranch();
      expect(await onBranch(gone), isNull, reason: 'الحذف الثاني لم يبلغ الفرع');
    });

    test('بلا تقاعد: شاهد حذف مديرٍ مباشر يُرفض في الفرع (لماذا التقاعد لازم)', () async {
      await db.into(db.users).insert(UsersCompanion.insert(id: 'a1', username: 'a1', role: const Value('admin')));
      await branch.into(branch.users).insert(UsersCompanion.insert(id: 'a1', username: 'a1', role: const Value('admin')));
      await (db.delete(db.users)..where((t) => t.id.equals('a1'))).go();
      await syncToBranch();
      expect(await onBranch('a1'), isNotNull);
    });
  });
}

/// مفتاحٌ وهميٌّ من بايتٍ مكرَّر.
Uint8List _fakeKey(int b) => Uint8List.fromList(List.filled(32, b));
