part of '../legacy_import.dart';

/// حدود المستودعات وسطور الأوامر وخطط الوجبات ويوميات المعسكرات
/// والتسويات والارتباطات.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyCamps on _LegacyBase {
  Future<void> _importWarehouseLimits(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final l in rows) {
      if (!_accept('warehouse_stock_limits', _id(l))) continue;
      await db
          .into(db.warehouseStockLimits)
          .insertOnConflictUpdate(WarehouseStockLimitsCompanion.insert(
            id: _id(l),
            warehouseId: _s(l, 'warehouseId'),
            warehouseName: Value(_s(l, 'warehouseName')),
            itemId: _s(l, 'itemId'),
            itemName: Value(_s(l, 'itemName')),
            unitName: Value(_s(l, 'unitName')),
            factor: Value(_d(l, 'factor', 1)),
            minStock: Value(_d(l, 'minStock')),
            maxStock: Value(_d(l, 'maxStock')),
            notes: Value(_s(l, 'notes')),
            updatedAt:
                Value(DateTime.tryParse(_s(l, 'updatedAt')) ?? DateTime.now()),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'حدود مخزون المستودعات', rows.length);
  }

  Future<void> _importRationOrderLines(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final l in rows) {
      if (!_accept('ration_order_lines', _id(l))) continue;
      await db
          .into(db.rationOrderLines)
          .insertOnConflictUpdate(RationOrderLinesCompanion.insert(
            id: _id(l),
            orderId: _s(l, 'orderId'),
            itemId: Value(_s(l, 'itemId')),
            itemCode: Value(_s(l, 'itemCode')),
            itemName: Value(_s(l, 'itemName')),
            unitName: Value(_s(l, 'unitName')),
            factor: Value(_d(l, 'factor', 1)),
            requestedQty: Value(_d(l, 'requestedQty')),
            approvedQty: Value(_d(l, 'approvedQty')),
            receivedQty: Value(_d(l, 'receivedQty')),
            notes: Value(_s(l, 'notes')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سطور طلبيات الإعاشة', rows.length);
  }

  Future<void> _importMealPlans(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final p in rows) {
      if (!_accept('meal_plans', _id(p))) continue;
      await db
          .into(db.mealPlans)
          .insertOnConflictUpdate(MealPlansCompanion.insert(
            id: _id(p),
            name: _s(p, 'name'),
            planType: Value(_s(p, 'planType', 'WEEKLY')),
            startDate: Value(_s(p, 'startDate')),
            endDate: Value(_s(p, 'endDate')),
            status: Value(_s(p, 'status', 'DRAFT')),
            facilityId: Value(_s(p, 'facilityId')),
            facilityName: Value(_s(p, 'facilityName')),
            warehouse: Value(_s(p, 'warehouse')),
            notes: Value(_s(p, 'notes')),
            createdBy: Value(_s(p, 'createdBy')),
            createdAt: Value(_created(p)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'خطط الوجبات', rows.length);
  }

  Future<void> _importMealPlanEntries(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final e in rows) {
      if (!_accept('meal_plan_entries', _id(e))) continue;
      await db
          .into(db.mealPlanEntries)
          .insertOnConflictUpdate(MealPlanEntriesCompanion.insert(
            id: _id(e),
            planId: _s(e, 'planId'),
            entryDate: Value(_s(e, 'entryDate')),
            mealType: Value(_s(e, 'mealType', 'LUNCH')),
            itemId: Value(_s(e, 'itemId')),
            itemCode: Value(_s(e, 'itemCode')),
            itemName: Value(_s(e, 'itemName')),
            unitName: Value(_s(e, 'unitName')),
            factor: Value(_d(e, 'factor', 1)),
            qtyPerPerson: Value(_d(e, 'qtyPerPerson')),
            notes: Value(_s(e, 'notes')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'وجبات الخطط', rows.length);
  }

  Future<void> _importCampLedgers(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final l in rows) {
      if (!_accept('camp_ledgers', _id(l))) continue;
      await db
          .into(db.campLedgers)
          .insertOnConflictUpdate(CampLedgersCompanion.insert(
            id: _id(l),
            campId: _s(l, 'campId'),
            campName: Value(_s(l, 'campName')),
            itemId: _s(l, 'itemId'),
            itemName: Value(_s(l, 'itemName')),
            unitName: Value(_s(l, 'unitName')),
            year: _i(l, 'year'),
            month: _i(l, 'month'),
            openingEntitled: Value(_d(l, 'openingEntitled')),
            openingStock: Value(_d(l, 'openingStock')),
            entitlementTotal: Value(_d(l, 'entitlementTotal')),
            transferredIn: Value(_d(l, 'transferredIn')),
            issuedDirect: Value(_d(l, 'issuedDirect')),
            returnedQty: Value(_d(l, 'returnedQty')),
            consumedKitchen: Value(_d(l, 'consumedKitchen')),
            strengthSum: Value(_d(l, 'strengthSum')),
            strengthDays: Value(_i(l, 'strengthDays')),
            status: Value(_s(l, 'status', 'OPEN')),
            closedBy: Value(_s(l, 'closedBy')),
            closedAt: Value(DateTime.tryParse(_s(l, 'closedAt'))),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سجلات المعسكرات', rows.length);
  }

  Future<void> _importCampStockLimits(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final c in rows) {
      if (!_accept('camp_stock_limits', _id(c))) continue;
      await db
          .into(db.campStockLimits)
          .insertOnConflictUpdate(CampStockLimitsCompanion.insert(
            id: _id(c),
            campId: _s(c, 'campId'),
            campName: Value(_s(c, 'campName')),
            itemId: _s(c, 'itemId'),
            itemName: Value(_s(c, 'itemName')),
            minStock: Value(_d(c, 'minStock')),
            maxStock: Value(_d(c, 'maxStock')),
            alertDaysBefore: Value(_i(c, 'alertDaysBefore', 2)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'حدود مخزون المعسكرات', rows.length);
  }

  Future<void> _importSettlements(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final m in rows) {
      if (!_accept('monthly_settlements', _id(m))) continue;
      await db
          .into(db.monthlySettlements)
          .insertOnConflictUpdate(MonthlySettlementsCompanion.insert(
            id: _id(m),
            year: _i(m, 'year'),
            month: _i(m, 'month'),
            settledBy: Value(_s(m, 'settledBy')),
            notes: Value(_s(m, 'notes')),
            campsCount: Value(_i(m, 'campsCount')),
            itemsCount: Value(_i(m, 'itemsCount')),
            totalCredit: Value(_d(m, 'totalCredit')),
            totalDebit: Value(_d(m, 'totalDebit')),
            settledAt:
                Value(DateTime.tryParse(_s(m, 'settledAt')) ?? DateTime.now()),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'تصفيات الشهور', rows.length);
  }

  /// البرقيات والارتباطات: صفوفها بتسلسل Drift (`toJson`) فتُقرأ بـ`fromJson`
  /// ويُرفض ما أقدم من نسخة الجهاز المحلية كبقية الجداول.
  Future<void> _importLinkage(Map<String, dynamic> data, LegacyImportResult res) async {
    Future<void> run<T extends Table, D extends DataClass>(
        String key, String entity, String label, TableInfo<T, D> table, D Function(Map<String, dynamic>) from) async {
      final rows = _rows(data[key]);
      var n = 0;
      for (final m in rows) {
        if (!_accept(entity, _id(m))) continue;
        await db.into(table).insertOnConflictUpdate(from(m) as Insertable<D>);
        n++;
      }
      if (n > 0) _count(res, label, n);
    }

    await run('cables', 'cables', 'البرقيات', db.cables, Cable.fromJson);
    await run('linkPersons', 'link_persons', 'أفراد القوة البشرية', db.linkPersons, LinkPerson.fromJson);
    await run('linkStatusLogs', 'link_status_logs', 'سجل حالات الأفراد', db.linkStatusLogs, LinkStatusLog.fromJson);
    await run('linkFinCustodies', 'link_fin_custodies', 'العهد', db.linkFinCustodies, LinkFinCustody.fromJson);
    await run('linkClearances', 'link_clearances', 'الإخلاءات', db.linkClearances, LinkClearance.fromJson);
    await run('linkPurchaseContracts', 'link_purchase_contracts', 'عقود الشراء', db.linkPurchaseContracts,
        LinkPurchaseContract.fromJson);
    await run('linkMoneyReceipts', 'link_money_receipts', 'سندات استلام المبالغ', db.linkMoneyReceipts, LinkMoneyReceipt.fromJson);
    await run('linkArmaments', 'link_armaments', 'التسليح', db.linkArmaments, LinkArmament.fromJson);
    await run('linkFinanceLedger', 'link_finance_ledger', 'قيود رصيد المالية', db.linkFinanceLedger, LinkFinanceLedgerData.fromJson);
    await run('linkCustodySheets', 'link_custody_sheets', 'مسيرات العهدة', db.linkCustodySheets, LinkCustodySheet.fromJson);
    await run('linkCustodySheetRows', 'link_custody_sheet_rows', 'أسطر مسيرات العهدة', db.linkCustodySheetRows,
        LinkCustodySheetRow.fromJson);
  }

}
