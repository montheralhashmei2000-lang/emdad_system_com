import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/ration_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/ration_order.dart';

/// طلبيات الإعاشة: فرعٌ يطلب من مستودع مورِّد، ثم تُعتمد وتُستلم.
///
/// الاستلام هنا ليس تعليمًا على ورقة: يولّد سند استلام حقيقي في المستودع
/// الطالب (انظر [RationRepo.receive])، فالرصيد يتحرك كما يتحرك بأي استلام آخر.
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
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _warehouses = warehouses;
      _items = items;
      _loading = false;
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
      _requesting = '';
      _supplying = '';
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
        for (final l in full.lines) _LineDraft(itemId: l.itemId, qty: l.requestedQty),
      ]);
    imdSetText(_notes, o.notes);
    setState(() {
      _editId = o.id;
      _requesting = o.requestingWarehouse;
      _supplying = o.supplyingWarehouse;
      _date = o.date;
      _requiredDate = o.requiredDate;
      _priority = o.priority;
    });
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
    showImdToast(context, res.ok ? '✔ حُفظت الطلبية ${res.refNo}' : res.error, error: !res.ok);
    if (res.ok) {
      _resetForm();
      await _render();
    }
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
      case 'approve':
        res = await _repo.approve(o.id, actor: actor);
      case 'receive':
        res = await _repo.receive(o.id, actor: actor);
      case 'reject':
        final reason = await _askReason();
        if (reason == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        res = await _repo.reject(o.id, reason: reason, actor: actor);
      case 'delete':
        if (!mounted) return;
        if (!await imdConfirm(context, 'حذف الطلبية ${o.refNo}؟', ok: 'حذف', danger: true)) {
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
      res.ok
          ? (action == 'receive'
              ? '✔ استُلمت الطلبية بالسند ${res.refNo}'
              : '✔ تم الإجراء على ${res.refNo}')
          : res.error,
      error: !res.ok,
    );
    if (res.ok) {
      if (_editId == o.id) _resetForm();
      await _render();
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final out = await showImdModal<String>(
      context,
      title: 'رفض الطلبية',
      icon: 'alert',
      maxWidth: 420,
      builder: (ctx) => ImdLabeled('سبب الرفض *', ImdFld(controller: ctrl, maxLines: 3)),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
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
      for (final s in RationStatus.all) s: _orders.where((o) => o.status == s).length,
    };

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'طلبيات الإعاشة',
        icon: 'clipboard',
        subtitle: 'طلب الأصناف من مستودع مورِّد: مسودة ← إرسال ← اعتماد ← استلام. '
            'والاستلام يولّد سند استلام يحرّك الرصيد فعلًا',
      ),
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
        ImdKpi(label: 'معتمدة بانتظار الاستلام', value: nf(counts[RationStatus.approved] ?? 0)),
        ImdKpi(label: 'مستلمة', value: nf(counts[RationStatus.received] ?? 0)),
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
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _render),
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

  Widget _form() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdF2(children: [
            ImdLabeled(
              'المستودع الطالب *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر —'),
                  for (final w in _warehouses)
                    if (Perm.of(context).canWh(w.name)) (w.name, w.name),
                ],
                value: _requesting,
                onChanged: (v) => setState(() => _requesting = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'المستودع المورِّد *',
              ImdSelect<String>(
                items: [('', '— اختر —'), for (final w in _warehouses) (w.name, w.name)],
                value: _supplying,
                onChanged: (v) => setState(() => _supplying = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'تاريخ الطلبية',
              ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)),
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
                items: [for (final p in RationPriority.all) (p, RationPriority.label(p))],
                value: _priority,
                onChanged: (v) => setState(() => _priority = v ?? RationPriority.normal),
              ),
              size: 11,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(
              child: Text('الأصناف المطلوبة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
                    child: ImdSelect<String>(
                      hint: 'الصنف',
                      items: [for (final it in _items) (it.id, '${it.code} · ${it.name}')],
                      value: l.itemId.isEmpty ? null : l.itemId,
                      onChanged: (v) => setState(() => l.itemId = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ImdFld(controller: l.qty, number: true, hint: 'الكمية'),
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

  Widget _table(bool can) => ImdTable(
        empty: 'لا توجد طلبيات',
        minWidth: 760,
        onRowTap: (i) => _showLines(_orders[i]),
        columns: const [
          ImdCol('المرجع'),
          ImdCol('من ← إلى'),
          ImdCol('التاريخ'),
          ImdCol('الحالة'),
          ImdCol('الأولوية'),
          ImdCol('إجراءات', center: true),
        ],
        rows: [
          for (final o in _orders)
            [
              Text(o.refNo, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${o.requestingWarehouse} ← ${o.supplyingWarehouse}'),
              Text(arDigits(o.date)),
              ImdChip(RationStatus.label(o.status), tone: _tone(o.status)),
              o.priority == RationPriority.urgent
                  ? const ImdChip('عاجل', tone: ImdTone.err)
                  : Text(RationPriority.label(o.priority),
                      style: TextStyle(color: context.imd.muted)),
              Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                if (RationRules.canEdit(o.status) && can)
                  ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(o)),
                if (RationRules.canSubmit(o.status) && can)
                  ImdIconButton(
                      icon: 'upload', tooltip: 'إرسال', onPressed: () => _act(o, 'submit')),
                if (RationRules.canApprove(o.status) && can)
                  ImdIconButton(
                      icon: 'check', tooltip: 'اعتماد', onPressed: () => _act(o, 'approve')),
                if (RationRules.canReceive(o.status) && can)
                  ImdIconButton(
                      icon: 'download', tooltip: 'استلام', onPressed: () => _act(o, 'receive')),
                if (RationRules.canReject(o.status) && can)
                  ImdIconButton(icon: 'x', tooltip: 'رفض', onPressed: () => _act(o, 'reject')),
                if (RationRules.canDelete(o.status) && can)
                  ImdIconButton(
                      icon: 'trash', tooltip: 'حذف', onPressed: () => _act(o, 'delete')),
              ]),
            ],
        ],
      );

  Widget _linesTable(RationOrderFull full) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdChipsRow(children: [
            ImdChip(RationStatus.label(full.order.status), tone: _tone(full.order.status)),
            if (full.order.receiptRef.isNotEmpty)
              ImdChip('سند الاستلام: ${full.order.receiptRef}', tone: ImdTone.code),
            if (full.order.rejectReason.isNotEmpty)
              ImdChip('سبب الرفض: ${full.order.rejectReason}', tone: ImdTone.err),
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
            ],
            rows: [
              for (final l in full.lines)
                [
                  Text('${l.itemCode} · ${l.itemName}'),
                  Text(l.unitName),
                  Text(nf(l.requestedQty)),
                  Text(nf(l.approvedQty)),
                  Text(nf(l.receivedQty)),
                ],
            ],
          ),
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
