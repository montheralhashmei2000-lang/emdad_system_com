/// تجميع أسطر الأصناف وإعادة توزيعها على الوحدات.
///
/// حين يتكرر الصنف نفسه بوحدات مختلفة (٥٠ كيسًا في سطر و٩٠ كجم في آخر) لم يكن
/// النظام يجمعها: كان يدمج المتطابق في الوحدة فقط، فيبقى السطران منفصلين
/// ويصعب على المستودع قراءة الكمية الحقيقية.
///
/// الآن تُردّ كل الكميات إلى الوحدة الأساسية ثم تُوزَّع من جديد: الأكبر أولًا
/// بأكبر عدد صحيح ممكن، والباقي على الأصغر.
///
/// مثال: ٥٠ كيس (معامل ٤٠ = ٢٠٠٠) + ٩٠ كجم = ٢٠٩٠ كجم
/// ⇒ ٥٢ كيسًا (٢٠٨٠) + ١٠ كجم.
library;

/// سطر كمية قابل للتجميع.
class LineQty {
  const LineQty({
    required this.groupKey,
    required this.unitName,
    required this.factor,
    required this.qty,
  });

  /// ما يجعل السطرين قابلين للدمج: الصنف، ومعه أي تمييز آخر لا يصح خلطه
  /// (نوع عملية الأسطوانات مثلًا، أو الجهة المستفيدة في أوامر الصرف).
  final String groupKey;

  final String unitName;

  /// معامل التحويل إلى الوحدة الأساسية (كم وحدة أساسية في هذه الوحدة).
  final double factor;

  final double qty;

  /// الكمية بالوحدة الأساسية.
  double get baseQty => qty * (factor <= 0 ? 1 : factor);

  LineQty copyWith({double? qty}) => LineQty(
        groupKey: groupKey,
        unitName: unitName,
        factor: factor,
        qty: qty ?? this.qty,
      );

  @override
  String toString() => '$groupKey: $qty $unitName (×$factor)';
}

/// يجمع الأسطر المتكررة ويعيد توزيعها.
///
/// يحافظ على ترتيب ظهور المجموعات، وداخل كل مجموعة يرتّب الوحدات من الأكبر
/// إلى الأصغر. الوحدات المستعملة هي **ما اختاره المستخدم فعلًا** في أسطره، فلا
/// تُقحم وحدة لم يكتبها.
///
/// السطر الذي يؤول إلى صفر يُحذف (٣٠ كجم موزّعة على [كيس، كجم] لا تعني «٠ كيس»)،
/// إلا أن تكون المجموعة كلها أصفارًا فيبقى سطر واحد يحمل الصفر.
List<LineQty> consolidateLines(List<LineQty> lines) {
  if (lines.isEmpty) return const [];

  final order = <String>[];
  final groups = <String, List<LineQty>>{};
  for (final l in lines) {
    groups.putIfAbsent(l.groupKey, () {
      order.add(l.groupKey);
      return <LineQty>[];
    }).add(l);
  }

  final out = <LineQty>[];
  for (final key in order) {
    final group = groups[key]!;

    // وحدة واحدة فقط ⇒ جمع بسيط بلا إعادة توزيع.
    final units = <String, double>{};
    for (final l in group) {
      units[l.unitName] = l.factor <= 0 ? 1 : l.factor;
    }
    var total = 0.0;
    for (final l in group) {
      total += l.baseQty;
    }
    total = _round(total);

    if (units.length == 1) {
      final e = units.entries.first;
      out.add(LineQty(
        groupKey: key,
        unitName: e.key,
        factor: e.value,
        qty: _round(total / e.value),
      ));
      continue;
    }

    final sorted = units.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var remaining = total;
    final produced = <LineQty>[];
    for (var i = 0; i < sorted.length; i++) {
      final unit = sorted[i];
      final last = i == sorted.length - 1;
      // الأصغر يأخذ الباقي كله (وقد يكون كسرًا)؛ وما فوقها أعدادًا صحيحة.
      final qty = last
          ? _round(remaining / unit.value)
          : (remaining / unit.value + _epsilon).floorToDouble();
      remaining = _round(remaining - qty * unit.value);
      produced.add(LineQty(groupKey: key, unitName: unit.key, factor: unit.value, qty: qty));
    }

    final nonZero = produced.where((l) => l.qty != 0).toList();
    out.addAll(nonZero.isEmpty ? [produced.last] : nonZero);
  }
  return out;
}

/// هامش يمنع الكسور العائمة من إسقاط وحدة كاملة (١٩٩٩٫٩٩٩٩٩٩ ÷ ٤٠).
const double _epsilon = 1e-9;

double _round(double v) => (v * 1000).round() / 1000;

/// إعادة احتساب الكمية عند تغيير وحدة القياس، مع ثبات الكمية بالوحدة الأساسية.
///
/// ١١٠٠ كجم (معامل ١) ⇒ كيس (معامل ٤٠) = ٢٧٫٥ كيسًا. بدونها كان المستخدم
/// يغيّر الوحدة فيبقى الرقم كما هو، فينقلب المعنى تمامًا (١١٠٠ كيسًا!).
double convertQty(double qty, double fromFactor, double toFactor) {
  final from = fromFactor <= 0 ? 1.0 : fromFactor;
  final to = toFactor <= 0 ? 1.0 : toFactor;
  return _round(qty * from / to);
}
