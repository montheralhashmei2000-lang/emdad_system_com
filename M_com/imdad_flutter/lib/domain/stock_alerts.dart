/// تنبيهات المخزون: الأصناف تحت الحد الأدنى، والدفعات القريبة من انتهاء صلاحيتها.
///
/// قاعدة «تحت الحد» كانت مكتوبة في ست شاشات (الأصناف، الأرصدة، الرئيسية،
/// صحة النظام، …) بصيغ متقاربة. هنا تُكتب مرة واحدة.
library;

/// صنف تحت حده الأدنى (أو عنده تمامًا).
class LowStockAlert {
  const LowStockAlert({required this.itemId, required this.balance, required this.minQty});

  final String itemId;
  final double balance;
  final double minQty;

  /// المطلوب لبلوغ الحد الأدنى.
  double get shortfall => minQty - balance;

  /// نفد الصنف كليًا.
  bool get outOfStock => balance <= 0;
}

/// دفعة واردة لها تاريخ صلاحية (سطر من سند وارد معتمد).
class ExpiryLot {
  const ExpiryLot({
    required this.warehouse,
    required this.itemId,
    required this.receivedOn,
    required this.expiryDate,
    required this.baseQty,
    this.refNo = '',
  });

  final String warehouse;
  final String itemId;

  /// تاريخ الاستلام (yyyy-MM-dd) — يحدد ترتيب خروج الدفعات.
  final String receivedOn;

  /// تاريخ الانتهاء (yyyy-MM-dd)؛ فارغ = بلا صلاحية.
  final String expiryDate;
  final double baseQty;
  final String refNo;
}

/// كمية من دفعة ما زالت في المستودع، وتنتهي صلاحيتها قريبًا أو انتهت.
class ExpiryAlert {
  const ExpiryAlert({required this.lot, required this.remainingQty, required this.daysLeft});

  final ExpiryLot lot;

  /// الكمية المقدَّرة الباقية من هذه الدفعة بالوحدة الأساسية.
  final double remainingQty;

  /// سالب = انتهت منذ هذا العدد من الأيام.
  final int daysLeft;

  bool get expired => daysLeft < 0;
}

class StockAlerts {
  const StockAlerts._();

  /// هل رصيد الصنف تحت حده الأدنى؟ الحد صفر = لا حد.
  static bool isLow(double balance, double minQty) => minQty > 0 && balance <= minQty;

  /// الأصناف التي بلغت حدها الأدنى، الأشد نقصًا (نسبةً إلى حدها) أولًا.
  static List<LowStockAlert> lowStock(
    Iterable<({String id, double minQty})> items,
    Map<String, double> balances,
  ) {
    final out = [
      for (final it in items)
        if (isLow(balances[it.id] ?? 0, it.minQty))
          LowStockAlert(itemId: it.id, balance: balances[it.id] ?? 0, minQty: it.minQty),
    ];
    out.sort((a, b) => (a.balance / a.minQty).compareTo(b.balance / b.minQty));
    return out;
  }

  /// الدفعات التي ما زال منها شيء في المستودع وتنتهي خلال [withinDays] يومًا أو انتهت.
  ///
  /// لا يُسجَّل في السندات من أي دفعة صُرف، فيُقدَّر الباقي على قاعدة «الوارد
  /// أولًا يُصرف أولًا»: رصيد الصنف في المستودع يُنسب إلى أحدث الدفعات، وما زاد
  /// عنه يُعدّ مصروفًا من الأقدم. فالدفعة القديمة التي استُهلكت لا تُنبِّه.
  /// والرصيد الذي لا تغطيه دفعات مؤرَّخة (افتتاحي، أو وارد بلا صلاحية) لا
  /// يُنسب إلى أي دفعة.
  static List<ExpiryAlert> expiring({
    required Iterable<ExpiryLot> lots,
    required Map<String, Map<String, double>> balances,
    required DateTime today,
    int withinDays = 30,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final byKey = <String, List<ExpiryLot>>{};
    for (final l in lots) {
      byKey.putIfAbsent('${l.warehouse}|${l.itemId}', () => []).add(l);
    }
    final out = <ExpiryAlert>[];
    byKey.forEach((key, group) {
      final first = group.first;
      var left = balances[first.warehouse]?[first.itemId] ?? 0;
      if (left <= 0) return;
      // الأحدث استلامًا أولًا: هو الباقي على الرف.
      group.sort((a, b) => b.receivedOn.compareTo(a.receivedOn));
      for (final lot in group) {
        if (left <= 1e-9) break;
        final take = lot.baseQty < left ? lot.baseQty : left;
        left -= take;
        final exp = DateTime.tryParse(lot.expiryDate);
        if (exp == null || take <= 0) continue;
        final daysLeft = DateTime(exp.year, exp.month, exp.day).difference(day).inDays;
        if (daysLeft <= withinDays) {
          out.add(ExpiryAlert(lot: lot, remainingQty: _round(take), daysLeft: daysLeft));
        }
      }
    });
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}
