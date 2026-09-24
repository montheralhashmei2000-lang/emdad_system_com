import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/camp_ledger.dart';
import '../../domain/date_span.dart';
import '../../domain/stock_alert.dart';
import '../../domain/variance_tracker.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import 'catalog_repo.dart';
import 'settings_repo.dart';

/// سجل مع مكوّناته الجاهزة للحساب.
class CampLedgerRow {
  const CampLedgerRow({required this.ledger, required this.amounts});

  final CampLedger ledger;
  final LedgerAmounts amounts;
}

class SettlementResult {
  const SettlementResult({
    required this.ok,
    this.error = '',
    this.camps = 0,
    this.items = 0,
    this.nextYear = 0,
    this.nextMonth = 0,
  });

  final bool ok;
  final String error;
  final int camps;
  final int items;
  final int nextYear;
  final int nextMonth;
}

/// سجل حساب المعسكرات: بناؤه من المصادر، وحدود مخزونه، وتصفية شهره.
///
/// **السجل مشتقّ لا مُدخَل.** لا يكتب فيه أحد رقمًا بيده: يُعاد بناؤه من
/// التفريدة والمقرر والتحويلات والصرف والمرتجعات وسجل الطهي. ولذلك تصحيح
/// تفريدة يوم يصحّح السجل كله بإعادة بناء، لا بتعديل يدوي يُنسى.
class CampLedgerRepo {
  CampLedgerRepo(this.db);

  final AppDatabase db;

  static DateSpan monthSpan(int year, int month) => DateSpan(
        DateSpan.ymd(DateTime(year, month, 1)),
        DateSpan.ymd(DateTime(year, month + 1, 0)),
      );

  // ───────────────────────── المخزن الرئيسي

