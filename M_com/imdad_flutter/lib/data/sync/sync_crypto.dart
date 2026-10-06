import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:pointycastle/export.dart';

import '../../core/security/pbkdf2.dart';

/// رمز الاقتران: ٨ أحرف من أبجدية ٣٢ حرفًا (٣٢⁸ ≈ ١٫١ تريليون احتمال).
///
/// الأبجدية بلا `I` و`O` و`0` و`1` لأن الرمز يُقرأ من شاشة ويُملى على مشغّل آخر،
/// والحروف المتشابهة أول مصادر الخطأ في ذلك.
class PairingCode {
  const PairingCode._();

  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int length = 8;

  static String generate() {
    final rnd = Random.secure();
    return List.generate(length, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  }

  /// يوحّد ما كتبه المشغّل (حروف صغيرة، شرطة، مسافات) ويعيد الرمز، أو `null`
  /// إن لم يكن رمزًا صالحًا.
  static String? normalize(String input) {
    final code = input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (code.length != length) return null;
    for (final ch in code.split('')) {
      if (!alphabet.contains(ch)) return null;
    }
    return code;
  }

  /// للعرض: `XXXX-XXXX`.
  static String format(String code) =>
      code.length == length ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
}

/// مفاتيح الاقتران: ECDH (P-256) مؤقت على الجهازين يُمزج برمز الاقتران.
///
/// **لماذا ليس الرمز وحده:** كان مفتاح الجلسة مشتقًّا من الرمز فقط، فمن يلتقط
/// طلبًا موقَّعًا واحدًا على الشبكة يجرّب الرموز دون اتصال حتى يطابق التوقيع.
/// وهذا المفتاح هو أصل المفتاح الدائم للثقة، فكسره يعني اقترانًا دائمًا.
/// الآن مفتاح الجلسة = HMAC(مشتق الرمز، سر ECDH ‖ المفتاحان العامان). المتنصّت
/// السلبي لا يملك أيًّا من المفتاحين الخاصين المؤقتين، فلا شيء يخمّنه دون اتصال.
/// المهاجم النشط وسط الاقتران يحتاج الرمز نفسه (١٫١ تريليون احتمال × ١٠٠ ألف دورة).
class PairingKeys {
  const PairingKeys._();

  /// دورات اشتقاق الرمز. الكلفة تُدفع مرة عند الاقتران لا عند كل طلب.
  static const int iterations = 100000;

  static final ECDomainParameters _domain = ECCurve_secp256r1();

  // الحقل الأولي لمنحنى P-256.
  static final BigInt _p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16,
  );

  static Uint8List codeKey(String code, List<int> salt) =>
      Pbkdf2.derive(utf8.encode(code), salt, iterations: iterations, length: 32);

  /// زوج مفاتيح مؤقت: المفتاح الخاص (hex) والعام (٦٥ بايت غير مضغوط).
  static ({String privHex, Uint8List pub}) newKeyPair() {
    final rnd = Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()),
        FortunaRandom()..seed(KeyParameter(seed)),
      ));
    final pair = gen.generateKeyPair();
    return (
      privHex: Pbkdf2.toHex(_bytesOf(pair.privateKey.d!)),
      pub: pair.publicKey.Q!.getEncoded(false),
    );
  }

  /// مفتاح الجلسة من طرف أحد الجهازين. ترتيب الإدخال (المستقبِل ثم المرسِل)
  /// ثابت حتى يبلغ الطرفان القيمة نفسها.
  static Uint8List sessionKey({
    required Uint8List codeKey,
    required String privHex,
    required Uint8List theirPub,
    required Uint8List receiverPub,
    required Uint8List senderPub,
  }) {
    final point = _decode(theirPub);
    final agreement = ECDHBasicAgreement()..init(ECPrivateKey(BigInt.parse(privHex, radix: 16), _domain));
    final shared = agreement.calculateAgreement(ECPublicKey(point, _domain));
    final msg = <int>[
      ...utf8.encode('imdad-pair-v3'),
      ..._bytesOf(shared),
      ...receiverPub,
      ...senderPub,
    ];
    return Uint8List.fromList(Hmac(sha256, codeKey).convert(msg).bytes);
  }

  /// يفكّ نقطة عامة ويرفض ما ليس على المنحنى (هجوم المنحنى غير الصالح).
  static ECPoint _decode(Uint8List bytes) {
    if (bytes.length != 65 || bytes[0] != 4) {
      throw const SyncCryptoError('مفتاح اقتران غير صالح');
    }
    final x = BigInt.parse(Pbkdf2.toHex(bytes.sublist(1, 33)), radix: 16);
    final y = BigInt.parse(Pbkdf2.toHex(bytes.sublist(33)), radix: 16);
    final a = _domain.curve.a!.toBigInteger()!;
    final b = _domain.curve.b!.toBigInteger()!;
    final onCurve = x < _p && y < _p && (y * y - (x * x * x + a * x + b)) % _p == BigInt.zero;
    if (!onCurve) throw const SyncCryptoError('مفتاح اقتران غير صالح');
    return _domain.curve.decodePoint(bytes)!;
  }

  /// تحقق مسبق من مفتاح عام قادم من الشبكة. يعيد `false` بدل الرمي.
  static bool isValidPublic(Uint8List bytes) {
    try {
      _decode(bytes);
      return true;
    } on SyncCryptoError {
      return false;
    }
  }

  static Uint8List _bytesOf(BigInt v) {
    final out = Uint8List(32);
    var n = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    return out;
  }
}

