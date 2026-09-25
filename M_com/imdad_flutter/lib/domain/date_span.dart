/// مدى تواريخ مغلق الطرفين، بصيغة `yyyy-MM-dd`.
///
/// مستقلٌّ عن أي وحدة عمل: تستعمله خطط الوجبات والتقارير معًا. وكان في
/// `meal_plan.dart` فاستُخرج هنا لئلا تستورد التقاريرُ الخططَ لتحصل على مدى.
///
/// والتواريخ نصوص لا `DateTime`: هكذا تُخزَّن في القاعدة، والمقارنة النصية على
/// `yyyy-MM-dd` ترتيبها ترتيب الزمن — فلا تحويل ولا منطقة زمنية تُزيح يومًا.
class DateSpan {
  const DateSpan(this.start, this.end);

  final String start;
  final String end;

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateSpan dayOf(DateTime d) {
    final s = ymd(d);
    return DateSpan(s, s);
  }

  /// عدد الأيام شاملًا الطرفين. مدى غير صالح ⇒ صفر.
  int get days {
    final a = DateTime.tryParse(start);
    final b = DateTime.tryParse(end);
    if (a == null || b == null || b.isBefore(a)) return 0;
    return b.difference(a).inDays + 1;
  }

  bool get isValid => days > 0;

  List<String> get dates {
    final a = DateTime.tryParse(start);
    final b = DateTime.tryParse(end);
    if (a == null || b == null || b.isBefore(a)) return const [];
    return [
      for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) ymd(d),
    ];
  }

  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;

  /// هل يتقاطع المداان؟
  bool overlaps(DateSpan other) =>
      start.compareTo(other.end) <= 0 && other.start.compareTo(end) <= 0;

  @override
  String toString() => '$start → $end';

  @override
  bool operator ==(Object other) =>
      other is DateSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// نوع الفترة في شاشات التقارير.
class PeriodKind {
  static const String daily = 'DAILY';
  static const String weekly = 'WEEKLY';
  static const String monthly = 'MONTHLY';
  static const String custom = 'CUSTOM';

  static const List<String> all = [daily, weekly, monthly, custom];

  static const Map<String, String> labels = {
    daily: 'يومي',
    weekly: 'أسبوعي',
    monthly: 'شهري',
    custom: 'فترة مخصصة',
  };

  static String label(String v) => labels[v] ?? v;

  /// يحلّ الفترة حول تاريخ مرجعي.
  ///
  /// الأسبوع يبدأ **السبت** لا الاثنين: أسبوع العمل هنا سبت–جمعة، وبدؤه
  /// بالاثنين يقسم الأسبوع الميداني نصفين على تقريرين.
  static DateSpan resolve(
    String kind,
    String anchor, {
    String customStart = '',
    String customEnd = '',
  }) {
    final at = DateTime.tryParse(anchor);
    if (at == null) return DateSpan(anchor, anchor);
    switch (kind) {
      case daily:
        return DateSpan.dayOf(at);
      case weekly:
        // DateTime.saturday = 6؛ الإزاحة إلى السبت السابق أو اليوم نفسه.
        final back = (at.weekday - DateTime.saturday + 7) % 7;
        final start = at.subtract(Duration(days: back));
        return DateSpan(DateSpan.ymd(start), DateSpan.ymd(start.add(const Duration(days: 6))));
      case monthly:
        return DateSpan(
          DateSpan.ymd(DateTime(at.year, at.month, 1)),
          DateSpan.ymd(DateTime(at.year, at.month + 1, 0)),
        );
      default:
        return DateSpan(
          customStart.isEmpty ? anchor : customStart,
          customEnd.isEmpty ? anchor : customEnd,
        );
    }
  }
}
