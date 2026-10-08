part of '../imd_table.dart';

/// شريط أدوات الجدول ولوحة التجميع.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableToolbar on _ImdTableBase, _ImdTableData {
  /// شريط أدوات الجدول: بحثٌ فوري، لوحة التجميع (إسقاط رأس عمود)، قائمتا التجميع
  /// والتصفية، وشارات الفلاتر الفعّالة. يظهر مع [ImdTable.values] وحدها.
  Widget _toolbar(BuildContext context, int shown) {
    final c = context.imd;
    final cols = widget.columns;
    final desktop = !ImdBp.of(context).mobile;
    final labelled = [
      for (var j = 0; j < cols.length; j++)
        if (cols[j].label.isNotEmpty) j,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
              child: TextField(
                controller: _find,
                onChanged: (v) => setState(() {
                  _findQ = v.trim();
                  _page = 0;
                }),
                style: TextStyle(fontSize: ImdDensity.cellFont, color: c.text),
                decoration: imdFieldDecoration(context, dense: true).copyWith(
                  hintText: 'بحث فوري…',
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
                    child: ImdIcon('search', size: 14, color: c.faint),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: _findQ.isEmpty
                      ? null
                      : InkWell(
                          onTap: () => setState(() {
                            _find.clear();
                            _findQ = '';
                          }),
                          child: Padding(padding: const EdgeInsets.all(10), child: ImdIcon('x', size: 12, color: c.muted)),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
            if (widget.groupable && !desktop)
              ImdMenuButton<int>(
                label: _groupBy == null ? 'تجميع حسب' : 'مجمَّع: ${cols[_groupBy!].label}',
                icon: 'folder',
                small: true,
                items: (_) => [
                  if (_groupBy != null) const PopupMenuItem<int>(value: -1, child: Text('إلغاء التجميع')),
                  for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label)),
                ],
                onSelected: (j) => _setGroup(j < 0 ? null : j),
              ),
            if (widget.filterable && !desktop)
              ImdMenuButton<int>(
                label: 'تصفية',
                icon: 'sliders',
                small: true,
                items: (_) => [for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label))],
                onSelected: _editFilter,
              ),
            // الفلاتر الفعّالة برتقاليةٌ: لونٌ يلفت إلى أن ما يُرى ليس كل البيانات.
            for (final e in _filters.entries)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _editFilter(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        '${cols[e.key].label}: ${e.value.length == 1 ? _shown(e.value.first) : '${e.value.length} قيم'}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.warn)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _filters.remove(e.key);
                        _page = 0;
                      }),
                      child: ImdIcon('x', size: 11, color: c.warn),
                    ),
                  ]),
                ),
              ),
            if (_filters.isNotEmpty)
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.muted),
                child: const Text('مسح الفلاتر', style: TextStyle(fontSize: 12)),
              ),
            if (_filters.isNotEmpty || _findQ.isNotEmpty)
              Text('${nf(shown)} من ${nf(widget.rows.length)}', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        if (widget.groupable && desktop) ...[
          const SizedBox(height: 6),
          _groupPanel(context),
        ],
      ]),
    );
  }

  void _setGroup(int? col) => setState(() {
        _groupBy = col;
        _collapsed.clear();
        _page = 0;
      });

  /// لوحة التجميع: يُسقَط عليها رأس عمودٍ لتجميع الجدول به، وتعرض العمود الحالي.
  Widget _groupPanel(BuildContext context) {
    final c = context.imd;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => widget.columns[d.data].label.isNotEmpty,
      onAcceptWithDetails: (d) => _setGroup(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hot ? c.accentSoft : c.subtle,
            border: Border.all(color: hot ? c.accent : c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            ImdIcon('folder', size: 13, color: c.muted),
            const SizedBox(width: 8),
            if (_groupBy == null)
              Text('اسحب رأس العمود هنا للتجميع', style: TextStyle(fontSize: 12, color: c.muted))
            else
              InkWell(
                onTap: () => _setGroup(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.columns[_groupBy!].label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text2)),
                    const SizedBox(width: 6),
                    ImdIcon('x', size: 11, color: c.muted),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
