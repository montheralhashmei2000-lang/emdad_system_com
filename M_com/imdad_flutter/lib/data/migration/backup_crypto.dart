import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../core/security/pbkdf2.dart';

/// تشفير ملف النسخة الاحتياطية بكلمة مرور.
///
/// قاعدة البيانات على الجهاز مشفّرة (SQLCipher)، لكن ملف التصدير كان JSON
/// مقروءًا بالكامل: أسماء الوحدات والأرصدة وكل الحركات. من يأخذ الملف يحصل على
/// كل ما يحميه التشفير — فكان الباب الخلفي مفتوحًا بعد إحكام الباب الأمامي.
///
/// الصيغة: `IMDBK1` + ملح (١٦) + متجه تهيئة (١٢) + نص مشفَّر بـAES-256-GCM.
/// المفتاح يُشتق من كلمة المرور بـPBKDF2، فلا يُحفظ المفتاح في أي مكان.
///
/// **المقايضة:** نسيان كلمة المرور يعني ضياع هذه النسخة نهائيًا — لا باب خلفيًا
/// ولا استعادة. ولذلك يبقى التصدير غير المشفَّر خيارًا متاحًا بتحذير، لا يُفرض.
class BackupCrypto {
  const BackupCrypto._();

  /// بادئة تميّز الملف المشفَّر عن JSON العادي، فيُعرف نوعه قبل فتحه.
  static const List<int> magic = [0x49, 0x4D, 0x44, 0x42, 0x4B, 0x31]; // IMDBK1

  static const int _saltLength = 16;
  static const int _ivLength = 12;

  /// دورات الاشتقاق — أعلى من دورات المزامنة لأن الملف قد يُسرق ويُهاجَم
  /// بلا حدّ زمني، بخلاف جلسة المزامنة قصيرة العمر.
  static const int iterations = 60000;

  /// هل هذا الملف نسخة احتياطية مشفّرة؟
  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// يشفّر نص النسخة الاحتياطية.
  static Uint8List seal(String json, String password) {
    if (password.isEmpty) throw const BackupError('كلمة مرور النسخة الاحتياطية فارغة');
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(_saltLength, (_) => rnd.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(_ivLength, (_) => rnd.nextInt(256)));

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_keyOf(password, salt)), 128, iv, Uint8List(0)));
    final body = cipher.process(Uint8List.fromList(utf8.encode(json)));

    return Uint8List.fromList([...magic, ...salt, ...iv, ...body]);
  }

  /// يفكّ التشفير ويعيد نص JSON. يرمي [BackupError] برسالة عربية صريحة.
  static String open(List<int> bytes, String password) {
    if (!isEncrypted(bytes)) {
      throw const BackupError('هذا الملف ليس نسخة احتياطية مشفّرة');
    }
    const headerLength = 6 + _saltLength + _ivLength;
    if (bytes.length <= headerLength + 16) {
      throw const BackupError('ملف النسخة الاحتياطية ناقص أو تالف');
    }
    final salt = Uint8List.fromList(bytes.sublist(6, 6 + _saltLength));
    final iv = Uint8List.fromList(bytes.sublist(6 + _saltLength, headerLength));
    final body = Uint8List.fromList(bytes.sublist(headerLength));

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_keyOf(password, salt)), 128, iv, Uint8List(0)));
    try {
      return utf8.decode(cipher.process(body));
    } on InvalidCipherTextException {
      // GCM لا تفرّق بين كلمة خاطئة وملف معدَّل: كلاهما يُسقط بصمة السلامة.
      throw const BackupError('كلمة المرور غير صحيحة، أو الملف عُدِّل بعد إنشائه');
    } on FormatException {
      throw const BackupError('تعذّرت قراءة محتوى النسخة بعد فكّ التشفير');
    }
  }

  static Uint8List _keyOf(String password, Uint8List salt) =>
      Pbkdf2.derive(utf8.encode(password), salt, iterations: iterations, length: 32);
}

/// خطأ نسخة احتياطية برسالة جاهزة للعرض.
class BackupError implements Exception {
  const BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}
