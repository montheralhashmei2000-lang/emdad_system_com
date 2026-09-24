/// قواعد طلبيات الإعاشة — دورة الحالة والتحقق.
///
/// دورة الطلبية: مسودة ← مرسلة ← معتمدة ← مستلمة. والرفض يقطعها عند الإرسال
/// أو الاعتماد. كل انتقال له شرطه، ومنعُ الانتقال الخاطئ هنا أرخص من تصحيح
/// رصيد مخزن بعد استلام طلبية مرفوضة.
library;

class RationStatus {
  static const String draft = 'DRAFT';
  static const String pending = 'PENDING';
  static const String approved = 'APPROVED';
  static const String received = 'RECEIVED';
  static const String rejected = 'REJECTED';

  static const List<String> all = [draft, pending, approved, received, rejected];

  static const Map<String, String> labels = {
    draft: 'مسودة',
    pending: 'مرسلة',
    approved: 'معتمدة',
    received: 'مستلمة',
    rejected: 'مرفوضة',
  };

  static String label(String v) => labels[v] ?? v;

  /// الحالات التي ما زالت تنتظر إجراءً — تُعدّ في لوحة «إجراءات تحتاج تدخل».
  static const List<String> open = [draft, pending, approved];
}

class RationPriority {
  static const String normal = 'NORMAL';
  static const String urgent = 'URGENT';

  static const List<String> all = [normal, urgent];

  static const Map<String, String> labels = {normal: 'عادي', urgent: 'عاجل'};

  static String label(String v) => labels[v] ?? v;
}

/// سطر طلبية كما تراه القواعد — بلا ارتباط بجدول، فيُختبر وحده.
class RationLineDraft {
  const RationLineDraft({
    required this.itemId,
    required this.requestedQty,
    this.approvedQty = 0,
  });

  final String itemId;
  final double requestedQty;
  final double approvedQty;
}

class RationRules {
  const RationRules._();

  // ───────────────────────── انتقالات الحالة

  static bool canEdit(String status) => status == RationStatus.draft;

  static bool canSubmit(String status) => status == RationStatus.draft;

  static bool canApprove(String status) => status == RationStatus.pending;

  /// الاستلام لا يقع إلا على طلبية **معتمدة**: الاستلام يزيد الرصيد، وزيادته
  /// من طلبية لم يعتمدها أحد تفتح باب إدخال كميات بلا رقيب.
  static bool canReceive(String status) => status == RationStatus.approved;

  static bool canReject(String status) =>
      status == RationStatus.pending || status == RationStatus.approved;

  static bool canDelete(String status) =>
      status == RationStatus.draft || status == RationStatus.rejected;

  /// الحالة التالية لإجراءٍ ما، أو `null` إن كان الإجراء غير مسموح الآن.
  static String? next(String status, String action) => switch (action) {
        'submit' => canSubmit(status) ? RationStatus.pending : null,
        'approve' => canApprove(status) ? RationStatus.approved : null,
        'receive' => canReceive(status) ? RationStatus.received : null,
        'reject' => canReject(status) ? RationStatus.rejected : null,
        _ => null,
      };

  // ───────────────────────── التحقق

  static String? validateWarehouses({
    required String requesting,
    required String supplying,
  }) {
    if (requesting.trim().isEmpty) return 'المستودع الطالب مطلوب';
    if (supplying.trim().isEmpty) return 'المستودع المورِّد مطلوب';
    if (requesting.trim() == supplying.trim()) {
      return 'المستودع الطالب هو نفسه المورِّد — اختر مستودعًا آخر';
    }
    return null;
  }

  /// [date] و[requiredDate] بصيغة yyyy-MM-dd. تاريخ الاحتياج الفارغ مقبول.
  static String? validateRequiredDate(String date, String requiredDate) {
    final need = requiredDate.trim();
    if (need.isEmpty) return null;
    final order = DateTime.tryParse(date.trim());
    final want = DateTime.tryParse(need);
    if (want == null) return 'تاريخ الاحتياج غير صالح';
    if (order != null && want.isBefore(order)) {
      return 'تاريخ الاحتياج قبل تاريخ الطلبية';
    }
    return null;
  }

  static String? validateLines(List<RationLineDraft> lines) {
    if (lines.isEmpty) return 'أضف صنفًا واحدًا على الأقل';
    for (final l in lines) {
      if (l.itemId.trim().isEmpty) return 'كل سطر يحتاج صنفًا';
      if (l.requestedQty <= 0) return 'الكمية المطلوبة أكبر من صفر في كل سطر';
    }
    final ids = lines.map((l) => l.itemId).toSet();
    if (ids.length != lines.length) {
      return 'صنف مكرر في الطلبية — ادمج سطريه في سطر واحد';
    }
    return null;
  }

  static String? validateQty(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'الكمية مطلوبة';
    final d = double.tryParse(v);
    if (d == null) return 'الكمية يجب أن تكون رقمًا';
    if (d <= 0) return 'الكمية أكبر من صفر';
    return null;
  }

  /// الكمية المعتمدة لا تتجاوز المطلوبة: الاعتماد تقليصٌ أو إقرار، لا زيادة
  /// من طرف واحد على ما طلبه الفرع.
  static String? validateApproved(List<RationLineDraft> lines) {
    for (final l in lines) {
      if (l.approvedQty < 0) return 'الكمية المعتمدة لا تكون سالبة';
      if (l.approvedQty > l.requestedQty) {
        return 'الكمية المعتمدة تتجاوز المطلوبة — راجع السطور';
      }
    }
    return null;
  }

  static String? validateRejectReason(String? reason) {
    if ((reason ?? '').trim().isEmpty) return 'اذكر سبب الرفض';
    return null;
  }
}
