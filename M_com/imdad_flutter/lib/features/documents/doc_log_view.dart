import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/voucher_print.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/documents_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/document_edit.dart';
import '../inventory/doc_kit.dart';

/// سجل المستندات — نقل مطابق لـ `documents-center.js`:
/// عرض وإعادة طباعة وتعديل وإلغاء سندات الاستلام والصرف والتحويل والمرتجعات.
/// الصلاحيات: `documents.<action>` أو صلاحية شاشة المستند نفسها، والنطاق `canWh`،
/// والمستودع المجمّد للجرد يمنع التعديل والإلغاء.
class DocLogView extends StatefulWidget {
  const DocLogView({super.key, this.kinds, this.embedded = false, this.extraActions});

  /// أنواع السندات المعروضة. `null` يعني كل ما يسمح به المستخدم — تستعمله
  /// الشاشة العامة، بينما تمرّر كل شاشة حركة نوعها وحده.
  final Set<DocKind>? kinds;

  /// مدمج داخل تبويب شاشة أخرى: بلا عنوان صفحة ولا مرشّح نوع.
  final bool embedded;

  /// أزرار إضافية خاصة بالشاشة المضيفة تُعرض بجوار الإجراءات القياسية
  /// (مثل «تعديل القوة» في أوامر الصرف). `reload` يعيد تحميل السجل بعدها.
  final List<Widget> Function(DocumentSummary doc, Future<void> Function() reload)? extraActions;

  @override
  State<DocLogView> createState() => _DocLogViewState();
}

/// `TYPES` في الويب.
class _DocType {
  const _DocType(this.kind, this.label, this.icon, this.perm, this.partyLbl);
  final DocKind kind;
  final String label;
  final String icon;

  /// الشاشة التي تُشتق منها الصلاحية حين لا يملك المستخدم صلاحية `documents`.
  final String perm;
  final String partyLbl;
}

const _types = <_DocType>[
  _DocType(DocKind.receipt, 'استلام بضاعة', 'download', 'receive', 'المورد'),
  _DocType(DocKind.issue, 'صرف بضاعة', 'upload', 'issue', 'الجهة المستفيدة'),
  _DocType(DocKind.transfer, 'تحويل مخزني', 'repeat', 'transfer', 'إلى المستودع'),
  _DocType(DocKind.returnDoc, 'مرتجعات', 'undo', 'returns', 'الجهة'),
];

_DocType _typeOf(DocKind k) => _types.firstWhere((t) => t.kind == k);

/// `STATUS` و`STATUS_CHIP`.
const _statusLabels = <String, String>{
  'COMPLETED': 'معتمد',
  'DRAFT': 'مسودة',
  'ORDER': 'أمر معلق',
  'PENDING': 'قيد الاستلام',
  'RECEIVED': 'مستلم',
  'REJECTED': 'مرفوض',
  'CANCELLED': 'ملغى',
};

/// رسالة نقص الرصيد بنص `editDoc()`: «✖ الرصيد لا يكفي للصنف …».
String _stockMessage(EditCheck check, Item? item) =>
    '✖ الرصيد لا يكفي للصنف «${item?.name ?? check.itemId}» (المتاح ${nf(check.available)})';

/// نص الكمية داخل حقل الإدخال — أرقام لاتينية كما في `input type=number`.
String _plain(double v) {
  final r = (v * 1000).round() / 1000;
  return r % 1 == 0 ? r.toInt().toString() : r.toString();
}

ImdTone _statusTone(String s) => switch (s) {
      'COMPLETED' || 'RECEIVED' => ImdTone.ok,
      'DRAFT' => ImdTone.off,
      'ORDER' || 'PENDING' => ImdTone.pend,
      'REJECTED' || 'CANCELLED' => ImdTone.err,
      _ => ImdTone.code,
    };