/// عرض الاقتران على الجهاز **المستقبِل**: الرمز والملح ومفتاح مؤقت. عمره قصير،
/// ولا يُستعمل بعد انتهاء مدته أو بعد إغلاق الاستقبال.
class PairingOffer {
  PairingOffer._({
    required this.code,
    required this.salt,
    required this.expiresAt,
    required Uint8List codeKey,
    required String privHex,
    required this.pub,
  })  : _codeKey = codeKey,
        _privHex = privHex;

  /// الرمز المعروض للمشغّل (٨ أحرف بلا شرطة).
  final String code;
  final Uint8List salt;
  final DateTime expiresAt;
  final Uint8List pub;
  final Uint8List _codeKey;
  final String _privHex;

  /// جلسات من اقترنوا بهذا العرض، بمفتاحهم المؤقت. تُحفظ لأن كل طلب بعد
  /// الأول يحمل المفتاح نفسه، واشتقاقه كل مرة هدر.
  final Map<String, SyncSession> _sessions = {};

  /// بصمة مفتاح آخر اقتران ناجح — تُعرض على الجهازين للتأكد من تطابقه.
  String? pairedFingerprint;

  /// مفاتيح اقتران سبق تسجيل نجاحها في التدقيق (مرة لكل اقتران لا لكل طلب).
  final Set<String> announced = {};

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  String get saltB64 => base64Encode(salt);
  String get pubB64 => base64Encode(pub);

  static const Duration defaultTtl = Duration(minutes: 10);

  /// عرض جديد. الاشتقاق ثقيل (١٠٠ ألف دورة) فيجري في Isolate لئلا تتجمد الواجهة.
  static Future<PairingOffer> create({Duration ttl = defaultTtl}) async {
    final r = await compute(_newOfferTask, 0);
    return PairingOffer._(
      code: r.code,
      salt: r.salt,
      expiresAt: DateTime.now().add(ttl),
      codeKey: r.codeKey,
      privHex: r.privHex,
      pub: r.pub,
    );
  }

  /// جلسة الطرف الذي أرسل مفتاحه المؤقت [epkB64]، أو `null` إن لم يكن صالحًا.
  SyncSession? sessionFor(String epkB64) {
    final cached = _sessions[epkB64];
    if (cached != null) return cached;
    try {
      final senderPub = Uint8List.fromList(base64Decode(epkB64));
      final key = PairingKeys.sessionKey(
        codeKey: _codeKey,
        privHex: _privHex,
        theirPub: senderPub,
        receiverPub: pub,
        senderPub: senderPub,
      );
      if (_sessions.length >= 8) _sessions.clear();
      return _sessions[epkB64] = SyncSession.fromKey(key, ttl: expiresAt.difference(DateTime.now()));
    } on SyncCryptoError {
      return null;
    } on FormatException {
      return null;
    }
  }
}

({String code, Uint8List salt, Uint8List codeKey, String privHex, Uint8List pub}) _newOfferTask(int _) {
  final rnd = Random.secure();
  final code = PairingCode.generate();
  final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
  final pair = PairingKeys.newKeyPair();
  return (
    code: code,
    salt: salt,
    codeKey: PairingKeys.codeKey(code, salt),
    privHex: pair.privHex,
    pub: pair.pub,
  );
}

({Uint8List key, String epk}) _clientDeriveTask((String, String, String) a) {
  final code = a.$1;
  final salt = base64Decode(a.$2);
  final receiverPub = Uint8List.fromList(base64Decode(a.$3));
  if (!PairingKeys.isValidPublic(receiverPub)) {
    throw const SyncCryptoError('مفتاح اقتران غير صالح');
  }
  final pair = PairingKeys.newKeyPair();
  final key = PairingKeys.sessionKey(
    codeKey: PairingKeys.codeKey(code, salt),
    privHex: pair.privHex,
    theirPub: receiverPub,
    receiverPub: receiverPub,
    senderPub: pair.pub,
  );
  return (key: key, epk: base64Encode(pair.pub));
}

