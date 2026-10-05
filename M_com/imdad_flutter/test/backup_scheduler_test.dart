import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/error_log.dart';
import 'package:imdad/data/backup/backup_scheduler.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/backup_crypto.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:path/path.dart' as p;

/// النسخ الاحتياطي المشفّر المجدول: الاستحقاق، الكتابة الذرّية، الاحتفاظ
/// بالأحدث، حماية النسخ اليدوية، وإدارة الفشل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;
  late MemoryBackupSecretStore secrets;
  var now = DateTime(2026, 10, 4, 10);
  final writes = <String>[];

  /// كاتبٌ سريع: يكتب ملفًا صغيرًا بدل التشفير الحقيقي.
  Future<({String path, int records, bool encrypted})> fakeWriter(
    String path, {
    required bool includeUsers,
    required String password,
  }) async {
    writes.add('$path|$includeUsers|$password');
    await File(path).writeAsString('fake');
    return (path: path, records: 12, encrypted: true);
  }

  BackupScheduler make({BackupWriter? writer, bool owner = true}) => BackupScheduler(
        db,
        secrets: secrets,
        isOwnerDevice: () async => owner,
        writer: writer ?? fakeWriter,
        clock: () => now,
        defaultDirectory: () async => p.join(dir.path, 'default'),
        checkEvery: const Duration(hours: 1),
      );

  setUp(() {
    ErrorLogger.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('imdad-bk-');
    secrets = MemoryBackupSecretStore();
    now = DateTime(2026, 10, 4, 10);
    writes.clear();
  });
  tearDown(() async {
    ErrorLogger.reset();
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> enable(BackupScheduler s, {String directory = '', int keep = 7, int hours = 24}) async {
    secrets.value = 'سر-النسخ-123';
    await s.save(BackupScheduleConfig(enabled: true, directory: directory, keep: keep, intervalHours: hours));
  }

  test('الإعداد وجدولته محليان للجهاز: لا يُزامنان', () {
    expect(SettingsRepo.localOnlyKeys, contains('backupSchedule'));
  });

  group('الاستحقاق', () {
    test('معطَّل أو لم ينقضِ الفاصل ⇒ لا نسخة', () {
      final s = make();
      expect(s.isDue(const BackupScheduleConfig()), isFalse, reason: 'معطَّل');
      final cfg = BackupScheduleConfig(enabled: true, lastSuccessAt: now.subtract(const Duration(hours: 23)));
      expect(s.isDue(cfg), isFalse);
      expect(s.isDue(BackupScheduleConfig(enabled: true, lastSuccessAt: now.subtract(const Duration(hours: 24)))), isTrue);
    });

    test('أول مرة (بلا نجاح سابق) مستحقة', () {
      expect(make().isDue(const BackupScheduleConfig(enabled: true)), isTrue);
    });

    test('المحاولة الفاشلة لا تُعاد قبل ساعة', () {
      final s = make();
      final failed = BackupScheduleConfig(enabled: true, lastAttemptAt: now.subtract(const Duration(minutes: 20)));
      expect(s.isDue(failed), isFalse);
      expect(s.isDue(failed, now.add(const Duration(minutes: 41))), isTrue);
    });
  });

  group('التشغيل', () {
    test('runIfDue يكتب نسخة بكلمة المرور من المخزن، ثم لا يكرر قبل الفاصل', () async {
      final s = make();
      await enable(s, directory: dir.path);

      final res = await s.runIfDue();
      expect(res?.ok, isTrue);
      expect(res!.records, 12);
      expect(p.basename(res.path), 'imdad-auto-20261004-1000.imdbk');
      expect(File(res.path).existsSync(), isTrue);
      expect(File('${res.path}.part').existsSync(), isFalse, reason: 'الكتابة ذرّية: لا .part متروك');
      expect(writes.single, endsWith('|true|سر-النسخ-123'));

      final cfg = await s.config();
      expect(cfg.lastSuccessAt, now);
      expect(cfg.lastError, isEmpty);

      now = now.add(const Duration(hours: 5));
      expect(await s.runIfDue(), isNull, reason: 'لم ينقضِ الفاصل');
      expect(writes, hasLength(1));

      now = now.add(const Duration(hours: 20));
      expect((await s.runIfDue())?.ok, isTrue);
      expect(writes, hasLength(2));
    });

    test('المجلد الافتراضي يُنشأ إن لم يحدَّد مجلد', () async {
      final s = make();
      await enable(s);
      final res = await s.run();
      expect(res.ok, isTrue);
      expect(res.path, startsWith(p.join(dir.path, 'default')));
    });

    test('الاحتفاظ بآخر N نسخة مجدولة وحدها، ولا تُمسّ النسخ اليدوية', () async {
      final s = make();
      await enable(s, directory: dir.path, keep: 3);
      File(p.join(dir.path, 'imdad-backup-20250101-0900.imdbk')).writeAsStringSync('manual');
      File(p.join(dir.path, 'ملاحظات.txt')).writeAsStringSync('note');

      for (var i = 0; i < 5; i++) {
        now = DateTime(2026, 10, 4 + i, 10);
        expect((await s.run()).ok, isTrue);
      }

      final names = dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(names.where((n) => n.startsWith('imdad-auto-')), [
        'imdad-auto-20261006-1000.imdbk',
        'imdad-auto-20261007-1000.imdbk',
        'imdad-auto-20261008-1000.imdbk',
      ], reason: 'أحدث ٣ فقط');
      expect(names, contains('imdad-backup-20250101-0900.imdbk'), reason: 'النسخة اليدوية محفوظة');
      expect(names, contains('ملاحظات.txt'));
    });

    test('بلا كلمة مرور: يفشل برسالة واضحة ولا يكتب شيئًا', () async {
      final s = make();
      await s.save(BackupScheduleConfig(enabled: true, directory: dir.path));
      final res = await s.run();
      expect(res.ok, isFalse);
      expect(res.error, contains('كلمة مرور'));
      expect(writes, isEmpty);
      expect((await s.config()).lastError, contains('كلمة مرور'));
    });

    test('فشل الكتابة: يُسجَّل حرجًا ويُنبَّه المستخدم، ويؤجَّل ساعة، ولا يحذف القديم', () async {
      final shown = <String>[];
      final persisted = <LoggedError>[];
      ErrorLogger.userNotifier = shown.add;
      ErrorLogger.sink = (e) async => persisted.add(e);

      final s = make(
        writer: (path, {required includeUsers, required password}) async =>
            throw const FileSystemException('disk full'),
      );
      await enable(s, directory: dir.path);
      final old = File(p.join(dir.path, 'imdad-auto-20260101-1000.imdbk'))..writeAsStringSync('old good backup');

      final res = await s.run();

      expect(res.ok, isFalse);
      expect(shown.single, contains('تعذّر النسخ الاحتياطي التلقائي'));
      expect(persisted.single.source, 'backup.scheduled');
      expect(old.existsSync(), isTrue, reason: 'فشل النسخة الجديدة لا يحذف القديمة');
      final cfg = await s.config();
      expect(cfg.lastSuccessAt, isNull);
      expect(cfg.lastAttemptAt, now);
      expect(await s.runIfDue(), isNull, reason: 'لا إعادة قبل ساعة');
    });

    test('نسخة حقيقية: تُفتح بكلمة المرور وتحمل البيانات', () async {
      final s = make(
        writer: (path, {required includeUsers, required password}) =>
            DataExporter(db).writeToFile(path, includeUsers: includeUsers, password: password),
      );
      await enable(s, directory: dir.path);

      final res = await s.run();
      expect(res.ok, isTrue);

      final bytes = File(res.path).readAsBytesSync();
      expect(BackupCrypto.isEncrypted(bytes), isTrue, reason: 'ليست JSON مقروءًا');
      final json = jsonDecode(BackupCrypto.open(bytes, 'سر-النسخ-123')) as Map<String, dynamic>;
      expect(json['meta']['app'], 'imdad');
      expect(() => BackupCrypto.open(bytes, 'خاطئة'), throwsA(isA<BackupError>()));
    });
  });
}
