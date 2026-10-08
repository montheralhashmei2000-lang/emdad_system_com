part of '../legacy_import.dart';

/// الكتالوج: الفئات والأصناف والمستودعات والموردون والوحدات والجهات.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyCatalog on _LegacyBase {
  Future<void> _importCategories(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final c in rows) {
      if (!_accept('categories', _id(c))) continue;
      await db
          .into(db.categories)
          .insertOnConflictUpdate(CategoriesCompanion.insert(
            id: _id(c),
            name: _s(c, 'name'),
            description: Value(_s(c, 'description')),
          ));
    }
    _count(res, 'categories', rows.length);
  }

  Future<void> _importItems(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final it in rows) {
      if (!_accept('items', _id(it))) continue;
      await db.into(db.items).insertOnConflictUpdate(ItemsCompanion.insert(
            id: _id(it),
            name: _s(it, 'name'),
            code: Value(_s(it, 'code')),
            categoryId: Value(_s(it, 'categoryId')),
            categoryName: Value(_s(it, 'categoryName')),
            baseUnit: Value(_s(it, 'baseUnit')),
            units: Value(_json(it['units'])),
            qty: Value(_d(it, 'qty')),
            // `min` في الملف المصدَّر، و`minQty` في تصدير هذا التطبيق.
            minQty: Value(_d(it, 'minQty', _d(it, 'min'))),
            barcode: Value(_s(it, 'barcode')),
            isRefillable: Value(_b(it, 'isRefillable')),
            reportUnit: Value(_s(it, 'reportUnit')),
            createdAt: Value(_created(it)),
          ));
    }
    _count(res, 'items', rows.length);
  }

  Future<void> _importWarehouses(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final w in rows) {
      if (!_accept('warehouses', _id(w))) continue;
      await db
          .into(db.warehouses)
          .insertOnConflictUpdate(WarehousesCompanion.insert(
            id: _id(w),
            name: _s(w, 'name'),
            code: Value(_s(w, 'code')),
            manager: Value(_s(w, 'manager')),
            location: Value(_s(w, 'location')),
            feedsAllCamps: Value(_b(w, 'feedsAllCamps', true)),
            isMain: Value(_b(w, 'isMain')),
            fuelCapacityLiters: Value(_d(w, 'fuelCapacityLiters')),
            campIds: Value(_json(w['campIds'])),
            notes: Value(_s(w, 'notes')),
          ));
    }
    _count(res, 'warehouses', rows.length);
  }

  Future<void> _importSuppliers(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final s in rows) {
      if (!_accept('suppliers', _id(s))) continue;
      await db
          .into(db.suppliers)
          .insertOnConflictUpdate(SuppliersCompanion.insert(
            id: _id(s),
            name: _s(s, 'name'),
            phone: Value(_s(s, 'phone')),
            notes: Value(_s(s, 'notes')),
            contact: Value(_s(s, 'contact')),
            city: Value(_s(s, 'city')),
          ));
    }
    _count(res, 'suppliers', rows.length);
  }

  Future<void> _importUnits(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final u in rows) {
      if (!_accept('beneficiary_units', _id(u))) continue;
      await db
          .into(db.beneficiaryUnits)
          .insertOnConflictUpdate(BeneficiaryUnitsCompanion.insert(
            id: _id(u),
            name: _s(u, 'name'),
            code: Value(_s(u, 'code')),
            type: Value(_s(u, 'type', 'unit')),
            parentId: Value(_s(u, 'parentId')),
            parentName: Value(_s(u, 'parentName')),
            isCamp: Value(_b(u, 'isCamp') || _s(u, 'type') == 'camp'),
            facilityId: Value(_s(u, 'facilityId')),
            // القائمة الجديدة، ومع البيانات القديمة يُشتق منها الارتباط المفرد.
            facilityIds: Value(_json(
                u['facilityIds'],
                _s(u, 'facilityId').isEmpty
                    ? '[]'
                    : '["${_s(u, 'facilityId')}"]')),
            category: Value(_s(u, 'category')),
          ));
    }
    _count(res, 'units', rows.length);
  }

  Future<void> _importFacilities(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final f in rows) {
      if (!_accept('facilities', _id(f))) continue;
      await db
          .into(db.facilities)
          .insertOnConflictUpdate(FacilitiesCompanion.insert(
            id: _id(f),
            name: _s(f, 'name'),
            fType: Value(_s(f, 'fType', 'KITCHEN')),
            capacity: Value(_i(f, 'capacity')),
            warehouse: Value(_s(f, 'warehouse')),
            notes: Value(_s(f, 'notes')),
          ));
    }
    _count(res, 'facilities', rows.length);
  }

}
