import 'package:flutter/material.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';

/// تبويبات كبسولية؛ النشط أسود.
class ImdPillTabs<T> extends StatelessWidget {
  const ImdPillTabs({super.key, required this.tabs, required this.value, required this.onChanged, this.wrap = true, this.gap = 8});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// false ⇒ صف واحد بفجوة 6 قابل للتمرير أفقيًا.
  final bool wrap;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = [for (final t in tabs) _PillTab(tab: t, on: t.value == value, onTap: () => onChanged(t.value))];
    if (!wrap) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 6), items[i]],
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(spacing: gap, runSpacing: gap, children: items),
    );
  }
}

class ImdTab<T> {
  const ImdTab(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final String? icon;
}

class _PillTab extends StatefulWidget {
  const _PillTab({required this.tab, required this.on, required this.onTap});
  final ImdTab tab;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_PillTab> createState() => _PillTabState();
}

class _PillTabState extends State<_PillTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = widget.on;
    final fg = on ? c.onText : c.text2;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: ImdSizes.barControl,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? c.text : (_hover ? c.hover : c.surface),
            border: Border.all(color: on ? c.text : c.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.tab.icon != null) ...[
                ImdIcon(widget.tab.icon!, size: 13 * 1.1, color: fg),
                const SizedBox(width: 6),
              ],
              Text(widget.tab.label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// مجموعة مقاطع بخلفية رمادية والنشط أبيض (مثل «وحدة مستفيدة / مطبخ / جهة»).
class ImdSegmented<T> extends StatelessWidget {
  const ImdSegmented({super.key, required this.tabs, required this.value, required this.onChanged});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // المقاطع الكثيرة تُمرَّر أفقيًّا في الشاشة الضيّقة بدل أن تفيض.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in tabs)
            GestureDetector(
              onTap: () => onChanged(t.value),
              child: MouseRegion(
                cursor: ImdCursor.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: t.value == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: t.value == value
                        ? [BoxShadow(color: c.shadowHairline, blurRadius: 3, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (t.icon != null) ...[
                      ImdIcon(t.icon!, size: 14, color: t.value == value ? c.text : c.text2),
                      const SizedBox(width: 6)
                    ],
                    Text(t.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: t.value == value ? c.text : c.text2)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    ),
      ),
    );
  }
}
