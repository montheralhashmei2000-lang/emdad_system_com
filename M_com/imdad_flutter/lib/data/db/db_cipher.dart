import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../core/error_log.dart';

/// مخزن سرّ المفتاح — واجهة ضيقة تُحقن في الاختبارات بنسخة في الذاكرة، لأن إضافة
/// مخزن اعتمادات النظام لا تعمل خارج التطبيق.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// المخزن الحقيقي: Keystore على أندرويد، وخزانة الاعتمادات على ويندوز.
class SecureKeyStore implements KeyStore {
  const SecureKeyStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

/// تشفير قاعدة البيانات على الجهاز (SQLCipher — AES-256).
///
/// الملف كان SQLite عاديًا: من ينسخه من جهاز ضائع أو من نسخة احتياطية يقرأ كل
/// الأرصدة والحركات وأسماء الوحدات بأداة مجانية. الآن لا يُفتح إلا بمفتاح
/// محفوظ في مخزن اعتمادات النظام (Keystore على أندرويد، وخزانة الاعتمادات
/// على ويندوز)، فلا يكفي أخذ الملف.
///
/// المفتاح يُولَّد مرة على الجهاز ولا يغادره ولا يدخل النسخ الاحتياطية: النسخة
/// الاحتياطية تبقى JSON مقروءًا كما كانت، وحمايتها مسؤولية من يحفظها.
class DbCipher {
  const DbCipher._();

  static const String _keyName = 'imdad.db.key';

  /// اسم ملف القاعدة في مجلد بيانات التطبيق.
  static const String fileName = 'imdad.sqlite';

  /// لاحقة النسخة غير المشفّرة التي يتركها الترحيل القديم.
  static const String plainBackupSuffix = '.plain.bak';

  /// يقرأ مفتاح القاعدة، ويولّده **عند غيابه تمامًا** فقط. [store] للاختبارات فقط.
  ///
  /// قيمة محفوظة غير سليمة (طولها ليس ٦٤ أو فيها غير hex) لا يُكتب فوقها: المفتاح
  /// القديم قد يكون ما يفتح القاعدة، ومسحه بصمت يحوّلها إلى ملف لا يُفتح ويبدو
  /// للمستخدم فاسدًا. يُرمى [StateError] بدل ذلك ليُعالَج الأمر عن علم.
  static Future<String> loadKey({KeyStore store = const SecureKeyStore()}) async {
    final existing = await store.read(_keyName);
    if (existing != null && existing.isNotEmpty) {
      if (!_validKey.hasMatch(existing)) {
        throw StateError(
          'مفتاح تشفير قاعدة البيانات المحفوظ على هذا الجهاز تالف. لم يُستبدل بمفتاح جديد '
          'حتى لا تضيع القاعدة نهائيًا؛ استعد نسخةً احتياطية أو تواصل مع الدعم.',
        );
      }
      return existing;
    }

    final rnd = Random.secure();
    final key = List.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await store.write(_keyName, key);
    return key;
  }

  static final RegExp _validKey = RegExp(r'^[0-9a-fA-F]{64}$');

  /// يُنفَّذ داخل خيط قاعدة البيانات قبل فتحها: أندرويد يفتح `sqlite3` العادية
  /// افتراضيًا، فيجب توجيهه إلى مكتبة SQLCipher.
  static void setupIsolate() {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }

  /// يجب أن يكون **أول** أمر على الاتصال، قبل أي قراءة أو كتابة.
  static void applyKey(CommonDatabase db, String keyHex) {
    db.execute("PRAGMA key = \"x'$keyHex'\"");
  }