class _DocLogViewState extends State<DocLogView> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final DocumentsRepo _repo = DocumentsRepo(_db);
  late final MovementsRepo _mv = MovementsRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();

  DocKind? _type;
  String _from = '';
  String _to = '';
  String _wh = '';
  String _status = '';

  List<DocumentSummary>? _docs;
  List<Item> _items = const [];
  List<Warehouse> _whs = const [];
  List<Supplier> _sups = const [];

  /// أسماء الأصناف داخل كل سند — يحتاجها البحث كما في الويب (`g.lines.map(itemName)`).
  final _lineText = <String, String>{};

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

  // ───────── الصلاحيات ─────────
  bool _dp(String action) => _perm.has('documents', action);
  bool _allowed(_DocType t) => _dp(PermAction.view) || _perm.has(t.perm, PermAction.view);
  List<_DocType> get _allowedTypes {
    final only = widget.kinds;
    return _types
        .where((t) => _allowed(t) && (only == null || only.contains(t.kind)))
        .toList();
  }

  bool _canPrint(_DocType t) => _dp(PermAction.print) || _perm.has(t.perm, PermAction.print);
  bool _canEdit(DocumentSummary g) {
    final t = _typeOf(g.kind);
    return g.status != 'CANCELLED' &&
        _perm.canWh(g.warehouse) &&
        (_dp(PermAction.edit) || _perm.has(t.perm, PermAction.edit)) &&
        g.editable;
  }

  bool _canDelete(DocumentSummary g) {
    final t = _typeOf(g.kind);
    return g.status != 'CANCELLED' &&
        _perm.canWh(g.warehouse) &&
        (_dp(PermAction.delete) || _perm.has(t.perm, PermAction.delete));
  }

  // ───────── التحميل ─────────
  /// `load()`
  Future<void> _load() async {
    final kinds = _allowedTypes.map((t) => t.kind).toSet();
    final docs = await _repo.list(kinds: kinds, scope: _perm.scope);
    final items = await _db.select(_db.items).get();
    final whs = await _db.select(_db.warehouses).get();
    final sups = await _db.select(_db.suppliers).get();

    _lineText.clear();
    for (final d in docs) {
      final ls = await _repo.lines(d.kind, d.refNo);
      _lineText['${d.kind.name}:${d.refNo}'] = ls.map((l) => l.itemName).join(' ').toLowerCase();
    }
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _items = items;
      _whs = whs;
      _sups = sups;
    });
  }

  /// زر «تحديث» في شريط المرشّحات.
  Future<void> _refresh() async {
    await _load();
    if (mounted) showImdToast(context, '✔ تم التحديث');
  }

  /// `filtered()` — الحالة الفارغة تُخفي الملغى كما في الويب.
  List<DocumentSummary> _filtered() {
    final q = _q.text.trim().toLowerCase();
    return (_docs ?? const <DocumentSummary>[]).where((g) {
      if (_type != null && g.kind != _type) return false;
      if (_from.isNotEmpty && g.date.compareTo(_from) < 0) return false;
      if (_to.isNotEmpty && g.date.compareTo(_to) > 0) return false;
      if (_wh.isNotEmpty && g.warehouse != _wh && g.party != _wh) return false;
      if (_status.isNotEmpty) {
        if (g.status != _status) return false;
      } else if (g.status == 'CANCELLED') {
        return false;
      }
      if (q.isEmpty) return true;
      final line = _lineText['${g.kind.name}:${g.refNo}'] ?? '';
      return [g.refNo, g.party, g.warehouse, g.createdBy]
              .any((v) => v.toLowerCase().contains(q)) ||
          line.contains(q);
    }).toList();
  }

  /// `statusLbl(g)` — المرتجع غير الملغى يعرض نوعه وحالته بدل كلمة «معتمد».
  String _statusLabel(DocumentSummary g) {
    if (g.kind == DocKind.returnDoc && g.status != 'CANCELLED') {
      return g.returnType == 'TO_SUPPLIER' ? 'إلى مورد' : 'من وحدة — ${g.condition}';
    }
    return _statusLabels[g.status] ?? (g.status.isEmpty ? '—' : g.status);
  }

  Item? _itemById(String id) {
    for (final it in _items) {
      if (it.id == id) return it;
    }
    return null;
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    final types = _allowedTypes;
    if (types.isEmpty) {
      const denied = ImdPanel(child: ImdLd('لا تملك صلاحية عرض أي نوع من المستندات.'));
      return widget.embedded ? denied : const ImdPage(children: [denied]);
    }
    final scope = _perm.scope;
    final rows = _filtered();

    final body = <Widget>[
      if (!widget.embedded)
        ImdPageTitle(
          title: 'سجل المستندات',
          icon: 'folder',
          subtitle: 'عرض وطباعة وتعديل سندات الاستلام والصرف والتحويل والمرتجعات حسب صلاحياتك'
              '${scope == null ? '' : ' — نطاقك: ${scope.join('، ')}'}',
        ),
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdGrid(columns: 6, minItemWidth: 170, gap: 12, children: [
            if (types.length > 1)
              ImdLabeled(
                'نوع المستند',
                ImdSelect<String>(
                  items: [('', 'الكل'), for (final t in types) (t.kind.name, t.label)],
                  value: _type?.name ?? '',
                  onChanged: (v) => setState(() =>
                      _type = (v == null || v.isEmpty) ? null : DocKind.values.byName(v)),
                ),
              ),
            ImdLabeled('من تاريخ', ImdDateField(value: _from, onChanged: (v) => setState(() => _from = v))),
            ImdLabeled('إلى تاريخ', ImdDateField(value: _to, onChanged: (v) => setState(() => _to = v))),
            ImdLabeled(
              'المستودع',
              ImdSelect<String>(
                items: [
                  ('', 'الكل'),
                  for (final w in _whs.where((w) => _perm.canWh(w.name))) (w.name, w.name),
                ],
                value: _wh,
                onChanged: (v) => setState(() => _wh = v ?? ''),
              ),
            ),
            ImdLabeled(
              'الحالة',
              ImdSelect<String>(
                items: [
                  ('', 'الكل (بدون الملغى)'),
                  for (final e in _statusLabels.entries) (e.key, e.value),
                ],
                value: _status,
                onChanged: (v) => setState(() => _status = v ?? ''),
              ),
            ),
            ImdLabeled(
              'بحث',
              ImdFld(
                controller: _q,
                hint: 'رقم السند، الجهة، الصنف…',
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ImdButton.outline(
              label: 'تحديث',
              icon: 'refresh',
              small: true,
              onPressed: _refresh,
            ),
            const SizedBox(width: 8),
            ImdChip('المستندات: ${nf(rows.length)}', tone: ImdTone.ok),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      if (_docs == null)
        const ImdLd('جارٍ التحميل…')
      else
        ImdTable(
          columns: const [
            ImdCol('النوع'),
            ImdCol('رقم السند'),
            ImdCol('التاريخ'),
            ImdCol('المستودع'),
            ImdCol('الجهة'),
            ImdCol('الأصناف', numeric: true),
            ImdCol('الحالة'),
            ImdCol('المُنشئ'),
            ImdCol('إجراءات'),
          ],
          empty: 'لا توجد مستندات مطابقة',
          rows: [
            for (final g in rows.take(1500)) _row(g),
          ],
        ),
    ];

    // مدمجًا: تُعاد قائمة العناصر داخل عمود لتضعها الشاشة المضيفة في تبويبها.
    return widget.embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)
        : ImdPage(children: body);
  }

  List<Widget> _row(DocumentSummary g) {
    final t = _typeOf(g.kind);
    return [
      // أيقونة ونص مضمَّنان كما في `ic(ty.icon)+' '+ty.label` — يلتفان معًا عند ضيق العمود.
      Text.rich(TextSpan(children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ImdIcon(t.icon, size: 15, color: context.imd.muted),
          ),
        ),
        TextSpan(text: t.label),
      ])),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(g.refNo, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (g.editCount > 0) ImdChip('معدّل ${nf(g.editCount)}', tone: ImdTone.code),
      ]),
      Text(g.date.isEmpty ? '—' : g.date),
      Text(g.warehouse.isEmpty ? '—' : g.warehouse),
      Text(g.party.isEmpty ? '—' : g.party),
      Text(nf(g.linesCount)),
      ImdChip(_statusLabel(g), tone: _statusTone(g.status)),
      Text(g.createdBy.isEmpty ? '—' : g.createdBy),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ImdButton.outline(label: 'عرض', icon: 'eye', small: true, onPressed: () => _view(g)),
        if (_canPrint(t))
          ImdButton.outline(label: 'طباعة', icon: 'printer', small: true, onPressed: () => _print(g)),
        if (_canEdit(g)) ImdButton(label: 'تعديل', icon: 'edit', small: true, onPressed: () => _edit(g)),
        if (_canDelete(g))
          ImdButton(
            label: 'إلغاء',
            icon: 'ban',
            small: true,
            kind: ImdBtnKind.danger,
            onPressed: () => _cancel(g),
          ),
        ...?widget.extraActions?.call(g, _load),
      ]),
    ];
  }

  // ───────── عرض ─────────
  /// `viewDoc(g)`
  Future<void> _view(DocumentSummary g) async {
    final t = _typeOf(g.kind);
    final lines = await _repo.lines(g.kind, g.refNo);
    if (!mounted) return;
    await showImdModal<void>(
      context,
      title: '${t.label} — ${g.refNo}',
      icon: t.icon,
      maxWidth: 980,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdGrid(columns: 6, minItemWidth: 180, gap: 8, children: [
          _info('التاريخ', g.date.isEmpty ? '—' : g.date),
          _info('المستودع', g.warehouse.isEmpty ? '—' : g.warehouse),
          _info(t.partyLbl, g.party.isEmpty ? '—' : g.party),
          _info('الحالة', _statusLabel(g)),
          _info('المُنشئ', g.createdBy.isEmpty ? '—' : g.createdBy),
          _info('ملاحظات', g.notes.isEmpty ? '—' : g.notes),
        ]),
        const SizedBox(height: 10),
        ImdTable(
          columns: [
            const ImdCol('م', numeric: true),
            const ImdCol('الكود'),
            const ImdCol('الصنف'),
            const ImdCol('الكمية', numeric: true),
            const ImdCol('الوحدة'),
            const ImdCol('بوحدة الأساس', numeric: true),
            if (g.kind == DocKind.issue) const ImdCol('المستفيد'),
            const ImdCol('ملاحظات'),
          ],
          rows: [
            for (final (i, l) in lines.indexed)
              [
                Text(nf(i + 1)),
                Text(l.itemCode),
                Text(l.itemName),
                Text(nf(l.qty)),
                Text(l.unitName),
                Text('${nf(l.baseQty)} ${_itemById(l.itemId)?.baseUnit ?? ''}'.trim()),
                if (g.kind == DocKind.issue)
                  Text(l.beneficiaryUnitName.isEmpty ? '—' : l.beneficiaryUnitName),
                Text(l.notes.isEmpty ? '—' : l.notes),
              ],
          ],
        ),
        if (g.editLog.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            ImdIcon('clock', size: 16, color: ctx.imd.accent),
            const SizedBox(width: 6),
            Text('سجل التعديلات',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ctx.imd.text)),
          ]),
          const SizedBox(height: 6),
          for (final e in g.editLog)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('${arDigits(e.at)} — ${e.by}: ${e.summary}',
                  style: TextStyle(fontSize: 12.5, color: ctx.imd.muted, height: 1.9)),
            ),
        ],
        if (g.cancelReason.isNotEmpty) ...[
          const SizedBox(height: 10),
          ImdNote('سبب الإلغاء: ${g.cancelReason}'),
        ],
      ]),
      actions: (ctx) => [ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop())],
    );
  }

  Widget _info(String label, String value) => Builder(builder: (ctx) {
        final c = ctx.imd;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: c.bg,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
            Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
          ]),
        );
      });

  // ───────── طباعة ─────────
  /// `printDoc(g)`
  Future<void> _print(DocumentSummary g) async {
    final t = _typeOf(g.kind);
    if (!_canPrint(t)) {
      showImdToast(context, '✖ لا تملك صلاحية طباعة المستندات المحفوظة', error: true);
      return;
    }
    final lines = await _repo.lines(g.kind, g.refNo);
    final raw = await _repo.rawLines(g.kind, g.refNo);
    if (lines.isEmpty || raw.isEmpty || !mounted) return;
    final head = raw.first;
    // الصرف متعدد الجهات (targetType = 3) يُطبع بعمود الوحدة المستفيدة.
    final multi = g.kind == DocKind.issue && (head.targetType as int) == 3;
    try {
      await VoucherPrint.print(
        db: _db,
        title: t.label,
        kind: switch (g.kind) {
          DocKind.receipt => VoucherKind.receive,
          DocKind.issue => VoucherKind.issue,
          DocKind.transfer => VoucherKind.transfer,
          DocKind.returnDoc =>
            g.returnType == 'TO_SUPPLIER' ? VoucherKind.returnToSupplier : VoucherKind.returnFromUnit,
        },
        refNo: g.refNo,
        date: g.date,
        warehouse: g.warehouse,
        party: g.party,
        notes: g.notes,
        multiUnit: multi,
        invoiceNo: g.kind == DocKind.receipt ? head.invoiceNo as String : '',
        audit: g.kind == DocKind.receipt ? head.audit as String : '',
        supervision: g.kind == DocKind.receipt ? head.supervision as String : '',
        statusLabel: _statusLabel(g),
        condition: g.kind == DocKind.returnDoc ? g.condition : '',
        origRef: g.kind == DocKind.returnDoc ? head.origRef as String : '',
        strength: g.kind == DocKind.issue ? nf(head.soldierCount as num) : '',
        days: g.kind == DocKind.issue ? nf(head.durationDays as num) : '',
        lines: [
          for (final l in lines)
            VoucherLine(
              itemName: l.itemName,
              unitName: l.unitName,
              qty: l.qty,
              itemCode: l.itemCode,
              notes: l.notes,
              beneficiary: l.beneficiaryUnitName,
            ),
        ],
      );
    } catch (e) {
      if (mounted) showImdToast(context, '✖ خدمة الطباعة غير متاحة: $e', error: true);
    }
  }

  // ───────── فحوص مشتركة ─────────
  /// `checkWrite(g, action, newWh)`
  Future<bool> _checkWrite(DocumentSummary g, String action, {String newWh = ''}) async {
    final t = _typeOf(g.kind);
    if (!(_dp(action) || _perm.has(t.perm, action))) {
      showImdToast(context,
          '✖ لا تملك صلاحية ${action == PermAction.edit ? 'تعديل' : 'إلغاء'} المستندات المحفوظة (${t.label})',
          error: true);
      return false;
    }
    // نطاق الصلاحيات: التحويل يُفحص على مستودعه المصدر فقط، والباقي على كل مستودعاته.
    final all = <String>{
      g.warehouse,
      if (g.destWarehouse.isNotEmpty) g.destWarehouse,
      if (newWh.isNotEmpty) newWh,
    }..removeWhere((w) => w.isEmpty);
    final src = g.kind == DocKind.transfer
        ? (<String>{g.warehouse, if (newWh.isNotEmpty) newWh}..removeWhere((w) => w.isEmpty))
        : all;
    for (final w in src) {
      if (!_perm.canWh(w)) {
        showImdToast(context, Perm.scopeBlock(w), error: true);
        return false;
      }
    }
    for (final w in all) {
      final no = await _mv.frozenOrder(w);
      if (no != null) {
        if (mounted) showImdToast(context, '✖ المستودع «$w» مجمّد بسبب الجرد $no', error: true);
        return false;
      }
    }
    return true;
  }

  // ───────── تعديل ─────────
  /// `editDoc(g)`
  Future<void> _edit(DocumentSummary g) async {
    final t = _typeOf(g.kind);
    if (!g.editable) {
      showImdToast(context, '✖ لا يمكن تعديل هذا المستند في حالته الحالية', error: true);
      return;
    }
    final lines = await _repo.lines(g.kind, g.refNo);
    if (!mounted) return;
    final saved = await showImdModal<bool>(
      context,
      title: 'تعديل ${t.label} — ${g.refNo}',
      icon: 'edit',
      maxWidth: 980,
      builder: (ctx) => _EditForm(
        doc: g,
        type: t,
        lines: lines,
        items: _items,
        warehouses: _whs,
        suppliers: _sups,
        perm: _perm,
        repo: _repo,
        mv: _mv,
        catalog: CatalogRepo(_db),
        checkWrite: (newWh) => _checkWrite(g, PermAction.edit, newWh: newWh),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ تعديل المستند ${g.refNo}');
    }
  }

  // ───────── إلغاء ─────────
  /// `cancelDoc(g)`
  Future<void> _cancel(DocumentSummary g) async {
    final t = _typeOf(g.kind);
    if (!await _checkWrite(g, PermAction.delete)) return;
    if (!mounted) return;
    final affects = g.context.sign != 0;
    final why = await imdPrompt(
      context,
      'إلغاء ${t.label} «${g.refNo}»${affects ? ' سيعكس أثره على الأرصدة' : ''}.\nاكتب سبب الإلغاء:',
      ok: 'تأكيد الإلغاء',
    );
    if (why == null) return;
    if (why.trim().isEmpty) {
      if (mounted) showImdToast(context, '✖ سبب الإلغاء مطلوب', error: true);
      return;
    }
    final available = await _mv.balances(scope: _perm.scope);
    final check = await _repo.cancel(
      doc: g,
      reason: why.trim(),
      availableBaseQty: available,
      cancelledBy: _perm.email,
    );
    if (!mounted) return;
    if (!check.ok) {
      showImdToast(context, _stockMessage(check, _itemById(check.itemId)), error: true);
      return;
    }
    await _load();
    if (mounted) {
      showImdToast(context,
          '✔ أُلغي المستند ${g.refNo}${affects ? ' وعُكس أثره على الأرصدة' : ''}');
    }
  }
}

