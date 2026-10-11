import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import '../../core/error_log.dart';
import '../../core/security/warehouse_scope.dart';
import '../../core/ui/imd_format.dart';
import '../../domain/item_barcode.dart';

/// منعٌ مقصود لتعديلٍ على مستودع. رسالته عربية تُعرض للمستخدم كما هي.
class WarehouseBlocked implements Exception {
  const WarehouseBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

/// وحدة قياس الصنف (تُحفظ JSON داخل عمود units).
class ItemUnit {
  const ItemUnit({required this.name, required this.factor, this.isBase = false});

  final String name;
  final double factor;
  final bool isBase;

  factory ItemUnit.fromMap(Map<String, dynamic> m) => ItemUnit(
        name: (m['name'] ?? '').toString(),
        factor: (m['factor'] is num) ? (m['factor'] as num).toDouble() : 1,
        isBase: m['isBase'] == true,
      );

  Map<String, dynamic> toMap() => {'name': name, 'factor': factor, 'isBase': isBase};
}

/// البيانات الأساسية: الأصناف والتصنيفات والمستودعات والموردون والوحدات المستفيدة والمطابخ.
/// منشآت الوحدة المشترَك فيها: القائمة الجديدة، وإن كانت فارغة فالارتباط
/// المفرد القديم — حتى تعمل البيانات المُرحَّلة وملفات التصدير السابقة.
List<String> facilityIdsOf(BeneficiaryUnit u) {
  try {
    final raw = jsonDecode(u.facilityIds);
    if (raw is List) {
      final out = [for (final v in raw) '$v'].where((v) => v.isNotEmpty).toList();
      if (out.isNotEmpty) return out;
    }
  } catch (err, stack) {
    ErrorLogger.log('catalog.facilityIds', err, stack);
  }
  return u.facilityId.isEmpty ? const [] : [u.facilityId];
}

/// عرض رصيد مخزَّن بالوحدة الأساسية بوحدة العرض المختارة للصنف.
///
/// الرصيد يُحفظ دائمًا بالوحدة الأساسية (كجم مثلًا)، لكن أمين المستودع يعدّ
/// بالأكياس. هذه الدالة تحوّل للعرض فقط ولا تمسّ المخزَّن إطلاقًا.
///
/// تعيد النص كاملًا: «٢٧٫٥ كيس» أو «١١٠٠ كجم» إن لم تُحدَّد وحدة عرض.
({double qty, String unit}) displayBalance(Item item, double baseQty) {
  final unit = item.reportUnit;
  if (unit.isEmpty || unit == item.baseUnit) {
    return (qty: baseQty, unit: item.baseUnit);
  }
  for (final u in unitsOfItem(item)) {
    if (u.name == unit) {
      final f = u.factor <= 0 ? 1.0 : u.factor;
      return (qty: (baseQty / f * 1000).round() / 1000, unit: unit);
    }
  }
  return (qty: baseQty, unit: item.baseUnit);
}

/// وحدات الصنف من عمود JSON — نسخة مستقلة عن الصنف `CatalogRepo` ليستعملها
/// العرض في أي طبقة بلا حاجة إلى مستودع.
List<ItemUnit> unitsOfItem(Item item) {
  try {
    final raw = jsonDecode(item.units);
    if (raw is List) {
      return [
        for (final u in raw.whereType<Map>())
          ItemUnit(
            name: '${u['name'] ?? ''}',
            factor: (u['factor'] as num?)?.toDouble() ?? 1,
            isBase: u['isBase'] == true,
          ),
      ].where((u) => u.name.isNotEmpty).toList();
    }
  } catch (err, stack) {
    ErrorLogger.log('catalog.itemUnits', err, stack);
  }
  return item.baseUnit.isEmpty
      ? const []
      : [ItemUnit(name: item.baseUnit, factor: 1, isBase: true)];
}

class CatalogRepo {
  CatalogRepo(this.db);

  final AppDatabase db;

