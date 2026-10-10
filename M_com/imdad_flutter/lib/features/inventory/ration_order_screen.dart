import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_screen_actions.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../data/repos/ration_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/line_consolidation.dart';
import '../../domain/ration_order.dart';
import 'doc_kit.dart';
import '../../domain/print_forms.dart';

part 'ration_order/ration_approve_sheet.dart';


String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// طلبيات الإعاشة: فرعٌ يطلب من مستودع مورِّد، ثم تُعتمد وتُستلم.
///
/// الاستلام هنا ليس تعليمًا على ورقة: يولّد سند استلام حقيقي في المستودع
/// الطالب (انظر [RationRepo.receive])، فالرصيد يتحرك كما يتحرك بأي استلام آخر.
///
/// **والاعتماد قرارٌ لا تصديق.** المورِّد نادرًا ما يملك كل ما طُلب منه، فله
/// أن يقلّص الكمية سطرًا سطرًا — وهذا ما يفتحه [_ApproveSheet]. ولأن القرار
/// لا يصحّ على عمياء، يُعرض معه رصيدُ المورِّد الفعلي لكل صنف.
class RationOrderScreen extends StatefulWidget {
  const RationOrderScreen({super.key});

  @override
  State<RationOrderScreen> createState() => _RationOrderScreenState();
}

class _LineDraft {
  _LineDraft({this.itemId = '', double qty = 0, this.unit = '', String notes = ''})
      : qty = TextEditingController(text: qty > 0 ? '$qty' : ''),
        notes = TextEditingController(text: notes);

  String itemId;
  final TextEditingController qty;

  /// وحدة الطلب — فارغةٌ تعني وحدة الأساس (كما كان الحال دومًا قبل أن
  /// تُختار الوحدة صراحةً): الطلبية طلبٌ لا حركة، فلا تحويل وحداتٍ حقيقي
  /// يجري عليها، لكن الطالب قد يعرف كميته بوحدةٍ غير الأساس (كرتونًا لا
  /// كيلو) فيطلب بها مباشرةً بدل أن يحسبها بنفسه.
  String unit;

  /// ملاحظة السطر — سبب طلبٍ خاص أو ظرفٌ يخصّ هذا الصنف وحده.
  final TextEditingController notes;

  /// هوية السطر عبر إعادة البناء — بها يبقى متحكّمه وتركيزه لو حُذف سطرٌ
  /// قبله، بدل أن تُعاد بقية الأسطر من فهارسها الجديدة.
  final key = UniqueKey();

  void dispose() {
    qty.dispose();
    notes.dispose();
  }
}

