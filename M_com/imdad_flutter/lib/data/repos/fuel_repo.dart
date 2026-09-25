import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/fuel.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import 'doc_numbering.dart';

class FuelResult {
  const FuelResult({required this.ok, this.error = '', this.refNo = ''});

  final bool ok;
  final String error;
  final String refNo;
}

/// تفريدة مع حساب استحقاقها ومصروفها.
class FuelAllocationRow {
  const FuelAllocationRow({
    required this.allocation,
    required this.issued,
    required this.asOf,
  });

  final FuelAllocation allocation;

  /// ما صُرف على هذه التفريدة فعلًا.
  final double issued;
  final DateTime asOf;

  FuelAllocationCalc get calc => FuelAllocationCalc(
        periodType: allocation.periodType,
        quantityPerPeriod: allocation.quantityPerPeriod,
        totalQuantity: allocation.totalQuantity,
        startDate: allocation.startDate,
        endDate: allocation.endDate,
        active: allocation.active,
        disbursable: allocation.disbursable,
        weeklyLiters: allocation.weeklyLiters,
        monthlyLiters: allocation.monthlyLiters,
      );

  double get entitled => Fuel.entitledLiters(calc, asOf);
  double get remaining =>
      Fuel.remainingLiters(allocation: calc, issued: issued, asOf: asOf);
  int get periods => Fuel.periodsElapsed(calc, asOf);
}

/// سجل مركبة بشاصيها: كم صرفت وكم مرة وآخر مرة.
class FuelChassisLog {
  const FuelChassisLog({
    required this.chassisNo,
    required this.vehicleType,
    required this.lastDriver,
    required this.lastDate,
    required this.count,
    required this.liters,
  });

  final String chassisNo;
  final String vehicleType;
  final String lastDriver;
  final String lastDate;
  final int count;
  final double liters;
}

/// قسم المحروقات: التفريدة والصرف والتوريد والتحويل والجرد.
///
/// **الرصيد محسوبٌ لا مخزَّن.** لا عمود يحمل «رصيد المستودع»: يُجمع من سنداته
/// في كل قراءة، كما يفعل دفتر حركات الإعاشة. ورقمٌ مخزَّن يفترق عن سنداته عند
/// أول تعديلٍ أو حذفٍ أو مزامنةٍ تصل متأخرة، ثم لا يُعرف أيّهما الصادق.
class FuelRepo {
  FuelRepo(this.db);

  final AppDatabase db;

  // ───────────────────────── الأدلة

