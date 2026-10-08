part of '../imd_table.dart';

/// خلايا الجسم ورؤوس الأعمدة وأيقونة تصفية العمود.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableCells on _ImdTableBase, _ImdTableData, _ImdTableGroups {
  Widget _cell(ImdCol col, Widget child, {required int row, EdgeInsets? pad}) {
    // `row >= 0` = خليةُ جسمٍ؛ الرأس والإجماليات يبقيان بحشوتهما.
    final Widget w0 = (widget.flushCells && row >= 0)
        ? child
        : Padding(
            padding: pad ?? widget.cellPadding ?? EdgeInsets.symmetric(horizontal: 12, vertical: ImdDensity.cellPadV),
            child: Align(
              alignment: col.center ? Alignment.center : AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: child,
            ),
          );
    Widget w = w0;
    if (row >= 0) {
      w = MouseRegion(
        cursor: widget.onRowTap != null ? ImdCursor.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = row),
        onExit: (_) => setState(() => _hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
          onSecondaryTapDown: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          onLongPressStart: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          child: w,
        ),
      );
    }
    // «middle» لا «fill»: خلايا fill لا تُسهم في ارتفاع الصف فينهار الصف إذا كانت كلها كذلك.
    return TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: w);
  }

  Widget _header(BuildContext context, ImdCol col, int index) {
    final c = context.imd;
    final sorted = widget.sortIndex == index;
    final headerFg = widget.headerForeground;
    final label = ImdEmojiText(col.label,
        iconSize: 13,
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: sorted ? FontWeight.w700 : FontWeight.w600,
            color: headerFg ?? (sorted ? c.accent : c.muted),
            height: 1.3));
    // السهم على العمود المفروز وحده: لو وُضع على كل عمودٍ قابلٍ للفرز لاتّسعت
    // كل الأعمدة (عرضها ذاتيٌّ من محتواها) وضاق الجدول بلا طائل.
    final text = !sorted
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 4),
              ImdIcon(widget.sortAsc ? 'chevron-up' : 'chevron-down', size: 12, color: c.accent),
            ],
          );
    Widget head = _headerWithFilter(context, index, text);
    // رأس العمود يُسحب إلى لوحة التجميع (سطح المكتب).
    if (_tools && widget.groupable && widget.columns[index].label.isNotEmpty && !ImdBp.of(context).mobile) {
      head = Draggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4)),
            child: Text(widget.columns[index].label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onAccent)),
          ),
        ),
        child: head,
      );
    }
    if (widget.onHeaderTap == null) return head;
    final hovered = _headerHover == index;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _headerHover = index),
      onExit: (_) => setState(() => _headerHover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onHeaderTap!(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: hovered ? c.headerHover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: head,
        ),
      ),
    );
  }

  /// أيقونة تصفية العمود بجوار عنوانه — سطح المكتب فقط (على اللمس يُستعمل زر
  /// «تصفية» في شريط الأدوات: أيقونةٌ بحجم 12 لا تصلح هدفَ إصبع).
  Widget _headerWithFilter(BuildContext context, int index, Widget text) {
    if (!_tools || !widget.filterable || widget.columns[index].label.isEmpty || ImdBp.of(context).mobile) return text;
    final c = context.imd;
    final active = _filters.containsKey(index);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: text),
      const SizedBox(width: 4),
      Tooltip(
        message: 'تصفية العمود',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _editFilter(index),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ImdIcon('sliders', size: 11, color: active ? c.accent : c.faint),
          ),
        ),
      ),
    ]);
  }
}