/// أمن المزامنة عبر الشبكة المحلية.
///
/// قبل هذه الطبقة كان الجهاز المستقبِل يفتح منفذًا مفتوحًا للجميع: أي جهاز على
/// الشبكة يسحب قاعدة البيانات كاملة من `/export` أو يدمج ما يشاء عبر `/import`.
///
/// الآن: المستقبِل يولّد **رمز اقتران** من ٨ أحرف ([PairingCode]) يُعرض على شاشته،
/// ويُدخله المشغّل في الجهاز المرسِل. من الرمز وتبادل مفتاحين مؤقتين (ECDH،
/// انظر [PairingKeys]) يُشتق مفتاح جلسة لا يعبر الشبكة إطلاقًا، ومنه مفتاحان
/// فرعيان: واحد لتوقيع الطلبات وآخر لتشفير الحمولة.
///
/// • كل طلب موقَّع بـ HMAC-SHA256 على (الفعل + المسار + الوقت + nonce + بصمة الجسم).
/// • الوقت يُرفض إن انحرف أكثر من خمس دقائق، والـ nonce لا يُقبل مرتين (منع إعادة الإرسال).
/// • الحمولة مشفَّرة بـ AES-256-GCM، فلا يكشفها من يتنصّت على الشبكة.
/// • للجلسة عمر محدود ينتهي بإغلاق الخادم تلقائيًا.
class SyncSession {
  SyncSession._({
    required this.key,
    required this.expiresAt,
    this.pairingEpk,
  });

  /// مفتاح الجلسة — لا يغادر الجهاز أبدًا.
  final Uint8List key;

  final DateTime expiresAt;

  /// المفتاح العام المؤقت للمرسِل (base64) في جلسة اقتران: يُرسَل مع كل طلب
  /// ليشتق المستقبِل المفتاح نفسه. `null` في جلسات الثقة الدائمة.
  final String? pairingEpk;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// بصمة قصيرة للمفتاح تُعرض على الجهازين للتأكد من تطابق الاقتران.
  String get fingerprint {
    final d = sha256.convert([...key, ...utf8.encode('fp')]).bytes;
    return Pbkdf2.toHex(d.sublist(0, 3)).toUpperCase();
  }

  /// مدة الجلسة الافتراضية: عشر دقائق تكفي لمزامنة ثم يُغلق المنفذ وحده.
  static const Duration defaultTtl = PairingOffer.defaultTtl;

  /// جلسة على الجهاز المرسِل: الرمز يُدخله المشغّل، والملح والمفتاح العام
  /// يأتيان من `/hello`. يرمي [SyncCryptoError] إن كان المفتاح العام غير صالح.
  static Future<SyncSession> fromPairing(
    String code,
    String saltB64,
    String receiverPubB64, {
    Duration ttl = defaultTtl,
  }) async {
    final r = await compute(_clientDeriveTask, (code, saltB64, receiverPubB64));
    return SyncSession._(
      key: r.key,
      expiresAt: DateTime.now().add(ttl),
      pairingEpk: r.epk,
    );
  }

