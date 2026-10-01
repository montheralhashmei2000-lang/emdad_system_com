import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/print/voucher_print.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_screen_actions.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/documents_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/line_consolidation.dart';
import '../../domain/cylinders.dart';
import '../documents/doc_log_view.dart';
import 'doc_kit.dart';

/// استلام بضاعة — نقل مطابق لـ `renderReceive()`: سند الوارد الجديد، المسودات، السجل.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

/// سطر صنفٍ في سند الوارد.
class _Row {
  _Row({this.itemId = '', this.unit = '', double? qty, this.cy = 'RECEIVE_FULL', this.expiry = '', this.noAuto = false})
      : qty = TextEditingController(text: qty == null ? '' : _num(qty));
  String itemId;
  String unit;
  final TextEditingController qty;
  String cy;

  /// تاريخ انتهاء صلاحية الدفعة (اختياري).
  String expiry;
  bool noAuto;
  final key = UniqueKey();
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// لقطة بيانات سند الوارد الكاملة — تُستخدم لتعليق السند الحالي عند فتح
/// سندٍ جديد، والعودة إليه لاحقًا داخل نفس الجلسة.
class _ReceiveSnapshot {
  _ReceiveSnapshot({
    required this.wh,
    required this.sup,
    required this.date,
    required this.ref,
    required this.c1,
    required this.c2,
    required this.c3,
    required this.inv,
    required this.notes,
    required this.rows,
  });
  final String wh, sup, date, ref, c1, c2, c3, inv, notes;
  final List<Map<String, Object>> rows;
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);

  String _tab = 'form';

  // RC
  List<Item> _items = const [];
  List<Supplier> _sups = const [];
  List<Warehouse> _whs = const [];
  bool _ready = false;
  bool _busy = false;

  /// يُقرأ من الإعدادات: مخزنٌ بلا موادّ تنتهي لا يحتاج العمود.
  bool _showExpiry = true;
  String _loadedDraftRef = '';
  Map<String, double> _whBal = const {};

  // النموذج
  String _wh = '';
  String _sup = '';
  String _date = imdToday();
  String _ref = '';
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _c3 = TextEditingController();
  final _inv = TextEditingController();
  final _notes = TextEditingController();
  final List<_Row> _rows = [];

  // المسودات والسجل
  List<Receipt>? _drafts;

  // سندات معلّقة داخل الجلسة (تبويب «سند جديد»)
  final List<ImdDocTab<_ReceiveSnapshot>> _suspended = [];
  int _tabSeq = 1;
  int _activeTabId = 0;

  ImdScreenActions? _screenActions;

  @override
  void initState() {
    super.initState();
    _form();
    _loadPrefs();
    _screenActions = ImdScreenActions.maybeOf(context)
      ?..register(
        onSave: () {
          if (!_busy) _save(true);
        },
        onPrint: () {
          if (!_busy) _print();
        },
        onNewDoc: _openNewTab,
        onRefresh: () => _form(keepValues: true),
      );
  }

  Future<void> _loadPrefs() async {
    final id = await SettingsRepo(_db).identity();
    if (mounted) setState(() => _showExpiry = id.showExpiry);
  }

