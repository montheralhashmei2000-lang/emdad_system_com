import 'package:drift/drift.dart';

import '../../domain/stock_alerts.dart';
import '../../domain/stock_ledger.dart';
import '../db/app_database.dart';
import 'movements_repo.dart';

/// بيانات شاشة التنبيهات، محصورة بنطاق مستودعات المستخدم.
class AlertsRepo {
  AlertsRepo(this.db);

  final AppDatabase db;

  late final MovementsRepo _moves = MovementsRepo(db);

  /// الأصناف تحت حدها الأدنى، على إجمالي مستودعات النطاق ([scope] null = الكل).
  Future<List<LowStockAlert>> lowStock({List<String>? scope}) async {
    final items = await (db.select(db.items)..where((t) => t.minQty.isBiggerThanValue(0))).get();
    final balances = await _moves.balances(scope: scope);
    return StockAlerts.lowStock([for (final i in items) (id: i.id, minQty: i.minQty)], balances);
  }

  /// دفعات تنتهي صلاحيتها خلال [withinDays] يومًا وما زال منها رصيد.
  Future<List<ExpiryAlert>> expiring({List<String>? scope, int withinDays = 30, DateTime? today}) async {
    // كل الوارد المعتمد لأصناف لها دفعة مؤرَّخة واحدة على الأقل — المؤرَّخ وغيره،
    // لأن الوارد الأحدث بلا تاريخ يأخذ نصيبه من الرصيد قبل الدفعات الأقدم.
    final dated = await (db.selectOnly(db.receipts, distinct: true)
          ..addColumns([db.receipts.itemId])
          ..where(db.receipts.expiryDate.isNotValue('')))
        .map((r) => r.read(db.receipts.itemId)!)
        .get();
    if (dated.isEmpty) return const [];
    final rows = await (db.select(db.receipts)
          ..where((t) =>
              t.itemId.isIn(dated) &
              t.status.isNotIn(MovementRecord.inactiveStatuses) &
              t.cylinderAction.isNotValue('REFILL')))
        .get();
    return StockAlerts.expiring(
      lots: [
        for (final r in rows)
          if (scope == null || scope.contains(r.warehouse))
            ExpiryLot(
              warehouse: r.warehouse,
              itemId: r.itemId,
              receivedOn: r.date,
              expiryDate: r.expiryDate,
              baseQty: r.baseQty,
              refNo: r.refNo,
            ),
      ],
      balances: await _moves.balancesByWarehouse(scope: scope),
      today: today ?? DateTime.now(),
      withinDays: withinDays,
    );
  }
}
