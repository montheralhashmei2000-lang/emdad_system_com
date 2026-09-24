import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';

/// التوقيع الإلكتروني للمستندات — ECDSA على المنحنى P-256.
///
/// المرحلة السابقة كانت ختمًا داخليًا بـ HMAC: يثبت أن المستند لم يُعدَّل على
/// **هذا الجهاز**، لأن المفتاح نفسه يوقّع ويتحقق — فمن يملك الجهاز يستطيع
/// تزوير أي ختم. (ونسخة الويب أضعف: تولّد مفتاح RSA ولا توقّع به شيئًا.)
///
/// الآن مفتاحان: خاصٌّ لا يغادر جهاز الموقِّع، وعامٌّ يُنشر ويُتحقق به. يصير
/// السند المطبوع قابلًا للتدقيق خارج النظام: رمز QR أسفله يحمل التوقيع، ومن
/// يملك المفتاح العام يتحقق منه بلا وصول إلى قاعدة البيانات.
///
/// التوقيع حتمي (RFC 6979): التوقيع نفسه على المستند نفسه يعطي النتيجة نفسها،
/// فلا يعتمد أمانه على جودة مولّد العشوائية لحظة التوقيع.
class ESign {
  ESign(this.db);

  final AppDatabase db;

  static const String _key = 'esign';

  /// بادئة رمز التحقق المطبوع — رقم النسخة يسمح بتغيير الصيغة لاحقًا.
  static const String qrPrefix = 'IMD1';

  // ───────────────────────── المفاتيح

  /// هل جُهِّز مفتاح الموقِّع على هذا الجهاز؟
  Future<bool> hasKey([String owner = 'commander']) async =>
      (await _read(owner))['priv']?.isNotEmpty ?? false;

  /// تاريخ تهيئة المفتاح، أو فارغ إن لم يُهيَّأ.
  Future<String> createdAt([String owner = 'commander']) async =>
      (await _read(owner))['at'] ?? '';

  /// المفتاح العام (نقطة مضغوطة، Base64) — هذا ما يُنشر ويُتحقق به.
  Future<String> publicKey([String owner = 'commander']) async =>
      (await _read(owner))['pub'] ?? '';

  /// معرّف المفتاح: ثمانية أحرف من بصمة المفتاح العام، يُطبع مع التوقيع
  /// ليعرف المتحقِّق أيّ مفتاح يستعمل.
  Future<String> keyId([String owner = 'commander']) async =>
      (await _read(owner))['kid'] ?? '';

