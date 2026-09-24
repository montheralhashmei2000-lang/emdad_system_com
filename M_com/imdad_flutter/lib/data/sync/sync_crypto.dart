import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../../core/security/pbkdf2.dart';

/// أمن المزامنة عبر الشبكة المحلية.
///
/// قبل هذه الطبقة كان الجهاز المستقبِل يفتح منفذًا مفتوحًا للجميع: أي جهاز على
/// الشبكة يسحب قاعدة البيانات كاملة من `/export` أو يدمج ما يشاء عبر `/import`.
///
/// الآن: المستقبِل يولّد **رمز اقتران** من ٦ أرقام يُعرض على شاشته، ويُدخله
/// المشغّل في الجهاز المرسِل. يُشتق من الرمز مفتاح جلسة (PBKDF2) لا يعبر الشبكة
/// إطلاقًا، ومنه مفتاحان فرعيان: واحد لتوقيع الطلبات وآخر لتشفير الحمولة.
///
/// • كل طلب موقَّع بـ HMAC-SHA256 على (الفعل + المسار + الوقت + nonce + بصمة الجسم).
/// • الوقت يُرفض إن انحرف أكثر من خمس دقائق، والـ nonce لا يُقبل مرتين (منع إعادة الإرسال).
/// • الحمولة مشفَّرة بـ AES-256-GCM، فلا يكشفها من يتنصّت على الشبكة.
/// • للجلسة عمر محدود ينتهي بإغلاق الخادم تلقائيًا.
class SyncSession {
  SyncSession._({
    required this.code,
    required this.salt,
    required this.key,
    required this.expiresAt,
  });

  /// رمز الاقتران المعروض على الجهاز المستقبِل (٦ أرقام).
  final String code;

  /// ملح الاشتقاق — يُعلن مع الترحيب لأنه ليس سرًّا، والسر هو الرمز وحده.
  final Uint8List salt;

  /// مفتاح الجلسة — لا يغادر الجهاز أبدًا.
  final Uint8List key;

  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get saltB64 => base64Encode(salt);

  /// بصمة قصيرة للمفتاح تُعرض على الجهازين للتأكد من تطابق الاقتران.
  String get fingerprint {
    final d = sha256.convert([...key, ...utf8.encode('fp')]).bytes;
    return Pbkdf2.toHex(d.sublist(0, 3)).toUpperCase();
  }

  /// مدة الجلسة الافتراضية: عشر دقائق تكفي لمزامنة ثم يُغلق المنفذ وحده.
  static const Duration defaultTtl = Duration(minutes: 10);

  /// عدد دورات الاشتقاق. أقل من دورات كلمات المرور لأن الجلسة قصيرة العمر
  /// والرمز يتبدّل في كل مرة، ولأن الاشتقاق يجري على هاتف عند كل طلب.
  static const int _iterations = 12000;

