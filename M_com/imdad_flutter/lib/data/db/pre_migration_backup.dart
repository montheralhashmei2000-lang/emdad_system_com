import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import '../../core/error_log.dart';
import '../repos/audit_repo.dart';
import 'app_database.dart';

/// نسخة احتياطية **كاملة** من ملف القاعدة قبل ترحيل v25.
///
/// **لماذا نسخ الملف نفسه لا تصدير JSON:** الرجوع بعد ترحيلٍ فاشل أو معيب يحتاج
/// القاعدة كما كانت بالضبط — بما فيها جدول المستخدمين وكلمات مرورهم. التصدير
/// يستثني المستخدمين على الفروع عمدًا، فلا يصلح شبكة أمان.
///
/// **التشفير:** الملف مشفَّر بـSQLCipher، ونسخته مشفَّرة بالمفتاح نفسه (المخزَّن في
/// مخزن اعتمادات هذا الجهاز). فلا تُنقل خارج الجهاز ولا تُقرأ بدونه، وتبقى في
/// مجلد بيانات التطبيق بجوار الأصل.
///
/// **التوقيت:** تُنشأ في إعداد الاتصال، **قبل** أن تفتح drift القاعدة وتُرحِّلها —
/// فهي حالتها قبل أي تعديل. تُسجَّل في التدقيق بعد الفتح (القاعدة لم تكن جاهزة
/// للكتابة وقتها)، وتُحذف بعد [keepFor] من نجاح الفتح.
///
/// فشل النسخ **يمنع الترحيل**: ترقيةٌ بلا طريق رجوع أخطرُ من تطبيقٍ لا يفتح اليوم.
class PreMigrationBackup {
  const PreMigrationBackup._();

  /// إصدار المخطط الذي تسبقه النسخة.
  static const int targetVersion = 25;

  /// مدة بقاء النسخة بعد نجاح الفتح بالمخطط الجديد.
  static const Duration keepFor = Duration(days: 7);

  static const String tag = 'pre-v25';
  static const String createdAction = 'backup.pre_migration.created';
  static const String deletedAction = 'backup.pre_migration.deleted';

  /// مجلد ملف القاعدة — يُستبدل في الاختبارات (لا `path_provider` فيها).
  /// تحت `flutter test` لا مجلد بيانات: قناة المنصّة تعلّق داخل FakeAsync فتتجمّد أول فتحٍ للقاعدة.
  static Future<Directory> Function() directoryProvider = () {
    if (Platform.environment.containsKey('FLUTTER_TEST')) throw StateError('no data dir in tests');
    return getApplicationSupportDirectory();
  };

  /// اسم ملف الوصف المرافق للنسخة.
  static String markerPathOf(String backupPath) => '$backupPath.json';

  // ───────────────────────── الإنشاء (قبل الترحيل)

