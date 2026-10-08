part of '../legacy_import.dart';

/// الجرد والمراجعات الحساسة وسجل التدقيق والأصول وأوامر الإعاشة.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyDocs on _LegacyBase {
  Future<void> _importStocktakes(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final s in rows) {
      if (!_accept('stocktakes', _id(s))) continue;
      await db
          .into(db.stocktakes)
          .insertOnConflictUpdate(StocktakesCompanion.insert(
            id: _id(s),
            orderNo: Value(_s(s, 'orderNo')),
            type: Value(_s(s, 'type', 'FULL')),
            date: Value(_s(s, 'date')),
            warehouse: Value(_s(s, 'warehouse')),
            categoryId: Value(_s(s, 'categoryId')),
            categoryName: Value(_s(s, 'categoryName')),
            committee: Value(_s(s, 'committee')),
            freeze: Value(_b(s, 'freeze', true)),
            status: Value(_s(s, 'status', 'COUNTING')),
            itemsCount: Value(_i(s, 'itemsCount')),
            notes: Value(_s(s, 'notes')),
            closedDate: Value(_s(s, 'closedDate')),
            createdBy: Value(_s(s, 'createdBy')),
            createdAt: Value(_created(s)),
            cancelReason: Value(_s(s, 'cancelReason')),
            cancelledBy: Value(_s(s, 'cancelledBy')),
            closedBy: Value(_s(s, 'closedBy')),
            countedCount: Value(_i(s, 'countedCount')),
            varianceCount: Value(_i(s, 'varianceCount')),
            adjustedCount: Value(_i(s, 'adjustedCount')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'أوامر الجرد', rows.length);
  }

  Future<void> _importStocktakeLines(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final l in rows) {
      if (!_accept('stocktake_lines', _id(l))) continue;
      await db
          .into(db.stocktakeLines)
          .insertOnConflictUpdate(StocktakeLinesCompanion.insert(
            id: _id(l),
            sessionId: _s(l, 'sessionId'),
            itemId: _s(l, 'itemId'),
            itemCode: Value(_s(l, 'itemCode')),
            itemName: Value(_s(l, 'itemName')),
            unitName: Value(_s(l, 'unitName')),
            systemQty: Value(_d(l, 'systemQty')),
            // الكمية المعدودة والفرق يبقيان فارغين ما لم يُعَدّ السطر فعلًا:
            // الصفر هنا يعني «عُدّ فوُجد صفرًا»، وهو غير «لم يُعَدّ بعد».
            countedQty:
                Value(l['countedQty'] == null ? null : _d(l, 'countedQty')),
            counts: Value(_json(l['counts'], '{}')),
            variance: Value(l['variance'] == null ? null : _d(l, 'variance')),
            reason: Value(_s(l, 'reason')),
            decision: Value(_s(l, 'decision', 'ADJUST')),
            status: Value(_s(l, 'status', 'PENDING')),
            discovered: Value(_b(l, 'discovered')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سطور الجرد', rows.length);
  }

  Future<void> _importSensitiveReviews(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('sensitive_reviews', _id(r))) continue;
      await db
          .into(db.sensitiveReviews)
          .insertOnConflictUpdate(SensitiveReviewsCompanion.insert(
            id: _id(r),
            logId: _s(r, 'logId'),
            reviewedBy: Value(_s(r, 'reviewedBy')),
            note: Value(_s(r, 'note')),
            reviewedAt:
                Value(DateTime.tryParse(_s(r, 'reviewedAt')) ?? DateTime.now()),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'مراجعات حساسة', rows.length);
  }

  /// سجل التدقيق: يتجمّع من كل الأجهزة عند الإدارة، فيُرى نشاط الوحدة كله في
  /// مكان واحد. السطور لا تُعدَّل بعد كتابتها، فالدمج بالمعرّف لا يتعارض.
  Future<void> _importAuditLogs(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('audit_logs', _id(a))) continue;
      await db
          .into(db.auditLogs)
          .insertOnConflictUpdate(AuditLogsCompanion.insert(
            id: _id(a),
            action: _s(a, 'action'),
            entityType: Value(_s(a, 'entityType')),
            summary: Value(_s(a, 'summary')),
            details: Value(_json(a['details'], '{}')),
            risk: Value(_s(a, 'risk', 'normal')),
            actorEmail: Value(_s(a, 'actorEmail')),
            logDate: Value(_s(a, 'logDate')),
            actorName: Value(_s(a, 'actorName')),
            actorRole: Value(_s(a, 'actorRole', 'user')),
            refNo: Value(_s(a, 'refNo')),
            warehouse: Value(_s(a, 'warehouse')),
            target: Value(_s(a, 'target')),
            status: Value(_s(a, 'status')),
            itemCount: Value(_i(a, 'itemCount')),
            qty: Value(_d(a, 'qty')),
            createdAt: Value(_created(a)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سجل التدقيق', rows.length);
  }

  Future<void> _importAssets(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('assets', _id(a))) continue;
      await db.into(db.assets).insertOnConflictUpdate(AssetsCompanion.insert(
            id: _id(a),
            name: _s(a, 'name'),
            quantity: Value(_d(a, 'quantity', 1)),
            assetType: Value(_s(a, 'assetType', 'equipment')),
            serialNumber: Value(_s(a, 'serialNumber')),
            facilityId: Value(_s(a, 'facilityId')),
            facilityName: Value(_s(a, 'facilityName')),
            beneficiaryUnitId: Value(_s(a, 'beneficiaryUnitId')),
            beneficiaryUnitName: Value(_s(a, 'beneficiaryUnitName')),
            warehouse: Value(_s(a, 'warehouse')),
            status: Value(_s(a, 'status', 'NEW')),
            acquisitionDate: Value(_s(a, 'acquisitionDate')),
            value: Value(_d(a, 'value')),
            lifespanMonths: Value(_i(a, 'lifespanMonths')),
            supplierId: Value(_s(a, 'supplierId')),
            supplierName: Value(_s(a, 'supplierName')),
            invoiceNumber: Value(_s(a, 'invoiceNumber')),
            notes: Value(_s(a, 'notes')),
            createdBy: Value(_s(a, 'createdBy')),
            createdAt: Value(_created(a)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'الأصول الثابتة', rows.length);
  }

  Future<void> _importAssetAssignments(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final g in rows) {
      if (!_accept('asset_assignments', _id(g))) continue;
      await db
          .into(db.assetAssignments)
          .insertOnConflictUpdate(AssetAssignmentsCompanion.insert(
            id: _id(g),
            assetId: _s(g, 'assetId'),
            assetName: Value(_s(g, 'assetName')),
            beneficiaryUnitId: Value(_s(g, 'beneficiaryUnitId')),
            beneficiaryUnitName: Value(_s(g, 'beneficiaryUnitName')),
            assignedDate: Value(_s(g, 'assignedDate')),
            returnedDate: Value(_s(g, 'returnedDate')),
            assignedTo: Value(_s(g, 'assignedTo')),
            notes: Value(_s(g, 'notes')),
            createdBy: Value(_s(g, 'createdBy')),
            createdAt: Value(_created(g)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'عهد الأصول', rows.length);
  }

  Future<void> _importRationOrders(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final o in rows) {
      if (!_accept('ration_orders', _id(o))) continue;
      await db
          .into(db.rationOrders)
          .insertOnConflictUpdate(RationOrdersCompanion.insert(
            id: _id(o),
            refNo: Value(_s(o, 'refNo')),
            requestingWarehouse: Value(_s(o, 'requestingWarehouse')),
            supplyingWarehouse: Value(_s(o, 'supplyingWarehouse')),
            date: Value(_s(o, 'date')),
            requiredDate: Value(_s(o, 'requiredDate')),
            status: Value(_s(o, 'status', 'DRAFT')),
            priority: Value(_s(o, 'priority', 'NORMAL')),
            notes: Value(_s(o, 'notes')),
            rejectReason: Value(_s(o, 'rejectReason')),
            createdBy: Value(_s(o, 'createdBy')),
            approvedBy: Value(_s(o, 'approvedBy')),
            receivedBy: Value(_s(o, 'receivedBy')),
            receiptRef: Value(_s(o, 'receiptRef')),
            orderKind: Value(_s(o, 'orderKind', 'BRANCH')),
            authorityId: Value(_s(o, 'authorityId')),
            authorityName: Value(_s(o, 'authorityName')),
            fulfillRef: Value(_s(o, 'fulfillRef')),
            fulfillKind: Value(_s(o, 'fulfillKind')),
            fulfillDate: Value(_s(o, 'fulfillDate')),
            createdAt: Value(_created(o)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'طلبيات الإعاشة', rows.length);
  }

}
