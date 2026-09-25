/// قواعد طلبيات الإعاشة — دورة الحالة والتحقق.
///
/// دورة الطلبية: مسودة ← مرسلة ← معتمدة ← منفَّذة. والرفض يقطعها عند الإرسال
/// أو الاعتماد. كل انتقال له شرطه، ومنعُ الانتقال الخاطئ هنا أرخص من تصحيحه
/// بعد وقوعه.
///
/// **والطلبية طلبٌ لا حركة: لا تمسّ المخزون أبدًا.** ما يحرّك الرصيد مستندٌ
/// مستقل — سندُ تحويل للمخزن الفرعي، وسندُ توريد للمخزن الرئيسي — والطلبية
/// تُربط به بعد إنشائه فيُعرف ما وصل مما طُلب. ولو حرّكت الطلبيةُ الرصيدَ
/// بنفسها لصار لكل صنفٍ أثران: أثرُ الطلب وأثرُ السند، فيتضاعف المخزون ورقيًّا
/// وهو لم يزد حبّةً واحدة.
library;

/// نوع الطلبية — ومن يُطلب منه يختلف باختلافه.
class RationKind {
  /// المخزن الرئيسي يطلب من **جهة** في تسلسل الفرقة، لا من مستودع.
  ///
  /// واعتمادُها إشعارٌ للجهة لا أمرَ صرف: لا رصيد لديها يُنقَص. وتُطابَق
  /// لاحقًا بسند التوريد الذي تأتي به الإعاشة.
  static const String main = 'MAIN';

  /// مخزن فرعي يطلب من المخزن الرئيسي.
  ///
  /// واعتمادُها إذنٌ بالتحويل: يسحبها أمين المخزن الرئيسي في شاشة التحويل
  /// فيُنشأ سندٌ حقيقي بين المستودعين.
  static const String branch = 'BRANCH';

  static const List<String> all = [main, branch];

  static const Map<String, String> labels = {
    main: 'طلبية المخزن الرئيسي (من جهة)',
    branch: 'طلبية مخزن فرعي (من المخزن الرئيسي)',
  };

  static String label(String v) => labels[v] ?? v;

  static bool isMain(String v) => v == main;
}

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
    received: 'منفَّذة',
    rejected: 'مرفوضة',
  };

  static String label(String v) => labels[v] ?? v;

  /// الوصف الدقيق للحالة بحسب نوع الطلبية.
  ///
  /// «معتمدة» تعني في الفرعية إذنًا بالتحويل، وفي الرئيسية إشعارًا لجهةٍ لا
  /// مخزن لها. وخلطُ المعنيين في كلمةٍ واحدة يجعل أمين المخزن ينتظر بضاعةً
  /// لا أحد يرسلها.
  static String labelOf(String status, String kind) => switch (status) {
        approved => RationKind.isMain(kind)
            ? 'معتمدة — إشعار للجهة'
            : 'معتمدة — جاهزة للتحويل',
        received => RationKind.isMain(kind) ? 'مطابَقة بتوريد' : 'محوَّلة',
        _ => label(status),
      };

  /// الحالات التي ما زالت تنتظر إجراءً — تُعدّ في لوحة «إجراءات تحتاج تدخل».
  static const List<String> open = [draft, pending, approved];
}

/// المستند الذي نُفِّذت به الطلبية.
class RationFulfillKind {
  /// سند تحويل بين مستودعين — طلبية مخزن فرعي.
  static const String transfer = 'TRANSFER';

  /// سند توريد من خارج الفرقة — طلبية المخزن الرئيسي.
  static const String receipt = 'RECEIPT';

  static const Map<String, String> labels = {
    transfer: 'سند تحويل',
    receipt: 'سند توريد',
  };

  static String label(String v) => labels[v] ?? v;

  /// المستند الذي تنتظره طلبيةٌ من هذا النوع.
  static String expectedFor(String orderKind) =>
      RationKind.isMain(orderKind) ? receipt : transfer;
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

  /// التنفيذ لا يقع إلا على طلبية **معتمدة**.
  ///
  /// والتنفيذ هنا ربطٌ بمستند لا حركةُ مخزون: سندُ التحويل أو التوريد هو من
  /// يحرّك الرصيد، وقد مرّ بفحوصه. لكن ربطَ طلبيةٍ لم يعتمدها أحدٌ بسندٍ
  /// يجعل السجل يشهد بإذنٍ لم يُعطَ.
  static bool canFulfill(String status) => status == RationStatus.approved;

  @Deprecated('استُبدل بـ canFulfill — الطلبية لا تُستلم بل تُربط بمستندها')
  static bool canReceive(String status) => canFulfill(status);

  static bool canReject(String status) =>
      status == RationStatus.pending || status == RationStatus.approved;

  static bool canDelete(String status) =>
      status == RationStatus.draft || status == RationStatus.rejected;

  /// الحالة التالية لإجراءٍ ما، أو `null` إن كان الإجراء غير مسموح الآن.
  static String? next(String status, String action) => switch (action) {
        'submit' => canSubmit(status) ? RationStatus.pending : null,
        'approve' => canApprove(status) ? RationStatus.approved : null,
        'fulfill' => canFulfill(status) ? RationStatus.received : null,
        'receive' => canFulfill(status) ? RationStatus.received : null,
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

  /// توجيه الطلبية: المخزن الرئيسي يطلب من جهة، وغيره يطلب من المخزن الرئيسي.
  ///
  /// المسار ليس تفضيلًا تنظيميًّا: هو ما يحدد أثر الاعتماد. فلو طلب فرعٌ من
  /// فرعٍ آخر لم يُعرف من يحوّل، ولو طلب الرئيسي من مستودعٍ لانتظر بضاعةً من
  /// نفسه.
  static String? validateRouting({
    required String kind,
    required String requesting,
    required String supplying,
    required String authorityId,
    required String mainWarehouse,
  }) {
    final main = mainWarehouse.trim();
    if (main.isEmpty) {
      return 'لم يُعيَّن مخزن رئيسي بعد — عيّنه من شاشة المستودعات أولًا';
    }
    final req = requesting.trim();
    if (RationKind.isMain(kind)) {
      if (req != main) {
        return 'طلبية المخزن الرئيسي يطلبها «$main» وحده — '
            'اختر «طلبية مخزن فرعي» لغيره';
      }
      if (authorityId.trim().isEmpty) {
        return 'اختر الجهة المطلوب منها';
      }
      return null;
    }
    if (req.isEmpty) return 'المستودع الطالب مطلوب';
    if (req == main) {
      return 'المخزن الرئيسي لا يطلب من نفسه — اختر «طلبية المخزن الرئيسي»';
    }
    if (supplying.trim() != main) {
      return 'المخزن الفرعي يطلب من المخزن الرئيسي «$main» وحده';
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
