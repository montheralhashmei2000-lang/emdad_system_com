part of '../issue_screen.dart';

/// معالجة أسطر الأصناف: الاختيار والتجميع والمسح.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueRows on _IssueBase, _IssueBeneficiary {
  void _onItem(_Row r, String id) {
    final it = _item(id);
    setState(() {
      r.itemId = id;
      final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
      r.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
      if (r.benUnit.isEmpty && _units.isNotEmpty) r.benUnit = _units.first.id;
      _calcRow(r);
      if (it != null && !r.noAuto && identical(_rows.last, r)) _rows.add(_newRow(benUnit: _units.isNotEmpty ? _units.first.id : ''));
    });
  }

  /// `issCollect()`
  ({List<DocLineInput> rows, String err}) _collect() {
    final rows = <DocLineInput>[];
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _item(r.itemId);
      if (it == null) continue;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) return (rows: rows, err: '✖ أدخل كمية صالحة للصنف ${it.name}');
      final factor = _catalog.factorOf(it, r.unit);
      final have = _whBal[it.id] ?? 0;
      if (_wh.isNotEmpty && IssueRules.shortage([(it.id, qty * factor)], _whBal) != null) {
        return (rows: rows, err: '✖ رصيد «${it.name}» في مستودع «$_wh» لا يكفي (${nf(have)} متاح)');
      }
      final ben = _type == 3 ? _units.where((u) => u.id == r.benUnit).firstOrNull : null;
      rows.add(DocLineInput(
        itemId: it.id,
        itemCode: it.code,
        itemName: it.name,
        unitName: r.unit,
        factor: factor,
        qty: qty,
        notes: r.notes.text.trim(),
        cylinderAction: it.isRefillable ? r.cy : '',
        beneficiaryUnitId: ben?.id ?? '',
        beneficiaryUnitName: ben == null ? '' : '${ben.code} — ${ben.name}',
      ));
    }
    return (rows: rows, err: '');
  }

  /// مجموع الخصم لكل صنف مقابل رصيد المستودع (`stockErrorFromMap`).
  String _balError(List<DocLineInput> rows) {
    final short = IssueRules.shortage([for (final r in rows) (r.itemId, r.baseQty)], _whBal);
    return short == null ? '' : MovementsRepo.stockError(_item(short.itemId), _wh, short.available, short.requested);
  }

  /// التجميع التلقائي وإعادة التوزيع على الوحدات — يحل محل زر «دمج التكرار».
  ///
  /// يُستدعى عند مغادرة حقل الكمية وعند إضافة سطر جديد. الصنف الواحد للجهة
  /// الواحدة يُجمع ولو اختلفت وحداته، ثم يُعاد توزيعه من الأكبر إلى الأصغر.
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

    // الجهة المستفيدة وعملية الأسطوانة لا يصح خلطها، فتدخل في مفتاح المجموعة.
    String keyOf(_Row r) {
      final it = _item(r.itemId)!;
      return '${r.itemId}|${r.benUnit}|${it.isRefillable ? r.cy : ''}';
    }

    final notesOf = <String, String>{};
    for (final r in complete) {
      final k = keyOf(r);
      if ((notesOf[k] ?? '').isEmpty) notesOf[k] = r.notes.text;
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

    final before = [for (final r in complete) '${keyOf(r)}|${r.unit}|${r.qty.text.trim()}'];
    final after = [for (final l in consolidated) '${l.groupKey}|${l.unitName}|${_num(l.qty)}'];
    if (before.join('§') == after.join('§')) return;

    setState(() {
      for (final r in complete) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final l in consolidated)
            _newRow(
              itemId: l.groupKey.split('|')[0],
              unit: l.unitName,
              qty: l.qty,
              notes: notesOf[l.groupKey] ?? '',
              benUnit: l.groupKey.split('|')[1],
              noAuto: true,
            )..cy = l.groupKey.split('|')[2].isEmpty ? 'EXCHANGE' : l.groupKey.split('|')[2],
          ...pending,
        ]);
      if (_rows.isEmpty) _rows.add(_newRow());
    });
  }

  /// `issScanGo()`
  void _scan(String code) {
    final it = _items.where((x) => x.barcode == code || x.code == code).firstOrNull;
    if (it == null) return showImdToast(context, '✖ الباركود/الكود غير معرّف');
    for (final r in _rows) {
      if (r.itemId == it.id) {
        r.qty.text = _num((double.tryParse(r.qty.text) ?? 0) + 1);
        _autoConsolidate();
        return;
      }
    }
    final row = _newRow(qty: 1);
    setState(() => _rows.add(row));
    _onItem(row, it.id);
    showImdToast(context, '➕ أُضيف: ${it.name}');
  }
}
