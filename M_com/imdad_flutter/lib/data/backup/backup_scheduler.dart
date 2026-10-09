import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error_log.dart';
import '../../core/security/device_activation.dart';
import '../db/app_database.dart';
import '../migration/data_export.dart';
import '../repos/settings_repo.dart';

/// مخزن كلمة مرور النسخ المجدولة.
///
/// النسخة المجدولة تعمل بلا مستخدم أمام الشاشة، فلا بدّ أن تكون كلمة المرور
/// محفوظة. تُحفظ في **مخزن اعتمادات النظام** (Keystore على أندرويد، وخزانة
/// الاعتمادات على ويندوز) — لا في قاعدة البيانات ولا في الإعدادات ولا تسافر
/// بالمزامنة — وهو المخزن نفسه الذي يحمل مفتاح تشفير القاعدة.
abstract class BackupSecretStore {
  Future<String?> read();
  Future<void> write(String password);
  Future<void> clear();
}

class SecureBackupSecretStore implements BackupSecretStore {
  const SecureBackupSecretStore();

  static const _storage = FlutterSecureStorage();
  static const String _key = 'imdad.backup.password';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String password) => _storage.write(key: _key, value: password);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// للاختبارات.
class MemoryBackupSecretStore implements BackupSecretStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String password) async => value = password;

  @override
  Future<void> clear() async => value = null;
}

/// إعداد النسخ المجدولة لهذا الجهاز.
class BackupScheduleConfig {
  const BackupScheduleConfig({
    this.enabled = false,
    this.intervalHours = 24,
    this.directory = '',
    this.keep = 7,
    this.includeUsers = true,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastFile = '',
    this.lastError = '',
  });

  final bool enabled;

  /// الفاصل بين نسختين بالساعات.
  final int intervalHours;

  /// مجلد الحفظ؛ فارغ ⇒ مجلد افتراضي داخل مستندات التطبيق.
  final String directory;

  /// عدد النسخ المجدولة المحتفَظ بها؛ الأقدم يُحذف.
  final int keep;
  final bool includeUsers;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String lastFile;
  final String lastError;

  BackupScheduleConfig copyWith({
    bool? enabled,
    int? intervalHours,
    String? directory,
    int? keep,
    bool? includeUsers,
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    String? lastFile,
    String? lastError,
  }) =>
      BackupScheduleConfig(
        enabled: enabled ?? this.enabled,
        intervalHours: intervalHours ?? this.intervalHours,
        directory: directory ?? this.directory,
        keep: keep ?? this.keep,
        includeUsers: includeUsers ?? this.includeUsers,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastFile: lastFile ?? this.lastFile,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'intervalHours': intervalHours,
        'directory': directory,
        'keep': keep,
        'includeUsers': includeUsers,
        if (lastSuccessAt != null) 'lastSuccessAt': lastSuccessAt!.toIso8601String(),
        if (lastAttemptAt != null) 'lastAttemptAt': lastAttemptAt!.toIso8601String(),
        'lastFile': lastFile,
        'lastError': lastError,
      };

  factory BackupScheduleConfig.fromMap(Map<String, dynamic> m) {
    int num_(Object? v, int d, int min) => v is num && v >= min ? v.toInt() : d;
    return BackupScheduleConfig(
      enabled: m['enabled'] == true,
      intervalHours: num_(m['intervalHours'], 24, 1),
      directory: '${m['directory'] ?? ''}',
      keep: num_(m['keep'], 7, 1),
      includeUsers: m['includeUsers'] != false,
      lastSuccessAt: DateTime.tryParse('${m['lastSuccessAt'] ?? ''}'),
      lastAttemptAt: DateTime.tryParse('${m['lastAttemptAt'] ?? ''}'),
      lastFile: '${m['lastFile'] ?? ''}',
      lastError: '${m['lastError'] ?? ''}',
    );
  }
}

/// نتيجة تشغيلة واحدة.
class BackupRunResult {
  const BackupRunResult({required this.ok, this.path = '', this.records = 0, this.error = ''});

  final bool ok;
  final String path;
  final int records;
  final String error;
}

/// كاتب النسخة — يُحقن في الاختبارات.
typedef BackupWriter = Future<({String path, int records, bool encrypted})> Function(
  String path, {
  required bool includeUsers,
  required String password,
});

