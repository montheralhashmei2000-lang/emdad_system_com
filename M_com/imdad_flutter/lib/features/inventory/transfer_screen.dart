import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/voucher_print.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/repos/documents_repo.dart';
import '../documents/doc_log_view.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/line_consolidation.dart';
import '../../domain/strength.dart';
import 'doc_kit.dart';

/// التحويل المخزني — نقل مطابق لـ `renderTransfer()`: إرسال تحويل جديد (مع الاحتساب التلقائي
/// بالاستحقاقات لمعسكر مستفيد)، بانتظار الاستلام (تأكيد أو رفض بسبب)، وسجل التحويلات.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _Row {
  _Row({this.itemId = '', this.unit = '', double? qty, this.noAuto = false})
      : qty = TextEditingController(text: qty == null ? '' : _num(qty));
  String itemId;
  String unit;
  final TextEditingController qty;
  bool noAuto;
  final key = UniqueKey();
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _TransferScreenState extends State<TransferScreen> {

  /// التجميع التلقائي وإعادة التوزيع على الوحدات (انظر [consolidateLines]).
  /// يُستدعى عند مغادرة حقل الكمية وعند إضافة سطر جديد.
  void _autoConsolidate() {
    final complete = <_Row>[];
    final pending = <_Row>[];
    for (final r in _rows) {
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
    final after = [for (final l in consolidated) '${l.groupKey}|${l.unitName}|${_num(l.qty)}'];
    if (before.join('§') == after.join('§')) return;

    setState(() {
      for (final r in complete) {
        r.qty.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final l in consolidated)
            _Row(itemId: l.groupKey, unit: l.unitName, qty: l.qty, noAuto: true),
          ...pending,
        ]);
      if (_rows.isEmpty) _rows.add(_Row());
    });
  }

  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);

  String _tab = 'form';

  // TRF
  List<Item> _items = const [];
  List<Warehouse> _whs = const [];
  List<BeneficiaryUnit> _units = const [];
  Map<String, Entitlement> _ents = const {};
  StrengthCalculator? _calc;
  Map<String, double> _fromBal = const {};
  bool _ready = false;
  bool _busy = false;

  // النموذج
  String _camp = '';
  String _from = '';
  String _to = '';
  String _date = imdToday();
  String _ref = '';
  final _notes = TextEditingController();
  final List<_Row> _rows = [];

  // الاحتساب التلقائي
  String _acDate = imdToday();
  final _acHead = TextEditingController();
  final _acDays = TextEditingController(text: '1');

  // المعلقة والسجل
  List<Transfer>? _pending;

  @override
  void initState() {
    super.initState();
    _form();
  }

  @override
  void dispose() {
    for (final c in [_notes, _acHead, _acDays]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.qty.dispose();
    }
    super.dispose();
  }

  void _switch(String t) {
    setState(() => _tab = t);
    if (t == 'form') _form();
    if (t == 'pending') _loadPending();
  }

  /// `trfFetchAll()` + `trfForm()`
  Future<void> _form() async {
    final perm = Perm.of(context);
    final items = await _catalog.items();
    final whs = (await _db.select(_db.warehouses).get()..sort((a, b) => a.name.compareTo(b.name)))
        .where((w) => perm.canWh(w.name))
        .toList();
    final units = await _catalog.units();
    final ents = {for (final e in await _db.select(_db.entitlements).get()) e.itemId: e};
    final calc = await DailyRepo(_db).calculator();
    final ref = await _moves.nextRef('transfers', 'ح-');
    if (!mounted) return;
    setState(() {
      _items = items;
      _whs = whs;
      _units = units;
      _ents = ents;
      _calc = calc;
      _camp = '';
      _from = whs.isNotEmpty ? whs.first.name : '';
      _to = whs.length > 1 ? whs[1].name : (whs.isNotEmpty ? whs.first.name : '');
      _date = imdToday();
      _acDate = imdToday();
      _acHead.clear();
      imdSetText(_acDays, '1');
      _ref = ref;
      _notes.clear();
      for (final r in _rows) {
        r.qty.dispose();
      }
      _rows
        ..clear()
        ..add(_Row());
      _ready = true;
    });
    await _refreshBal();
  }

  Future<void> _refreshBal() async {
    if (_from.isEmpty) return;
    final b = await _moves.balances(warehouse: _from);
    if (mounted) setState(() => _fromBal = b);
  }

  List<BeneficiaryUnit> get _camps => _units.where((u) => u.type == 'camp' || u.parentId.isEmpty).toList();

  bool _feeds(Warehouse w, String campId) => w.feedsAllCamps || _catalog.campsOf(w).contains(campId);

  /// `trfWhOptionsFor(campId)`
  List<Warehouse> _whsForCamp(String campId) {
    if (campId.isEmpty) return _whs;
    final f = _whs.where((w) => _feeds(w, campId)).toList();
    return f.isNotEmpty ? f : _whs;
  }

  Item? _item(String id) => _items.where((x) => x.id == id).firstOrNull;

  void _onItem(_Row r, String id) {
    final it = _item(id);
    setState(() {
      r.itemId = id;
      final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
      r.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
      if (it != null && !r.noAuto && identical(_rows.last, r)) _rows.add(_Row());
    });
  }

  /// `trfCollect()`
  ({List<DocLineInput> rows, String err}) _collect() {
    final rows = <DocLineInput>[];
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _item(r.itemId);
      if (it == null) continue;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) return (rows: rows, err: '✖ أدخل كمية صالحة للصنف ${it.name}');
      rows.add(DocLineInput(
        itemId: it.id,
        itemCode: it.code,
        itemName: it.name,
        unitName: r.unit,
        factor: _catalog.factorOf(it, r.unit),
        qty: qty,
      ));
    }
    return (rows: rows, err: '');
  }

  String _balError(List<DocLineInput> rows) {
    final sum = <String, double>{};
    for (final r in rows) {
      sum[r.itemId] = (sum[r.itemId] ?? 0) + r.baseQty;
    }
    for (final e in sum.entries) {
      final have = _fromBal[e.key] ?? 0;
      if (e.value > have + 1e-9) return MovementsRepo.stockError(_item(e.key), _from, have, e.value);
    }
    return '';
  }

  /// `trfValidateLive()`
  List<ImdCheck> _validate() {
    final items = <ImdCheck>[];
    if (_from.isEmpty || _to.isEmpty) items.add(const ImdCheck('warn', 'المستودعات غير مكتملة', 'حدّد المصدر والهدف قبل إرسال التحويل.'));
    if (_from.isNotEmpty && _from == _to) items.add(const ImdCheck('err', 'تحويل غير منطقي', 'لا يمكن التحويل من وإلى نفس المستودع.'));
    if (imdIsFuture(_date)) items.add(const ImdCheck('err', 'تاريخ غير صالح', 'تاريخ التحويل لا يمكن أن يكون في المستقبل.'));
    final c = _collect();
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في السطور', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل إرسال التحويل.'));
    if (imdDuplicateCount(c.rows, (r) => '${r.itemId}|${r.unitName}') > 0) {
      items.add(const ImdCheck('warn', 'أصناف مكررة', 'ادمج السطور المتشابهة أو راجعها بدقة.'));
    }
    final bal = _balError(c.rows);
    if (bal.isNotEmpty) items.add(ImdCheck('err', 'الرصيد لا يكفي للتحويل', bal.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isNotEmpty) {
      items.add(ImdCheck('ok', 'ملخص سريع',
          'عدد السطور: ${nf(c.rows.length)} — إجمالي الكمية الأساسية: ${nf(c.rows.fold<double>(0, (a, b) => a + b.baseQty))}'));
    }
    return items;
  }

  /// `trfAutoCalcFromEntitlements()`
  Future<void> _autoCalc() async {
    if (_camp.isEmpty) return showImdToast(context, '✖ اختر المعسكر المستفيد أولًا');
    final days = int.tryParse(_acDays.text.trim()) ?? 1;
    final date = _acDate.isNotEmpty ? _acDate : _date;
    var head = double.tryParse(_acHead.text.trim()) ?? 0;
    if (head == 0) {
      final camp = _calc?.campStrengthOn(_camp, date);
      head = camp?.total ?? 0;
      imdSetText(_acHead, _num(head));
      if (head == 0) {
        return showImdToast(context,
            '✖ لا توجد تفريدة يومية لوحدات هذا المعسكر بهذا التاريخ — أدخل عدد الأفراد الإجمالي يدويًا في الحقل ثم أعد الاحتساب');
      }
      final found = camp?.source == StrengthSource.campRecord ? 1 : (camp?.unitsCounted ?? 0);
      final of = camp?.source == StrengthSource.campRecord ? 1 : _units.where((u) => u.parentId == _camp).length;
      showImdToast(context, 'ℹ تم جلب ${nf(head)} فردًا تلقائيًا من التفريدة اليومية ($found/$of وحدة لها تفريدة بهذا التاريخ)');
    }
    final entries = _ents.values.where((e) => e.qtyPerPerson > 0).toList();
    if (entries.isEmpty) {
      return showImdToast(context, '✖ لا توجد استحقاقات مقررة بعد — اضبطها من شاشة «الاستحقاقات والمقررات»');
    }
    setState(() {
      for (final r in _rows) {
        r.qty.dispose();
      }
      _rows.clear();
      for (final e in entries) {
        final it = _item(e.itemId);
        if (it == null) continue;
        // `entMeasureQty(e,it)/30` — المقرر الشهري بوحدة القياس المختارة.
        final daily = e.qtyPerPerson / 30.0;
        final qty = (daily * head * (days <= 0 ? 1 : days) * 1000).round() / 1000;
        if (qty <= 0) continue;
        final uName = e.measureUnitName.isNotEmpty ? e.measureUnitName : it.baseUnit;
        _rows.add(_Row(itemId: it.id, unit: uName, qty: qty, noAuto: true));
      }
      if (_rows.isEmpty) _rows.add(_Row());
    });
    if (mounted) {
      showImdToast(context, '✔ تم احتساب ${nf(entries.length)} صنفًا تلقائيًا بناءً على الاستحقاقات — راجع الكميات قبل الإرسال');
    }
  }

  /// `trfSend()`
  Future<void> _send() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'transfer', 'create')) return;
    for (final wh in [_from, _to]) {
      if (wh.isNotEmpty && !perm.canWh(wh)) return showImdToast(context, Perm.scopeBlock(wh));
      final frozen = await _moves.frozenMessage(wh);
      if (!mounted) return;
      if (frozen != null) return showImdToast(context, frozen);
    }
    if (_from.isEmpty || _to.isEmpty) return showImdToast(context, '✖ اختر المستودعين');
    if (_date.isEmpty) return showImdToast(context, '✖ اختر تاريخ التحويل');
    if (imdIsFuture(_date)) return showImdToast(context, '✖ تاريخ التحويل لا يمكن أن يكون في المستقبل');
    if (_ref.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    if (_from == _to) return showImdToast(context, '✖ لا يمكن التحويل لنفس المستودع');
    final c = _collect();
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل');
    final bal = _balError(c.rows);
    if (bal.isNotEmpty) return showImdToast(context, bal);
    setState(() => _busy = true);
    try {
      if (await _moves.hasRefConflict('transfers', _ref, 'REJECTED')) {
        if (mounted) showImdToast(context, '✖ يوجد تحويل سابق بنفس المرجع — استخدم مرجعًا مختلفًا');
        return;
      }
      if (!mounted) return;
      final ok = await imdConfirm(
        context,
        'إرسال أمر التحويل من «$_from» إلى «$_to»؟\nسيبقى معلقًا حتى يؤكد استلامه أمين المستودع الهدف.',
      );
      if (!ok || !mounted) return;
      final camp = _camps.where((x) => x.id == _camp).firstOrNull;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveTransfer(
        fromWarehouse: _from,
        toWarehouse: _to,
        date: _date,
        lines: c.rows,
        campId: _camp,
        campName: camp?.name ?? '',
        refNo: _ref,
        notes: _notes.text.trim(),
        createdBy: actor?.email ?? '',
        actor: actor,
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      if (!mounted) return;
      showImdToast(context, '📤 أُرسل أمر التحويل — بانتظار تأكيد الاستلام من «$_to»');
      await _form();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _print() {
    final c = _collect();
    if (c.rows.isEmpty) {
      return showImdToast(context, '✖ لا توجد أصناف للطباعة${c.err.isNotEmpty ? ' — ${c.err}' : ''}');
    }
    VoucherPrint.print(
      db: _db,
      title: 'إذن تحويل مخزني',
      kind: VoucherKind.transfer,
      statusLabel: 'معلّق بانتظار الاستلام',
      refNo: _ref,
      date: _date,
      warehouse: _from,
      party: _to,
      notes: _notes.text.trim(),
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

  // ───────────────────────── العرض ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      const ImdPageTitle(
        title: 'التحويل المخزني',
        icon: 'refresh',
        subtitle: 'إرسال واستلام تحويلات بين المستودعات بدورة اعتماد ثنائية (إرسال ← استلام وتأكيد)',
      ),
      ImdItabs(
        value: _tab,
        onChanged: _switch,
        tabs: const [
          ImdTab('form', 'إرسال تحويل جديد', icon: 'file'),
          ImdTab('pending', 'بانتظار الاستلام', icon: 'hourglass'),
          ImdTab('hist', 'سجل التحويلات', icon: 'file'),
        ],
      ),
    ];
    if (_tab != 'form') {
      return ImdPage(children: [...head, if (_tab == 'pending') _pendingView(context) else const DocLogView(kinds: {DocKind.transfer}, embedded: true)]);
    }
    if (!_ready) return ImdPage(children: [...head, const ImdLd('جارٍ التهيئة…')]);
    if (!Perm.of(context).writable('transfer')) {
      return ImdPage(children: [
        ...head,
        const ImdICard(
          title: 'عرض فقط',
          icon: 'eye',
          child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: ImdLdText('إرسال التحويلات متاح لمدير النظام')),
        ),
      ]);
    }
    if (_whs.length < 2) {
      return ImdPage(children: [
        ...head,
        const ImdICard(child: ImdLdText('يلزم وجود مستودعين على الأقل لإجراء تحويل — أضف مستودعًا من شاشة «استلام بضاعة»')),
      ]);
    }
    return ImdStickyPage(
      sticky: ImdStickyActions(
        caption: 'يتم الإغلاق النهائي من شاشة التحويلات المعلقة بعد الاستلام',
        children: [
          ImdButton.outline(
            label: '+ سطر جديد',
            small: true,
            onPressed: _busy
                ? null
                : () {
                    _autoConsolidate();
                    setState(() => _rows.add(_Row()));
                  },
          ),
          ImdButton.outline(label: 'طباعة إذن التحويل', icon: 'printer', small: true, onPressed: _busy ? null : _print),
          ImdButton(label: 'إرسال أمر التحويل (بانتظار الاستلام)', icon: 'upload', busy: _busy, onPressed: _send),
        ],
      ),
      children: [...head, ..._formBody(context)],
    );
  }

  List<Widget> _formBody(BuildContext context) {
    final c = context.imd;
    final toOpts = _whsForCamp(_camp);
    final campFiltered = _camp.isEmpty ? <Warehouse>[] : _whs.where((w) => _feeds(w, _camp)).toList();
    final note = _camp.isEmpty
        ? ''
        : (campFiltered.isNotEmpty
            ? '🏕️ تمت التصفية تلقائيًا: ${nf(campFiltered.length)} مستودع يغذي هذا المعسكر'
            : '⚠ لا يوجد مستودع مرتبط بهذا المعسكر بعد — تُعرض كل المستودعات');
    Widget lab(String l, Widget f) => ImdLabeled(l, f, size: 11);
    final mobile = ImdBp.of(context).mobile;

    return [
      ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdWorkflowSteps(['اختر المصدر والهدف', 'أضف الأصناف', 'اطبع الإذن', 'أرسل للتحويل المعلّق']),
          ImdQuickGrid([('المستودعات', nf(_whs.length)), ('الأصناف', nf(_items.length))]),
          const ImdPrintTip('التحويل لا يكتمل هنا نهائيًا؛ هو يدخل حالة «بانتظار الاستلام» لحد ما الجهة الهدف تأكد الاستلام أو ترفضه.'),
        ]),
      ),
      const SizedBox(height: 12),
      ImdICard(
        title: 'بيانات التحويل',
        icon: 'clipboard',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          lab(
            '🏕️ المعسكر المستفيد (اختياري — للصرف الرئيسي عبر تحويل مخزني)',
            ImdSelect<String>(
              value: _camp,
              items: [
                ('', '— بدون (تحويل عادي بين مستودعات) —'),
                for (final cp in _camps) (cp.id, '${cp.code} — ${cp.name}'),
              ],
              onChanged: (v) => setState(() {
                _camp = v ?? '';
                final opts = _whsForCamp(_camp);
                if (!opts.any((w) => w.name == _to)) _to = opts.isNotEmpty ? opts.first.name : '';
              }),
            ),
          ),
          const SizedBox(height: 8),
          if (mobile) ...[
            lab('من مستودع (المصدر) *', _whSelect(_from, _whs, (v) {
              setState(() => _from = v);
              _refreshBal();
            })),
            const SizedBox(height: 8),
            lab('إلى مستودع (الهدف) *', _whSelect(_to, toOpts, (v) => setState(() => _to = v))),
            const SizedBox(height: 8),
            lab('التاريخ', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
            const SizedBox(height: 8),
            lab('المرجع', ImdReadonlyField(text: _ref)),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: lab('من مستودع (المصدر) *', _whSelect(_from, _whs, (v) {
                  setState(() => _from = v);
                  _refreshBal();
                })),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  lab('إلى مستودع (الهدف) *', _whSelect(_to, toOpts, (v) => setState(() => _to = v))),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: ImdEmojiText(note, iconSize: 11, style: TextStyle(fontSize: 11, color: c.muted)),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: lab('التاريخ', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)))),
              const SizedBox(width: 8),
              SizedBox(width: 192, child: lab('المرجع', ImdReadonlyField(text: _ref))),
            ]),
          const SizedBox(height: 10),
          lab('مبررات التحويل / ملاحظات', ImdFld(controller: _notes)),
        ]),
      ),
      if (_camp.isNotEmpty)
        ImdICard(
          title: 'احتساب تلقائي بالاستحقاقات (بدل إدخال كل صنف يدويًا)',
          icon: 'calculator',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdPrintTip(
                'تُحسب الكمية = الاستحقاق اليومي للفرد × إجمالي عدد الأفراد × مدة الإعاشة. عدد الأفراد يُجلب تلقائيًا من التفريدة اليومية لوحدات المعسكر (إجمالي المعسكر كاملاً وليس وحدة وحدة)، أو أدخله يدويًا إن لم تتوفر تفريدة.'),
            const SizedBox(height: 10),
            ImdRbar(bottom: 0, children: [
              SizedBox(
                width: mobile ? double.infinity : 200,
                child: lab('تاريخ التفريدة المعتمدة', ImdDateField(value: _acDate, onChanged: (v) => setState(() => _acDate = v))),
              ),
              SizedBox(
                width: mobile ? double.infinity : 260,
                child: lab('إجمالي عدد الأفراد (اتركه فارغًا للجلب التلقائي)',
                    ImdFld(controller: _acHead, number: true, hint: 'تلقائي من التفريدة')),
              ),
              SizedBox(
                width: mobile ? double.infinity : 160,
                child: lab('مدة الإعاشة (أيام)', ImdFld(controller: _acDays, number: true)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 19),
                child: ImdButton(label: 'احتساب الأصناف تلقائيًا', icon: 'calculator', onPressed: _autoCalc),
              ),
            ]),
          ]),
        ),
      for (final (i, r) in _rows.indexed) KeyedSubtree(key: r.key, child: _rowView(context, i + 1, r)),
      ImdValidationBox(title: 'فحص سريع قبل إرسال أمر التحويل', items: _validate()),
    ];
  }

  Widget _whSelect(String value, List<Warehouse> opts, ValueChanged<String> on) => ImdSelect<String>(
        value: value,
        items: opts.isEmpty
            ? [('', Perm.of(context).scope == null ? '— لا مستودعات —' : '— لا توجد مستودعات ضمن نطاقك —')]
            : [for (final w in opts) (w.name, '${w.code.isNotEmpty ? '${w.code} — ' : ''}${w.name}')],
        onChanged: (v) => on(v ?? ''),
      );


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

  Widget _rowView(BuildContext context, int index, _Row r) {
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final narrow = MediaQuery.sizeOf(context).width <= 768;
    final meta = it == null
        ? ''
        : () {
            final b = displayBalance(it, _from.isNotEmpty ? (_fromBal[it.id] ?? 0) : it.qty);
            return _from.isNotEmpty
                ? 'رصيد «$_from»: ${nf(b.qty)} ${b.unit}'
                : 'الرصيد الكلي: ${nf(b.qty)} ${b.unit}';
          }();
    final picker = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الصنف'),
      ImdItemPicker(items: _items, value: r.itemId, onChanged: (v) => _onItem(r, v)),
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
          if (!has) _autoConsolidate();
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
          _rows.remove(r);
          r.qty.dispose();
          if (_rows.isEmpty) _rows.add(_Row());
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

  // ───────────────────────── بانتظار الاستلام ─────────────────────────
  Future<void> _loadPending() async {
    setState(() => _pending = null);
    final rows = await (_db.select(_db.transfers)..where((t) => t.status.equals('PENDING'))).get();
    if (mounted) setState(() => _pending = rows);
  }

  Map<String, List<Transfer>> _group(List<Transfer> docs) {
    final g = <String, List<Transfer>>{};
    for (final d in docs) {
      g.putIfAbsent(d.refNo.isNotEmpty ? d.refNo : '_${d.id}', () => []).add(d);
    }
    return g;
  }

  Widget _pendingView(BuildContext context) {
    final docs = _pending;
    if (docs == null) return const ImdLd('جارٍ تحميل التحويلات المعلقة…');
    final groups = _group(docs);
    if (groups.isEmpty) return const ImdICard(child: ImdLdText('لا توجد تحويلات معلقة حاليًا 👌'));
    final w = Perm.of(context).writable('transfer');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdChipsRow(children: [ImdChip('معلّقة: ${nf(groups.length)}', tone: ImdTone.pend)]),
      for (final e in groups.entries)
        ImdDocCard(
          head: [
            ImdChip(e.key, tone: ImdTone.code),
            ImdChip('${e.value.first.warehouse} ← ${e.value.first.destWarehouse}', tone: ImdTone.off),
            ImdChip(e.value.first.date.isEmpty ? '—' : e.value.first.date, tone: ImdTone.pend),
            ImdChip('${nf(e.value.length)} صنف', tone: ImdTone.ok),
          ],
          body: ImdDocLines([for (final x in e.value) (x.itemName, x.qty, x.unitName)]),
          actions: w
              ? [
                  ImdButton(label: 'استلام وتأكيد التحويل', icon: 'check', small: true, onPressed: () => _receive(e.key, e.value)),
                  ImdButton(label: 'رفض التحويل', icon: 'x', small: true, kind: ImdBtnKind.danger, onPressed: () => _reject(e.key, e.value)),
                ]
              : null,
        ),
    ]);
  }

  Future<void> _receive(String k, List<Transfer> g) async {
    // النطاق: الاستلام يتطلب أن يكون مستودع الوصول ضمن نطاق المستخدم.
    final perm = Perm.of(context);
    if (!perm.canWh(g.first.destWarehouse)) return showImdToast(context, Perm.scopeBlock(g.first.destWarehouse));
    // الاستلام يزيد رصيد المستودع الهدف، فيُمنع إن كان مجمّدًا بأمر جرد كبقية الحركات.
    final frozen = await _moves.frozenMessage(g.first.destWarehouse);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    if (!await imdConfirm(context, 'تأكيد استلام التحويل «$k» في المستودع الهدف؟')) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.update(_db.transfers)..where((t) => t.id.equals(d.id)))
              .write(TransfersCompanion(status: const Value('RECEIVED'), notes: Value(d.notes)));
        }
      });
      await AuditRepo(_db).write('TRANSFER_RECEIVED', 'transfer', 'تأكيد استلام تحويل مخزني',
          details: {
            'refNo': k,
            'warehouse': g.first.warehouse,
            'target': g.first.destWarehouse,
            'status': 'RECEIVED',
            'itemCount': g.length,
            'totalBaseQty': g.fold<double>(0, (a, b) => a + b.baseQty),
            'risk': 'sensitive',
          },
          actor: actor);
      if (mounted) showImdToast(context, '✔ تم تأكيد الاستلام — أُغلق التحويل');
      await _loadPending();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _reject(String k, List<Transfer> g) async {
    final perm = Perm.of(context);
    if (!perm.canWh(g.first.destWarehouse)) return showImdToast(context, Perm.scopeBlock(g.first.destWarehouse));
    final reason = await imdPrompt(context, 'سبب رفض التحويل:');
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.update(_db.transfers)..where((t) => t.id.equals(d.id)))
              .write(TransfersCompanion(status: const Value('REJECTED'), rejectReason: Value(reason.trim())));
        }
      });
      await AuditRepo(_db).write('TRANSFER_REJECTED', 'transfer', 'رفض تحويل مخزني',
          details: {
            'refNo': k,
            'warehouse': g.first.warehouse,
            'target': g.first.destWarehouse,
            'status': 'REJECTED',
            'itemCount': g.length,
            'reason': reason.trim(),
            'risk': 'sensitive',
          },
          actor: actor);
      if (mounted) showImdToast(context, '✖ رُفض التحويل');
      await _loadPending();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  // ───────────────────────── السجل ─────────────────────────

}
