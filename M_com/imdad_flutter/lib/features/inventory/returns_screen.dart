import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/voucher_print.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/repos/documents_repo.dart';
import '../documents/doc_log_view.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/line_consolidation.dart';
import 'doc_kit.dart';

/// المرتجعات — نقل مطابق لـ `renderReturns()`: مرتجع من وحدة (صالح يُعاد للرصيد أو تالف توثيقي)،
/// مرتجع إلى مورّد (يخصم الرصيد)، وسجل المرتجعات.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _Row {
  _Row() : unit = '', itemId = '', qty = TextEditingController();
  String itemId;
  String unit;
  final TextEditingController qty;
  final key = UniqueKey();
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _ReturnsScreenState extends State<ReturnsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);

  String _tab = 'unit';
  String _cond = 'GOOD';
  List<Item> _items = const [];
  List<Warehouse> _whs = const [];
  List<BeneficiaryUnit> _units = const [];
  List<Supplier> _sups = const [];
  Map<String, double> _whBal = const {};
  bool _ready = false;
  bool _busy = false;

  // مرتجع الوحدة
  String _uWh = '';
  String _uUnit = '';
  String _uDate = imdToday();
  String _uRef = '';
  final _uNotes = TextEditingController();
  final List<_Row> _uRows = [];

  // مرتجع المورد
  String _sWh = '';
  String _sSup = '';
  String _sDate = imdToday();
  String _sRef = '';
  final _sOrig = TextEditingController();
  final _sNotes = TextEditingController();
  final List<_Row> _sRows = [];

  // السجل

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in [_uNotes, _sOrig, _sNotes]) {
      c.dispose();
    }
    for (final r in [..._uRows, ..._sRows]) {
      r.qty.dispose();
    }
    super.dispose();
  }

  void _switch(String t) {
    setState(() => _tab = t);
    if (t == 'hist') {
    } else {
      _fetch();
    }
  }

  /// `retFetchAll()`
  Future<void> _fetch() async {
    final perm = Perm.of(context);
    final items = await _catalog.items();
    final whs = (await _db.select(_db.warehouses).get()..sort((a, b) => a.name.compareTo(b.name)))
        .where((w) => perm.canWh(w.name))
        .toList();
    final units = await _catalog.units();
    final sups = await _catalog.suppliers()..sort((a, b) => a.name.compareTo(b.name));
    final ref = await _moves.nextRef('returns', 'رد-');
    if (!mounted) return;
    setState(() {
      _items = items;
      _whs = whs;
      _units = units;
      _sups = sups;
      if (_tab == 'unit') {
        _uWh = whs.isNotEmpty ? whs.first.name : '';
        _uUnit = '';
        _uDate = imdToday();
        _uRef = ref;
        _uNotes.clear();
        for (final r in _uRows) {
          r.qty.dispose();
        }
        _uRows
          ..clear()
          ..add(_Row());
      } else {
        _sWh = whs.isNotEmpty ? whs.first.name : '';
        _sSup = '';
        _sDate = imdToday();
        _sRef = ref;
        _sOrig.clear();
        _sNotes.clear();
        for (final r in _sRows) {
          r.qty.dispose();
        }
        _sRows
          ..clear()
          ..add(_Row());
      }
      _ready = true;
    });
    await _refreshBal();
  }

  /// معرّف الوحدة من اسمها المعروض في القائمة.
  ///
  /// القائمة تعرض الاسم لأنه ما يقرؤه المستخدم، والمعرّف هو ما يُحفظ: الاسم
  /// يتبدّل بإعادة تسمية، والمعرّف لا.
  String _unitIdOf(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    for (final u in _units) {
      if (u.name.trim() == n) return u.id;
    }
    return '';
  }

  Future<void> _refreshBal() async {
    final wh = _tab == 'unit' ? _uWh : _sWh;
    if (wh.isEmpty) return;
    final b = await _moves.balances(warehouse: wh);
    if (mounted) setState(() => _whBal = b);
  }

  Item? _item(String id) => _items.where((x) => x.id == id).firstOrNull;

  /// التجميع التلقائي وإعادة التوزيع على الوحدات (انظر [consolidateLines]).
  /// تعمل على قائمة الأسطر المعروضة (مرتجع من وحدة أو إلى مورّد).
  void _autoConsolidate(List<_Row> rows) {
    final complete = <_Row>[];
    final pending = <_Row>[];
    for (final r in rows) {
      final it = _item(r.itemId);
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (it == null || r.unit.isEmpty || qty <= 0) {
        pending.add(r);
      } else {
        complete.add(r);
      }
    }
    if (complete.length < 2) return;

    final consolidated = consolidateLines([
      for (final r in complete)
        LineQty(
          groupKey: r.itemId,
          unitName: r.unit,
          factor: _catalog.factorOf(_item(r.itemId)!, r.unit),
          qty: double.parse(r.qty.text.trim()),
        ),
    ]);

    final before = [for (final r in complete) '${r.itemId}|${r.unit}|${r.qty.text.trim()}'];
    final after = [
      for (final l in consolidated)
        '${l.groupKey}|${l.unitName}|${l.qty == l.qty.roundToDouble() ? l.qty.toInt() : l.qty}'
    ];
    if (before.join('§') == after.join('§')) return;

    setState(() {
      for (final r in complete) {
        r.qty.dispose();
      }
      final rebuilt = <_Row>[
        for (final l in consolidated)
          _Row()
            ..itemId = l.groupKey
            ..unit = l.unitName
            ..qty.text = l.qty == l.qty.roundToDouble() ? l.qty.toInt().toString() : '${l.qty}',
        ...pending,
      ];
      rows
        ..clear()
        ..addAll(rebuilt);
      if (rows.isEmpty) rows.add(_Row());
    });
  }


  void _onItem(List<_Row> rows, _Row r, String id) {
    final it = _item(id);
    setState(() {
      r.itemId = id;
      final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
      r.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
      if (it != null && identical(rows.last, r)) rows.add(_Row());
    });
  }

  /// `retCollect(boxId, checkBalance)`
  ({List<DocLineInput> rows, String err}) _collect(List<_Row> rows, bool checkBalance) {
    final out = <DocLineInput>[];
    for (final r in rows) {
      if (r.itemId.isEmpty) continue;
      final it = _item(r.itemId);
      if (it == null) continue;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) return (rows: out, err: '✖ أدخل كمية صالحة للصنف ${it.name}');
      final f = _catalog.factorOf(it, r.unit);
      final have = _whBal[it.id] ?? 0;
      if (checkBalance && qty * f > have + 1e-9) {
        return (rows: out, err: '✖ الرصيد المتاح من «${it.name}» لا يكفي لإرجاعه للمورّد (${nf(have)} ${it.baseUnit})');
      }
      out.add(DocLineInput(
        itemId: it.id,
        itemCode: it.code,
        itemName: it.name,
        unitName: r.unit,
        factor: f,
        qty: qty,
      ));
    }
    return (rows: out, err: '');
  }

  String _balError(List<DocLineInput> rows, String wh) {
    final sum = <String, double>{};
    for (final r in rows) {
      sum[r.itemId] = (sum[r.itemId] ?? 0) + r.baseQty;
    }
    for (final e in sum.entries) {
      final have = _whBal[e.key] ?? 0;
      if (e.value > have + 1e-9) return MovementsRepo.stockError(_item(e.key), wh, have, e.value);
    }
    return '';
  }

  // ───────────────────────── العرض ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      const ImdPageTitle(
        title: 'المرتجعات',
        icon: 'undo',
        subtitle: 'مرتجعات من الوحدات المستفيدة (فائض/تالف) ومرتجعات إلى الموردين (مواد غير مطابقة)',
      ),
      ImdItabs(
        value: _tab,
        onChanged: _switch,
        tabs: const [
          ImdTab('unit', 'مرتجع من وحدة', icon: 'users'),
          ImdTab('supplier', 'مرتجع إلى مورّد', icon: 'truck'),
          ImdTab('hist', 'سجل المرتجعات', icon: 'file'),
        ],
      ),
    ];
    if (_tab == 'hist') return ImdPage(children: [...head, const DocLogView(kinds: {DocKind.returnDoc}, embedded: true)]);
    if (!_ready) return ImdPage(children: [...head, const ImdLd('جارٍ التهيئة…')]);
    if (!Perm.of(context).writable('returns')) {
      return ImdPage(children: [
        ...head,
        const ImdICard(
          title: 'عرض فقط',
          icon: 'eye',
          child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: ImdLdText('تسجيل المرتجعات متاح لمدير النظام')),
        ),
      ]);
    }
    final unit = _tab == 'unit';
    return ImdStickyPage(
      sticky: ImdStickyActions(
        caption: unit ? 'لو الحالة «صالحة» الكمية هترجع للمخزون' : 'تنبيه: التنفيذ النهائي يخصم الكميات من المخزون فورًا',
        children: [
          ImdButton.outline(
            label: '+ سطر جديد',
            small: true,
            onPressed: _busy
                ? null
                : () {
                    final rows = unit ? _uRows : _sRows;
                    _autoConsolidate(rows);
                    setState(() => rows.add(_Row()));
                  },
          ),
          ImdButton.outline(label: 'طباعة سند المرتجع', icon: 'printer', small: true, onPressed: _busy ? null : () => _print(unit)),
          ImdButton(
            label: unit ? 'اعتماد وتسجيل المرتجع' : 'اعتماد وتسجيل المرتجع (خصم من الرصيد)',
            icon: 'check',
            busy: _busy,
            onPressed: unit ? _saveUnit : _saveSupplier,
          ),
        ],
      ),
      children: [...head, ...(unit ? _unitForm(context) : _supplierForm(context))],
    );
  }

  Widget _lab(String l, Widget f) => ImdLabeled(l, f, size: 11);

  Widget _whSelect(String value, ValueChanged<String> on) => ImdSelect<String>(
        value: value,
        items: _whs.isEmpty
            ? [('', Perm.of(context).scope == null ? '— لا مستودعات —' : '— لا توجد مستودعات ضمن نطاقك —')]
            : [for (final w in _whs) (w.name, w.name)],
        onChanged: (v) => on(v ?? ''),
      );

  List<Widget> _unitForm(BuildContext context) {
    final mobile = ImdBp.of(context).mobile;
    final fields = [
      _lab('المستودع المستلم *', _whSelect(_uWh, (v) {
        setState(() => _uWh = v);
        _refreshBal();
      })),
      _lab(
        'الوحدة المرتجعة *',
        ImdSelect<String>(
          value: _uUnit,
          items: [('', '— اختر الوحدة —'), for (final u in _units) (u.name, '${u.code} — ${u.name}')],
          onChanged: (v) => setState(() => _uUnit = v ?? ''),
        ),
      ),
      _lab('التاريخ', ImdDateField(value: _uDate, onChanged: (v) => setState(() => _uDate = v))),
      _lab('المرجع', ImdReadonlyField(text: _uRef)),
    ];
    return [
      ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdWorkflowSteps(['اختر الوحدة والمستودع', 'حدد الحالة', 'أضف الأصناف', 'اطبع أو اعتمد']),
          ImdQuickGrid([('المستودعات', nf(_whs.length)), ('الوحدات', nf(_units.length)), ('الأصناف', nf(_items.length))]),
          const ImdPrintTip('الأصناف الصالحة تُعاد للرصيد. الأصناف التالفة تُسجل توثيقيًا فقط بدون إضافة مخزون.'),
        ]),
      ),
      const SizedBox(height: 12),
      ImdICard(
        title: 'بيانات مرتجع الوحدة',
        icon: 'clipboard',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mobile)
            for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 8), child: f)
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 8),
              Expanded(child: fields[1]),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: fields[2]),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: fields[3]),
            ]),
          const SizedBox(height: 10),
          const ImdRowLabel('حالة الأصناف المرتجعة'),
          ImdTargetPills<String>(
            value: _cond,
            onChanged: (v) => setState(() => _cond = v),
            tabs: const [
              ImdTab('GOOD', '✅ صالحة — تُضاف للرصيد'),
              ImdTab('DAMAGED', '💥 تالفة — تُسجَّل إتلافًا (بدون إضافة للرصيد)'),
            ],
          ),
          _lab('ملاحظات', ImdFld(controller: _uNotes)),
        ]),
      ),
      for (final (i, r) in _uRows.indexed)
        KeyedSubtree(key: r.key, child: _rowView(context, i + 1, _uRows, r, 'الرصيد الحالي')),
      ImdValidationBox(title: 'فحص سريع قبل اعتماد مرتجع الوحدة', items: _validateUnit()),
    ];
  }

  List<Widget> _supplierForm(BuildContext context) {
    final mobile = ImdBp.of(context).mobile;
    final fields = [
      _lab('المستودع المرسل منه *', _whSelect(_sWh, (v) {
        setState(() => _sWh = v);
        _refreshBal();
      })),
      _lab(
        'الجهة الموردة *',
        ImdSelect<String>(
          value: _sSup,
          items: [('', '— اختر المورد —'), for (final s in _sups) (s.name, s.name)],
          onChanged: (v) => setState(() => _sSup = v ?? ''),
        ),
      ),
      _lab('التاريخ', ImdDateField(value: _sDate, onChanged: (v) => setState(() => _sDate = v))),
      _lab('المرجع', ImdReadonlyField(text: _sRef)),
    ];
    return [
      ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdWorkflowSteps(['اختر المورد والمستودع', 'اربط السند الأصلي إن وجد', 'أضف الأصناف', 'اطبع واعتمد الخصم']),
          ImdQuickGrid([('الموردون', nf(_sups.length)), ('المستودعات', nf(_whs.length)), ('الأصناف', nf(_items.length))]),
          const ImdPrintTip('اعتماد مرتجع المورد يخصم الكميات من الرصيد الحالي، فراجِع المرجع الأصلي والسبب قبل التنفيذ.'),
        ]),
      ),
      const SizedBox(height: 12),
      ImdICard(
        title: 'بيانات مرتجع المورّد',
        icon: 'clipboard',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mobile)
            for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 8), child: f)
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 8),
              Expanded(child: fields[1]),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: fields[2]),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: fields[3]),
            ]),
          const SizedBox(height: 8),
          if (mobile) ...[
            _lab('مرجع سند التوريد الأصلي', ImdFld(controller: _sOrig, hint: 'مثال: و-000012')),
            const SizedBox(height: 8),
            _lab('سبب الإرجاع / ملاحظات', ImdFld(controller: _sNotes, hint: 'مواصفات غير مطابقة، تلف بالنقل...أو غيره', onChanged: (_) => setState(() {}))),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _lab('مرجع سند التوريد الأصلي', ImdFld(controller: _sOrig, hint: 'مثال: و-000012', onChanged: (_) => setState(() {})))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _lab('سبب الإرجاع / ملاحظات',
                    ImdFld(controller: _sNotes, hint: 'مواصفات غير مطابقة، تلف بالنقل...أو غيره', onChanged: (_) => setState(() {}))),
              ),
            ]),
        ]),
      ),
      for (final (i, r) in _sRows.indexed)
        KeyedSubtree(key: r.key, child: _rowView(context, i + 1, _sRows, r, 'الرصيد الحالي')),
      ImdValidationBox(title: 'فحص سريع قبل اعتماد مرتجع المورد', items: _validateSupplier()),
    ];
  }


  /// مكافئ الكمية بالوحدة الأساسية — يجعل التجميع التلقائي وإعادة التوزيع
  /// مرئيَّين للمستخدم بدل أن يتغيّر الرقم أمامه بلا تفسير.
  Widget? _baseHint(_Row r) {
    final it = _item(r.itemId);
    if (it == null || r.unit.isEmpty) return null;
    final qty = double.tryParse(r.qty.text.trim()) ?? 0;
    final f = _catalog.factorOf(it, r.unit);
    if (qty <= 0 || f == 1) return null;
    return ImdRowMeta('= ${nf((qty * f * 1000).round() / 1000)} ${it.baseUnit}');
  }

  Widget _rowView(BuildContext context, int index, List<_Row> rows, _Row r, String metaLabel) {
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final narrow = MediaQuery.sizeOf(context).width <= 768;
    final wh = _tab == 'unit' ? _uWh : _sWh;
    final meta = it == null
        ? ''
        : () {
            final b = displayBalance(it, wh.isNotEmpty ? (_whBal[it.id] ?? 0) : it.qty);
            return wh.isNotEmpty
                ? 'رصيد «$wh»: ${nf(b.qty)} ${b.unit}'
                : '$metaLabel: ${nf(b.qty)} ${b.unit}';
          }();
    final picker = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الصنف'),
      ImdItemPicker(items: _items, value: r.itemId, onChanged: (v) => _onItem(rows, r, v)),
      ImdRowMeta(meta),
    ]);
    final unit = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الوحدة'),
      ImdSelect<String>(
        value: r.unit,
        items: units.isEmpty ? const [('', '—')] : [for (final u in units) (u.name, u.name)],
        onChanged: (v) => setState(() {
          // تغيير الوحدة يعيد احتساب الكمية بثبات الكمية بالوحدة الأساسية:
          // ١١٠٠ كجم ⇒ ٢٧٫٥ كيسًا، لا ١١٠٠ كيسًا.
          final next = v ?? '';
          final item = _item(r.itemId);
          final qty = double.tryParse(r.qty.text.trim()) ?? 0;
          if (item != null && qty > 0 && r.unit.isNotEmpty && next.isNotEmpty && next != r.unit) {
            imdSetText(
              r.qty,
              _num(convertQty(
                qty,
                _catalog.factorOf(item, r.unit),
                _catalog.factorOf(item, next),
              )),
            );
          }
          r.unit = next;
        }),
      ),
    ]);
    final qty = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الكمية'),
      // مغادرة الحقل تجمع الأصناف المكررة تلقائيًا وتعيد توزيع الوحدات.
      Focus(
        onFocusChange: (has) {
          if (!has) _autoConsolidate(rows);
        },
        child: ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
      ),
    ]);
    final del = Padding(
      padding: const EdgeInsets.only(top: 19),
      child: ImdIconButton(
        icon: 'x',
        kind: ImdBtnKind.danger,
        onPressed: () => setState(() {
          rows.remove(r);
          r.qty.dispose();
          if (rows.isEmpty) rows.add(_Row());
        }),
      ),
    );
    return ImdRvRow(
      index: index,
      trailing: _baseHint(r),
      child: narrow
          ? Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: picker), const SizedBox(width: 10), Expanded(child: unit)]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: qty), const SizedBox(width: 10), del]),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: picker),
              const SizedBox(width: 10),
              SizedBox(width: 150, child: unit),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: qty),
              const SizedBox(width: 10),
              del,
            ]),
    );
  }

  /// `retValidateUnitLive()`
  List<ImdCheck> _validateUnit() {
    final items = <ImdCheck>[];
    if (_uWh.isEmpty) items.add(const ImdCheck('warn', 'المستودع غير محدد', 'اختَر المستودع المستلم للمرتجع.'));
    if (_uUnit.isEmpty) items.add(const ImdCheck('warn', 'الوحدة غير محددة', 'اختَر الوحدة التي أعادت الأصناف.'));
    if (imdIsFuture(_uDate)) items.add(const ImdCheck('err', 'تاريخ غير صالح', 'تاريخ المرتجع لا يمكن أن يكون في المستقبل.'));
    final c = _collect(_uRows, false);
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في السطور', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل الاعتماد.'));
    items.add(ImdCheck('ok', 'نوع المرتجع الحالي',
        _cond == 'GOOD' ? 'مرتجع صالح — سيُعاد للمخزون عند الاعتماد.' : 'مرتجع تالف — سيسجل توثيقيًا بدون إضافة رصيد.'));
    return items;
  }

  /// `retValidateSupplierLive()`
  List<ImdCheck> _validateSupplier() {
    final items = <ImdCheck>[];
    if (_sWh.isEmpty) items.add(const ImdCheck('warn', 'المستودع غير محدد', 'اختَر المستودع الذي سيخرج منه مرتجع المورد.'));
    if (_sSup.isEmpty) items.add(const ImdCheck('warn', 'المورد غير محدد', 'اختَر الجهة الموردة قبل الاعتماد.'));
    if (imdIsFuture(_sDate)) items.add(const ImdCheck('err', 'تاريخ غير صالح', 'تاريخ المرتجع لا يمكن أن يكون في المستقبل.'));
    if (_sOrig.text.trim().isEmpty) {
      items.add(const ImdCheck('warn', 'مرجع السند الأصلي غير مدخل', 'مش إجباري تقنيًا، لكن مهم جدًا للتتبع والمراجعة.'));
    }
    if (_sNotes.text.trim().isEmpty) {
      items.add(const ImdCheck('warn', 'سبب الإرجاع غير مكتوب', 'اكتب سبب الإرجاع لتقليل اللخبطة والمراجعات اليدوية.'));
    }
    final c = _collect(_sRows, true);
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في السطور', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل الاعتماد.'));
    final bal = _balError(c.rows, _sWh);
    if (bal.isNotEmpty) items.add(ImdCheck('err', 'الرصيد لا يكفي', bal.replaceFirst(RegExp(r'^✖\s*'), '')));
    return items;
  }

  /// `retSaveUnit()`
  Future<void> _saveUnit() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'returns', 'create')) return;
    if (_uWh.isNotEmpty && !perm.canWh(_uWh)) return showImdToast(context, Perm.scopeBlock(_uWh));
    final frozen = await _moves.frozenMessage(_uWh);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    if (_uWh.isEmpty) return showImdToast(context, '✖ اختر المستودع');
    if (_uUnit.isEmpty) return showImdToast(context, '✖ اختر الوحدة المرتجعة');
    if (_uDate.isEmpty) return showImdToast(context, '✖ اختر تاريخ المرتجع');
    if (imdIsFuture(_uDate)) return showImdToast(context, '✖ تاريخ المرتجع لا يمكن أن يكون في المستقبل');
    if (_uRef.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    final c = _collect(_uRows, false);
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل');
    final isGood = _cond == 'GOOD';
    setState(() => _busy = true);
    try {
      if (await _moves.hasRefConflict('returns', _uRef, '')) {
        if (mounted) showImdToast(context, '✖ يوجد مرتجع سابق بنفس المرجع — استخدم مرجعًا مختلفًا');
        return;
      }
      if (!mounted) return;
      final ok = await imdConfirm(
        context,
        isGood ? 'اعتماد المرتجع وإضافة الكميات إلى الرصيد؟' : 'اعتماد المرتجع كإتلاف (لن تُضاف الكميات إلى الرصيد)؟',
      );
      if (!ok || !mounted) return;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveReturn(
        warehouse: _uWh,
        party: _uUnit,
        beneficiaryUnitId: _unitIdOf(_uUnit),
        beneficiaryUnitName: _uUnit,
        date: _uDate,
        lines: c.rows,
        type: 'FROM_UNIT',
        condition: isGood ? 'صالحة' : 'تالفة',
        refNo: _uRef,
        notes: _uNotes.text.trim(),
        createdBy: actor?.email ?? '',
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      await AuditRepo(_db).write('RETURN_FROM_UNIT', 'return', isGood ? 'تسجيل مرتجع من وحدة وإضافة الرصيد' : 'تسجيل مرتجع من وحدة كتالف',
          details: {
            'refNo': _uRef,
            'warehouse': _uWh,
            'target': _uUnit,
            'status': isGood ? 'GOOD' : 'DAMAGED',
            'itemCount': c.rows.length,
            'totalBaseQty': c.rows.fold<double>(0, (a, b) => a + b.baseQty),
            'risk': isGood ? 'normal' : 'sensitive',
          },
          actor: actor);
      if (!mounted) return;
      showImdToast(context, isGood ? '🎉 تم تسجيل المرتجع وإضافته للرصيد' : '✔ تم تسجيل المرتجع كإتلاف');
      await _fetch();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `retSaveSupplier()`
  Future<void> _saveSupplier() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'returns', 'create')) return;
    if (_sWh.isNotEmpty && !perm.canWh(_sWh)) return showImdToast(context, Perm.scopeBlock(_sWh));
    final frozen = await _moves.frozenMessage(_sWh);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    if (_sWh.isEmpty) return showImdToast(context, '✖ اختر المستودع');
    if (_sSup.isEmpty) return showImdToast(context, '✖ اختر الجهة الموردة');
    if (_sDate.isEmpty) return showImdToast(context, '✖ اختر تاريخ المرتجع');
    if (imdIsFuture(_sDate)) return showImdToast(context, '✖ تاريخ المرتجع لا يمكن أن يكون في المستقبل');
    if (_sRef.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    final c = _collect(_sRows, true);
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل');
    final bal = _balError(c.rows, _sWh);
    if (bal.isNotEmpty) return showImdToast(context, bal);
    setState(() => _busy = true);
    try {
      if (await _moves.hasRefConflict('returns', _sRef, '')) {
        if (mounted) showImdToast(context, '✖ يوجد مرتجع سابق بنفس المرجع — استخدم مرجعًا مختلفًا');
        return;
      }
      if (!mounted) return;
      if (!await imdConfirm(context, 'اعتماد مرتجع المورّد؟ سيتم خصم الكميات من الرصيد الحالي.')) return;
      if (!mounted) return;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveReturn(
        warehouse: _sWh,
        party: _sSup,
        date: _sDate,
        lines: c.rows,
        type: 'TO_SUPPLIER',
        origRef: _sOrig.text.trim(),
        refNo: _sRef,
        notes: _sNotes.text.trim(),
        createdBy: actor?.email ?? '',
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      await AuditRepo(_db).write('RETURN_TO_SUPPLIER', 'return', 'تسجيل مرتجع إلى المورد وخصم الرصيد',
          details: {
            'refNo': _sRef,
            'warehouse': _sWh,
            'target': _sSup,
            'status': 'TO_SUPPLIER',
            'itemCount': c.rows.length,
            'totalBaseQty': c.rows.fold<double>(0, (a, b) => a + b.baseQty),
            'origRef': _sOrig.text.trim(),
            'risk': 'sensitive',
          },
          actor: actor);
      if (!mounted) return;
      showImdToast(context, '✔ تم تسجيل مرتجع المورّد وخصم الرصيد');
      await _fetch();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `retPrint(isUnit)`
  void _print(bool isUnit) {
    final c = _collect(isUnit ? _uRows : _sRows, false);
    if (c.rows.isEmpty) {
      return showImdToast(context, '✖ لا توجد أصناف للطباعة${c.err.isNotEmpty ? ' — ${c.err}' : ''}');
    }
    VoucherPrint.print(
      db: _db,
      title: isUnit ? 'سند مرتجع من وحدة مستفيدة' : 'سند مرتجع إلى مورّد',
      kind: isUnit ? VoucherKind.returnFromUnit : VoucherKind.returnToSupplier,
      condition: isUnit ? (_cond == 'GOOD' ? 'صالحة' : 'تالفة') : '',
      origRef: isUnit ? '' : _sOrig.text.trim(),
      refNo: isUnit ? _uRef : _sRef,
      date: isUnit ? _uDate : _sDate,
      warehouse: isUnit ? _uWh : _sWh,
      party: isUnit ? _uUnit : _sSup,
      notes: isUnit ? _uNotes.text.trim() : _sNotes.text.trim(),
      lines: [
        for (final l in c.rows)
          VoucherLine(
            itemName: l.itemName,
            unitName: l.unitName,
            qty: l.qty,
            itemCode: l.itemCode,
            notes: l.notes,
          ),
      ],
    );
  }

  // ───────────────────────── السجل ─────────────────────────

}
