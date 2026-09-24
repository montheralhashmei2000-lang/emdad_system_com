import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

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

  static const _storage = FlutterSecureStorage();
  static const String _keyName = 'imdad.db.key';

  /// يقرأ مفتاح القاعدة، ويولّده عند أول تشغيل.
  static Future<String> loadKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null && existing.length == 64) return existing;

    final rnd = Random.secure();
    final key = List.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _keyName, value: key);
    return key;
  }

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
  /// `sqlcipher_export`، ويُحتفظ بالأصل باسم `.plain.bak` حتى لا يضيع شيء إن
  /// انقطع الترحيل في منتصفه.
  static Future<bool> migratePlainFile(File file, String keyHex) async {
    if (!file.existsSync()) return false;
    if (!_looksPlain(file)) return false;

    final encrypted = File('${file.path}.enc');
    if (encrypted.existsSync()) encrypted.deleteSync();

    final db = sqlite3.open(file.path);
    try {
      if (!isEncrypted(db)) return false; // المكتبة ليست SQLCipher: لا ترحيل
      db.execute("ATTACH DATABASE '${encrypted.path}' AS enc KEY \"x'$keyHex'\"");
      db.execute("SELECT sqlcipher_export('enc')");
      db.execute('DETACH DATABASE enc');
    } finally {
      db.dispose();
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
    return true;
  }

  static void _dropSidecars(File file) {
    for (final suffix in const ['-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
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
      } catch (_) {}
    }
  }
}
