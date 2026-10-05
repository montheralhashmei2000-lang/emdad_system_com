import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'device_activation.dart';
import 'esign.dart';
import 'owner_key.dart';

/// توقيع المالك على قرارات تمسّ الحسابات — ECDSA P-256 بمفتاح المالك الخاص،
/// ويُتحقَّق منه بالمفتاح العام المدفون في التطبيق ([OwnerKey]).
///
/// **عمود `users.owner_sig`** نصٌّ فارغ (لا توقيع) أو JSON بتواقيع مسمّاة:
/// `{"s": "<توقيع الأقسام>", "r": "<توقيع الدور>"}`. أكثر من توقيعٍ على الحساب
/// الواحد (دورٌ مرفوع وحجبٌ مفكوك) لا يتزاحمان في عمودٍ واحد.
///
/// **ما يغطّيه كل توقيع** (يمنع نسخه إلى حسابٍ آخر أو قيمةٍ أخرى أو وقتٍ آخر):
///  • `s` — الأقسام: `userId | section_blocked | updatedAt` (ثوانٍ).
///  • `r` — الدور: `userId | role | updatedAt` (ثوانٍ).
class OwnerSignature {
  const OwnerSignature._();

  static const String sectionsKey = 's';
  static const String roleKey = 'r';

  /// رتبة الدور: رفعُها هو ما يستلزم توقيع المالك عند الاستقبال.
  static int rank(String? role) => switch (role) {
        'owner' => 2,
        'admin' => 1,
        _ => 0,
      };

  /// يقرأ محتوى `owner_sig`. التالف أو الفارغ ⇒ خريطة فارغة (لا توقيع).
  static Map<String, String> parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return {};
    try {
      final v = jsonDecode(text);
      if (v is! Map) return {};
      return {for (final e in v.entries) if (e.value is String && '${e.value}'.isNotEmpty) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  /// يرمّز التواقيع. فارغ ⇒ `''` (العمود يعود إلى «لا توقيع»).
  static String encode(Map<String, String> sigs) {
    final clean = {for (final e in sigs.entries) if (e.value.isNotEmpty) e.key: e.value};
    if (clean.isEmpty) return '';
    final keys = clean.keys.toList()..sort();
    return jsonEncode({for (final k in keys) k: clean[k]});
  }

  /// ثواني Unix للحظة — الدقة التي تُخزَّن بها `updatedAt` في القاعدة، فتتطابق
  /// بصمة الموقِّع والمتحقِّق مهما مرّ الصف بتصدير واستيراد.
  static int seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  /// بصمة منح الدور.
  static Uint8List roleDigest({
    required String userId,
    required String role,
    required int updatedAtSec,
  }) =>
      Uint8List.fromList(sha256.convert(utf8.encode('imdad.role.v1|$userId|$role|$updatedAtSec')).bytes);

  /// يوقّع منح دورٍ بمفتاح المالك الخاص على هذا الجهاز؛ `null` إن لم يوجد.
  static Future<String?> signRole(
    DeviceActivation activation, {
    required String userId,
    required String role,
    required int updatedAtSec,
  }) async {
    final raw = await activation.signDigest(roleDigest(userId: userId, role: role, updatedAtSec: updatedAtSec));
    return raw == null ? null : base64Url.encode(raw);
  }

  /// هل [sigB64] توقيعٌ صحيح من المالك على منح [role] لـ[userId] في هذه اللحظة؟
  static bool verifyRole({
    required String sigB64,
    required String userId,
    required String role,
    required int updatedAtSec,
    String? publicKey,
  }) {
    final key = publicKey ?? OwnerKey.publicKey;
    if (key.isEmpty || sigB64.isEmpty) return false;
    try {
      return ESign.verifyRawWithKey(
        publicKeyB64: key,
        digest: roleDigest(userId: userId, role: role, updatedAtSec: updatedAtSec),
        rawSignature: Uint8List.fromList(base64Url.decode(sigB64)),
      );
    } catch (_) {
      return false;
    }
  }

  /// بصمة قرار الأقسام.
  static Uint8List sectionsDigest({
    required String userId,
    required String blockedJson,
    required int updatedAtSec,
  }) =>
      Uint8List.fromList(sha256.convert(utf8.encode('imdad.sections.v1|$userId|$blockedJson|$updatedAtSec')).bytes);

  /// يوقّع قرار الأقسام بمفتاح المالك الخاص على هذا الجهاز؛ `null` إن لم يوجد.
  static Future<String?> signSections(
    DeviceActivation activation, {
    required String userId,
    required String blockedJson,
    required int updatedAtSec,
  }) async {
    final raw = await activation.signDigest(
      sectionsDigest(userId: userId, blockedJson: blockedJson, updatedAtSec: updatedAtSec),
    );
    return raw == null ? null : base64Url.encode(raw);
  }

  /// هل [sigB64] توقيعٌ صحيح من المالك على هذا القرار؟
  ///
  /// [publicKey] حقنٌ للاختبارات؛ الإنتاج يستعمل المفتاح المدفون.
  static bool verifySections({
    required String sigB64,
    required String userId,
    required String blockedJson,
    required int updatedAtSec,
    String? publicKey,
  }) {
    final key = publicKey ?? OwnerKey.publicKey;
    if (key.isEmpty || sigB64.isEmpty) return false;
    try {
      return ESign.verifyRawWithKey(
        publicKeyB64: key,
        digest: sectionsDigest(userId: userId, blockedJson: blockedJson, updatedAtSec: updatedAtSec),
        rawSignature: Uint8List.fromList(base64Url.decode(sigB64)),
      );
    } catch (_) {
      return false;
    }
  }
}
