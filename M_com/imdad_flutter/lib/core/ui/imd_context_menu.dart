import 'package:flutter/material.dart';

import 'imd_icon.dart';
import 'imd_tokens.dart';

/// بندٌ في قائمة السياق (كليك يمين على سطح المكتب، وضغطةٌ مطوّلة على اللمس).
class ImdMenuItem {
  const ImdMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.shortcut,
  });

  final String label;
  final VoidCallback onTap;

  /// اسم أيقونة من [ImdIcon].
  final String? icon;

  /// بندٌ هدّام (حذف) — يُلوَّن بلون الخطر ويُفصل عمّا قبله.
  final bool danger;
  final bool enabled;

  /// نصٌّ يُعرض في طرف البند (مثل `Ctrl+S`) — للعلم فقط، لا يربط اختصارًا.
  final String? shortcut;
}

/// يفتح قائمة سياقٍ عند [position] (إحداثيات الشاشة) ويُنفّذ البند المختار.
///
/// القائمة بلا بنودٍ لا تُفتح. تُلوَّن من `context.imd` فتتبع السمة، وتأخذ
/// شكل قوائم ويندوز: صفوفٌ كثيفة، وفاصلٌ قبل البند الهدّام.
Future<void> showImdContextMenu(
  BuildContext context,
  Offset position,
  List<ImdMenuItem> items,
) async {
  if (items.isEmpty) return;
  final c = context.imd;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    color: c.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: c.line),
    ),
    items: [
      for (var i = 0; i < items.length; i++) ...[
        if (items[i].danger && i > 0 && !items[i - 1].danger) const PopupMenuDivider(height: 8),
        PopupMenuItem<int>(
          value: i,
          enabled: items[i].enabled,
          height: 36,
          child: _ItemRow(items[i]),
        ),
      ],
    ],
  );
  if (picked != null) items[picked].onTap();
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item);
  final ImdMenuItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final color = !item.enabled ? c.muted : (item.danger ? c.danger : c.text);
    return Row(children: [
      if (item.icon != null) ...[
        ImdIcon(item.icon!, size: 15, color: color),
        const SizedBox(width: 10),
      ],
      Expanded(child: Text(item.label, style: TextStyle(fontSize: 13, color: color))),
      if (item.shortcut != null) ...[
        const SizedBox(width: 24),
        Text(item.shortcut!, style: TextStyle(fontSize: 11.5, color: c.muted)),
      ],
    ]);
  }
}