class _RationOrderScreenState extends State<RationOrderScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final RationRepo _repo = RationRepo(_db);
  late final CatalogRepo _catalog = CatalogRepo(_db);

  List<RationOrder> _orders = const [];
  List<Warehouse> _warehouses = const [];
  List<Item> _items = const [];
  RationOrderFull? _open;

  /// رصيد المستودع المورِّد لكل صنف — يُقرأ كلما تغيّر المورِّد.
  ///
  /// بغيره يطلب الفرع ما ليس عند المورِّد، فتُقلَّص الطلبية عند الاعتماد بعد
  /// أن يكون قد اعتمد عليها في تخطيطه.
  Map<String, double> _supplyBal = const {};
  bool _balLoading = false;

  /// دليل الجهات واسم المخزن الرئيسي — بهما يُعرف من يطلب ممّن.
  List<SupplyAuthority> _authorities = const [];
  String _mainWh = '';

  String _kind = RationKind.branch;
  String _authorityId = '';

  final _notes = TextEditingController();
  final List<_LineDraft> _lines = [];

  String _requesting = '';
  String _supplying = '';
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  String _requiredDate = '';
  String _priority = RationPriority.normal;
  String _filterStatus = '';
  String? _editId;
  bool _loading = true;
  bool _busy = false;

  // طلبيات معلّقة داخل الجلسة (زر «طلبية جديدة»)
  final List<ImdDocTab<Map<String, dynamic>>> _suspended = [];
  int _tabSeq = 1;
  int _activeTabId = 0;

  ImdScreenActions? _screenActions;

  @override
  void initState() {
    super.initState();
    _ensureBlank();
    _render();
    _screenActions = ImdScreenActions.maybeOf(context)
      ?..register(
        onSave: () {
          if (!_busy) _save();
        },
        onNewDoc: _openNewTab,
        onRefresh: _render,
      );
  }

  @override
  void dispose() {
    _screenActions?.clear();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _render() async {
    final scope = Perm.of(context).scope;
    final orders = await _repo.orders(status: _filterStatus, scope: scope);
    final warehouses = await CatalogRepo(_db).warehouses();
    final items = await CatalogRepo(_db).items();
    final authorities = await _repo.authorities(onlyActive: true);
    final main = await _repo.mainWarehouseName();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _warehouses = warehouses;
      _items = items;
      _authorities = authorities;
      _mainWh = main;
      _loading = false;
    });
  }

  /// أرصدة مستودعٍ بعينه — تُستعمل للطالب عند البناء وللمورِّد عند الاعتماد.
  Future<Map<String, double>> _balancesOf(String warehouse) async {
    if (warehouse.trim().isEmpty) return const {};
    return MovementsRepo(_db).balances(warehouse: warehouse);
  }

  Future<void> _loadSupplyBalances() async {
    final wh = _supplying;
    if (wh.isEmpty) {
      setState(() => _supplyBal = const {});
      return;
    }
    setState(() => _balLoading = true);
    final bal = await _balancesOf(wh);
    if (!mounted || _supplying != wh) return;
    setState(() {
      _supplyBal = bal;
      _balLoading = false;
    });
  }

  /// سطرٌ فارغ في آخر الجدول دائمًا (كشاشة التحويل): جدول الإدخال لا يختفي،
  /// والسطر الأخير جاهزٌ للصنف التالي.
  void _ensureBlank() {
    if (_lines.isEmpty || _lines.last.itemId.isNotEmpty) _lines.add(_LineDraft());
  }

  /// السطور التي أدخل فيها المستخدم شيئًا — الفارغ (بلا صنف ولا كمية) لا
  /// يدخل التحقق ولا الحفظ، وإلا منع السطرُ الدائم الحفظَ («كل سطر يحتاج صنفًا»).
  List<_LineDraft> get _filled =>
      [for (final l in _lines) if (l.itemId.isNotEmpty || l.qty.text.trim().isNotEmpty) l];

  void _resetForm() {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    _ensureBlank();
    imdSetText(_notes, '');
    setState(() {
      _editId = null;
      _kind = RationKind.branch;
      _authorityId = '';
      _requesting = '';
      _supplying = '';
      _supplyBal = const {};
      _date = DateTime.now().toIso8601String().substring(0, 10);
      _requiredDate = '';
      _priority = RationPriority.normal;
    });
  }

  /// لقطة بيانات الطلبية الجاري تحريرها — لتعليقها في تبويبٍ جانبي.
  Map<String, dynamic> _captureDocSnapshot() => {
        'editId': _editId,
        'kind': _kind,
        'authorityId': _authorityId,
        'requesting': _requesting,
        'supplying': _supplying,
        'date': _date,
        'requiredDate': _requiredDate,
        'priority': _priority,
        'notes': _notes.text,
        'lines': [
          for (final l in _filled)
            {'itemId': l.itemId, 'qty': l.qty.text, 'unit': l.unit, 'notes': l.notes.text},
        ],
      };

  /// يكتب لقطةً محفوظةً من تبويبٍ معلّق رجوعًا إلى حقول النموذج.
  void _applySnapshot(Map<String, dynamic> data) {
    for (final l in _lines) {
      l.dispose();
    }
    setState(() {
      _editId = data['editId'] as String?;
      _kind = '${data['kind'] ?? RationKind.branch}';
      _authorityId = '${data['authorityId'] ?? ''}';
      _requesting = '${data['requesting'] ?? ''}';
      _supplying = '${data['supplying'] ?? ''}';
      _date = '${data['date'] ?? _date}';
      _requiredDate = '${data['requiredDate'] ?? ''}';
      _priority = '${data['priority'] ?? RationPriority.normal}';
      imdSetText(_notes, '${data['notes'] ?? ''}');
      final savedLines = data['lines'];
      _lines
        ..clear()
        ..addAll(savedLines is List
            ? [
                for (final v in savedLines.whereType<Map>())
                  _LineDraft(
                    itemId: '${v['itemId'] ?? ''}',
                    qty: double.tryParse('${v['qty'] ?? ''}') ?? 0,
                    unit: '${v['unit'] ?? ''}',
                    notes: '${v['notes'] ?? ''}',
                  ),
              ]
            : <_LineDraft>[]);
      _ensureBlank();
    });
    _loadSupplyBalances();
  }

  // ─────────────────────── تبويبات الطلبيات المعلّقة ───────────────────────
  String _activeTabLabel() => _requesting.isNotEmpty ? _requesting : 'طلبية بلا جهة';

  /// زر «طلبية جديدة»: يعلّق الطلبية الحالية في تبويبٍ جانبي ويفتح طلبية فارغة.
  void _openNewTab() {
    final snap = _captureDocSnapshot();
    setState(() {
      _suspended.add(ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: snap));
      _activeTabId = _tabSeq++;
    });
    _resetForm();
  }

  void _switchDocTab(int id) {
    if (id == _activeTabId) return;
    final idx = _suspended.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final target = _suspended.removeAt(idx);
    final current = ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: _captureDocSnapshot());
    setState(() {
      _suspended
        ..removeWhere((t) => t.id == target.id)
        ..add(current);
      _activeTabId = target.id;
    });
    _applySnapshot(target.snapshot);
  }

  void _closeDocTab(int id) => setState(() => _suspended.removeWhere((t) => t.id == id));

  Future<void> _edit(RationOrder o) async {
    final full = await _repo.byId(o.id);
    if (full == null || !mounted) return;
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll([
        for (final l in full.lines)
          _LineDraft(itemId: l.itemId, qty: l.requestedQty, unit: l.unitName, notes: l.notes),
      ]);
    _ensureBlank();
    imdSetText(_notes, o.notes);
    setState(() {
      _editId = o.id;
      _kind = o.orderKind;
      _authorityId = o.authorityId;
      _requesting = o.requestingWarehouse;
      _supplying = o.supplyingWarehouse;
      _date = o.date;
      _requiredDate = o.requiredDate;
      _priority = o.priority;
    });
    await _loadSupplyBalances();
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'rationOrders',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    if (!perm.canWh(_requesting)) {
      showImdToast(context, Perm.scopeBlock(_requesting), error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await _repo.save(
      id: _editId,
      kind: _kind,
      authorityId: _authorityId,
      authorityName: _authorityName,
      requestingWarehouse: _requesting,
      supplyingWarehouse: _supplying,
      date: _date,
      requiredDate: _requiredDate,
      priority: _priority,
      notes: _notes.text.trim(),
      lines: [for (final l in _filled) _inputOf(l)],
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ حُفظت الطلبية ${res.refNo}' : res.error,
        error: !res.ok);
    if (res.ok) {
      _resetForm();
      await _render();
    }
  }

  String get _authorityName =>
      _authorities.where((a) => a.id == _authorityId).firstOrNull?.name ?? '';

  /// المخزن الرئيسي يطلب باسمه، والفرعي يطلب من الرئيسي — يُملآن تلقائيًّا
  /// بدل أن يُتركا لاختيارٍ قد يخطئ المسار.
  void _applyKind(String kind) {
    setState(() {
      _kind = kind;
      if (RationKind.isMain(kind)) {
        _requesting = _mainWh;
        _supplying = '';
        _supplyBal = const {};
      } else {
        _authorityId = '';
        if (_requesting == _mainWh) _requesting = '';
        _supplying = _mainWh;
      }
    });
    if (!RationKind.isMain(kind)) _loadSupplyBalances();
  }

  RationLineInput _inputOf(_LineDraft l) {
    final item = _items.where((i) => i.id == l.itemId).firstOrNull;
    // بلا وحدةٍ مختارة: وحدة الأساس بمعامل ١، كما كان الحال دومًا. ووحدةٌ
    // مختارة تحمل معاملها الفعلي — فالكمية المطلوبة تُفهم بوحدتها لا
    // بافتراض أنها بالأساس دائمًا.
    final unitName = l.unit.isNotEmpty ? l.unit : (item?.baseUnit ?? '');
    final factor = (item != null && l.unit.isNotEmpty) ? _catalog.factorOf(item, l.unit) : 1.0;
    return RationLineInput(
      itemId: l.itemId,
      itemCode: item?.code ?? '',
      itemName: item?.name ?? '',
      unitName: unitName,
      factor: factor,
      requestedQty: double.tryParse(l.qty.text.trim()) ?? 0,
      notes: l.notes.text.trim(),
    );
  }

  /// ملاحظات المسودة الحيّة — تُعرض قبل الحفظ لا بعد رفضه.
  List<ImdCheck> _checks() {
    final out = <ImdCheck>[];
    final routeError = RationRules.validateRouting(
      kind: _kind,
      requesting: _requesting,
      supplying: _supplying,
      authorityId: _authorityId,
      mainWarehouse: _mainWh,
    );
    if (routeError != null) out.add(ImdCheck('err', 'مسار الطلبية', routeError));

    final dateError = RationRules.validateRequiredDate(_date, _requiredDate);
    if (dateError != null) out.add(ImdCheck('err', 'التواريخ', dateError));

    final lineError =
        RationRules.validateLines([for (final l in _filled) _inputOf(l).draft]);
    if (lineError != null) out.add(ImdCheck('err', 'سطور الطلبية', lineError));

    // تجاوزُ رصيد المورِّد ليس منعًا: للفرع أن يطلب ما يتوقّع وروده. لكنه
    // يُقال له الآن لا عند الاعتماد، فيبني تخطيطه على ما سيصله فعلًا.
    if (RationKind.isMain(_kind)) {
      out.add(const ImdCheck(
        'ok',
        'هذه الطلبية لا تحرّك المخزون',
        'اعتمادها إشعارٌ للجهة. ويُطابَق ما يصل بسند التوريد لاحقًا من زر '
            '«مطابقة بتوريد».',
      ));
    }
    if (!RationKind.isMain(_kind) && _supplying.isNotEmpty && !_balLoading) {
      for (final l in _lines) {
        if (l.itemId.isEmpty) continue;
        final want = double.tryParse(l.qty.text.trim()) ?? 0;
        if (want <= 0) continue;
        final have = _supplyBal[l.itemId] ?? 0;
        if (want <= have) continue;
        final item = _items.where((i) => i.id == l.itemId).firstOrNull;
        out.add(ImdCheck(
          'warn',
          'رصيد المورِّد لا يكفي: ${item?.name ?? l.itemId}',
          'المطلوب ${nf(want)} والمتاح لدى «$_supplying» ${nf(have)} — '
              'الطلب مسموح، لكن الاعتماد قد يُقلَّص.',
        ));
      }
    }
    return out;
  }

  Future<void> _act(RationOrder o, String action) async {
    final perm = Perm.of(context);
    final needed = action == 'approve' || action == 'reject'
        ? PermAction.approve
        : PermAction.edit;
    if (!perm.guard(context, 'rationOrders', needed)) return;

    final actor = context.read<AuthService>().currentUser?.email ?? '';
    setState(() => _busy = true);
    RationResult res;
    switch (action) {
      case 'submit':
        res = await _repo.submit(o.id, actor: actor);
      case 'reject':
        final reason = await _askReason();
        if (reason == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        res = await _repo.reject(o.id, reason: reason, actor: actor);
      case 'delete':
        if (!mounted) return;
        if (!await imdConfirm(context, 'حذف الطلبية ${o.refNo}؟',
            ok: 'حذف', danger: true)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        res = await _repo.delete(o.id, actor: actor);
      default:
        return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(
      context,
      res.ok ? '✔ تم الإجراء على ${res.refNo}' : res.error,
      error: !res.ok,
    );
    if (res.ok) {
      if (_editId == o.id) _resetForm();
      await _render();
    }
  }

  /// الاعتماد: يفتح ورقة الكميات بدل أن يُقرّ المطلوب كله بضغطة.
  Future<void> _approve(RationOrder o) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'rationOrders', PermAction.approve)) return;

    setState(() => _busy = true);
    final full = await _repo.byId(o.id);
    final available = await _balancesOf(o.supplyingWarehouse);
    if (!mounted) return;
    setState(() => _busy = false);
    if (full == null) return;

    final decided = await showImdModal<Map<String, double>>(
      context,
      title: 'اعتماد الطلبية ${o.refNo}',
      icon: 'check',
      maxWidth: 680,
      builder: (ctx) => _ApproveSheet(full: full, available: available),
    );
    if (decided == null || !mounted) return;

    setState(() => _busy = true);
    final res = await _repo.approve(
      o.id,
      approved: decided,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final cut = decided.entries
        .where((e) =>
            e.value <
            (full.lines.where((l) => l.id == e.key).firstOrNull?.requestedQty ??
                0))
        .length;
    showImdToast(
      context,
      res.ok
          ? (cut == 0
              ? '✔ اعتُمدت الطلبية ${res.refNo} بكامل المطلوب'
              : '✔ اعتُمدت الطلبية ${res.refNo} — قُلِّص $cut سطرًا')
          : res.error,
      error: !res.ok,
    );
    if (res.ok) await _render();
  }

  /// مطابقة طلبية المخزن الرئيسي بسند التوريد الذي جاء بها.
  Future<void> _matchReceipt(RationOrder o) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'rationOrders', PermAction.edit)) return;

    final recent = await MovementsRepo(_db).recentReceipts();
    if (!mounted) return;
    // سندات التوريد المتاحة للمطابقة — أحدثها أولًا، بلا تكرار المرجع.
    final refs = <String, String>{};
    for (final r in recent) {
      if (r.refNo.isEmpty) continue;
      refs.putIfAbsent(r.refNo, () => '${r.refNo} — ${r.date} — ${r.supplier}');
    }

    var picked = '';
    final chosen = await showImdModal<String>(
      context,
      title: 'مطابقة الطلبية ${o.refNo} بسند توريد',
      icon: 'link',
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الطلبية طلبٌ لا حركة. وسند التوريد هو ما أدخل الإعاشة فعلًا — '
              'بربطهما يُعرف ما وصل مما طُلب.',
              style: TextStyle(
                  fontSize: 12.5, color: ctx.imd.muted, height: 1.6),
            ),
            const SizedBox(height: 12),
            ImdLabeled(
              'سند التوريد *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر —'),
                  for (final e in refs.entries) (e.key, e.value),
                ],
                value: picked,
                onChanged: (v) => setInner(() => picked = v ?? ''),
              ),
            ),
            if (refs.isEmpty) ...[
              const SizedBox(height: 8),
              const ImdEmptyState.noData(
                title: 'لا توجد سندات توريد بعد',
                message: 'سجّل الاستلام أولًا',
              ),
            ],
          ],
        ),
      ),
      actions: (ctx) => [
        ImdButton.outline(
            label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
        ImdButton(
          label: 'مطابقة',
          icon: 'link',
          onPressed: () => Navigator.of(ctx).pop(picked),
        ),
      ],
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final res = await _repo.matchReceipt(
      o.id,
      receiptRef: chosen,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context,
        res.ok ? '✔ طوبقت ${o.refNo} بالسند $chosen' : res.error,
        error: !res.ok);
    if (res.ok) await _render();
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final out = await showImdModal<String>(
      context,
      title: 'رفض الطلبية',
      icon: 'alert',
      maxWidth: 420,
      builder: (ctx) =>
          ImdLabeled('سبب الرفض *', ImdFld(controller: ctrl, maxLines: 3)),
      actions: (ctx) => [
        ImdButton.outline(
            label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
        ImdButton(
          label: 'رفض',
          icon: 'x',
          kind: ImdBtnKind.danger,
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
        ),
      ],
    );
    ctrl.dispose();
    return out;
  }

  Future<void> _showLines(RationOrder o) async {
    final full = await _repo.byId(o.id);
    if (full == null || !mounted) return;
    setState(() => _open = full);
  }

  /// طباعة الطلبية مستندًا — تُحمل بين المستودعين وتُوقَّع.
  Future<void> _print(RationOrderFull full) async {
    if (!Perm.of(context).guard(context, 'rationOrders', PermAction.print)) return;
    final o = full.order;
    final layout = await SettingsRepo(_db).printLayoutFor(PrintForms.rationOrder);
    if (!mounted) return;
    var i = 1;
    await DocumentPdf.printDoc(
      layout: layout,
      doc: PrintDoc(
        title: 'طلبية إعاشة — ${RationStatus.label(o.status)}',
        headers: const [
          'م',
          'الكود',
          'اسم الصنف',
          'الوحدة',
          'مطلوب',
          'معتمد',
          'مستلم',
        ],
        columnFlex: const [1, 2, 6, 2, 2, 2, 2],
        rows: [
          for (final l in full.lines)
            [
              '${i++}',
              l.itemCode,
              l.itemName,
              l.unitName,
              nf(l.requestedQty),
              nf(l.approvedQty),
              nf(l.receivedQty),
            ],
        ],
        leftValues: {'date': o.date, 'refNo': o.refNo},
        fieldValues: {
          'warehouse': o.requestingWarehouse,
          'party': o.supplyingWarehouse,
          'notes': o.notes,
        },
        footerNote: [
          if (o.requiredDate.isNotEmpty) 'تاريخ الاحتياج: ${o.requiredDate}',
          if (o.priority == RationPriority.urgent) 'أولوية: عاجل',
          if (o.receiptRef.isNotEmpty) 'سند الاستلام: ${o.receiptRef}',
          if (o.rejectReason.isNotEmpty) 'سبب الرفض: ${o.rejectReason}',
        ].join(' · '),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'طلبيات الإعاشة', icon: 'clipboard'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final perm = Perm.of(context);
    final can = perm.writable('rationOrders');
    final counts = {
      for (final s in RationStatus.all)
        s: _orders.where((o) => o.status == s).length,
    };
    final urgent = _orders
        .where((o) =>
            o.priority == RationPriority.urgent &&
            RationStatus.open.contains(o.status))
        .length;

    final head = <Widget>[
      const ImdPageTitle(
        title: 'طلبيات الإعاشة',
        icon: 'clipboard',
        subtitle: 'الطلبية طلبٌ لا حركة: لا تمسّ المخزون. '
            'وما يحرّكه سندُ التحويل أو التوريد الذي تُربط به بعد الاعتماد',
      ),
      if (_suspended.isNotEmpty)
        ImdDocTabsBar<Map<String, dynamic>>(
          activeLabel: _activeTabLabel(),
          suspended: _suspended,
          onSelect: _switchDocTab,
          onClose: _closeDocTab,
        ),
      ImdGuidePanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdWorkflowSteps([
            'يبني الطالب المسودة: المخزن الرئيسي من جهة، وغيره من المخزن الرئيسي',
            'يرسلها فتُرفع إلى ركن الإمداد',
            'يعتمدها ركن الإمداد كاملةً أو مقلَّصة',
            'الفرعية تُسحب في شاشة التحويل، والرئيسية تُطابَق بسند توريد',
          ]),
          ImdKpis(children: [
            ImdKpi(label: 'إجمالي الطلبيات', value: nf(_orders.length)),
            ImdKpi(label: 'مسودات', value: nf(counts[RationStatus.draft] ?? 0)),
            ImdKpi(
              label: 'بانتظار الاعتماد',
              value: nf(counts[RationStatus.pending] ?? 0),
              extra: (counts[RationStatus.pending] ?? 0) == 0
                  ? null
                  : const ImdChip('يحتاج إجراء', tone: ImdTone.pend),
            ),
            ImdKpi(
              label: 'معتمدة بانتظار التنفيذ',
              value: nf(counts[RationStatus.approved] ?? 0),
              extra: (counts[RationStatus.approved] ?? 0) == 0
                  ? null
                  : const ImdChip('تحويل أو توريد', tone: ImdTone.info),
            ),
            ImdKpi(
              label: 'عاجلة مفتوحة',
              value: nf(urgent),
              extra:
                  urgent == 0 ? null : const ImdChip('عاجل', tone: ImdTone.err),
            ),
            ImdKpi(label: 'منفَّذة', value: nf(counts[RationStatus.received] ?? 0)),
          ]),
        ]),
      ),
    ];
    final after = <Widget>[
      ImdICard(
        child: ImdF2(children: [
          ImdLabeled(
            'تصفية بالحالة',
            ImdSelect<String>(
              items: [
                ('', 'كل الحالات'),
                for (final s in RationStatus.all) (s, RationStatus.label(s)),
              ],
              value: _filterStatus,
              onChanged: (v) {
                setState(() => _filterStatus = v ?? '');
                _render();
              },
            ),
            size: 11,
          ),
          ImdLabeled(
            ' ',
            Wrap(spacing: 10, children: [
              ImdButton.outline(
                  label: 'تحديث',
                  icon: 'refresh',
                  small: true,
                  onPressed: _render),
            ]),
            size: 11,
          ),
        ]),
      ),
      ImdPanel(title: 'سجل الطلبيات', icon: 'list', child: _table(can)),
      if (_open != null) ...[
        ImdPanel(
          title: 'سطور الطلبية ${_open!.order.refNo}',
          icon: 'package',
          child: _linesTable(_open!),
        ),
      ],
    ];
    // بلا صلاحية كتابة: لا نموذج ولا شريط إجراءات.
    if (!can) return ImdPage(children: [...head, ...after]);

    // كسندات العمليات المخزنية: النموذج يمرّ وأزرار الحفظ/الجديد/الطباعة
    // ملتصقةٌ بالأسفل، والتصفية والسجل بعدها.
    return ImdStickyPage(
      sticky: ImdStickyActions(children: [
        ImdButton.outline(label: 'طلبية جديدة', icon: 'plus-square', small: true, onPressed: _busy ? null : _openNewTab),
        ImdButton.outline(label: 'طباعة الطلبية', icon: 'printer', small: true, onPressed: _busy ? null : _printCurrent),
        if (_editId != null)
          ImdButton.outline(label: 'إلغاء التعديل', icon: 'x', small: true, onPressed: _busy ? null : _resetForm),
        ImdButton(
          label: _editId == null ? 'حفظ كمسودة' : 'حفظ التعديل',
          icon: 'check',
          busy: _busy,
          onPressed: _save,
        ),
      ]),
      after: [const SizedBox(height: 14), ...after],
      children: [
        ...head,
        ImdPanel(
          title: _editId == null ? 'طلبية جديدة' : 'تعديل مسودة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: _form(),
        ),
      ],
    );
  }

  /// الطباعة من الشريط: الطلبية المحفوظة الجاري تعديلها. الطلبية الجديدة
  /// لا رقم لها ولا سطور معتمدة بعد، فتُحفظ أولًا.
  Future<void> _printCurrent() async {
    final id = _editId;
    if (id == null) {
      showImdToast(context, 'ℹ احفظ الطلبية أولًا ثم اطبعها — أو اطبع طلبيةً من السجل');
      return;
    }
    final full = await _repo.byId(id);
    if (full != null && mounted) await _print(full);
  }

  Widget _form() {
    final checks = _checks();
    return ImdCompact(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImdFormGrid(children: [
          ImdLabeled(
            'نوع الطلبية *',
            ImdSelect<String>(
              items: [for (final k in RationKind.all) (k, RationKind.label(k))],
              value: _kind,
              onChanged: (v) => _applyKind(v ?? RationKind.branch),
            ),
            size: 11,
          ),
          // المخزن الرئيسي يطلب من جهةٍ في تسلسل الفرقة، لا من مستودع: لا
          // رصيد لها يُنقَص، فاعتمادها إشعارٌ يُطابَق بتوريده لاحقًا.
          if (RationKind.isMain(_kind)) ...[
            ImdLabeled(
              'الجهة المطلوب منها *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر —'),
                  for (final a in _authorities)
                    (a.id, a.title.isEmpty ? a.name : '${a.name} — ${a.title}'),
                ],
                value: _authorityId,
                onChanged: (v) => setState(() => _authorityId = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'المستودع الطالب',
              ImdReadonlyField(
                  text: _mainWh.isEmpty ? '— لم يُعيَّن مخزن رئيسي —' : _mainWh),
              size: 11,
            ),
          ] else ...[
            ImdLabeled(
              'المستودع الطالب *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر —'),
                  for (final w in _warehouses)
                    if (w.name != _mainWh && Perm.of(context).canWh(w.name))
                      (w.name, w.name),
                ],
                value: _requesting,
                onChanged: (v) => setState(() => _requesting = v ?? ''),
              ),
              size: 11,
            ),
            // المخزن الفرعي يطلب من الرئيسي وحده، فلا خيار يُعرض.
            ImdLabeled(
              'المطلوب منه',
              ImdReadonlyField(
                  text: _mainWh.isEmpty ? '— لم يُعيَّن مخزن رئيسي —' : _mainWh),
              size: 11,
            ),
          ],
          ImdLabeled(
            'تاريخ الطلبية',
            ImdDateField(
                value: _date, onChanged: (v) => setState(() => _date = v)),
            size: 11,
          ),
          ImdLabeled(
            'تاريخ الاحتياج',
            ImdDateField(
              value: _requiredDate,
              onChanged: (v) => setState(() => _requiredDate = v),
            ),
            size: 11,
          ),
          ImdLabeled(
            'الأولوية',
            ImdSelect<String>(
              items: [
                for (final p in RationPriority.all) (p, RationPriority.label(p))
              ],
              value: _priority,
              onChanged: (v) =>
                  setState(() => _priority = v ?? RationPriority.normal),
            ),
            size: 11,
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          // `Wrap` لا `Row`: على الهاتف يلتفّ التلميح تحت العنوان بدل أن يفيض.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('الأصناف المطلوبة',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (_supplying.isEmpty)
                  Text('اختر المورِّد ليظهر رصيده',
                      style: TextStyle(fontSize: 11.5, color: context.imd.muted))
                else if (_balLoading)
                  Text('⏳ يُقرأ رصيد «$_supplying»…',
                      style: TextStyle(fontSize: 11.5, color: context.imd.muted)),
              ],
            ),
          ),
          ImdButton.outline(
            label: 'إضافة صنف',
            icon: 'plus-square',
            small: true,
            onPressed: () => setState(() => _lines.add(_LineDraft())),
          ),
        ]),
        const SizedBox(height: 8),
        _linesTableEditor(context),
        const SizedBox(height: 6),
        ImdCollapsibleSection(title: 'ملاحظات', child: ImdFld(controller: _notes, maxLines: 2)),
        if (_filled.isNotEmpty || _requesting.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImdValidationBox(title: 'مراجعة الطلبية', items: checks),
        ],
      ],
    ));
  }

  Widget _table(bool can) => ImdTable(
        empty: 'لا توجد طلبيات',
        minWidth: 820,
        onRowTap: (i) => _showLines(_orders[i]),
        columns: const [
          ImdCol('المرجع'),
          ImdCol('النوع'),
          ImdCol('من ← إلى'),
          ImdCol('التاريخ'),
          ImdCol('الحالة'),
          ImdCol('المستند المنفِّذ'),
          ImdCol('', center: true),
        ],
        pageSize: 50,
        rows: [
          for (final o in _orders)
            [
              // Wrap لا Row: الخلية ضيّقة، وسطرٌ لا يلتفّ يفيض على جاره.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(o.refNo,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (o.priority == RationPriority.urgent)
                    const ImdChip('عاجل', tone: ImdTone.err),
                ],
              ),
              ImdChip(
                RationKind.isMain(o.orderKind) ? 'رئيسي ← جهة' : 'فرعي ← رئيسي',
                tone: RationKind.isMain(o.orderKind)
                    ? ImdTone.info
                    : ImdTone.off,
              ),
              Text(RationKind.isMain(o.orderKind)
                  ? '${o.requestingWarehouse} ← ${o.authorityName}'
                  : '${o.requestingWarehouse} ← ${o.supplyingWarehouse}'),
              Text(arDigits(o.date)),
              ImdChip(RationStatus.labelOf(o.status, o.orderKind),
                  tone: _tone(o.status)),
              // الطلبية لا تحرّك مخزونًا: هذا العمود هو كل صلتها به.
              o.fulfillRef.isEmpty
                  ? Text(
                      o.status == RationStatus.approved
                          ? (RationKind.isMain(o.orderKind)
                              ? 'بانتظار التوريد'
                              : 'بانتظار التحويل')
                          : '—',
                      style: TextStyle(color: context.imd.muted, fontSize: 12.5))
                  : ImdChip(
                      '${RationFulfillKind.label(o.fulfillKind)}: ${o.fulfillRef}',
                      tone: ImdTone.code),
              Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                if (RationRules.canEdit(o.status) && can)
                  ImdIconButton(
                      icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(o)),
                if (RationRules.canSubmit(o.status) && can)
                  ImdIconButton(
                      icon: 'upload',
                      tooltip: 'إرسال',
                      onPressed: () => _act(o, 'submit')),
                if (RationRules.canApprove(o.status) && can)
                  ImdIconButton(
                      icon: 'check',
                      tooltip: 'اعتماد بالكميات',
                      onPressed: () => _approve(o)),
                // طلبية المخزن الرئيسي تُطابَق بسند توريد. أما الفرعية فلا
                // زرّ لها هنا: يسحبها أمين المخزن من شاشة التحويل، فيقع
                // التنفيذ مع الحركة لا قبلها.
                if (RationRules.canFulfill(o.status) &&
                    RationKind.isMain(o.orderKind) &&
                    can)
                  ImdIconButton(
                      icon: 'link',
                      tooltip: 'مطابقة بسند توريد',
                      onPressed: () => _matchReceipt(o)),
                if (RationRules.canFulfill(o.status) &&
                    !RationKind.isMain(o.orderKind))
                  ImdIconButton(
                      icon: 'truck',
                      tooltip: 'تُسحب من شاشة التحويل — اضغط للتفاصيل',
                      onPressed: () => showImdToast(
                            context,
                            'ℹ افتح «التحويل المخزني» من «${o.supplyingWarehouse}» '
                            'واضغط «سحب من طلبية» لتنفيذ ${o.refNo}',
                          )),
                if (RationRules.canReject(o.status) && can)
                  ImdIconButton(
                      icon: 'x',
                      tooltip: 'رفض',
                      onPressed: () => _act(o, 'reject')),
                ImdIconButton(
                    icon: 'printer',
                    tooltip: 'طباعة',
                    onPressed: () async {
                      final full = await _repo.byId(o.id);
                      if (full != null && mounted) await _print(full);
                    }),
                if (RationRules.canDelete(o.status) && can)
                  ImdIconButton(
                      icon: 'trash',
                      tooltip: 'حذف',
                      onPressed: () => _act(o, 'delete')),
              ]),
            ],
        ],
      );

  /// وحدة الطلب لصنف السطر — قائمة وحدات صنفه، أو فارغة إن لم يُختر صنفٌ بعد.
  /// تغييرها يحوّل الكمية بمعامل الوحدتين (كما في بقية السندات): ١١٠٠ كجم
  /// ⇒ ٢٧٫٥ كيسًا، لا ١١٠٠ كيسًا.
  Widget _unitFieldFor(_LineDraft l) {
    final item = _items.where((i) => i.id == l.itemId).firstOrNull;
    final units = item == null ? const <ItemUnit>[] : _catalog.unitsOf(item);
    return ImdUnitPicker(
      units: [for (final u in units) u.name],
      value: l.unit,
      onChanged: (v) => setState(() {
        final next = v;
        final previous = l.unit;
        final qty = double.tryParse(l.qty.text.trim()) ?? 0;
        l.unit = next;
        if (item != null && qty > 0 && previous.isNotEmpty && next.isNotEmpty && next != previous) {
          imdSetText(
            l.qty,
            _num(convertQty(qty, _catalog.factorOf(item, previous), _catalog.factorOf(item, next))),
          );
        }
      }),
    );
  }

  /// محرّر أسطر الطلبية — الجدول الكثيف المشترك نفسه في بقية السندات.
  ///
  /// الطلبية طلبٌ لا حركة، فلا إجراء أسطوانة فيها؛ لكن الوحدة تبقى مفيدة:
  /// الطالب قد يعرف كميته بوحدةٍ غير الأساس (كرتونًا لا كيلو) فيطلب بها
  /// مباشرةً بدل أن يحسبها بنفسه — بلا وحدةٍ مختارة تبقى الأساس كما كانت
  /// دومًا. والملاحظة لكل صنفٍ سبب طلبٍ خاص لا يخصّ الطلبية كلّها.
  Widget _linesTableEditor(BuildContext context) {
    const cell = ImdEntryTable.cell;
    return ImdEntryTable(
      columns: const [
        ImdCol('الصنف', flex: 3),
        ImdCol('المتاح', width: 96),
        ImdCol('الوحدة', width: 112),
        ImdCol('الكمية', width: 96),
        ImdCol('ملاحظة', flex: 2),
        ImdCol('', width: 56),
      ],
      rowKeys: [for (final l in _lines) l.key],
      rows: [
        for (final l in _lines)
          [
            // المنتقي بالبحث لا القائمة المنسدلة: أصناف النظام بالمئات،
            // والتمرير بينها في كل سطر أبطأ من كتابة حرفين.
            cell(ImdItemPicker(
              items: _items,
              value: l.itemId,
              onChanged: (v) => setState(() {
                l.itemId = v;
                final item = _items.where((i) => i.id == v).firstOrNull;
                final units = item == null ? const <ItemUnit>[] : _catalog.unitsOf(item);
                l.unit = units.where((u) => u.isBase).firstOrNull?.name ??
                    (units.isNotEmpty ? units.first.name : '');
                _ensureBlank();
              }),
            )),
            cell(ImdEntryBalanceCell(
              _supplying.isEmpty || l.itemId.isEmpty ? '' : nf(_supplyBal[l.itemId] ?? 0),
            )),
            cell(_unitFieldFor(l)),
            cell(ImdFld(
              controller: l.qty,
              number: true,
              hint: 'الكمية',
              onChanged: (_) => setState(() {}),
            )),
            cell(ImdFld(controller: l.notes, hint: 'ملاحظة على هذا الصنف…')),
            cell(ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف السطر',
              onPressed: () => setState(() {
                _lines.remove(l);
                l.dispose();
                _ensureBlank();
              }),
            )),
          ],
      ],
    );
  }

  Widget _linesTable(RationOrderFull full) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdChipsRow(children: [
            ImdChip(
                RationStatus.labelOf(full.order.status, full.order.orderKind),
                tone: _tone(full.order.status)),
            if (full.order.fulfillRef.isNotEmpty)
              ImdChip(
                  '${RationFulfillKind.label(full.order.fulfillKind)}: '
                  '${full.order.fulfillRef}',
                  tone: ImdTone.code),
            if (full.order.receiptRef.isNotEmpty)
              ImdChip('سند الاستلام: ${full.order.receiptRef}',
                  tone: ImdTone.code),
            if (full.order.rejectReason.isNotEmpty)
              ImdChip('سبب الرفض: ${full.order.rejectReason}',
                  tone: ImdTone.err),
          ]),
          const SizedBox(height: 8),
          ImdTable(
            empty: 'لا سطور',
            columns: const [
              ImdCol('الصنف'),
              ImdCol('الوحدة'),
              ImdCol('مطلوب', numeric: true),
              ImdCol('معتمد', numeric: true),
              ImdCol('مستلم', numeric: true),
              ImdCol('الفرق', numeric: true),
            ],
            pageSize: 50,
            rows: [
              for (final l in full.lines)
                [
                  Text('${l.itemCode} · ${l.itemName}'),
                  Text(l.unitName),
                  Text(nf(l.requestedQty)),
                  Text(nf(l.approvedQty)),
                  Text(nf(l.receivedQty)),
                  // الفرق بين ما طُلب وما اعتُمد: سببُ العجز إن وقع، ودليلٌ
                  // على أن التقليص كان قرارًا مسجَّلًا لا سهوًا.
                  if (l.approvedQty < l.requestedQty)
                    Text('−${nf(l.requestedQty - l.approvedQty)}',
                        style: TextStyle(color: context.imd.danger))
                  else
                    Text('—', style: TextStyle(color: context.imd.muted)),
                ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, children: [
            ImdButton.outline(
              label: 'طباعة الطلبية',
              icon: 'printer',
              small: true,
              onPressed: () => _print(full),
            ),
            ImdButton.outline(
              label: 'إغلاق',
              icon: 'x',
              small: true,
              onPressed: () => setState(() => _open = null),
            ),
          ]),
        ],
      );

  static ImdTone _tone(String status) => switch (status) {
        RationStatus.draft => ImdTone.off,
        RationStatus.pending => ImdTone.pend,
        RationStatus.approved => ImdTone.info,
        RationStatus.received => ImdTone.ok,
        RationStatus.rejected => ImdTone.err,
        _ => ImdTone.off,
      };
}
