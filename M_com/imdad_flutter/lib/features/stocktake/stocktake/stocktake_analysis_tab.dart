part of '../stocktake_screen.dart';

/// تبويب تحليل الفروقات — يحتفظ بتعديلات السبب والقرار قبل حفظها.
class _AnalysisTab extends StatefulWidget {
  const _AnalysisTab({required this.state});
  final _StocktakeScreenState state;

  @override
  State<_AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<_AnalysisTab> {
  final _edits = <String, (String, String)>{};

  _StocktakeScreenState get s => widget.state;

  (String, String) _valueOf(StocktakeLine l) =>
      _edits[l.id] ?? (l.reason, l.decision.isEmpty ? 'ADJUST' : l.decision);

  @override
  Widget build(BuildContext context) {
    final o = s._order;
    final open = o?.status == 'COUNTING' && s._canWrite;
    final counted = s._lines.where((l) => l.countedQty != null).toList();
    final withVar = counted.where((l) => s._varOf(l) != 0).toList();
    final rows =
        s._lines.where((l) => !s._onlyVar || (l.countedQty != null && s._varOf(l) != 0)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
            s._orderPicker(onlyOpen: false),
            ImdButton.outline(label: 'تقرير الفروقات', icon: 'printer', onPressed: s._printVar),
            ImdCheckbox(
              value: s._onlyVar,
              label: 'الأصناف التي بها فروقات فقط',
              onChanged: (v) => s.setState(() => s._onlyVar = v),
            ),
          ]),
          const SizedBox(height: 10),
          ImdChipsRow(bottom: 0, children: [
            ImdChip('المعدود: ${nf(counted.length)} / ${nf(s._lines.length)}', tone: ImdTone.ok),
            ImdChip('بها فروقات: ${nf(withVar.length)}',
                tone: withVar.isEmpty ? ImdTone.ok : ImdTone.err),
            ImdChip('لم تُعد: ${nf(s._lines.length - counted.length)}', tone: ImdTone.pend),
            if (o != null) ImdChip(_statuses[o.status] ?? '', tone: _statusTone(o.status)),
          ]),
        ]),
      ),
      if (s._cur.isEmpty)
        const ImdEmptyState.noData(
          title: 'اختر أمر الجرد لعرض الفروقات',
          message: 'الفروقات تُحسب بمقارنة المعدود بالرصيد الدفتري، '
              'فاختر أمر الجرد من القائمة أعلاه لعرضها.',
        )
      else
        ImdTable(
          minWidth: 1100,
          columns: const [
            ImdCol('الصنف'),
            ImdCol('و١'),
            ImdCol('دفتري ١', numeric: true),
            ImdCol('فعلي ١', numeric: true),
            ImdCol('الفرق ١', numeric: true),
            ImdCol('و٢'),
            ImdCol('دفتري ٢', numeric: true),
            ImdCol('فعلي ٢', numeric: true),
            ImdCol('الفرق ٢', numeric: true),
            ImdCol('الفرق (أساس)', numeric: true),
            ImdCol('السبب', auto: false, width: 150),
            ImdCol('القرار', auto: false, width: 140),
          ],
          pageSize: 50,
          empty: 'لا توجد أصناف للعرض',
          rows: [for (final l in rows) _row(l, open)],
        ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton(
          label: 'حفظ الأسباب والقرارات',
          icon: 'save',
          onPressed: open && _edits.isNotEmpty
              ? () async {
                  await s._saveAnalysis(_edits);
                  if (mounted) setState(_edits.clear);
                }
              : null,
        ),
      ),
    ]);
  }

  List<Widget> _row(StocktakeLine l, bool open) {
    final c = context.imd;
    final units = s._unitsOf(l);
    final has = l.countedQty != null;
    final book = StocktakeRepo.split(l.systemQty, units);
    final actual = has ? StocktakeRepo.split(l.countedQty!, units) : const <String, double>{};
    final v = s._varOf(l);
    final (reason, decision) = _valueOf(l);

    Widget diff(double? d) => Text(
          d == null ? '—' : _sg(d),
          style: TextStyle(
            fontWeight: d != null && d != 0 ? FontWeight.w700 : FontWeight.w400,
            color: d == null || d == 0 ? c.text : (d > 0 ? c.success : c.danger),
          ),
        );

    final cells = <Widget>[
      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(l.itemCode, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(l.itemName),
        if (l.discovered) const ImdChip('مكتشف', tone: ImdTone.code),
      ]),
    ];
    for (var i = 0; i < 2; i++) {
      if (i >= units.length) {
        cells..add(const Text('—'))..add(const Text(''))..add(const Text(''))..add(const Text(''));
        continue;
      }
      final u = units[i];
      final b = book[u.name] ?? 0;
      final a = actual[u.name] ?? 0;
      cells
        ..add(Text(u.name))
        ..add(Text(nf(b)))
        ..add(Text(has ? nf(a) : '—'))
        ..add(diff(has ? ((a - b) * 1000).round() / 1000 : null));
    }
    cells
      ..add(v == null
          ? const ImdChip('لم يُعد', tone: ImdTone.pend)
          : Text('${_sg(v)} ${units.last.name}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: v == 0 ? c.text : (v > 0 ? c.success : c.danger))))
      ..add(ImdSelect<String>(
        dense: true,
        hint: '—',
        items: [for (final r in _reasons) (r, r.isEmpty ? '—' : r)],
        value: reason,
        onChanged: open ? (val) => setState(() => _edits[l.id] = (val ?? '', decision)) : null,
      ))
      ..add(ImdSelect<String>(
        dense: true,
        items: [for (final e in _decisions.entries) (e.key, e.value)],
        value: decision,
        onChanged: open ? (val) => setState(() => _edits[l.id] = (reason, val ?? 'ADJUST')) : null,
      ));
    return cells;
  }
}
