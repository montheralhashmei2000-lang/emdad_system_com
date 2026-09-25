/// قواعد سند الصرف بعيدًا عن الواجهة: التحقق من رأس السند وسطوره، وكفاية الرصيد،
/// واحتساب الكمية من الاستحقاق، وموعد الصرف القادم للوحدة.
///
/// كانت كلها داخل `issue_screen.dart`، وبعضها مكرر بين زر التنفيذ ولوحة التحقق
/// الحية بنصوص متطابقة. هنا تُكتب مرة واحدة وتُختبر دون بناء شاشة.
library;

/// أنواع توجيه الصرف بترتيب تبويبات الشاشة.
enum IssueTarget {
  unit, // وحدة مستفيدة
  facility, // مطبخ أو فرن
  custom, // مستلم باسمه
  multiUnit; // وحدات متعددة (لكل سطر وحدته)

  static IssueTarget of(int index) => IssueTarget.values[index.clamp(0, IssueTarget.values.length - 1)];
}

/// رأس سند الصرف كما أدخله المستخدم.
class IssueHeader {
  const IssueHeader({
    required this.target,
    required this.warehouse,
    required this.date,
    this.unitId = '',
    this.unitName = '',
    this.facilityId = '',
    this.facilityLabel = '',
    this.customRecipient = '',
  });

  final IssueTarget target;
  final String warehouse;
  final String date;
  final String unitId;
  final String unitName;
  final String facilityId;
  final String facilityLabel;
  final String customRecipient;

  /// اسم المستلم كما يُحفظ ويُطبع (`recipientDisplay`).
  String get recipient => switch (target) {
        IssueTarget.unit => unitName,
        IssueTarget.facility => facilityLabel,
        IssueTarget.custom => customRecipient.trim(),
        IssueTarget.multiUnit => 'صرف لوحدات متعددة',
      };
}

/// ملاحظة تحقق على السند. كل ملاحظة تمنع التنفيذ عند الضغط على الزر؛ و[isError]
/// يحدد درجتها في لوحة التحقق الحية فقط (خطأ أحمر أو تنبيه).
class IssueProblem {
  const IssueProblem(this.isError, this.title, this.message);

  final bool isError;
  final String title;

  /// نص الرسالة كما يظهر في التنبيه المنبثق (يبدأ بـ ✖).
  final String message;

  /// النص بلا رمز البداية، كما يظهر في لوحة التحقق الحية.
  String get detail => message.replaceFirst(RegExp(r'^✖\s*'), '');
}

class IssueRules {
  const IssueRules._();

  /// مشكلات رأس السند بترتيب فحص زر التنفيذ؛ الأولى هي ما يُعرض عند الضغط.
  static List<IssueProblem> headerProblems(IssueHeader h, {required DateTime today}) {
    final out = <IssueProblem>[];
    if (h.warehouse.isEmpty) {
      out.add(const IssueProblem(false, 'المستودع غير محدد', '✖ اختر المستودع'));
    }
    if (h.date.isEmpty) {
      out.add(const IssueProblem(true, 'تاريخ غير محدد', '✖ اختر تاريخ الصرف'));
    } else if (isFuture(h.date, today)) {
      out.add(const IssueProblem(true, 'تاريخ غير صالح', '✖ تاريخ الصرف لا يمكن أن يكون في المستقبل'));
    }
    switch (h.target) {
      case IssueTarget.unit when h.unitId.isEmpty:
        out.add(const IssueProblem(false, 'الوحدة المستفيدة غير محددة', '✖ اختر الوحدة المستفيدة'));
      case IssueTarget.facility when h.facilityId.isEmpty:
        out.add(const IssueProblem(false, 'المطبخ/الفرن غير محدد', '✖ اختر المطبخ أو الفرن'));
      case IssueTarget.custom when h.customRecipient.trim().isEmpty:
        out.add(const IssueProblem(false, 'اسم المستلم ناقص', '✖ اكتب اسم المستلم'));
      default:
    }
    return out;
  }

  /// هل التاريخ (yyyy-mm-dd) بعد اليوم؟
  static bool isFuture(String isoDate, DateTime today) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return false;
    return DateTime(d.year, d.month, d.day).isAfter(DateTime(today.year, today.month, today.day));
  }

  /// أول صنف يتجاوز مجموعُ خصمه رصيدَ المستودع، أو null إن كفى الرصيد للجميع.
  ///
  /// الجمع لكل صنف لا لكل سطر: سطران من الصنف نفسه قد يكفي كل منهما وحده ولا
  /// يكفيان معًا.
  static Shortage? shortage(Iterable<(String itemId, double baseQty)> lines, Map<String, double> balances) {
    final sum = <String, double>{};
    for (final (id, qty) in lines) {
      if (id.isEmpty) continue;
      sum[id] = (sum[id] ?? 0) + qty;
    }
    for (final e in sum.entries) {
      final have = balances[e.key] ?? 0;
      if (e.value > have + 1e-9) return Shortage(e.key, have, e.value);
    }
    return null;
  }

  /// الكمية المستحقة بوحدة السطر: (المقرر الشهري ÷ ٣٠) × القوة × الأيام.
  ///
  /// [monthlyPerPerson] بوحدة القياس المقررة، و[measureFactor] معاملها إلى
  /// الوحدة الأساسية، و[lineFactor] معامل وحدة السطر. null إن لم ينطبق الاحتساب.
  static double? entitledQty({
    required double monthlyPerPerson,
    required double measureFactor,
    required double strength,
    required int days,
    required double lineFactor,
  }) {
    if (monthlyPerPerson == 0 || strength <= 0) return null;
    final perDayBase = monthlyPerPerson * measureFactor / 30.0;
    final totalBase = perDayBase * strength * (days <= 0 ? 1 : days);
    return round3(totalBase / (lineFactor <= 0 ? 1 : lineFactor));
  }

  /// موعد الصرف القادم لوحدة من آخر صرفياتها المعتمدة (الأحدث أولًا).
  ///
  /// كل صرف يغطي `durationDays` يومًا من تاريخه؛ الموعد أبعد نهاية بين آخر عشرة.
  static NextDue nextDue(List<({String date, int durationDays})> recent, DateTime today) {
    if (recent.isEmpty) return const NextDue.none();
    DateTime? maxNext;
    for (final v in recent.take(10)) {
      final d = DateTime.tryParse(v.date);
      if (d == null) continue;
      final next = DateTime(d.year, d.month, d.day).add(Duration(days: v.durationDays <= 0 ? 1 : v.durationDays));
      if (maxNext == null || next.isAfter(maxNext)) maxNext = next;
    }
    if (maxNext == null) return const NextDue.unknown();
    final day = DateTime(today.year, today.month, today.day);
    return NextDue(maxNext, (maxNext.difference(day).inHours / 24).round());
  }

  static double round3(double v) => (v * 1000).round() / 1000;
}

class Shortage {
  const Shortage(this.itemId, this.available, this.requested);

  final String itemId;
  final double available;
  final double requested;
}

/// موعد الصرف القادم: [date] و[daysLeft] (سالب = متأخر، صفر = اليوم).
class NextDue {
  const NextDue(DateTime this.date, int this.daysLeft) : hasHistory = true;
  const NextDue.none()
      : date = null,
        daysLeft = null,
        hasHistory = false;
  const NextDue.unknown()
      : date = null,
        daysLeft = null,
        hasHistory = true;

  final DateTime? date;
  final int? daysLeft;

  /// هل للوحدة صرف سابق أصلًا؟
  final bool hasHistory;

  bool get overdue => (daysLeft ?? 0) < 0;
  bool get dueToday => daysLeft == 0;
}
