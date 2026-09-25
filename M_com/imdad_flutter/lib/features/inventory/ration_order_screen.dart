import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../data/repos/ration_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/ration_order.dart';
import 'doc_kit.dart';

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
  _LineDraft({this.itemId = '', double qty = 0})
      : qty = TextEditingController(text: qty > 0 ? '$qty' : '');

  String itemId;
  final TextEditingController qty;

  void dispose() => qty.dispose();
}

class _RationOrderScreenState extends State<RationOrderScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final RationRepo _repo = RationRepo(_db);

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

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _render() async {
    final scope = Perm.of(context).scope;
    final orders = await _repo.orders(status: _filterStatus, scope: scope);
    final warehouses = await _db.select(_db.warehouses).get();
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

  void _resetForm() {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
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
          _LineDraft(itemId: l.itemId, qty: l.requestedQty),
      ]);
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
      lines: [for (final l in _lines) _inputOf(l)],
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
    return RationLineInput(
      itemId: l.itemId,
      itemCode: item?.code ?? '',
      itemName: item?.name ?? '',
      unitName: item?.baseUnit ?? '',
      factor: 1,
      requestedQty: double.tryParse(l.qty.text.trim()) ?? 0,
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
        RationRules.validateLines([for (final l in _lines) _inputOf(l).draft]);
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

    final recent = await (_db.select(_db.receipts)
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(400))
        .get();
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
              const ImdEmptyBox('لا توجد سندات توريد بعد — سجّل الاستلام أولًا'),
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
    final o = full.order;
    final layout = await SettingsRepo(_db).printLayout();
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

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'طلبيات الإعاشة',
        icon: 'clipboard',
        subtitle: 'الطلبية طلبٌ لا حركة: لا تمسّ المخزون. '
            'وما يحرّكه سندُ التحويل أو التوريد الذي تُربط به بعد الاعتماد',
      ),
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
              if (can)
                ImdButton.outline(
                  label: 'طلبية جديدة',
                  icon: 'plus-square',
                  small: true,
                  onPressed: _resetForm,
                ),
            ]),
            size: 11,
          ),
        ]),
      ),
      if (can) ...[
        ImdPanel(
          title: _editId == null ? 'طلبية جديدة' : 'تعديل مسودة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: _form(),
        ),
      ],
      ImdPanel(title: 'سجل الطلبيات', icon: 'list', child: _table(can)),
      if (_open != null) ...[
        ImdPanel(
          title: 'سطور الطلبية ${_open!.order.refNo}',
          icon: 'package',
          child: _linesTable(_open!),
        ),
      ],
    ]);
  }

  Widget _form() {
    final checks = _checks();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImdF2(children: [
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
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Row(children: [
              const Text('الأصناف المطلوبة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(width: 8),
              if (_supplying.isEmpty)
                Text('اختر المورِّد ليظهر رصيده',
                    style:
                        TextStyle(fontSize: 11.5, color: context.imd.muted))
              else if (_balLoading)
                Text('⏳ يُقرأ رصيد «$_supplying»…',
                    style:
                        TextStyle(fontSize: 11.5, color: context.imd.muted)),
            ]),
          ),
          ImdButton.outline(
            label: 'إضافة صنف',
            icon: 'plus-square',
            small: true,
            onPressed: () => setState(() => _lines.add(_LineDraft())),
          ),
        ]),
        const SizedBox(height: 8),
        if (_lines.isEmpty)
          const ImdEmptyBox('لم يُضف صنف بعد')
        else
          for (final (i, l) in _lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: 5,
                  // المنتقي بالبحث لا القائمة المنسدلة: أصناف النظام بالمئات،
                  // والتمرير بينها في كل سطر أبطأ من كتابة حرفين.
                  child: ImdItemPicker(
                    items: _items,
                    value: l.itemId,
                    labelOf: (it) => _supplying.isEmpty
                        ? '${it.code} — ${it.name}'
                        : '${it.code} — ${it.name} '
                            '(متاح: ${nf(_supplyBal[it.id] ?? 0)})',
                    onChanged: (v) => setState(() => l.itemId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ImdFld(
                    controller: l.qty,
                    number: true,
                    hint: 'الكمية',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                ImdIconButton(
                  icon: 'trash',
                  tooltip: 'حذف السطر',
                  onPressed: () => setState(() {
                    _lines.removeAt(i).dispose();
                  }),
                ),
              ]),
            ),
        const SizedBox(height: 10),
        ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
        if (_lines.isNotEmpty || _requesting.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImdValidationBox(title: 'مراجعة الطلبية', items: checks),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton(
            label: _editId == null ? 'حفظ كمسودة' : 'حفظ التعديل',
            icon: 'check',
            busy: _busy,
            onPressed: _save,
          ),
          if (_editId != null)
            ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: _resetForm),
        ]),
      ],
    );
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
          ImdCol('إجراءات', center: true),
        ],
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