  // ───────── الأصناف ─────────
  Future<List<Item>> items({String query = ''}) async {
    final rows = await db.select(db.items).get();
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? rows
        : rows
            .where((i) =>
                i.name.toLowerCase().contains(q) ||
                i.code.toLowerCase().contains(q) ||
                i.barcode.toLowerCase().contains(q))
            .toList();
    list.sort(_byCodeThenName);
    return list;
  }

  Future<Item?> itemById(String id) =>
      (db.select(db.items)..where((t) => t.id.equals(id))).getSingleOrNull();

  List<ItemUnit> unitsOf(Item item) {
    try {
      final raw = jsonDecode(item.units);
      if (raw is List && raw.isNotEmpty) {
        return raw
            .whereType<Map>()
            .map((e) => ItemUnit.fromMap(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (err, stack) {
      ErrorLogger.log('catalog.itemUnits', err, stack);
    }
    return [ItemUnit(name: item.baseUnit.isEmpty ? 'وحدة' : item.baseUnit, factor: 1, isBase: true)];
  }

  /// وحدات الصنف من الأكبر إلى الأصغر (تُستخدم في العد والترحيل والطباعة).
  List<ItemUnit> unitsDescending(Item item) =>
      unitsOf(item)..sort((a, b) => b.factor.compareTo(a.factor));

  double factorOf(Item item, String unitName) {
    for (final u in unitsOf(item)) {
      if (u.name == unitName) return u.factor <= 0 ? 1 : u.factor;
    }
    return 1;
  }

  Future<String> saveItem({
    String? id,
    required String code,
    required String name,
    String categoryId = '',
    String categoryName = '',
    String baseUnit = '',
    List<ItemUnit> units = const [],
    double minQty = 0,
    String barcode = '',
    bool isRefillable = false,
    String reportUnit = '',
  }) async {
    final newId = id ?? _newId('itm');
    final list = units.isEmpty ? [ItemUnit(name: baseUnit, factor: 1, isBase: true)] : units;
    final unitsJson = jsonEncode(list.map((u) => u.toMap()).toList());
    // وحدة الأساس تُشتق من الوحدات حين لا تُمرَّر صراحةً (الوحدة ذات isBase).
    final base = baseUnit.isNotEmpty
        ? baseUnit
        : list.firstWhere((u) => u.isBase, orElse: () => list.first).name;
    await db.into(db.items).insertOnConflictUpdate(ItemsCompanion.insert(
          id: newId,
          name: name,
          code: Value(code),
          categoryId: Value(categoryId),
          categoryName: Value(categoryName),
          baseUnit: Value(base),
          units: Value(unitsJson),
          minQty: Value(minQty),
          barcode: Value(barcode),
          isRefillable: Value(isRefillable),
          reportUnit: Value(reportUnit),
        ));
    return newId;
  }

  /// يحذف الصنف. من له حركات لا يُحذف: السجلات تبقى بلا صنف فتختل الأرصدة.
  /// (المشغّل `tg_items_delete_guard` يحرس القاعدة نفسها؛ هذا للرسالة الواضحة.)
  Future<void> deleteItem(String id) async {
    if (await hasMovements(id)) {
      throw StateError('لا يمكن حذف صنف له حركات (وارد أو صرف أو تحويل أو مرتجع أو رصيد افتتاحي أو تسوية)');
    }
    await (db.delete(db.items)..where((t) => t.id.equals(id))).go();
  }

  /// هل للصنف أي حركة مسجَّلة؟
  Future<bool> hasMovements(String id) async {
    final rows = await db.customSelect(
      'SELECT 1 AS x WHERE ${AppDatabase.itemHasMovementsSql('?1')}',
      variables: [Variable.withString(id)],
    ).get();
    return rows.isNotEmpty;
  }

  // ───────── التصنيفات ─────────
  Future<List<Category>> categories() async {
    final rows = await db.select(db.categories).get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<String> saveCategory({String? id, required String name, String description = ''}) async {
    final newId = id ?? _newId('cat');
    await db.into(db.categories).insertOnConflictUpdate(
        CategoriesCompanion.insert(id: newId, name: name, description: Value(description)));
    return newId;
  }

  // ───────── المستودعات ─────────
  /// إضافة سريعة من شاشة الاستلام (➕ بجانب المستودع/المورد).
  Future<void> quickAddWarehouse(String name) =>
      db.into(db.warehouses).insert(WarehousesCompanion.insert(id: Ids.next('wh'), name: name.trim()));
  Future<void> quickAddSupplier(String name) =>
      db.into(db.suppliers).insert(SuppliersCompanion.insert(id: Ids.next('sup'), name: name.trim()));

  Future<List<Warehouse>> warehouses({List<String>? scope}) async {
    final rows = await db.select(db.warehouses).get();
    final list = scope == null ? rows : rows.where((w) => scope.contains(w.name)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// الجداول التي تشير إلى المستودع **بالاسم** لا بالمعرّف، وعمودُ الاسم في كل
  /// منها. سجلُّ التدقيق مستثنى: هو تاريخٌ لما جرى، لا مرجعًا يُتابَع.
  static const Map<String, List<String>> warehouseNameRefs = {
    'receipts': ['warehouse'],
    'issues': ['warehouse'],
    'transfers': ['warehouse', 'dest_warehouse'],
    'returns': ['warehouse'],
    'adjustments': ['warehouse'],
    'opening_balances': ['warehouse'],
    'stocktakes': ['warehouse'],
    'facilities': ['warehouse'],
    'meal_plans': ['warehouse'],
    'assets': ['warehouse'],
    'ration_orders': ['requesting_warehouse', 'supplying_warehouse'],
    'archive_files': ['warehouse'],
    'warehouse_stock_limits': ['warehouse_name'],
  };

  /// هل يشير إلى مستودعٍ بهذا الاسم سجلٌّ واحد على الأقل؟
  ///
  /// نظير `FuelRepo._warehouseInUse` لقسم الإمداد، وأوسعُ منه لأن المستودع هنا
  /// تشير إليه الحركاتُ والمنشآتُ وخطط الوجبات والأصول والطلبيات والأرشيف.
  Future<bool> warehouseInUse(String name) async {
    final key = name.trim();
    if (key.isEmpty) return false;
    final parts = [
      for (final e in warehouseNameRefs.entries)
        for (final col in e.value) 'SELECT 1 FROM "${e.key}" WHERE TRIM("$col") = ?1',
    ];
    final row = await db
        .customSelect('${parts.join(' UNION ALL ')} LIMIT 1', variables: [Variable<String>(key)])
        .getSingleOrNull();
    if (row != null) return true;
    // نطاقُ مستخدمٍ مقيَّد بأسماء مستودعاته (`users.warehouse_scope`، JSON).
    for (final u in await db.select(db.users).get()) {
      if (parseWarehouseScope(u.warehouseScope, source: 'catalog.warehouseInUse')?.contains(key) ?? false) {
        return true;
      }
    }
    return false;
  }

  /// يحفظ مستودعًا. **تغيير اسم مستودعٍ مُستعمَل مرفوض** ([WarehouseBlocked]).
  ///
  /// كل حركةٍ وكل منشأةٍ ونطاقِ مستخدمٍ تشير إلى المستودع **بنصّ اسمه** (ثلاثة
  /// عشر جدولًا، [warehouseNameRefs])، فتغييرُ الاسم يُيتّم ما أشار إليه: يظهر
  /// رصيدُه صفرًا وتبقى حركاته باسمٍ لا مستودعَ له، ويفقد المستخدم المقيَّد
  /// نطاقه. ولا تُرحَّل المراجع لأن الترحيل محليٌّ والنظام موزَّع: جهازٌ لم
  /// يُرحِّل يُرسل صفوفه بالاسم القديم فيعيد بعضها «الأحدثُ يفوز»، و`warehouse_scope`
  /// لا ينتقل أصلًا بلا توقيع المالك. والمحروقات حُسمت على الرفض نفسه
  /// (`FuelRepo.saveWarehouse`).
  Future<String> saveWarehouse({
    String? id,
    required String code,
    required String name,
    String manager = '',
    String location = '',
    bool feedsAllCamps = true,
    List<String> campIds = const [],
    String notes = '',
  }) async {
    final newId = id ?? _newId('wh');
    if (id != null) {
      final old = await (db.select(db.warehouses)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (old != null && old.name.trim() != name.trim() && await warehouseInUse(old.name)) {
        throw WarehouseBlocked('لا يُغيَّر اسم «${old.name}» وعليه حركة أو ارتباط — '
            'أنشئ مستودعًا بالاسم الجديد وحوّل إليه الرصيد');
      }
    }
    await db.into(db.warehouses).insertOnConflictUpdate(WarehousesCompanion.insert(
          id: newId,
          name: name,
          code: Value(code),
          manager: Value(manager),
          location: Value(location),
          feedsAllCamps: Value(feedsAllCamps),
          campIds: Value(jsonEncode(campIds)),
          notes: Value(notes),
        ));
    return newId;
  }

  /// معسكرات المستودع (لربط التحويل بالاستحقاق).
  List<String> campsOf(Warehouse w) {
    try {
      final raw = jsonDecode(w.campIds);
      if (raw is List) return raw.map((e) => e.toString()).toList();
    } catch (err, stack) {
      ErrorLogger.log('catalog.campIds', err, stack);
    }
    return const [];
  }

  // ───────── الموردون ─────────
  Future<List<Supplier>> suppliers() async {
    final rows = await db.select(db.suppliers).get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<String> saveSupplier({
    String? id,
    required String name,
    String phone = '',
    String notes = '',
    String contact = '',
    String city = '',
  }) async {
    final newId = id ?? _newId('sup');
    await db.into(db.suppliers).insertOnConflictUpdate(SuppliersCompanion.insert(
      id: newId,
      name: name,
      phone: Value(phone),
      notes: Value(notes),
      contact: Value(contact),
      city: Value(city),
    ));
    return newId;
  }

  // ───────── الوحدات المستفيدة والمعسكرات ─────────
  Future<List<BeneficiaryUnit>> units() async {
    final rows = await db.select(db.beneficiaryUnits).get();
    rows.sort((a, b) => a.code.compareTo(b.code));
    return rows;
  }

  /// بترتيب الإنشاء (بلا فرز) — لشاشةٍ تعرض الوحدات بترتيب إدخالها.
  Future<List<BeneficiaryUnit>> unitsUnsorted() => db.select(db.beneficiaryUnits).get();

  Future<List<BeneficiaryUnit>> camps() async =>
      (await units()).where((u) => u.isCamp || u.parentId.isEmpty).toList();

  Future<List<BeneficiaryUnit>> childrenOf(String campId) async =>
      (await units()).where((u) => u.parentId == campId).toList();

  Future<String> saveUnit({
    String? id,
    required String code,
    required String name,
    String type = 'unit',
    String parentId = '',
    String parentName = '',
    String? facilityId,
    String category = '',
  }) async {
    final newId = id ?? _newId('unit');
    // facilityId لا يُمس عند التعديل (اشتراك المطبخ يُدار من شاشة المطابخ).
    await db.into(db.beneficiaryUnits).insertOnConflictUpdate(BeneficiaryUnitsCompanion.insert(
          id: newId,
          name: name,
          code: Value(code),
          type: Value(type),
          parentId: Value(parentId),
          parentName: Value(parentName),
          isCamp: Value(type == 'camp'),
          facilityId: facilityId == null ? const Value.absent() : Value(facilityId),
          category: Value(category),
        ));
    return newId;
  }

  // ───────── المطابخ والأفران ─────────
  Future<List<Facility>> facilities() async {
    final rows = await db.select(db.facilities).get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<String> saveFacility({
    String? id,
    required String name,
    String fType = 'KITCHEN',
    int capacity = 0,
    String warehouse = '',
    String notes = '',
  }) async {
    final newId = id ?? _newId('fac');
    await db.into(db.facilities).insertOnConflictUpdate(FacilitiesCompanion.insert(
          id: newId,
          name: name,
          fType: Value(fType),
          capacity: Value(capacity),
          warehouse: Value(warehouse),
          notes: Value(notes),
        ));
    return newId;
  }

  static int _byCodeThenName(Item a, Item b) {
    final ca = int.tryParse(a.code), cb = int.tryParse(b.code);
    if (ca != null && cb != null) return ca.compareTo(cb);
    if (a.code.isNotEmpty && b.code.isNotEmpty) return a.code.compareTo(b.code);
    if (a.code.isNotEmpty) return -1;
    if (b.code.isNotEmpty) return 1;
    return a.name.compareTo(b.name);
  }

  // ───────── عمليات تستعملها شاشات الكتالوج (كانت استعلاماتٍ مباشرة في الشاشات) ─────────

  Future<Item?> itemByCode(String code) async =>
      (await (db.select(db.items)..where((t) => t.code.equals(code))).get()).firstOrNull;

  Future<void> setItemBarcode(String id, String barcode) =>
      (db.update(db.items)..where((t) => t.id.equals(id))).write(ItemsCompanion(barcode: Value(barcode)));

  Future<bool> barcodeTaken(String barcode) async =>
      (await (db.select(db.items)..where((t) => t.barcode.equals(barcode))..limit(1)).get()).isNotEmpty;

  /// مولّد باركود نظامي يبدأ بعد أكبر تسلسل محفوظ في دقيقة [now].
  Future<ItemBarcode> barcodeGenerator([DateTime? now]) async {
    final t = now ?? DateTime.now();
    final prefix = ItemBarcode.prefixOf(t);
    final rows = await (db.selectOnly(db.items)
          ..addColumns([db.items.barcode])
          ..where(db.items.barcode.like('$prefix%')))
        .map((r) => r.read(db.items.barcode) ?? '')
        .get();
    return ItemBarcode.startingAt(t, rows.map((b) => ItemBarcode.seqOf(b, prefix)).whereType<int>());
  }

  /// باركود نظامي جديد غير مكرر (فحص القاعدة + [reserved] الممنوحة في الدفعة نفسها).
  Future<String> newItemBarcode({ItemBarcode? generator, Set<String> reserved = const {}}) async {
    final g = generator ?? await barcodeGenerator();
    return g.nextFree((bc) async => reserved.contains(bc) || await barcodeTaken(bc));
  }

  /// يفرّغ وحدات الصنف (استيراد صنفٍ بلا وحدة): `saveItem` يضيف وحدةً افتراضية.
  Future<void> clearItemUnits(String id) =>
      (db.update(db.items)..where((t) => t.id.equals(id))).write(const ItemsCompanion(units: Value('[]')));

  /// تحديث صنفٍ قائم من صفّ استيراد: الاسم والتصنيف والحد الأدنى دائمًا، والوحدة
  /// الأساسية إن وُجدت، ووحدةٌ أولى ([firstUnitJson]) إن لم يكن للصنف وحدات.
  Future<void> updateItemFromImport(
    String id, {
    required String name,
    required String categoryName,
    required String categoryId,
    required double minQty,
    String baseUnit = '',
    String? firstUnitJson,
  }) =>
      (db.update(db.items)..where((t) => t.id.equals(id))).write(ItemsCompanion(
        name: Value(name),
        categoryName: Value(categoryName),
        categoryId: Value(categoryId),
        baseUnit: baseUnit.isEmpty ? const Value.absent() : Value(baseUnit),
        units: firstUnitJson == null ? const Value.absent() : Value(firstUnitJson),
        minQty: Value(minQty),
      ));

  /// آخر تاريخ رصيدٍ افتتاحي لكل صنف في مستودع.
  Future<Map<String, String>> openingDates(String warehouse) async {
    final rows = await (db.select(db.openingBalances)..where((t) => t.warehouse.equals(warehouse))).get();
    final dates = <String, String>{};
    for (final r in rows) {
      final prev = dates[r.itemId] ?? '';
      if (r.date.compareTo(prev) > 0) dates[r.itemId] = r.date;
    }
    return dates;
  }

  /// معرّف الرصيد الافتتاحي لصنفٍ في مستودع — **واحدٌ** على كل الأجهزة.
  ///
  /// كان التثبيت حذفًا ثم إدراجًا بمعرّفٍ عشوائي، فجهازان يثبّتان رصيد الصنف
  /// نفسه قبل أن يتزامنا يتركان صفّين، فيُجمعان: يُحتسب الرصيد مرتين بصمت (H-7).
  static String openingIdOf(String itemId, String warehouse) => Ids.natural('opb', [itemId, warehouse]);

  /// يثبّت رصيد [item] في [warehouse]: صفٌّ واحد بالمعرّف الحتمي، وتُحذف أي
  /// صفوفٍ أخرى للمفتاح نفسه (من إصدارٍ أقدم أو من دمجٍ سابق) فيسافر شاهد حذفها.
  Future<void> _putOpening(Item item, String warehouse, double qty, String actor, String date) async {
    final id = openingIdOf(item.id, warehouse);
    await (db.delete(db.openingBalances)
          ..where((t) => t.itemId.equals(item.id) & t.warehouse.equals(warehouse) & t.id.equals(id).not()))
        .go();
    await db.into(db.openingBalances).insertOnConflictUpdate(OpeningBalancesCompanion.insert(
          id: id,
          itemId: item.id,
          itemCode: Value(item.code),
          itemName: Value(item.name),
          warehouse: Value(warehouse),
          qty: Value(qty),
          date: Value(date),
          setBy: Value(actor),
          createdAt: Value(DateTime.now()),
        ));
  }

  /// تثبيت عدة أرصدة افتتاحية بمعاملةٍ واحدة وتاريخٍ واحد (كل صنفٍ يستبدل سابقه في المستودع).
  Future<void> setOpeningBalances(String warehouse, String actor, List<({Item item, double qty})> entries,
          {required String date}) =>
      db.transaction(() async {
        for (final e in entries) {
          await _putOpening(e.item, warehouse, e.qty, actor, date);
        }
      });

  /// رصيدٌ افتتاحي للصنف في مستودع — تثبيتٌ يستبدل السابق (كشاشة الأرصدة الافتتاحية).
  Future<void> setOpeningBalance(Item item, String warehouse, double qty, String actor) =>
      db.transaction(() => _putOpening(item, warehouse, qty, actor, isoDay(DateTime.now())));

  Future<void> deleteCategory(String id) =>
      (db.delete(db.categories)..where((t) => t.id.equals(id))).go();

  Future<void> deleteWarehouse(String id) =>
      (db.delete(db.warehouses)..where((t) => t.id.equals(id))).go();

  Future<void> deleteUnit(String id) =>
      (db.delete(db.beneficiaryUnits)..where((t) => t.id.equals(id))).go();

  Future<void> deleteFacility(String id) =>
      (db.delete(db.facilities)..where((t) => t.id.equals(id))).go();

  Future<void> deleteSupplier(String id) =>
      (db.delete(db.suppliers)..where((t) => t.id.equals(id))).go();

  /// اشتراكات وحداتٍ في مطبخ/فرن دفعةً واحدة: كل عنصرٍ (معرّف الوحدة ← قائمة معرّفات
  /// المرافق الجديدة). العمود المفرد `facilityId` يبقى أول اشتراك للتوافق مع التصدير القديم.
  Future<void> setUnitFacilities(Map<String, List<String>> idsByUnit) => db.transaction(() async {
        for (final e in idsByUnit.entries) {
          await (db.update(db.beneficiaryUnits)..where((t) => t.id.equals(e.key))).write(
            BeneficiaryUnitsCompanion(
              facilityIds: Value(jsonEncode(e.value)),
              facilityId: Value(e.value.isEmpty ? '' : e.value.first),
            ),
          );
        }
      });

  static String _newId(String prefix) =>
      Ids.next(prefix);
}
