part of '../fuel_moves_screen.dart';

/// أفعال الشاشة: اختيار الاستحقاق وتفريغ النموذج والحفظ والطباعة والعكس والحذف.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesActions on _FuelMovesBase {
  // ───────────────────────── أفعال

  void _onChassis(String v) {
    final prev = _lastForChassis;
    if (prev != null) {
      if (_driver.text.trim().isEmpty) imdSetText(_driver, prev.driverName);
      if (_vehicle.text.trim().isEmpty) imdSetText(_vehicle, prev.vehicleType);
    }
    setState(() {});
  }

  void _pickAllocation(String id) {
    final a = _allocations.where((x) => x.allocation.id == id).firstOrNull;
    setState(() => _allocationId = id);
    if (a == null) return;
    // الكمية المقترحة حصّةُ الفترة، ولا تتجاوز ما بقي من الاستحقاق.
    final suggested = a.allocation.quantityPerPeriod;
    final value = suggested > a.remaining ? a.remaining : suggested;
    imdSetText(_qty, value <= 0 ? '' : _num(value));
    imdSetText(_orderAuthority, 'استحقاق');
    if (_beneficiary.text.trim().isEmpty) {
      imdSetText(_beneficiary, a.allocation.unitName);
    }
    setState(() {});
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _clearForm() {
    for (final c in _all) {
      if (c == _q) continue;
      imdSetText(c, '');
    }
    imdSetText(
        _orderAuthority, _source == FuelSource.allocation ? 'استحقاق' : '');
    setState(() {
      _allocationId = '';
      _unitId = '';
      _savedRef = '';
    });
  }

  Future<void> _submit() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelMoves', PermAction.create)) return;
    setState(() => _busy = true);
    final actor = context.read<AuthService>().currentUser?.email ?? '';
    late FuelResult res;
    switch (_tab) {
      case 'issue':
        final unit = _allocation?.allocation.unitId ?? _unitId;
        res = await _repo.saveIssue(
          date: _date,
          fuelType: _fuelType,
          warehouse: _warehouse,
          quantityLiters: _qtyValue,
          source: _source,
          allocationId: _source == FuelSource.allocation ? _allocationId : '',
          beneficiaryUnitId: unit,
          beneficiaryName: _beneficiary.text.trim().isNotEmpty
              ? _beneficiary.text.trim()
              : (_units.where((u) => u.id == unit).firstOrNull?.name ??
                  _driver.text.trim()),
          driverName: _driver.text.trim(),
          vehicleType: _vehicle.text.trim(),
          chassisNo: _chassis.text.trim(),
          justification: _justification.text.trim(),
          orderAuthority: _orderAuthority.text.trim().isNotEmpty
              ? _orderAuthority.text.trim()
              : (_source == FuelSource.allocation ? 'استحقاق' : 'أمر استثنائي'),
          purpose: _purpose.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      case 'supply':
        res = await _repo.saveSupply(
          date: _date,
          fuelType: _fuelType,
          warehouse: _warehouse,
          quantityLiters: _qtyValue,
          supplierName: _supplier.text.trim(),
          transportVehicleType: _transport.text.trim(),
          driverName: _driver.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      case 'transfer':
        res = await _repo.saveTransfer(
          date: _date,
          fuelType: _fuelType,
          fromWarehouse: _warehouse,
          toWarehouse: _toWarehouse,
          quantityLiters: _qtyValue,
          driverName: _driver.text.trim(),
          transportVehicleType: _transport.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      default:
        res = await _repo.saveOpening(
          warehouse: _warehouse,
          fuelType: _fuelType,
          liters: _qtyValue,
          asOfDate: _date,
          note: _notes.text.trim(),
          actor: actor,
        );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(
      context,
      res.ok
          ? '✔ حُفظ${res.refNo.isEmpty ? '' : ' السند ${res.refNo}'}'
          : res.error,
      error: !res.ok,
    );
    if (res.ok) {
      _clearForm();
      await _load();
      if (mounted) setState(() => _savedRef = res.refNo);
    }
  }

  Future<void> _printIssue(FuelIssue issue) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
    final row = issue.allocationId.isEmpty
        ? null
        : _allocations
            .where((a) => a.allocation.id == issue.allocationId)
            .firstOrNull;
    await FuelPrint.issueVoucher(_db, issue, allocation: row);
  }

  Future<void> _printSaved() async {
    if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
    switch (_tab) {
      case 'issue':
        final doc = _issues.where((i) => i.refNo == _savedRef).firstOrNull;
        if (doc != null) await _printIssue(doc);
      case 'supply':
        final doc = _supplies.where((s) => s.refNo == _savedRef).firstOrNull;
        if (doc != null) await FuelPrint.supplyVoucher(_db, doc);
      case 'transfer':
        final doc = _transfers.where((t) => t.refNo == _savedRef).firstOrNull;
        if (doc != null) await FuelPrint.transferVoucher(_db, doc);
    }
  }

  Future<void> _reverse(FuelTransfer t) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', PermAction.create)) {
      return;
    }
    if (!await imdConfirm(
      context,
      'يُنشأ سند تحويل عكسي بنفس الكمية والصنف من «${t.toWarehouse}» إلى '
      '«${t.fromWarehouse}». متابعة؟',
      ok: 'تأكيد العكس',
    )) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.reverseTransfer(
      t.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ سند عكس ${res.refNo}' : res.error,
        error: !res.ok);
    if (res.ok) await _load();
  }

  Future<void> _deleteOpening(FuelOpening o) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', PermAction.delete)) {
      return;
    }
    if (!await imdConfirm(context, 'حذف الرصيد الافتتاحي لـ«${o.warehouse}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    await _repo.deleteOpening(o.id);
    if (!mounted) return;
    showImdToast(context, '✔ حُذف الرصيد الافتتاحي');
    await _load();
  }
}
