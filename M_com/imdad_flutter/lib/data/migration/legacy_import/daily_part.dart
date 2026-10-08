part of '../legacy_import.dart';

/// القوة ويوميات المطبخ والاستحقاقات والإعدادات.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyDaily on _LegacyBase {
  Future<void> _importStrengths(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('strengths', _id(r))) continue;
      await db
          .into(db.strengths)
          .insertOnConflictUpdate(StrengthsCompanion.insert(
            id: _id(r),
            unitId: _s(r, 'unitId'),
            unitName: Value(_s(r, 'unitName')),
            campId: Value(_s(r, 'campId')),
            campName: Value(_s(r, 'campName')),
            strengthDate: _s(r, 'strengthDate', _s(r, 'date')),
            soldierCount: Value(_d(r, 'soldierCount')),
            officerCount: Value(_d(r, 'officerCount')),
            total: Value(_d(r, 'total')),
            pct: Value(_d(r, 'pct')),
            mode: Value(_s(r, 'mode', 'detail')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'strengths', rows.length);
  }

  Future<void> _importKitchenLogs(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('kitchen_logs', _id(r))) continue;
      await db
          .into(db.kitchenLogs)
          .insertOnConflictUpdate(KitchenLogsCompanion.insert(
            id: _id(r),
            facilityId: _s(r, 'facilityId'),
            facilityName: Value(_s(r, 'facilityName')),
            date: _s(r, 'date'),
            mealType: Value(_s(r, 'mealType', 'LUNCH')),
            strength: Value(_d(r, 'strength')),
            itemId: Value(_s(r, 'itemId')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            expectedBase: Value(_d(r, 'expectedBase')),
            varianceBase: Value(_d(r, 'varianceBase')),
            notes: Value(_s(r, 'notes')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'kitchenLogs', rows.length);
  }

  Future<void> _importEntitlements(Object? raw, LegacyImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      final itemId = _s(r, 'itemId', _id(r));
      if (!_accept('entitlements', itemId)) continue;
      final unitName = _s(r, 'measureUnitName', _s(r, 'unitName'));
      // المعامل من وحدات الصنف بالاسم (النظام السابق لا يخزّنه في المقرر)،
      // وإلا فالمعامل المصدَّر مع المقرر (تصدير هذا التطبيق) حين لا يكون الصنف هنا بعد.
      var factor = _d(r, 'measureFactor', 1);
      if (factor <= 0) factor = 1;
      final item = await (db.select(db.items)
            ..where((t) => t.id.equals(itemId)))
          .getSingleOrNull();
      if (item != null) {
        try {
          final units = jsonDecode(item.units);
          if (units is List) {
            for (final u in units.whereType<Map>()) {
              if (u['name']?.toString() == unitName &&
                  u['factor'] is num &&
                  (u['factor'] as num) > 0) {
                factor = (u['factor'] as num).toDouble();
              }
            }
          }
        } catch (err, stack) {
          ErrorLogger.log('import.itemUnits', err, stack);
        }
      }
      // `entMeasureQty`: السجلات القديمة (بدون qtyUnit='measure') محفوظة بالوحدة الأساسية فتُحوَّل.
      final q = _d(r, 'qtyPerPerson');
      final measureQty = _s(r, 'qtyUnit') == 'measure' ? q : q / factor;
      await db
          .into(db.entitlements)
          .insertOnConflictUpdate(EntitlementsCompanion.insert(
            itemId: itemId,
            itemName: Value(_s(r, 'itemName')),
            qtyPerPerson: Value((measureQty * 1000).round() / 1000),
            measureUnitName: Value(unitName),
            measureFactor: Value(factor),
            notes: Value(_s(r, 'notes')),
            updatedAt: Value(DateTime.now()),
          ));
    }
    _count(res, 'entitlements', rows.length);
  }

  Future<void> _importSettings(Object? raw, LegacyImportResult res) async {
    if (raw is! Map) return;
    final map = raw.cast<String, dynamic>();
    for (final entry in map.entries) {
      // خاصٌّ بالجهاز: لا يُكتب فوقه من نسخةٍ واردة.
      if (SettingsRepo.localOnlyKeys.contains(entry.key)) continue;
      if (!_accept('app_settings', entry.key)) continue;
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(AppSettingsCompanion.insert(
            key: entry.key,
            value: Value(_json(entry.value, '{}')),
            updatedAt: Value(DateTime.now()),
          ));
    }
    _count(res, 'settings', map.length);
  }
}