  /// ينسخ [dbFile] إن كانت القاعدة مفتوحةً بإصدارٍ أقدم من [target]، ويعيد ملف
  /// النسخة، أو `null` إن لم يلزم (قاعدة جديدة، أو محدَّثة، أو نسخةٌ سابقةٌ لم
  /// يكتمل بعدها ترحيل). يُنادى من إعداد الاتصال بعد تطبيق المفتاح.
  ///
  /// [schemaVersion] إصدار مخطط التطبيق الحالي: لا نسخة ما لم يبلغ [target]،
  /// وإلا نُسخت قاعدةٌ لن يمسّها ترحيل.
  static File? createIfNeeded(
    CommonDatabase db,
    File dbFile, {
    int target = targetVersion,
    int schemaVersion = AppDatabase.kSchemaVersion,
    DateTime? now,
  }) {
    if (schemaVersion < target) return null;

    final version = (db.select('PRAGMA user_version').first.values.first as num).toInt();
    // 0 = قاعدةٌ جديدة لا شيء فيها تُحفَظ.
    if (version < 1 || version >= target) return null;

    // نسخةٌ سابقةٌ لم يُفتح بعدها المخطط الجديد ⇒ هي حالة ما قبل الترحيل
    // نفسها (إقلاعاتٌ فاشلة متتالية)، ولا تُستبدل بنسخةٍ من قاعدةٍ قد تكون
    // تضرّرت جزئيًّا.
    if (_markers(dbFile.parent, dbFile).any((m) => m.openedOkAt == null)) return null;

    final t = now ?? DateTime.now();
    final dest = '${dbFile.path}.$tag-${_stamp(t)}';
    final part = '$dest.part';
    try {
      // سجل WAL يُفرَّغ في الملف الرئيسي أولًا، وإلا فاتت النسخةَ آخرُ الكتابات.
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      dbFile.copySync(part);
      final copied = File(part);
      if (copied.lengthSync() != dbFile.lengthSync() || copied.lengthSync() == 0) {
        throw const FileSystemException('حجم النسخة لا يطابق الأصل');
      }
      copied.renameSync(dest);
      File(markerPathOf(dest)).writeAsStringSync(jsonEncode({
        'createdAt': t.toIso8601String(),
        'fromVersion': version,
        'toVersion': target,
        'size': File(dest).lengthSync(),
        'openedOkAt': null,
        'createdAudited': false,
      }));
      return File(dest);
    } catch (err) {
      for (final leftover in [part, dest, markerPathOf(dest)]) {
        try {
          final f = File(leftover);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {
          // تنظيفٌ بأقصى جهد.
        }
      }
      throw StateError(
        'تعذّر إنشاء نسخة احتياطية من قاعدة البيانات قبل الترقية، فلم تبدأ الترقية '
        'وبقيت بياناتك كما هي. تأكّد من توفّر مساحة كافية على القرص ثم أعد التشغيل. '
        '($err)',
      );
    }
  }

  // ───────────────────────── التسوية (بعد الفتح)

  /// يُنادى بعد نجاح فتح القاعدة (بعد الترحيل):
  ///  1. نسخةٌ جديدة لم تُسجَّل ⇒ يُسجَّل إنشاؤها ويُعلَّم نجاح الفتح.
  ///  2. نسخةٌ مضى على نجاح فتحها [keepFor] ⇒ تُحذف ويُسجَّل حذفها.
  ///
  /// لا يُفشل الإقلاع أبدًا: التنظيف والتدقيق ثانويان أمام فتح التطبيق.
  static Future<void> settle(
    AppDatabase db, {
    int schemaVersion = AppDatabase.kSchemaVersion,
    DateTime? now,
  }) async {
    try {
      // قبل أن يبلغ التطبيق مخطط النسخة لا معنى لـ«نجاح الترحيل».
      if (schemaVersion < targetVersion) return;

      final Directory dir;
      try {
        dir = await directoryProvider();
      } catch (_) {
        return; // بيئةٌ بلا مجلد بيانات (اختبارات) — لا نسخ أصلًا.
      }
      if (!dir.existsSync()) return;

      final t = now ?? DateTime.now();
      final audit = AuditRepo(db);
      for (final m in _markers(dir, null)) {
        final name = p.basename(m.backupPath);

        m.openedOkAt ??= t;
        if (!m.createdAudited) {
          await audit.log(
            action: createdAction,
            entityType: 'نسخة احتياطية',
            summary: 'نسخة احتياطية كاملة قبل ترقية القاعدة من v${m.fromVersion} إلى v${m.toVersion}: $name',
            details: {'file': name, 'fromVersion': m.fromVersion, 'toVersion': m.toVersion, 'bytes': m.size},
            risk: AuditRepo.riskHigh,
            actorEmail: 'system',
          );
          m.createdAudited = true;
        }

        if (t.difference(m.openedOkAt!) >= keepFor) {
          var removed = true;
          try {
            final f = File(m.backupPath);
            if (f.existsSync()) f.deleteSync();
            final marker = File(markerPathOf(m.backupPath));
            if (marker.existsSync()) marker.deleteSync();
          } catch (err, stack) {
            removed = false;
            ErrorLogger.log('backup.preMigration.delete', err, stack);
          }
          if (removed) {
            await audit.log(
              action: deletedAction,
              entityType: 'نسخة احتياطية',
              summary: 'حُذفت النسخة الاحتياطية قبل الترقية بعد ${keepFor.inDays} أيام من نجاح الفتح: $name',
              details: {'file': name, 'keptDays': keepFor.inDays},
              risk: AuditRepo.riskHigh,
              actorEmail: 'system',
            );
            continue;
          }
        }
        m.save();
      }
    } catch (err, stack) {
      ErrorLogger.log('backup.preMigration.settle', err, stack);
    }
  }

  // ───────────────────────── داخلي

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// أوصاف النسخ الموجودة في [dir] (لقاعدةٍ بعينها إن أُعطيت [dbFile]).
  static List<_Marker> _markers(Directory dir, File? dbFile) {
    if (!dir.existsSync()) return const [];
    final prefix = dbFile == null ? null : '${p.basename(dbFile.path)}.$tag-';
    final out = <_Marker>[];
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final base = p.basename(e.path);
      if (!base.contains('.$tag-')) continue;
      if (prefix != null && !base.startsWith(prefix)) continue;
      final backupPath = e.path.substring(0, e.path.length - '.json'.length);
      try {
        out.add(_Marker.read(backupPath, jsonDecode(e.readAsStringSync()) as Map<String, dynamic>));
      } catch (_) {
        // وصفٌ تالف: يُتجاهل (لا يُحذف شيءٌ لا نعرف تاريخه).
      }
    }
    return out;
  }
}

class _Marker {
  _Marker({
    required this.backupPath,
    required this.fromVersion,
    required this.toVersion,
    required this.size,
    required this.createdAt,
    this.openedOkAt,
    this.createdAudited = false,
  });

  factory _Marker.read(String backupPath, Map<String, dynamic> m) => _Marker(
        backupPath: backupPath,
        fromVersion: (m['fromVersion'] as num?)?.toInt() ?? 0,
        toVersion: (m['toVersion'] as num?)?.toInt() ?? PreMigrationBackup.targetVersion,
        size: (m['size'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now(),
        openedOkAt: DateTime.tryParse('${m['openedOkAt'] ?? ''}'),
        createdAudited: m['createdAudited'] == true,
      );

  final String backupPath;
  final int fromVersion;
  final int toVersion;
  final int size;
  final DateTime createdAt;
  DateTime? openedOkAt;
  bool createdAudited;

  void save() => File(PreMigrationBackup.markerPathOf(backupPath)).writeAsStringSync(jsonEncode({
        'createdAt': createdAt.toIso8601String(),
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'size': size,
        'openedOkAt': openedOkAt?.toIso8601String(),
        'createdAudited': createdAudited,
      }));
}
