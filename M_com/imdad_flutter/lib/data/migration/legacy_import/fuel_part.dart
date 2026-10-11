part of '../legacy_import.dart';

/// جهات الإمداد وجداول المحروقات كلها.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyFuel on _LegacyBase, _LegacyNaturalKeys {
  Future<void> _importSupplyAuthorities(
      Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('supply_authorities', _id(a))) continue;
      await db
          .into(db.supplyAuthorities)
          .insertOnConflictUpdate(SupplyAuthoritiesCompanion.insert(
            id: _id(a),
            name: _s(a, 'name'),
            title: Value(_s(a, 'title')),
            notes: Value(_s(a, 'notes')),
            active: Value(_b(a, 'active', true)),
            createdAt: Value(_created(a)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'جهات الإمداد', rows.length);
  }

  Future<void> _importFuel(
      Map<String, dynamic> data, LegacyImportResult res) async {
    for (final w in _rows(data['fuelWarehouses'])) {
      if (!_accept('fuel_warehouses', _id(w))) continue;
      if (!await _claimNaturalKey('fuel_warehouses', _id(w), [_s(w, 'name')], res)) continue;
      await _guardedRow('fuel_warehouses', _id(w), res, () async {
        await db
            .into(db.fuelWarehouses)
            .insertOnConflictUpdate(FuelWarehousesCompanion.insert(
              id: _id(w),
              code: Value(_s(w, 'code')),
              name: _s(w, 'name'),
              manager: Value(_s(w, 'manager')),
              location: Value(_s(w, 'location')),
              capacityLiters: Value(_d(w, 'capacityLiters')),
              active: Value(_b(w, 'active', true)),
              notes: Value(_s(w, 'notes')),
              createdAt: Value(_created(w)),
            ));
      });
    }
    for (final u in _rows(data['fuelUnits'])) {
      if (!_accept('fuel_units', _id(u))) continue;
      if (!await _claimNaturalKey('fuel_units', _id(u), [_s(u, 'name')], res)) continue;
      await _guardedRow('fuel_units', _id(u), res, () async {
        await db
            .into(db.fuelUnits)
            .insertOnConflictUpdate(FuelUnitsCompanion.insert(
              id: _id(u),
              code: Value(_s(u, 'code')),
              name: _s(u, 'name'),
              commander: Value(_s(u, 'commander')),
              phone: Value(_s(u, 'phone')),
              active: Value(_b(u, 'active', true)),
              notes: Value(_s(u, 'notes')),
              createdAt: Value(_created(u)),
            ));
      });
    }
    for (final x in _rows(data['fuelSettings'])) {
      if (!_accept('fuel_settings_rows', _id(x))) continue;
      await db
          .into(db.fuelSettingsRows)
          .insertOnConflictUpdate(FuelSettingsRowsCompanion.insert(
            id: _id(x),
            lowStockPercent: Value(_d(x, 'lowStockPercent', 20)),
            defaultDailyLiters: Value(_d(x, 'defaultDailyLiters', 200)),
            defaultWeeklyLiters: Value(_d(x, 'defaultWeeklyLiters', 1000)),
            defaultMonthlyLiters: Value(_d(x, 'defaultMonthlyLiters', 4000)),
            parentOrg: Value(_s(x, 'parentOrg')),
            agencyTitle: Value(_s(x, 'agencyTitle')),
            commandTitle: Value(_s(x, 'commandTitle')),
            branchTitle: Value(_s(x, 'branchTitle')),
            orgName: Value(_s(x, 'orgName')),
            sealLines: Value(_s(x, 'sealLines')),
            roleOfficer: Value(_s(x, 'roleOfficer')),
            roleSupply: Value(_s(x, 'roleSupply')),
            roleChief: Value(_s(x, 'roleChief')),
            signOfficer: Value(_s(x, 'signOfficer')),
            signSupply: Value(_s(x, 'signSupply')),
            signChief: Value(_s(x, 'signChief')),
            requireChassis: Value(_b(x, 'requireChassis')),
            allowExceptional: Value(_b(x, 'allowExceptional', true)),
            // قرينٌ أقدم بلا الحقل ⇒ يبقى المحلي (لا يُفرض الافتراضي فوقه).
            carryCapPeriods: x.containsKey('carryCapPeriods') ? Value(_i(x, 'carryCapPeriods', 3)) : const Value.absent(),
            notes: Value(_s(x, 'notes')),
          ));
    }
    for (final a in _rows(data['fuelAllocations'])) {
      if (!_accept('fuel_allocations', _id(a))) continue;
      await db
          .into(db.fuelAllocations)
          .insertOnConflictUpdate(FuelAllocationsCompanion.insert(
            id: _id(a),
            refNo: Value(_s(a, 'refNo')),
            unitId: Value(_ref('fuel_units', _s(a, 'unitId'))),
            unitName: Value(_s(a, 'unitName')),
            fuelType: Value(_s(a, 'fuelType', 'diesel')),
            periodType: Value(_s(a, 'periodType', 'monthly')),
            quantityPerPeriod: Value(_d(a, 'quantityPerPeriod')),
            totalQuantity: Value(_d(a, 'totalQuantity')),
            weeklyLiters: Value(_d(a, 'weeklyLiters')),
            monthlyLiters: Value(_d(a, 'monthlyLiters')),
            issueLocation: Value(_s(a, 'issueLocation')),
            startDate: Value(_s(a, 'startDate')),
            endDate: Value(_s(a, 'endDate')),
            active: Value(_b(a, 'active', true)),
            disbursable: Value(_b(a, 'disbursable', true)),
            writtenOffLiters:
                a.containsKey('writtenOffLiters') ? Value(_d(a, 'writtenOffLiters')) : const Value.absent(),
            notes: Value(_s(a, 'notes')),
            createdBy: Value(_s(a, 'createdBy')),
            createdAt: Value(_created(a)),
          ));
    }
    for (final i in _rows(data['fuelIssues'])) {
      if (!_accept('fuel_issues', _id(i))) continue;
      await db
          .into(db.fuelIssues)
          .insertOnConflictUpdate(FuelIssuesCompanion.insert(
            id: _id(i),
            refNo: Value(_s(i, 'refNo')),
            date: Value(_s(i, 'date')),
            fuelType: Value(_s(i, 'fuelType', 'diesel')),
            warehouse: Value(_s(i, 'warehouse')),
            source: Value(_s(i, 'source', 'allocation')),
            quantityLiters: Value(_d(i, 'quantityLiters')),
            driverName: Value(_s(i, 'driverName')),
            vehicleType: Value(_s(i, 'vehicleType')),
            chassisNo: Value(_s(i, 'chassisNo')),
            allocationId: Value(_s(i, 'allocationId')),
            beneficiaryUnitId: Value(_ref('fuel_units', _s(i, 'beneficiaryUnitId'))),
            beneficiaryName: Value(_s(i, 'beneficiaryName')),
            entitledLiters: Value(_d(i, 'entitledLiters')),
            periodType: Value(_s(i, 'periodType')),
            customFrom: Value(_s(i, 'customFrom')),
            customTo: Value(_s(i, 'customTo')),
            justification: Value(_s(i, 'justification')),
            orderAuthority: Value(_s(i, 'orderAuthority')),
            purpose: Value(_s(i, 'purpose')),
            notes: Value(_s(i, 'notes')),
            createdBy: Value(_s(i, 'createdBy')),
            createdAt: Value(_created(i)),
          ));
    }
    for (final x in _rows(data['fuelSupplies'])) {
      if (!_accept('fuel_supplies', _id(x))) continue;
      await db
          .into(db.fuelSupplies)
          .insertOnConflictUpdate(FuelSuppliesCompanion.insert(
            id: _id(x),
            refNo: Value(_s(x, 'refNo')),
            date: Value(_s(x, 'date')),
            fuelType: Value(_s(x, 'fuelType', 'diesel')),
            quantityLiters: Value(_d(x, 'quantityLiters')),
            supplierName: Value(_s(x, 'supplierName')),
            warehouse: Value(_s(x, 'warehouse')),
            transportVehicleType: Value(_s(x, 'transportVehicleType')),
            driverName: Value(_s(x, 'driverName')),
            notes: Value(_s(x, 'notes')),
            createdBy: Value(_s(x, 'createdBy')),
            createdAt: Value(_created(x)),
          ));
    }
    for (final x in _rows(data['fuelOpenings'])) {
      if (!_accept('fuel_openings', _id(x))) continue;
      await db
          .into(db.fuelOpenings)
          .insertOnConflictUpdate(FuelOpeningsCompanion.insert(
            id: _id(x),
            warehouse: Value(_s(x, 'warehouse')),
            fuelType: Value(_s(x, 'fuelType', 'diesel')),
            liters: Value(_d(x, 'liters')),
            asOfDate: Value(_s(x, 'asOfDate')),
            note: Value(_s(x, 'note')),
            createdAt: Value(_created(x)),
          ));
    }
    for (final x in _rows(data['fuelTransfers'])) {
      if (!_accept('fuel_transfers', _id(x))) continue;
      await db
          .into(db.fuelTransfers)
          .insertOnConflictUpdate(FuelTransfersCompanion.insert(
            id: _id(x),
            refNo: Value(_s(x, 'refNo')),
            date: Value(_s(x, 'date')),
            fuelType: Value(_s(x, 'fuelType', 'diesel')),
            quantityLiters: Value(_d(x, 'quantityLiters')),
            fromWarehouse: Value(_s(x, 'fromWarehouse')),
            toWarehouse: Value(_s(x, 'toWarehouse')),
            driverName: Value(_s(x, 'driverName')),
            transportVehicleType: Value(_s(x, 'transportVehicleType')),
            notes: Value(_s(x, 'notes')),
            createdBy: Value(_s(x, 'createdBy')),
            createdAt: Value(_created(x)),
          ));
    }
    for (final x in _rows(data['fuelStocktakes'])) {
      if (!_accept('fuel_stocktakes', _id(x))) continue;
      await db
          .into(db.fuelStocktakes)
          .insertOnConflictUpdate(FuelStocktakesCompanion.insert(
            id: _id(x),
            refNo: Value(_s(x, 'refNo')),
            date: Value(_s(x, 'date')),
            warehouse: Value(_s(x, 'warehouse')),
            kind: Value(_s(x, 'kind', 'full')),
            fuelFilter: Value(_s(x, 'fuelFilter', 'all')),
            committee: Value(_s(x, 'committee')),
            status: Value(_s(x, 'status', 'open')),
            notes: Value(_s(x, 'notes')),
            createdBy: Value(_s(x, 'createdBy')),
            createdAt: Value(_created(x)),
          ));
    }
    for (final x in _rows(data['fuelStocktakeLines'])) {
      if (!_accept('fuel_stocktake_lines', _id(x))) continue;
      await db
          .into(db.fuelStocktakeLines)
          .insertOnConflictUpdate(FuelStocktakeLinesCompanion.insert(
            id: _id(x),
            stocktakeId: _s(x, 'stocktakeId'),
            fuelType: Value(_s(x, 'fuelType', 'diesel')),
            bookLiters: Value(_d(x, 'bookLiters')),
            counted: Value(_b(x, 'counted')),
            countedLiters: Value(_d(x, 'countedLiters')),
          ));
    }
  }

}