/// نموذج التعديل داخل النافذة — سطور قابلة للإضافة والحذف مع حقول الرأس وسبب التعديل.
class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.doc,
    required this.type,
    required this.lines,
    required this.items,
    required this.warehouses,
    required this.suppliers,
    required this.perm,
    required this.repo,
    required this.mv,
    required this.catalog,
    required this.checkWrite,
  });

  final DocumentSummary doc;
  final _DocType type;
  final List<DocumentLineRow> lines;
  final List<Item> items;
  final List<Warehouse> warehouses;
  final List<Supplier> suppliers;
  final Perm perm;
  final DocumentsRepo repo;
  final MovementsRepo mv;
  final CatalogRepo catalog;
  final Future<bool> Function(String newWh) checkWrite;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditRow {
  _EditRow({required this.itemId, required this.unitName, required this.qty, required this.notes, this.source});
  String itemId;
  String unitName;
  final TextEditingController qty;
  final TextEditingController notes;

  /// السطر الأصلي — منه تُنقل حقول المستفيد وإجراء الأسطوانة كما في الويب.
  DocumentLineRow? source;
}

class _EditFormState extends State<_EditForm> {
  late String _date = widget.doc.date;
  late String _wh = widget.doc.warehouse;
  late final TextEditingController _party = TextEditingController(text: widget.doc.party);
  late final TextEditingController _notes = TextEditingController(text: widget.doc.notes);
  final _reason = TextEditingController();
  final _rows = <_EditRow>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final l in widget.lines) {
      _rows.add(_EditRow(
        itemId: l.itemId,
        unitName: l.unitName,
        qty: TextEditingController(text: _plain(l.qty)),
        notes: TextEditingController(text: l.notes),
        source: l,
      ));
    }
  }

  @override
  void dispose() {
    _party.dispose();
    _notes.dispose();
    _reason.dispose();
    for (final r in _rows) {
      r.qty.dispose();
      r.notes.dispose();
    }
    super.dispose();
  }

  Item? _itemById(String id) {
    for (final it in widget.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// `unitsOf(it)`
  List<(String, double)> _unitsOf(Item? it) {
    if (it == null) return const [('وحدة', 1)];
    return [for (final u in widget.catalog.unitsOf(it)) (u.name, u.factor <= 0 ? 1.0 : u.factor)];
  }

  double _factorOf(Item? it, String unitName) {
    for (final u in _unitsOf(it)) {
      if (u.$1 == unitName) return u.$2;
    }
    return 1;
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      showImdToast(context, '✖ اكتب سبب التعديل', error: true);
      return;
    }
    final party = _party.text.trim();
    if (widget.doc.kind == DocKind.transfer && party == _wh) {
      showImdToast(context, '✖ لا يمكن التحويل إلى نفس المستودع', error: true);
      return;
    }

    final out = <DocumentLineRow>[];
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _itemById(r.itemId);
      final q = double.tryParse(r.qty.text.trim()) ?? 0;
      if (q <= 0) {
        showImdToast(context, '✖ كمية غير صالحة للصنف ${it?.name ?? ''}', error: true);
        return;
      }
      final f = _factorOf(it, r.unitName);
      out.add(DocumentLineRow(
        id: r.source?.id ?? '',
        itemId: r.itemId,
        itemCode: it?.code ?? '',
        itemName: it?.name ?? '',
        unitName: r.unitName.isNotEmpty ? r.unitName : (it?.baseUnit ?? ''),
        factor: f,
        qty: q,
        baseQty: (q * f * 1000).round() / 1000,
        notes: r.notes.text.trim(),
        beneficiaryUnitId: r.source?.beneficiaryUnitId ?? '',
        beneficiaryUnitName: r.source?.beneficiaryUnitName ?? '',
        cylinderAction: r.source?.cylinderAction ?? '',
      ));
    }
    if (out.isEmpty) {
      showImdToast(context, '✖ يجب أن يحتوي المستند على صنف واحد على الأقل', error: true);
      return;
    }
    if (!await widget.checkWrite(_wh)) return;

    setState(() => _busy = true);
    try {
      final available = await widget.mv.balances(scope: widget.perm.scope);
      final check = await widget.repo.saveEdit(
        doc: widget.doc,
        rows: out,
        reason: reason,
        availableBaseQty: available,
        date: _date.isNotEmpty ? _date : widget.doc.date,
        warehouse: _wh,
        party: party,
        headNotes: _notes.text.trim(),
        actor: widget.perm.email,
      );
      if (!mounted) return;
      if (!check.ok) {
        setState(() => _busy = false);
        showImdToast(context, _stockMessage(check, _itemById(check.itemId)), error: true);
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showImdToast(context, '✖ $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final t = widget.type;
    final isTransfer = doc.kind == DocKind.transfer;
    final supplierLike = doc.kind == DocKind.receipt || doc.returnType == 'TO_SUPPLIER';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (doc.context.sign != 0)
        ImdNote('المستند ${_statusLabels[doc.status] ?? doc.status}: '
            'سيُطبَّق فرق الكميات فقط على الأرصدة عند الحفظ.'),
      const SizedBox(height: 10),
      ImdGrid(columns: 4, minItemWidth: 200, gap: 10, children: [
        ImdLabeled('التاريخ', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
        ImdLabeled(
          isTransfer ? 'من المستودع' : 'المستودع',
          ImdSelect<String>(
            items: [
              for (final w in widget.warehouses.where((w) => widget.perm.canWh(w.name) || w.name == _wh))
                (w.name, w.name),
            ],
            value: _wh,
            onChanged: (v) => setState(() => _wh = v ?? _wh),
          ),
        ),
        ImdLabeled(
          t.partyLbl,
          isTransfer
              ? ImdSelect<String>(
                  items: [for (final w in widget.warehouses) (w.name, w.name)],
                  value: _party.text,
                  onChanged: (v) => setState(() => _party.text = v ?? ''),
                )
              : ImdFld(
                  controller: _party,
                  hint: supplierLike && widget.suppliers.isNotEmpty ? widget.suppliers.first.name : null,
                ),
        ),
        ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      ]),
      const SizedBox(height: 10),
      ImdLabeled('سبب التعديل *', ImdFld(controller: _reason, hint: 'مطلوب لسجل التدقيق')),
      const SizedBox(height: 12),
      ImdTable(
        columns: const [
          ImdCol('الصنف', auto: false, flex: 4),
          ImdCol('الوحدة', auto: false, flex: 2),
          ImdCol('الكمية', auto: false, flex: 2),
          ImdCol('ملاحظات', auto: false, flex: 3),
          ImdCol('', width: 52),
        ],
        rows: [
          for (final (i, r) in _rows.indexed) _lineRow(i, r),
        ],
      ),
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
          label: 'إضافة سطر',
          icon: 'plus',
          small: true,
          onPressed: () => setState(() => _rows.add(_EditRow(
                itemId: '',
                unitName: '',
                qty: TextEditingController(),
                notes: TextEditingController(),
              ))),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ImdButton(label: 'حفظ التعديلات', icon: 'save', onPressed: _busy ? null : _save),
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(context).pop(false)),
      ]),
    ]);
  }

  List<Widget> _lineRow(int i, _EditRow r) {
    final it = _itemById(r.itemId);
    final units = _unitsOf(it);
    if (r.unitName.isEmpty && units.isNotEmpty) r.unitName = units.first.$1;
    return [
      ImdItemPicker(
        items: widget.items,
        value: r.itemId,
        onChanged: (id) => setState(() {
          r.itemId = id;
          r.unitName = _unitsOf(_itemById(id)).first.$1;
        }),
      ),
      ImdSelect<String>(
        dense: true,
        items: [for (final u in units) (u.$1, u.$2 == 1 ? u.$1 : '${u.$1} ×${nf(u.$2)}')],
        value: r.unitName,
        onChanged: (v) => setState(() => r.unitName = v ?? r.unitName),
      ),
      ImdFld(controller: r.qty, number: true, dense: true),
      ImdFld(controller: r.notes, dense: true),
      ImdIconButton(
        icon: 'trash',
        kind: ImdBtnKind.danger,
        tooltip: 'حذف السطر',
        onPressed: () => setState(() {
          final row = _rows.removeAt(i);
          row.qty.dispose();
          row.notes.dispose();
        }),
      ),
    ];
  }
}
