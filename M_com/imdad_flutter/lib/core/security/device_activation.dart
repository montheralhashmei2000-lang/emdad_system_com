import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/sync/sync_trust.dart';
import 'esign.dart';
import 'owner_key.dart';

/// دور الجهاز الذي يمنحه رمز التفعيل.
enum DeviceRole {
  /// جهاز فرع: يستقبل الحسابات بالمزامنة ولا يُنشئ حسابًا.
  branch,

  /// جهاز الإدارة: يُنشئ حساب المدير الأول ويُصدر رموز الأجهزة الأخرى.
  master,
}

/// تفعيل الأجهزة برمز موقَّع — بلا إنترنت إطلاقًا.
///
/// **لماذا المفتاح مدفون في التطبيق:** لو قُرئ المفتاح العام من قاعدة البيانات
/// لاستطاع من يثبّت نسخة جديدة أن يولّد مفتاحه الخاص، ويضع عامَّه في قاعدته،
/// ويُصدر لنفسه رمزًا — فيصير هو الإدارة. بدفنه في ملف التطبيق ([OwnerKey])
/// لا يُقبل إلا ما وقّعه المالك بمفتاحه الخاص، وهو عنده وحده.
///
/// **ولماذا لا يُشتق معرّف الجهاز من العتاد:** البصمة العتادية تتغيّر بتحديث
/// نظام أو تبديل قرص، فيفقد الجهاز تفعيله بلا ذنب. المعرّف هنا عشوائي مخزَّن.
///
/// صيغتا الرمز (كلتاهما ASCII بالكامل فلا يتوقف على ترميز الماسح):
///
/// • **المضغوطة `IMDACT2.<Base64Url>`** — ما يُصدره النظام الآن: الحقول الموقَّعة
///   نفسها في ثنائيٍّ مضغوط (معرّف الجهاز في خمسة بايتات لا ثمانية أحرف،
///   والانتهاء في ستة لا ثلاثة عشر رقمًا) فيقصر الرمز نحو ثلث طوله، ويُرسم QR
///   أصغر يُقرأ بالكاميرا بسهولة.
/// • **القديمة `IMDACT1|معرّف المفتاح|معرّف الجهاز|الفرع(Base64)|الدور|الانتهاء|التوقيع`**
///   — تبقى مقبولةً فلا يسقط تفعيل جهازٍ صدر له رمزٌ بها.
///
/// الصيغتان توقّعان **البصمة نفسها** ([_digest])، فهما ترميزان لشيءٍ واحد.
class DeviceActivation {
  /// [ownerPublicKey] حقن للاختبارات وحدها؛ الإنتاج يستعمل المفتاح المدفون
  /// ولا يوجد أي مسار في الواجهة أو التشغيل يغيّره.
  DeviceActivation(this.db, {String? ownerPublicKey})
      : _ownerPublicKey = ownerPublicKey ?? OwnerKey.publicKey;

  final AppDatabase db;
  final String _ownerPublicKey;

  bool get _configured => _ownerPublicKey.isNotEmpty;

  static const String prefix = 'IMDACT1';
  static const String prefixV2 = 'IMDACT2';
  static const String _registryKey = 'devices';
  static const String _revocationsKey = 'revocations';
  static const String _settingsKey = 'device';

  // ───────────────────────── هوية الجهاز

