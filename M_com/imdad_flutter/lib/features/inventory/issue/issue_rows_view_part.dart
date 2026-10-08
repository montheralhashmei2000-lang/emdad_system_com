part of '../issue_screen.dart';

/// عرض أسطر الصرف: تلميح الوحدة الأساسية وجدول سطح المكتب.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueRowsView on _IssueBase, _IssueBeneficiary, _IssueRows {
  // يُنفَّذ في الواجهة الأصلية (issue_screen.dart).
  Widget _rowView(BuildContext context, int index, _Row r);

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
  /// المكتب (خليةٌ عاريةٌ تحت رأسٍ مشترك) بلا تكرار سطرٍ واحد.
  ({
    bool refill,
    Widget balance,
    Widget picker,
    Widget ben,
    Widget unit,
    Widget qty,
    Widget notes,
    Widget cy,
    Widget delete,
  }) _rowFields(_Row r) {
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final shown = it == null ? null : displayBalance(it, _whBal[it.id] ?? 0);
    final picker = ImdItemPicker(
      items: _items,
      value: r.itemId,
      detailOf: (i) => 'رصيد ${nf(_whBal[i.id] ?? 0)}',
      onChanged: (v) {
        _onItem(r, v);
        _scheduleAutosave();
      },
    );
    final balance =
        ImdEntryBalanceCell(shown == null ? '' : '${nf(shown.qty)} ${shown.unit}');
    final ben = ImdSelect<String>(
      value: r.benUnit.isEmpty && _units.isNotEmpty ? _units.first.id : r.benUnit,
      items: [for (final u in _units) (u.id, '${u.code} — ${u.name}')],
      onChanged: (v) {
        setState(() => r.benUnit = v ?? '');
        _scheduleAutosave();
      },
    );
    final unit = ImdUnitPicker(
      units: [for (final u in units) u.name],
      value: r.unit,
      onChanged: (v) {
        _scheduleAutosave();
        setState(() {
          final next = v;
          final previous = r.unit;
          final qty = double.tryParse(r.qty.text.trim()) ?? 0;
          r.unit = next;
          // الاستحقاق أولى إن انطبق؛ وإلا تُحوَّل الكمية بمعامل الوحدتين
          // (١١٠٠ كجم ⇒ ٢٧٫٥ كيسًا) بدل بقاء الرقم على حاله.
          if (_calcRow(r)) return;
          final item = _item(r.itemId);
          if (item != null && qty > 0 && previous.isNotEmpty && next.isNotEmpty && next != previous) {
            imdSetText(
              r.qty,
              _num(convertQty(
                qty,
                _catalog.factorOf(item, previous),
                _catalog.factorOf(item, next),
              )),
            );
          }
        });
      },
    );
    // مغادرة الحقل تجمع الأصناف المكررة تلقائيًا وتعيد توزيع الوحدات.
    final qty = Focus(
      onFocusChange: (has) {
        if (!has) _autoConsolidate();
      },
      child: ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
    );
    final notes = ImdFld(controller: r.notes, hint: 'ملاحظات على هذا الصنف...');
    // **نوع العملية في صفّ الصنف لا تحته**: صندوقٌ مستقل يستقطع سطرًا لكل
    // أسطوانة، ويقطع تسلسل `Tab` من الكمية إلى السطر التالي.
    final refill = it != null && it.isRefillable;
    final cy = ImdSelect<String>(
      value: r.cy,
      items: CylAction.issueOptions,
      onChanged: (v) {
        setState(() => r.cy = v ?? r.cy);
        _scheduleAutosave();
      },
    );
    final delete = ImdIconButton(
      icon: 'x',
      tooltip: 'حذف السطر',
      kind: ImdBtnKind.danger,
      onPressed: () {
        setState(() {
          _rows.remove(r);
          r.dispose();
          if (_rows.isEmpty) _rows.add(_newRow());
        });
        _scheduleAutosave();
      },
    );
    return (
      refill: refill,
      balance: balance,
      picker: picker,
      ben: ben,
      unit: unit,
      qty: qty,
      notes: notes,
      cy: cy,
      delete: delete,
    );
  }

  /// عرض سطح المكتب: الجدول الكثيف المشترك — الأسلوب نفسه في كل السندات.
  ///
  /// «الوحدة المستفيدة» عمودٌ لا يظهر إلا في التوجيه متعدّد الوحدات، و«نوع
  /// العملية» يظهر إن كان في الجدول صنفٌ قابلٌ للتعبئة — شرطٌ على مستوى
  /// الجدول كلّه لا السطر الواحد، فلا تتبدّل الأعمدة وهي تُقرأ.
  Widget _desktopTable(BuildContext context) {
    final fields = [for (final r in _rows) _rowFields(r)];
    final multi = _type == 3;
    final anyRefill = fields.any((f) => f.refill);
    const cell = ImdEntryTable.cell;

    return ImdEntryTable(
      columns: [
        const ImdCol('الصنف', flex: 3),
        const ImdCol('الرصيد', width: 96),
        if (multi) const ImdCol('الوحدة المستفيدة', flex: 2),
        const ImdCol('الوحدة', width: 112),
        const ImdCol('الكمية', width: 88),
        if (anyRefill) const ImdCol('نوع العملية', width: 150),
        const ImdCol('ملاحظة', flex: 2),
        const ImdCol('', width: 56),
      ],
      rowKeys: [for (final r in _rows) r.key],
      rows: [
        for (final f in fields)
          [
            cell(f.picker),
            cell(f.balance),
            if (multi) cell(f.ben),
            cell(f.unit),
            cell(f.qty),
            if (anyRefill) cell(f.refill ? f.cy : const SizedBox.shrink()),
            cell(f.notes),
            cell(f.delete),
          ],
      ],
    );
  }
}
