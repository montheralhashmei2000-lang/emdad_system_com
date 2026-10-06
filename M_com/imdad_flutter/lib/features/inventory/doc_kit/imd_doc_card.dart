import 'package:flutter/material.dart';
import '../../../core/ui/imd_format.dart';
import '../../../core/ui/imd_icon.dart';
import '../../../core/ui/imd_layout.dart';
import '../../../core/ui/imd_tokens.dart';


/// بطاقة مستند (مسودة/أمر/سند) برأسٍ يحمل رقمه وحالته.
class ImdDocCard extends StatelessWidget {
  const ImdDocCard({super.key, required this.head, this.body, this.actions});
  final List<Widget> head;
  final Widget? body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: head),
        if (body != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: body),
        if (actions != null && actions!.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ImdRbar(bottom: 0, children: actions!)),
      ]),
    );
  }
}


/// مستودع بأيقونة صغيرة في رأس البطاقة (`<span style="color:var(--mut);font-size:12px">🏬 …</span>`).
class ImdDocWarehouse extends StatelessWidget {
  const ImdDocWarehouse(this.name, {super.key, this.icon = 'warehouse'});
  final String name;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ImdIcon(icon, size: 13, color: c.muted),
      const SizedBox(width: 4),
      Text(name, style: TextStyle(color: c.muted, fontSize: 12)),
    ]);
  }
}


/// نص أصناف المستند: «اسم <b>كمية</b> وحدة · …».
class ImdDocLines extends StatelessWidget {
  const ImdDocLines(this.lines,
      {super.key, this.qtyColor, this.negative = false});
  final List<(String name, double qty, String unit)> lines;
  final Color? qtyColor;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const TextSpan(text: ' · '),
          TextSpan(text: '${lines[i].$1} '),
          TextSpan(
            text: '${negative ? '-' : ''}${nf(lines[i].$2)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: qtyColor),
          ),
          TextSpan(text: ' ${lines[i].$3}'),
        ],
      ]),
      style: TextStyle(fontSize: 13, height: 1.9, color: c.text),
    );
  }
}


/// الوقت الحالي بتاريخ اليوم المحلي (`todayISO()`).
String imdToday() => isoDay(DateTime.now());


/// `isFutureDate(v)`
bool imdIsFuture(String v) => v.isNotEmpty && v.compareTo(imdToday()) > 0;


/// `duplicateCountBy(rows, keyFn)`
int imdDuplicateCount<T>(List<T> rows, String Function(T) key) {
  final m = <String, int>{};
  for (final r in rows) {
    final k = key(r);
    if (k.isEmpty) continue;
    m[k] = (m[k] ?? 0) + 1;
  }
  return m.values.where((v) => v > 1).length;
}