  Future<List<FuelWarehouse>> warehouses({bool onlyActive = false}) async {
    final q = db.select(db.fuelWarehouses);
    if (onlyActive) q.where((t) => t.active.equals(true));
    final rows = await q.get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<FuelResult> saveWarehouse({
    String? id,
    required String name,
    String code = '',
    String manager = '',
    String location = '',
    double capacityLiters = 0,
    bool active = true,
    String notes = '',
    String actor = '',
  }) async {
    if (name.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اسم المستودع مطلوب');
    }
    if (capacityLiters < 0) {
      return const FuelResult(ok: false, error: '✖ السعة لا تكون سالبة');
    }
    final all = await warehouses();
    if (all.any((w) => w.id != id && w.name.trim() == name.trim())) {
      return const FuelResult(ok: false, error: '✖ يوجد مستودع بهذا الاسم');
    }
    // السندات تشير إلى **الاسم**، فتغييره على مستودعٍ له حركة يقطع صلته بها.
    if (id != null) {
      final old = all.where((w) => w.id == id).firstOrNull;
      if (old != null && old.name.trim() != name.trim()) {
        final used = await _warehouseInUse(old.name);
        if (used) {
          return FuelResult(
            ok: false,
            error: '✖ لا يُغيَّر اسم «${old.name}» وعليه حركة — '
                'عطّله وأنشئ غيره',
          );
        }
      }
    }
    final newId = id ?? Ids.next('fwh');
    await db
        .into(db.fuelWarehouses)
        .insertOnConflictUpdate(FuelWarehousesCompanion.insert(
          id: newId,
          code: Value(code.trim()),
          name: name.trim(),
          manager: Value(manager.trim()),
          location: Value(location.trim()),
          capacityLiters: Value(capacityLiters),
          active: Value(active),
          notes: Value(notes.trim()),
        ));
    await AuditRepo(db).log(
      action: id == null ? 'fuel.warehouse.create' : 'fuel.warehouse.update',
      entityType: 'مستودع محروقات',
      summary: '${id == null ? 'إضافة' : 'تعديل'} مستودع «${name.trim()}»',
      details: {'warehouseId': newId},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: newId);
  }

  Future<bool> _warehouseInUse(String name) async {
    final row = await db.customSelect(
      'SELECT 1 AS x FROM fuel_issues WHERE warehouse = ?1 '
      'UNION ALL SELECT 1 FROM fuel_supplies WHERE warehouse = ?1 '
      'UNION ALL SELECT 1 FROM fuel_openings WHERE warehouse = ?1 '
      'UNION ALL SELECT 1 FROM fuel_transfers WHERE from_warehouse = ?1 '
      'OR to_warehouse = ?1 '
      'UNION ALL SELECT 1 FROM fuel_stocktakes WHERE warehouse = ?1 LIMIT 1',
      variables: [Variable<String>(name)],
    ).getSingleOrNull();
    return row != null;
  }

  Future<FuelResult> deleteWarehouse(String id, {String actor = ''}) async {
    final row = await (db.select(db.fuelWarehouses)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return const FuelResult(ok: false, error: '✖ المستودع غير موجود');
    }
    if (await _warehouseInUse(row.name)) {
      return const FuelResult(
        ok: false,
        error: '✖ لا يُحذف مستودع عليه حركة — عطّله بدل حذفه',
      );
    }
    await (db.delete(db.fuelWarehouses)..where((t) => t.id.equals(id))).go();
    await AuditRepo(db).log(
      action: 'fuel.warehouse.delete',
      entityType: 'مستودع محروقات',
      summary: 'حذف مستودع محروقات «${row.name}»',
      details: {'warehouseId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const FuelResult(ok: true);
  }

  Future<List<FuelUnit>> units({bool onlyActive = false}) async {
    final q = db.select(db.fuelUnits);
    if (onlyActive) q.where((t) => t.active.equals(true));
    final rows = await q.get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<FuelResult> saveUnit({
    String? id,
    required String name,
    String code = '',
    String commander = '',
    String phone = '',
    bool active = true,
    String notes = '',
    String actor = '',
  }) async {
    if (name.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اسم الوحدة مطلوب');
    }
    final all = await units();
    if (all.any((u) => u.id != id && u.name.trim() == name.trim())) {
      return const FuelResult(ok: false, error: '✖ توجد وحدة بهذا الاسم');
    }
    final newId = id ?? Ids.next('fun');
    await db.into(db.fuelUnits).insertOnConflictUpdate(FuelUnitsCompanion.insert(
          id: newId,
          code: Value(code.trim()),
          name: name.trim(),
          commander: Value(commander.trim()),
          phone: Value(phone.trim()),
          active: Value(active),
          notes: Value(notes.trim()),
        ));
    await AuditRepo(db).log(
      action: id == null ? 'fuel.unit.create' : 'fuel.unit.update',
      entityType: 'وحدة محروقات',
      summary: '${id == null ? 'إضافة' : 'تعديل'} وحدة «${name.trim()}»',
      details: {'unitId': newId},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: newId);
  }

  Future<FuelResult> deleteUnit(String id, {String actor = ''}) async {
    final used = await (db.select(db.fuelAllocations)
          ..where((t) => t.unitId.equals(id))
          ..limit(1))
        .get();
    if (used.isNotEmpty) {
      return const FuelResult(
        ok: false,
        error: '✖ لا تُحذف وحدة لها تفريدة — عطّلها بدل حذفها',
      );
    }
    await (db.delete(db.fuelUnits)..where((t) => t.id.equals(id))).go();
    await AuditRepo(db).log(
      action: 'fuel.unit.delete',
      entityType: 'وحدة محروقات',
      summary: 'حذف وحدة محروقات',
      details: {'unitId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const FuelResult(ok: true);
  }

  // ───────────────────────── الإعدادات

  static const String settingsId = 'fuel-settings';

  /// إعدادات القسم — تُنشأ بقيمها الافتراضية عند أول قراءة.
  Future<FuelSettingsRow> settings() async {
    final row = await (db.select(db.fuelSettingsRows)
          ..where((t) => t.id.equals(settingsId)))
        .getSingleOrNull();
    if (row != null) return row;
    await db
        .into(db.fuelSettingsRows)
        .insertOnConflictUpdate(
            FuelSettingsRowsCompanion.insert(id: settingsId));
    return (db.select(db.fuelSettingsRows)
          ..where((t) => t.id.equals(settingsId)))
        .getSingle();
  }

  Future<FuelResult> saveSettings({
    required double lowStockPercent,
    required double defaultDailyLiters,
    required double defaultWeeklyLiters,
    required double defaultMonthlyLiters,
    String signOfficer = '',
    String signSupply = '',
    String signChief = '',
    bool requireChassis = false,
    bool allowExceptional = true,
    String notes = '',
    String actor = '',
  }) async {
    if (lowStockPercent < 0 || lowStockPercent > 100) {
      return const FuelResult(
          ok: false, error: '✖ حد التنبيه نسبة بين صفر ومئة');
    }
    await settings();
    await (db.update(db.fuelSettingsRows)
          ..where((t) => t.id.equals(settingsId)))
        .write(FuelSettingsRowsCompanion(
      lowStockPercent: Value(lowStockPercent),
      defaultDailyLiters: Value(defaultDailyLiters),
      defaultWeeklyLiters: Value(defaultWeeklyLiters),
      defaultMonthlyLiters: Value(defaultMonthlyLiters),
      signOfficer: Value(signOfficer.trim()),
      signSupply: Value(signSupply.trim()),
      signChief: Value(signChief.trim()),
      requireChassis: Value(requireChassis),
      allowExceptional: Value(allowExceptional),
      notes: Value(notes.trim()),
      updatedAt: Value(DateTime.now()),
    ));
    await AuditRepo(db).log(
      action: 'fuel.settings.update',
      entityType: 'إعدادات محروقات',
      summary: 'تعديل إعدادات قسم المحروقات',
      details: {'lowStockPercent': lowStockPercent},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const FuelResult(ok: true);
  }

  // ───────────────────────── الرصيد

  /// مكوّنات رصيد كل نوعٍ في كل مستودع.
  ///
  /// [upTo] يحصر الحساب بتاريخٍ فأقل — به يُقرأ الرصيد الدفتري وقت فتح الجرد
  /// لا رصيد اليوم.
  Future<List<FuelStock>> stocks({String warehouse = '', String upTo = ''}) async {
    final warehouses = await this.warehouses();
    final wanted = warehouse.trim();
    final list = wanted.isEmpty
        ? warehouses
        : warehouses.where((w) => w.name == wanted).toList();
    if (list.isEmpty) return const [];

    bool within(String date) => upTo.isEmpty || date.compareTo(upTo) <= 0;

    final openings = await db.select(db.fuelOpenings).get();
    final supplies = await db.select(db.fuelSupplies).get();
    final issues = await db.select(db.fuelIssues).get();
    final transfers = await db.select(db.fuelTransfers).get();
    // الجرد المرحَّل وحده يمسّ الرصيد: أرقام مرحلة العدّ لم تُراجع بعد.
    final posted = await (db.select(db.fuelStocktakes)
          ..where((t) => t.status.equals(FuelStocktakeStatus.posted)))
        .get();
    final postedIds = {for (final s in posted) s.id: s};
    final lines = postedIds.isEmpty
        ? const <FuelStocktakeLine>[]
        : await (db.select(db.fuelStocktakeLines)
              ..where((t) => t.stocktakeId.isIn(postedIds.keys.toList())))
            .get();

    final out = <FuelStock>[];
    for (final w in list) {
      for (final type in FuelType.all) {
        var opening = 0.0, supplied = 0.0, issued = 0.0;
        var inn = 0.0, outQty = 0.0, adjustments = 0.0;

        for (final o in openings) {
          if (o.warehouse == w.name && o.fuelType == type && within(o.asOfDate)) {
            opening += o.liters;
          }
        }
        for (final s in supplies) {
          if (s.warehouse == w.name && s.fuelType == type && within(s.date)) {
            supplied += s.quantityLiters;
          }
        }
        for (final i in issues) {
          if (i.warehouse == w.name && i.fuelType == type && within(i.date)) {
            issued += i.quantityLiters;
          }
        }
        for (final t in transfers) {
          if (t.fuelType != type || !within(t.date)) continue;
          if (t.toWarehouse == w.name) inn += t.quantityLiters;
          if (t.fromWarehouse == w.name) outQty += t.quantityLiters;
        }
        for (final l in lines) {
          final head = postedIds[l.stocktakeId];
          if (head == null || head.warehouse != w.name) continue;
          if (l.fuelType != type || !l.counted || !within(head.date)) continue;
          adjustments += l.countedLiters - l.bookLiters;
        }

        out.add(FuelStock(
          warehouse: w.name,
          fuelType: type,
          opening: opening,
          supplied: supplied,
          issued: issued,
          transferredIn: inn,
          transferredOut: outQty,
          adjustments: adjustments,
          capacityLiters: w.capacityLiters,
        ));
      }
    }
    return out;
  }

  Future<double> available(String warehouse, String fuelType) async {
    final rows = await stocks(warehouse: warehouse);
    final match = rows.where((r) => r.fuelType == fuelType).firstOrNull;
    return match?.stock ?? 0;
  }

  // ───────────────────────── التفريدة

  Future<List<FuelAllocationRow>> allocations({
    String unitId = '',
    bool onlyActive = false,
    DateTime? asOf,
  }) async {
    final q = db.select(db.fuelAllocations);
    if (unitId.isNotEmpty) q.where((t) => t.unitId.equals(unitId));
    if (onlyActive) q.where((t) => t.active.equals(true));
    final rows = await q.get();
    if (rows.isEmpty) return const [];

    final issues = await db.select(db.fuelIssues).get();
    final issued = <String, double>{};
    for (final i in issues) {
      if (i.allocationId.isEmpty) continue;
      issued.update(i.allocationId, (v) => v + i.quantityLiters,
          ifAbsent: () => i.quantityLiters);
    }
    final now = asOf ?? DateTime.now();
    final out = [
      for (final a in rows)
        FuelAllocationRow(
          allocation: a,
          issued: issued[a.id] ?? 0,
          asOf: now,
        ),
    ];
    out.sort((a, b) => a.allocation.unitName.compareTo(b.allocation.unitName));
    return out;
  }

  Future<FuelResult> saveAllocation({
    String? id,
    required String unitId,
    required String unitName,
    required String fuelType,
    required String periodType,
    required double quantityPerPeriod,
    String code = '',
    double totalQuantity = 0,
    double weeklyLiters = 0,
    double monthlyLiters = 0,
    String issueLocation = '',
    String startDate = '',
    String endDate = '',
    bool active = true,
    bool disbursable = true,
    String notes = '',
    String actor = '',
  }) async {
    if (unitId.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اختر الوحدة المستفيدة');
    }
    if (startDate.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ تاريخ بداية التفريدة مطلوب');
    }
    if (periodType == FuelPeriod.custom) {
      if (totalQuantity <= 0) {
        return const FuelResult(
            ok: false, error: '✖ إجمالي الفترة المحددة أكبر من صفر');
      }
    } else if (quantityPerPeriod <= 0) {
      return const FuelResult(ok: false, error: '✖ كمية الفترة أكبر من صفر');
    }
    if (endDate.trim().isNotEmpty &&
        endDate.trim().compareTo(startDate.trim()) < 0) {
      return const FuelResult(ok: false, error: '✖ النهاية قبل البداية');
    }

    final newId = id ?? Ids.next('fal');
    final ref = code.trim().isNotEmpty
        ? code.trim()
        : (id == null ? await DocNumbering(db).peek('fuel_allocations', 'تف-') : code);
    await db
        .into(db.fuelAllocations)
        .insertOnConflictUpdate(FuelAllocationsCompanion.insert(
          id: newId,
          refNo: Value(ref),
          unitId: Value(unitId),
          unitName: Value(unitName),
          fuelType: Value(fuelType),
          periodType: Value(periodType),
          quantityPerPeriod: Value(quantityPerPeriod),
          totalQuantity: Value(totalQuantity),
          weeklyLiters: Value(weeklyLiters),
          monthlyLiters: Value(monthlyLiters),
          issueLocation: Value(issueLocation),
          startDate: Value(startDate),
          endDate: Value(endDate),
          active: Value(active),
          disbursable: Value(disbursable),
          notes: Value(notes),
          createdBy: Value(actor),
          updatedAt: Value(id == null ? null : DateTime.now()),
        ));
    if (id == null) await DocNumbering(db).claim('fuel_allocations', 'تف-', ref);
    await AuditRepo(db).log(
      action: id == null ? 'fuel.allocation.create' : 'fuel.allocation.update',
      entityType: 'تفريدة محروقات',
      summary: '${id == null ? 'إنشاء' : 'تعديل'} تفريدة «$unitName» ($ref)',
      details: {'allocationId': newId, 'fuelType': fuelType},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: ref);
  }

  /// التفريدة التي صُرف عليها لا تُحذف: حذفها يترك سنداتها بلا مرجع.
  Future<FuelResult> deleteAllocation(String id, {String actor = ''}) async {
    final used = await (db.select(db.fuelIssues)
          ..where((t) => t.allocationId.equals(id))
          ..limit(1))
        .get();
    if (used.isNotEmpty) {
      return const FuelResult(
        ok: false,
        error: '✖ لا تُحذف تفريدة صُرف عليها — أوقفها بدل حذفها',
      );
    }
    await (db.delete(db.fuelAllocations)..where((t) => t.id.equals(id))).go();
    await AuditRepo(db).log(
      action: 'fuel.allocation.delete',
      entityType: 'تفريدة محروقات',
      summary: 'حذف تفريدة محروقات',
      details: {'allocationId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const FuelResult(ok: true);
  }

  // ───────────────────────── الصرف

  Future<List<FuelIssue>> issues({String from = '', String to = ''}) async {
    final q = db.select(db.fuelIssues);
    if (from.isNotEmpty) q.where((t) => t.date.isBiggerOrEqualValue(from));
    if (to.isNotEmpty) q.where((t) => t.date.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  /// صرف محروقات — يُخصم من التفريدة إن كان منها، ومن رصيد المستودع دائمًا.
  Future<FuelResult> saveIssue({
    required String date,
    required String fuelType,
    required String warehouse,
    required double quantityLiters,
    String source = FuelSource.allocation,
    String allocationId = '',
    String beneficiaryUnitId = '',
    String beneficiaryName = '',
    String driverName = '',
    String vehicleType = '',
    String chassisNo = '',
    String justification = '',
    String orderAuthority = '',
    String purpose = '',
    String notes = '',
    String actor = '',
  }) async {
    final qtyError = Fuel.validateQty(quantityLiters);
    if (qtyError != null) return FuelResult(ok: false, error: '✖ $qtyError');
    if (warehouse.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اختر المستودع');
    }
    if (date.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ التاريخ مطلوب');
    }

    final stock = await available(warehouse, fuelType);
    if (quantityLiters > stock + 1e-9) {
      return FuelResult(
        ok: false,
        error: '✖ رصيد «$warehouse» من ${FuelType.label(fuelType)} '
            '${Fuel.round(stock)} ${Fuel.unit} فقط',
      );
    }

    final conf = await settings();
    if (conf.requireChassis && chassisNo.trim().isEmpty) {
      return const FuelResult(
          ok: false, error: '✖ رقم الشاصي مطلوب — اضبطه من إعدادات المحروقات');
    }
    if (source == FuelSource.exceptional && !conf.allowExceptional) {
      return const FuelResult(
          ok: false, error: '✖ الصرف الاستثنائي معطَّل في إعدادات المحروقات');
    }

    var entitled = 0.0;
    var periodType = '';
    if (source == FuelSource.allocation) {
      if (allocationId.trim().isEmpty) {
        return const FuelResult(ok: false, error: '✖ اختر التفريدة');
      }
      final rows = await allocations();
      final row = rows.where((r) => r.allocation.id == allocationId).firstOrNull;
      if (row == null) {
        return const FuelResult(ok: false, error: '✖ التفريدة غير موجودة');
      }
      final block = Fuel.issueBlock(
        allocation: row.calc,
        date: date,
        qty: quantityLiters,
        alreadyIssued: row.issued,
      );
      if (block != null) return FuelResult(ok: false, error: '✖ $block');
      entitled = row.entitled;
      periodType = row.allocation.periodType;
      beneficiaryUnitId = beneficiaryUnitId.isEmpty
          ? row.allocation.unitId
          : beneficiaryUnitId;
      beneficiaryName =
          beneficiaryName.isEmpty ? row.allocation.unitName : beneficiaryName;
    } else {
      // الاستثنائي خارج كل تفريدة، فلا يُجاز إلا بمبرر وجهةِ أمرٍ مسمّاة.
      if (justification.trim().isEmpty) {
        return const FuelResult(
            ok: false, error: '✖ الأمر الاستثنائي يلزمه مبرر');
      }
      if (orderAuthority.trim().isEmpty) {
        return const FuelResult(ok: false, error: '✖ اذكر جهة الأمر');
      }
    }

    final numbering = DocNumbering(db);
    final docNo = await numbering.peek('fuel_issues', 'مح-');
    final id = Ids.next('fis');
    await db.into(db.fuelIssues).insert(FuelIssuesCompanion.insert(
          id: id,
          refNo: Value(docNo),
          date: Value(date),
          fuelType: Value(fuelType),
          warehouse: Value(warehouse),
          source: Value(source),
          quantityLiters: Value(quantityLiters),
          driverName: Value(driverName),
          vehicleType: Value(vehicleType),
          chassisNo: Value(chassisNo.trim()),
          allocationId: Value(source == FuelSource.allocation ? allocationId : ''),
          beneficiaryUnitId: Value(beneficiaryUnitId),
          beneficiaryName: Value(beneficiaryName),
          entitledLiters: Value(entitled),
          periodType: Value(periodType),
          justification: Value(justification),
          orderAuthority: Value(orderAuthority),
          purpose: Value(purpose),
          notes: Value(notes),
          createdBy: Value(actor),
        ));
    await numbering.claim('fuel_issues', 'مح-', docNo);
    await AuditRepo(db).log(
      action: 'fuel.issue',
      entityType: 'صرف محروقات',
      summary: 'صرف ${Fuel.round(quantityLiters)} ${Fuel.unit} '
          '${FuelType.label(fuelType)} لـ«$beneficiaryName» ($docNo)',
      details: {
        'issueId': id,
        'docNo': docNo,
        'warehouse': warehouse,
        'source': source,
        'chassisNo': chassisNo.trim(),
      },
      risk: source == FuelSource.exceptional
          ? AuditRepo.riskHigh
          : AuditRepo.riskNormal,
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: docNo);
  }

  // ───────────────────────── التوريد

  Future<List<FuelSupply>> supplies() async {
    final rows = await (db.select(db.fuelSupplies)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
    return rows;
  }

  Future<FuelResult> saveSupply({
    required String date,
    required String fuelType,
    required String warehouse,
    required double quantityLiters,
    String supplierName = '',
    String transportVehicleType = '',
    String driverName = '',
    String notes = '',
    String actor = '',
  }) async {
    final qtyError = Fuel.validateQty(quantityLiters);
    if (qtyError != null) return FuelResult(ok: false, error: '✖ $qtyError');
    if (warehouse.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اختر المستودع');
    }
    final numbering = DocNumbering(db);
    final docNo = await numbering.peek('fuel_supplies', 'تو-');
    await db.into(db.fuelSupplies).insert(FuelSuppliesCompanion.insert(
          id: Ids.next('fsu'),
          refNo: Value(docNo),
          date: Value(date),
          fuelType: Value(fuelType),
          quantityLiters: Value(quantityLiters),
          supplierName: Value(supplierName),
          warehouse: Value(warehouse),
          transportVehicleType: Value(transportVehicleType),
          driverName: Value(driverName),
          notes: Value(notes),
          createdBy: Value(actor),
        ));
    await numbering.claim('fuel_supplies', 'تو-', docNo);
    await AuditRepo(db).log(
      action: 'fuel.supply',
      entityType: 'توريد محروقات',
      summary: 'توريد ${Fuel.round(quantityLiters)} ${Fuel.unit} '
          '${FuelType.label(fuelType)} إلى «$warehouse» ($docNo)',
      details: {'docNo': docNo, 'supplier': supplierName},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: docNo);
  }

  // ───────────────────────── التحويل

  Future<List<FuelTransfer>> transfers() => (db.select(db.fuelTransfers)
        ..orderBy([(t) => OrderingTerm.desc(t.date)]))
      .get();

  Future<FuelResult> saveTransfer({
    required String date,
    required String fuelType,
    required String fromWarehouse,
    required String toWarehouse,
    required double quantityLiters,
    String driverName = '',
    String transportVehicleType = '',
    String notes = '',
    String actor = '',
  }) async {
    final stock = await available(fromWarehouse, fuelType);
    final error = Fuel.validateTransfer(
      from: fromWarehouse,
      to: toWarehouse,
      qty: quantityLiters,
      available: stock,
    );
    if (error != null) return FuelResult(ok: false, error: '✖ $error');

    final numbering = DocNumbering(db);
    final docNo = await numbering.peek('fuel_transfers', 'حت-');
    await db.into(db.fuelTransfers).insert(FuelTransfersCompanion.insert(
          id: Ids.next('ftr'),
          refNo: Value(docNo),
          date: Value(date),
          fuelType: Value(fuelType),
          quantityLiters: Value(quantityLiters),
          fromWarehouse: Value(fromWarehouse),
          toWarehouse: Value(toWarehouse),
          driverName: Value(driverName),
          transportVehicleType: Value(transportVehicleType),
          notes: Value(notes),
          createdBy: Value(actor),
        ));
    await numbering.claim('fuel_transfers', 'حت-', docNo);
    await AuditRepo(db).log(
      action: 'fuel.transfer',
      entityType: 'تحويل محروقات',
      summary: 'تحويل ${Fuel.round(quantityLiters)} ${Fuel.unit} من '
          '«$fromWarehouse» إلى «$toWarehouse» ($docNo)',
      details: {'docNo': docNo, 'fuelType': fuelType},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: docNo);
  }

  // ───────────────────────── الرصيد الافتتاحي

  Future<List<FuelOpening>> openings() => db.select(db.fuelOpenings).get();

  Future<FuelResult> saveOpening({
    String? id,
    required String warehouse,
    required String fuelType,
    required double liters,
    String asOfDate = '',
    String note = '',
    String actor = '',
  }) async {
    if (warehouse.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اختر المستودع');
    }
    if (liters < 0) {
      return const FuelResult(ok: false, error: '✖ الرصيد لا يكون سالبًا');
    }
    await db
        .into(db.fuelOpenings)
        .insertOnConflictUpdate(FuelOpeningsCompanion.insert(
          id: id ?? Ids.next('fop'),
          warehouse: Value(warehouse),
          fuelType: Value(fuelType),
          liters: Value(liters),
          asOfDate: Value(asOfDate),
          note: Value(note),
        ));
    await AuditRepo(db).log(
      action: 'fuel.opening',
      entityType: 'رصيد محروقات افتتاحي',
      summary: 'ضبط رصيد افتتاحي ${Fuel.round(liters)} ${Fuel.unit} '
          '${FuelType.label(fuelType)} في «$warehouse»',
      details: {'warehouse': warehouse, 'fuelType': fuelType},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const FuelResult(ok: true);
  }

  Future<void> deleteOpening(String id) =>
      (db.delete(db.fuelOpenings)..where((t) => t.id.equals(id))).go();

  // ───────────────────────── الجرد

  Future<List<FuelStocktake>> stocktakes() => (db.select(db.fuelStocktakes)
        ..orderBy([(t) => OrderingTerm.desc(t.date)]))
      .get();

  Future<List<FuelStocktakeLine>> stocktakeLines(String id) =>
      (db.select(db.fuelStocktakeLines)
            ..where((t) => t.stocktakeId.equals(id)))
          .get();

  /// فتح أمر جرد — يلتقط الرصيد الدفتري وقت الفتح.
  ///
  /// يُلتقط **الآن** لا عند الترحيل: الفارق بين المعدود والدفتري هو ما يُسأل
  /// عنه، ولو قُرئ الدفتري لحظة الترحيل لابتلع كلَّ حركةٍ وقعت أثناء العدّ.
  Future<FuelResult> openStocktake({
    required String date,
    required String warehouse,
    String kind = 'full',
    String fuelFilter = 'all',
    String committee = '',
    String notes = '',
    String actor = '',
  }) async {
    if (warehouse.trim().isEmpty) {
      return const FuelResult(ok: false, error: '✖ اختر المستودع');
    }
    final rows = await stocks(warehouse: warehouse, upTo: date);
    final types = fuelFilter == 'all' ? FuelType.all : [fuelFilter];
    final numbering = DocNumbering(db);
    final docNo = await numbering.peek('fuel_stocktakes', 'جم-');
    final id = Ids.next('fst');

    await db.transaction(() async {
      await db.into(db.fuelStocktakes).insert(FuelStocktakesCompanion.insert(
            id: id,
            refNo: Value(docNo),
            date: Value(date),
            warehouse: Value(warehouse),
            kind: Value(kind),
            fuelFilter: Value(fuelFilter),
            committee: Value(committee),
            notes: Value(notes),
            createdBy: Value(actor),
          ));
      for (final type in types) {
        final book =
            rows.where((r) => r.fuelType == type).firstOrNull?.stock ?? 0;
        await db
            .into(db.fuelStocktakeLines)
            .insert(FuelStocktakeLinesCompanion.insert(
              id: Ids.next('fsl'),
              stocktakeId: id,
              fuelType: Value(type),
              bookLiters: Value(book),
            ));
      }
    });
    await numbering.claim('fuel_stocktakes', 'جم-', docNo);
    await AuditRepo(db).log(
      action: 'fuel.stocktake.open',
      entityType: 'جرد محروقات',
      summary: 'فتح جرد محروقات «$warehouse» ($docNo)',
      details: {'stocktakeId': id, 'docNo': docNo},
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: docNo);
  }

  Future<FuelResult> countLine({
    required String lineId,
    required double counted,
    String actor = '',
  }) async {
    if (counted < 0) {
      return const FuelResult(ok: false, error: '✖ المعدود لا يكون سالبًا');
    }
    await (db.update(db.fuelStocktakeLines)
          ..where((t) => t.id.equals(lineId)))
        .write(FuelStocktakeLinesCompanion(
      counted: const Value(true),
      countedLiters: Value(counted),
    ));
    return const FuelResult(ok: true);
  }

  /// نقل الجرد إلى مرحلته التالية. والترحيل هو ما يمسّ الرصيد.
  Future<FuelResult> advanceStocktake(String id, {String actor = ''}) async {
    final head = await (db.select(db.fuelStocktakes)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (head == null) {
      return const FuelResult(ok: false, error: '✖ أمر الجرد غير موجود');
    }
    final next = FuelStocktakeStatus.next(head.status);
    if (next == null) {
      return const FuelResult(ok: false, error: '✖ الجرد مرحّل — لا مرحلة بعده');
    }
    if (next == FuelStocktakeStatus.posted) {
      final lines = await stocktakeLines(id);
      if (lines.any((l) => !l.counted)) {
        return const FuelResult(
          ok: false,
          error: '✖ لا يُرحَّل جرد فيه صنف لم يُعدّ — عُدّه أو ألغِ الأمر',
        );
      }
    }
    await (db.update(db.fuelStocktakes)..where((t) => t.id.equals(id))).write(
      FuelStocktakesCompanion(
        status: Value(next),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'fuel.stocktake.$next',
      entityType: 'جرد محروقات',
      summary: 'جرد ${head.refNo}: ${FuelStocktakeStatus.label(next)}',
      details: {'stocktakeId': id, 'to': next},
      risk: next == FuelStocktakeStatus.posted
          ? AuditRepo.riskHigh
          : AuditRepo.riskNormal,
      actorEmail: actor,
    );
    return FuelResult(ok: true, refNo: head.refNo);
  }

  // ───────────────────────── سجل الشاصيات

  /// كل مركبة بشاصيها: كم صرفت وكم مرة وآخر مرة.
  Future<List<FuelChassisLog>> chassisLogs() async {
    final rows = await (db.select(db.fuelIssues)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
    final map = <String, FuelChassisLog>{};
    for (final i in rows) {
      final key = i.chassisNo.trim();
      if (key.isEmpty) continue;
      final existing = map[key];
      map[key] = existing == null
          ? FuelChassisLog(
              chassisNo: key,
              vehicleType: i.vehicleType,
              lastDriver: i.driverName,
              lastDate: i.date,
              count: 1,
              liters: i.quantityLiters,
            )
          : FuelChassisLog(
              chassisNo: key,
              vehicleType: existing.vehicleType,
              lastDriver: existing.lastDriver,
              lastDate: existing.lastDate,
              count: existing.count + 1,
              liters: existing.liters + i.quantityLiters,
            );
    }
    final out = map.values.toList()
      ..sort((a, b) => b.lastDate.compareTo(a.lastDate));
    return out;
  }

  // ───────────────────────── التنبيهات

  /// [lowPercent] يُقرأ من إعدادات القسم ما لم يُمرَّر صراحةً.
  Future<List<FuelAlert>> alerts({double? lowPercent}) async {
    final threshold = lowPercent ?? (await settings()).lowStockPercent;
    final out = FuelAlerts.forStocks(await stocks(), lowPercent: threshold);
    for (final row in await allocations(onlyActive: true)) {
      final alert = FuelAlerts.forAllocation(
        code: row.allocation.refNo.isEmpty
            ? row.allocation.unitName
            : row.allocation.refNo,
        entitled: row.entitled,
        remaining: row.remaining,
      );
      if (alert != null) out.add(alert);
    }
    return out;
  }
}
