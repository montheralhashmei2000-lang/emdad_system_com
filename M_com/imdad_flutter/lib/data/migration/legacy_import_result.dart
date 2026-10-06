
/// ترحيل بيانات النظام السابق إلى قاعدة Drift.
/// المصدر: ملف JSON مُصدَّر منه بالشكل:
/// { "items": [...], "warehouses": [...], "receipts": [...], ... }
/// كل مجموعة مصفوفة من الوثائق بأسماء حقولها الأصلية.
/// حسابٌ رُفض استقباله لأنه يرفع دورًا أو يفكّ حجبًا بلا توقيع مالكٍ صحيح.
class RejectedUser {
  const RejectedUser({required this.id, required this.username, required this.kind, required this.reason});

  final String id;
  final String username;

  /// `role` (رفع دور) أو `unblock` (فكّ حجب).
  final String kind;
  final String reason;
}


class LegacyImportResult {
  LegacyImportResult();

  final Map<String, int> inserted = {};
  final List<String> warnings = [];

  /// حسابات رُفضت لغياب توقيع المالك (لا تُكتب، ويبقى المحلي كما هو).
  final List<RejectedUser> rejectedUsers = [];

  /// حسابات تجاوزها الدمج لأن المحلي أحدث (ليست رفضًا أمنيًّا).
  int usersSkipped = 0;

  int get total => inserted.values.fold(0, (a, b) => a + b);

  @override
  String toString() =>
      'استُورد $total سجلًا: ${inserted.entries.map((e) => '${e.key}=${e.value}').join('، ')}';
}
