import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// اشتقاق المفاتيح: PBKDF2-HMAC-SHA256 · Salt عشوائي 16 بايت · مخرج 256 بت (64 حرفًا hex).
///
/// عدد الدورات يُحفظ مع كل حساب (`users.iterations`)، فالحسابات القديمة المُرحَّلة
/// من الويب (45,000 دورة — [legacyIterations]) تبقى تعمل، وتُعاد تجزئتها بالعدد
/// الحالي [iterations] عند أول دخول ناجح (انظر `PasswordHash`).
class Pbkdf2 {
  /// العدد الحالي لكل كلمة مرور جديدة أو مُعاد تجزئتها. (توصية OWASP لـ SHA-256.)
  static const int iterations = 310000;

  /// عدد نسخة الويب ودفعات التطبيق الأولى — للتحقق من الحسابات القديمة فقط.
  static const int legacyIterations = 45000;
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
  ///
  /// الحلقة الداخلية هي كل الكلفة، فكُتبت بلا حجز ذاكرة: حالتا SHA-256 بعد كتلتي
  /// ipad وopad تُحسبان مرة واحدة من كلمة المرور، ثم كل دورة = ضغطتان فقط بدل
  /// أربع في `Hmac.convert` (الذي يعيد معالجة المفتاح في كل استدعاء). الناتج
  /// مطابق بايتًا ببايت للتنفيذ المرجعي — تحرسه قيم الويب في pbkdf2_test.
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

    // مفتاح HMAC: يُختصر بـ SHA-256 إن زاد عن طول الكتلة (64 بايت).
    final key = Uint8List(64)..setAll(0, password.length > 64 ? sha256.convert(password).bytes : password);
    final ipad = Uint8List(64);
    final opad = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      ipad[i] = key[i] ^ 0x36;
      opad[i] = key[i] ^ 0x5c;
    }
    final innerState = Uint32List.fromList(_sha256Init);
    _Sha256.compressBytes(innerState, ipad);
    final outerState = Uint32List.fromList(_sha256Init);
    _Sha256.compressBytes(outerState, opad);

    final hmac = Hmac(sha256, password);
    const hashLength = 32; // sha256
    final blocks = (length + hashLength - 1) ~/ hashLength;
    final output = Uint8List(blocks * hashLength);

    // كتلة رسالة لقيمة بطول 32 بايت بعد كتلة مفتاح: الحشوة ثابتة وطولها (64+32)×8 بت.
    final w = Uint32List(64);
    final st = Uint32List(8);
    final u = Uint32List(8);
    final acc = Uint32List(8);

    for (var block = 1; block <= blocks; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      final first = hmac.convert(<int>[...salt, ...blockIndex]).bytes;
      for (var j = 0; j < 8; j++) {
        u[j] = (first[j * 4] << 24) | (first[j * 4 + 1] << 16) | (first[j * 4 + 2] << 8) | first[j * 4 + 3];
        acc[j] = u[j];
      }

      for (var i = 1; i < iterations; i++) {
        // الداخلي: SHA256(ipad || u)
        st.setAll(0, innerState);
        _Sha256.compressDigest(st, w, u);
        // الخارجي: SHA256(opad || الداخلي)
        u.setAll(0, st);
        st.setAll(0, outerState);
        _Sha256.compressDigest(st, w, u);
        u.setAll(0, st);
        for (var j = 0; j < 8; j++) {
          acc[j] ^= u[j];
        }
      }
      final base = (block - 1) * hashLength;
      for (var j = 0; j < 8; j++) {
        output[base + j * 4] = acc[j] >> 24;
        output[base + j * 4 + 1] = (acc[j] >> 16) & 0xff;
        output[base + j * 4 + 2] = (acc[j] >> 8) & 0xff;
        output[base + j * 4 + 3] = acc[j] & 0xff;
      }
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

const List<int> _sha256Init = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

/// دالة ضغط SHA-256 (FIPS 180-4) على حالة 8 كلمات — لا تُستخدم إلا داخل [Pbkdf2.derive].
class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  /// ضغط كتلة من 64 بايت (كتلة مفتاح HMAC).
  static void compressBytes(Uint32List state, Uint8List block) {
    final w = Uint32List(64);
    for (var i = 0; i < 16; i++) {
      w[i] = (block[i * 4] << 24) | (block[i * 4 + 1] << 16) | (block[i * 4 + 2] << 8) | block[i * 4 + 3];
    }
    _run(state, w);
  }

  /// ضغط الكتلة الأخيرة لرسالة من 32 بايت تلي كتلة مفتاح: الكلمات الثماني ثم
  /// بت الحشوة ثم الطول الكلي 768 بت.
  static void compressDigest(Uint32List state, Uint32List w, Uint32List digest) {
    for (var i = 0; i < 8; i++) {
      w[i] = digest[i];
    }
    w[8] = 0x80000000;
    for (var i = 9; i < 15; i++) {
      w[i] = 0;
    }
    w[15] = 768;
    _run(state, w);
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  static void _run(Uint32List state, Uint32List w) {
    for (var i = 16; i < 64; i++) {
      final x = w[i - 15];
      final y = w[i - 2];
      final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
      final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = state[0], b = state[1], c = state[2], d = state[3];
    var e = state[4], f = state[5], g = state[6], h = state[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    state[0] = (state[0] + a) & 0xffffffff;
    state[1] = (state[1] + b) & 0xffffffff;
    state[2] = (state[2] + c) & 0xffffffff;
    state[3] = (state[3] + d) & 0xffffffff;
    state[4] = (state[4] + e) & 0xffffffff;
    state[5] = (state[5] + f) & 0xffffffff;
    state[6] = (state[6] + g) & 0xffffffff;
    state[7] = (state[7] + h) & 0xffffffff;
  }
}
