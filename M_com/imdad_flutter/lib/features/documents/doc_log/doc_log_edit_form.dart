part of '../doc_log_view.dart';

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

  /// السطر الأصلي — منه تُنقل حقول المستفيد وإجراء الأسطوانة.
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
        expiryDate: r.source?.expiryDate ?? '',
      ));
    }
    if (out.isEmpty) {
      showImdToast(context, '✖ يجب أن يحتوي المستند على صنف واحد على الأقل', error: true);
      return;
    }
    if (!await widget.checkWrite(_wh)) return;

    setState(() => _busy = true);
    try {
      final check = await widget.repo.saveEdit(
        doc: widget.doc,
        rows: out,
        reason: reason,
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
        pageSize: 50,
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
