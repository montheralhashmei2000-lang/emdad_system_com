import 'package:flutter/material.dart';

import 'imd_format.dart';
import 'imd_tokens.dart';

/// شريط إشغال مع نسبة: اسم فوقه، شريط تقدّم، ونصّ «كذا من كذا» تحته.
///
/// اللون يتبع النسبة: `c.warn` عند الامتلاء (قرب طفح)، `c.danger` عند
/// الانخفاض الشديد، و`c.accent` بينهما، و`c.muted` إن كانت السعة غير معروفة
/// (صفر أو أقل) فلا نسبة تُحسب أصلًا.
///
/// استُخرجت من `_OccupancyBar` في `fuel_dashboard_screen.dart` — أول استخدامٍ
/// لها هناك (خزّانات المحروقات)، وعتباتها معاملاتٌ لا قيمًا ثابتة كي تصلح
/// لأي مقياس سعة/استخدام آخر لاحقًا (مستودع، حصة، إلخ).
class ImdOccupancyBar extends StatelessWidget {
  const ImdOccupancyBar({
    super.key,
    required this.name,
    required this.used,
    required this.capacity,
    this.unit = '',
    this.highAt = 90,
    this.lowAt = 20,
  });

  final String name;
  final double used;
  final double capacity;

  /// يُلحَق برقمَي الاستخدام والسعة في السطر السفلي (مثل «لتر»).
  final String unit;

  /// النسبة% التي يتحوّل عندها اللون إلى `c.warn` (امتلاء).
  final double highAt;

  /// النسبة% التي يتحوّل تحتها اللون إلى `c.danger` (نضوب).
  final double lowAt;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final known = capacity > 0;
    // لا حدّ أعلى للنسبة نفسها (خزّانٌ تجاوز سعته المسجَّلة يظهر رقمه الحقيقي
    // ولو فوق 100٪)؛ الشريط وحده يُقيَّد بصريًّا في `value:` أدناه.
    final pct = known ? used / capacity * 100 : 0.0;
    final color = !known
        ? c.muted
        : (pct >= highAt ? c.warn : (pct <= lowAt ? c.danger : c.accent));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
        ),
        Text(known ? '${pct.round()}٪' : 'بلا سعة',
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: known ? (pct / 100).clamp(0.0, 1.0) : 0,
          minHeight: 8,
          backgroundColor: c.subtle,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        known ? '${nf(used)}${unit.isEmpty ? '' : ' $unit'} من ${nf(capacity)}' : '${nf(used)}${unit.isEmpty ? '' : ' $unit'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: c.muted),
      ),
    ]);
  }
}
