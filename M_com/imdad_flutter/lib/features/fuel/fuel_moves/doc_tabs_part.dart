part of '../fuel_moves_screen.dart';

/// تبويبات السندات المعلّقة داخل الجلسة (زر «سند جديد»).
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesDocTabs on _FuelMovesBase, _FuelMovesActions {
  // ─────────────────────── تبويبات السندات المعلّقة ───────────────────────
  static String _tabLabel(String tab) => switch (tab) {
        'issue' => 'صرف',
        'supply' => 'توريد',
        'transfer' => 'تحويل',
        _ => 'رصيد افتتاحي',
      };

  String _activeTabLabel() =>
      _savedRef.isNotEmpty ? _savedRef : '${_tabLabel(_tab)} جديد';

  /// لقطة بيانات السند الجاري تعبئته — لتعليقه في تبويبٍ جانبي.
  Map<String, dynamic> _captureDocSnapshot() => {
        'tab': _tab,
        'date': _date,
        'fuelType': _fuelType,
        'warehouse': _warehouse,
        'qty': _qty.text,
        'notes': _notes.text,
        'source': _source,
        'allocationId': _allocationId,
        'unitId': _unitId,
        'orderAuthority': _orderAuthority.text,
        'driver': _driver.text,
        'vehicle': _vehicle.text,
        'chassis': _chassis.text,
        'justification': _justification.text,
        'purpose': _purpose.text,
        'beneficiary': _beneficiary.text,
        'supplier': _supplier.text,
        'transport': _transport.text,
        'toWarehouse': _toWarehouse,
        'savedRef': _savedRef,
      };

  /// يكتب لقطةً محفوظةً من تبويبٍ معلّق رجوعًا إلى حقول النموذج — بلا
  /// المرور بـ[_clearForm] حتى لا تُمحى اللقطة المُستعادة نفسها.
  void _applySnapshot(Map<String, dynamic> data) {
    setState(() {
      _tab = '${data['tab'] ?? _tab}';
      _date = '${data['date'] ?? _date}';
      _fuelType = '${data['fuelType'] ?? _fuelType}';
      _warehouse = '${data['warehouse'] ?? _warehouse}';
      imdSetText(_qty, '${data['qty'] ?? ''}');
      imdSetText(_notes, '${data['notes'] ?? ''}');
      _source = '${data['source'] ?? FuelSource.allocation}';
      _allocationId = '${data['allocationId'] ?? ''}';
      _unitId = '${data['unitId'] ?? ''}';
      imdSetText(_orderAuthority, '${data['orderAuthority'] ?? ''}');
      imdSetText(_driver, '${data['driver'] ?? ''}');
      imdSetText(_vehicle, '${data['vehicle'] ?? ''}');
      imdSetText(_chassis, '${data['chassis'] ?? ''}');
      imdSetText(_justification, '${data['justification'] ?? ''}');
      imdSetText(_purpose, '${data['purpose'] ?? ''}');
      imdSetText(_beneficiary, '${data['beneficiary'] ?? ''}');
      imdSetText(_supplier, '${data['supplier'] ?? ''}');
      imdSetText(_transport, '${data['transport'] ?? ''}');
      _toWarehouse = '${data['toWarehouse'] ?? ''}';
      _savedRef = '${data['savedRef'] ?? ''}';
    });
  }

  /// زر «سند جديد»: يعلّق السند الحالي في تبويبٍ جانبي ويفتح سندًا فارغًا
  /// بنفس التبويبة الحالية (صرف/توريد/تحويل/رصيد).
  void _openNewTab() {
    final snap = _captureDocSnapshot();
    setState(() {
      _suspended.add(ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: snap));
      _activeTabId = _tabSeq++;
    });
    _clearForm();
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
}
