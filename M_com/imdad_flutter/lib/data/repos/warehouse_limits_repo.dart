import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/warehouse_limits.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import 'catalog_repo.dart';
import 'movements_repo.dart';

/// سطر حدود كما تُدخله الشاشة — **بوحدة الإدخال** لا بوحدة الأساس.
class LimitInput {
  const LimitInput({
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.factor,
    required this.min,
    required this.max,
    this.notes = '',
  });

  final String itemId;
  final String itemName;
  final String unitName;
  final double factor;

  /// بوحدة [unitName].
  final double min;
  final double max;
  final String notes;

  ({String itemId, double min, double max}) get check =>
      (itemId: itemId, min: min, max: max);
}

/// صفٌّ في لوحة المستودع: الحدّ والرصيد والحكم بينهما.
class WarehouseLimitRow {
  const WarehouseLimitRow({
    required this.limit,
    required this.item,
    required this.balanceBase,
  });

  final WarehouseStockLimit limit;
  final Item? item;

  /// الرصيد بوحدة الأساس.
  final double balanceBase;

  double get factor => WarehouseLimits.safeFactor(limit.factor);

  String get unitName =>
      limit.unitName.isNotEmpty ? limit.unitName : (item?.baseUnit ?? '');

  double get balance => WarehouseLimits.fromBase(balanceBase, factor);
  double get min => WarehouseLimits.fromBase(limit.minStock, factor);
  double get max => WarehouseLimits.fromBase(limit.maxStock, factor);

  LimitStatus get status => WarehouseLimits.statusOf(
        balance: balanceBase,
        minStock: limit.minStock,
        maxStock: limit.maxStock,
      );

  /// النقص بوحدة العرض — ما يجب تحويله ليبلغ الحد الأدنى.
  double get shortfall => WarehouseLimits.fromBase(
        WarehouseLimits.shortfall(
            balance: balanceBase, minStock: limit.minStock),
        factor,
      );

  double get surplus => WarehouseLimits.fromBase(
        WarehouseLimits.surplus(balance: balanceBase, maxStock: limit.maxStock),
        factor,
      );

  double? get fillRatio => WarehouseLimits.fillRatio(
        balance: balanceBase,
        maxStock: limit.maxStock,
      );
}

class LimitResult {
  const LimitResult({required this.ok, this.error = '', this.saved = 0});

  final bool ok;
  final String error;
  final int saved;
}

/// حدود مخزون المستودعات: ضبطها، وقراءة لوحة المستودع منها.
///
/// **الحدود تُخزَّن بوحدة الأساس وتُعرض بوحدة صاحبها.** الرصيد في النظام كلّه
/// بوحدة الأساس، فالمقارنة به لا تصحّ إلا بها؛ والمستخدم يضبط حدّه بالكرتون
/// أو الشوال، فإعادته إليه بالحبة تجعله يعيد الحساب في رأسه كل مرة.
class WarehouseLimitsRepo {
  WarehouseLimitsRepo(this.db);

  final AppDatabase db;

  Future<List<WarehouseStockLimit>> limits({String warehouseId = ''}) async {
    final q = db.select(db.warehouseStockLimits);
    if (warehouseId.isNotEmpty) {
      q.where((t) => t.warehouseId.equals(warehouseId));
    }
    final rows = await q.get();
    rows.sort((a, b) => a.itemName.compareTo(b.itemName));
    return rows;
  }

