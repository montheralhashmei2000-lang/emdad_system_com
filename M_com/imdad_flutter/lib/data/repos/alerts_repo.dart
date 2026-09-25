import 'package:drift/drift.dart';

import '../../domain/stock_alerts.dart';
import '../../domain/stock_forecast.dart';
import '../../domain/stock_ledger.dart';
import '../db/app_database.dart';
import 'daily_repo.dart';
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

  /// توقّع نفاد الأصناف من صرف آخر [windowDays] يومًا ومن المقررات والقوة.
  ///
  /// الحاجة المقررة تخص القوة كلها، فلا تُحسب إلا لمن نطاقه كل المستودعات:
  /// مقارنتها برصيد مستودع واحد تنذر بنفاد لا وجود له. والأصناف القابلة للتعبئة
  /// أصول تدور لا تُستهلك، فلا توقّع لها.
  Future<List<StockForecast>> forecast({List<String>? scope, int windowDays = 30, DateTime? today}) async {
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final from = _iso(day.subtract(Duration(days: windowDays - 1)));
    final to = _iso(day);

    final items = await (db.select(db.items)..where((t) => t.isRefillable.equals(false))).get();
    final issues = await (db.select(db.issues)
          ..where((t) =>
              t.status.isNotIn(MovementRecord.inactiveStatuses) &
              t.date.isBetweenValues(from, to)))
        .get();
    final consumed = <String, double>{};
    for (final r in issues) {
      if (scope != null && !scope.contains(r.warehouse)) continue;
      consumed[r.itemId] = (consumed[r.itemId] ?? 0) + r.baseQty;
    }

    // نظام عمره أقل من الفترة: القسمة على عمره لا على الفترة كلها.
    final first = await db.customSelect("SELECT MIN(date) AS d FROM issues WHERE date <> ''").getSingle();
    final firstDay = DateTime.tryParse('${first.data['d'] ?? ''}');
    final age = firstDay == null ? windowDays : day.difference(firstDay).inDays + 1;
    final days = age.clamp(1, windowDays);

    final planned = <String, double>{};
    if (scope == null) {
      final strength = StockForecasting.currentStrength(await DailyRepo(db).calculator(), to);
      if (strength > 0) {
        for (final e in await db.select(db.entitlements).get()) {
          if (e.qtyPerPerson <= 0) continue;
          planned[e.itemId] = StockForecasting.plannedDaily(
            monthlyPerPerson: e.qtyPerPerson,
            measureFactor: e.measureFactor,
            strength: strength,
          );
        }
      }
    }

    final balances = await _moves.balances(scope: scope);
    return StockForecasting.forecast([
      for (final it in items)
        ForecastInput(
          itemId: it.id,
          balance: balances[it.id] ?? 0,
          consumed: consumed[it.id] ?? 0,
          windowDays: days,
          plannedDaily: planned[it.id],
        ),
    ], day);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