/// جدولة النسخ الاحتياطي المشفّر.
///
/// عند الإقلاع وكل [checkEvery] أثناء عمل التطبيق يُفحص: هل انقضى الفاصل منذ
/// آخر نسخة ناجحة؟ فإن نعم كُتبت نسخةٌ مشفَّرة (`imdad-auto-…imdbk`، بصيغة
/// [BackupCrypto] نفسها فتُستعاد من «استعادة من ملف نسخة»)، وحُذفت الأقدم من
/// المجدولة بعد [BackupScheduleConfig.keep].
///
/// - **الكتابة ذرّية:** إلى `.part` ثم إعادة تسمية، فلا تبقى نسخة نصف مكتوبة
///   باسم نسخة سليمة.
/// - **الحذف محصور** بملفات `imdad-auto-*.imdbk` وحدها: نسخك اليدوية في المجلد
///   نفسه لا تُمسّ.
/// - **الفشل لا يتكرر كل دقيقة:** المحاولة الفاشلة تُؤجَّل [retryAfter]، ويُسجَّل
///   خطأً حرجًا (سجل التدقيق وإشعار) عبر [ErrorLogger].
class BackupScheduler extends ChangeNotifier {
  BackupScheduler(
    this._db, {
    BackupSecretStore? secrets,
    BackupWriter? writer,
    DateTime Function()? clock,
    Future<String> Function()? defaultDirectory,
    Future<bool> Function()? isOwnerDevice,
    this.checkEvery = const Duration(minutes: 30),
  })  : _secrets = secrets ?? const SecureBackupSecretStore(),
        _writer = writer ?? _defaultWriter(_db),
        _now = clock ?? DateTime.now,
        _defaultDir = defaultDirectory ?? _documentsBackupDir,
        _isOwnerDevice = isOwnerDevice ?? (() => _defaultIsOwnerDevice(_db));

  final AppDatabase _db;
  final BackupSecretStore _secrets;
  final BackupWriter _writer;
  final DateTime Function() _now;
  final Future<String> Function() _defaultDir;
  final Future<bool> Function() _isOwnerDevice;
  final Duration checkEvery;

  static const String settingsKey = 'backupSchedule';
  static const String filePrefix = 'imdad-auto-';
  static const String fileExt = '.imdbk';

  /// المحاولة الفاشلة لا تُعاد قبل هذه المدة.
  static const Duration retryAfter = Duration(hours: 1);

  /// الفواصل المعروضة بالساعات: يوميًّا / كل ٣ أيام / أسبوعيًّا.
  static const List<int> intervalChoices = [24, 72, 168, 720];
  static const List<int> keepChoices = [3, 7, 14, 30];

  Timer? _timer;
  bool _running = false;
  bool get running => _running;

  static BackupWriter _defaultWriter(AppDatabase db) =>
      (path, {required includeUsers, required password}) =>
          DataExporter(db).writeToFile(path, includeUsers: includeUsers, password: password);

  /// جهاز المالك: جهاز الإدارة المفعَّل، أو الجهاز الذي يحمل مفتاح المالك الخاص.
  static Future<bool> _defaultIsOwnerDevice(AppDatabase db) async {
    final act = DeviceActivation(db);
    return await act.isMaster() || await act.canIssue();
  }