  /// جلسة من **مفتاح ثقة محفوظ** — اقتران دائم بلا رمز ولا مشغّل.
  ///
  /// هذه هي ركيزة المزامنة التلقائية: الرمز يصلح لمرة واحدة
  /// بحضور إنسان، ولا يصلح لجهاز يزامن وحده كل ربع ساعة. فبعد اقتران يدوي
  /// واحد يُشتقّ من مفتاح الجلسة مفتاحٌ دائم ([trustKeyFor]) يُحفظ على
  /// الجهازين، وتُبنى منه هذه الجلسة عند كل مزامنة لاحقة. لا رمز يُخمَّن هنا:
  /// السر مفتاح ٢٥٦ بت لا رمزًا قصيرًا.
  factory SyncSession.fromKey(Uint8List key, {Duration ttl = trustedTtl}) => SyncSession._(
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
      // بصمة الجسم معلنةً: تتيح للمستقبِل التحقق من التوقيع قبل قراءة الجسم.
      headerBodyDigest: sha256.convert(body).toString(),
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
  }) =>
      _verify(
        method: method,
        path: path,
        ts: ts,
        nonce: nonce,
        mac: mac,
        digest: sha256.convert(body).toString(),
        seenNonces: seenNonces,
      );

  /// التحقق **قبل قراءة الجسم**: التوقيع يشمل بصمة الجسم، والمرسِل يعلنها في
  /// [headerBodyDigest]. فيُتحقَّق من التوقيع على البصمة المعلنة أولًا (رخيصٌ ولا
  /// يُقرأ به بايت)، ثم يُقرأ الجسم بسقفه ويُطابَق بالبصمة ([digestMatches]).
  /// طلبٌ لا يملك صاحبه المفتاح يسقط هنا فلا يستنزف ذاكرة الجهاز بجسمٍ ضخم.
  String? verifyPreBody({
    required String method,
    required String path,
    required String? ts,
    required String? nonce,
    required String? mac,
    required String claimedDigest,
    required Set<String> seenNonces,
  }) =>
      _verify(
        method: method,
        path: path,
        ts: ts,
        nonce: nonce,
        mac: mac,
        digest: claimedDigest,
        seenNonces: seenNonces,
      );

  /// هل بصمة الجسم المقروء هي المعلنة (والموقَّعة)؟
  static bool digestMatches(List<int> body, String claimedDigest) =>
      Pbkdf2.constantTimeEquals(sha256.convert(body).toString(), claimedDigest);

  String? _verify({
    required String method,
    required String path,
    required String? ts,
    required String? nonce,
    required String? mac,
    required String digest,
    required Set<String> seenNonces,
  }) {
    if (ts == null || nonce == null || mac == null) return 'طلب بلا توقيع';
    final at = int.tryParse(ts);
    if (at == null) return 'ختم زمني غير صالح';
    final skew = (DateTime.now().millisecondsSinceEpoch - at).abs();
    if (skew > maxSkew.inMilliseconds) return 'فارق التوقيت كبير — اضبط ساعة الجهازين';
    if (!seenNonces.add(nonce)) return 'طلب مكرر (إعادة إرسال)';
    if (!Pbkdf2.constantTimeEquals(mac, _macOfDigest(method, path, ts, nonce, digest))) {
      return 'توقيع غير مطابق';
    }
    return null;
  }

  String _mac(String method, String path, String ts, String nonce, List<int> body) =>
      _macOfDigest(method, path, ts, nonce, sha256.convert(body).toString());

  String _macOfDigest(String method, String path, String ts, String nonce, String digest) {
    final msg = '$method\n$path\n$ts\n$nonce\n$digest';
    return base64Encode(Hmac(sha256, _macKey).convert(utf8.encode(msg)).bytes);
  }

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

  /// SHA-256 (hex) لجسم الطلب — داخلٌ في التوقيع، ومعلنٌ ليُتحقَّق منه قبل قراءة الجسم.
  static const String headerBodyDigest = 'x-imdad-body';

  /// معرّف الجهاز الطالب — به يعرف المستقبِل أي مفتاح ثقة يتحقق به.
  /// ليس سرًّا ولا يُصدَّق وحده: التوقيع هو ما يُثبت الهوية.
  static const String headerDevice = 'x-imdad-device';

  /// المفتاح العام المؤقت للمرسِل في جلسة اقتران (base64). غيابه من جهاز غير
  /// موثوق يعني إصدارًا قديمًا (v2) لا يعرف الاقتران بـ ECDH.
  static const String headerPairKey = 'x-imdad-epk';

  /// أقصى انحراف مقبول بين ساعتي الجهازين.
  static const Duration maxSkew = Duration(minutes: 5);
}

class SyncCryptoError implements Exception {
  const SyncCryptoError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// سجلّ الـnonce المستهلكة لمنع إعادة الإرسال — **مقلَّمٌ بالزمن**.
///
/// الطلب لا يُقبل إلا في نافذة [SyncSession.maxSkew] حول ساعة المستقبِل، فنonce
/// أقدم من ضعف النافذة لا يمكن أن يعود صالحًا ولا حاجة لحفظه. بلا تقليم كان
/// المجموعُ ينمو مع كل طلب ما دام الاستقبال مفتوحًا. [maxEntries] سقفٌ صلب:
/// عند بلوغه يُرفض الجديد (مغلقٌ لا مفتوح) بدل أن ينمو بلا حد.
class NonceCache {
  NonceCache({
    this.ttl = const Duration(minutes: 11),
    this.maxEntries = 100000,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;

  // خريطة مرتَّبة بالإدخال = مرتَّبة بالزمن، فالتقليم يقرأ من رأسها وحده.
  final Map<String, int> _seen = {};

  int get length => _seen.length;

  /// يسجّل [nonce]؛ `false` إن سبق (إعادة إرسال) أو امتلأ السجل.
  bool add(String nonce) {
    final t = _now().millisecondsSinceEpoch;
    _prune(t);
    if (_seen.containsKey(nonce) || _seen.length >= maxEntries) return false;
    _seen[nonce] = t;
    return true;
  }

  void _prune(int nowMs) {
    final cutoff = nowMs - ttl.inMilliseconds;
    while (_seen.isNotEmpty && _seen.values.first < cutoff) {
      _seen.remove(_seen.keys.first);
    }
  }

  void clear() => _seen.clear();
}