  /// جلسة جديدة على الجهاز المستقبِل — يُولَّد لها رمز وملح عشوائيان.
  factory SyncSession.create({Duration ttl = defaultTtl}) {
    final rnd = Random.secure();
    final code = List.generate(6, (_) => rnd.nextInt(10)).join();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    return SyncSession._(
      code: code,
      salt: salt,
      key: Pbkdf2.derive(utf8.encode(code), salt, iterations: _iterations, length: 32),
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// جلسة على الجهاز المرسِل: الرمز يُدخله المشغّل، والملح يأتي من `/hello`.
  factory SyncSession.fromCode(String code, String saltB64, {Duration ttl = defaultTtl}) {
    final salt = Uint8List.fromList(base64Decode(saltB64));
    return SyncSession._(
      code: code,
      salt: salt,
      key: Pbkdf2.derive(utf8.encode(code), salt, iterations: _iterations, length: 32),
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// جلسة من **مفتاح ثقة محفوظ** — اقتران دائم بلا رمز ولا مشغّل.
  ///
  /// هذه هي ركيزة المزامنة التلقائية: الرمز ذو الأرقام الستة يصلح لمرة واحدة
  /// بحضور إنسان، ولا يصلح لجهاز يزامن وحده كل ربع ساعة. فبعد اقتران يدوي
  /// واحد يُشتقّ من مفتاح الجلسة مفتاحٌ دائم ([trustKeyFor]) يُحفظ على
  /// الجهازين، وتُبنى منه هذه الجلسة عند كل مزامنة لاحقة. لا رمز يُخمَّن هنا:
  /// السر مفتاح ٢٥٦ بت لا ستة أرقام.
  factory SyncSession.fromKey(Uint8List key, {Duration ttl = trustedTtl}) => SyncSession._(
        code: '',
        salt: Uint8List(0),
        key: Uint8List.fromList(key),
        expiresAt: DateTime.now().add(ttl),
      );

  /// المفتاح الدائم بين هذا الجهاز وجهاز معرّفه [peerDeviceId].
  ///
  /// يُشتقّ من مفتاح الاقتران، فلا يوجد إلا بعد أن أدخل إنسانٌ الرمز الصحيح.
  /// والاشتقاق باسم الجهاز الطالب وحده حتى يبلغ الطرفان القيمة نفسها بلا
  /// اتفاق على ترتيب.
  Uint8List trustKeyFor(String peerDeviceId) => Uint8List.fromList(
        Hmac(sha256, key).convert(utf8.encode('trust:$peerDeviceId')).bytes,
      );

  /// عمر جلسة الثقة: ساعة تكفي لأي مزامنة، وتُبنى جلسة جديدة عند كل دورة.
  static const Duration trustedTtl = Duration(hours: 1);

  Uint8List get _macKey => _subKey('mac');
  Uint8List get _encKey => _subKey('enc');

  /// مفتاح فرعي لكل غرض حتى لا يُستعمل مفتاح واحد للتوقيع والتشفير معًا.
  Uint8List _subKey(String purpose) =>
      Uint8List.fromList(Hmac(sha256, key).convert(utf8.encode(purpose)).bytes);

  // ───────────────────────── توقيع الطلبات

  /// ترويسات التوقيع لطلب واحد. `body` هو الجسم بعد التشفير (أو فارغ).
  ///
  /// [skewMs] فرق ساعة الجهاز المستقبِل عن ساعتنا، يُعرف من ترحيبه المفتوح.
  /// الختم يُكتب **بساعته هو** لا بساعتنا: النظام يعمل بلا إنترنت، وأجهزة
  /// الميدان لا تجد خادم وقت فتنحرف ساعاتها بالأيام. فلو وُقّع بساعتنا لتوقفت
  /// المزامنة كلها لأن هاتفًا تأخّر سبع دقائق — وذلك خللٌ لا حماية.
  ///
  /// والحماية لا تضعف: نافذة [maxSkew] تبقى ضيّقة **بمقياس ساعة المستقبِل**،
  /// وهي المقياس الوحيد الذي يملكه ليحكم على عمر الطلب.
  Map<String, String> signHeaders(
    String method,
    String path,
    List<int> body, {
    int skewMs = 0,
  }) {
    final rnd = Random.secure();
    final nonce = base64Encode(List.generate(12, (_) => rnd.nextInt(256)));
    final ts = (DateTime.now().millisecondsSinceEpoch + skewMs).toString();
    return {
      headerTs: ts,
      headerNonce: nonce,
      headerMac: _mac(method, path, ts, nonce, body),
    };
  }

  /// يتحقق من توقيع طلب وارد. يعيد رسالة الخطأ، أو `null` إذا كان سليمًا.
  String? verify({
    required String method,
    required String path,
    required String? ts,
    required String? nonce,
    required String? mac,
    required List<int> body,
    required Set<String> seenNonces,
  }) {
    if (ts == null || nonce == null || mac == null) return 'طلب بلا توقيع';
    final at = int.tryParse(ts);
    if (at == null) return 'ختم زمني غير صالح';
    final skew = (DateTime.now().millisecondsSinceEpoch - at).abs();
    if (skew > maxSkew.inMilliseconds) return 'فارق التوقيت كبير — اضبط ساعة الجهازين';
    if (!seenNonces.add(nonce)) return 'طلب مكرر (إعادة إرسال)';
    if (!Pbkdf2.constantTimeEquals(mac, _mac(method, path, ts, nonce, body))) {
      return 'توقيع غير مطابق';
    }
    return null;
  }

  String _mac(String method, String path, String ts, String nonce, List<int> body) {
    final digest = sha256.convert(body).toString();
    final msg = '$method\n$path\n$ts\n$nonce\n$digest';
    return base64Encode(Hmac(sha256, _macKey).convert(utf8.encode(msg)).bytes);
  }

  // ───────────────────────── تشفير الحمولة

  /// AES-256-GCM. الناتج: متجه التهيئة (١٢ بايت) ثم النص المشفَّر ثم بصمة السلامة.
  Uint8List encrypt(List<int> plain) {
    final rnd = Random.secure();
    final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_encKey), 128, iv, Uint8List(0)));
    final out = cipher.process(Uint8List.fromList(plain));
    return Uint8List.fromList([...iv, ...out]);
  }

  /// يفكّ التشفير ويتحقق من السلامة. يرمي [SyncCryptoError] إن عُبث بالحمولة.
  Uint8List decrypt(List<int> data) {
    if (data.length < 12 + 16) throw const SyncCryptoError('حمولة أقصر من أن تكون صحيحة');
    final iv = Uint8List.fromList(data.sublist(0, 12));
    final body = Uint8List.fromList(data.sublist(12));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_encKey), 128, iv, Uint8List(0)));
    try {
      return cipher.process(body);
    } on InvalidCipherTextException {
      throw const SyncCryptoError('الحمولة مُعدَّلة أو الرمز غير مطابق');
    }
  }

  /// تغليف خريطة JSON: تُرمَّز ثم تُشفَّر.
  Uint8List sealJson(Map<String, dynamic> map) => encrypt(utf8.encode(jsonEncode(map)));

  /// فتح خريطة JSON مشفَّرة.
  Map<String, dynamic> openJson(List<int> data) =>
      jsonDecode(utf8.decode(decrypt(data))) as Map<String, dynamic>;

  static const String headerTs = 'x-imdad-ts';
  static const String headerNonce = 'x-imdad-nonce';
  static const String headerMac = 'x-imdad-mac';

  /// معرّف الجهاز الطالب — به يعرف المستقبِل أي مفتاح ثقة يتحقق به.
  /// ليس سرًّا ولا يُصدَّق وحده: التوقيع هو ما يُثبت الهوية.
  static const String headerDevice = 'x-imdad-device';

  /// أقصى انحراف مقبول بين ساعتي الجهازين.
  static const Duration maxSkew = Duration(minutes: 5);
}

class SyncCryptoError implements Exception {
  const SyncCryptoError(this.message);
  final String message;
  @override
  String toString() => message;
}