  /// معرّف هذا الجهاز: ثمانية أحرف تُولَّد مرة واحدة وتبقى.
  Future<String> deviceId() async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey);
    final existing = '${map['id'] ?? ''}';
    if (existing.length == 8) return existing;

    final rnd = Random.secure();
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // بلا حروف تلتبس بالأرقام
    final id = List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    map['id'] = id;
    await settings.write(_settingsKey, map);
    return id;
  }

  /// جزء قصير يدخل في معرّفات السجلات، فيستحيل التصادم بين فرعين.
  Future<String> idSeed() async => (await deviceId()).substring(0, 4).toLowerCase();

  // ───────────────────────── حالة التفعيل

  /// التفعيل المحفوظ، أو `null` إن لم يُفعَّل.
  Future<ActivationState?> current() async {
    final map = await SettingsRepo(db).read(_settingsKey);
    final token = '${map['token'] ?? ''}';
    if (token.isEmpty) return null;
    final id = await deviceId();
    final state = await verify(token, expectDeviceId: id);
    if (state.ok && await isRevoked(id)) {
      return ActivationState(
        ok: false,
        reason: 'أُلغي تفعيل هذا الجهاز من الإدارة — تواصل معها',
        deviceId: state.deviceId,
        branch: state.branch,
        role: state.role,
        expiresAt: state.expiresAt,
      );
    }
    return state;
  }

  /// هل يُسمح لهذا الجهاز بالعمل؟
  ///
  /// في وضع التطوير (لا مفتاح مالك مضبوط) يعمل بلا قيد، وإلا فلا بدّ من رمز.
  Future<bool> isActivated() async {
    if (!_configured) return true;
    return (await current())?.ok ?? false;
  }

  /// هل هذا جهاز الإدارة؟ عليه وحده يُنشأ حساب المدير الأول.
  Future<bool> isMaster() async {
    if (!_configured) return true;
    final state = await current();
    return state != null && state.ok && state.role == DeviceRole.master;
  }

  /// هل هذا جهاز فرع مفعَّل؟ (يستقبل حساباته ومالكه بالمزامنة.)
  Future<bool> isBranch() async {
    if (!_configured) return false;
    final state = await current();
    return state != null && state.ok && state.role == DeviceRole.branch;
  }

  Future<ActivationState> activate(String token) async {
    final state = await verify(token, expectDeviceId: await deviceId());
    if (!state.ok) return state;
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey)..['token'] = token.trim();
    await settings.write(_settingsKey, map);
    return state;
  }

  Future<void> deactivate() async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey)..remove('token');
    await settings.write(_settingsKey, map);
  }

  // ───────────────────────── مفتاح المالك على جهاز الإدارة

  /// هل يحمل هذا الجهاز المفتاح الخاص (فيستطيع إصدار الرموز)؟
  Future<bool> canIssue() async => (await _privateKey()).isNotEmpty;

  /// يستورد المفتاح الخاص إلى جهاز الإدارة. يُرفض إن لم يطابق المفتاح المدفون.
  Future<bool> importPrivateKey(String privateHex) async {
    final hex = privateHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return false;
    // التحقق العملي: نوقّع ببصمة تجريبية ونتحقق بالمفتاح المدفون.
    if (_configured) {
      final probe = Uint8List.fromList(sha256.convert(utf8.encode('probe')).bytes);
      final sig = ESign.signRawWithKey(privateHex: hex, digest: probe);
      final ok = ESign.verifyRawWithKey(
        publicKeyB64: _ownerPublicKey,
        digest: probe,
        rawSignature: sig,
      );
      if (!ok) return false;
    }
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey)..['owner'] = hex;
    await settings.write(_settingsKey, map);
    return true;
  }

  /// يوقّع [digest] بمفتاح المالك الخاص المستورد على هذا الجهاز (٦٤ بايت خام)،
  /// أو `null` إن لم يكن المفتاح هنا. مستعملٌ في توقيع قرارات المالك (فكّ الحجب،
  /// منح الأدوار) — التحقق بالمفتاح العام المدفون ([OwnerKey]) على أي جهاز.
  Future<Uint8List?> signDigest(Uint8List digest) async {
    final priv = await _privateKey();
    if (priv.isEmpty) return null;
    return ESign.signRawWithKey(privateHex: priv, digest: digest);
  }

  Future<void> forgetPrivateKey() async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey)..remove('owner');
    await settings.write(_settingsKey, map);
  }

  Future<String> _privateKey() async =>
      '${(await SettingsRepo(db).read(_settingsKey))['owner'] ?? ''}';

  // ───────────────────────── الإصدار والتحقق

  /// يُصدر رمز تفعيل موقَّعًا بمفتاح المالك. `null` إن لم يكن المفتاح هنا.
  Future<String?> issue({
    required String deviceId,
    required String branch,
    required DateTime expiresAt,
    DeviceRole role = DeviceRole.branch,
    String name = '',
    bool compact = true,
  }) async {
    final priv = await _privateKey();
    if (priv.isEmpty) return null;

    final expiry = expiresAt.millisecondsSinceEpoch;
    final branchB64 = base64Url.encode(utf8.encode(branch));
    final roleName = role.name;
    final signature = ESign.signRawWithKey(
      privateHex: priv,
      digest: _digest(deviceId, branchB64, roleName, expiry),
    );
    // المضغوطة أولًا؛ وما لا يتّسع لها (معرّف بحروف خارج الأبجدية أو فرعٌ أطول
    // من 255 بايتًا) يُصدَر بالقديمة فلا يفشل الإصدار.
    final short = compact ? _encodeV2(deviceId, branch, role, expiry, signature) : null;
    final token = short ??
        [
          prefix,
          _configured ? ESign.keyIdOf(_ownerPublicKey) : 'DEVMODE0',
          deviceId,
          branchB64,
          roleName,
          '$expiry',
          base64Url.encode(signature),
        ].join('|');

    await _record(IssuedDevice(
      deviceId: deviceId,
      name: name.trim(),
      branch: branch,
      role: role,
      issuedAt: DateTime.now(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry),
    ));
    return token;
  }

  /// يتحقق من رمز: التوقيع بالمفتاح **المدفون**، ومطابقة الجهاز، والانتهاء.
  Future<ActivationState> verify(String token, {required String expectDeviceId}) async {
    final _Parsed? parsed = _parse(token.trim());
    if (parsed == null) {
      return const ActivationState(ok: false, reason: 'رمز التفعيل غير مقروء');
    }
    final device = parsed.deviceId;
    final roleName = parsed.roleName;
    final expiry = parsed.expiry;
    if (device != expectDeviceId) {
      return ActivationState(
        ok: false,
        reason: 'هذا الرمز صادر لجهاز آخر ($device)',
        deviceId: device,
      );
    }

    final String branch;
    final Uint8List signature = parsed.signature;
    try {
      branch = utf8.decode(base64Url.decode(parsed.branchB64));
    } catch (_) {
      return const ActivationState(ok: false, reason: 'رمز التفعيل تالف');
    }

    final role = roleName == DeviceRole.master.name ? DeviceRole.master : DeviceRole.branch;
    final expires = DateTime.fromMillisecondsSinceEpoch(expiry);

    if (_configured) {
      final ok = ESign.verifyRawWithKey(
        publicKeyB64: _ownerPublicKey,
        digest: _digest(device, parsed.branchB64, roleName, expiry),
        rawSignature: signature,
      );
      if (!ok) {
        return ActivationState(
          ok: false,
          reason: 'التوقيع غير صادر عن إدارة النظام',
          deviceId: device,
          branch: branch,
          role: role,
        );
      }
    }

    if (DateTime.now().isAfter(expires)) {
      return ActivationState(
        ok: false,
        reason: 'انتهت صلاحية التفعيل في ${_day(expires)} — اطلب رمزًا جديدًا',
        deviceId: device,
        branch: branch,
        role: role,
        expiresAt: expires,
      );
    }

    return ActivationState(
      ok: true,
      reason: role == DeviceRole.master ? 'جهاز الإدارة — مفعَّل' : 'الجهاز مفعَّل',
      deviceId: device,
      branch: branch,
      role: role,
      expiresAt: expires,
    );
  }

  // ───────────────────────── الترميز

  /// أبجدية معرّف الجهاز — اثنان وثلاثون رمزًا بالضبط، فيُحمَل كل رمزٍ في خمس بتّات.
  static const String _idAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  static Uint8List? _idToBytes(String id) {
    if (id.length != 8) return null;
    var acc = 0;
    for (final ch in id.split('')) {
      final v = _idAlphabet.indexOf(ch);
      if (v < 0) return null;
      acc = (acc << 5) | v;
    }
    return Uint8List.fromList([for (var i = 4; i >= 0; i--) (acc >> (8 * i)) & 0xFF]);
  }

  static String _idFromBytes(List<int> b) {
    var acc = 0;
    for (final x in b) {
      acc = (acc << 8) | x;
    }
    return [for (var i = 7; i >= 0; i--) _idAlphabet[(acc >> (5 * i)) & 31]].join();
  }

  /// `IMDACT2.<Base64Url بلا حشو>` — أو `null` إن تعذّر الضغط فيُستعمل القديم.
  ///
  /// التخطيط: معرّف الجهاز (5) · الدور (1) · الانتهاء بالمللي ثانية (6) ·
  /// طول الفرع (1) · الفرع UTF-8 · التوقيع (64).
  static String? _encodeV2(
      String deviceId, String branch, DeviceRole role, int expiry, Uint8List signature) {
    final id = _idToBytes(deviceId);
    final b = utf8.encode(branch);
    if (id == null || b.length > 255 || signature.length != 64 || expiry < 0) return null;
    final out = BytesBuilder()
      ..add(id)
      ..addByte(role == DeviceRole.master ? 1 : 0)
      ..add([for (var i = 5; i >= 0; i--) (expiry >> (8 * i)) & 0xFF])
      ..addByte(b.length)
      ..add(b)
      ..add(signature);
    return '$prefixV2.${base64Url.encode(out.toBytes()).replaceAll('=', '')}';
  }

  /// يفكّ الصيغتين إلى الحقول الموقَّعة نفسها، أو `null` إن لم يُقرأ الرمز.
  static _Parsed? _parse(String token) {
    try {
      if (token.startsWith('$prefixV2.')) {
        final raw = base64Url.decode(base64Url.normalize(token.substring(prefixV2.length + 1)));
        if (raw.length < 5 + 1 + 6 + 1 + 64) return null;
        final len = raw[12];
        if (raw.length != 13 + len + 64) return null;
        var expiry = 0;
        for (var i = 6; i < 12; i++) {
          expiry = (expiry << 8) | raw[i];
        }
        return _Parsed(
          deviceId: _idFromBytes(raw.sublist(0, 5)),
          branchB64: base64Url.encode(raw.sublist(13, 13 + len)),
          roleName: raw[5] == 1 ? DeviceRole.master.name : DeviceRole.branch.name,
          expiry: expiry,
          signature: Uint8List.fromList(raw.sublist(13 + len)),
        );
      }
      final parts = token.split('|');
      if (parts.length != 7 || parts.first != prefix) return null;
      final expiry = int.tryParse(parts[5]);
      if (expiry == null) return null;
      return _Parsed(
        deviceId: parts[2],
        branchB64: parts[3],
        roleName: parts[4],
        expiry: expiry,
        signature: base64Url.decode(parts[6]),
      );
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── سجلّ الأجهزة المُصدَر لها (على جهاز الإدارة)

  /// الأجهزة التي أُصدر لها رمزٌ من هذا الجهاز، الأحدث أولًا، بحالتها الحالية.
  Future<List<IssuedDevice>> registry() async {
    final map = await SettingsRepo(db).read(_registryKey);
    final revoked = await _revocations();
    final list = <IssuedDevice>[
      for (final e in (map['list'] as List? ?? const []))
        if (e is Map) IssuedDevice.fromMap(e.cast<String, dynamic>()),
    ];
    return [
      for (final d in list)
        d.copyWith(revoked: (revoked[d.deviceId]?['revoked'] ?? false) == true),
    ]..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
  }

  Future<void> _saveRegistry(List<IssuedDevice> list) =>
      SettingsRepo(db).write(_registryKey, {'list': [for (final d in list) d.toMap()]});

  /// يسجّل الإصدار: إعادة الإصدار لجهازٍ مسجَّل تحدّث سجلّه ولا تكرّره، وتحفظ
  /// اسمه السابق إن لم يُعطَ اسمٌ جديد.
  Future<void> _record(IssuedDevice d) async {
    final all = await registry();
    final i = all.indexWhere((x) => x.deviceId == d.deviceId);
    final next = [...all];
    if (i >= 0) {
      next[i] = d.copyWith(name: d.name.isEmpty ? all[i].name : d.name);
    } else {
      next.add(d);
    }
    await _saveRegistry(next);
  }

  Future<void> renameIssued(String deviceId, String name) async {
    final all = await registry();
    await _saveRegistry([
      for (final d in all) d.deviceId == deviceId ? d.copyWith(name: name.trim()) : d,
    ]);
  }

  /// يحذف الجهاز من السجلّ فقط. **لا يلغي تفعيله**: من أراد إيقافه فليُلغِه أولًا؛
  /// وإلغاءٌ سابق يبقى سارياً بعد الحذف حتى لا يعود الجهاز بحذف سطره.
  Future<void> removeIssued(String deviceId) async {
    final all = await registry();
    await _saveRegistry([for (final d in all) if (d.deviceId != deviceId) d]);
  }

  // ───────────────────────── الإلغاء

  /// إلغاء تفعيل جهاز (أو إعادته). الإلغاء يُسجَّل بختم وقته، ويسافر مع المزامنة
  /// إلى الأجهزة الأخرى (آخر ختمٍ يفوز) فيتوقف الجهاز الملغى عند أول مزامنة له
  /// مع أي جهازٍ حمل الإلغاء. الرمز نفسه لا يمكن سحبه لأنه يُتحقَّق منه محليًا
  /// بلا إنترنت — فالمزامنة هي القناة الوحيدة.
  /// يعيد `true` إن وُقِّع القرار فينتشر بالمزامنة، و`false` إن بقي محليًّا (لا
  /// مفتاح مالكٍ على هذا الجهاز) — تقول الواجهة ذلك للمشغّل.
  ///
  /// والإلغاء يقطع الثقة كذلك: جهازٌ أُلغي تفعيله كان يبقى قرينًا موثوقًا،
  /// فيُفتح له المنفذ ويُقبل منه السحب والدفع. توقّفُه عند بوابة التفعيل حمايةٌ
  /// في واجهته لا في بابنا — ومن سُرق جهازه لا يملك واجهته.
  Future<bool> setRevoked(String deviceId, bool revoked) async {
    final at = DateTime.now().millisecondsSinceEpoch;
    final raw = await signDigest(revocationDigest(deviceId: deviceId, revoked: revoked, atMs: at));
    final sig = raw == null ? null : base64Url.encode(raw);
    final map = await _revocations();
    map[deviceId] = {
      'revoked': revoked,
      'at': at,
      if (sig != null) 'sig': sig,
    };
    await SettingsRepo(db).write(_revocationsKey, {'map': map});
    if (revoked) await SyncTrust(db).forget(deviceId);
    return sig != null;
  }

  /// بصمة قرار إلغاء تفعيل جهاز (أو إعادته).
  ///
  /// القرار والختم داخلان في البصمة، فلا يُنقل توقيعٌ من قرارٍ إلى نقيضه:
  /// توقيعُ «أُلغي في ت١» لا يصلح لـ«أُعيد في ت٢».
  ///
  /// وهو هنا لا في [OwnerSignature] لأن ذاك يستورد هذا الملف (توقيعُه يحتاج
  /// [signDigest])، فوضعُه هناك يُحدث حلقة استيراد. وبيانات الإلغاء كلها في هذا
  /// الملف أصلًا، فاجتماعُها في موضعٍ واحد أسهلُ في التدقيق.
  static Uint8List revocationDigest({
    required String deviceId,
    required bool revoked,
    required int atMs,
  }) =>
      Uint8List.fromList(
          sha256.convert(utf8.encode('imdad.revoke.v1|$deviceId|${revoked ? 1 : 0}|$atMs')).bytes);

  /// هل [sigB64] توقيعٌ صحيح من المالك على هذا القرار بعينه؟
  bool verifyRevocation({
    required String sigB64,
    required String deviceId,
    required bool revoked,
    required int atMs,
  }) {
    if (!_configured || sigB64.isEmpty) return false;
    try {
      return ESign.verifyRawWithKey(
        publicKeyB64: _ownerPublicKey,
        digest: revocationDigest(deviceId: deviceId, revoked: revoked, atMs: atMs),
        rawSignature: Uint8List.fromList(base64Url.decode(sigB64)),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> isRevoked(String deviceId) async =>
      ((await _revocations())[deviceId]?['revoked'] ?? false) == true;

  Future<Map<String, Map<String, dynamic>>> _revocations() async {
    final raw = (await SettingsRepo(db).read(_revocationsKey))['map'];
    return {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map),
    };
  }

  /// ما يُرسَل إلى الأجهزة الأخرى مع المزامنة.
  Future<Map<String, Map<String, dynamic>>> revocationsForSync() => _revocations();

  /// يدمج إلغاءاتٍ واردة: لكل جهازٍ آخر ختمٍ يفوز، **بتوقيع المالك وحده**.
  ///
  /// كان القرار يُقبل بلا توقيع والختم بيد المرسِل، فأي قرينٍ مقترن يستطيع
  /// شقّين: أن **يُلغي تفعيل أي جهاز** ومنه جهاز الإدارة بختمٍ من المستقبل فلا
  /// يُنقَض أبدًا، وأن **يُحيي جهازًا مسروقًا** أُلغي تفعيله بالطريقة نفسها.
  /// الآن يُشترط توقيعٌ على (الجهاز + القرار + الختم) معًا، فلا يُنقل توقيعٌ من
  /// قرارٍ إلى آخر. والقرار الموقَّع يقطع الثقة هنا أيضًا كما تقطعها [setRevoked].
  ///
  /// وبلا مفتاح مالكٍ مضبوط (وضع التطوير) لا يُفرض التوقيع — كحال بقية الحُرّاس.
  /// ويُرجع عدد ما تغيّر.
  Future<int> mergeRevocations(Object? incoming) async {
    if (incoming is! Map) return 0;
    final local = await _revocations();
    var changed = 0;
    var rejected = 0;
    for (final e in incoming.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final at = int.tryParse('${v['at']}') ?? 0;
      final mine = int.tryParse('${local['${e.key}']?['at']}') ?? -1;
      if (at <= mine) continue;
      final revoked = v['revoked'] == true;
      final sig = '${v['sig'] ?? ''}';
      if (_configured && !verifyRevocation(sigB64: sig, deviceId: '${e.key}', revoked: revoked, atMs: at)) {
        rejected++;
        continue;
      }
      local['${e.key}'] = {'revoked': revoked, 'at': at, if (sig.isNotEmpty) 'sig': sig};
      if (revoked) await SyncTrust(db).forget('${e.key}');
      changed++;
    }
    if (changed > 0) {
      await SettingsRepo(db).write(_revocationsKey, {'map': local});
    }
    if (rejected > 0) {
      await AuditRepo(db).log(
        action: 'sync.revocation_rejected',
        entityType: 'جهاز',
        summary: 'رُفض $rejected قرار تفعيل/إلغاء وارد بلا توقيع مالكٍ صحيح',
        details: {'count': rejected},
        risk: AuditRepo.riskHigh,
        actorEmail: 'sync',
      );
    }
    return changed;
  }

  /// ما يُوقَّع عليه: يربط الرمز بالجهاز والفرع والدور والانتهاء معًا، فلا
  /// يُنقل بين الأجهزة ولا تُرفع صلاحيته ولا يُمدَّد تاريخه.
  static Uint8List _digest(String deviceId, String branchB64, String role, int expiry) =>
      Uint8List.fromList(
        sha256.convert(utf8.encode('ACT1:$deviceId:$branchB64:$role:$expiry')).bytes,
      );

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// بصمة قصيرة تُعرض بجوار المعرّف لتأكيد التلاوة الهاتفية.
  static String checksum(String deviceId) {
    final d = sha256.convert(utf8.encode(deviceId)).bytes;
    return ((d[0] << 8 | d[1]) % 1000).toString().padLeft(3, '0');
  }
}

/// حالة تفعيل جاهزة للعرض.
class ActivationState {
  const ActivationState({
    required this.ok,
    required this.reason,
    this.deviceId = '',
    this.branch = '',
    this.role = DeviceRole.branch,
    this.expiresAt,
  });

  final bool ok;
  final String reason;
  final String deviceId;
  final String branch;
  final DeviceRole role;
  final DateTime? expiresAt;
}

/// الحقول الموقَّعة بعد فكّ أيٍّ من صيغتَي الرمز.
class _Parsed {
  const _Parsed({
    required this.deviceId,
    required this.branchB64,
    required this.roleName,
    required this.expiry,
    required this.signature,
  });

  final String deviceId;
  final String branchB64;
  final String roleName;
  final int expiry;
  final Uint8List signature;
}

enum IssuedStatus { active, expired, revoked }

/// جهازٌ أُصدر له رمز تفعيل — سطر سجلّ الأجهزة على جهاز الإدارة.
class IssuedDevice {
  const IssuedDevice({
    required this.deviceId,
    required this.name,
    required this.branch,
    required this.role,
    required this.issuedAt,
    required this.expiresAt,
    this.revoked = false,
  });

  final String deviceId;

  /// اسمٌ يضعه المشرف ليتعرّف على الجهاز («حاسوب المخزن»…) — اختياري.
  final String name;
  final String branch;
  final DeviceRole role;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool revoked;

  IssuedStatus get status => revoked
      ? IssuedStatus.revoked
      : (DateTime.now().isAfter(expiresAt) ? IssuedStatus.expired : IssuedStatus.active);

  IssuedDevice copyWith({String? name, bool? revoked}) => IssuedDevice(
        deviceId: deviceId,
        name: name ?? this.name,
        branch: branch,
        role: role,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        revoked: revoked ?? this.revoked,
      );

  Map<String, dynamic> toMap() => {
        'id': deviceId,
        'name': name,
        'branch': branch,
        'role': role.name,
        'issuedAt': issuedAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  factory IssuedDevice.fromMap(Map<String, dynamic> m) => IssuedDevice(
        deviceId: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        branch: '${m['branch'] ?? ''}',
        role: m['role'] == DeviceRole.master.name ? DeviceRole.master : DeviceRole.branch,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse('${m['issuedAt']}') ?? 0),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse('${m['expiresAt']}') ?? 0),
      );
}