  /// لوحة مستودع: كل صنف له حدّ، ورصيده الآن، والحكم بينهما.
  ///
  /// الرصيد يُقرأ من دفتر الحركات لا من حقلٍ مخزَّن — هو المصدر الوحيد الذي
  /// يوافق التقارير، فلا تختلف اللوحة عن تقرير الأرصدة أمام نفس المستخدم.
  Future<List<WarehouseLimitRow>> dashboard(String warehouseName) async {
    final all = await limits();
    if (all.isEmpty) return const [];
    final byName = await _warehouseIdsByName();
    final id = byName[warehouseName.trim()] ?? '';
    final mine = id.isEmpty
        ? const <WarehouseStockLimit>[]
        : all.where((l) => l.warehouseId == id).toList();
    if (mine.isEmpty) return const [];

    final balances =
        await MovementsRepo(db).balances(warehouse: warehouseName.trim());
    final items = await CatalogRepo(db).items();
    final byId = {for (final i in items) i.id: i};

    final rows = [
      for (final l in mine)
        WarehouseLimitRow(
          limit: l,
          item: byId[l.itemId],
          balanceBase: balances[l.itemId] ?? 0,
        ),
    ];
    // الأحرج أولًا: ما هو تحت الأدنى يُقرأ قبل ما هو سليم.
    const order = {
      LimitStatus.low: 0,
      LimitStatus.over: 1,
      LimitStatus.ok: 2,
      LimitStatus.none: 3,
    };
    rows.sort((a, b) {
      final byStatus = order[a.status]!.compareTo(order[b.status]!);
      return byStatus != 0
          ? byStatus
          : a.limit.itemName.compareTo(b.limit.itemName);
    });
    return rows;
  }

  Future<Map<String, String>> _warehouseIdsByName() async {
    final rows = await db.select(db.warehouses).get();
    return {for (final w in rows) w.name.trim(): w.id};
  }

  /// حفظ دفعة حدود لمستودع واحد.
  ///
  /// الدفعة تُحفظ كلّها أو لا شيء: نصفُ دفعةٍ محفوظ يترك المستخدم لا يدري
  /// أيّ سطر وصل وأيّ سطر ضاع.
  Future<LimitResult> saveBatch({
    required String warehouseId,
    required String warehouseName,
    required List<LimitInput> rows,
    String actor = '',
  }) async {
    if (warehouseId.trim().isEmpty) {
      return const LimitResult(ok: false, error: '✖ اختر المستودع');
    }
    final error =
        WarehouseLimits.validateBatch([for (final r in rows) r.check]);
    if (error != null) return LimitResult(ok: false, error: '✖ $error');

    final existing = await limits(warehouseId: warehouseId);
    final byItem = {for (final l in existing) l.itemId: l};

    await db.transaction(() async {
      for (final r in rows) {
        final factor = WarehouseLimits.safeFactor(r.factor);
        await db
            .into(db.warehouseStockLimits)
            .insertOnConflictUpdate(WarehouseStockLimitsCompanion.insert(
              id: byItem[r.itemId]?.id ?? Ids.next('whl'),
              warehouseId: warehouseId,
              warehouseName: Value(warehouseName),
              itemId: r.itemId,
              itemName: Value(r.itemName),
              unitName: Value(r.unitName),
              factor: Value(factor),
              minStock: Value(WarehouseLimits.toBase(r.min, factor)),
              maxStock: Value(WarehouseLimits.toBase(r.max, factor)),
              notes: Value(r.notes),
              updatedAt: Value(DateTime.now()),
            ));
      }
    });

    await AuditRepo(db).log(
      action: 'warehouseLimit.saveBatch',
      entityType: 'حد مخزون',
      summary: 'ضبط ${rows.length} حدًّا في «$warehouseName»',
      details: {'warehouseId': warehouseId, 'rows': rows.length},
      actorEmail: actor,
    );
    return LimitResult(ok: true, saved: rows.length);
  }

  Future<LimitResult> delete(String id, {String actor = ''}) async {
    final row = await (db.select(db.warehouseStockLimits)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return const LimitResult(ok: false, error: '✖ الحد غير موجود');
    }
    await (db.delete(db.warehouseStockLimits)..where((t) => t.id.equals(id)))
        .go();
    await AuditRepo(db).log(
      action: 'warehouseLimit.delete',
      entityType: 'حد مخزون',
      summary: 'حذف حد «${row.itemName}» من «${row.warehouseName}»',
      details: {'limitId': id},
      actorEmail: actor,
    );
    return const LimitResult(ok: true);
  }

  /// أصناف تحت الحد الأدنى في كل المستودعات — تُغذّي جرس التنبيهات.
  Future<List<WarehouseLimitRow>> lowEverywhere() async {
    final warehouses = await db.select(db.warehouses).get();
    final out = <WarehouseLimitRow>[];
    for (final w in warehouses) {
      final rows = await dashboard(w.name);
      out.addAll(rows.where((r) => r.status == LimitStatus.low));
    }
    return out;
  }
}
