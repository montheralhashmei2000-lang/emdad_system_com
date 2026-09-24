/// انحراف التفريدة اليومية عن متوسط الشهر.
///
/// **الغرض:** حين يُصرف للمعسكر بحسب متوسط القوة، فاليوم الذي قوته أعلى من
/// المتوسط يكون قد أخذ أقل من حاجته (فله فرق)، واليوم الذي قوته أدنى يكون قد
/// أخذ أكثر (فعليه فرق). والتراكم يبيّن أي المعسكرات يُظلم بالمتوسط وأيها
/// يُحابى — وهو ما لا يظهره إجمالي الشهر أبدًا لأنه يُلغي الفروق بجمعها.
///
/// **ولا يُحفظ في جدول.** الانحراف مشتقّ من التفريدة والمقرر، وكلاهما محفوظ.
/// حفظه ثالثًا يعني نسخة تُصبح كاذبة أول ما تُصحَّح تفريدة يوم — وتصحيح
/// التفريدة يقع كثيرًا.
library;

import 'camp_ledger.dart';

/// انحراف يوم واحد.
class VarianceDay {
  const VarianceDay({
    required this.date,
    required this.actual,
    required this.average,
    required this.variance,
    required this.cumulative,
  });

  /// yyyy-MM-dd
  final String date;

  /// القوة المسجّلة لهذا اليوم.
  final double actual;

  /// متوسط الشهر الذي صُرف على أساسه.
  final int average;

  /// موجب ⇒ له (قوته فوق المتوسط)، سالب ⇒ عليه.
  final double variance;

  /// المجموع حتى هذا اليوم.
  final double cumulative;

  bool get isCredit => variance > CampLedgerCalc.epsilon;
  bool get isDebit => variance < -CampLedgerCalc.epsilon;
}

class VarianceTracker {
  const VarianceTracker._();

  /// انحراف يوم: المعدل اليومي للفرد × (القوة الفعلية − المتوسط).
  static double dailyVariance({
    required double dailyRatePerPerson,
    required double actualStrength,
    required int averageStrength,
  }) =>
      CampLedgerCalc.round(dailyRatePerPerson * (actualStrength - averageStrength));

  /// المعدل اليومي للفرد من المقرر الشهري.
  static double dailyRate({
    required double monthlyQtyPerPerson,
    required double measureFactor,
  }) {
    final factor = measureFactor <= 0 ? 1.0 : measureFactor;
    return monthlyQtyPerPerson * factor / 30.0;
  }

  /// سلسلة الانحراف اليومي مرتّبة بالتاريخ، مع التراكم.
  ///
  /// [strengthByDay] التاريخ ⇦ القوة المسجّلة. الأيام غير المسجّلة لا تدخل:
  /// لا انحراف ليوم لا قوة له.
  static List<VarianceDay> series({
    required Map<String, double> strengthByDay,
    required double monthlyQtyPerPerson,
    required double measureFactor,
  }) {
    final days = strengthByDay.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (days.isEmpty) return const [];

    final avg = CampLedgerCalc.averageStrength(days.map((e) => e.value));
    final rate = dailyRate(
      monthlyQtyPerPerson: monthlyQtyPerPerson,
      measureFactor: measureFactor,
    );

    final out = <VarianceDay>[];
    var cumulative = 0.0;
    for (final e in days) {
      final v = dailyVariance(
        dailyRatePerPerson: rate,
        actualStrength: e.value,
        averageStrength: avg,
      );
      cumulative = CampLedgerCalc.round(cumulative + v);
      out.add(VarianceDay(
        date: e.key,
        actual: e.value,
        average: avg,
        variance: v,
        cumulative: cumulative,
      ));
    }
    return out;
  }

  /// خلاصة السلسلة: الانحراف الصافي، وأكبر يوم له وأكبر يوم عليه.
  ///
  /// الصافي يقارب الصفر دائمًا حين يُحسب المتوسط من الأيام نفسها — فالفائدة
  /// في **أطراف** السلسلة لا في مجموعها: يومٌ انحرافه كبير يعني قوةً تبدّلت
  /// فجأةً، وهي إما حركة وحدات أو خطأ تفريدة.
  static ({double net, VarianceDay? maxCredit, VarianceDay? maxDebit}) summary(
    List<VarianceDay> series,
  ) {
    if (series.isEmpty) return (net: 0, maxCredit: null, maxDebit: null);
    VarianceDay? up;
    VarianceDay? down;
    for (final d in series) {
      if (up == null || d.variance > up.variance) up = d;
      if (down == null || d.variance < down.variance) down = d;
    }
    return (
      net: series.last.cumulative,
      maxCredit: up != null && up.isCredit ? up : null,
      maxDebit: down != null && down.isDebit ? down : null,
    );
  }
}
