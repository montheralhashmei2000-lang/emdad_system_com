import 'dart:math' as math;

/// نسب الاستحقاق — نقل مطابق لمنطق النسخة الحالية:
/// • تُسجَّل الكمية للفرد **شهريًا** بوحدة قياس مختارة (`qtyPerPerson` + `measureUnitName`).
/// • المعدل اليومي بوحدة الأساس = (الكمية الشهرية × معامل الوحدة المختارة) ÷ 30.
/// • الاستحقاق = المعدل اليومي × عدد الأفراد × عدد الأيام.
class Entitlement {
  const Entitlement({
    required this.itemId,
    required this.qtyPerPerson,
    this.measureUnitName = '',
    this.measureFactor = 1,
    this.itemName = '',
  });

  final String itemId;
  final String itemName;

  /// الكمية الشهرية للفرد الواحد بوحدة القياس المختارة.
  final double qtyPerPerson;

  /// اسم وحدة القياس المختارة (قد تكون وحدة الأساس أو وحدة أكبر).
  final String measureUnitName;

  /// معامل تحويل الوحدة المختارة إلى وحدة الأساس (كيس 40 كجم ⇒ 40).
  final double measureFactor;

  /// الكمية الشهرية للفرد محوَّلة إلى وحدة الأساس.
  double get monthlyBaseQty => qtyPerPerson * (measureFactor <= 0 ? 1 : measureFactor);

  /// المعدل اليومي للفرد بوحدة الأساس.
  double get dailyBaseRate => monthlyBaseQty / 30.0;
}

class EntitlementResult {
  const EntitlementResult({
    required this.itemId,
    required this.persons,
    required this.days,
    required this.dailyBaseRate,
    required this.totalBaseQty,
  });

  final String itemId;
  final int persons;
  final int days;
  final double dailyBaseRate;

  /// إجمالي الاستحقاق بوحدة الأساس.
  final double totalBaseQty;

  String get formula => 'المعدل اليومي للفرد × عدد الأفراد × عدد الأيام';
}

class EntitlementEngine {
  /// حساب الاستحقاق لصنف واحد.
  static EntitlementResult compute({
    required Entitlement entitlement,
    required int persons,
    required int days,
  }) {
    final p = math.max(0, persons);
    final d = math.max(1, days);
    final rate = entitlement.dailyBaseRate;
    final total = _round3(rate * p * d);
    return EntitlementResult(
      itemId: entitlement.itemId,
      persons: p,
      days: d,
      dailyBaseRate: rate,
      totalBaseQty: total,
    );
  }

  /// تحويل الاستحقاق من وحدة الأساس إلى وحدة الإدخال المختارة (للعرض في السند).
  static double toMeasureUnit(double baseQty, double measureFactor) {
    final f = measureFactor <= 0 ? 1 : measureFactor;
    return _round3(baseQty / f);
  }

  /// مقارنة الرصيد المتاح بالاستحقاق المحسوب.
  static EntitlementCheck assess({
    required Entitlement entitlement,
    required int persons,
    required int days,
    required double availableBaseQty,
  }) {
    final r = compute(entitlement: entitlement, persons: persons, days: days);
    return EntitlementCheck(
      due: r.totalBaseQty,
      available: availableBaseQty,
      shortage: _round3(math.max(0, r.totalBaseQty - availableBaseQty)),
    );
  }

  static double _round3(double v) => (v * 1000).round() / 1000;
}

class EntitlementCheck {
  const EntitlementCheck({
    required this.due,
    required this.available,
    required this.shortage,
  });

  final double due;
  final double available;
  final double shortage;

  bool get isEnough => shortage <= 0;
}
