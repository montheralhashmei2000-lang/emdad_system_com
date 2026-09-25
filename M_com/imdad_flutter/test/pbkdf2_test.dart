import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/pbkdf2.dart';

/// قيم مرجعية مأخوذة من النظام الحالي (WebCrypto PBKDF2-HMAC-SHA256) حرفيًا،
/// حتى تعمل حسابات المستخدمين المُرحَّلة في التطبيق الجديد دون إعادة تعيين كلمات المرور.
void main() {
  group('PBKDF2 مطابق لنسخة الويب', () {
    test('كلمة مرور لاتينية · 45,000 دورة', () {
      final hash = Pbkdf2.deriveHex(
        'Admin#12345',
        'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        iterations: Pbkdf2.legacyIterations,
      );
      expect(hash, '126a93206f5d47d8466ae625f0470bc73b835c9569a10b34db5b91356f4ef4e7');
    });

    test('كلمة مرور عربية (UTF-8) · 45,000 دورة', () {
      final hash = Pbkdf2.deriveHex(
        'كلمة المرور',
        '00112233445566778899aabbccddeeff',
        iterations: Pbkdf2.legacyIterations,
      );
      expect(hash, '76327c2f79784042286b93c84cc70d100eeaa6160d82b01ee3012c861c64bef3');
    });

    test('عدد دورات مختلف (1,000) للتأكد من صحة التنفيذ لا الثوابت', () {
      final hash = Pbkdf2.deriveHex(
        'x',
        '0f0e0d0c0b0a09080706050403020100',
        iterations: 1000,
      );
      expect(hash, '3830d1e88b6dd2bc0edbcfcb67e633a1975a193b143a748b5a588a759aed8147');
    });

    test('متجهات RFC 7914 (PBKDF2-HMAC-SHA256)', () {
      // مستقلة عن نسخة الويب: تحرس التنفيذ السريع للحلقة الداخلية وطول مخرج أطول من كتلة.
      expect(
        Pbkdf2.toHex(Pbkdf2.derive('passwd'.codeUnits, 'salt'.codeUnits, iterations: 1, length: 64)),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
      expect(
        Pbkdf2.toHex(Pbkdf2.derive('Password'.codeUnits, 'NaCl'.codeUnits, iterations: 80000, length: 64)),
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
        'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
      );
    });

    test('مفتاح أطول من كتلة SHA-256 (64 بايت) يُختصر أولًا', () {
      final long = List.filled(100, 0x61); // 'a' × 100
      expect(
        Pbkdf2.toHex(Pbkdf2.derive(long, 'salt'.codeUnits, iterations: 2)),
        Pbkdf2.toHex(Pbkdf2.derive(sha256Of(long), 'salt'.codeUnits, iterations: 2)),
      );
    });

    test('الملح الجديد بطول 32 حرفًا hex ويختلف في كل مرة', () {
      final a = Pbkdf2.newSaltHex();
      final b = Pbkdf2.newSaltHex();
      expect(a.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('المقارنة بزمن ثابت', () {
      expect(Pbkdf2.constantTimeEquals('abc', 'abc'), isTrue);
      expect(Pbkdf2.constantTimeEquals('abc', 'abd'), isFalse);
      expect(Pbkdf2.constantTimeEquals('abc', 'ab'), isFalse);
    });

    test('تحويل hex ذهابًا وإيابًا', () {
      const hex = 'deadbeef0102';
      expect(Pbkdf2.toHex(Pbkdf2.fromHex(hex)), hex);
    });
  });
}

List<int> sha256Of(List<int> v) => sha256.convert(v).bytes;