  static Future<String> _documentsBackupDir() async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'imdad_backups');

  /// هل يملك هذا الجهاز أن يكتب في مجلدٍ يختاره المستخدم؟
  ///
  /// على أندرويد: لا. منذ Android 10 لا يكتب التطبيق خارج مجلداته الخاصة إلا
  /// بصلاحية «إدارة كل الملفات» (وهي غير معلنة هنا عن قصد)، ومنتقي المجلدات
  /// يُرجع مسارًا مثل `/storage/emulated/0/Download` تفشل الكتابة فيه بـ
  /// EACCES — فيبدو النسخ الاحتياطي مفعَّلًا وهو لا يكتب شيئًا. فيُخفى
  /// المنتقي هناك ويُحفظ في مجلد التطبيق، ويُصدَّر الملف بمنتقي **الحفظ**
  /// (SAF) حين يُراد نقله خارج الجهاز.
  static bool get canChooseDirectory => !Platform.isAndroid && !Platform.isIOS;

  // ───────────────────────── الإعداد

  Future<BackupScheduleConfig> config() async =>
      BackupScheduleConfig.fromMap(await SettingsRepo(_db).read(settingsKey));

  Future<void> save(BackupScheduleConfig cfg) async {
    await SettingsRepo(_db).write(settingsKey, cfg.toMap());
    notifyListeners();
  }

  Future<bool> hasPassword() async => (await _secrets.read())?.isNotEmpty ?? false;

  Future<void> setPassword(String password) async {
    await _secrets.write(password);
    notifyListeners();
  }

  /// المجلد الفعلي: المحدَّد، وإلا الافتراضي.
  Future<String> effectiveDirectory(BackupScheduleConfig cfg) async =>
      cfg.directory.isNotEmpty ? cfg.directory : await _defaultDir();

  // ───────────────────────── الاستحقاق

  /// هل حان وقت نسخة؟ مفعَّل، وانقضى الفاصل منذ آخر نجاح، وانقضت مهلة إعادة
  /// المحاولة منذ آخر محاولة فاشلة.
  bool isDue(BackupScheduleConfig cfg, [DateTime? at]) {
    if (!cfg.enabled) return false;
    final now = at ?? _now();
    final ok = cfg.lastSuccessAt;
    if (ok != null && now.difference(ok) < Duration(hours: cfg.intervalHours)) return false;
    final tried = cfg.lastAttemptAt;
    if (tried != null && (ok == null || tried.isAfter(ok)) && now.difference(tried) < retryAfter) {
      return false;
    }
    return true;
  }

  /// يشغّل نسخةً إن حان وقتها. `null` ⇒ لا شيء مستحق.
  Future<BackupRunResult?> runIfDue() async {
    if (_running) return null;
    final cfg = await config();
    if (!isDue(cfg)) return null;
    return run();
  }

  /// نسخةٌ الآن بغضّ النظر عن الفاصل (زر «نسخة الآن» والمجدولة المستحقة).
  Future<BackupRunResult> run() async {
    if (_running) return const BackupRunResult(ok: false, error: 'نسخةٌ جارية الآن');
    _running = true;
    notifyListeners();
    final started = _now();
    var cfg = await config();
    try {
      final password = await _secrets.read();
      if (password == null || password.isEmpty) {
        throw const _BackupSetupError('لا كلمة مرور للنسخ المجدولة — اضبطها من الإعدادات');
      }
      final dir = Directory(await effectiveDirectory(cfg));
      try {
        await dir.create(recursive: true);
      } on FileSystemException catch (e) {
        // المجلد المختار لم يعد قابلًا للكتابة (قرصٌ مفصول، مسار أندرويد
        // محجوب، مجلدٌ حُذف). الرسالة تقول ما يُفعل بدل أن تُعرض لغةُ النظام.
        throw _BackupSetupError(
          'تعذّر الكتابة في مجلد النسخ «${dir.path}» — اختر مجلدًا آخر '
          '(${e.osError?.message ?? e.message})',
        );
      }

      final name = fileName(started);
      final finalPath = p.join(dir.path, name);
      final partPath = '$finalPath.part';
      // **هجين:** النسخة الكاملة (بالمستخدمين) لجهاز المالك وحده. الفرع يحفظ بياناته
      // دون حسابات ولا مفاتيح — فقدُ جهاز فرعٍ لا يُفلت منه ما يخصّ الإدارة.
      final includeUsers = cfg.includeUsers && await _isOwnerDevice();
      final result = await _writer(partPath, includeUsers: includeUsers, password: password);
      await File(partPath).rename(finalPath);

      await prune(dir, cfg.keep);

      cfg = cfg.copyWith(
        lastSuccessAt: started,
        lastAttemptAt: started,
        lastFile: finalPath,
        lastError: '',
      );
      await save(cfg);
      return BackupRunResult(ok: true, path: finalPath, records: result.records);
    } catch (err, stack) {
      final message = err is _BackupSetupError ? err.message : '$err';
      await save(cfg.copyWith(lastAttemptAt: started, lastError: message));
      ErrorLogger.critical(
        'backup.scheduled',
        err,
        stack: stack,
        userMessage: 'تعذّر النسخ الاحتياطي التلقائي: $message',
      );
      return BackupRunResult(ok: false, error: message);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// آخر نسخةٍ مكتوبة على القرص، أو `null` إن لم تكن ثمّ نسخة أو حُذف ملفها.
  ///
  /// تُستعمل في «حفظ آخر نسخة إلى ملف»: على الهاتف يكون المجلد داخليًّا لا
  /// يراه مدير الملفات، فالنسخة لا تنفع في كارثةٍ حتى تخرج من الجهاز.
  Future<({String name, Uint8List bytes})?> lastBackupBytes() async {
    final cfg = await config();
    if (cfg.lastFile.isEmpty) return null;
    final file = File(cfg.lastFile);
    if (!await file.exists()) return null;
    return (name: p.basename(file.path), bytes: await file.readAsBytes());
  }

  /// اسم ملف النسخة: `imdad-auto-YYYYMMDD-HHMM.imdbk`.
  static String fileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$filePrefix${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}$fileExt';
  }

  /// يُبقي أحدث [keep] نسخةٍ **مجدولة** ويحذف الأقدم. غيرها في المجلد لا يُمسّ.
  /// الترتيب بالاسم (يحمل التاريخ) لا بتاريخ تعديل الملف الذي ينسخه المستخدم.
  Future<List<String>> prune(Directory dir, int keep) async {
    if (!await dir.exists()) return const [];
    final mine = [
      for (final e in await dir.list().toList())
        if (e is File &&
            p.basename(e.path).startsWith(filePrefix) &&
            p.basename(e.path).endsWith(fileExt))
          e,
    ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    final removed = <String>[];
    for (final f in mine.skip(keep < 1 ? 1 : keep)) {
      try {
        await f.delete();
        removed.add(f.path);
      } catch (err, stack) {
        ErrorLogger.log('backup.prune', err, stack);
      }
    }
    return removed;
  }

  // ───────────────────────── التشغيل الدوري

  /// يبدأ الفحص عند الإقلاع ثم كل [checkEvery].
  void start() {
    if (_timer != null) return;
    unawaited(_tick());
    _timer = Timer.periodic(checkEvery, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      await runIfDue();
    } catch (err, stack) {
      ErrorLogger.log('backup.tick', err, stack);
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

class _BackupSetupError implements Exception {
  const _BackupSetupError(this.message);
  final String message;
  @override
  String toString() => message;
}
