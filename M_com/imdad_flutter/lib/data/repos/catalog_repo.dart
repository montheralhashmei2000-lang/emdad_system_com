import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';

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
  } catch (_) {}
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
  } catch (_) {}
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
    } catch (_) {}
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
    // وحدة الأساس تُشتق من الوحدات حين لا تُمرَّر صراحةً (كما في الويب: `baseUnit` = وحدة isBase).
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

  Future<void> deleteItem(String id) =>
      (db.delete(db.items)..where((t) => t.id.equals(id))).go();

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
  Future<List<Warehouse>> warehouses({List<String>? scope}) async {
    final rows = await db.select(db.warehouses).get();
    final list = scope == null ? rows : rows.where((w) => scope.contains(w.name)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

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
    } catch (_) {}
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
    // facilityId لا يُمس عند التعديل (اشتراك المطبخ يُدار من شاشة المطابخ) كما في unSave بالويب.
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

  static String _newId(String prefix) =>
      Ids.next(prefix);
}
