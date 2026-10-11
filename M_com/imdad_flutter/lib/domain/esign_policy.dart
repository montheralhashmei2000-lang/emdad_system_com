/// سياسة التوقيع الإلكتروني للسندات (البند H-5 في تدقيق 2026-10-10، وقرار
/// المالك في 2026-10-11).
///
/// كان كل سندٍ يُطبع يُوقَّع تلقائيًّا بمفتاح «القائد» — ومنه نموذجٌ لم يُحفظ
/// برقمٍ محجوزٍ لا مُستهلَك، فتخرج ورقةٌ رسمية موقَّعة لسندٍ لا وجود له. القرار:
///
/// • التوقيع على **السند المحفوظ** وحده، وبحالةٍ نهائية (لا مسودة ولا أمرًا
///   معلّقًا ولا ملغى ولا مرفوضًا).
/// • ثلاثة أوضاع في الإعدادات: تلقائي عند طباعة المحفوظ، أو **يدوي** يعتمده
///   القائد وحده بصلاحية [permKey]، أو معطَّل.
library;

import 'access_control.dart';

enum ESignMode {
  /// يُوقَّع السند المحفوظ تلقائيًّا عند طباعته.
  auto,

  /// لا يُوقَّع إلا بإجراءٍ صريح ممن يملك صلاحية التوقيع.
  manual,

  /// لا توقيع إلكتروني على السندات.
  off,
}

class ESignPolicy {
  const ESignPolicy._();

  /// مفتاح الإعدادات — **مزامَن**: سياسة الجهة لا تفضيل جهاز.
  static const String settingsKey = 'esignPolicy';

  /// صفحة الصلاحية في الكتالوج؛ الإجراء [PermAction.approve].
  static const String permKey = 'esign';

  static const Map<ESignMode, String> labels = {
    ESignMode.auto: 'تلقائي عند طباعة السند المحفوظ',
    ESignMode.manual: 'يدوي — يعتمده القائد وحده',
    ESignMode.off: 'معطَّل',
  };

  static ESignMode parse(Object? raw) => switch (raw) {
        'manual' => ESignMode.manual,
        'off' => ESignMode.off,
        _ => ESignMode.auto,
      };

  /// الحالات التي لا يُوقَّع سندها أبدًا.
  static const Set<String> _unsignable = {'', 'DRAFT', 'ORDER', 'CANCELLED', 'REJECTED'};

  /// هل يصلح سندٌ محفوظٌ بهذه الحالة للتوقيع؟
  static bool signable(String status) => !_unsignable.contains(status);

  /// هل يملك المستخدم التوقيع اليدوي؟
  ///
  /// **المالك، أو من مُنح الصلاحية صراحةً** — والمدير لا يرثها ضمنًا كما يرث
  /// بقية الصفحات: التوقيع باسم القائد قرارُ شخصٍ بعينه لا صلاحيةُ دور.
  static bool canSign({required String? role, required Map<String, dynamic> permissions}) {
    if (UserRole.isOwner(role)) return true;
    final page = permissions[permKey];
    return AccessControl.allows(page is Map ? page : null, PermAction.approve);
  }
}
