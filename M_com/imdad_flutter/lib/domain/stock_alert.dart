/// تنبيه نفاد مخزون المعسكر قبل وقوعه.
///
/// السؤال الذي يجيب عنه: «كم يومًا يكفي ما في مخزن المعسكر قبل أن يبلغ حدّه
/// الأدنى؟» — لا «هل نفد؟». التنبيه بعد النفاد لا قيمة له: التحويل من المخزن
/// الرئيسي إلى معسكر بعيد يحتاج يومًا أو يومين.
library;

enum AlertLevel {
  /// كفاية مريحة.
  ok,

  /// خمسة أيام أو أقل.
  low,

  /// يومان أو أقل.
  medium,

  /// يوم أو أقل.
  high,

  /// بلغ الحد الأدنى أو نزل عنه.
  critical,
}

extension AlertLevelX on AlertLevel {
  String get label => switch (this) {
        AlertLevel.ok => 'كافٍ',
        AlertLevel.low => 'منخفض',
        AlertLevel.medium => 'تحذير',
        AlertLevel.high => 'عاجل',
        AlertLevel.critical => 'حرج',
      };

  bool get needsAction => this != AlertLevel.ok;
}

/// حالة صنف واحد في معسكر واحد.
class StockAlert {
  const StockAlert({
    required this.campId,
    required this.campName,
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.current,
    required this.minStock,
    required this.maxStock,
    required this.dailyConsumption,
    required this.alertDaysBefore,
  });

  final String campId;
  final String campName;
  final String itemId;
  final String itemName;
  final String unitName;
  final double current;
  final double minStock;
  final double maxStock;
  final double dailyConsumption;
  final int alertDaysBefore;

  /// أيام الكفاية حتى بلوغ الحد الأدنى. لا استهلاك ⇒ `null` لا لانهاية:
  /// اللانهاية عددٌ يتسرّب إلى الحسابات والفرز والعرض، والغياب لا يتسرّب.
  double? get daysLeft {
    if (dailyConsumption <= 0) return null;
    if (current <= minStock) return 0;
    return StockAlertEngine.round((current - minStock) / dailyConsumption);
  }

  AlertLevel get level {
    final d = daysLeft;
    // صنف بلا استهلاك مسجّل: لا يُنبَّه عليه بالأيام، لكن نزوله تحت الحد
    // الأدنى حقيقةٌ قائمة تُعرض.
    if (d == null) return current <= minStock ? AlertLevel.critical : AlertLevel.ok;
    return StockAlertEngine.levelOf(d);
  }

  bool get shouldAlert {
    final d = daysLeft;
    if (d == null) return current <= minStock;
    return d <= alertDaysBefore;
  }

  /// الكمية المقترح تحويلها — تملأ إلى الحد الأعلى ولا تتجاوزه.
  double get suggestedTransfer {
    if (maxStock <= 0) return 0;
    final needed = maxStock - current;
    return needed <= 0 ? 0 : StockAlertEngine.round(needed);
  }
}

class StockAlertEngine {
  const StockAlertEngine._();

  /// نافذة قياس معدل الاستهلاك: أسبوع. أقصر منها يتأثر بيوم عطلة، وأطول
  /// يبطئ استجابة التنبيه لتغيّر القوة.
  static const int defaultWindowDays = 7;

  /// معدل الاستهلاك اليومي من سجل الطهي.
  ///
  /// **القسمة على أيام الاستهلاك الفعلية لا على طول النافذة.** صنفٌ يُطبخ
  /// يومين في الأسبوع وتُقسم كميته على سبعة يبدو استهلاكه ثلث حقيقته، فيتأخر
  /// التنبيه حتى ينفد فعلًا.
  static double dailyConsumption(Iterable<({String date, double baseQty})> logs) {
    final byDay = <String, double>{};
    for (final l in logs) {
      if (l.date.isEmpty) continue;
      byDay.update(l.date, (v) => v + l.baseQty, ifAbsent: () => l.baseQty);
    }
    final days = byDay.values.where((v) => v > 0).toList();
    if (days.isEmpty) return 0;
    return round(days.reduce((a, b) => a + b) / days.length);
  }

  static AlertLevel levelOf(double daysLeft) {
    if (daysLeft <= 0) return AlertLevel.critical;
    if (daysLeft <= 1) return AlertLevel.high;
    if (daysLeft <= 2) return AlertLevel.medium;
    if (daysLeft <= 5) return AlertLevel.low;
    return AlertLevel.ok;
  }

  /// ترتيب التنبيهات: الأحرج أولًا، ثم الأقل أيامًا.
  static List<StockAlert> sorted(List<StockAlert> alerts) {
    final out = [...alerts];
    out.sort((a, b) {
      final l = b.level.index.compareTo(a.level.index);
      if (l != 0) return l;
      return (a.daysLeft ?? double.maxFinite).compareTo(b.daysLeft ?? double.maxFinite);
    });
    return out;
  }

  static double round(double v) => (v * 1000).round() / 1000;

  /// خلاصة معسكر واحد: أسوأ مستوى فيه وعدد ما يحتاج تعزيزًا.
  ///
  /// حالة المعسكر هي حال **أسوأ أصنافه** لا متوسطها: معسكرٌ تسعةٌ من أصنافه
  /// ممتازة وواحدٌ نفد ليس «ممتازًا بنسبة ٩٠٪» — هو معسكر ينقصه صنف.
  static CampStatus statusOf(Iterable<StockAlert> alerts) {
    var worst = AlertLevel.ok;
    var needing = 0;
    var suggested = 0.0;
    for (final a in alerts) {
      if (a.level.index > worst.index) worst = a.level;
      if (a.shouldAlert) {
        needing++;
        suggested += a.suggestedTransfer;
      }
    }
    return CampStatus(level: worst, itemsNeeding: needing, suggestedTotal: round(suggested));
  }
}

/// حالة معسكر كاملة — ما يُعرض في بطاقته على اللوحة.
class CampStatus {
  const CampStatus({
    required this.level,
    required this.itemsNeeding,
    required this.suggestedTotal,
  });

  final AlertLevel level;
  final int itemsNeeding;
  final double suggestedTotal;

  /// التسمية الميدانية المعتادة للحالة العامة.
  String get label => switch (level) {
        AlertLevel.ok => 'ممتاز',
        AlertLevel.low => 'جيد',
        AlertLevel.medium => 'تحذير',
        AlertLevel.high => 'تحذير شديد',
        AlertLevel.critical => 'طوارئ',
      };
}
