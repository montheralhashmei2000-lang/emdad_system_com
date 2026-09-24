/// حساب القوة (التفريدة) — نقل مطابق لمنطق strength-fix.js:
/// • قوة المعسكر ليوم محدد = سجل «إجمالي المعسكر» لذلك اليوم، وإلا مجموع سجلات وحداته لنفس اليوم.
/// • قوة الوحدة الفرعية = سجلها لذلك اليوم، وإلا حصتها من إجمالي المعسكر لذلك اليوم، وإلا صفر.
/// • قوة المطبخ/الفرن = معسكراته المرتبطة (مرة واحدة) + وحداته التي لا يُحسب معسكرها.
/// لا يُؤخذ أي سجل من يوم آخر، ولا يُجمع المعسكر مع وحداته.
library;

class StrengthRecord {
  const StrengthRecord({
    required this.unitId,
    required this.date,
    required this.total,
    this.campId = '',
    this.mode = 'detail', // camp | detail
  });

  final String unitId;
  final String campId;
  final String date; // yyyy-MM-dd
  final double total;
  final String mode;

  bool get isCampRecord => mode == 'camp' || (unitId.isNotEmpty && unitId == campId);
}

class UnitNode {
  const UnitNode({
    required this.id,
    this.parentId = '',
    this.isCamp = false,
    this.facilityIds = const [],
    this.name = '',
  });

  final String id;
  final String parentId;
  final bool isCamp;

  /// المنشآت المشترِكة فيها الوحدة — مطبخ وفرن معًا مثلًا.
  final List<String> facilityIds;

  final String name;

  bool subscribesTo(String facilityId) => facilityIds.contains(facilityId);
}

enum StrengthSource { campRecord, unitsSum, none }

class CampStrength {
  const CampStrength({required this.total, required this.source, required this.unitsCounted});

  final double total;
  final StrengthSource source;
  final int unitsCounted;
}

class StrengthCalculator {
  StrengthCalculator({required this.records, required this.units});

  final List<StrengthRecord> records;
  final List<UnitNode> units;

  /// قوة المعسكر في يوم محدد.
  CampStrength campStrengthOn(String campId, String date) {
    if (campId.isEmpty || date.isEmpty) {
      return const CampStrength(total: 0, source: StrengthSource.none, unitsCounted: 0);
    }
    final sameDay = records
        .where((r) => r.date == date && (r.campId == campId || r.unitId == campId))
        .toList();

    final campRec = sameDay.where((r) => r.isCampRecord).toList();
    if (campRec.isNotEmpty) {
      return CampStrength(
        total: campRec.first.total,
        source: StrengthSource.campRecord,
        unitsCounted: 0,
      );
    }

    final details = sameDay.where((r) => !r.isCampRecord).toList();
    if (details.isEmpty) {
      return const CampStrength(total: 0, source: StrengthSource.none, unitsCounted: 0);
    }
    final total = details.fold<double>(0, (sum, r) => sum + r.total);
    return CampStrength(
      total: _round(total),
      source: StrengthSource.unitsSum,
      unitsCounted: details.length,
    );
  }

  /// قوة وحدة في يوم محدد.
  double unitStrengthOn(String unitId, String date) {
    if (unitId.isEmpty || date.isEmpty) return 0;

    final own = records
        .where((r) => r.unitId == unitId && r.date == date && !r.isCampRecord)
        .toList();
    if (own.isNotEmpty) return own.first.total;

    final node = _node(unitId);
    final isCamp = node != null &&
        (node.isCamp || node.parentId.isEmpty) &&
        units.any((u) => u.parentId == unitId);
    if (isCamp) return campStrengthOn(unitId, date).total;

    // معسكر بلا وحدات تابعة: أي سجل له في ذلك اليوم (strength-fix.js).
    if (node != null && node.parentId.isEmpty) {
      final campOnly = records.where((r) => r.unitId == unitId && r.date == date).toList();
      return campOnly.isEmpty ? 0 : campOnly.first.total;
    }

    if (node != null && node.parentId.isNotEmpty) {
      final camp = records
          .where((r) =>
              r.date == date &&
              r.isCampRecord &&
              (r.unitId == node.parentId || r.campId == node.parentId))
          .toList();
      if (camp.isNotEmpty) {
        final siblings = units.where((u) => u.parentId == node.parentId).toList();
        // النسبة من آخر قوة معروفة لكل وحدة (للتوزيع فقط)، وإلا بالتساوي
        final last = siblings.map(_lastKnown).toList();
        final sum = last.fold<double>(0, (a, b) => a + b);
        final index = siblings.indexWhere((u) => u.id == unitId);
        if (index < 0) return 0;
        final share = sum > 0 ? last[index] / sum : (siblings.isEmpty ? 0 : 1 / siblings.length);
        return (camp.first.total * share).round().toDouble();
      }
    }
    return 0;
  }

  /// قوة مطبخ أو فرن في يوم محدد (بلا ازدواج بين المعسكر ووحداته).
  double facilityStrengthOn(String facilityId, String date) {
    if (facilityId.isEmpty || date.isEmpty) return 0;
    final linked = units.where((u) => u.subscribesTo(facilityId)).toList();
    if (linked.isEmpty) return 0;

    final campIds = linked
        .where((u) => u.isCamp || u.parentId.isEmpty)
        .map((u) => u.id)
        .toSet();

    var total = 0.0;
    for (final campId in campIds) {
      total += campStrengthOn(campId, date).total;
    }
    for (final u in linked) {
      if (campIds.contains(u.id)) continue;
      if (u.parentId.isNotEmpty && campIds.contains(u.parentId)) continue;
      total += unitStrengthOn(u.id, date);
    }
    return _round(total);
  }

  UnitNode? _node(String id) {
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  double _lastKnown(UnitNode u) {
    final history = records.where((r) => r.unitId == u.id && !r.isCampRecord).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return history.isEmpty ? 0 : history.first.total;
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}
