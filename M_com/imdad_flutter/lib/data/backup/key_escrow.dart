import 'dart:convert';
import 'dart:typed_data';

import '../db/app_database.dart';
import '../migration/backup_crypto.dart';
import '../repos/settings_repo.dart';

/// ملف استرداد مفتاح القاعدة — يُحفظ على USB في خزنة (البند H-2، وقرار المالك
/// في 2026-10-11).
///
/// مفتاح القاعدة لا يغادر مخزن أسرار الجهاز، وفقدُه (مخزنٌ مُسح بعد عطل،
/// حسابُ ويندوز أُعيد تعيينه، نقلُ مجلد البيانات) يجعل القاعدة لا تُفتح أبدًا.
/// هذا الملف نسخةٌ منه **مشفّرة بكلمة مرورٍ يختارها المالك** (صيغة [BackupCrypto]
/// نفسها: PBKDF2 بـ٣١٠ ألف دورة وAES-256-GCM)، فلا يفتح القاعدة من وجد
/// الملف وحده. ويحمل معرّف الجهاز ليُعرف لأي جهازٍ هو.
class KeyEscrow {
  const KeyEscrow._();

  /// وسمُ المحتوى بعد فكّه: يميّز ملف الاسترداد عن النسخة الاحتياطية (الصيغة
  /// المشفّرة واحدة).
  static const String kind = 'imdad.dbkey.v1';

  /// امتداد الملف المقترح.
  static const String extension = 'imdkey';

  /// مفتاح إعدادات **محليّ**: متى حُفظ آخر ملف استرداد على هذا الجهاز.
  static const String settingsKey = 'keyEscrow';

  /// بعد هذه المدة يُذكَّر المالك بتحديث الملف («يُحدَّث دوريًّا»).
  static const Duration refreshAfter = Duration(days: 90);

  /// أقصر كلمة مرورٍ تُقبل للملف.
  static const int minPasswordLength = 8;

  /// يشفّر [keyHex] لجهاز [deviceId] بكلمة المرور [password].
  static Uint8List seal({
    required String keyHex,
    required String deviceId,
    required String password,
    DateTime? now,
  }) {
    if (password.length < minPasswordLength) {
      throw const BackupError('كلمة مرور ملف الاسترداد $minPasswordLength أحرف على الأقل');
    }
    return BackupCrypto.seal(
      jsonEncode({
        'kind': kind,
        'deviceId': deviceId,
        'key': keyHex,
        'createdAt': (now ?? DateTime.now()).toIso8601String(),
      }),
      password,
    );
  }

  /// يفكّ ملف الاسترداد. يرمي [BackupError] برسالةٍ عربية إن لم يكن ملف
  /// استرداد، أو كانت كلمة المرور خاطئة.
  static ({String keyHex, String deviceId, String createdAt}) open(List<int> bytes, String password) {
    final Object? data;
    try {
      data = jsonDecode(BackupCrypto.open(bytes, password));
    } on FormatException {
      throw const BackupError('محتوى الملف غير مقروء');
    }
    if (data is! Map || data['kind'] != kind) {
      throw const BackupError('هذا ليس ملف استرداد مفتاح القاعدة');
    }
    final key = '${data['key'] ?? ''}';
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
      throw const BackupError('ملف الاسترداد تالف (المفتاح غير صالح)');
    }
    return (keyHex: key, deviceId: '${data['deviceId'] ?? ''}', createdAt: '${data['createdAt'] ?? ''}');
  }

  /// هل محتوى النسخة المفكوك ملفُّ استرداد لا نسخة بيانات؟
  static bool isEscrowPayload(Object? decoded) => decoded is Map && decoded['kind'] == kind;

  /// يسجّل حفظ ملفٍّ الآن (إعداد محلي).
  static Future<void> markSaved(AppDatabase db, {DateTime? now}) =>
      SettingsRepo(db).write(settingsKey, {'at': (now ?? DateTime.now()).toIso8601String()});

  /// متى حُفظ آخر ملف استرداد على هذا الجهاز، أو `null` إن لم يُحفظ قط.
  static Future<DateTime?> lastSaved(AppDatabase db) async =>
      DateTime.tryParse('${(await SettingsRepo(db).read(settingsKey))['at'] ?? ''}');

  /// هل حان تحديث الملف (أو لم يُحفظ بعد)؟
  static bool isDue(DateTime? lastSaved, {DateTime? now}) =>
      lastSaved == null || (now ?? DateTime.now()).difference(lastSaved) >= refreshAfter;
}
