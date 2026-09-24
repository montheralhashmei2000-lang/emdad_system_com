/// قواعد خطط الوجبات وحساب احتياجها.
///
/// **موقعها من نسب الاستحقاق:** النسبة مقرَّر شهري ثابت للفرد من كل صنف، تُجيب
/// عن «كم يستحق اللواء من الأرز هذا الشهر». والخطة قائمة طعام تُجيب عن «كم
/// يلزم مطبخ الأحد غدًا». الأولى للمحاسبة، والثانية للتشغيل — ولا تُغني عن
/// الأخرى (انظر [Entitlement] في `entitlements.dart`).
library;

import 'date_span.dart';

export 'date_span.dart';

class MealType {
  static const String breakfast = 'BREAKFAST';
  static const String lunch = 'LUNCH';
  static const String dinner = 'DINNER';
  static const String snack = 'SNACK';

  /// بترتيب اليوم لا بترتيب الحروف: الجدول يُقرأ كما يُعاش.
  static const List<String> all = [breakfast, lunch, dinner, snack];

  static const Map<String, String> labels = {
    breakfast: 'الفطور',
    lunch: 'الغداء',
    dinner: 'العشاء',
    snack: 'وجبة خفيفة',
  };

  static String label(String v) => labels[v] ?? v;
}

class MealPlanType {
  static const String weekly = 'WEEKLY';
  static const String biweekly = 'BIWEEKLY';
  static const String monthly = 'MONTHLY';
  static const String custom = 'CUSTOM';

  static const List<String> all = [weekly, biweekly, monthly, custom];

  static const Map<String, String> labels = {
    weekly: 'أسبوعية',
    biweekly: 'نصف شهرية',
    monthly: 'شهرية',
    custom: 'مخصصة',
  };

  static String label(String v) => labels[v] ?? v;
}

class MealPlanStatus {
  static const String draft = 'DRAFT';
  static const String active = 'ACTIVE';
  static const String archived = 'ARCHIVED';

  static const List<String> all = [draft, active, archived];

  static const Map<String, String> labels = {
    draft: 'مسودة',
    active: 'نشطة',
    archived: 'مؤرشفة',
  };

  static String label(String v) => labels[v] ?? v;
}

class MealPlanRules {
  const MealPlanRules._();

  /// اختصار لـ[DateSpan.ymd] — أُبقي لأن الشاشات تستدعيه بهذا الاسم.
  static String ymd(DateTime d) => DateSpan.ymd(d);

  /// اسم اليوم بالعربية — يُحسب من التقويم لا من جدول لغة، فلا يحتاج تهيئة.
  static const List<String> weekdayNames = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  static String weekdayOf(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return '';
    return weekdayNames[d.weekday - 1];
  }

  /// نهاية المدى المحسوبة من نوع الخطة وبدايتها.
  ///
  /// الشهرية تنتهي بآخر يوم في الشهر لا بعد ثلاثين يومًا: خطة فبراير تنتهي
  /// بانتهاء فبراير، وإلا امتدت إلى مارس فاختلطت بخطته.
  static DateSpan spanOf(String planType, String startDate, {String customEnd = ''}) {
    final start = DateTime.tryParse(startDate);
    if (start == null) return DateSpan(startDate, customEnd);
    return switch (planType) {
      MealPlanType.weekly => DateSpan(startDate, ymd(start.add(const Duration(days: 6)))),
      MealPlanType.biweekly => DateSpan(startDate, ymd(start.add(const Duration(days: 13)))),
      MealPlanType.monthly =>
        DateSpan(startDate, ymd(DateTime(start.year, start.month + 1, 0))),
      _ => DateSpan(startDate, customEnd.isEmpty ? startDate : customEnd),
    };
  }

  // ───────────────────────── التحقق

  static String? validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'اسم الخطة مطلوب';
    if (v.length < 3) return 'اسم الخطة ثلاثة أحرف على الأقل';
    return null;
  }

  static String? validateSpan(DateSpan span) {
    if (span.start.trim().isEmpty) return 'تاريخ البداية مطلوب';
    if (span.end.trim().isEmpty) return 'تاريخ النهاية مطلوب';
    if (DateTime.tryParse(span.start) == null || DateTime.tryParse(span.end) == null) {
      return 'تاريخ غير صالح';
    }
    if (span.days <= 0) return 'تاريخ النهاية قبل البداية';
    if (span.days > 366) return 'مدة الخطة لا تتجاوز سنة';
    return null;
  }

  static String? validateQtyPerPerson(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'الكمية للفرد مطلوبة';
    final d = double.tryParse(v);
    if (d == null) return 'الكمية يجب أن تكون رقمًا';
    if (d <= 0) return 'الكمية أكبر من صفر';
    return null;
  }

  /// تاريخ المدخل داخل مدى الخطة — وإلا صار في الجدول يومٌ لا يُعرض.
  static String? validateEntryDate(String date, DateSpan span) {
    if (date.trim().isEmpty) return 'تاريخ الوجبة مطلوب';
    if (!span.contains(date)) return 'التاريخ خارج مدى الخطة';
    return null;
  }
}

