/// ترحيل الكميات من الوحدة الصغرى إلى الكبرى — نقل مطابق لمنطق النسخة الحالية.
/// مثال: أرز 4 كيس (الكيس 40 كجم) + أرز 50 كجم ⇒ 5 كيس + 10 كجم.
/// القاعدة: يُجمع الكل بوحدة الأساس ثم يُوزَّع من الوحدة الأكبر إلى الأصغر
/// **بين الوحدات المُدخلة فقط**، فلا يبقى في أي وحدة إلا ما هو أقل من معامل الوحدة الأكبر منها.
library;

class UnitLine {
  UnitLine({required this.unitName, required this.factor, required this.qty});

  final String unitName;

  /// معامل التحويل إلى وحدة الأساس (كجم = 1، كيس = 40).
  final double factor;
  double qty;

  double get baseQty => qty * factor;

  UnitLine copyWith({double? qty}) =>
      UnitLine(unitName: unitName, factor: factor, qty: qty ?? this.qty);

  @override
  String toString() => '$qty $unitName';
}

class UnitCarry {
  static const double _eps = 1e-9;

  /// يُعيد السطور بعد الترحيل. السطور ذات الوحدة نفسها تُدمج.
  /// إذا كانت كل السطور بوحدة واحدة فلا يحدث ترحيل (مطابق للنسخة الحالية).
  static List<UnitLine> normalize(List<UnitLine> lines) {
    final valid = lines.where((l) => l.qty > 0 && l.unitName.isNotEmpty).toList();
    if (valid.isEmpty) return <UnitLine>[];

    // دمج السطور المتشابهة في الوحدة
    final byUnit = <String, UnitLine>{};
    for (final l in valid) {
      final cur = byUnit[l.unitName];
      if (cur == null) {
        byUnit[l.unitName] = UnitLine(unitName: l.unitName, factor: l.factor, qty: l.qty);
      } else {
        cur.qty += l.qty;
      }
    }

    final units = byUnit.values.toList()..sort((a, b) => b.factor.compareTo(a.factor));
    if (units.length < 2 || units.first.factor == units.last.factor) {
      return units.map((u) => u.copyWith(qty: _round3(u.qty))).toList();
    }

    var rest = _round3(units.fold<double>(0, (sum, u) => sum + u.baseQty));
    final out = <UnitLine>[];
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      double q;
      if (i < units.length - 1) {
        q = ((rest + _eps) / u.factor).floorToDouble();
        rest = _round3(rest - q * u.factor);
      } else {
        q = _round3(rest / u.factor);
        rest = 0;
      }
      if (q > _eps) out.add(u.copyWith(qty: q));
    }
    return out;
  }

  /// وصف مختصر للتنبيه: «أرز: 5 كيس + 10 كجم».
  static String describe(String itemName, List<UnitLine> lines) =>
      '$itemName: ${lines.map((l) => '${_fmt(l.qty)} ${l.unitName}').join(' + ')}';

  static double _round3(double v) => (v * 1000).round() / 1000;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
