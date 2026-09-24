import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/stocktake_repo.dart';
import '../../domain/access_control.dart';
import '../inventory/doc_kit.dart';

/// إدارة الجرد المخزني — نقل `stocktake-center.js` بتبويباته الخمسة:
/// إنشاء أمر جرد · العد الفعلي · تحليل الفروقات · التسوية والاعتماد · سجل الجرد.
/// العد يُدخل بالوحدات (حتى ثلاث) ويُحوَّل لوحدة الأساس، والفرق يُسوَّى في رصيد
/// المستودع عند الاعتماد، وتجميد المستودع يمنع الحركات حتى الإغلاق أو الإلغاء.
class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

const _types = <String, String>{
  'FULL': 'جرد كامل',
  'PARTIAL': 'جرد جزئي (تصنيف)',
  'SURPRISE': 'جرد مفاجئ',
  'CYCLE': 'جرد دوري',
};

const _statuses = <String, String>{
  'COUNTING': 'قيد التنفيذ',
  'CLOSED': 'معتمد ومغلق',
  'CANCELLED': 'ملغى',
};

ImdTone _statusTone(String s) => switch (s) {
      'COUNTING' => ImdTone.pend,
      'CLOSED' => ImdTone.ok,
      'CANCELLED' => ImdTone.off,
      _ => ImdTone.code,
    };

const _reasons = <String>[
  '',
  'تلف',
  'فقد / عجز',
  'خطأ في الإدخال',
  'حركة غير مسجلة',
  'خطأ في وحدة القياس',
  'زيادة غير مبررة',
  'أخرى',
];

const _decisions = <String, String>{
  'ADJUST': 'تسوية الرصيد',
  'IGNORE': 'تجاهل الفرق',
  'RECOUNT': 'إعادة العد',
};