/// ورقة الاعتماد: سطرًا سطرًا، بالمطلوب والمتاح والمعتمَد.
///
/// كان الاعتماد إقرارًا للمطلوب كلّه بضغطة، مع أن [RationRepo.approve] يقبل
/// كمياتٍ مقلَّصة و[RationRules.validateApproved] يحرسها. فكانت القدرة موجودة
/// في الطبقات ولا سبيل إليها من الشاشة.
class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.full, required this.available});

  final RationOrderFull full;

  /// رصيد المستودع المورِّد لكل صنف.
  final Map<String, double> available;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  late final Map<String, TextEditingController> _qty = {
    for (final l in widget.full.lines)
      l.id: TextEditingController(text: '${l.requestedQty}'),
  };

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _valueOf(String lineId) =>
      double.tryParse((_qty[lineId]?.text ?? '').trim()) ?? 0;

  double _availableFor(RationOrderLine l) => widget.available[l.itemId] ?? 0;

  void _setAll(double Function(RationOrderLine) pick) {
    setState(() {
      for (final l in widget.full.lines) {
        imdSetText(_qty[l.id]!, '${pick(l)}');
      }
    });
  }

  /// أخطاء تمنع الاعتماد — تُحسب من قاعدة المجال نفسها لا من نسخةٍ منها.
  String? get _error => RationRules.validateApproved([
        for (final l in widget.full.lines)
          RationLineDraft(
            itemId: l.itemId,
            requestedQty: l.requestedQty,
            approvedQty: _valueOf(l.id),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final lines = widget.full.lines;
    final error = _error;
    final total = lines.fold<double>(0, (s, l) => s + _valueOf(l.id));
    final short = lines.where((l) => _valueOf(l.id) > _availableFor(l)).length;
    final cut = lines.where((l) => _valueOf(l.id) < l.requestedQty).length;
    final empty = lines.every((l) => _valueOf(l.id) <= 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'المورِّد «${widget.full.order.supplyingWarehouse}» — '
          'الكمية المعتمدة لا تتجاوز المطلوبة، وقد تقلّ عنها.',
          style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.6),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ImdButton.outline(
            label: 'اعتماد كامل المطلوب',
            icon: 'check',
            small: true,
            onPressed: () => _setAll((l) => l.requestedQty),
          ),
          ImdButton.outline(
            label: 'تقليص إلى المتاح',
            icon: 'scale',
            small: true,
            onPressed: () => _setAll(
              (l) => l.requestedQty < _availableFor(l)
                  ? l.requestedQty
                  : _availableFor(l),
            ),
          ),
          ImdButton.outline(
            label: 'تصفير الكل',
            icon: 'x',
            small: true,
            onPressed: () => _setAll((_) => 0),
          ),
        ]),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in lines) _lineRow(l),
              ],
            ),
          ),
        ),
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Text(
              [
                'الإجمالي المعتمد: ${nf(total)}',
                if (cut > 0) 'مقلَّص: $cut سطرًا',
                if (short > 0) 'يتجاوز رصيد المورِّد: $short سطرًا',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12.5,
                color: short > 0 ? c.danger : c.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text('✖ $error',
              style: TextStyle(
                  fontSize: 12.5, color: c.danger, fontWeight: FontWeight.w600)),
        ] else if (empty) ...[
          const SizedBox(height: 8),
          Text(
            '✖ كل السطور بصفر — لا شيء يُستلم. اعتمد كميةً أو ارفض الطلبية.',
            style: TextStyle(
                fontSize: 12.5, color: c.danger, fontWeight: FontWeight.w600),
          ),
        ] else if (short > 0) ...[
          const SizedBox(height: 8),
          Text(
            '⚠ الاعتماد يتجاوز رصيد المورِّد — سيُرفض السند عند الاستلام إن لم '
            'يصل التوريد قبله.',
            style: TextStyle(fontSize: 12.5, color: c.warn, height: 1.6),
          ),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ImdButton.outline(
              label: 'إلغاء', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          ImdButton(
            label: 'اعتماد',
            icon: 'check',
            onPressed: error != null || empty
                ? null
                : () => Navigator.of(context).pop({
                      for (final l in lines) l.id: _valueOf(l.id),
                    }),
          ),
        ]),
      ],
    );
  }

  Widget _lineRow(RationOrderLine l) {
    final c = context.imd;
    final have = _availableFor(l);
    final want = _valueOf(l.id);
    final over = want > have;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l.itemCode} · ${l.itemName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                'مطلوب ${nf(l.requestedQty)} ${l.unitName} · '
                'متاح ${nf(have)}',
                style: TextStyle(
                    fontSize: 11.5, color: over ? c.danger : c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: ImdFld(
            controller: _qty[l.id]!,
            number: true,
            hint: 'معتمد',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 6),
        ImdIconButton(
          icon: 'scale',
          tooltip: 'اجعلها المتاح',
          onPressed: () => setState(() => imdSetText(
              _qty[l.id]!, '${l.requestedQty < have ? l.requestedQty : have}')),
        ),
      ]),
    );
  }
}