  /// ينشئ زوج مفاتيح للموقِّع إن لم يوجد. لا يستبدل مفتاحًا قائمًا لأن ذلك
  /// يُبطل كل التواقيع السابقة.
  Future<void> ensureKey([String owner = 'commander']) async {
    if (await hasKey(owner)) return;

    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()),
        _seededRandom(),
      ));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;
    final pubBytes = pub.Q!.getEncoded(true);

    await _write(owner, {
      'priv': _hex(_bigIntBytes(priv.d!, 32)),
      'pub': base64Encode(pubBytes),
      'kid': keyIdOf(base64Encode(pubBytes)),
      'at': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
    });
  }

  /// حذف المفتاح — يُبطل التحقق من كل ما وُقّع به، فيُستعمل عند تسليم العهدة فقط.
  Future<void> removeKey([String owner = 'commander']) async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_key);
    map.remove(owner);
    await settings.write(_key, map);
  }

  /// بصمة مفتاح عام — تُشتق منه وحده فتتطابق على كل الأجهزة.
  static String keyIdOf(String publicKeyB64) {
    final digest = sha256.convert(base64Decode(publicKeyB64)).bytes;
    return _hex(digest.sublist(0, 4)).toUpperCase();
  }

  // ───────────────────────── التوقيع والتحقق

  /// يوقّع مستندًا ويعيد رمزًا مضغوطًا صالحًا للطباعة في QR، أو `null` إن لم
  /// يكن للموقِّع مفتاح على هذا الجهاز.
  Future<String?> sign({
    required String docRef,
    required Map<String, dynamic> payload,
    String owner = 'commander',
    DateTime? at,
  }) async {
    final stored = await _read(owner);
    final privHex = stored['priv'] ?? '';
    if (privHex.isEmpty) return null;

    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final digest = digestOf(docRef: docRef, ts: ts, payload: payload);

    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(
        true,
        PrivateKeyParameter<ECPrivateKey>(
          ECPrivateKey(BigInt.parse(privHex, radix: 16), ECCurve_secp256r1()),
        ),
      );
    final sig = signer.generateSignature(Uint8List.fromList(digest)) as ECSignature;

    final raw = Uint8List.fromList([
      ..._bigIntBytes(sig.r, 32),
      ..._bigIntBytes(sig.s, 32),
    ]);
    return [
      qrPrefix,
      stored['kid'] ?? '',
      // المرجع يُرمَّز لأنه عربي: الرمز كله يبقى ASCII فلا يتوقف على تفسير
      // الماسح لترميز UTF-8 داخل QR.
      base64Url.encode(utf8.encode(docRef)),
      '$ts',
      base64Url.encode(digest),
      base64Url.encode(raw),
    ].join('|');
  }

  /// يتحقق من رمز توقيع مقروء من QR أو مكتوب يدويًا.
  ///
  /// [payload] هو محتوى المستند كما هو عند المتحقِّق: إن اختلف حرفًا واحدًا
  /// اختلفت البصمة وسقط التحقق — وهذا هو المقصود.
  Future<ESignCheck> verify(String token, {Map<String, dynamic>? payload}) async {
    final parts = token.trim().split('|');
    if (parts.length != 6 || parts.first != qrPrefix) {
      return const ESignCheck(ok: false, reason: 'رمز التوقيع غير مقروء');
    }
    final kid = parts[1];
    final docRef = refOf(token);
    final ts = int.tryParse(parts[3]);
    if (ts == null) return const ESignCheck(ok: false, reason: 'ختم زمني غير صالح');

    final Uint8List digest;
    final Uint8List raw;
    try {
      digest = base64Url.decode(parts[4]);
      raw = base64Url.decode(parts[5]);
    } catch (_) {
      return const ESignCheck(ok: false, reason: 'رمز التوقيع تالف');
    }
    if (raw.length != 64) return const ESignCheck(ok: false, reason: 'طول التوقيع غير صحيح');

    final owner = await _ownerOfKeyId(kid);
    if (owner == null) {
      return ESignCheck(ok: false, reason: 'لا يوجد مفتاح عام بالمعرّف $kid', keyId: kid);
    }
    final pubB64 = (await _read(owner))['pub'] ?? '';

    // بصمة المستند الذي بين يدي المتحقِّق يجب أن تطابق الموقَّع عليها.
    if (payload != null) {
      final expected = digestOf(docRef: docRef, ts: ts, payload: payload);
      if (!_sameBytes(expected, digest)) {
        return ESignCheck(
          ok: false,
          reason: 'المستند لا يطابق ما وُقّع عليه',
          keyId: kid,
          signer: owner,
          signedAt: DateTime.fromMillisecondsSinceEpoch(ts),
          docRef: docRef,
        );
      }
    }

    final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(false, PublicKeyParameter<ECPublicKey>(_publicKeyFrom(pubB64)));
    final ok = verifier.verifySignature(
      digest,
      ECSignature(
        _bigIntFrom(raw.sublist(0, 32)),
        _bigIntFrom(raw.sublist(32)),
      ),
    );

    return ESignCheck(
      ok: ok,
      reason: ok ? 'توقيع سليم' : 'التوقيع لا يطابق المفتاح العام',
      keyId: kid,
      signer: owner,
      signedAt: DateTime.fromMillisecondsSinceEpoch(ts),
      docRef: docRef,
      digestMatched: payload != null,
    );
  }

  /// مرجع السند المضمَّن في الرمز، أو فارغ إن كان الرمز غير صالح.
  static String refOf(String token) {
    final parts = token.trim().split('|');
    if (parts.length != 6 || parts.first != qrPrefix) return '';
    try {
      return utf8.decode(base64Url.decode(parts[2]));
    } catch (_) {
      return '';
    }
  }


  /// تحقق من توقيع **بمفتاح عام مُعطى**، بلا أي قراءة من قاعدة البيانات.
  ///
  /// يلزم حين يكون المفتاح مدفونًا في ملف التطبيق (تفعيل الأجهزة): القراءة من
  /// القاعدة تعني أن من يثبّت نسخة جديدة يضع مفتاحه ويصير هو الإدارة.
  static bool verifyRawWithKey({
    required String publicKeyB64,
    required Uint8List digest,
    required Uint8List rawSignature,
  }) {
    if (rawSignature.length != 64 || publicKeyB64.isEmpty) return false;
    try {
      final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
        ..init(false, PublicKeyParameter<ECPublicKey>(_publicKeyFrom(publicKeyB64)));
      return verifier.verifySignature(
        digest,
        ECSignature(_bigIntFrom(rawSignature.sublist(0, 32)), _bigIntFrom(rawSignature.sublist(32))),
      );
    } catch (_) {
      return false;
    }
  }

  /// توقيع خام (٦٤ بايت) بمفتاح خاص مُعطى — يستعمله مُصدِر رموز التفعيل.
  static Uint8List signRawWithKey({required String privateHex, required Uint8List digest}) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(
        true,
        PrivateKeyParameter<ECPrivateKey>(
          ECPrivateKey(BigInt.parse(privateHex, radix: 16), ECCurve_secp256r1()),
        ),
      );
    final sig = signer.generateSignature(digest) as ECSignature;
    return Uint8List.fromList([..._bigIntBytes(sig.r, 32), ..._bigIntBytes(sig.s, 32)]);
  }

  /// زوج مفاتيح جديد — يستعمله مولّد مفتاح المالك مرة واحدة.
  static ({String privateHex, String publicB64}) generateKeyPair() {
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()),
        _seededRandom(),
      ));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;
    return (
      privateHex: _hex(_bigIntBytes(priv.d!, 32)),
      publicB64: base64Encode(pub.Q!.getEncoded(true)),
    );
  }

  /// بصمة ما يُوقَّع عليه: المرجع والوقت والمحتوى مرتّبًا ترتيبًا ثابتًا.
  static Uint8List digestOf({
    required String docRef,
    required int ts,
    required Map<String, dynamic> payload,
  }) {
    final msg = jsonEncode({'ref': docRef, 'ts': ts, 'payload': _canonical(payload)});
    return Uint8List.fromList(sha256.convert(utf8.encode(msg)).bytes);
  }

  // ───────────────────────── تفاصيل التخزين والترميز

  Future<Map<String, String>> _read(String owner) async {
    final map = await SettingsRepo(db).read(_key);
    final v = map[owner];
    if (v is Map) return v.map((k, val) => MapEntry('$k', '${val ?? ''}'));
    return const {};
  }

  Future<void> _write(String owner, Map<String, String> value) async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_key);
    map[owner] = value;
    await settings.write(_key, map);
  }

  /// أي موقِّع يملك هذا المعرّف؟ (النظام يدعم أكثر من موقِّع واحد.)
  Future<String?> _ownerOfKeyId(String kid) async {
    final map = await SettingsRepo(db).read(_key);
    for (final entry in map.entries) {
      final v = entry.value;
      if (v is Map && '${v['kid'] ?? ''}' == kid) return entry.key;
    }
    return null;
  }

  static ECPublicKey _publicKeyFrom(String b64) {
    final curve = ECCurve_secp256r1();
    return ECPublicKey(curve.curve.decodePoint(base64Decode(b64)), curve);
  }

  /// ترتيب المفاتيح أبجديًا (وداخل الخرائط المتداخلة) حتى تكون البصمة ثابتة
  /// مهما اختلف ترتيب الحقول بين جهاز وآخر.
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(value[k])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static SecureRandom _seededRandom() {
    final rnd = Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    return FortunaRandom()..seed(KeyParameter(seed));
  }

  /// عدد صحيح كبير إلى بايتات بطول ثابت (بأصفار بادئة عند اللزوم).
  static Uint8List _bigIntBytes(BigInt v, int length) {
    final out = Uint8List(length);
    var x = v;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static BigInt _bigIntFrom(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// نتيجة التحقق من توقيع، بصيغة صالحة للعرض على الشاشة مباشرة.
class ESignCheck {
  const ESignCheck({
    required this.ok,
    required this.reason,
    this.keyId = '',
    this.signer = '',
    this.docRef = '',
    this.signedAt,
    this.digestMatched = false,
  });

  final bool ok;
  final String reason;
  final String keyId;
  final String signer;
  final String docRef;
  final DateTime? signedAt;

  /// هل قُورن محتوى المستند فعلًا، أم تُحقق من التوقيع وحده؟
  final bool digestMatched;
}