/// سطر خطة كما تراه الحسابات — بلا ارتباط بجدول.
class MealEntry {
  const MealEntry({
    required this.entryDate,
    required this.mealType,
    required this.itemId,
    required this.qtyPerPerson,
    this.factor = 1,
    this.itemName = '',
    this.unitName = '',
  });

  final String entryDate;
  final String mealType;
  final String itemId;
  final double qtyPerPerson;
  final double factor;
  final String itemName;
  final String unitName;

  /// الكمية للفرد بوحدة الأساس — عليها يقع الجمع والمقارنة بالمنصرف.
  double get baseQtyPerPerson => qtyPerPerson * (factor <= 0 ? 1 : factor);
}

/// احتياج صنف واحد من خطة على مدى.
class MealRequirement {
  const MealRequirement({
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.baseQty,
    required this.days,
  });

  final String itemId;
  final String itemName;
  final String unitName;

  /// الإجمالي بوحدة الأساس.
  final double baseQty;

  /// عدد الأيام التي ظهر فيها الصنف فعلًا.
  final int days;
}

class MealPlanCalc {
  const MealPlanCalc._();

  /// احتياج الخطة من كل صنف: لكل مدخل، الكمية للفرد × قوة ذلك اليوم.
  ///
  /// **القوة تُقرأ ليوم المدخل وحده.** استعمال متوسط الفترة يخطئ حين تتبدّل
  /// القوة — وهي تتبدّل كل يوم في وحدةٍ ميدانية. ويومٌ بلا قوة مسجّلة يُحسب
  /// صفرًا لا يُقدَّر، فيظهر النقص في التقرير بدل أن يُخفيه تقدير.
  static List<MealRequirement> requirements({
    required List<MealEntry> entries,
    required Map<String, int> personsByDay,
    DateSpan? within,
  }) {
    final totals = <String, double>{};
    final names = <String, String>{};
    final units = <String, String>{};
    final daysSeen = <String, Set<String>>{};

    for (final e in entries) {
      if (within != null && !within.contains(e.entryDate)) continue;
      final persons = personsByDay[e.entryDate] ?? 0;
      final qty = e.baseQtyPerPerson * persons;
      totals.update(e.itemId, (v) => v + qty, ifAbsent: () => qty);
      names.putIfAbsent(e.itemId, () => e.itemName);
      units.putIfAbsent(e.itemId, () => e.unitName);
      daysSeen.putIfAbsent(e.itemId, () => <String>{}).add(e.entryDate);
    }

    final out = [
      for (final id in totals.keys)
        MealRequirement(
          itemId: id,
          itemName: names[id] ?? '',
          unitName: units[id] ?? '',
          baseQty: _round3(totals[id]!),
          days: daysSeen[id]?.length ?? 0,
        ),
    ];
    out.sort((a, b) => b.baseQty.compareTo(a.baseQty));
    return out;
  }

  /// فرق صنف واحد بين خطتين.
  static List<MealPlanDiff> compare({
    required List<MealEntry> a,
    required List<MealEntry> b,
  }) {
    double sum(List<MealEntry> es, String id) => es
        .where((e) => e.itemId == id)
        .fold<double>(0, (s, e) => s + e.baseQtyPerPerson);

    final names = <String, String>{};
    for (final e in [...a, ...b]) {
      names.putIfAbsent(e.itemId, () => e.itemName);
    }

    final out = [
      for (final id in names.keys)
        MealPlanDiff(
          itemId: id,
          itemName: names[id] ?? '',
          qtyA: _round3(sum(a, id)),
          qtyB: _round3(sum(b, id)),
        ),
    ];
    // الأكبر فرقًا أولًا: من يقارن خطتين يبحث عمّا تغيّر لا عمّا ثبت.
    out.sort((x, y) => y.delta.abs().compareTo(x.delta.abs()));
    return out;
  }

  static double _round3(double v) => (v * 1000).round() / 1000;
}

class MealPlanDiff {
  const MealPlanDiff({
    required this.itemId,
    required this.itemName,
    required this.qtyA,
    required this.qtyB,
  });

  final String itemId;
  final String itemName;

  /// إجمالي الكمية للفرد في الخطة (أ) و(ب) بوحدة الأساس.
  final double qtyA;
  final double qtyB;

  double get delta => qtyB - qtyA;

  /// نسبة التغير من (أ) إلى (ب). صنف جديد كليًا ⇒ ١٠٠٪.
  double get pct {
    if (qtyA == 0) return qtyB == 0 ? 0 : 100;
    return delta / qtyA * 100;
  }

  bool get onlyInA => qtyB == 0 && qtyA > 0;
  bool get onlyInB => qtyA == 0 && qtyB > 0;
}
