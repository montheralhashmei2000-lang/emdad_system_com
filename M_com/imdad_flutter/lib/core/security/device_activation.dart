import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
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
/// صيغة الرمز (ASCII بالكامل فلا يتوقف على ترميز الماسح):
/// `IMDACT1|معرّف المفتاح|معرّف الجهاز|الفرع(Base64)|الدور|الانتهاء|التوقيع`
class DeviceActivation {
  /// [ownerPublicKey] حقن للاختبارات وحدها؛ الإنتاج يستعمل المفتاح المدفون
  /// ولا يوجد أي مسار في الواجهة أو التشغيل يغيّره.
  DeviceActivation(this.db, {String? ownerPublicKey})
      : _ownerPublicKey = ownerPublicKey ?? OwnerKey.publicKey;

  final AppDatabase db;
  final String _ownerPublicKey;

  bool get _configured => _ownerPublicKey.isNotEmpty;

  static const String prefix = 'IMDACT1';
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
    return verify(token, expectDeviceId: await deviceId());
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
    final kid = _configured ? ESign.keyIdOf(_ownerPublicKey) : 'DEVMODE0';
    return [prefix, kid, deviceId, branchB64, roleName, '$expiry', base64Url.encode(signature)]
        .join('|');
  }

  /// يتحقق من رمز: التوقيع بالمفتاح **المدفون**، ومطابقة الجهاز، والانتهاء.
  Future<ActivationState> verify(String token, {required String expectDeviceId}) async {
    final parts = token.trim().split('|');
    if (parts.length != 7 || parts.first != prefix) {
      return const ActivationState(ok: false, reason: 'رمز التفعيل غير مقروء');
    }
    final device = parts[2];
    final roleName = parts[4];
    final expiry = int.tryParse(parts[5]);
    if (expiry == null) {
      return const ActivationState(ok: false, reason: 'تاريخ انتهاء غير صالح');
    }
    if (device != expectDeviceId) {
      return ActivationState(
        ok: false,
        reason: 'هذا الرمز صادر لجهاز آخر ($device)',
        deviceId: device,
      );
    }

    final String branch;
    final Uint8List signature;
    try {
      branch = utf8.decode(base64Url.decode(parts[3]));
      signature = base64Url.decode(parts[6]);
    } catch (_) {
      return const ActivationState(ok: false, reason: 'رمز التفعيل تالف');
    }

    final role = roleName == DeviceRole.master.name ? DeviceRole.master : DeviceRole.branch;
    final expires = DateTime.fromMillisecondsSinceEpoch(expiry);

    if (_configured) {
      final ok = ESign.verifyRawWithKey(
        publicKeyB64: _ownerPublicKey,
        digest: _digest(device, parts[3], roleName, expiry),
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
