import 'package:flutter/material.dart';
import '../../../core/ui/imd_icon.dart';
import '../../../core/ui/imd_tokens.dart';


/// سندٌ معلّقٌ داخل الجلسة الحالية: لقطة بيانات [T] بانتظار العودة إليها.
/// (لا يُحفظ فعليًا؛ يضيع بإغلاق الشاشة أو البرنامج.)
class ImdDocTab<T> {
  ImdDocTab({required this.id, required this.label, required this.snapshot});
  final int id;
  final String label;
  final T snapshot;
}


/// شريط تبويبات السندات المفتوحة/المعلّقة داخل الجلسة — يظهر فقط عند وجود
/// أكثر من سندٍ واحد؛ كل تبويبٍ معلّق له زرّ إغلاقٍ لتجاهله.
class ImdDocTabsBar<T> extends StatelessWidget {
  const ImdDocTabsBar({
    super.key,
    required this.activeLabel,
    required this.suspended,
    required this.onSelect,
    required this.onClose,
  });
  final String activeLabel;
  final List<ImdDocTab<T>> suspended;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    if (suspended.isEmpty) return const SizedBox.shrink();
    final c = context.imd;
    Widget chip({required bool active, required String label, VoidCallback? onTap, VoidCallback? onClose}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          margin: const EdgeInsetsDirectional.only(start: 6),
          height: ImdSizes.compactField,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? c.accentSoft : c.surface,
            border: Border.all(color: active ? c.accent : c.faint),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ImdIcon('file', size: 12, color: active ? c.accent : c.muted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: active ? c.accent : c.text2)),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(onTap: onClose, child: ImdIcon('x', size: 11, color: c.muted)),
            ],
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(active: true, label: activeLabel),
          for (final t in suspended)
            chip(active: false, label: t.label, onTap: () => onSelect(t.id), onClose: () => onClose(t.id)),
        ]),
      ),
    );
  }
}
