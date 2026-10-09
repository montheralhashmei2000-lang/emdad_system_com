import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

import '../db/db_cipher.dart';

/// تشفير المرفقات على القرص (AES-256-GCM بمفتاحٍ مشتقٍّ من مفتاح القاعدة).
///
/// القاعدة مشفَّرة (SQLCipher) لكن مرفقاتها كانت تُكتب ملفاتٍ صريحة بجوارها:
/// الأرشيف الإلكتروني، والبرقيات **المصنَّفة**، ومرفقات العهد والإخلاءات. فمن
/// أخذ الجهاز أو نسخ مجلد بياناته قرأها بعارض ملفاتٍ عادي — والبرقية المصنَّفة
/// أولى بالتشفير من الرصيد.
///
/// **المفتاح لا يُحفظ:** يُشتقّ بـHKDF-SHA256 من مفتاح القاعدة نفسه (المحفوظ في
/// مخزن اعتمادات النظام)، بغرضٍ (`info`) خاصٍّ بالمرفقات فلا يُستعمل مفتاح
/// القاعدة لغرضين. فمن يملك مفتاح القاعدة يملك المرفقات أيضًا — وهو الصواب:
/// الحمايةُ المقصودة هي أخذُ الملفات لا أخذُ الجهاز كله.
///
/// **التوافق الخلفي:** الملفات الصريحة القديمة تُقرأ كما هي ([read] تتعرّف على
/// البادئة)، ولا تُرحَّل دفعةً واحدة: ترحيلُ كل ملفات الأرشيف في مرةٍ واحدة
/// ينقطع في منتصفه فيخلّف خلطًا بلا سجلٍّ لما تمّ. فالجديد يُشفَّر، والقديم
/// يُقرأ، ويُشفَّر عند أول استبدالٍ له.
class AttachmentCrypto {
  const AttachmentCrypto._();

  /// بادئة الملف المشفَّر — بها يُعرف نوعه قبل فكّه.
  static const List<int> magic = [0x49, 0x4D, 0x44, 0x41, 0x54, 0x31]; // IMDAT1

  static const int _ivLength = 12;
  static const int _tagBits = 128;

  /// ملح الاشتقاق وغرضه — ثابتان: المفتاح المشتقّ لا بد أن يتطابق بين تشغيلة
  /// وأخرى على الجهاز نفسه، فلا ملح عشوائي هنا (العشوائية في متجه التهيئة).
  static final Uint8List _salt = Uint8List.fromList('imdad-attach-salt'.codeUnits);
  static final Uint8List _info = Uint8List.fromList('imdad-attach-v1'.codeUnits);

  static Uint8List? _cached;
  static String? _debugKeyHex;

  /// مفتاح قاعدةٍ وهميّ للاختبارات (٦٤ محرف hex)، أو `null` للمخزن الحقيقي.
  ///
  /// مخزن اعتمادات النظام لا يعمل خارج التطبيق، والقاعدة في الاختبارات تعمل في
  /// الذاكرة فلا تمرّ بـ[DbCipher] أصلًا. فكلُّ اختبارٍ يكتب مرفقًا يضبط هذا
  /// سطرًا واحدًا. وضبطُه يُنسي المفتاح المشتقّ المحفوظ.
  @visibleForTesting
  static set debugKeyHex(String? hex) {
    _debugKeyHex = hex;
    _cached = null;
  }

  /// المفتاح المشتقّ، يُحسب مرة لكل تشغيلة.
  ///
  /// تعذّر قراءة مفتاح القاعدة يُرمى كما هو: **فشلٌ مغلق** — لا يُكتب المرفق
  /// صريحًا على القرص لأن المفتاح غاب. وفي الإنتاج لا يقع هذا إلا والقاعدة
  /// نفسها لا تُفتح.
  static Future<Uint8List> _key() async {
    final have = _cached;
    if (have != null) return have;
    final dbKey = _debugKeyHex ?? await DbCipher.loadKey();
    final out = Uint8List(32);
    HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(_hexToBytes(dbKey), 32, _salt, _info))
      ..deriveKey(Uint8List(0), 0, out, 0);
    return _cached = out;
  }

  /// هل تبدأ [bytes] ببادئة المرفق المشفَّر؟
  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// يشفّر [plain]: البادئة ثم متجه التهيئة ثم النص المشفَّر وبصمة سلامته.
  static Future<Uint8List> seal(List<int> plain) async {
    final rnd = Random.secure();
    final iv = Uint8List.fromList(List.generate(_ivLength, (_) => rnd.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(await _key()), _tagBits, iv, Uint8List(0)));
    final body = cipher.process(Uint8List.fromList(plain));
    return Uint8List.fromList([...magic, ...iv, ...body]);
  }

  /// يفكّ تشفير [bytes]، أو يعيدها كما هي إن كانت ملفًّا صريحًا قديمًا.
  ///
  /// يرمي [AttachmentCryptoError] إن كان الملف مشفَّرًا وتعذّر فكّه: مفتاحٌ آخر
  /// (ملفٌّ نُسخ من جهازٍ غير هذا) أو بايتاتٌ عُبث بها. والصمت هنا أسوأ من
  /// الخطأ: عرضُ بايتاتٍ مشفَّرة كأنها PDF يُظهر «ملفًّا تالفًا» بلا سبب.
  static Future<Uint8List> open(List<int> bytes) async {
    if (!isEncrypted(bytes)) return Uint8List.fromList(bytes);
    const head = 6 + _ivLength;
    if (bytes.length <= head + 16) {
      throw const AttachmentCryptoError('ملف المرفق ناقص أو تالف');
    }
    final iv = Uint8List.fromList(bytes.sublist(6, head));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(await _key()), _tagBits, iv, Uint8List(0)));
    try {
      return cipher.process(Uint8List.fromList(bytes.sublist(head)));
    } on InvalidCipherTextException {
      throw const AttachmentCryptoError(
          'تعذّر فكّ تشفير المرفق — الملف من جهازٍ آخر أو عُدِّل بعد حفظه');
    }
  }

  /// يكتب [plain] مشفَّرًا في [file].
  static Future<void> write(File file, List<int> plain) async =>
      file.writeAsBytes(await seal(plain), flush: true);

  /// يقرأ [file] مفكوكًا — مشفَّرًا كان أو صريحًا قديمًا.
  static Future<Uint8List> read(File file) async => open(await file.readAsBytes());

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// خطأ مرفقٍ برسالة جاهزة للعرض.
class AttachmentCryptoError implements Exception {
  const AttachmentCryptoError(this.message);
  final String message;
  @override
  String toString() => message;
}
