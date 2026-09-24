import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/export/excel_export.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';

/// الأرصدة الحالية — نقل `renderBalances()` / `balPaint()`:
/// كشف لحظي بأرصدة الأصناف (الافتتاحي + الوارد − المنصرف ± التحويلات) مع رقائق
/// الإحصاء وحالة كل صنف. أُضيف اختيار المستودع لأن الأرصدة هنا مفصولة بالمستودعات.
class BalancesScreen extends StatefulWidget {
  const BalancesScreen({super.key});

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);
  late final SettingsRepo _settings = SettingsRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();
  List<Item> _items = const [];
  List<Warehouse> _warehouses = const [];
  Map<String, double> _balances = const {};

  /// فارغ = إجمالي مستودعات النطاق.
  String _warehouse = '';
  bool _loading = true;

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

  /// `balLoad()`
  Future<void> _load() async {
    final scope = _perm.scope;
    final items = await _catalog.items();
    final whs = await _catalog.warehouses(scope: scope);
    final bal = await _moves.balances(
      warehouse: _warehouse.isEmpty ? null : _warehouse,
      scope: _warehouse.isEmpty ? scope : null,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _warehouses = whs;
      _balances = bal;
      _loading = false;
    });
  }

  double _bal(Item i) => _balances[i.id] ?? 0;

  List<Item> _rows() {
    final q = _q.text.trim().toLowerCase();
    return _items
        .where((x) =>
            q.isEmpty ||
            x.code.toLowerCase().contains(q) ||
            x.name.toLowerCase().contains(q) ||
            x.categoryName.toLowerCase().contains(q))
        .toList();
  }

  String get _scopeLabel {
    if (_warehouse.isNotEmpty) return _warehouse;
    final scope = _perm.scope;
    return scope == null ? 'كل المستودعات' : 'مستودعات نطاقك: ${scope.join('، ')}';
  }

  /// حالة الصنف كما في `balPaint()`.
  (String, ImdTone) _state(Item x) {
    final bal = _bal(x);
    if (bal <= 0) return ('فارغ ❌', ImdTone.off);
    if (x.minQty > 0 && bal <= x.minQty) return ('تحت الحد ⚠️', ImdTone.pend);
    return ('جيد ✅', ImdTone.ok);
  }

  static const _headers = ['م', 'الكود', 'الصنف', 'التصنيف', 'الرصيد الحالي', 'الوحدة', 'الحالة'];

  List<List<String>> _reportRows(List<Item> rows) {
    var i = 0;
    return [
      for (final x in rows)
        [
          nf(++i),
          x.code,
          x.name,
          x.categoryName.isEmpty ? '—' : x.categoryName,
          nf(displayBalance(x, _bal(x)).qty),
          displayBalance(x, _bal(x)).unit,
          _state(x).$1.replaceAll(RegExp(r'[❌⚠️✅]'), '').trim(),
        ],
    ];
  }

  /// `balPrintReport()`
  Future<void> _print() async {
    final rows = _rows();
    if (rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للطباعة', error: true);
      return;
    }
    final layout = await _settings.printLayout();
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'كشف الأرصدة الحالية',
        headers: _headers,
        columnFlex: const [1, 2, 6, 3, 3, 2, 2],
        rows: _reportRows(rows),
        leftValues: {'date': isoDay(DateTime.now())},
        fieldValues: {'warehouse': _scopeLabel, 'notes': 'عدد الأصناف: ${nf(rows.length)}'},
      ),
      layout: layout,
    );
  }

  Future<void> _export() async {
    final rows = _rows();
    if (rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للتصدير', error: true);
      return;
    }
    final bytes = ExcelExport.build(
      sheetName: 'الأرصدة',
      headers: _headers,
      rows: _reportRows(rows),
    );
    if (!mounted) return;
    final path = await ImdFiles.saveBytes(context, 'الأرصدة الحالية.xlsx', bytes);
    if (path != null && mounted) showImdToast(context, '✔ صُدِّر الملف');
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final low = _items.where((x) => x.minQty > 0 && _bal(x) <= x.minQty).length;
    final zero = _items.where((x) => _bal(x) <= 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الأرصدة الحالية',
        icon: 'calculator',
        subtitle: 'كشف لحظي بأرصدة جميع الأصناف '
            '(الرصيد = الافتتاحي + الوارد − المنصرف ± التحويلات)',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث بالكود أو الاسم أو التصنيف…',
            onChanged: (_) => setState(() {}),
            actions: [
              SizedBox(
                width: 220,
                child: ImdSelect<String>(
                  dense: true,
                  items: [
                    ('', _perm.scope == null ? 'الإجمالي (كل المستودعات)' : 'إجمالي مستودعات نطاقك'),
                    for (final w in _warehouses) (w.name, w.name),
                  ],
                  value: _warehouse,
                  onChanged: (v) async {
                    setState(() => _warehouse = v ?? '');
                    await _load();
                  },
                ),
              ),
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
              if (_perm.admin || _perm.has('balances', PermAction.export))
                ImdButton.outline(label: 'تصدير للإكسيل', icon: 'download', small: true, onPressed: _export),
              if (_perm.admin || _perm.has('balances', PermAction.print))
                ImdButton(
                  label: 'طباعة كشف الأرصدة',
                  icon: 'printer',
                  kind: ImdBtnKind.purple,
                  small: true,
                  onPressed: _print,
                ),
            ],
          ),
          const SizedBox(height: 4),
          ImdChipsRow(bottom: 0, children: [
            ImdChip('الأصناف: ${nf(_items.length)}', tone: ImdTone.ok),
            ImdChip('تحت الحد: ${nf(low)}', tone: ImdTone.pend),
            ImdChip('فارغة: ${nf(zero)}', tone: ImdTone.err),
          ]),
        ]),
      ),
      if (_loading)
        const ImdLd('⏳ جارٍ التحميل…')
      else
        ImdTable(
          columns: const [
            ImdCol('الكود'),
            ImdCol('الصنف'),
            ImdCol('التصنيف'),
            ImdCol('حد التنبيه', numeric: true),
            ImdCol('الرصيد الحالي', numeric: true),
            ImdCol('الوحدة'),
            ImdCol('الحالة'),
          ],
          empty: 'لا أصناف مطابقة',
          rows: [
            for (final x in rows)
              [
                Text(x.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(x.name),
                Text(x.categoryName.isEmpty ? '—' : x.categoryName),
                Text(x.minQty > 0 ? nf(displayBalance(x, x.minQty).qty) : '—'),
                // الكمية والوحدة يجب أن تُحوَّلا معًا وإلا صار السطر كاذبًا.
                Text(nf(displayBalance(x, _bal(x)).qty),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(displayBalance(x, _bal(x)).unit),
                ImdChip(_state(x).$1, tone: _state(x).$2),
              ],
          ],
        ),
    ]);
  }
}
