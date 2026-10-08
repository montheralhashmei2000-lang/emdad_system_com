part of '../legacy_import.dart';

/// الحركات: الاستلام والصرف والتحويل والمرتجع والافتتاحي والتسويات.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyMovements on _LegacyBase {
  Future<void> _importReceipts(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('receipts', _id(r))) continue;
      if (!_quantitiesOk(r, 'receipts', res)) continue;
      await db
          .into(db.receipts)
          .insertOnConflictUpdate(ReceiptsCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            supplier: Value(_s(r, 'supplier')),
            invoiceNo: Value(_s(r, 'invoiceNo')),
            committee: Value(_s(r, 'committee')),
            supervision: Value(_s(r, 'supervision')),
            audit: Value(_s(r, 'audit')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            expiryDate: Value(_s(r, 'expiryDate')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'receipts', rows.length);
  }

  Future<void> _importIssues(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('issues', _id(r))) continue;
      if (!_quantitiesOk(r, 'issues', res)) continue;
      await db.into(db.issues).insertOnConflictUpdate(IssuesCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            targetType: Value(_i(r, 'targetType')),
            recipientDisplay: Value(_s(r, 'recipientDisplay')),
            unitId: Value(_s(r, 'unitId')),
            facilityId: Value(_s(r, 'facilityId')),
            beneficiaryUnitId: Value(_s(r, 'beneficiaryUnitId')),
            beneficiaryUnitName: Value(_s(r, 'beneficiaryUnitName')),
            soldierCount: Value(_d(r, 'soldierCount')),
            durationDays: Value(_i(r, 'durationDays', 1)),
            officerCount: Value(_d(r, 'officerCount')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            approvedBy: Value(_s(r, 'approvedBy')),
            rejectReason: Value(_s(r, 'rejectReason')),
            rejectedBy: Value(_s(r, 'rejectedBy')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'issues', rows.length);
  }

  Future<void> _importTransfers(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('transfers', _id(r))) continue;
      if (!_quantitiesOk(r, 'transfers', res)) continue;
      await db
          .into(db.transfers)
          .insertOnConflictUpdate(TransfersCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'PENDING')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            destWarehouse: Value(_s(r, 'destWarehouse')),
            campId: Value(_s(r, 'campId')),
            campName: Value(_s(r, 'campName')),
            strength: Value(_d(r, 'strength')),
            durationDays: Value(_i(r, 'durationDays', 1)),
            rejectReason: Value(_s(r, 'rejectReason')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'transfers', rows.length);
  }

  Future<void> _importReturns(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('returns', _id(r))) continue;
      if (!_quantitiesOk(r, 'returns', res)) continue;
      await db.into(db.returns).insertOnConflictUpdate(ReturnsCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            party: Value(_s(r, 'party')),
            beneficiaryUnitId: Value(_s(r, 'beneficiaryUnitId')),
            beneficiaryUnitName: Value(_s(r, 'beneficiaryUnitName')),
            type: Value(_s(r, 'type', 'FROM_UNIT')),
            condition: Value(_s(r, 'condition', 'صالحة')),
            origRef: Value(_s(r, 'origRef')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'returns', rows.length);
  }

  Future<void> _importOpening(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('opening_balances', _id(r))) continue;
      if (!_quantitiesOk(r, 'opening_balances', res, hasFactor: false)) continue;
      await db
          .into(db.openingBalances)
          .insertOnConflictUpdate(OpeningBalancesCompanion.insert(
            id: _id(r),
            itemId: _s(r, 'itemId'),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            warehouse: Value(_s(r, 'warehouse')),
            qty: Value(_d(r, 'qty')),
            date: Value(_s(r, 'date')),
            setBy: Value(_s(r, 'setBy')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'openingBalances', rows.length);
    if (rows.any((r) => _s(r, 'warehouse').isEmpty)) {
      res.warnings.add(
          'بعض الأرصدة الافتتاحية بلا مستودع — حدّد لها مستودعًا بعد الترحيل لتدخل في رصيده.');
    }
  }

  /// تسويات الجرد — موجودة في نسخ التطبيق الأصلي فقط، وبدونها تختل الأرصدة
  /// المستعادة لأن فروق الجرد المعتمدة جزء من رصيد المستودع.
  Future<void> _importAdjustments(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('adjustments', _id(a))) continue;
      await db
          .into(db.adjustments)
          .insertOnConflictUpdate(AdjustmentsCompanion.insert(
            id: _id(a),
            refNo: Value(_s(a, 'refNo')),
            date: Value(_s(a, 'date')),
            warehouse: Value(_s(a, 'warehouse')),
            itemId: Value(_s(a, 'itemId')),
            itemCode: Value(_s(a, 'itemCode')),
            itemName: Value(_s(a, 'itemName')),
            unitName: Value(_s(a, 'unitName')),
            factor: Value(_d(a, 'factor', 1)),
            qty: Value(_d(a, 'qty')),
            baseQty: Value(_d(a, 'baseQty')),
            status: Value(_s(a, 'status', 'COMPLETED')),
            notes: Value(_s(a, 'notes')),
            createdBy: Value(_s(a, 'createdBy')),
            createdAt: Value(_created(a)),
            sessionId: Value(_s(a, 'sessionId')),
            reason: Value(_s(a, 'reason')),
            approvedBy: Value(_s(a, 'approvedBy')),
            editCount: Value(_i(a, 'editCount')),
            editLog: Value(_json(a['editLog'])),
            editedBy: Value(_s(a, 'editedBy')),
            cancelReason: Value(_s(a, 'cancelReason')),
            cancelledBy: Value(_s(a, 'cancelledBy')),
            prevStatus: Value(_s(a, 'prevStatus')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'adjustments', rows.length);
  }

}
