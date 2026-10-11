import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/db/pre_migration_backup.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// ترحيل v25: عمودا `section_blocked` و`owner_sig` + النسخة الاحتياطية + ترقية المالك.
///
/// القاعدة الاصطناعية v24 تُبنى بأحدث مخطط ثم تُسحب منها الأعمدة الجديدة ويُخفَّض
/// طابَعها — فتطابق قاعدةً أنشأتها نسخةٌ سبقت v25. والفتح يمرّ بالإعداد الحقيقي
/// نفسه (`PreMigrationBackup.createIfNeeded` في `setup`) كما في الاتصال المشفَّر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('imdad_v25');
    file = File(p.join(dir.path, 'imdad.sqlite'));
    PreMigrationBackup.directoryProvider = () async => dir;
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // يبقى مقفلًا أحيانًا على ويندوز.
    }
  });

  /// يفتح القاعدة كما يفعل الاتصال الحقيقي: النسخة الاحتياطية في `setup` قبل الترحيل.
  AppDatabase open() => AppDatabase.forTesting(NativeDatabase(
        file,
        setup: (raw) => PreMigrationBackup.createIfNeeded(raw, file),
      ));

  /// قاعدة v24 بمستخدمين: تُنشأ بأحدث مخطط ثم تُرجَع إلى ما قبل v25.
  Future<void> makeV24({List<(String id, String username, String role)> users = const []}) async {
    final db = AppDatabase.forTesting(NativeDatabase(file));
    for (final (id, name, role) in users) {
      await db.into(db.users).insert(UsersCompanion.insert(id: id, username: name, role: Value(role)));
    }
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sql.sqlite3.open(file.path);
    raw.execute('ALTER TABLE users DROP COLUMN section_blocked');
    raw.execute('ALTER TABLE users DROP COLUMN owner_sig');
    raw.execute('PRAGMA user_version = 24');
    raw.dispose();
  }

  Future<Set<String>> userColumns(AppDatabase db) async =>
      {for (final r in await db.customSelect('PRAGMA table_info(users)').get()) r.read<String>('name')};

  List<File> backups() => [
        for (final e in dir.listSync())
          if (e is File && p.basename(e.path).contains('.pre-v') && !e.path.endsWith('.json')) e,
      ];

  test('المخطط الحالي 25 فأحدث', () {
    // v26 (تراكم المحروقات) فوق v25؛ هذا الملف يحرس ترحيل v25 وحده.
    expect(AppDatabase.kSchemaVersion, greaterThanOrEqualTo(25));
  });

  test('الترقية من v24 تضيف العمودين بقيمتيهما الافتراضيتين وتُبقي البيانات', () async {
    await makeV24(users: [('local-root', 'root', UserRole.admin), ('u1', 'ali', UserRole.user)]);

    final raw = sql.sqlite3.open(file.path);
    expect((raw.select('PRAGMA user_version').first.values.first as num).toInt(), 24);
    raw.dispose();

    final db = open();
    final cols = await userColumns(db);
    expect(cols, containsAll(['section_blocked', 'owner_sig']), reason: 'العمودان أُضيفا');

    final ali = await (db.select(db.users)..where((t) => t.username.equals('ali'))).getSingle();
    expect(ali.sectionBlocked, '[]', reason: 'افتراضي: لا حجب');
    expect(ali.ownerSig, '', reason: 'افتراضي: غير موقَّع');
    expect(ali.role, UserRole.user, reason: 'البيانات القائمة لم تُمسّ');
    expect((await db.select(db.users).get()).length, 2);

    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), AppDatabase.kSchemaVersion);
    await db.close();
  });

  test('مدير محلي وحيد يُرقّى مالكًا مرةً واحدة مع تدقيق، ولا تُكرَّر الترقية', () async {
    await makeV24(users: [('local-root', 'root', UserRole.admin), ('u1', 'ali', UserRole.user)]);

    var db = open();
    final root = await (db.select(db.users)..where((t) => t.username.equals('root'))).getSingle();
    expect(root.role, UserRole.owner, reason: 'المدير المحلي الوحيد صار مالكًا');
    final audits = await (db.select(db.auditLogs)..where((t) => t.action.equals('owner.auto_promoted'))).get();
    expect(audits, hasLength(1));
    await db.close();

    // إعادة الفتح لا تُعيد الترقية (طابَع 25 والمالك قائم).
    db = open();
    expect(await (db.select(db.auditLogs)..where((t) => t.action.equals('owner.auto_promoted'))).get(), hasLength(1));
    await db.close();
  });

  test('أكثر من مدير ⇒ لا ترقية تلقائية (لا مالك يُخمَّن)', () async {
    await makeV24(users: [('local-a', 'a', UserRole.admin), ('local-b', 'b', UserRole.admin)]);
    final db = open();
    final roles = [for (final u in await db.select(db.users).get()) u.role];
    expect(roles, everyElement(UserRole.admin));
    await db.close();
  });

  test('مدير غير محلي (وصل بالمزامنة) لا يُرقّى', () async {
    await makeV24(users: [('remote-77', 'far', UserRole.admin)]);
    final db = open();
    expect((await db.select(db.users).getSingle()).role, UserRole.admin);
    await db.close();
  });

  test('نسخة احتياطية كاملة قبل الترحيل، وتدقيق created مرةً واحدة', () async {
    await makeV24(users: [('local-root', 'root', UserRole.admin)]);
    final sizeBefore = file.lengthSync();

    var db = open();
    await db.customSelect('SELECT 1').get(); // القاعدة تُفتح عند أول استعلام
    final copies = backups();
    expect(copies, hasLength(1), reason: 'نسخة واحدة قبل الترحيل');

    // النسخة هي حالة v24: بلا العمودين الجديدين وبطابَع 24 وببيانات المستخدم.
    final c = sql.sqlite3.open(copies.single.path);
    expect((c.select('PRAGMA user_version').first.values.first as num).toInt(), 24);
    final names = {for (final r in c.select('PRAGMA table_info(users)')) r['name']};
    expect(names, isNot(contains('section_blocked')));
    expect(c.select('SELECT username FROM users').map((r) => r['username']), ['root']);
    c.dispose();
    expect(copies.single.lengthSync(), greaterThan(0));
    expect(sizeBefore, greaterThan(0));

    final created = await (db.select(db.auditLogs)..where((t) => t.action.equals(PreMigrationBackup.createdAction))).get();
    expect(created, hasLength(1));
    await db.close();

    // إعادة الفتح: لا نسخة ثانية ولا تدقيق ثانٍ.
    db = open();
    await db.customSelect('SELECT 1').get();
    expect(backups(), hasLength(1));
    expect(await (db.select(db.auditLogs)..where((t) => t.action.equals(PreMigrationBackup.createdAction))).get(),
        hasLength(1));
    await db.close();
  });

  test('إعادة الفتح بعد الترقية، وبعد تخفيض الطابَع، لا ترمي duplicate column', () async {
    await makeV24(users: [('u1', 'ali', UserRole.user)]);
    var db = open();
    await db.customSelect('SELECT 1').get();
    await db.close();

    // تنقّل بين نسختين: الطابَع يرجع إلى 24 والعمودان قائمان.
    final raw = sql.sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 24');
    raw.dispose();

    await expectLater(() async {
      db = open();
      await db.customSelect('SELECT 1').get();
      await db.close();
    }(), completes, reason: 'الترقية أضافت عمودًا قائمًا فرمت duplicate column');

    db = open();
    expect(await userColumns(db), containsAll(['section_blocked', 'owner_sig']));
    expect((await db.select(db.users).get()).single.username, 'ali');
    await db.close();
  });

  test('قاعدة جديدة (بلا ترحيل) تُنشأ بالعمودين ولا نسخة احتياطية ولا ترقية', () async {
    final db = open();
    expect(await userColumns(db), containsAll(['section_blocked', 'owner_sig']));
    expect(backups(), isEmpty);
    expect(await db.select(db.auditLogs).get(), isEmpty);
    await db.close();
  });
}
