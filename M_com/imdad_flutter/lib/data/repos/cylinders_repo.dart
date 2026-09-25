import 'package:drift/drift.dart';

import '../../domain/cylinders.dart';
import '../db/app_database.dart';

/// موقف الأسطوانات من السندات: المستودعات بحالاتها، والعهد لدى الوحدات والمطابخ.
class CylindersRepo {
  CylindersRepo(this.db);

  final AppDatabase db;

  /// الأصناف القابلة للتعبئة.
  Future<List<Item>> items() => (db.select(db.items)
        ..where((t) => t.isRefillable.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.code)]))
      .get();

  /// [scope] نطاق مستودعات المستخدم (`null` ⇒ الكل): تُحسب حركات مستودعاته وحدها،
  /// ومنها ما صرفته عهدةً.
  Future<CylinderPosition> position({List<String>? scope}) async {
    final ids = [for (final i in await items()) i.id];
    if (ids.isEmpty) return CylinderPosition.from(const []);
    bool inScope(String wh) => scope == null || scope.contains(wh);

    final units = await db.select(db.beneficiaryUnits).get();
    final facilities = await db.select(db.facilities).get();
    final unitByName = {for (final u in units) u.name.trim(): u};
    final facilityByName = {for (final f in facilities) f.name.trim(): f};

    final moves = <CylMove>[];
    for (final o in await (db.select(db.openingBalances)..where((t) => t.itemId.isIn(ids))).get()) {
      if (!inScope(o.warehouse)) continue;
      moves.add(CylMove(
          kind: CylMoveKind.opening, itemId: o.itemId, warehouse: o.warehouse, qty: o.qty, date: o.date, at: o.createdAt));
    }
    for (final a in await (db.select(db.adjustments)..where((t) => t.itemId.isIn(ids))).get()) {
      if (!inScope(a.warehouse)) continue;
      moves.add(CylMove(
          kind: CylMoveKind.adjustment,
          itemId: a.itemId,
          warehouse: a.warehouse,
          qty: a.baseQty,
          status: a.status,
          date: a.date,
          at: a.createdAt));
    }
    for (final r in await (db.select(db.receipts)..where((t) => t.itemId.isIn(ids))).get()) {
      if (!inScope(r.warehouse)) continue;
      moves.add(CylMove(
        kind: CylMoveKind.receipt,
        itemId: r.itemId,
        warehouse: r.warehouse,
        qty: r.baseQty,
        action: r.cylinderAction,
        status: r.status,
        date: r.date,
        at: r.createdAt,
      ));
    }
    for (final i in await (db.select(db.issues)..where((t) => t.itemId.isIn(ids))).get()) {
      if (!inScope(i.warehouse)) continue;
      final h = _issueHolder(i);
      moves.add(CylMove(
        kind: CylMoveKind.issue,
        itemId: i.itemId,
        warehouse: i.warehouse,
        qty: i.baseQty,
        action: i.cylinderAction,
        status: i.status,
        date: i.date,
        at: i.createdAt,
        holderKey: h.key,
        holderName: h.name,
        holderKind: h.kind,
      ));
    }
    for (final t in await (db.select(db.transfers)..where((t) => t.itemId.isIn(ids))).get()) {
      final from = inScope(t.warehouse), to = inScope(t.destWarehouse);
      if (!from && !to) continue;
      moves.add(CylMove(
        kind: CylMoveKind.transfer,
        itemId: t.itemId,
        // مستودع خارج النطاق يُحسب باسمه ثم يُحذف من العرض: حركة واحدة تمس الطرفين.
        warehouse: t.warehouse,
        destWarehouse: t.destWarehouse,
        qty: t.baseQty,
        action: t.cylinderAction,
        status: t.status,
        date: t.date,
        at: t.createdAt,
      ));
    }
    for (final r in await (db.select(db.returns)..where((t) => t.itemId.isIn(ids))).get()) {
      if (!inScope(r.warehouse)) continue;
      if (r.type == 'TO_SUPPLIER') {
        moves.add(CylMove(
          kind: CylMoveKind.returnToSupplier,
          itemId: r.itemId,
          warehouse: r.warehouse,
          qty: r.baseQty,
          action: r.cylinderAction,
          status: r.status,
          date: r.date,
          at: r.createdAt,
        ));
        continue;
      }
      // صاحب العهدة: بمعرّف الوحدة إن حُفظ (v11)، وإلا بمطابقة الاسم مطبخًا أو وحدةً.
      var key = 'name:${r.party.trim()}';
      var kind = CylHolderKind.other;
      var name = r.party;
      if (r.beneficiaryUnitId.isNotEmpty) {
        key = 'unit:${r.beneficiaryUnitId}';
        kind = CylHolderKind.unit;
        name = r.beneficiaryUnitName.isNotEmpty ? r.beneficiaryUnitName : r.party;
      } else if (facilityByName[r.party.trim()] case final f?) {
        key = 'facility:${f.id}';
        kind = CylHolderKind.facility;
      } else if (unitByName[r.party.trim()] case final u?) {
        key = 'unit:${u.id}';
        kind = CylHolderKind.unit;
      }
      moves.add(CylMove(
        kind: CylMoveKind.returnFromUnit,
        itemId: r.itemId,
        warehouse: r.warehouse,
        qty: r.baseQty,
        action: r.cylinderAction,
        status: r.status,
        date: r.date,
        at: r.createdAt,
        holderKey: key,
        holderName: name,
        holderKind: kind,
        damaged: r.condition == 'تالفة',
      ));
    }

    final p = CylinderPosition.from(moves);
    if (scope != null) {
      for (final byWh in p.stock.values) {
        byWh.removeWhere((wh, _) => !scope.contains(wh));
      }
    }
    return p;
  }

  static ({String key, String name, CylHolderKind kind}) _issueHolder(Issue i) {
    if (i.targetType == 3 && i.beneficiaryUnitId.isNotEmpty) {
      return (key: 'unit:${i.beneficiaryUnitId}', name: i.beneficiaryUnitName, kind: CylHolderKind.unit);
    }
    if (i.targetType == 0 && i.unitId.isNotEmpty) {
      return (key: 'unit:${i.unitId}', name: i.recipientDisplay, kind: CylHolderKind.unit);
    }
    if (i.targetType == 1 && i.facilityId.isNotEmpty) {
      return (key: 'facility:${i.facilityId}', name: i.recipientDisplay, kind: CylHolderKind.facility);
    }
    return (key: 'name:${i.recipientDisplay.trim()}', name: i.recipientDisplay, kind: CylHolderKind.other);
  }
}
