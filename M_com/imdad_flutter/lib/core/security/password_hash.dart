import 'package:flutter/foundation.dart';

import 'pbkdf2.dart';

/// بصمة كلمة مرور جاهزة للحفظ في جدول المستخدمين (الأعمدة الثلاثة معًا).
class PasswordHash {
  const PasswordHash({required this.saltHex, required this.hashHex, required this.iterations});

  final String saltHex;
  final String hashHex;
  final int iterations;

  /// بصمة جديدة بملح جديد وبالعدد الحالي من الدورات.
  ///
  /// الاشتقاق يعمل في Isolate منفصل حتى لا تتجمد الواجهة أثناءه (على الويب
  /// يعمل `compute` في الخيط نفسه).
  static Future<PasswordHash> create(String password) async {
    final salt = Pbkdf2.newSaltHex();
    const n = Pbkdf2.iterations;
    final hash = await compute(_derive, (password, salt, n));
    return PasswordHash(saltHex: salt, hashHex: hash, iterations: n);
  }

  /// مطابقة كلمة مرور مع بصمة محفوظة بعدد دوراتها هي (لا العدد الحالي).
  static Future<bool> verify(String password, String saltHex, String hashHex, int iterations) async {
    if (saltHex.isEmpty || hashHex.isEmpty || iterations < 1) return false;
    final derived = await compute(_derive, (password, saltHex, iterations));
    return Pbkdf2.constantTimeEquals(derived, hashHex);
  }

  /// هل البصمة أضعف من المعيار الحالي فتُعاد تجزئتها عند الدخول الناجح؟
  static bool needsUpgrade(int iterations) => iterations < Pbkdf2.iterations;
}

String _derive((String, String, int) a) => Pbkdf2.deriveHex(a.$1, a.$2, iterations: a.$3);
