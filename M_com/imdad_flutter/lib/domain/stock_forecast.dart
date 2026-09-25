/// توقّع نفاد الأصناف: كم يومًا يكفي الرصيد الحالي، ومتى ينفد.
///
/// معدّل الاستهلاك اليومي من مصدرين:
/// • **الفعلي**: متوسط المنصرف المعتمد في آخر فترة (المسودات والأوامر والملغى لا تُحسب).
/// • **المخطط**: المقرر الشهري للفرد ÷ ٣٠ × القوة الحالية — حاجة القوة كما تقررها
///   الاستحقاقات، ولو لم يُصرف بعد.
/// يُعتمد الأكبر منهما: التوقّع للتحذير المبكر، والتحذير المتأخر أسوأ من المبكر.
library;

import 'strength.dart';

class ForecastInput {
  const ForecastInput({
    required this.itemId,
    required this.balance,
    required this.consumed,
    required this.windowDays,
    this.plannedDaily,
  });

  final String itemId;

  /// الرصيد الحالي بالوحدة الأساسية.
  final double balance;

  /// المنصرف المعتمد خلال [windowDays] يومًا بالوحدة الأساسية.
  final double consumed;
  final int windowDays;

  /// الحاجة اليومية المقررة بالوحدة الأساسية، أو null إن لم يُعرف مقرر أو قوة.
  final double? plannedDaily;
}

class StockForecast {
  const StockForecast({
    required this.itemId,
    required this.balance,
    required this.actualDaily,
    required this.plannedDaily,
    required this.daysLeft,
    required this.stockoutDate,
  });

  final String itemId;
  final double balance;
  final double actualDaily;
  final double? plannedDaily;

  /// الأيام الباقية حتى النفاد بالمعدل المعتمد (صفر = نافد الآن).
  final double daysLeft;
  final DateTime stockoutDate;

  /// المعدل المعتمد في الحساب.
  double get daily => plannedDaily != null && plannedDaily! > actualDaily ? plannedDaily! : actualDaily;

  /// هل الحساب مبني على المقرر لا على الصرف الفعلي؟
  bool get fromPlan => plannedDaily != null && plannedDaily! > actualDaily;
}

class StockForecasting {
  const StockForecasting._();

  /// توقّعات الأصناف التي لها استهلاك، الأقرب نفادًا أولًا.
  /// صنف بلا صرف ولا مقرر لا يُتوقَّع له نفاد فلا يظهر.
  static List<StockForecast> forecast(Iterable<ForecastInput> inputs, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    final out = <StockForecast>[];
    for (final i in inputs) {
      final actual = i.windowDays > 0 ? i.consumed / i.windowDays : 0.0;
      final planned = i.plannedDaily;
      final daily = planned != null && planned > actual ? planned : actual;
      if (daily <= 0) continue;
      final left = i.balance <= 0 ? 0.0 : i.balance / daily;
      out.add(StockForecast(
        itemId: i.itemId,
        balance: i.balance,
        actualDaily: _round(actual),
        plannedDaily: planned == null ? null : _round(planned),
        daysLeft: (left * 10).floor() / 10,
        stockoutDate: day.add(Duration(days: left.floor())),
      ));
    }
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  /// الحاجة اليومية من المقرر: (الشهري بوحدة القياس × معاملها) ÷ ٣٠ × القوة.
  static double plannedDaily({
    required double monthlyPerPerson,
    required double measureFactor,
    required double strength,
  }) =>
      _round(monthlyPerPerson * (measureFactor <= 0 ? 1 : measureFactor) / 30 * strength);

  /// إجمالي القوة: مجموع المعسكرات في آخر يوم سُجّلت فيه قوة حتى [today].
  ///
  /// القوة تُحصر بيوم محدد ولا تُجمع أيام (قاعدة `StrengthCalculator`)، فيُؤخذ
  /// أحدث يوم له حصر كاملًا.
  static double currentStrength(StrengthCalculator calc, String today) {
    final days = {for (final r in calc.records) if (r.date.compareTo(today) <= 0) r.date}.toList()..sort();
    if (days.isEmpty) return 0;
    final latest = days.last;
    var total = 0.0;
    for (final camp in calc.units.where((u) => u.isCamp)) {
      total += calc.campStrengthOn(camp.id, latest).total;
    }
    return _round(total);
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}