  @override
  void dispose() {
    _screenActions?.clear();
    for (final c in [_c1, _c2, _c3, _inv, _notes]) {
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
    if (t == 'drafts') _loadDrafts();
  }

  // ─────────────────────── تبويبات السندات المعلّقة ───────────────────────
  String _activeTabLabel() => _ref.isNotEmpty ? _ref : 'سند بلا رقم';

  _ReceiveSnapshot _captureSnapshot() => _ReceiveSnapshot(
        wh: _wh,
        sup: _sup,
        date: _date,
        ref: _ref,
        c1: _c1.text,
        c2: _c2.text,
        c3: _c3.text,
        inv: _inv.text,
        notes: _notes.text,
        rows: [
          for (final r in _rows)
            {
              'itemId': r.itemId,
              'unit': r.unit,
              'qty': r.qty.text,
              'cy': r.cy,
              'expiry': r.expiry,
              'noAuto': r.noAuto,
            },
        ],
      );

  void _restoreSnapshot(_ReceiveSnapshot s) {
    for (final r in _rows) {
      r.qty.dispose();
    }
    setState(() {
      _wh = s.wh;
      _sup = s.sup;
      _date = s.date;
      _ref = s.ref;
      _c1.text = s.c1;
      _c2.text = s.c2;
      _c3.text = s.c3;
      _inv.text = s.inv;
      _notes.text = s.notes;
      _loadedDraftRef = '';
      _rows
        ..clear()
        ..addAll([
          for (final r in s.rows)
            _Row(
              itemId: r['itemId'] as String,
              unit: r['unit'] as String,
              qty: double.tryParse(r['qty'] as String),
              cy: r['cy'] as String,
              expiry: r['expiry'] as String,
              noAuto: r['noAuto'] as bool,
            ),
        ]);
    });
    _refreshBal();
  }

  /// زر «سند جديد»: يعلّق السند الحالي في تبويبٍ جانبي ويفتح سندًا فارغًا.
  void _openNewTab() {
    final snap = _captureSnapshot();
    setState(() {
      _suspended.add(ImdDocTab<_ReceiveSnapshot>(id: _activeTabId, label: _activeTabLabel(), snapshot: snap));
      _activeTabId = _tabSeq++;
      _tab = 'form';
    });
    _form();
  }

  void _switchDocTab(int id) {
    if (id == _activeTabId) return;
    final idx = _suspended.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final target = _suspended.removeAt(idx);
    final current = ImdDocTab<_ReceiveSnapshot>(id: _activeTabId, label: _activeTabLabel(), snapshot: _captureSnapshot());
    setState(() {
      _suspended
        ..removeWhere((t) => t.id == target.id)
        ..add(current);
      _activeTabId = target.id;
      _tab = 'form';
    });
    _restoreSnapshot(target.snapshot);
  }

  void _closeDocTab(int id) => setState(() => _suspended.removeWhere((t) => t.id == id));

  // ───────────────────────── النموذج ─────────────────────────
  /// `rcFetchAll()` + `rcForm()`
  Future<void> _form({bool keepValues = false}) async {
    _loadedDraftRef = '';
    final perm = Perm.of(context);
    final items = await _catalog.items();
    final sups = await _catalog.suppliers()
      ..sort((a, b) => a.name.compareTo(b.name));
    final whs = (await _db.select(_db.warehouses).get()
          ..sort((a, b) => a.name.compareTo(b.name)))
        .where((w) => perm.canWh(w.name))
        .toList();
    final ref = await _moves.nextRef('receipts', 'و-');
    if (!mounted) return;
    setState(() {
      _items = items;
      _sups = sups;
      _whs = whs;
      if (!keepValues) {
        _wh = whs.isNotEmpty ? whs.first.name : '';
        _sup = sups.isNotEmpty ? sups.first.name : '';
        _date = imdToday();
        _ref = ref;
        for (final c in [_c1, _c2, _c3, _inv, _notes]) {
          c.clear();
        }
        for (final r in _rows) {
          r.qty.dispose();
        }
        _rows
          ..clear()
          ..add(_Row());
      }
      _ready = true;
    });
    await _refreshBal();
  }

  Future<void> _refreshBal() async {
    // بلا مستودع محدد: إجمالي مستودعات نطاق المستخدم من دفتر الحركات نفسه —
    // لا عمود `items.qty` القديم الذي لا يعرف المستودعات ولا الحركات.
    final b = await _moves.balances(warehouse: _wh, scope: Perm.of(context).scope);
    if (mounted) setState(() => _whBal = b);
  }

  Item? _item(String id) => _items.where((x) => x.id == id).firstOrNull;

  void _addRow([_Row? pre]) {
    // التجميع قبل فتح سطر جديد: هذا أحد موضعي الاستدعاء التلقائي.
    _autoConsolidate();
    setState(() => _rows.add(pre ?? _Row()));
  }

  /// دفعةٌ أخرى من الصنف نفسه: الصنف ووحدته وإجراء أسطوانته تُنسخ، والكمية
  /// وتاريخ الصلاحية يُتركان فارغين.
  ///
  /// تفريغ الكمية ليس كسلًا: [_autoConsolidate] يدمج السطور المتطابقة في
  /// المفتاح (صنف|أسطوانة|صلاحية) ويجمع كمياتها، فنسخةٌ كاملةٌ كانت ستُدمج في
  /// أصلها فورًا وتُضاعف كميته بدل أن تفتح سطرًا. والسطر بكميةٍ صفر يبقى
  /// «قيد الإكمال» فلا يمسّه الدمج حتى يكتبه المستخدم.
  void _copyRow(_Row r) {
    final at = _rows.indexOf(r);
    if (at < 0) return;
    setState(() => _rows.insert(at + 1, _Row(itemId: r.itemId, unit: r.unit, cy: r.cy, noAuto: true)));
  }

  void _onItem(_Row r, String id) {
    final it = _item(id);
    setState(() {
      r.itemId = id;
      final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
      r.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
      if (it != null && !r.noAuto && identical(_rows.last, r)) _rows.add(_Row());
    });
  }

  /// `rcCollect()`
  ({List<DocLineInput> rows, String err}) _collect() {
    final rows = <DocLineInput>[];
    final map = <String, int>{};
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _item(r.itemId);
      if (it == null) continue;
      if (r.unit.isEmpty) return (rows: rows, err: '✖ اختر وحدة قياس للصنف ${it.name}');
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) return (rows: rows, err: '✖ الكميات يجب أن تكون أكبر من صفر');
      final f = _catalog.factorOf(it, r.unit);
      final cy = it.isRefillable ? r.cy : '';
      // دفعتان بتاريخي صلاحية مختلفين سطران مختلفان.
      final key = '${r.itemId}|${r.unit}|$cy|${r.expiry}';
      if (!map.containsKey(key)) {
        map[key] = rows.length;
        rows.add(DocLineInput(
          itemId: r.itemId,
          itemCode: it.code,
          itemName: it.name,
          unitName: r.unit,
          factor: f,
          qty: qty,
          cylinderAction: cy,
          expiryDate: r.expiry,
        ));
      } else {
        final i = map[key]!;
        final o = rows[i];
        rows[i] = DocLineInput(
          itemId: o.itemId,
          itemCode: o.itemCode,
          itemName: o.itemName,
          unitName: o.unitName,
          factor: o.factor,
          qty: o.qty + qty,
          cylinderAction: o.cylinderAction,
          expiryDate: o.expiryDate,
        );
      }
    }
    return (rows: rows, err: '');
  }

  /// `rcMergeRows()`
  /// التجميع التلقائي وإعادة التوزيع على الوحدات.
  ///
  /// يحل محل زر «دمج التكرار» الذي أُزيل: يُستدعى عند مغادرة حقل الكمية وعند
  /// إضافة سطر جديد، فيجمع الصنف المتكرر بوحداته المختلفة ويعيد توزيعه
  /// (٥٠ كيس + ٩٠ كجم ⇒ ٥٢ كيس + ١٠ كجم). الأسطر غير المكتملة تُترك كما هي.
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

    String keyOf(_Row r) {
      final it = _item(r.itemId)!;
      return '${r.itemId}|${it.isRefillable ? r.cy : ''}|${r.expiry}';
    }

    final consolidated = consolidateLines([
      for (final r in complete)
        LineQty(
          groupKey: keyOf(r),
          unitName: r.unit,
          factor: _catalog.factorOf(_item(r.itemId)!, r.unit),
          qty: double.parse(r.qty.text.trim()),
        ),
    ]);

    // لا إعادة بناء بلا تغيير: إتلاف المتحكّمات يفقد موضع المؤشر بلا داعٍ.
    final before = [for (final r in complete) '${keyOf(r)}|${r.unit}|${r.qty.text.trim()}'];
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
            _Row(
              itemId: l.groupKey.split('|')[0],
              unit: l.unitName,
              qty: l.qty,
              cy: l.groupKey.split('|')[1].isEmpty ? 'RECEIVE_FULL' : l.groupKey.split('|')[1],
              expiry: l.groupKey.split('|')[2],
              noAuto: true,
            ),
          ...pending,
        ]);
      if (_rows.isEmpty) _rows.add(_Row());
    });
  }

  /// `rcScanGo()`
  void _scan(String code) {
    final it = _items.where((x) => x.barcode == code || x.code == code).firstOrNull;
    if (it == null) return showImdToast(context, '✖ الباركود/الكود ($code) غير معرّف');
    for (final r in _rows) {
      if (r.itemId == it.id) {
        r.qty.text = _num((double.tryParse(r.qty.text) ?? 0) + 1);
        _autoConsolidate();
        return;
      }
    }
    final row = _Row(itemId: it.id, qty: 1);
    final units = _catalog.unitsOf(it);
    row.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
    setState(() {
      // يحل محل السطر الفارغ الأخير كي يبقى سطر فارغ واحد في النهاية.
      _rows.add(row);
      if (_rows.last.itemId.isNotEmpty) _rows.add(_Row());
    });
    showImdToast(context, '➕ أُضيف: ${it.name}');
  }

  /// `rcValidateLive()`
  List<ImdCheck> _validate() {
    final items = <ImdCheck>[];
    final c = _collect();
    if (_wh.isEmpty) items.add(const ImdCheck('warn', 'المستودع غير محدد', 'اختَر المستودع الذي ستدخل عليه الكميات قبل الحفظ.'));
    if (_sup.isEmpty) items.add(const ImdCheck('warn', 'المورّد غير محدد', 'اختَر الجهة الموردة لتجنب سند ناقص البيانات.'));
    if (imdIsFuture(_date)) items.add(const ImdCheck('err', 'تاريخ غير صالح', 'تاريخ سند الوارد لا يمكن أن يكون في المستقبل.'));
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في الأصناف', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل الحفظ أو الاعتماد.'));
    final expired = c.rows.where((r) => r.expiryDate.isNotEmpty && r.expiryDate.compareTo(_date) <= 0).toList();
    if (expired.isNotEmpty) {
      items.add(ImdCheck('warn', 'دفعة منتهية الصلاحية',
          '«${expired.first.itemName}» تنتهي صلاحيته في تاريخ السند أو قبله — تأكد من التاريخ قبل الاستلام.'));
    }
    if (imdDuplicateCount(c.rows, (r) => '${r.itemId}|${r.unitName}|${r.cylinderAction}') > 0) {
    }
    if (c.rows.isNotEmpty) {
      items.add(ImdCheck('ok', 'ملخص سريع',
          'عدد السطور الفعلية: ${nf(c.rows.length)} — إجمالي الكميات الأساسية: ${nf(c.rows.fold<double>(0, (a, b) => a + b.baseQty))}'));
    }
    return items;
  }

  /// `rcSave(draft)`
  Future<void> _save(bool draft) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'receive', draft ? 'create' : 'approve')) return;
    if (_wh.isNotEmpty && !perm.canWh(_wh)) return showImdToast(context, Perm.scopeBlock(_wh));
    final frozen = await _moves.frozenMessage(_wh);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    if (_wh.isEmpty) return showImdToast(context, '✖ اختر المستودع (أو أضف واحدًا بزر ➕)');
    if (_sup.isEmpty) return showImdToast(context, '✖ اختر الجهة الموردة');
    if (_date.isEmpty) return showImdToast(context, '✖ اختر تاريخ السند');
    if (imdIsFuture(_date)) return showImdToast(context, '✖ تاريخ السند لا يمكن أن يكون في المستقبل');
    if (_ref.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    final c = _collect();
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ القائمة فارغة — أضف صنفًا واحدًا على الأقل');
    setState(() => _busy = true);
    try {
      final conflict = await _moves.hasRefConflict('receipts', _ref, 'DRAFT');
      if (!mounted) return;
      if (conflict && _loadedDraftRef != _ref) {
        return showImdToast(context, '✖ يوجد سند وارد سابق بنفس المرجع — غيّر المرجع أو راجع السجل');
      }
      if (!draft && !await imdConfirm(context, 'اعتماد السند النهائي؟\nستُضاف الكميات إلى الأرصدة ولا يمكن التراجع.')) {
        return;
      }
      if (!mounted) return;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveReceipt(
        warehouse: _wh,
        supplier: _sup,
        date: _date,
        lines: c.rows,
        refNo: _ref,
        invoiceNo: _inv.text.trim(),
        committee: _c1.text.trim(),
        supervision: _c2.text.trim(),
        audit: _c3.text.trim(),
        notes: _notes.text.trim(),
        draft: draft,
        replaceDraft: _loadedDraftRef == _ref,
        createdBy: actor?.email ?? '',
        actor: actor,
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      if (!mounted) return;
      _loadedDraftRef = '';
      showImdToast(context, draft ? '💾 حُفظت المسودة — لم تُؤثر على الأرصدة' : '🎉 تم الاستلام وإضافة الأرصدة بنجاح');
      await _form();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// زر ➕ بجانب المستودع/المورد (`addQ`).
  Future<void> _quickAdd(bool warehouse) async {
    final n = await imdPrompt(context, 'اسم ${warehouse ? 'المستودع' : 'مورد'} الجديد:');
    if (n == null || n.trim().isEmpty || !mounted) return;
    try {
      if (warehouse) {
        await _db.into(_db.warehouses).insert(WarehousesCompanion.insert(id: Ids.next('wh'), name: n.trim()));
      } else {
        await _db.into(_db.suppliers).insert(SuppliersCompanion.insert(id: Ids.next('sup'), name: n.trim()));
      }
      if (!mounted) return;
      showImdToast(context, '✔ أُضيف: ${n.trim()}');
      await _form();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  void _print() {
    final c = _collect();
    if (c.rows.isEmpty) {
      showImdToast(context, '✖ لا توجد أصناف للطباعة${c.err.isNotEmpty ? ' — ${c.err}' : ''}');
      return;
    }
    VoucherPrint.print(
      db: _db,
      title: 'سند توريد مخزني',
      kind: VoucherKind.receive,
      refNo: _ref,
      date: _date,
      warehouse: _wh,
      party: _sup,
      notes: _notes.text.trim(),
      invoiceNo: _inv.text.trim(),
      audit: _c3.text.trim(),
      supervision: _c2.text.trim(),
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
      ImdPageTitle(
        title: 'استلام بضاعة',
        icon: 'download',
        subtitle: 'سند توريد مخزني — اعتماد فوري أو مسودة + سجل الواردات السابقة',
        actions: [
          ImdButton.outline(label: 'سند جديد', icon: 'plus-square', small: true, onPressed: _openNewTab),
          ImdItabs(
            value: _tab,
            onChanged: _switch,
            tabs: const [
              ImdTab('form', 'سند الوارد الجديد', icon: 'file'),
              ImdTab('drafts', 'المسودات', icon: 'save'),
              ImdTab('hist', 'السجل', icon: 'file'),
            ],
          ),
        ],
      ),
      if (_suspended.isNotEmpty)
        ImdDocTabsBar<_ReceiveSnapshot>(
          activeLabel: _activeTabLabel(),
          suspended: _suspended,
          onSelect: _switchDocTab,
          onClose: _closeDocTab,
        ),
    ];
    if (_tab == 'form') {
      final w = Perm.of(context).writable('receive');
      if (!_ready) return ImdPage(children: [...head, const ImdLd('جارٍ التهيئة…')]);
      if (!w) {
        return ImdPage(children: [
          ...head,
          const ImdICard(
            title: 'عرض فقط',
            icon: 'eye',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: ImdLdText('تسجيل السندات متاح لمدير النظام — راجع تبويب «📜 السجل»'),
            ),
          ),
        ]);
      }
      return ImdStickyPage(
        sticky: ImdStickyActions(
          caption: 'تنبيه: الاعتماد النهائي يضيف الكميات مباشرة إلى الرصيد',
          children: [
            ImdButton.outline(label: '+ سطر جديد', small: true, onPressed: _busy ? null : () => _addRow()),
            ImdButton.outline(label: 'طباعة سند التوريد', icon: 'printer', small: true, onPressed: _busy ? null : _print),
            _OrangeButton(label: 'حفظ كمسودة', busy: _busy, onPressed: () => _save(true)),
            ImdButton(label: 'اعتماد وتسجيل سند الوارد', icon: 'check', busy: _busy, onPressed: () => _save(false)),
          ],
        ),
        children: [...head, ..._formBody(context)],
      );
    }
    return ImdPage(children: [...head, if (_tab == 'drafts') _draftsView(context) else const DocLogView(kinds: {DocKind.receipt}, embedded: true)]);
  }

  List<Widget> _formBody(BuildContext context) {
    final mobile = ImdBp.of(context).mobile;
    Widget selWithAdd(String label, String value, List<(String, String)> opts, String empty, ValueChanged<String> on, bool wh) =>
        ImdLabeled(
          label,
          ImdInputGroup(
            field: ImdSelect<String>(
              value: value,
              items: opts.isEmpty ? [('', empty)] : opts,
              onChanged: (v) => on(v ?? ''),
            ),
            button: ImdIconButton(icon: 'plus', onPressed: () => _quickAdd(wh)),
          ),
          size: 11,
        );
    final whField = selWithAdd(
      'التخزين في (المستودع) *',
      _wh,
      [for (final w in _whs) (w.name, '${w.code.isNotEmpty ? '${w.code} — ' : ''}${w.name}')],
      Perm.of(context).scope == null ? '— لا مستودعات —' : '— لا توجد مستودعات ضمن نطاقك —',
      (v) {
        setState(() => _wh = v);
        _refreshBal();
      },
      true,
    );
    final supField = selWithAdd(
      'الجهة الموردة *',
      _sup,
      [for (final s in _sups) (s.name, s.name)],
      '— لا موردين —',
      (v) => setState(() => _sup = v),
      false,
    );
    final dateField = ImdLabeled('تاريخ التوريد', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)), size: 11);
    // حقل للقراءة فقط: لا يُنشأ له TextEditingController في كل بناء
    // (المتحكّم الجديد يحمل تحديدًا غير صالح فيرمي الإطار assert isValid).
    final refField = ImdLabeled('المرجع (سند)', ImdReadonlyField(text: _ref), size: 11);
    Widget fld(String l, TextEditingController ctrl) => ImdLabeled(l, ImdFld(controller: ctrl), size: 11);

    final collected = _collect();
    final activeStep = (_wh.isEmpty || _sup.isEmpty || imdIsFuture(_date))
        ? 0
        : !_rows.any((r) => r.itemId.isNotEmpty)
            ? 1
            : (collected.err.isNotEmpty || _validate().any((x) => x.level == 'err'))
                ? 2
                : 3;

    return [
      ImdGuidePanel(
        child: ImdSoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdWorkflowSteps(
              const ['بيانات السند', 'إضافة الأصناف', 'مراجعة وطباعة', 'حفظ مسودة أو اعتماد نهائي'],
              activeIndex: activeStep,
              hints: const [
                'حدد المستودع والجهة الموردة، وتأكد أن تاريخ التوريد ليس في المستقبل.',
                'أضف صنفًا واحدًا على الأقل وحدد وحدته وكميته.',
                'راجع الكميات وتواريخ الصلاحية والتكرارات قبل الحفظ.',
                'اكتمل التحقق. احفظ كمسودة، أو اعتمد السند نهائيًا لإدخال الكميات للمخزون.',
              ],
            ),
            ImdQuickGrid([
              ('الأصناف المتاحة', nf(_items.length)),
              ('الموردون', nf(_sups.length)),
              ('المستودعات', nf(_whs.length)),
            ]),
            const ImdPrintTip('لو السند لسه غير مكتمل: احفظه كمسودة الأول. ولو جاهز للمخزون الفعلي: استخدم الاعتماد النهائي مرة واحدة فقط.'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ImdICard(
        title: 'بيانات السند الرئيسية',
        icon: 'clipboard',
        child: ImdCompact(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdFormGrid(children: [whField, supField, dateField, refField]),
          const SizedBox(height: ImdSizes.compactRowGap),
          ImdFormGrid(children: [
            fld('لجنة الفحص (رقابة)', _c1),
            fld('المراجعة والتفتيش', _c2),
            fld('التدقيق', _c3),
            fld('رقم الفاتورة/التاجر', _inv),
          ]),
          const SizedBox(height: ImdSizes.compactRowGap),
          ImdCollapsibleSection(title: 'ملاحظات', child: ImdFld(controller: _notes)),
        ])),
      ),
      ImdICard(
        title: 'ماسح الباركود / الإضافة السريعة',
        icon: 'tag',
        child: ImdBarcodeInput(hint: 'مرّر قارئ الباركود أو اكتب الكود ثم Enter…', onSubmit: _scan),
      ),
      if (mobile)
        for (final (i, r) in _rows.indexed) KeyedSubtree(key: r.key, child: _rowView(context, i + 1, r))
      else
        _desktopTable(context),
      ImdValidationBox(title: 'فحص سريع قبل حفظ سند الوارد', items: _validate()),
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

  /// الحقول التفاعلية لسطر صنفٍ واحد — بلا عنوانٍ فوقها ولا تخطيط: المصدر
  /// الوحيد لمنطق الإدخال، يستهلكه عرض الجوال (بطاقةٌ معنونة) وجدول سطح
  /// المكتب (خليةٌ عاريةٌ تحت رأسٍ مشترك) كلاهما بلا تكرار سطرٍ واحد.
  ({
    bool refill,
    bool hasExpiry,
    String meta,
    Widget balance,
    Widget picker,
    Widget unit,
    Widget qty,
    Widget cy,
    Widget expiry,
    Widget copy,
    Widget delete,
  }) _rowFields(_Row r) {
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final meta = it == null
        ? ''
        : (_wh.isNotEmpty
            ? () {
                final b = displayBalance(it, _whBal[it.id] ?? 0);
                return 'رصيد «$_wh»: ${nf(b.qty)} ${b.unit}';
              }()
            : () {
                final b = displayBalance(it, _whBal[it.id] ?? 0);
                return 'الرصيد: ${nf(b.qty)} ${b.unit}'
                    '${it.barcode.isNotEmpty ? ' • باركود: ${it.barcode}' : ''}';
              }());
    final picker = ImdItemPicker(
      items: _items,
      value: r.itemId,
      onChanged: (v) => _onItem(r, v),
      detailOf: (i) {
        final b = displayBalance(i, _whBal[i.id] ?? 0);
        return 'رصيد ${nf(b.qty)} ${b.unit}';
      },
    );
    // رصيد المستودع المختار — عمودٌ في الجدول لا سطرٌ تحت اسم الصنف: العين
    // تمسحه في عمودٍ واحد مع بقية الأرقام. ثانويٌّ فخطّه أصغر ولونه أهدأ.
    final balance = ImdEntryBalanceCell(
      it == null ? '' : () {
        final b = displayBalance(it, _whBal[it.id] ?? 0);
        return '${nf(b.qty)} ${b.unit}';
      }(),
    );
    final unit = ImdUnitPicker(
      units: [for (final u in units) u.name],
      value: r.unit,
      onChanged: (v) => setState(() {
        // تغيير الوحدة يعيد احتساب الكمية بثبات الكمية بالوحدة الأساسية:
        // ١١٠٠ كجم ⇒ ٢٧٫٥ كيسًا، لا ١١٠٠ كيسًا.
        final next = v;
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
    );
    // مغادرة الحقل تجمع الأصناف المكررة تلقائيًا وتعيد توزيع الوحدات.
    final qty = Focus(
      onFocusChange: (has) {
        if (!has) _autoConsolidate();
      },
      child: ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
    );
    // الأسطوانات أصول تُعبّأ لا مواد تنتهي، فلا صلاحية لها. ويُخفى العمود
    // كذلك إن أُطفئ من الإعدادات.
    final hasExpiry = _showExpiry && it != null && !it.isRefillable;
    // **نوع العملية في صفّ الصنف لا تحته.** صندوقٌ مستقل يستقطع سطرًا
    // لكل أسطوانة، ويقطع تسلسل `Tab` من الكمية إلى التاريخ.
    final refill = it != null && it.isRefillable;
    final cy = ImdSelect<String>(
      value: r.cy,
      items: CylAction.receiveOptions,
      onChanged: (v) => setState(() => r.cy = v ?? r.cy),
    );
    final expiry = Row(children: [
      Expanded(child: ImdDateField(value: r.expiry, onChanged: (v) => setState(() => r.expiry = v))),
      if (r.expiry.isNotEmpty)
        ImdIconButton(icon: 'x', tooltip: 'بلا صلاحية', onPressed: () => setState(() => r.expiry = '')),
    ]);
    final copy = r.itemId.isEmpty
        ? const SizedBox.shrink()
        : ImdIconButton(
            icon: 'plus-square',
            tooltip: 'دفعة أخرى من هذا الصنف',
            onPressed: () => _copyRow(r),
          );
    final delete = ImdIconButton(
      icon: 'x',
      kind: ImdBtnKind.danger,
      onPressed: () => setState(() {
        _rows.remove(r);
        if (_rows.isEmpty) _rows.add(_Row());
      }),
    );
    return (
      refill: refill,
      hasExpiry: hasExpiry,
      balance: balance,
      meta: meta,
      picker: picker,
      unit: unit,
      qty: qty,
      cy: cy,
      expiry: expiry,
      copy: copy,
      delete: delete,
    );
  }

  /// عرض الجوال: بطاقةٌ معنونة لكل صنف — العناوين فوق حقولها لأن الشاشة
  /// الضيّقة لا تتّسع لرأس جدولٍ يبقى ذا معنى.
  Widget _rowView(BuildContext context, int index, _Row r) {
    final f = _rowFields(r);
    Widget labeled(String label, Widget field) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ImdRowLabel(label), field]);
    return ImdRvRow(
      index: index,
      trailing: _baseHint(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ImdRowLabel('الصنف'),
              f.picker,
              ImdRowMeta(f.meta),
            ]),
          ),
          const SizedBox(width: ImdSizes.compactGap),
          SizedBox(width: 104, child: labeled('الوحدة', f.unit)),
        ]),
        const SizedBox(height: ImdSizes.compactGap),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: labeled('الكمية', f.qty)),
          if (f.refill) ...[
            const SizedBox(width: ImdSizes.compactGap),
            Expanded(child: labeled('نوع العملية', f.cy)),
          ],
          if (f.hasExpiry) ...[
            const SizedBox(width: ImdSizes.compactGap),
            Expanded(child: labeled('تاريخ الانتهاء', f.expiry)),
          ],
          const SizedBox(width: ImdSizes.compactGap),
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Row(mainAxisSize: MainAxisSize.min, children: [f.copy, f.delete]),
          ),
        ]),
      ]),
    );
  }

  /// عرض سطح المكتب: جدولٌ كثيف برأسٍ ثابتٍ بلون التمييز — عمودا «نوع
  /// العملية» و«تاريخ الانتهاء» شرطيّان على مستوى الجدول كله لا السطر
  /// الواحد: يظهر العمود إن احتاجه **أي** صفٍّ حاليًّا، وتبقى خليته فارغةً
  /// فيما عداه من الصفوف — فلا تتغيّر أعمدة الجدول وهي تُقرأ.
  Widget _desktopTable(BuildContext context) {
    final fields = [for (final r in _rows) _rowFields(r)];
    final anyRefill = fields.any((f) => f.refill);
    final anyExpiry = fields.any((f) => f.hasExpiry);
    const cell = ImdEntryTable.cell;

    return ImdEntryTable(
      columns: [
        const ImdCol('الصنف', flex: 3),
        const ImdCol('الرصيد', width: 96),
        const ImdCol('الوحدة', width: 112),
        const ImdCol('الكمية', width: 88),
        if (anyRefill) const ImdCol('نوع العملية', width: 150),
        if (anyExpiry) const ImdCol('تاريخ الانتهاء', width: 150),
        // زرّا النسخ والحذف معًا (وحدة النسخ لا تظهر إلا بعد اختيار صنف):
        // ٦٤px محتوًى لا تكفيهما، فطفح تخطيطٌ بـ١٤px عند أول اختبار.
        const ImdCol('', width: 96),
      ],
      rowKeys: [for (final r in _rows) r.key],
      rows: [
        for (final f in fields)
          [
            cell(f.picker),
            cell(f.balance),
            cell(f.unit),
            cell(f.qty),
            if (anyRefill) cell(f.refill ? f.cy : const SizedBox.shrink()),
            if (anyExpiry) cell(f.hasExpiry ? f.expiry : const SizedBox.shrink()),
            ImdEntryTable.actions([f.copy, f.delete]),
          ],
      ],
    );
  }

  // ───────────────────────── المسودات ─────────────────────────
  Future<void> _loadDrafts() async {
    setState(() => _drafts = null);
    final rows = await (_db.select(_db.receipts)..where((t) => t.status.equals('DRAFT'))).get();
    if (mounted) setState(() => _drafts = rows);
  }

  Map<String, List<Receipt>> _group(List<Receipt> docs) {
    final g = <String, List<Receipt>>{};
    for (final d in docs) {
      g.putIfAbsent(d.refNo.isNotEmpty ? d.refNo : '_${d.id}', () => []).add(d);
    }
    return g;
  }

  Widget _draftsView(BuildContext context) {
    final docs = _drafts;
    if (docs == null) return const ImdLd('جارٍ تحميل المسودات…');
    final groups = _group(docs);
    if (groups.isEmpty) return const ImdICard(child: ImdLdText('لا توجد مسودات محفوظة 👌'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdChipsRow(children: [ImdChip('مسودات: ${nf(groups.length)}', tone: ImdTone.code)]),
      for (final e in groups.entries)
        ImdDocCard(
          head: [
            ImdChip(e.key, tone: ImdTone.code),
            Text(e.value.first.supplier.isEmpty ? '—' : e.value.first.supplier, style: const TextStyle(fontWeight: FontWeight.w700)),
            ImdChip(e.value.first.date.isEmpty ? '—' : e.value.first.date, tone: ImdTone.off),
            ImdChip('${nf(e.value.length)} صنف', tone: ImdTone.ok),
            ImdDocWarehouse(e.value.first.warehouse, icon: 'building'),
          ],
          actions: [
            ImdButton.outline(label: 'عرض في السند', icon: 'eye', small: true, onPressed: () => _loadDraft(e.value)),
            ImdButton(label: 'اعتماد وتسجيل', icon: 'check', small: true, onPressed: () => _approveDraft(e.key, e.value)),
            ImdButton(label: 'حذف', icon: 'trash', small: true, kind: ImdBtnKind.danger, onPressed: () => _deleteDraft(e.key, e.value)),
          ],
        ),
    ]);
  }

  Future<bool> _scopeOk(String wh) async {
    final perm = Perm.of(context);
    if (!perm.canWh(wh)) {
      showImdToast(context, Perm.scopeBlock(wh));
      return false;
    }
    return true;
  }

  Future<void> _approveDraft(String k, List<Receipt> g) async {
    if (!Perm.of(context).guard(context, 'receive', 'approve')) return;
    if (!await _scopeOk(g.first.warehouse) || !mounted) return;
    if (!await imdConfirm(context, 'اعتماد المسودة $k وإضافة أرصدتها إلى الأصناف؟')) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      final res = await _moves.approveReceiptDraft(g, actor: actor);
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      showImdToast(context, '🎉 اعتُمدت المسودة وأُضيف الرصيد');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
      return;
    }
    await _loadDrafts();
  }

  Future<void> _deleteDraft(String k, List<Receipt> g) async {
    if (!await _scopeOk(g.first.warehouse) || !mounted) return;
    if (!await imdConfirm(context, 'حذف هذه المسودة نهائيًا؟', ok: 'حذف', danger: true)) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.delete(_db.receipts)..where((t) => t.id.equals(d.id))).go();
        }
      });
      await AuditRepo(_db).write('RECEIPT_DRAFT_DELETED', 'receipt', 'حذف مسودة وارد',
          details: {
            'refNo': k,
            'warehouse': g.first.warehouse,
            'target': g.first.supplier,
            'status': 'DELETED',
            'itemCount': g.length,
            'risk': 'sensitive',
          },
          actor: actor);
      if (mounted) showImdToast(context, '✔ حُذفت المسودة');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
      return;
    }
    await _loadDrafts();
  }

  /// `rcLoadDraft(g)`
  Future<void> _loadDraft(List<Receipt> g) async {
    await _form();
    if (!mounted) return;
    final f = g.first;
    setState(() {
      _ref = f.refNo;
      _date = f.date;
      imdSetText(_notes, f.notes);
      imdSetText(_inv, f.invoiceNo);
      imdSetText(_c1, f.committee);
      imdSetText(_c2, f.supervision);
      imdSetText(_c3, f.audit);
      if (_whs.any((w) => w.name == f.warehouse)) _wh = f.warehouse;
      if (_sups.any((s) => s.name == f.supplier)) _sup = f.supplier;
      for (final r in _rows) {
        r.qty.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final d in g)
            _Row(
              itemId: d.itemId,
              unit: d.unitName,
              qty: d.qty,
              cy: d.cylinderAction.isEmpty ? 'RECEIVE_FULL' : d.cylinderAction,
              expiry: d.expiryDate,
              noAuto: true,
            ),
        ]);
      if (_rows.isEmpty) _rows.add(_Row());
      _loadedDraftRef = f.refNo;
      _tab = 'form';
    });
    await _refreshBal();
    if (mounted) showImdToast(context, '📝 حُمّلت المسودة للتعديل');
  }

  // ───────────────────────── السجل ─────────────────────────

}

/// `<button class="btn" style="background:#f39c12;color:#fff">` — زر «حفظ كمسودة» البرتقالي.
class _OrangeButton extends StatefulWidget {
  const _OrangeButton({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  State<_OrangeButton> createState() => _OrangeButtonState();
}

class _OrangeButtonState extends State<_OrangeButton> {
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [
          context.imd.orangeAccent,
        ],
      ),
      child: ImdButton(label: widget.label, icon: 'save', busy: widget.busy, onPressed: widget.onPressed),
    );
  }
}