  /// هل المكتبة المحمَّلة فعلًا هي SQLCipher؟
  ///
  /// السؤال ليس نظريًا: `PRAGMA key` على SQLite العادية **تمرّ بلا خطأ ولا
  /// تشفّر شيئًا**. بدون هذا الفحص قد يظن المستخدم أن بياناته مشفّرة وهي ليست
  /// كذلك — ولذلك يظهر في فحص سلامة النظام.
  static bool isEncrypted(CommonDatabase db) {
    try {
      final rows = db.select('PRAGMA cipher_version');
      return rows.isNotEmpty && '${rows.first.values.first ?? ''}'.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// ترحيل قاعدة قديمة غير مشفّرة إلى نسخة مشفّرة بالمفتاح نفسه.
  ///
  /// يُنفَّذ مرة واحدة قبل أول فتح: تُصدَّر البيانات إلى ملف جديد عبر
  /// `sqlcipher_export`، ويُحتفظ بالأصل باسم `.plain.bak` إلى أن تُفتح النسخة
  /// المشفّرة وتُطابق الأصل، ثم يُحذف: بقاؤه نسخةً مقروءةً بكل البيانات يُبطل
  /// التشفير. فشل حذفه يُسجَّل تحذيرًا ولا يُفشل الترحيل.
  static Future<bool> migratePlainFile(File file, String keyHex) async {
    if (!file.existsSync()) return false;
    if (!_looksPlain(file)) return false;

    final encrypted = File('${file.path}.enc');
    if (encrypted.existsSync()) encrypted.deleteSync();

    int sourceObjects;
    final db = sqlite3.open(file.path);
    try {
      if (!isEncrypted(db)) return false; // المكتبة ليست SQLCipher: لا ترحيل
      sourceObjects = _objectCount(db);
      db.execute("ATTACH DATABASE '${encrypted.path}' AS enc KEY \"x'$keyHex'\"");
      db.execute("SELECT sqlcipher_export('enc')");
      db.execute('DETACH DATABASE enc');
    } finally {
      db.dispose();
    }

    // لا يُستبدل الأصل قبل التأكد أن النسخة المشفّرة تُفتح بالمفتاح وتحمل
    // البيانات نفسها؛ وإلا بقي الأصل سليمًا والتشغيل التالي يعيد المحاولة.
    if (!_verifyEncrypted(encrypted, keyHex, sourceObjects)) {
      try {
        encrypted.deleteSync();
      } catch (err, stack) {
        ErrorLogger.log('db.cleanupEncrypted', err, stack);
      }
      throw StateError(
        'تعذّر التحقق من النسخة المشفّرة لقاعدة البيانات، فبقيت القاعدة الأصلية كما هي. '
        'أعد تشغيل التطبيق للمحاولة من جديد.',
      );
    }

    // القاعدة تعمل بوضع WAL، فيرافق الملفَ ملفّا `-wal` و`-shm`. لو بقيا بعد
    // الاستبدال لحاول SQLite تطبيق سجل الملف القديم غير المشفّر على الجديد.
    _dropSidecars(file);
    _dropSidecars(encrypted);

    try {
      file.renameSync('${file.path}.plain.bak');
      encrypted.renameSync(file.path);
    } on FileSystemException catch (e) {
      // النسخة المشفّرة جاهزة بجوار الأصل، فالفشل هنا في الاستبدال وحده.
      // رسالة صريحة خير من استثناء خام يوقف الإقلاع بلا تفسير.
      throw StateError(
        'تعذّر استبدال قاعدة البيانات بالنسخة المشفّرة (${e.osError?.message ?? e.message}). '
        'أغلق أي نسخة أخرى من التطبيق ثم أعد التشغيل. '
        'النسخة المشفّرة محفوظة في ${encrypted.path}',
      );
    }

    // النسخة المشفّرة تعمل الآن؛ الأصل المقروء لم يعد له مبرر.
    final backup = File('${file.path}$plainBackupSuffix');
    try {
      backup.deleteSync();
    } catch (e) {
      debugPrint(
        'DbCipher: تعذّر حذف النسخة غير المشفّرة ${backup.path} ($e) — احذفها يدويًا لأنها تحوي بيانات مقروءة.',
      );
    }
    _dropSidecars(backup);
    return true;
  }

  /// يحذف أي `*.plain.bak` بجوار [file] — بقايا ترحيلٍ قديم كان يتركها — **بشرط**
  /// أن تكون القاعدة المشفّرة سليمة (ليست عادية، وتُفتح بالمفتاح، وفيها مخطط).
  /// وإلا بقيت النسخ كما هي: قد تكون الوحيدة التي تحوي البيانات.
  ///
  /// يعيد مسارات ما حُذف. ما تعذّر حذفه يُسجَّل تحذيرًا ولا يُرمى.
  static List<String> removeStalePlainBackups(File file, String keyHex) {
    final dir = file.parent;
    if (!dir.existsSync()) return const [];
    final stale = [
      for (final e in dir.listSync().whereType<File>())
        if (e.path.endsWith(plainBackupSuffix)) e,
    ];
    if (stale.isEmpty) return const [];

    final healthy = file.existsSync() && !_looksPlain(file) && _verifyEncrypted(file, keyHex, 1, atLeast: true);
    if (!healthy) return const [];

    final removed = <String>[];
    for (final f in stale) {
      try {
        f.deleteSync();
        removed.add(f.path);
        _dropSidecars(f);
      } catch (e) {
        debugPrint('DbCipher: تعذّر حذف النسخة غير المشفّرة ${f.path} ($e) — احذفها يدويًا.');
      }
    }
    return removed;
  }

  /// عدد كائنات المخطط (جداول وفهارس…) — بصمة سريعة لمطابقة الأصل بالنسخة.
  static int _objectCount(CommonDatabase db) =>
      db.select('SELECT COUNT(*) AS c FROM sqlite_master').first['c'] as int;

  /// يفتح [file] بالمفتاح ويتأكد أنه يُقرأ ويحمل [expected] كائنًا من المخطط
  /// (أو [expected] فأكثر إن كان [atLeast]).
  static bool _verifyEncrypted(File file, String keyHex, int expected, {bool atLeast = false}) {
    Database? db;
    try {
      db = sqlite3.open(file.path);
      applyKey(db, keyHex);
      final n = _objectCount(db);
      return atLeast ? n >= expected : n == expected;
    } catch (_) {
      return false;
    } finally {
      try {
        db?.dispose();
      } catch (err, stack) {
        ErrorLogger.log('db.dispose', err, stack);
      }
    }
  }

  static void _dropSidecars(File file) {
    for (final suffix in const ['-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (err, stack) {
          ErrorLogger.log('db.sidecar', err, stack);
        }
      }
    }
  }

  /// ملف SQLite العادي يبدأ بالنص `SQLite format 3`، والمشفَّر يبدأ بعشوائية.
  ///
  /// المقبض يُغلق في `finally`: تركه مفتوحًا يُبقي الملف مقفولًا على ويندوز
  /// فتفشل إعادة تسميته لاحقًا بالخطأ ٣٢ ويسقط الترحيل بعد نجاح التصدير.
  static bool _looksPlain(File file) {
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      final head = handle.readSync(16);
      return String.fromCharCodes(head).startsWith('SQLite format 3');
    } catch (_) {
      return false;
    } finally {
      try {
        handle?.closeSync();
      } catch (err, stack) {
        ErrorLogger.log('db.closeHandle', err, stack);
      }
    }
  }
}