/// الفرق بإشارته كما في `SG()`.
String _sg(double n) {
  final v = (n * 1000).round() / 1000;
  return '${v > 0 ? '+' : (v < 0 ? '-' : '')}${nf(v.abs())}';
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final StocktakeRepo _repo = StocktakeRepo(_db);
  late final Perm _perm = Perm.of(context);

  // إنشاء الأمر
  final _committee = TextEditingController();
  final _notes = TextEditingController();
  String _date = imdToday();
  String _warehouse = '';
  String _type = 'FULL';
  String _categoryId = '';
  bool _freeze = true;

  // العد والتحليل والسجل
  final _q = TextEditingController();
  final _histQ = TextEditingController();
  final Map<String, Map<String, TextEditingController>> _counts = {};
  String _addItemId = '';
  bool _onlyVar = false;

  String _tab = 'create';
  String _cur = '';
  List<Warehouse> _warehouses = const [];
  List<Category> _categories = const [];
  List<Item> _items = const [];
  List<Stocktake> _orders = const [];
  List<StocktakeLine> _lines = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _committee.dispose();
    _notes.dispose();
    _q.dispose();
    _histQ.dispose();
    for (final m in _counts.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  bool get _canWrite => _perm.admin || _perm.manage('stocktake');

  /// `loadBase()`
  Future<void> _load() async {
    final scope = _perm.scope;
    final whs = await _catalog.warehouses(scope: scope);
    final cats = await _catalog.categories();
    final items = await _catalog.items();
    final orders = await _repo.sessions();
    if (!mounted) return;
    setState(() {
      _warehouses = whs;
      _categories = cats;
      _items = items;
      _orders = orders;
      if (_warehouse.isEmpty && whs.isNotEmpty) _warehouse = whs.first.name;
      if (_cur.isNotEmpty && !orders.any((o) => o.id == _cur)) _cur = '';
      _loading = false;
    });
  }

  /// `loadLines(id)`
  Future<void> _loadLines() async {
    if (_cur.isEmpty) {
      setState(() => _lines = const []);
      return;
    }
    final rows = await _repo.lines(_cur);
    rows.sort((a, b) => a.itemCode.compareTo(b.itemCode));
    if (!mounted) return;
    for (final m in _counts.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _counts.clear();
    for (final l in rows) {
      final saved = StocktakeRepo.countsOf(l);
      // سطر عُدَّ قبل تفصيل الوحدات: تُفكَّك كميته على الوحدات للعرض.
      final shown = saved.isEmpty && l.countedQty != null
          ? StocktakeRepo.split(l.countedQty!, _unitsOf(l))
          : saved;
      _counts[l.id] = {
        for (final u in _unitsOf(l))
          u.name: TextEditingController(
              text: shown[u.name] == null ? '' : _plain(shown[u.name]!)),
      };
    }
    setState(() => _lines = rows);
  }

  Stocktake? get _order {
    for (final o in _orders) {
      if (o.id == _cur) return o;
    }
    return null;
  }

  List<Stocktake> get _openOrders => _orders.where((o) => o.status == 'COUNTING').toList();

  Item? _itemById(String id) {
    for (final it in _items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// `unitsOf(it)` — وحدات الصنف من الأكبر إلى الأصغر، ثلاث كحد أقصى.
  List<ItemUnit> _unitsOf(StocktakeLine l) {
    final it = _itemById(l.itemId);
    final units = it == null
        ? [ItemUnit(name: l.unitName.isEmpty ? 'وحدة' : l.unitName, factor: 1)]
        : _catalog.unitsDescending(it);
    return units.take(3).toList();
  }

  String _orderLabel(Stocktake o) =>
      '${o.orderNo.isEmpty ? '#${o.id.substring(0, 6)}' : o.orderNo} — '
      '${o.warehouse.isEmpty ? 'بدون مستودع' : o.warehouse} — ${o.date}'
      '${o.status != 'COUNTING' ? ' (${_statuses[o.status]})' : ''}';

  double? _varOf(StocktakeLine l) =>
      l.countedQty == null ? null : ((l.countedQty! - l.systemQty) * 1000).round() / 1000;

  static String _plain(double v) {
    final r = (v * 1000).round() / 1000;
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }

  // ───────── 1) إنشاء أمر جرد ─────────
  /// `createOrder()`
  Future<void> _create() async {
    if (!_perm.guard(context, 'stocktake', PermAction.create)) return;
    if (_warehouse.isEmpty) {
      showImdToast(context, '✖ اختر المستودع', error: true);
      return;
    }
    if (_type == 'PARTIAL' && _categoryId.isEmpty) {
      showImdToast(context, '✖ اختر التصنيف للجرد الجزئي', error: true);
      return;
    }
    final dup = await _repo.openOrderOf(_warehouse);
    if (dup != null) {
      if (mounted) {
        showImdToast(context, '✖ يوجد أمر جرد مفتوح لهذا المستودع: ${dup.orderNo}', error: true);
      }
      return;
    }
    final catName = _categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? '';
    setState(() => _busy = true);
    final id = await _repo.createOrder(
      warehouse: _warehouse,
      date: _date,
      type: _type,
      categoryId: _categoryId,
      categoryName: catName,
      committee: _committee.text.trim(),
      freeze: _freeze,
      notes: _notes.text.trim(),
      createdBy: _perm.email,
    );
    await _load();
    if (!mounted) return;
    final created = _orders.where((o) => o.id == id).firstOrNull;
    setState(() {
      _busy = false;
      _cur = id;
      _tab = 'count';
    });
    await _loadLines();
    if (mounted) {
      showImdToast(context,
          '✔ أُنشئ أمر الجرد ${created?.orderNo ?? ''} — ${nf(created?.itemsCount ?? 0)} صنف');
    }
  }

  // ───────── 2) العد الفعلي ─────────
  /// `saveCount()`
  Future<void> _saveCount() async {
    if (_cur.isEmpty) {
      showImdToast(context, '✖ اختر أمر الجرد', error: true);
      return;
    }
    if (!_perm.guard(context, 'stocktake', PermAction.edit)) return;
    var n = 0;
    for (final l in _lines) {
      final units = _unitsOf(l);
      final entered = <String, double>{};
      for (final u in units) {
        final t = _counts[l.id]?[u.name]?.text.trim() ?? '';
        if (t.isEmpty) continue;
        entered[u.name] = double.tryParse(t) ?? 0;
      }
      final before = StocktakeRepo.countsOf(l);
      if (entered.isEmpty && l.countedQty == null) continue;
      if (entered.toString() == before.toString()) continue;
      await _repo.saveCount(
        lineId: l.id,
        countsByUnit: entered,
        factors: {for (final u in units) u.name: u.factor},
      );
      n++;
    }
    if (!mounted) return;
    if (n == 0) {
      showImdToast(context, 'لا توجد تغييرات للحفظ');
      return;
    }
    showImdToast(context, '✔ حُفظ العد الفعلي (${nf(n)} صنف)');
    await _loadLines();
  }

  /// `addItem()` — إضافة صنف مكتشف غير مدرج في الأمر.
  Future<void> _addItem() async {
    if (_cur.isEmpty) {
      showImdToast(context, '✖ اختر أمر الجرد أولًا', error: true);
      return;
    }
    if (!_perm.guard(context, 'stocktake', PermAction.edit)) return;
    final it = _itemById(_addItemId);
    if (it == null) {
      showImdToast(context, '✖ اختر الصنف', error: true);
      return;
    }
    await _repo.addDiscoveredItem(
      sessionId: _cur,
      item: it,
      warehouse: _order?.warehouse ?? '',
    );
    await _load();
    await _loadLines();
    if (mounted) {
      setState(() => _addItemId = '');
      showImdToast(context, '✔ أُضيف الصنف «${it.name}» إلى الجرد');
    }
  }

  /// `printBlank()` — استمارة عد فارغة.
  Future<void> _printBlank() async {
    final o = _order;
    if (o == null) {
      showImdToast(context, '✖ اختر أمر الجرد أولًا', error: true);
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    var i = 0;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'استمارة جرد فعلي',
        headers: const ['م', 'الكود', 'الصنف', 'الوحدات', 'الفعلي 1', 'الفعلي 2', 'الفعلي 3'],
        columnFlex: const [1, 2, 6, 3, 2, 2, 2],
        rows: [
          for (final l in _lines)
            [nf(++i), l.itemCode, l.itemName, _unitsOf(l).map((u) => u.name).join(' / '), '', '', ''],
        ],
        leftValues: {'date': o.date, 'refNo': o.orderNo, 'entryNo': o.orderNo},
        fieldValues: {
          'warehouse': o.warehouse,
          'party': o.committee,
          'notes': _types[o.type] ?? o.type,
        },
      ),
      layout: layout,
    );
  }

  // ───────── 3) تحليل الفروقات ─────────
  /// `saveAnalysis()`
  Future<void> _saveAnalysis(Map<String, (String reason, String decision)> edits) async {
    if (_cur.isEmpty) return;
    if (!_perm.guard(context, 'stocktake', PermAction.edit)) return;
    var n = 0;
    for (final l in _lines) {
      final e = edits[l.id];
      if (e == null) continue;
      if (e.$1 == l.reason && e.$2 == l.decision) continue;
      await _repo.setDecision(lineId: l.id, decision: e.$2, reason: e.$1);
      n++;
    }
    if (!mounted) return;
    if (n == 0) {
      showImdToast(context, 'لا توجد تغييرات للحفظ');
      return;
    }
    showImdToast(context, '✔ حُفظت الأسباب والقرارات (${nf(n)})');
    await _loadLines();
  }

  /// `printVar()` — تقرير الفروقات.
  Future<void> _printVar() async {
    final o = _order;
    if (o == null) {
      showImdToast(context, '✖ اختر أمر الجرد أولًا', error: true);
      return;
    }
    final rows = _lines.where((l) => l.countedQty != null && _varOf(l) != 0).toList();
    if (rows.isEmpty) {
      showImdToast(context, 'لا توجد فروقات في هذا الأمر');
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    var i = 0;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'تقرير فروقات الجرد',
        headers: const ['م', 'الكود', 'الصنف', 'الدفتري', 'الفعلي', 'الفرق', 'السبب', 'القرار'],
        columnFlex: const [1, 2, 5, 3, 3, 2, 3, 3],
        rows: [
          for (final l in rows)
            [
              nf(++i),
              l.itemCode,
              l.itemName,
              '${nf(l.systemQty)} ${l.unitName}',
              '${nf(l.countedQty ?? 0)} ${l.unitName}',
              _sg(_varOf(l) ?? 0),
              l.reason.isEmpty ? '—' : l.reason,
              _decisions[l.decision] ?? l.decision,
            ],
        ],
        leftValues: {'date': o.date, 'refNo': o.orderNo, 'entryNo': o.orderNo},
        fieldValues: {
          'warehouse': o.warehouse,
          'party': o.committee,
          'notes': '${_types[o.type] ?? o.type} — ${_statuses[o.status] ?? o.status}',
        },
      ),
      layout: layout,
    );
  }

  // ───────── 4) التسوية والاعتماد ─────────
  /// `approve()`
  Future<void> _approve() async {
    final o = _order;
    if (o == null) return;
    if (!_perm.guard(context, 'stocktake', PermAction.approve)) return;
    final counted = _lines.where((l) => l.countedQty != null).toList();
    final adjust =
        counted.where((l) => _varOf(l) != 0 && (l.decision.isEmpty ? 'ADJUST' : l.decision) == 'ADJUST');
    if (counted.any((l) => _varOf(l) != 0 && l.decision == 'RECOUNT')) {
      showImdToast(context, '✖ توجد أصناف بقرار إعادة العد', error: true);
      return;
    }
    final ok = await imdConfirm(
      context,
      'اعتماد التسوية سيعدّل أرصدة ${nf(adjust.length)} صنف ويغلق أمر الجرد ${o.orderNo}. متابعة؟',
      ok: 'اعتماد',
    );
    if (!ok) return;
    await _repo.approve(sessionId: _cur, approvedBy: _perm.email);
    await _load();
    await _loadLines();
    if (mounted) {
      setState(() => _tab = 'history');
      showImdToast(context, '✔ اعتُمدت التسوية وأُغلق أمر الجرد');
    }
  }

  /// `cancelOrder()`
  Future<void> _cancel() async {
    final o = _order;
    if (o == null) return;
    if (!_perm.guard(context, 'stocktake', PermAction.delete)) return;
    final why = await imdPrompt(context, 'سبب إلغاء أمر الجرد ${o.orderNo}:', ok: 'إلغاء الأمر');
    if (why == null) return;
    await _repo.cancelOrder(sessionId: _cur, reason: why.trim(), cancelledBy: _perm.email);
    await _load();
    if (mounted) {
      setState(() {
        _cur = '';
        _tab = 'history';
      });
      showImdToast(context, '✔ أُلغي أمر الجرد ورُفع تجميد المستودع');
    }
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'إدارة الجرد المخزني',
        icon: 'clipboard',
        subtitle: 'أوامر الجرد، العد الفعلي بالوحدات، تحليل الفروقات، واعتماد التسوية',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) async {
          setState(() => _tab = v);
          if (v != 'create' && v != 'history') await _loadLines();
        },
        tabs: const [
          ImdTab('create', 'إنشاء أمر جرد', icon: 'plus-square'),
          ImdTab('count', 'العد الفعلي', icon: 'clipboard'),
          ImdTab('analysis', 'تحليل الفروقات', icon: 'scale'),
          ImdTab('approve', 'التسوية والاعتماد', icon: 'check-circle'),
          ImdTab('history', 'سجل الجرد', icon: 'clock'),
        ],
      ),
      const SizedBox(height: 12),
      if (_loading)
        const ImdLd('جارٍ التحميل…')
      else
        switch (_tab) {
          'count' => _countTab(),
          'analysis' => _AnalysisTab(state: this),
          'approve' => _approveTab(),
          'history' => _historyTab(),
          _ => _createTab(),
        },
    ]);
  }

  /// منتقي أمر الجرد أعلى التبويبات (`orderPicker`).
  Widget _orderPicker({required bool onlyOpen}) {
    final list = onlyOpen ? _openOrders : _orders;
    return SizedBox(
      width: 340,
      child: ImdLabeled(
        'أمر الجرد:',
        ImdSelect<String>(
          hint: '— اختر أمر الجرد —',
          items: [for (final o in list) (o.id, _orderLabel(o))],
          value: list.any((o) => o.id == _cur) ? _cur : '',
          onChanged: (v) async {
            setState(() => _cur = v ?? '');
            await _loadLines();
          },
        ),
        size: 11,
      ),
    );
  }

  Widget _createTab() {
    final w = _canWrite;
    return ImdGrid(columns: 2, minItemWidth: 340, children: [
      ImdPanel(
        title: 'أمر جرد جديد',
        icon: 'plus-square',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!w) const ImdNote('عرض فقط — إنشاء أوامر الجرد يتطلب صلاحية.'),
          ImdLabeled(
            'المستودع:',
            ImdSelect<String>(
              items: [
                for (final x in _warehouses) (x.name, x.code.isEmpty ? x.name : '${x.code} — ${x.name}')
              ],
              value: _warehouse,
              onChanged: w ? (v) => setState(() => _warehouse = v ?? '') : null,
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled(
            'نوع الجرد:',
            ImdSelect<String>(
              items: [for (final e in _types.entries) (e.key, e.value)],
              value: _type,
              onChanged: w
                  ? (v) => setState(() {
                        _type = v ?? 'FULL';
                        if (_type != 'PARTIAL') _categoryId = '';
                      })
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled(
            'التصنيف (للجرد الجزئي):',
            ImdSelect<String>(
              hint: 'كل التصنيفات',
              items: [for (final c in _categories) (c.id, c.name)],
              value: _categoryId,
              onChanged: w && _type == 'PARTIAL' ? (v) => setState(() => _categoryId = v ?? '') : null,
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled('تاريخ البدء:', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v), enabled: w)),
          const SizedBox(height: 10),
          ImdLabeled(
            'أعضاء اللجنة:',
            ImdFld(
              controller: _committee,
              enabled: w,
              hint: 'أسماء أعضاء اللجنة (مفصولين بفاصلة)',
            ),
          ),
          const SizedBox(height: 10),
          ImdCheckbox(
            value: _freeze,
            label: 'تجميد المستودع (منع الحركات حتى الاعتماد)',
            onChanged: w ? (v) => setState(() => _freeze = v) : null,
          ),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات:', ImdFld(controller: _notes, enabled: w)),
          const SizedBox(height: 14),
          ImdButton(
            label: 'إنشاء أمر الجرد وسحب الأرصدة الدفترية',
            icon: 'check-circle',
            expand: true,
            busy: _busy,
            onPressed: w && !_busy ? _create : null,
          ),
        ]),
      ),
      ImdPanel(
        title: 'أوامر الجرد قيد التنفيذ',
        icon: 'hourglass',
        child: ImdTable(
          columns: const [
            ImdCol('رقم الأمر'),
            ImdCol('المستودع'),
            ImdCol('النوع'),
            ImdCol('التاريخ'),
            ImdCol('تجميد'),
          ],
          empty: 'لا توجد أوامر جرد مفتوحة',
          onRowTap: (i) async {
            setState(() {
              _cur = _openOrders[i].id;
              _tab = 'count';
            });
            await _loadLines();
          },
          rows: [
            for (final o in _openOrders)
              [
                Text(o.orderNo.isEmpty ? '—' : o.orderNo,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(o.warehouse.isEmpty ? '—' : o.warehouse),
                Text(_types[o.type] ?? o.type),
                Text(o.date),
                o.freeze ? const ImdChip('مجمّد', tone: ImdTone.pend) : const Text('—'),
              ],
          ],
        ),
      ),
    ]);
  }

  Widget _countTab() {
    final o = _order;
    final open = o?.status == 'COUNTING' && _canWrite;
    final q = _q.text.trim().toLowerCase();
    final rows = _lines
        .where((l) =>
            q.isEmpty ||
            l.itemCode.toLowerCase().contains(q) ||
            l.itemName.toLowerCase().contains(q))
        .toList();
    final done = _lines.where((l) => l.countedQty != null).length;
    final inList = {for (final l in _lines) l.itemId};

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
            _orderPicker(onlyOpen: true),
            ImdButton.outline(label: 'طباعة استمارة الجرد (فارغة)', icon: 'printer', onPressed: _printBlank),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(
              width: 340,
              child: ImdLabeled(
                'إضافة صنف مكتشف:',
                ImdSelect<String>(
                  hint: '— اختر صنفًا غير مدرج —',
                  items: [
                    for (final it in _items.where((x) => !inList.contains(x.id)))
                      (it.id, it.code.isEmpty ? it.name : '${it.code} — ${it.name}')
                  ],
                  value: _addItemId,
                  onChanged: open ? (v) => setState(() => _addItemId = v ?? '') : null,
                ),
                size: 11,
              ),
            ),
            ImdButton(
              label: 'إضافة للجرد',
              icon: 'plus',
              kind: ImdBtnKind.warn,
              onPressed: open ? _addItem : null,
            ),
          ]),
          const SizedBox(height: 10),
          ImdLabeled(
            'بحث في الجدول:',
            ImdFld(
              controller: _q,
              hint: 'ابحث برقم أو اسم الصنف…',
              onChanged: (_) => setState(() {}),
            ),
            size: 11,
          ),
        ]),
      ),
      if (_cur.isEmpty)
        const ImdEmptyBox('اختر أمر جرد مفتوحًا لبدء العد')
      else
        ImdTable(
          minWidth: 900,
          columns: const [
            ImdCol('الكود'),
            ImdCol('الصنف'),
            ImdCol('الوحدة 1'),
            ImdCol('الفعلي 1', auto: false, width: 110),
            ImdCol('الوحدة 2'),
            ImdCol('الفعلي 2', auto: false, width: 110),
            ImdCol('الوحدة 3'),
            ImdCol('الفعلي 3', auto: false, width: 110),
          ],
          empty: _lines.isEmpty ? 'لا توجد أصناف في هذا الأمر' : 'لا نتائج مطابقة للبحث',
          rows: [for (final l in rows) _countRow(l, open)],
        ),
      const SizedBox(height: 12),
      Row(children: [
        ImdButton(
          label: 'حفظ العد الفعلي',
          icon: 'save',
          onPressed: open ? _saveCount : null,
        ),
        const SizedBox(width: 10),
        Text('تم عدّ ${nf(done)} من ${nf(_lines.length)} صنف',
            style: TextStyle(fontSize: 12, color: context.imd.muted)),
      ]),
    ]);
  }

  List<Widget> _countRow(StocktakeLine l, bool open) {
    final units = _unitsOf(l);
    final cells = <Widget>[
      Text(l.itemCode.isEmpty ? '—' : l.itemCode, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(l.itemName),
    ];
    for (var i = 0; i < 3; i++) {
      if (i >= units.length) {
        cells..add(const Text('—'))..add(const SizedBox.shrink());
        continue;
      }
      final u = units[i];
      cells.add(Text(u.factor == 1 ? u.name : '${u.name} ×${nf(u.factor)}'));
      cells.add(ImdFld(
        controller: _counts[l.id]![u.name]!,
        number: true,
        dense: true,
        enabled: open,
      ));
    }
    return cells;
  }

  Widget _approveTab() {
    final o = _order;
    final counted = _lines.where((l) => l.countedQty != null).toList();
    final withVar = counted.where((l) => _varOf(l) != 0).toList();
    final recount = withVar.where((l) => l.decision == 'RECOUNT').toList();
    final adjust = withVar.where((l) => (l.decision.isEmpty ? 'ADJUST' : l.decision) == 'ADJUST').toList();
    final warnings = <String>[
      if (o != null && counted.length < _lines.length)
        'يوجد ${nf(_lines.length - counted.length)} صنف لم يُعد — لن تُعدّل أرصدتها.',
      if (recount.isNotEmpty)
        'يوجد ${nf(recount.length)} صنف بقرار «إعادة العد» — عدّل القرار أو أعد العد قبل الاعتماد.',
    ];
    final canApprove =
        _canWrite && o != null && o.status == 'COUNTING' && counted.isNotEmpty && recount.isEmpty;

    return ImdPanel(
      title: 'ملخص أمر الجرد',
      icon: 'info',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _orderPicker(onlyOpen: true),
        const SizedBox(height: 12),
        ImdGrid(columns: 4, minItemWidth: 170, gap: 10, children: [
          _sumCell('رقم الأمر', o?.orderNo ?? '-'),
          _sumCell('المستودع', o?.warehouse ?? '-'),
          _sumCell('إجمالي الأصناف', o == null ? '-' : nf(_lines.length)),
          _sumCell('تم جردها', o == null ? '-' : nf(counted.length)),
          _sumCell('أصناف بها فروقات', o == null ? '-' : nf(withVar.length)),
          _sumCell('ستُسوّى', o == null ? '-' : nf(adjust.length)),
          _sumCell('تجميد المستودع', o == null ? '-' : (o.freeze ? 'مجمّد' : 'غير مجمّد')),
        ]),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          ImdNote(warnings.join('\n')),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton(
            label: 'اعتماد التسوية وإغلاق الجرد',
            icon: 'check-circle',
            onPressed: canApprove ? _approve : null,
          ),
          ImdButton(
            label: 'إلغاء أمر الجرد (ورفع التجميد)',
            icon: 'x',
            kind: ImdBtnKind.danger,
            onPressed: _canWrite && o != null && o.status == 'COUNTING' ? _cancel : null,
          ),
        ]),
      ]),
    );
  }

  /// `.stk-sum div`
  Widget _sumCell(String label, String value) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
      ]),
    );
  }

  Widget _historyTab() {
    final q = _histQ.text.trim().toLowerCase();
    final rows = _orders
        .where((o) =>
            q.isEmpty || o.orderNo.toLowerCase().contains(q) || o.warehouse.toLowerCase().contains(q))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdPanel(
        child: ImdSearchBar(
          controller: _histQ,
          hint: 'بحث برقم الأمر أو المستودع…',
          onChanged: (_) => setState(() {}),
          actions: [
            ImdButton(
              label: 'تحديث',
              icon: 'refresh',
              onPressed: () async {
                await _load();
                if (mounted) showImdToast(context, '✔ تم التحديث');
              },
            ),
          ],
        ),
      ),
      ImdTable(
        columns: const [
          ImdCol('رقم الأمر'),
          ImdCol('المستودع'),
          ImdCol('النوع'),
          ImdCol('تاريخ البدء'),
          ImdCol('تاريخ الإغلاق'),
          ImdCol('الأصناف', numeric: true),
          ImdCol('الفروقات', numeric: true),
          ImdCol('الحالة'),
        ],
        empty: 'لا توجد أوامر جرد',
        onRowTap: (i) async {
          setState(() {
            _cur = rows[i].id;
            _tab = 'analysis';
          });
          await _loadLines();
        },
        rows: [
          for (final o in rows)
            [
              Text(o.orderNo.isEmpty ? '#${o.id.substring(0, 6)}' : o.orderNo,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(o.warehouse.isEmpty ? '—' : o.warehouse),
              Text(_types[o.type] ?? o.type),
              Text(o.date),
              Text(o.closedDate.isEmpty ? '—' : o.closedDate),
              Text(nf(o.itemsCount)),
              Text(o.status == 'COUNTING' ? '—' : nf(o.varianceCount)),
              ImdChip(_statuses[o.status] ?? o.status, tone: _statusTone(o.status)),
            ],
        ],
      ),
    ]);
  }
}

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
        const ImdEmptyBox('اختر أمر الجرد لعرض الفروقات')
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
