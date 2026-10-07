import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/print/money_receipt_print.dart';
import '../../core/print/print_format.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/access_control.dart';
import 'link_export.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

String _methodLabel(String m) => switch (m) {
      'cash' => 'كاش',
      'transfer' => 'حوالة مالية',
      _ => '—',
    };

/// تبويب «استلام مبلغ مالي» في المالية: سنداتٌ تُسجَّل وتُطبع على نموذج الجهة
/// (سندٌ واحد في الصفحة)، والمبلغ بالحروف يُكتب تلقائيًّا من المبلغ رقمًا.
class MoneyReceiptsTab extends StatefulWidget {
  const MoneyReceiptsTab({super.key, required this.repo, required this.perm});

  final LinkageRepo repo;
  final Perm perm;

  @override
  State<MoneyReceiptsTab> createState() => _MoneyReceiptsTabState();
}

class _MoneyReceiptsTabState extends State<MoneyReceiptsTab> {
  final _q = TextEditingController();
  List<LinkMoneyReceipt>? _rows;
  List<String> _names = const [];

  bool get _canCreate => widget.perm.has('linkages', PermAction.create);
  bool get _canEdit => widget.perm.has('linkages', PermAction.edit);
  bool get _canDelete => widget.perm.has('linkages', PermAction.delete);
  bool get _canExport => widget.perm.has('linkages', PermAction.export);
  bool get _canPrint => widget.perm.has('linkages', PermAction.print);

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
    final rows = await widget.repo.moneyReceipts();
    final persons = await widget.repo.persons();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _names = ({for (final p in persons) p.fullName.trim()}..remove('')).toList()..sort();
    });
  }

  List<LinkMoneyReceipt> get _filtered {
    final q = _q.text.trim().toLowerCase();
    return (_rows ?? const <LinkMoneyReceipt>[]).where((r) {
      if (q.isEmpty) return true;
      return [r.receiverName, r.capacity, r.purpose, r.delivererName, r.transferNo].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _edit([LinkMoneyReceipt? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    if (initial != null && !_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: initial == null ? 'استلام مبلغ مالي' : 'تعديل سند الاستلام',
      icon: 'dollar',
      maxWidth: 760,
      builder: (ctx) => _ReceiptForm(
        repo: widget.repo,
        initial: initial,
        names: _names,
        actor: widget.perm.email,
        canPrint: _canPrint,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ السند');
    }
  }

  Future<void> _print(LinkMoneyReceipt? r) async {
    if (!_canPrint) return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    try {
      await MoneyReceiptPrint.print(widget.repo.db, r);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  Future<void> _delete(LinkMoneyReceipt r) async {
    if (!await imdConfirm(context, 'حذف سند الاستلام للمستلم «${r.receiverName}» نهائيًّا؟', ok: 'حذف', danger: true)) return;
    await widget.repo.deleteMoneyReceipt(r, actor: widget.perm.email);
    await _load();
  }

  Future<void> _export() async {
    final rows = _filtered;
    await linkExportExcel(
      context,
      sheetName: 'استلام مبالغ مالية',
      fileName: 'استلام-مبالغ-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'المستلم', 'بصفته', 'المبلغ', 'العملة', 'كتابةً', 'التاريخ', 'مقابل', 'الطريقة', 'رقم الحوالة', 'المسلِّم'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].receiverName,
            rows[i].capacity,
            printNum(rows[i].amount),
            LinkCurrency.label(rows[i].currency),
            MoneyReceiptPrint.words(rows[i].amount, rows[i].currency),
            _d(rows[i].receiptDate),
            rows[i].purpose,
            _methodLabel(rows[i].method),
            rows[i].transferNo,
            rows[i].delivererName,
          ],
      ],
      numericColumns: const {0, 3},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final all = _rows ?? const <LinkMoneyReceipt>[];
    double sum(String cur) => all.where((r) => r.currency == cur).fold<double>(0, (s, r) => s + r.amount);
    final rows = _filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdKpis(children: [
        ImdKpi(label: 'عدد السندات', value: nf(all.length), icon: 'file', color: c.accent),
        ImdKpi(label: 'إجمالي بالسعودي', value: '${nf(sum(LinkCurrency.sar))} ر.س', icon: 'dollar', color: c.info),
        ImdKpi(label: 'إجمالي باليمني', value: '${nf(sum(LinkCurrency.yer))} ر.ي', icon: 'dollar', color: c.warn),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالمستلم أو الصفة أو الغرض…',
        onChanged: (_) => setState(() {}),
        actions: [
          if (_canPrint) ImdButton.outline(label: 'نموذج فارغ', icon: 'printer', small: true, onPressed: () => _print(null)),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _export),
          if (_canCreate) ImdButton(label: 'استلام مبلغ مالي', icon: 'plus', onPressed: _edit),
        ],
      ),
      if (_rows == null)
        const ImdLd('جارٍ تحميل السندات…')
      else if (rows.isEmpty)
        const ImdEmptyBox('لا سندات استلام بعد')
      else
        ImdTable(
          columns: const [
            ImdCol('المستلم', flex: 2),
            ImdCol('بصفته'),
            ImdCol('المبلغ', numeric: true),
            ImdCol('التاريخ'),
            ImdCol('مقابل', flex: 2),
            ImdCol('الطريقة'),
            ImdCol(''),
          ],
          rows: [for (final r in rows) _row(context, r)],
          empty: 'لا سندات مطابقة',
          onRowTap: null,
        ),
    ]);
  }

  List<Widget> _row(BuildContext context, LinkMoneyReceipt r) {
    final c = context.imd;
    return [
      Text(r.receiverName.isEmpty ? '—' : r.receiverName, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text(r.capacity.isEmpty ? '—' : r.capacity),
      Text(r.amount <= 0 ? '—' : '${printNum(r.amount)} ${LinkCurrency.symbol(r.currency)}'),
      Text(_d(r.receiptDate)),
      Text(r.purpose.isEmpty ? '—' : r.purpose),
      Text(r.method == 'transfer' && r.transferNo.isNotEmpty ? 'حوالة ${r.transferNo}' : _methodLabel(r.method)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (_canPrint) ImdIconButton(icon: 'printer', tooltip: 'طباعة', onPressed: () => _print(r)),
        if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(r)),
        if (_canDelete) ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _delete(r)),
      ]),
    ];
  }
}

// ═════════════════════ نموذج السند ═════════════════════

class _ReceiptForm extends StatefulWidget {
  const _ReceiptForm({
    required this.repo,
    required this.names,
    required this.actor,
    required this.canPrint,
    this.initial,
  });

  final LinkageRepo repo;
  final LinkMoneyReceipt? initial;
  final List<String> names;
  final String actor;
  final bool canPrint;

  @override
  State<_ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends State<_ReceiptForm> {
  final _receiver = TextEditingController();
  final _capacity = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  final _transferNo = TextEditingController();
  final _deliverer = TextEditingController();
  final _attachments = TextEditingController();
  String _currency = LinkCurrency.sar;
  String _date = isoDay(DateTime.now());
  String _method = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r == null) return;
    _receiver.text = r.receiverName;
    _capacity.text = r.capacity;
    _amount.text = r.amount > 0 ? printNum(r.amount).replaceAll(',', '') : '';
    _purpose.text = r.purpose;
    _transferNo.text = r.transferNo;
    _deliverer.text = r.delivererName;
    _attachments.text = r.attachments;
    _currency = r.currency;
    _date = r.receiptDate;
    _method = r.method;
  }

  @override
  void dispose() {
    for (final c in [_receiver, _capacity, _amount, _purpose, _transferNo, _deliverer, _attachments]) {
      c.dispose();
    }
    super.dispose();
  }

  /// المبلغ رقمًا — يقبل الأرقام الهندية والفاصلة العربية.
  double get _amountValue {
    final t = _amount.text
        .trim()
        .replaceAll(RegExp(r'[٬,\s]'), '')
        .replaceAll('٫', '.')
        .replaceAllMapped(RegExp(r'[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');
    return double.tryParse(t) ?? 0;
  }

  LinkMoneyReceiptsCompanion _companion() => LinkMoneyReceiptsCompanion(
        id: Value(widget.initial?.id ?? Ids.next('mr')),
        receiverName: Value(_receiver.text.trim()),
        capacity: Value(_capacity.text.trim()),
        amount: Value(_amountValue),
        currency: Value(_currency),
        receiptDate: Value(_date),
        purpose: Value(_purpose.text.trim()),
        method: Value(_method),
        transferNo: Value(_method == 'transfer' ? _transferNo.text.trim() : ''),
        delivererName: Value(_deliverer.text.trim()),
        attachments: Value(_attachments.text.trim()),
        createdBy: widget.initial == null ? Value(widget.actor) : const Value.absent(),
        createdAt: widget.initial == null ? Value(DateTime.now()) : const Value.absent(),
      );

  Future<LinkMoneyReceipt?> _save() async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final comp = _companion();
      await widget.repo.saveMoneyReceipt(comp, actor: widget.actor);
      final saved = await widget.repo.moneyReceiptById(comp.id.value);
      return saved;
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final words = MoneyReceiptPrint.words(_amountValue, _currency);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('كل الحقول اختيارية — ما يُترك فارغًا يُطبع نقاطًا ليُملأ بخط اليد. يُطبع سندٌ واحد في الصفحة.'),
      ImdGrid(columns: 2, minItemWidth: 220, gap: 10, children: [
        ImdLabeled('استلمت أنا', ImdFld(controller: _receiver, suggestions: widget.names, onChanged: (_) => setState(() {}))),
        ImdLabeled('بصفتي', ImdFld(controller: _capacity)),
      ]),
      ImdGrid(columns: 3, minItemWidth: 200, gap: 10, children: [
        ImdLabeled('المبلغ رقمًا', ImdFld(controller: _amount, number: true, onChanged: (_) => setState(() {}))),
        ImdLabeled(
          'العملة',
          ImdSelect<String>(
            items: [for (final e in LinkCurrency.labels.entries) (e.key, e.value)],
            value: _currency,
            onChanged: (v) => setState(() => _currency = v ?? LinkCurrency.sar),
          ),
        ),
        ImdLabeled('التاريخ', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
      ]),
      ImdLabeled(
        'المبلغ كتابةً (تلقائي)',
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.subtle,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            words.isEmpty ? 'يُكتب هنا تلقائيًّا عند إدخال المبلغ رقمًا' : words,
            style: TextStyle(color: words.isEmpty ? c.muted : c.text, fontWeight: FontWeight.w600, height: 1.6),
          ),
        ),
      ),
      ImdLabeled('وذلك مقابل', ImdFld(controller: _purpose)),
      ImdGrid(columns: 2, minItemWidth: 220, gap: 10, children: [
        ImdLabeled(
          'طريقة التسليم',
          ImdSelect<String>(
            items: const [('', 'غير محدد'), ('cash', 'كاش'), ('transfer', 'حوالة مالية')],
            value: _method,
            onChanged: (v) => setState(() => _method = v ?? ''),
          ),
        ),
        if (_method == 'transfer') ImdLabeled('رقم الحوالة', ImdFld(controller: _transferNo)) else const SizedBox.shrink(),
      ]),
      ImdGrid(columns: 2, minItemWidth: 220, gap: 10, children: [
        ImdLabeled('اسم المسلِّم', ImdFld(controller: _deliverer, suggestions: widget.names)),
        ImdLabeled('المرفقات', ImdFld(controller: _attachments)),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        if (widget.canPrint)
          ImdButton.outline(
            label: 'حفظ وطباعة',
            icon: 'printer',
            busy: _busy,
            onPressed: () async {
              final nav = Navigator.of(context);
              final saved = await _save();
              if (saved == null) return;
              await MoneyReceiptPrint.print(widget.repo.db, saved);
              nav.pop(true);
            },
          ),
        ImdButton(
          label: 'حفظ',
          icon: 'save',
          busy: _busy,
          onPressed: () async {
            final nav = Navigator.of(context);
            final saved = await _save();
            if (saved != null) nav.pop(true);
          },
        ),
      ]),
    ]);
  }
}
