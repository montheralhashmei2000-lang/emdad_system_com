/// تنبيهات النظام — ما يحتاج إجراءً قبل أن يصير مشكلة.
///
/// **التنبيه مشتقّ لا محفوظ.** يُحسب من حالة البيانات عند كل فحص، ولا يُخزَّن
/// إلا ما قرأه المستخدم أو أخفاه. ولو خُزّنت التنبيهات نفسها لبقي تنبيه «مخزون
/// منخفض» ظاهرًا بعد أن عُزّز المخزون، ولاعتاد المستخدم تجاهل الجرس — وجرسٌ
/// يُتجاهل أسوأ من غياب الجرس.
///
/// ولذلك [AppNotification.id] **ثابت لنفس الحالة**: تنبيه نفاد صنفٍ في معسكر
/// يأخذ المعرّف نفسه في كل فحص، فيُعرف أنه هو الذي قُرئ أمس ولا يُعاد إظهاره.
library;

enum NotifySeverity {
  /// معلومة تُقرأ ولا تستدعي إجراءً فوريًا.
  info,

  /// يحتاج إجراءً قريبًا.
  warning,

  /// يحتاج إجراءً اليوم.
  danger,
}

extension NotifySeverityX on NotifySeverity {
  String get label => switch (this) {
        NotifySeverity.info => 'معلومة',
        NotifySeverity.warning => 'تحذير',
        NotifySeverity.danger => 'عاجل',
      };

  /// ترتيب العرض: الأخطر أولًا.
  int get rank => switch (this) {
        NotifySeverity.danger => 0,
        NotifySeverity.warning => 1,
        NotifySeverity.info => 2,
      };
}

/// نوع التنبيه — يحدّد أيقونته والشاشة التي يفتحها.
enum NotifyKind {
  campStockLow,
  assetExpiring,
  assetExpired,
  rationPending,
  mealPlanEnding,
  settlementDue,
  stockNegative,
}

extension NotifyKindX on NotifyKind {
  String get icon => switch (this) {
        NotifyKind.campStockLow => 'radio',
        NotifyKind.assetExpiring || NotifyKind.assetExpired => 'package',
        NotifyKind.rationPending => 'clipboard',
        NotifyKind.mealPlanEnding => 'utensils',
        NotifyKind.settlementDue => 'lock',
        NotifyKind.stockNegative => 'alert',
      };

  /// مسار الشاشة التي يفتحها التنبيه في القشرة.
  String get route => switch (this) {
        NotifyKind.campStockLow => 'campDashboard',
        NotifyKind.assetExpiring || NotifyKind.assetExpired => 'assets',
        NotifyKind.rationPending => 'rationOrders',
        NotifyKind.mealPlanEnding => 'mealPlans',
        NotifyKind.settlementDue => 'campSettlement',
        NotifyKind.stockNegative => 'campLedger',
      };

  /// الصفحة التي تحكم ظهور التنبيه: من لا يرى الشاشة لا يُنبَّه بما فيها.
  String get page => route;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.body,
    this.read = false,
  });

  /// معرّف ثابت لنفس الحالة — لا يحمل تاريخًا ولا رقمًا متغيّرًا.
  final String id;
  final NotifyKind kind;
  final NotifySeverity severity;
  final String title;
  final String body;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        severity: severity,
        title: title,
        body: body,
        read: read ?? this.read,
      );
}

class NotifyRules {
  const NotifyRules._();

  /// أقصى ما يُعرض من تنبيهات نوعٍ واحد.
  ///
  /// معسكرٌ نقصت فيه أربعون صنفًا يُغرق القائمة فتُخفي ما سواه. تُعرض الأشدّ
  /// ويُذكر الباقي عددًا — والتفصيل في شاشته.
  static const int perKindCap = 8;

  /// ترتيب العرض: الأخطر، ثم غير المقروء، ثم بالنوع.
  static List<AppNotification> sort(List<AppNotification> items) {
    final out = [...items];
    out.sort((a, b) {
      final s = a.severity.rank.compareTo(b.severity.rank);
      if (s != 0) return s;
      if (a.read != b.read) return a.read ? 1 : -1;
      return a.kind.index.compareTo(b.kind.index);
    });
    return out;
  }

  /// يقصّ كل نوع إلى [perKindCap] ويضيف سطرًا يلخّص ما حُجب.
  static List<AppNotification> cap(List<AppNotification> items) {
    final byKind = <NotifyKind, List<AppNotification>>{};
    for (final n in items) {
      byKind.putIfAbsent(n.kind, () => []).add(n);
    }
    final out = <AppNotification>[];
    byKind.forEach((kind, list) {
      final sorted = sort(list);
      out.addAll(sorted.take(perKindCap));
      final hidden = sorted.length - perKindCap;
      if (hidden > 0) {
        out.add(AppNotification(
          id: 'more.${kind.name}',
          kind: kind,
          severity: NotifySeverity.info,
          title: 'و$hidden تنبيهًا آخر من النوع نفسه',
          body: 'افتح الشاشة لرؤيتها كلها',
        ));
      }
    });
    return sort(out);
  }

  static int unreadOf(Iterable<AppNotification> items) =>
      items.where((n) => !n.read).length;
}
