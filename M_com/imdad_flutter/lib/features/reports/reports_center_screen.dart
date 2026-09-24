import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/export/excel_export.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/reports_repo.dart';
import '../../data/repos/settings_repo.dart';

/// مركز التقارير — نقل `reports-center.js`: قائمة جانبية بتسعة تقارير،
/// فلاتر مخصصة لكل تقرير، ملخّص برقائق، جدول قابل للفرز بسطر إجمالي،
/// وبحث داخل النتائج مع الطباعة والتصدير إلى Excel.
class ReportsCenterScreen extends StatefulWidget {
  const ReportsCenterScreen({super.key});

  @override
  State<ReportsCenterScreen> createState() => _ReportsCenterScreenState();
}

class _ReportsCenterScreenState extends State<ReportsCenterScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final ReportsRepo _repo = ReportsRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();

  ReportData? _data;
  ReportResult _out = const ReportResult();
  int _idx = 0;

  /// حالة فلاتر كل تقرير على حدة (`RC.f`).
  final Map<ReportId, Map<String, String>> _filters = {};

  /// عمود الفرز واتجاهه.
  int? _sortCol;
  int _sortDir = 1;
  bool _loading = true;

  ReportInfo get _report => kReports[_idx];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _repo.load(scope: _perm.scope);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
    _run();
  }

  /// زر «تحديث البيانات».
  Future<void> _refresh() async {
    await _load();
    if (mounted) showImdToast(context, '✔ تم تحديث البيانات');
  }

  /// `fState()` — القيم الابتدائية لفلاتر التقرير الحالي.
  Map<String, String> _state() {
    final id = _report.id;
    final existing = _filters[id];
    if (existing != null) return existing;
    final s = <String, String>{};
    for (final x in ReportsRepo.filtersFor(id)) {
      switch (x.type) {
        case 'range':
          s['dateOn'] = x.defaultOn ? '1' : '';
          s['from'] = ReportsRepo.daysAgo(x.fromDaysAgo);
          s['to'] = ReportsRepo.today();
        case 'date':
          s[x.key] = ReportsRepo.today();
        default:
          final opts = x.options?.call(_data!, s) ?? const [];
          s[x.key] = opts.isEmpty ? '' : opts.first.$1;
      }
    }
    _filters[id] = s;
    return s;
  }

  /// `run()`
  void _run() {
    if (_data == null) return;
    setState(() => _out = _repo.run(_report.id, _data!, _state()));
  }

  /// نص المحددات المعروض بجوار العنوان (`RC.filterText`).
  String get _filterText {
    final f = _state();
    final parts = <String>[];
    if (_report.id == ReportId.daily) {
      parts.add('اليوم: ${f['day'] ?? ReportsRepo.today()}');
    }
    if (f['dateOn'] == '1' && (f['from'] ?? '').isNotEmpty) {
      parts.add('من ${f['from']} إلى ${f['to']}');
    }
    for (final x in ReportsRepo.filtersFor(_report.id)) {
      if (x.type != 'select') continue;
      final opts = x.options?.call(_data!, f) ?? const [];
      final v = f[x.key] ?? '';
      if (v.isEmpty) continue;
      final label = opts.where((o) => o.$1 == v).firstOrNull?.$2;
      if (label != null) parts.add('${x.label}: $label');
    }
    return parts.join(' · ');
  }

  /// `viewRows()` — بحث داخل النتائج ثم الفرز.
  List<List<ReportCell>> _rows() {
    final q = _q.text.trim().toLowerCase();
    var rows = _out.rows;
    if (q.isNotEmpty) {
      rows = rows.where((r) => r.any((c) => c.text.toLowerCase().contains(q))).toList();
    }
    final sc = _sortCol;
    if (sc != null && sc < _out.columns.length) {
      final numeric = _out.columns[sc].numeric;
      rows = [...rows]..sort((a, b) {
          final x = a[sc];
          final y = b[sc];
          final r = numeric
              ? (x.value ?? 0).compareTo(y.value ?? 0)
              : x.text.compareTo(y.text);
          return r * _sortDir;
        });
    }
    return rows;
  }

  bool _hasRows() {
    if (_out.message.isNotEmpty || _rows().isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات — اعرض التقرير أولًا', error: true);
      return false;
    }
    return true;
  }

  String get _title => _report.name + (_out.title.isEmpty ? '' : ' — ${_out.title}');

  List<String> get _headers => ['م', for (final c in _out.columns) c.title];

  List<List<String>> _exportRows() {
    var i = 0;
    return [
      for (final r in _rows()) [nf(++i), for (final c in r) c.text],
    ];
  }

  /// `doPrint()`
  Future<void> _print() async {
    if (!_hasRows()) return;
    final layout = await SettingsRepo(_db).printLayout();
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: _title,
        headers: _headers,
        rows: _exportRows(),
        leftValues: {'date': ReportsRepo.today()},
        fieldValues: {
          'notes': _filterText.isEmpty ? 'بدون فلاتر' : _filterText,
          'warehouse': _perm.scope == null ? '' : _perm.scope!.join('، '),
        },
      ),
      layout: layout,
    );
  }

  /// `doXlsx()`
  Future<void> _export() async {
    if (!_hasRows()) return;
    final bytes = ExcelExport.build(
      sheetName: _report.name,
      headers: _headers,
      rows: _exportRows(),
    );
    if (!mounted) return;
    final name = 'تقرير_${_report.name}_${ReportsRepo.today()}'.replaceAll(' ', '_');
    final path = await ImdFiles.saveBytes(context, '$name.xlsx', bytes);
    if (path != null && mounted) showImdToast(context, '✔ صُدِّر الملف');
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return ImdPage(children: [
      ImdPageTitle(
        title: 'مركز التقارير',
        icon: 'chart',
        subtitle: 'تقارير تفصيلية بفلاتر مخصصة لكل تقرير، مع الطباعة والتصدير إلى Excel',
        trailing: narrow
            ? null
            : ImdButton.outline(
                label: 'تحديث البيانات',
                icon: 'refresh',
                small: true,
                onPressed: _refresh,
              ),
      ),
      if (_loading)
        const ImdLd('جارٍ تحميل البيانات…')
      else if (narrow) ...[
        _nav(horizontal: true),
        const SizedBox(height: 12),
        _body(),
      ] else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 280, child: _nav(horizontal: false)),
          const SizedBox(width: 16),
          Expanded(child: _body()),
        ]),
    ]);
  }

  /// `.rc-nav`
  Widget _nav({required bool horizontal}) {
    final c = context.imd;
    final buttons = [
      for (final (i, r) in kReports.indexed) _navButton(i, r, horizontal: horizontal),
    ];
    return Container(
      padding: EdgeInsets.all(horizontal ? 6 : 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final b in buttons) Padding(padding: const EdgeInsets.only(left: 4), child: b),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons),
    );
  }

  Widget _navButton(int i, ReportInfo r, {required bool horizontal}) {
    final c = context.imd;
    final on = i == _idx;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _idx = i;
            _sortCol = null;
            _q.clear();
          });
          _run();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: on ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ImdIcon(r.icon, size: 16, color: c.accent),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: horizontal ? 200 : 210),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(r.name,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: on ? c.accentHover : c.text)),
                if (!horizontal)
                  Text(r.desc, style: TextStyle(fontSize: 11.5, color: c.muted, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    final rows = _rows();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ImdIcon(_report.icon, size: 18, color: context.imd.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_report.name,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.imd.text)),
            ),
            Flexible(
              child: Text(
                _filterText.isEmpty ? 'بدون فلاتر' : _filterText,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: context.imd.muted),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _filtersBar(),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ImdButton(label: 'عرض التقرير', icon: 'search', onPressed: _run),
            ImdButton.outline(label: 'طباعة', icon: 'printer', onPressed: _print),
            ImdButton.outline(label: 'تصدير Excel', icon: 'download', onPressed: _export),
            ImdButton.outline(
              label: 'إعادة تعيين',
              icon: 'eraser',
              small: true,
              onPressed: () {
                _filters.remove(_report.id);
                _q.clear();
                setState(() => _sortCol = null);
                _run();
              },
            ),
            SizedBox(
              width: 240,
              child: ImdFld(
                controller: _q,
                hint: 'بحث داخل النتائج…',
                dense: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ]),
      ),
      if (_out.summary.isNotEmpty)
        ImdChipsRow(children: [
          for (final (i, s) in _out.summary.indexed)
            ImdChip('${s.$1}: ${nf(s.$2)}', tone: i == 0 ? ImdTone.ok : ImdTone.code),
        ]),
      if (_out.note.isNotEmpty) ImdNote(_out.note, margin: const EdgeInsets.only(bottom: 10)),
      if (_out.message.isNotEmpty)
        ImdEmptyBox(_out.message)
      else
        ImdTable(
          minWidth: _out.columns.length > 7 ? 1000 : null,
          columns: [
            const ImdCol('م', numeric: true),
            for (final (i, c) in _out.columns.indexed)
              ImdCol(
                '${c.title}${_sortCol == i ? (_sortDir > 0 ? ' ▲' : ' ▼') : ''}',
                numeric: c.numeric,
              ),
          ],
          empty: 'لا توجد بيانات مطابقة للفلاتر الحالية',
          onHeaderTap: (i) {
            if (i == 0) return;
            setState(() {
              final col = i - 1;
              if (_sortCol == col) {
                _sortDir = -_sortDir;
              } else {
                _sortCol = col;
                _sortDir = 1;
              }
            });
          },
          footer: _totals(rows),
          rows: [
            for (final (i, r) in rows.take(2000).indexed)
              [
                Text(nf(i + 1)),
                for (final (ci, cell) in r.indexed)
                  if (_out.columns[ci].chip && cell.tone.isNotEmpty)
                    ImdChip(cell.text, tone: _tone(cell.tone))
                  else
                    Text(cell.text),
              ],
          ],
        ),
      if (rows.length > 2000)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'يُعرض أول ${nf(2000)} سطر من ${nf(rows.length)} — استخدم الفلاتر لتضييق النتائج',
            style: TextStyle(fontSize: 12, color: context.imd.muted),
          ),
        ),
    ]);
  }

  static ImdTone _tone(String t) => switch (t) {
        'ok' => ImdTone.ok,
        'pend' => ImdTone.pend,
        'err' => ImdTone.err,
        _ => ImdTone.code,
      };

  /// سطر الإجمالي للأعمدة المجمَّعة (`rc-sum`).
  List<Widget>? _totals(List<List<ReportCell>> rows) {
    if (rows.length < 2 || !_out.columns.any((c) => c.numeric && c.sum)) return null;
    return [
      const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final (i, c) in _out.columns.indexed)
        Text(
          c.numeric && c.sum
              ? nf(rows.fold<double>(0, (a, r) => a + (r[i].value ?? 0)))
              : '',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
    ];
  }

  /// `paintFilters()` — شبكة الفلاتر المتجاوبة.
  Widget _filtersBar() {
    final f = _state();
    final defs = ReportsRepo.filtersFor(_report.id);
    final fields = <Widget>[];

    for (final x in defs) {
      switch (x.type) {
        case 'range':
          fields.add(SizedBox(
            width: double.infinity,
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
              ImdCheckbox(
                value: f['dateOn'] == '1',
                label: 'تحديد فترة',
                onChanged: (v) {
                  f['dateOn'] = v ? '1' : '';
                  _run();
                },
              ),
              SizedBox(
                width: 170,
                child: ImdLabeled(
                  'من تاريخ',
                  ImdDateField(
                    value: f['from'] ?? '',
                    enabled: f['dateOn'] == '1',
                    onChanged: (v) {
                      f['from'] = v;
                      _run();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: ImdLabeled(
                  'إلى تاريخ',
                  ImdDateField(
                    value: f['to'] ?? '',
                    enabled: f['dateOn'] == '1',
                    onChanged: (v) {
                      f['to'] = v;
                      _run();
                    },
                  ),
                ),
              ),
            ]),
          ));
        case 'date':
          fields.add(SizedBox(
            width: 190,
            child: ImdLabeled(
              x.label,
              ImdDateField(
                value: f[x.key] ?? '',
                onChanged: (v) {
                  f[x.key] = v;
                  _run();
                },
              ),
            ),
          ));
        default:
          final opts = x.options?.call(_data!, f) ?? const [];
          if (!opts.any((o) => o.$1 == f[x.key])) f[x.key] = opts.isEmpty ? '' : opts.first.$1;
          fields.add(SizedBox(
            width: 220,
            child: ImdLabeled(
              x.label,
              ImdSelect<String>(
                items: opts,
                value: f[x.key],
                onChanged: (v) {
                  f[x.key] = v ?? '';
                  // تغيير الوحدة الرئيسية يعيد بناء قائمة الوحدات الفرعية.
                  if (x.key == 'parent') f['child'] = '';
                  _run();
                },
              ),
            ),
          ));
      }
    }
    return Wrap(spacing: 12, runSpacing: 10, children: fields);
  }
}
