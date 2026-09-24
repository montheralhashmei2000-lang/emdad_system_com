import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// اشتقاق المفاتيح بنفس معايير نظام الويب الحالي:
/// PBKDF2-HMAC-SHA256 · 45,000 دورة · Salt عشوائي 16 بايت · مخرج 256 بت (64 حرفًا hex).
/// المدخلات والمخرجات متطابقة مع الدالة القديمة (AUTHCORE.derive) حتى تعمل الحسابات المُرحَّلة كما هي.
class Pbkdf2 {
  static const int iterations = 45000;
  static const int _keyLengthBytes = 32; // 256 بت
  static const int _saltLengthBytes = 16;

  /// توليد salt عشوائي بصيغة hex (32 حرفًا) كما يفعل النظام الحالي.
  static String newSaltHex() {
    final rnd = Random.secure();
    final bytes = Uint8List(_saltLengthBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    return toHex(bytes);
  }

  /// اشتقاق المفتاح وإرجاعه hex — نفس ناتج WebCrypto في النسخة الحالية.
  static String deriveHex(String password, String saltHex,
      {int iterations = iterations}) {
    final derived = derive(
      utf8.encode(password),
      fromHex(saltHex),
      iterations: iterations,
      length: _keyLengthBytes,
    );
    return toHex(derived);
  }

  /// PBKDF2 (RFC 8018) فوق HMAC-SHA256.
  static Uint8List derive(
    List<int> password,
    List<int> salt, {
    int iterations = iterations,
    int length = _keyLengthBytes,
  }) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'يجب أن يكون 1 فأكثر');
    }
    if (length < 1) {
      throw ArgumentError.value(length, 'length', 'يجب أن يكون 1 فأكثر');
    }

    final hmac = Hmac(sha256, password);
    const hashLength = 32; // sha256
    final blocks = (length + hashLength - 1) ~/ hashLength;
    final output = Uint8List(blocks * hashLength);

    for (var block = 1; block <= blocks; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert(<int>[...salt, ...blockIndex]).bytes);
      final acc = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      output.setRange((block - 1) * hashLength, block * hashLength, acc);
    }
    return Uint8List.sublistView(output, 0, length);
  }

  /// مقارنة بزمن ثابت لتفادي تسريب المعلومات عبر توقيت المقارنة.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List fromHex(String hex) {
    final clean = hex.trim();
    if (clean.length.isOdd) {
      throw ArgumentError.value(hex, 'hex', 'طول غير صالح');
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
