import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import 'catalog_repo.dart';
import 'movements_repo.dart';

/// دورة الجرد الكاملة: إنشاء الأمر ← العد الفعلي ← تحليل الفروقات ←
/// التسوية والاعتماد ← السجل. مطابقة لقواعد نسخة الويب:
/// • رصيد الدفاتر يُلتقط من دفتر أرصدة المستودع لحظة إنشاء الأمر.
/// • تجميد المستودع يمنع أي حركة عليه ما دام الأمر مفتوحًا.
/// • الاعتماد يكتب فرق كل صنف تسويةً في رصيد المستودع، ثم يُغلق الأمر.
class StocktakeRepo {
  StocktakeRepo(this.db);

  final AppDatabase db;

  static const String counting = 'COUNTING';
  static const String review = 'REVIEW';
  static const String closed = 'CLOSED';
  static const String cancelled = 'CANCELLED';

  static const String decisionAdjust = 'ADJUST';
  static const String decisionIgnore = 'IGNORE';
  static const String decisionRecount = 'RECOUNT';

  Future<List<Stocktake>> sessions({String? warehouse, String? status}) async {
    final q = db.select(db.stocktakes);
    if (warehouse != null && warehouse.isNotEmpty) {
      q.where((t) => t.warehouse.equals(warehouse));
    }
    if (status != null && status.isNotEmpty) q.where((t) => t.status.equals(status));
    final rows = await q.get();
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  Future<Stocktake?> sessionById(String id) async {
    final rows = await (db.select(db.stocktakes)..where((t) => t.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// أمر جرد مفتوح يجمّد المستودع (إن وُجد) — تستخدمه شاشات الحركات للمنع.
  Future<Stocktake?> frozenOrderOf(String warehouse) async {
    final rows = await (db.select(db.stocktakes)
          ..where((t) =>
              t.warehouse.equals(warehouse) &
              t.freeze.equals(true) &
              t.status.isNotValue(closed)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<StocktakeLine>> lines(String sessionId) async {
    final rows = await (db.select(db.stocktakeLines)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();
    rows.sort((a, b) => a.itemName.compareTo(b.itemName));
    return rows;
  }

  /// إنشاء أمر جرد والتقاط رصيد الدفاتر لكل صنف في المستودع المحدد.
  Future<String> createOrder({
    required String warehouse,
    required String date,
    String type = 'FULL',
    String categoryId = '',
    String categoryName = '',
    String committee = '',
    bool freeze = true,
    String notes = '',
    String createdBy = '',
  }) async {
    final catalog = CatalogRepo(db);
    final moves = MovementsRepo(db);
    final balances = await moves.balances(warehouse: warehouse);
    final items = await catalog.items();
    // `PARTIAL` في الويب = جرد جزئي بتصنيف محدد، وما عداه يشمل كل الأصناف.
    final scoped = (type == 'PARTIAL' && categoryId.isNotEmpty)
        ? items.where((i) => i.categoryId == categoryId).toList()
        : items;

    final id = Ids.next('stk');
    final orderNo = await _nextOrderNo();

    await db.into(db.stocktakes).insert(StocktakesCompanion.insert(
          id: id,
          orderNo: Value(orderNo),
          type: Value(type),
          date: Value(date),
          warehouse: Value(warehouse),
          categoryId: Value(categoryId),
          categoryName: Value(categoryName),
          committee: Value(committee),
          freeze: Value(freeze),
          status: const Value(counting),
          itemsCount: Value(scoped.length),
          notes: Value(notes),
          createdBy: Value(createdBy),
        ));

    await db.batch((b) {
      for (final item in scoped) {
        b.insert(
          db.stocktakeLines,
          StocktakeLinesCompanion.insert(
            id: Ids.next('stl-${item.id}'),
            sessionId: id,
            itemId: item.id,
            itemCode: Value(item.code),
            itemName: Value(item.name),
            unitName: Value(item.baseUnit),
            systemQty: Value(balances[item.id] ?? 0),
          ),
        );
      }
    });
    return id;
  }

  /// `nextNo()` — STK-<السنة>-<تسلسل من ثلاث خانات> لأوامر السنة الحالية.
  Future<String> _nextOrderNo() async {
    final year = DateTime.now().year;
    final re = RegExp(r'^STK-(\d{4})-(\d+)$');
    var max = 0;
    for (final o in await db.select(db.stocktakes).get()) {
      final m = re.firstMatch(o.orderNo);
      if (m != null && int.parse(m.group(1)!) == year) {
        max = max > int.parse(m.group(2)!) ? max : int.parse(m.group(2)!);
      }
    }
    return 'STK-$year-${(max + 1).toString().padLeft(3, '0')}';
  }

  /// أمر جرد مفتوح على المستودع (مجمّدًا كان أو لا) — يمنع فتح أمر ثانٍ له.
  Future<Stocktake?> openOrderOf(String warehouse) async {
    final rows = await (db.select(db.stocktakes)
          ..where((t) => t.warehouse.equals(warehouse) & t.status.equals(counting)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// تسجيل العد الفعلي لصنف: كميات بالوحدات المختلفة تُحوَّل إلى وحدة الأساس.
  Future<void> saveCount({
    required String lineId,
    required Map<String, double> countsByUnit,
    required Map<String, double> factors,
  }) async {
    var base = 0.0;
    countsByUnit.forEach((unit, qty) {
      base += qty * (factors[unit] ?? 1);
    });
    base = _round(base);

    final rows = await (db.select(db.stocktakeLines)..where((t) => t.id.equals(lineId))).get();
    if (rows.isEmpty) return;
    final line = rows.first;

    await (db.update(db.stocktakeLines)..where((t) => t.id.equals(lineId))).write(
      StocktakeLinesCompanion(
        counts: Value(jsonEncode(countsByUnit)),
        countedQty: Value(base),
        variance: Value(_round(base - line.systemQty)),
        status: const Value('COUNTED'),
      ),
    );
  }

  /// `addItem()` — صنف مكتشف أثناء العد يُضاف للأمر برصيد دفتري لحظي.
  Future<void> addDiscoveredItem({
    required String sessionId,
    required Item item,
    required String warehouse,
  }) async {
    final balances = await MovementsRepo(db).balances(warehouse: warehouse);
    await db.into(db.stocktakeLines).insert(StocktakeLinesCompanion.insert(
          id: Ids.next('stl'),
          sessionId: sessionId,
          itemId: item.id,
          itemCode: Value(item.code),
          itemName: Value(item.name),
          unitName: Value(item.baseUnit),
          systemQty: Value(_round(balances[item.id] ?? 0)),
          discovered: const Value(true),
        ));
    final session = await sessionById(sessionId);
    if (session != null) {
      await (db.update(db.stocktakes)..where((t) => t.id.equals(sessionId)))
          .write(StocktakesCompanion(itemsCount: Value(session.itemsCount + 1)));
    }
  }

  /// `cancelOrder()` — إلغاء الأمر ورفع التجميد مع حفظ السبب.
  Future<void> cancelOrder({
    required String sessionId,
    required String reason,
    String cancelledBy = '',
  }) async {
    final session = await sessionById(sessionId);
    if (session == null) return;
    await (db.update(db.stocktakes)..where((t) => t.id.equals(sessionId))).write(StocktakesCompanion(
      status: const Value(cancelled),
      freeze: const Value(false),
      cancelReason: Value(reason),
      cancelledBy: Value(cancelledBy),
      closedDate: Value(_today()),
    ));
    await AuditRepo(db).write(
      'STOCKTAKE_CANCELLED',
      'stocktake',
      'إلغاء أمر الجرد ${session.orderNo}',
      details: {
        'refNo': session.orderNo,
        'warehouse': session.warehouse,
        'status': cancelled,
        'reason': reason,
        'risk': 'sensitive',
      },
    );
  }

  Future<void> setDecision({
    required String lineId,
    required String decision,
    String reason = '',
  }) =>
      (db.update(db.stocktakeLines)..where((t) => t.id.equals(lineId))).write(
        StocktakeLinesCompanion(decision: Value(decision), reason: Value(reason)),
      );

  Future<void> moveToReview(String sessionId) =>
      (db.update(db.stocktakes)..where((t) => t.id.equals(sessionId)))
          .write(const StocktakesCompanion(status: Value(review)));

  /// اعتماد التسوية: تُكتب فروق الأصناف المقرَّر تسويتها كحركات تسوية على
  /// المستودع، ثم يُغلق الأمر ويُفك التجميد. الأصناف المهملة أو المطلوب
  /// إعادة عدّها لا تُغيِّر الرصيد.
  Future<int> approve({
    required String sessionId,
    String approvedBy = '',
  }) async {
    final session = await sessionById(sessionId);
    if (session == null) return 0;
    final rows = await lines(sessionId);
    var applied = 0;
    var totalAdjusted = 0.0;

    for (final l in rows) {
      final variance = l.variance ?? 0;
      if (l.decision != decisionAdjust || variance == 0 || l.countedQty == null) continue;
      await db.into(db.adjustments).insert(AdjustmentsCompanion.insert(
            id: 'adj-${l.id}',
            refNo: Value(session.orderNo),
            date: Value(session.date),
            warehouse: Value(session.warehouse),
            itemId: Value(l.itemId),
            itemCode: Value(l.itemCode),
            itemName: Value(l.itemName),
            unitName: Value(l.unitName),
            qty: Value(variance),
            baseQty: Value(variance),
            createdBy: Value(approvedBy),
            sessionId: Value(sessionId),
            reason: Value(l.reason),
            approvedBy: Value(approvedBy),
          ));
      await (db.update(db.stocktakeLines)..where((t) => t.id.equals(l.id)))
          .write(const StocktakeLinesCompanion(status: Value('SETTLED')));
      totalAdjusted += variance.abs();
      applied++;
    }

    final counted = rows.where((l) => l.countedQty != null).toList();
    final varied = counted.where((l) => (l.variance ?? 0) != 0).length;
    await (db.update(db.stocktakes)..where((t) => t.id.equals(sessionId))).write(
      StocktakesCompanion(
        status: const Value(closed),
        freeze: const Value(false),
        closedDate: Value(_today()),
        closedBy: Value(approvedBy),
        countedCount: Value(counted.length),
        varianceCount: Value(varied),
        adjustedCount: Value(applied),
      ),
    );

    await AuditRepo(db).write(
      'STOCKTAKE_POSTED',
      'stocktake',
      'اعتماد تسوية الجرد ${session.orderNo}',
      details: {
        'refNo': session.orderNo,
        'warehouse': session.warehouse,
        'status': closed,
        'itemCount': applied,
        'totalBaseQty': totalAdjusted,
        'risk': 'critical',
      },
    );
    return applied;
  }

  Future<void> deleteSession(String sessionId) async {
    await (db.delete(db.stocktakeLines)..where((t) => t.sessionId.equals(sessionId))).go();
    await (db.delete(db.stocktakes)..where((t) => t.id.equals(sessionId))).go();
  }

  static Map<String, double> countsOf(StocktakeLine line) {
    final raw = jsonDecode(line.counts);
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  /// توزيع كمية بوحدة الأساس على الوحدات من الأكبر إلى الأصغر (للعرض).
  static Map<String, double> split(double baseQty, List<ItemUnit> unitsDescending) {
    final out = <String, double>{};
    var rest = baseQty.abs();
    for (var i = 0; i < unitsDescending.length; i++) {
      final u = unitsDescending[i];
      final f = u.factor <= 0 ? 1.0 : u.factor;
      if (i == unitsDescending.length - 1) {
        out[u.name] = _round(rest / f);
      } else {
        final whole = (rest / f).floor().toDouble();
        if (whole > 0) out[u.name] = whole;
        rest = _round(rest - whole * f);
      }
    }
    if (baseQty < 0) {
      out.updateAll((key, value) => -value);
    }
    return out;
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}