  Future<Warehouse?> mainWarehouse() async {
    final rows =
        await (db.select(db.warehouses)..where((t) => t.isMain.equals(true))).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// تعيين المخزن الرئيسي — واحد لا أكثر، فيُلغى السابق في المعاملة نفسها.
  Future<void> setMainWarehouse(String warehouseId, {String actor = ''}) async {
    await db.transaction(() async {
      await db.update(db.warehouses).write(const WarehousesCompanion(isMain: Value(false)));
      await (db.update(db.warehouses)..where((t) => t.id.equals(warehouseId)))
          .write(const WarehousesCompanion(isMain: Value(true)));
    });
    final w = await (db.select(db.warehouses)..where((t) => t.id.equals(warehouseId)))
        .getSingleOrNull();
    await AuditRepo(db).log(
      action: 'warehouse.setMain',
      entityType: 'مستودع',
      summary: 'تعيين «${w?.name ?? warehouseId}» مخزنًا رئيسيًا',
      details: {'warehouseId': warehouseId},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ───────────────────────── قراءة السجل

  Future<List<CampLedgerRow>> ledgers({
    required int year,
    required int month,
    String campId = '',
    String status = '',
  }) async {
    final q = db.select(db.campLedgers)
      ..where((t) => t.year.equals(year) & t.month.equals(month));
    if (campId.isNotEmpty) q.where((t) => t.campId.equals(campId));
    if (status.isNotEmpty) q.where((t) => t.status.equals(status));
    final rows = await q.get();
    rows.sort((a, b) => a.itemName.compareTo(b.itemName));
    return [for (final r in rows) CampLedgerRow(ledger: r, amounts: _amountsOf(r))];
  }

  /// تاريخ صنف في معسكر عبر الشهور — منه يُقرأ اتجاه الرصيد.
  Future<List<CampLedgerRow>> history({
    required String campId,
    required String itemId,
    int limit = 12,
  }) async {
    final rows = await (db.select(db.campLedgers)
          ..where((t) => t.campId.equals(campId) & t.itemId.equals(itemId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.year),
            (t) => OrderingTerm.desc(t.month),
          ])
          ..limit(limit))
        .get();
    return [for (final r in rows) CampLedgerRow(ledger: r, amounts: _amountsOf(r))];
  }

  static LedgerAmounts _amountsOf(CampLedger r) => LedgerAmounts(
        openingEntitled: r.openingEntitled,
        openingStock: r.openingStock,
        entitlementTotal: r.entitlementTotal,
        transferredIn: r.transferredIn,
        issuedDirect: r.issuedDirect,
        returnedQty: r.returnedQty,
        consumedKitchen: r.consumedKitchen,
      );

  // ───────────────────────── بناء السجل

  /// يعيد بناء سجلات شهر لمعسكر واحد أو للمعسكرات كلها.
  ///
  /// الشهر المُغلق لا يُمسّ: أرقامه صارت أساس الشهر التالي، وتغييرها بأثر
  /// رجعي يفسد سلسلة الترحيل كلها.
  Future<int> rebuild({
    required int year,
    required int month,
    String campId = '',
    String actor = '',
  }) async {
    final catalog = CatalogRepo(db);
    final camps = (await catalog.camps())
        .where((c) => campId.isEmpty || c.id == campId)
        .toList();
    if (camps.isEmpty) return 0;

    final span = monthSpan(year, month);
    final items = await catalog.items();
    final itemById = {for (final i in items) i.id: i};
    final scales = await db.select(db.entitlements).get();
    final units = await catalog.units();
    final facilities = await db.select(db.facilities).get();

    // المصادر تُقرأ مرة واحدة لا مرة لكل معسكر وصنف.
    final transfers = await _inSpan(db.select(db.transfers).get(), span);
    final issues = await _inSpan(db.select(db.issues).get(), span);
    final returns = await _inSpan(db.select(db.returns).get(), span);
    final logs = (await db.select(db.kitchenLogs).get())
        .where((l) => span.contains(l.date))
        .toList();
    final strengths = (await db.select(db.strengths).get())
        .where((s) => span.contains(s.strengthDate))
        .toList();

    var written = 0;
    for (final camp in camps) {
      final memberIds = _membersOf(camp, units);
      final memberNames = {
        camp.name.trim(),
        for (final u in units)
          if (memberIds.contains(u.id)) u.name.trim(),
      }..removeWhere((v) => v.isEmpty);
      final facilityIds = _facilitiesOf(camp, units, memberIds, facilities);
      final strengthByDay = _strengthByDay(strengths, camp.id, memberIds);
      final strengthSum = strengthByDay.values.fold<double>(0, (s, v) => s + v);

      for (final scale in scales) {
        final item = itemById[scale.itemId];
        final entitlement = CampLedgerCalc.entitlementOf(
          monthlyQtyPerPerson: scale.qtyPerPerson,
          measureFactor: scale.measureFactor,
          strengthSum: strengthSum,
        );

        final transferredIn = transfers
            .where((t) => t.campId == camp.id && t.itemId == scale.itemId)
            .fold<double>(0, (s, t) => s + t.baseQty);
        final issuedDirect = issues
            .where((i) =>
                i.itemId == scale.itemId &&
                (memberIds.contains(i.beneficiaryUnitId) || memberIds.contains(i.unitId)))
            .fold<double>(0, (s, i) => s + i.baseQty);
        // المرتجع يُنسب بمعرّف وحدته. والسطور التي سبقت العمود (v11) لا معرّف
        // لها، فتُطابق بالاسم — احتياطٌ للقديم لا أساسٌ للجديد.
        final returned = returns
            .where((r) =>
                r.itemId == scale.itemId &&
                r.type == 'FROM_UNIT' &&
                (r.beneficiaryUnitId.isNotEmpty
                    ? memberIds.contains(r.beneficiaryUnitId)
                    : memberNames.contains(r.party.trim())))
            .fold<double>(0, (s, r) => s + r.baseQty);
        final consumed = logs
            .where((l) => l.itemId == scale.itemId && facilityIds.contains(l.facilityId))
            .fold<double>(0, (s, l) => s + l.baseQty);

        final nothing = entitlement == 0 &&
            transferredIn == 0 &&
            issuedDirect == 0 &&
            returned == 0 &&
            consumed == 0;

        final existing = await _find(camp.id, scale.itemId, year, month);
        if (existing != null && existing.status == 'CLOSED') continue;
        // سطرٌ بلا أي حركة ولا استحقاق لا يُنشأ: جدولٌ بمعسكرات × أصناف يمتلئ
        // بآلاف الأصفار فلا يُقرأ.
        if (nothing && existing == null) continue;

        final opening = await _openingOf(camp.id, scale.itemId, year, month);
        await db.into(db.campLedgers).insertOnConflictUpdate(CampLedgersCompanion.insert(
              id: existing?.id ?? Ids.next('cld'),
              campId: camp.id,
              campName: Value(camp.name),
              itemId: scale.itemId,
              itemName: Value(item?.name ?? scale.itemName),
              unitName: Value(item?.baseUnit ?? ''),
              year: year,
              month: month,
              openingEntitled: Value(opening.entitled),
              openingStock: Value(opening.stock),
              entitlementTotal: Value(entitlement),
              transferredIn: Value(CampLedgerCalc.round(transferredIn)),
              issuedDirect: Value(CampLedgerCalc.round(issuedDirect)),
              returnedQty: Value(CampLedgerCalc.round(returned)),
              consumedKitchen: Value(CampLedgerCalc.round(consumed)),
              strengthSum: Value(CampLedgerCalc.round(strengthSum)),
              strengthDays: Value(strengthByDay.length),
              updatedAt: Value(DateTime.now()),
            ));
        written++;
      }
    }

    if (written > 0 && actor.isNotEmpty) {
      await AuditRepo(db).log(
        action: 'campLedger.rebuild',
        entityType: 'سجل معسكر',
        summary: 'إعادة بناء سجل $month/$year — $written سطرًا',
        details: {'year': year, 'month': month, 'rows': written},
        actorEmail: actor,
      );
    }
    return written;
  }

  Future<List<T>> _inSpan<T>(Future<List<T>> future, DateSpan span) async {
    final rows = await future;
    return rows.where((r) => span.contains((r as dynamic).date as String)).toList();
  }

  /// المعسكر ووحداته الفرعية — الصرف يقع على الوحدة لا على المعسكر غالبًا.
  static Set<String> _membersOf(BeneficiaryUnit camp, List<BeneficiaryUnit> units) => {
        camp.id,
        for (final u in units)
          if (u.parentId == camp.id) u.id,
      };

  static Set<String> _facilitiesOf(
    BeneficiaryUnit camp,
    List<BeneficiaryUnit> units,
    Set<String> memberIds,
    List<Facility> facilities,
  ) {
    final ids = <String>{};
    for (final u in units) {
      if (!memberIds.contains(u.id)) continue;
      ids.addAll(facilityIdsOf(u));
    }
    ids.addAll(facilityIdsOf(camp));
    ids.removeWhere((v) => v.isEmpty);
    return ids;
  }

  /// قوة المعسكر لكل يوم.
  ///
  /// سطر «المعسكر» يُغني عن تفصيل وحداته، فجمعهما يضاعف القوة ويضاعف معها
  /// الاستحقاق كله.
  static Map<String, double> _strengthByDay(
    List<Strength> rows,
    String campId,
    Set<String> memberIds,
  ) {
    final detail = <String, double>{};
    final camp = <String, double>{};
    for (final s in rows) {
      final belongs = s.campId == campId || memberIds.contains(s.unitId);
      if (!belongs) continue;
      final bucket = s.mode == 'camp' ? camp : detail;
      bucket.update(s.strengthDate, (v) => v + s.total, ifAbsent: () => s.total);
    }
    final out = <String, double>{...camp};
    // التفصيل أدقّ، فيغلب سطر المعسكر في اليوم الذي سُجّل فيه الاثنان.
    out.addAll(detail);
    return out;
  }

  Future<CampLedger?> _find(String campId, String itemId, int year, int month) async {
    final rows = await (db.select(db.campLedgers)
          ..where((t) =>
              t.campId.equals(campId) &
              t.itemId.equals(itemId) &
              t.year.equals(year) &
              t.month.equals(month)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// رصيدا الترحيل من الشهر السابق — من سجله المُغلق وحده.
  ///
  /// شهرٌ سابق لم يُصفَّ لا يُرحَّل منه شيء: الترحيل من أرقام قد تتغيّر يجعل
  /// رصيد هذا الشهر يتبدّل من تلقاء نفسه كلما عُدّل ما قبله.
  Future<({double entitled, double stock})> _openingOf(
    String campId,
    String itemId,
    int year,
    int month,
  ) async {
    final prevYear = month == 1 ? year - 1 : year;
    final prevMonth = month == 1 ? 12 : month - 1;
    final prev = await _find(campId, itemId, prevYear, prevMonth);
    if (prev == null || prev.status != 'CLOSED') return (entitled: 0.0, stock: 0.0);
    final a = _amountsOf(prev);
    return (entitled: a.entitlementBalance, stock: a.stockBalance);
  }

  // ───────────────────────── تصفية الشهر

  Future<SettlementResult> closeMonth({
    required int year,
    required int month,
    String actor = '',
    String notes = '',
  }) async {
    final today = DateTime.now();
    final endOfMonth = DateTime(year, month + 1, 0);
    if (endOfMonth.isAfter(DateTime(today.year, today.month, today.day))) {
      return const SettlementResult(
        ok: false,
        error: '✖ لا يُصفّى شهر لم ينتهِ بعد',
      );
    }
    final already = await (db.select(db.monthlySettlements)
          ..where((t) => t.year.equals(year) & t.month.equals(month)))
        .get();
    if (already.isNotEmpty) {
      return const SettlementResult(ok: false, error: '✖ هذا الشهر مُصفّى سلفًا');
    }

    // إعادة بناء قبل الإغلاق: التصفية تُثبّت الأرقام، فلتُثبّت أحدثها.
    await rebuild(year: year, month: month, actor: actor);

    final rows = await ledgers(year: year, month: month, status: 'OPEN');
    if (rows.isEmpty) {
      return SettlementResult(ok: false, error: '✖ لا سجلات مفتوحة لشهر $month/$year');
    }

    final camps = <String>{};
    final items = <String>{};
    var credit = 0.0;
    var debit = 0.0;
    final nextYear = month == 12 ? year + 1 : year;
    final nextMonth = month == 12 ? 1 : month + 1;

    await db.transaction(() async {
      for (final r in rows) {
        camps.add(r.ledger.campId);
        items.add(r.ledger.itemId);
        final b = r.amounts.entitlementBalance;
        if (b > CampLedgerCalc.epsilon) {
          credit += b;
        } else if (b < -CampLedgerCalc.epsilon) {
          debit += -b;
        }

        await (db.update(db.campLedgers)..where((t) => t.id.equals(r.ledger.id))).write(
          CampLedgersCompanion(
            status: const Value('CLOSED'),
            closedBy: Value(actor),
            closedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        // فتح الشهر التالي بالرصيدين المُرحَّلين.
        final next = await _find(r.ledger.campId, r.ledger.itemId, nextYear, nextMonth);
        await db.into(db.campLedgers).insertOnConflictUpdate(CampLedgersCompanion.insert(
              id: next?.id ?? Ids.next('cld'),
              campId: r.ledger.campId,
              campName: Value(r.ledger.campName),
              itemId: r.ledger.itemId,
              itemName: Value(r.ledger.itemName),
              unitName: Value(r.ledger.unitName),
              year: nextYear,
              month: nextMonth,
              openingEntitled: Value(r.amounts.entitlementBalance),
              openingStock: Value(r.amounts.stockBalance),
              entitlementTotal: Value(next?.entitlementTotal ?? 0),
              transferredIn: Value(next?.transferredIn ?? 0),
              issuedDirect: Value(next?.issuedDirect ?? 0),
              returnedQty: Value(next?.returnedQty ?? 0),
              consumedKitchen: Value(next?.consumedKitchen ?? 0),
              updatedAt: Value(DateTime.now()),
            ));
      }

      await db.into(db.monthlySettlements).insert(MonthlySettlementsCompanion.insert(
            id: Ids.next('stl'),
            year: year,
            month: month,
            settledBy: Value(actor),
            notes: Value(notes),
            campsCount: Value(camps.length),
            itemsCount: Value(items.length),
            totalCredit: Value(CampLedgerCalc.round(credit)),
            totalDebit: Value(CampLedgerCalc.round(debit)),
          ));
    });

    await AuditRepo(db).log(
      action: 'campLedger.settle',
      entityType: 'تصفية شهر',
      summary: 'تصفية $month/$year — ${camps.length} معسكرًا و${items.length} صنفًا',
      details: {
        'year': year,
        'month': month,
        'camps': camps.length,
        'items': items.length,
        'credit': credit,
        'debit': debit,
      },
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );

    return SettlementResult(
      ok: true,
      camps: camps.length,
      items: items.length,
      nextYear: nextYear,
      nextMonth: nextMonth,
    );
  }

  static const String _settingsKey = 'campLedger';

  /// هل التصفية التلقائية مفعّلة؟ **مطفأة افتراضيًا**: التصفية لا رجعة فيها،
  /// وإجراءٌ لا يُلغى لا يعمل بلا إذن صريح.
  Future<bool> isAutoSettle() async =>
      (await SettingsRepo(db).read(_settingsKey))['autoSettle'] == true;

  Future<void> setAutoSettle(bool on) async {
    final settings = SettingsRepo(db);
    final map = await settings.read(_settingsKey)..['autoSettle'] = on;
    await settings.write(_settingsKey, map);
  }

  /// تُستدعى عند إقلاع التطبيق: تصفّي الشهر المنقضي إن أُذن بذلك.
  ///
  /// تشترط أن يكون الشهر قد **انتهى بالكامل** وأن يوجد له سجل مفتوح، ولا
  /// تصفّي أكثر من شهر واحد في النداء: تراكم شهور لم تُصفَّ حالةٌ تستحق نظر
  /// المدير لا معالجةً صامتة.
  Future<SettlementResult> autoSettleIfDue({String actor = 'تلقائي'}) async {
    if (!await isAutoSettle()) {
      return const SettlementResult(ok: false, error: 'التصفية التلقائية مطفأة');
    }
    final now = DateTime.now();
    final year = now.month == 1 ? now.year - 1 : now.year;
    final month = now.month == 1 ? 12 : now.month - 1;

    final done = await settlements();
    if (done.any((s) => s.year == year && s.month == month)) {
      return const SettlementResult(ok: false, error: 'الشهر المنقضي مُصفّى سلفًا');
    }
    final open = await ledgers(year: year, month: month, status: 'OPEN');
    if (open.isEmpty) {
      return const SettlementResult(ok: false, error: 'لا سجلات مفتوحة للشهر المنقضي');
    }
    return closeMonth(year: year, month: month, actor: actor, notes: 'تصفية تلقائية');
  }

  Future<List<MonthlySettlement>> settlements() =>
      (db.select(db.monthlySettlements)
            ..orderBy([(t) => OrderingTerm.desc(t.settledAt)]))
          .get();

  // ───────────────────────── حدود المخزون والتنبيه

  Future<List<CampStockLimit>> limits({String campId = ''}) async {
    final q = db.select(db.campStockLimits);
    if (campId.isNotEmpty) q.where((t) => t.campId.equals(campId));
    final rows = await q.get();
    rows.sort((a, b) => a.itemName.compareTo(b.itemName));
    return rows;
  }

  Future<void> saveLimit({
    required String campId,
    required String campName,
    required String itemId,
    required String itemName,
    required double minStock,
    required double maxStock,
    int alertDaysBefore = 2,
  }) async {
    final rows = await (db.select(db.campStockLimits)
          ..where((t) => t.campId.equals(campId) & t.itemId.equals(itemId)))
        .get();
    await db.into(db.campStockLimits).insertOnConflictUpdate(
          CampStockLimitsCompanion.insert(
            id: rows.isEmpty ? Ids.next('lim') : rows.first.id,
            campId: campId,
            campName: Value(campName),
            itemId: itemId,
            itemName: Value(itemName),
            minStock: Value(minStock),
            maxStock: Value(maxStock),
            alertDaysBefore: Value(alertDaysBefore),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> deleteLimit(String id) =>
      (db.delete(db.campStockLimits)..where((t) => t.id.equals(id))).go();

  /// تنبيهات مخزون المعسكرات الآن.
  ///
  /// المخزون من سجل الشهر الجاري، ومعدل الاستهلاك من سجل الطهي في آخر أسبوع.
  Future<List<StockAlert>> alerts({String campId = ''}) async {
    final now = DateTime.now();
    final rows = await ledgers(year: now.year, month: now.month, campId: campId);
    if (rows.isEmpty) return const [];

    final defs = await limits(campId: campId);
    if (defs.isEmpty) return const [];

    final window = DateSpan(
      DateSpan.ymd(now.subtract(const Duration(days: StockAlertEngine.defaultWindowDays))),
      DateSpan.ymd(now),
    );
    final units = await CatalogRepo(db).units();
    final camps = await CatalogRepo(db).camps();
    final facilities = await db.select(db.facilities).get();
    final logs = (await db.select(db.kitchenLogs).get())
        .where((l) => window.contains(l.date))
        .toList();

    final out = <StockAlert>[];
    for (final def in defs) {
      final row = rows
          .where((r) => r.ledger.campId == def.campId && r.ledger.itemId == def.itemId)
          .firstOrNull;
      if (row == null) continue;

      final camp = camps.where((c) => c.id == def.campId).firstOrNull;
      final facilityIds = camp == null
          ? <String>{}
          : _facilitiesOf(camp, units, _membersOf(camp, units), facilities);
      final rate = StockAlertEngine.dailyConsumption([
        for (final l in logs)
          if (l.itemId == def.itemId && facilityIds.contains(l.facilityId))
            (date: l.date, baseQty: l.baseQty),
      ]);

      out.add(StockAlert(
        campId: def.campId,
        campName: def.campName.isEmpty ? (camp?.name ?? '') : def.campName,
        itemId: def.itemId,
        itemName: def.itemName.isEmpty ? row.ledger.itemName : def.itemName,
        unitName: row.ledger.unitName,
        current: row.amounts.stockBalance,
        minStock: def.minStock,
        maxStock: def.maxStock,
        dailyConsumption: rate,
        alertDaysBefore: def.alertDaysBefore,
      ));
    }
    return StockAlertEngine.sorted(out);
  }

  // ───────────────────────── الانحراف اليومي

  /// سلسلة انحراف صنف في معسكر خلال شهر — تُحسب ولا تُحفظ.
  Future<List<VarianceDay>> variance({
    required String campId,
    required String itemId,
    required int year,
    required int month,
  }) async {
    final scale = await (db.select(db.entitlements)..where((t) => t.itemId.equals(itemId)))
        .getSingleOrNull();
    if (scale == null) return const [];

    final span = monthSpan(year, month);
    final units = await CatalogRepo(db).units();
    final camps = await CatalogRepo(db).camps();
    final camp = camps.where((c) => c.id == campId).firstOrNull;
    if (camp == null) return const [];

    final strengths = (await db.select(db.strengths).get())
        .where((s) => span.contains(s.strengthDate))
        .toList();

    return VarianceTracker.series(
      strengthByDay: _strengthByDay(strengths, campId, _membersOf(camp, units)),
      monthlyQtyPerPerson: scale.qtyPerPerson,
      measureFactor: scale.measureFactor,
    );
  }
}
