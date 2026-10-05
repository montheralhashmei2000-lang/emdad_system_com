import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/backup/backup_scheduler.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/db/pre_migration_backup.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// النسخة الاحتياطية الكاملة قبل ترحيل v25 + تسجيلها وحذفها + المجدول الهجين.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File dbFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('imdad_premig');
    dbFile = File(p.join(dir.path, 'imdad.sqlite'));
    PreMigrationBackup.directoryProvider = () async => dir;
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // يبقى مقفلًا أحيانًا على ويندوز.
    }
  });

  /// قاعدة بإصدار [version] وبياناتٍ في WAL **لم تُفرَّغ** بعد في الملف الرئيسي.
  sql.Database makeDb(int version, {bool wal = true}) {
    final db = sql.sqlite3.open(dbFile.path);
    if (wal) db.execute('PRAGMA journal_mode = WAL');
    db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
    db.execute("INSERT INTO t (v) VALUES ('قبل'), ('الترحيل')");
    db.execute('PRAGMA user_version = $version');
    return db;
  }

  List<File> backups() => [
        for (final e in dir.listSync())
          if (e is File && p.basename(e.path).contains('.pre-v25-') && !e.path.endsWith('.json')) e,
      ];

  group('الإنشاء قبل الترحيل', () {
    test('قاعدة v24 تُنسخ كاملةً بما فيها ما لم يُفرَّغ من WAL، ويُكتب وصفها', () {
      final db = makeDb(24);
      final copy = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25);
      db.dispose();

      expect(copy, isNotNull);
      expect(copy!.existsSync(), isTrue);
      expect(p.basename(copy.path), startsWith('imdad.sqlite.pre-v25-'));

      // النسخة قاعدةٌ صالحة بالبيانات نفسها (لا تفقد آخر كتابات WAL).
      final c = sql.sqlite3.open(copy.path);
      expect(c.select('SELECT v FROM t ORDER BY id').map((r) => r['v']).toList(), ['قبل', 'الترحيل']);
      expect((c.select('PRAGMA user_version').first.values.first as num).toInt(), 24);
      c.dispose();

      final marker = jsonDecode(File('${copy.path}.json').readAsStringSync()) as Map<String, dynamic>;
      expect(marker['fromVersion'], 24);
      expect(marker['toVersion'], 25);
      expect(marker['openedOkAt'], isNull, reason: 'لم يُفتح بالمخطط الجديد بعد');
    });

    test('لا نسخة لقاعدة جديدة (0) ولا لمحدَّثة (≥ الهدف)', () {
      final db = makeDb(0);
      expect(PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25), isNull);
      db.execute('PRAGMA user_version = 25');
      expect(PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25), isNull);
      db.dispose();
      expect(backups(), isEmpty);
    });

    test('خاملةٌ قبل أن يبلغ التطبيق مخطط النسخة (لا ترحيل = لا نسخة)', () {
      final db = makeDb(24);
      expect(PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 24), isNull);
      db.dispose();
      expect(backups(), isEmpty);
    });

    test('إقلاعٌ فاشل ثانٍ لا يستبدل النسخة الأولى بنسخةٍ من قاعدةٍ قد تضرّرت', () {
      final db = makeDb(24);
      final first = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25);
      final second = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25);
      db.dispose();
      expect(first, isNotNull);
      expect(second, isNull);
      expect(backups().length, 1);
    });

    test('فشل النسخ يرمي رسالة واضحة ولا يترك ملفاتٍ نصف مكتوبة', () {
      final db = makeDb(24);
      // مسارٌ غير موجود: النسخ يفشل، وعلى الاستدعاء أن يمنع الترحيل بالرمي.
      final ghost = File(p.join(dir.path, 'gone', 'imdad.sqlite'));
      expect(
        () => PreMigrationBackup.createIfNeeded(db, ghost, target: 25, schemaVersion: 25),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('لم تبدأ الترقية'))),
      );
      db.dispose();
      expect(backups(), isEmpty);
      expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.part')), isEmpty);
    });
  });

  group('التسوية بعد الفتح: التدقيق والحذف بعد 7 أيام', () {
    late AppDatabase appDb;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      // يُفتح قبل إنشاء أي نسخة: فتحُ القاعدة ينادي `settle` تلقائيًّا (بمخطط 25)،
      // ولا يجوز أن يلتقط نسخة الاختبار قبل أن يستدعيها الاختبار بوقته وإصداره.
      await appDb.customSelect('SELECT 1').get();
    });
    tearDown(() => appDb.close());

    Future<List<String>> audits(String action) async => [
          for (final a in await appDb.select(appDb.auditLogs).get())
            if (a.action == action) a.summary,
        ];

    test('تُسجَّل مرةً واحدة ويُعلَّم نجاح الفتح، ولا تُحذف قبل 7 أيام', () async {
      final db = makeDb(24);
      final copy = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25)!;
      db.dispose();

      final t0 = DateTime(2026, 10, 1, 9);
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0);
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0.add(const Duration(days: 3)));

      expect(await audits(PreMigrationBackup.createdAction), hasLength(1), reason: 'تُسجَّل مرةً لا كل إقلاع');
      expect((await audits(PreMigrationBackup.createdAction)).single, contains(p.basename(copy.path)));
      expect(copy.existsSync(), isTrue);

      // بعد 6 أيام و23 ساعة: باقية.
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0.add(const Duration(days: 6, hours: 23)));
      expect(copy.existsSync(), isTrue);
      expect(await audits(PreMigrationBackup.deletedAction), isEmpty);
    });

    test('بعد 7 أيام من نجاح الفتح تُحذف مع وصفها ويُسجَّل الحذف', () async {
      final db = makeDb(24);
      final copy = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25)!;
      db.dispose();

      final t0 = DateTime(2026, 10, 1, 9);
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0);
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0.add(const Duration(days: 7)));

      expect(copy.existsSync(), isFalse);
      expect(File('${copy.path}.json').existsSync(), isFalse);
      expect(await audits(PreMigrationBackup.deletedAction), hasLength(1));
      // وبعد الحذف لا يتكرر تسجيلٌ ولا خطأ.
      await PreMigrationBackup.settle(appDb, schemaVersion: 25, now: t0.add(const Duration(days: 9)));
      expect(await audits(PreMigrationBackup.deletedAction), hasLength(1));
    });

    test('قبل بلوغ مخطط النسخة لا تُعلَّم النسخة ناجحة ولا تُحذف', () async {
      final db = makeDb(24);
      final copy = PreMigrationBackup.createIfNeeded(db, dbFile, target: 25, schemaVersion: 25)!;
      db.dispose();

      // فتحٌ بمخطط 24 (الترحيل لم يجرِ): ليس «نجاح ترحيل».
      await PreMigrationBackup.settle(appDb, schemaVersion: 24, now: DateTime(2027));
      expect(copy.existsSync(), isTrue);
      expect(await audits(PreMigrationBackup.createdAction), isEmpty);
    });
  });

  group('المجدول الهجين', () {
    late AppDatabase appDb;
    late MemoryBackupSecretStore secrets;
    final writes = <bool>[];

    Future<({String path, int records, bool encrypted})> writer(
      String path, {
      required bool includeUsers,
      required String password,
    }) async {
      writes.add(includeUsers);
      await File(path).writeAsString('x');
      return (path: path, records: 1, encrypted: true);
    }

    setUp(() async {
      writes.clear();
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      secrets = MemoryBackupSecretStore()..value = 'pw';
    });
    tearDown(() => appDb.close());

    Future<void> runAs({required bool owner}) async {
      final s = BackupScheduler(
        appDb,
        secrets: secrets,
        writer: writer,
        isOwnerDevice: () async => owner,
        defaultDirectory: () async => p.join(dir.path, 'bk'),
      );
      await s.save((await s.config()).copyWith(enabled: true, includeUsers: true));
      expect((await s.run()).ok, isTrue);
    }

    test('جهاز المالك: نسخة كاملة بالمستخدمين', () async {
      await runAs(owner: true);
      expect(writes, [true]);
    });

    test('الفرع: بيانات فقط بلا مستخدمين ولا مفاتيح حتى لو طُلبت', () async {
      await runAs(owner: false);
      expect(writes, [false]);
    });

    test('خيار «كل شهر» (720 ساعة) متاح', () {
      expect(BackupScheduler.intervalChoices, contains(720));
    });
  });

  group('_ensureSchema لا يرمي duplicate column', () {
    test('عمودٌ ناقص يُضاف مرةً واحدة، وإعادة الفتح لاحقًا لا ترمي', () async {
      final file = File(p.join(dir.path, 'schema.sqlite'));
      Future<void> open(Future<void> Function(AppDatabase db)? probe) async {
        final db = AppDatabase.forTesting(NativeDatabase(file));
        await db.customSelect('SELECT 1').get();
        if (probe != null) await probe(db);
        await db.close();
      }

      await open(null);
      await open((db) => db.customStatement('ALTER TABLE users DROP COLUMN approved'));

      Future<bool> hasColumn() async {
        final db = AppDatabase.forTesting(NativeDatabase(file));
        final cols = await db.customSelect('PRAGMA table_info(users)').get();
        final has = cols.any((r) => r.read<String>('name') == 'approved');
        await db.close();
        return has;
      }

      expect(await hasColumn(), isTrue, reason: '_ensureSchema أعاد العمود الناقص عند الفتح');
      await expectLater(open(null), completes, reason: 'فتحٌ ثانٍ بعد الإصلاح رمى duplicate column');
      await expectLater(open(null), completes);
    });
  });
}
