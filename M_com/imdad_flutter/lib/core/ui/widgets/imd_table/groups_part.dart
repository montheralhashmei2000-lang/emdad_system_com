part of '../imd_table.dart';

/// رؤوس المجموعات (صفًّا وبطاقةً)، وتلوين الزِّبرة، وقائمة سياق الصفّ.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableGroups on _ImdTableBase, _ImdTableData {
  /// صفّ رأس مجموعة. ارتفاعه ثابتٌ وعرض خليته الأولى صفر عمدًا: نصّه يمتدّ فوق
  /// الأعمدة المجاورة (فارغةٍ) من غير أن يوسّع العمود الأول بقياسه الذاتي.
  TableRow _groupRow(BuildContext context, _TableItem g) {
    final c = context.imd;
    final h = ImdDensity.isHigh ? 26.0 : 34.0;
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
      const SizedBox(width: 6),
      Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
      const SizedBox(width: 8),
      Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
    return TableRow(
      key: ValueKey('group:${g.key}'),
      decoration: BoxDecoration(color: c.subtle, border: Border(bottom: BorderSide(color: c.tableRowLine))),
      children: [
        for (var j = 0; j < widget.columns.length; j++)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: MouseRegion(
              cursor: ImdCursor.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleGroup(g.key!),
                child: SizedBox(
                  width: j == 0 ? 0 : null,
                  height: h,
                  child: j == 0
                      ? Stack(clipBehavior: Clip.none, children: [
                          PositionedDirectional(start: 12, top: 0, bottom: 0, child: Center(child: label)),
                        ])
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// رأس مجموعة في عرض البطاقات.
  Widget _groupCard(BuildContext context, _TableItem g) {
    final c = context.imd;
    return InkWell(
      onTap: () => _toggleGroup(g.key!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
          ),
          Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
      ),
    );
  }

  /// لونٌ محايد خفيف جدًّا فوق سطح الجدول — يعمل في كل سمة (فاتحة/داكنة/محروقات)
  /// لأنه مشتقٌّ من ألوان السمة الحالية لا لونًا ثابتًا.
  Color _zebraColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(scheme.onSurface.withValues(alpha: .035), scheme.surface);
  }

  void _openMenu(int row, Offset at) {
    final items = widget.rowMenu?.call(row) ?? const <ImdMenuItem>[];
    showImdContextMenu(context, at, items);
  }
}
