import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute;

import '../../core/security/device_activation.dart';
import '../../domain/access_control.dart';
import '../db/app_database.dart';
import '../repos/settings_repo.dart';
import 'backup_crypto.dart';
import '../sync/sync_marks.dart';

/// تصدير قاعدة البيانات إلى JSON بالبنية التي يقرؤها
/// [LegacyImporter] مباشرة — نسخة احتياطية ونقل بين الأجهزة في آنٍ واحد.
class DataExporter {
  DataExporter(this.db);

  final AppDatabase db;

  /// [since] يحوّل التصدير إلى **تفاضلي**: لا يخرج إلا ما تغيّر بعد ذلك الختم.
  ///
  /// هذا ما يجعل المزامنة عبر الإنترنت ممكنة: قاعدة كاملة كل ربع ساعة على
  /// بيانات الجوال فاتورةٌ لا تُحتمل، والتغيير اليومي في وحدة إمداد عشرات
  /// السجلات لا عشرات الآلاف.
  ///
  /// والدمج في الطرف الآخر إضافيّ لا استبداليّ ([LegacyImporter]): ما غاب عن
  /// الحمولة يبقى كما هو، والحذف ينتقل بشاهده في `syncMarks` لا بغياب السجل.
  /// فالحمولة الجزئية آمنة تمامًا — ولولا ذلك لاستحال هذا كله.
  /// [includeOwnerSecrets] = `false` يُسقط الملح والبصمة لحساب **المالك** من الحمولة
  /// (المزامنة): بصمة المالك على كل جهاز فرعٍ تتيح كسرها دون اتصال بسرقة جهازٍ
  /// واحد، والمالك يعمل من جهاز الإدارة الذي يحمل مفتاحه. المفتاحان يغيبان ولا
  /// يُفرَّغان، فيُبقي المستقبِل بصمته القائمة (انظر `_importUsers`).
  ///
  /// **المديرون يبقون**: مدير الفرع يدخل بكلمة مروره على جهاز فرعه، وجهاز فرعٍ جديد
  /// لا يملك حسابًا يدخل به غير الحسابات الواصلة بالمزامنة. بصماتهم تتبع حكمَ
  /// PBKDF2 (310 ألف دورة) وحارس المزامنة (`c`) يمنع استبدالها. النسخة الاحتياطية
  /// لملفٍّ مشفَّر تُبقي الكل (الافتراضي).
  ///
  /// [sinceSeq] هو المسار التفاضلي المعتمد: ما كُتب **على هذا الجهاز** بعد رقم
  /// التسلسل ذاك (`SyncMarks.changedSinceSeq`)، أيًّا كانت ساعة كاتبه الأصلي.
  /// و[since] (ختم زمني) باقٍ لقرينٍ بإصدارٍ أقدم وحده؛ يُهمل إن مُرِّر [sinceSeq].
  Future<Map<String, dynamic>> toMap({
    bool includeUsers = false,
    int? since,
    int? sinceSeq,
    bool includeOwnerSecrets = true,
  }) async {
    final marks = SyncMarks(db);
    // **الترتيب هنا ليس اعتباطًا.** علامة الماء تُقرأ **قبل** مسح التغييرات:
    // سجلٌ يُكتب بين القراءتين رقمُه أكبر من العلامة المُعلنة، فيُلتقط في
    // الدورة القادمة. لو عُكس الترتيب لسقط ذلك السجل من الحمولة وسقطت العلامة
    // فوقه — فلا يُطلب مرة أخرى أبدًا، ويضيع بلا أثر.
    final upTo = await marks.maxStamp();
    final upToSeq = await marks.maxSeq();
    final delta = sinceSeq != null
        ? await marks.changedSinceSeq(sinceSeq)
        : (since == null ? null : await marks.changedSince(since));

    /// معرّفات ما تغيّر في جدول واحد. `null` ⇒ تصدير كامل بلا ترشيح.
    Set<String>? ids(String entity) {
      if (delta == null) return null;
      return {
        for (final m in delta)
          if (m.entity == entity) m.rowId
      };
    }

    final receipts = await _rows(db.receipts, ids('receipts'), (t) => t.id);
    final issues = await _rows(db.issues, ids('issues'), (t) => t.id);
    final transfers = await _rows(db.transfers, ids('transfers'), (t) => t.id);
    final returns = await _rows(db.returns, ids('returns'), (t) => t.id);

    return {
      'meta': {
        'app': 'imdad',
        'exportedAt': DateTime.now().toIso8601String(),
        'schema': db.schemaVersion,
        if (sinceSeq != null) 'sinceSeq': sinceSeq else if (since != null) 'since': since,
        // علامة الماء التي يحفظها الطرف الآخر ليطلب ما بعدها في المرة القادمة:
        // رقم تسلسل هذا الجهاز (`maxSeq`). و`maxStamp` لقرينٍ أقدم وحده — هو
        // أكبر ختمٍ في الجدول، خليطٌ من ساعات الأجهزة كلها، ولا يصلح علامةً.
        'maxSeq': upToSeq,
        'maxStamp': upTo,
      },
      if (includeUsers)
        'users': (await _rows(db.users, ids('users'), (t) => t.id))
            .map((u) => {
                  'id': u.id,
                  'username': u.username,
                  'name': u.name,
                  'email': u.email,
                  'role': u.role,
                  'roles': u.roles,
                  'permissions': u.permissions,
                  'warehouseScope': u.warehouseScope,
                  if (includeOwnerSecrets || !UserRole.isOwner(u.role)) ...{
                    'saltHex': u.saltHex,
                    'hashHex': u.hashHex,
                    'iterations': u.iterations,
                  },
                  'active': u.active,
                  'approved': u.approved,
                  // بثوانٍ (دقة التخزين): بصمة توقيع المالك تضمّها، فيتحقق المستقبِل منها.
                  'updatedAt': u.updatedAt == null ? null : u.updatedAt!.millisecondsSinceEpoch ~/ 1000,
                  'sectionBlocked': u.sectionBlocked,
                  'ownerSig': u.ownerSig,
                })
            .toList(),
      'categories': (await _rows(db.categories, ids('categories'), (t) => t.id))
          .map(
              (c) => {'id': c.id, 'name': c.name, 'description': c.description})
          .toList(),
      'items': (await _rows(db.items, ids('items'), (t) => t.id))
          .map((i) => {
                'id': i.id,
                'code': i.code,
                'name': i.name,
                'categoryId': i.categoryId,
                'categoryName': i.categoryName,
                'baseUnit': i.baseUnit,
                'units': i.units,
                'minQty': i.minQty,
                'qty': i.qty,
                'barcode': i.barcode,
                'isRefillable': i.isRefillable,
                'reportUnit': i.reportUnit,
              })
          .toList(),
      'warehouses': (await _rows(db.warehouses, ids('warehouses'), (t) => t.id))
          .map((w) => {
                'id': w.id,
                'code': w.code,
                'name': w.name,
                'manager': w.manager,
                'location': w.location,
                'feedsAllCamps': w.feedsAllCamps,
                'isMain': w.isMain,
                'fuelCapacityLiters': w.fuelCapacityLiters,
                'campIds': w.campIds,
                'notes': w.notes,
              })
          .toList(),
      'suppliers': (await _rows(db.suppliers, ids('suppliers'), (t) => t.id))
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'contact': s.contact,
                'phone': s.phone,
                'city': s.city,
                'notes': s.notes
              })
          .toList(),
      'units': (await _rows(
              db.beneficiaryUnits, ids('beneficiary_units'), (t) => t.id))
          .map((u) => {
                'id': u.id,
                'code': u.code,
                'name': u.name,
                'type': u.type,
                'parentId': u.parentId,
                'parentName': u.parentName,
                'category': u.category,
                'isCamp': u.isCamp,
                'facilityId': u.facilityId,
                'facilityIds': u.facilityIds,
              })
          .toList(),
      'facilities': (await _rows(db.facilities, ids('facilities'), (t) => t.id))
          .map((f) => {
                'id': f.id,
                'name': f.name,
                'fType': f.fType,
                'capacity': f.capacity,
                'warehouse': f.warehouse,
                'notes': f.notes,
              })
          .toList(),
      'receipts': receipts
          .map((r) => {
                ..._movement(
                  id: r.id,
                  refNo: r.refNo,
                  date: r.date,
                  warehouse: r.warehouse,
                  itemId: r.itemId,
                  itemCode: r.itemCode,
                  itemName: r.itemName,
                  unitName: r.unitName,
                  factor: r.factor,
                  qty: r.qty,
                  baseQty: r.baseQty,
                  status: r.status,
                  notes: r.notes,
                  createdBy: r.createdBy,
                  createdAt: r.createdAt,
                ),
                'supplier': r.supplier,
                'invoiceNo': r.invoiceNo,
                'committee': r.committee,
                'supervision': r.supervision,
                'audit': r.audit,
                // توريد التعبئة لا يزيد عدد الأسطوانات: بدونه يُحسب في الجهاز الآخر توريدًا جديدًا.
                'cylinderAction': r.cylinderAction,
                'expiryDate': r.expiryDate,
                ..._edits(r.editCount, r.editLog, r.editedBy, r.cancelReason,
                    r.cancelledBy, r.prevStatus),
              })
          .toList(),
      'issues': issues
          .map((i) => {
                ..._movement(
                  id: i.id,
                  refNo: i.refNo,
                  date: i.date,
                  warehouse: i.warehouse,
                  itemId: i.itemId,
                  itemCode: i.itemCode,
                  itemName: i.itemName,
                  unitName: i.unitName,
                  factor: i.factor,
                  qty: i.qty,
                  baseQty: i.baseQty,
                  status: i.status,
                  notes: i.notes,
                  createdBy: i.createdBy,
                  createdAt: i.createdAt,
                ),
                'targetType': i.targetType,
                'recipientDisplay': i.recipientDisplay,
                'unitId': i.unitId,
                'facilityId': i.facilityId,
                'beneficiaryUnitId': i.beneficiaryUnitId,
                'beneficiaryUnitName': i.beneficiaryUnitName,
                'soldierCount': i.soldierCount,
                'durationDays': i.durationDays,
                'officerCount': i.officerCount,
                'cylinderAction': i.cylinderAction,
                'approvedBy': i.approvedBy,
                'rejectReason': i.rejectReason,
                'rejectedBy': i.rejectedBy,
                ..._edits(i.editCount, i.editLog, i.editedBy, i.cancelReason,
                    i.cancelledBy, i.prevStatus),
              })
          .toList(),
      'transfers': transfers
          .map((t) => {
                ..._movement(
                  id: t.id,
                  refNo: t.refNo,
                  date: t.date,
                  warehouse: t.warehouse,
                  itemId: t.itemId,
                  itemCode: t.itemCode,
                  itemName: t.itemName,
                  unitName: t.unitName,
                  factor: t.factor,
                  qty: t.qty,
                  baseQty: t.baseQty,
                  status: t.status,
                  notes: t.notes,
                  createdBy: t.createdBy,
                  createdAt: t.createdAt,
                ),
                'destWarehouse': t.destWarehouse,
                'campId': t.campId,
                'campName': t.campName,
                'strength': t.strength,
                'durationDays': t.durationDays,
                'rejectReason': t.rejectReason,
                'cylinderAction': t.cylinderAction,
                ..._edits(t.editCount, t.editLog, t.editedBy, t.cancelReason,
                    t.cancelledBy, t.prevStatus),
              })
          .toList(),
      'returns': returns
          .map((r) => {
                ..._movement(
                  id: r.id,
                  refNo: r.refNo,
                  date: r.date,
                  warehouse: r.warehouse,
                  itemId: r.itemId,
                  itemCode: r.itemCode,
                  itemName: r.itemName,
                  unitName: r.unitName,
                  factor: r.factor,
                  qty: r.qty,
                  baseQty: r.baseQty,
                  status: r.status,
                  notes: r.notes,
                  createdBy: r.createdBy,
                  createdAt: r.createdAt,
                ),
                'party': r.party,
                'type': r.type,
                'beneficiaryUnitId': r.beneficiaryUnitId,
                'beneficiaryUnitName': r.beneficiaryUnitName,
                'condition': r.condition,
                'origRef': r.origRef,
                'cylinderAction': r.cylinderAction,
                ..._edits(r.editCount, r.editLog, r.editedBy, r.cancelReason,
                    r.cancelledBy, r.prevStatus),
              })
          .toList(),
      'openingBalances': (await _rows(
              db.openingBalances, ids('opening_balances'), (t) => t.id))
          .map((o) => {
                'id': o.id,
                'itemId': o.itemId,
                'itemCode': o.itemCode,
                'itemName': o.itemName,
                'warehouse': o.warehouse,
                'qty': o.qty,
                'date': o.date,
                'setBy': o.setBy,
              })
          .toList(),
      'adjustments':
          (await _rows(db.adjustments, ids('adjustments'), (t) => t.id))
              .map((a) => {
                    'id': a.id,
                    'refNo': a.refNo,
                    'date': a.date,
                    'warehouse': a.warehouse,
                    'itemId': a.itemId,
                    'itemCode': a.itemCode,
                    'itemName': a.itemName,
                    'unitName': a.unitName,
                    'factor': a.factor,
                    'qty': a.qty,
                    'baseQty': a.baseQty,
                    'status': a.status,
                    'notes': a.notes,
                    'createdBy': a.createdBy,
                    'createdAt': a.createdAt.toIso8601String(),
                    'sessionId': a.sessionId,
                    'reason': a.reason,
                    'approvedBy': a.approvedBy,
                    ..._edits(a.editCount, a.editLog, a.editedBy,
                        a.cancelReason, a.cancelledBy, a.prevStatus),
                  })
              .toList(),
      'strengths': (await _rows(db.strengths, ids('strengths'), (t) => t.id))
          .map((s) => {
                'id': s.id,
                'unitId': s.unitId,
                'unitName': s.unitName,
                'campId': s.campId,
                'campName': s.campName,
                'date': s.strengthDate,
                'soldierCount': s.soldierCount,
                'officerCount': s.officerCount,
                'total': s.total,
                'pct': s.pct,
                'mode': s.mode,
                'createdBy': s.createdBy,
              })
          .toList(),
      'kitchenLogs':
          (await _rows(db.kitchenLogs, ids('kitchen_logs'), (t) => t.id))
              .map((l) => {
                    'id': l.id,
                    'facilityId': l.facilityId,
                    'facilityName': l.facilityName,
                    'date': l.date,
                    'mealType': l.mealType,
                    'strength': l.strength,
                    'itemId': l.itemId,
                    'itemName': l.itemName,
                    'unitName': l.unitName,
                    'qty': l.qty,
                    'baseQty': l.baseQty,
                    'expectedBase': l.expectedBase,
                    'varianceBase': l.varianceBase,
                    'notes': l.notes,
                  })
              .toList(),
      'entitlements':
          (await _rows(db.entitlements, ids('entitlements'), (t) => t.itemId))
              .map((e) => {
                    'itemId': e.itemId,
                    'itemName': e.itemName,
                    'qtyPerPerson': e.qtyPerPerson,
                    'measureUnitName': e.measureUnitName,
                    'measureFactor': e.measureFactor,
                    // الكمية محفوظة بوحدة القياس المقررة. بدون هذا الوسم يعاملها المستورِد
                    // كتصدير ويب قديم بالوحدة الأساسية فيقسمها على المعامل في كل مزامنة.
                    'qtyUnit': 'measure',
                    'notes': e.notes,
                  })
              .toList(),
      'stocktakes': (await _rows(db.stocktakes, ids('stocktakes'), (t) => t.id))
          .map((s) => {
                'id': s.id,
                'orderNo': s.orderNo,
                'type': s.type,
                'date': s.date,
                'warehouse': s.warehouse,
                'categoryId': s.categoryId,
                'categoryName': s.categoryName,
                'committee': s.committee,
                'freeze': s.freeze,
                'status': s.status,
                'itemsCount': s.itemsCount,
                'notes': s.notes,
                'closedDate': s.closedDate,
                'createdBy': s.createdBy,
                'createdAt': s.createdAt.toIso8601String(),
                'cancelReason': s.cancelReason,
                'cancelledBy': s.cancelledBy,
                'closedBy': s.closedBy,
                'countedCount': s.countedCount,
                'varianceCount': s.varianceCount,
                'adjustedCount': s.adjustedCount,
              })
          .toList(),
      'stocktakeLines':
          (await _rows(db.stocktakeLines, ids('stocktake_lines'), (t) => t.id))
              .map((l) => {
                    'id': l.id,
                    'sessionId': l.sessionId,
                    'itemId': l.itemId,
                    'itemCode': l.itemCode,
                    'itemName': l.itemName,
                    'unitName': l.unitName,
                    'systemQty': l.systemQty,
                    'countedQty': l.countedQty,
                    'counts': l.counts,
                    'variance': l.variance,
                    'reason': l.reason,
                    'decision': l.decision,
                    'status': l.status,
                    'discovered': l.discovered,
                  })
              .toList(),
      'sensitiveReviews': (await _rows(
              db.sensitiveReviews, ids('sensitive_reviews'), (t) => t.id))
          .map((r) => {
                'id': r.id,
                'logId': r.logId,
                'reviewedBy': r.reviewedBy,
                'note': r.note,
                'reviewedAt': r.reviewedAt.toIso8601String(),
              })
          .toList(),
      'auditLogs': (await _rows(db.auditLogs, ids('audit_logs'), (t) => t.id))
          .map((a) => {
                'id': a.id,
                'action': a.action,
                'entityType': a.entityType,
                'summary': a.summary,
                'details': a.details,
                'risk': a.risk,
                'actorEmail': a.actorEmail,
                'logDate': a.logDate,
                'actorName': a.actorName,
                'actorRole': a.actorRole,
                'refNo': a.refNo,
                'warehouse': a.warehouse,
                'target': a.target,
                'status': a.status,
                'itemCount': a.itemCount,
                'qty': a.qty,
                'createdAt': a.createdAt.toIso8601String(),
              })
          .toList(),
      'assets': (await _rows(db.assets, ids('assets'), (t) => t.id))
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'quantity': a.quantity,
                'assetType': a.assetType,
                'serialNumber': a.serialNumber,
                'facilityId': a.facilityId,
                'facilityName': a.facilityName,
                'beneficiaryUnitId': a.beneficiaryUnitId,
                'beneficiaryUnitName': a.beneficiaryUnitName,
                'warehouse': a.warehouse,
                'status': a.status,
                'acquisitionDate': a.acquisitionDate,
                'value': a.value,
                'lifespanMonths': a.lifespanMonths,
                'supplierId': a.supplierId,
                'supplierName': a.supplierName,
                'invoiceNumber': a.invoiceNumber,
                'notes': a.notes,
                'createdBy': a.createdBy,
                'createdAt': a.createdAt.toIso8601String(),
              })
          .toList(),
      'assetAssignments': (await _rows(
              db.assetAssignments, ids('asset_assignments'), (t) => t.id))
          .map((g) => {
                'id': g.id,
                'assetId': g.assetId,
                'assetName': g.assetName,
                'beneficiaryUnitId': g.beneficiaryUnitId,
                'beneficiaryUnitName': g.beneficiaryUnitName,
                'assignedDate': g.assignedDate,
                'returnedDate': g.returnedDate,
                'assignedTo': g.assignedTo,
                'notes': g.notes,
                'createdBy': g.createdBy,
                'createdAt': g.createdAt.toIso8601String(),
              })
          .toList(),
      'rationOrders':
          (await _rows(db.rationOrders, ids('ration_orders'), (t) => t.id))
              .map((o) => {
                    'id': o.id,
                    'refNo': o.refNo,
                    'requestingWarehouse': o.requestingWarehouse,
                    'supplyingWarehouse': o.supplyingWarehouse,
                    'date': o.date,
                    'requiredDate': o.requiredDate,
                    'status': o.status,
                    'priority': o.priority,
                    'notes': o.notes,
                    'rejectReason': o.rejectReason,
                    'createdBy': o.createdBy,
                    'approvedBy': o.approvedBy,
                    'receivedBy': o.receivedBy,
                    'receiptRef': o.receiptRef,
                    'orderKind': o.orderKind,
                    'authorityId': o.authorityId,
                    'authorityName': o.authorityName,
                    'fulfillRef': o.fulfillRef,
                    'fulfillKind': o.fulfillKind,
                    'fulfillDate': o.fulfillDate,
                    'createdAt': o.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelWarehouses':
          (await _rows(db.fuelWarehouses, ids('fuel_warehouses'), (t) => t.id))
              .map((w) => {
                    'id': w.id,
                    'code': w.code,
                    'name': w.name,
                    'manager': w.manager,
                    'location': w.location,
                    'capacityLiters': w.capacityLiters,
                    'active': w.active,
                    'notes': w.notes,
                    'createdAt': w.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelUnits': (await _rows(db.fuelUnits, ids('fuel_units'), (t) => t.id))
          .map((u) => {
                'id': u.id,
                'code': u.code,
                'name': u.name,
                'commander': u.commander,
                'phone': u.phone,
                'active': u.active,
                'notes': u.notes,
                'createdAt': u.createdAt.toIso8601String(),
              })
          .toList(),
      'fuelSettings': (await _rows(
              db.fuelSettingsRows, ids('fuel_settings_rows'), (t) => t.id))
          .map((x) => {
                'id': x.id,
                'lowStockPercent': x.lowStockPercent,
                'defaultDailyLiters': x.defaultDailyLiters,
                'defaultWeeklyLiters': x.defaultWeeklyLiters,
                'defaultMonthlyLiters': x.defaultMonthlyLiters,
                'parentOrg': x.parentOrg,
                'agencyTitle': x.agencyTitle,
                'commandTitle': x.commandTitle,
                'branchTitle': x.branchTitle,
                'orgName': x.orgName,
                'sealLines': x.sealLines,
                'roleOfficer': x.roleOfficer,
                'roleSupply': x.roleSupply,
                'roleChief': x.roleChief,
                'signOfficer': x.signOfficer,
                'signSupply': x.signSupply,
                'signChief': x.signChief,
                'requireChassis': x.requireChassis,
                'allowExceptional': x.allowExceptional,
                'carryCapPeriods': x.carryCapPeriods,
                'notes': x.notes,
              })
          .toList(),
      'fuelAllocations': (await _rows(
              db.fuelAllocations, ids('fuel_allocations'), (t) => t.id))
          .map((a) => {
                'id': a.id,
                'refNo': a.refNo,
                'unitId': a.unitId,
                'unitName': a.unitName,
                'fuelType': a.fuelType,
                'periodType': a.periodType,
                'quantityPerPeriod': a.quantityPerPeriod,
                'totalQuantity': a.totalQuantity,
                'weeklyLiters': a.weeklyLiters,
                'monthlyLiters': a.monthlyLiters,
                'issueLocation': a.issueLocation,
                'startDate': a.startDate,
                'endDate': a.endDate,
                'active': a.active,
                'disbursable': a.disbursable,
                'writtenOffLiters': a.writtenOffLiters,
                'notes': a.notes,
                'createdBy': a.createdBy,
                'createdAt': a.createdAt.toIso8601String(),
              })
          .toList(),
      'fuelIssues':
          (await _rows(db.fuelIssues, ids('fuel_issues'), (t) => t.id))
              .map((i) => {
                    'id': i.id,
                    'refNo': i.refNo,
                    'date': i.date,
                    'fuelType': i.fuelType,
                    'warehouse': i.warehouse,
                    'source': i.source,
                    'quantityLiters': i.quantityLiters,
                    'driverName': i.driverName,
                    'vehicleType': i.vehicleType,
                    'chassisNo': i.chassisNo,
                    'allocationId': i.allocationId,
                    'beneficiaryUnitId': i.beneficiaryUnitId,
                    'beneficiaryName': i.beneficiaryName,
                    'entitledLiters': i.entitledLiters,
                    'periodType': i.periodType,
                    'customFrom': i.customFrom,
                    'customTo': i.customTo,
                    'justification': i.justification,
                    'orderAuthority': i.orderAuthority,
                    'purpose': i.purpose,
                    'notes': i.notes,
                    'createdBy': i.createdBy,
                    'createdAt': i.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelSupplies':
          (await _rows(db.fuelSupplies, ids('fuel_supplies'), (t) => t.id))
              .map((x) => {
                    'id': x.id,
                    'refNo': x.refNo,
                    'date': x.date,
                    'fuelType': x.fuelType,
                    'quantityLiters': x.quantityLiters,
                    'supplierName': x.supplierName,
                    'warehouse': x.warehouse,
                    'transportVehicleType': x.transportVehicleType,
                    'driverName': x.driverName,
                    'notes': x.notes,
                    'createdBy': x.createdBy,
                    'createdAt': x.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelOpenings':
          (await _rows(db.fuelOpenings, ids('fuel_openings'), (t) => t.id))
              .map((x) => {
                    'id': x.id,
                    'warehouse': x.warehouse,
                    'fuelType': x.fuelType,
                    'liters': x.liters,
                    'asOfDate': x.asOfDate,
                    'note': x.note,
                    'createdAt': x.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelTransfers':
          (await _rows(db.fuelTransfers, ids('fuel_transfers'), (t) => t.id))
              .map((x) => {
                    'id': x.id,
                    'refNo': x.refNo,
                    'date': x.date,
                    'fuelType': x.fuelType,
                    'quantityLiters': x.quantityLiters,
                    'fromWarehouse': x.fromWarehouse,
                    'toWarehouse': x.toWarehouse,
                    'driverName': x.driverName,
                    'transportVehicleType': x.transportVehicleType,
                    'notes': x.notes,
                    'createdBy': x.createdBy,
                    'createdAt': x.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelStocktakes':
          (await _rows(db.fuelStocktakes, ids('fuel_stocktakes'), (t) => t.id))
              .map((x) => {
                    'id': x.id,
                    'refNo': x.refNo,
                    'date': x.date,
                    'warehouse': x.warehouse,
                    'kind': x.kind,
                    'fuelFilter': x.fuelFilter,
                    'committee': x.committee,
                    'status': x.status,
                    'notes': x.notes,
                    'createdBy': x.createdBy,
                    'createdAt': x.createdAt.toIso8601String(),
                  })
              .toList(),
      'fuelStocktakeLines': (await _rows(
              db.fuelStocktakeLines, ids('fuel_stocktake_lines'), (t) => t.id))
          .map((x) => {
                'id': x.id,
                'stocktakeId': x.stocktakeId,
                'fuelType': x.fuelType,
                'bookLiters': x.bookLiters,
                'counted': x.counted,
                'countedLiters': x.countedLiters,
              })
          .toList(),
      'warehouseStockLimits': (await _rows(db.warehouseStockLimits,
              ids('warehouse_stock_limits'), (t) => t.id))
          .map((l) => {
                'id': l.id,
                'warehouseId': l.warehouseId,
                'warehouseName': l.warehouseName,
                'itemId': l.itemId,
                'itemName': l.itemName,
                'unitName': l.unitName,
                'factor': l.factor,
                'minStock': l.minStock,
                'maxStock': l.maxStock,
                'notes': l.notes,
                'updatedAt': l.updatedAt.toIso8601String(),
              })
          .toList(),
      'supplyAuthorities': (await _rows(
              db.supplyAuthorities, ids('supply_authorities'), (t) => t.id))
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'title': a.title,
                'notes': a.notes,
                'active': a.active,
                'createdAt': a.createdAt.toIso8601String(),
              })
          .toList(),
      'rationOrderLines': (await _rows(
              db.rationOrderLines, ids('ration_order_lines'), (t) => t.id))
          .map((l) => {
                'id': l.id,
                'orderId': l.orderId,
                'itemId': l.itemId,
                'itemCode': l.itemCode,
                'itemName': l.itemName,
                'unitName': l.unitName,
                'factor': l.factor,
                'requestedQty': l.requestedQty,
                'approvedQty': l.approvedQty,
                'receivedQty': l.receivedQty,
                'notes': l.notes,
              })
          .toList(),
      'mealPlans': (await _rows(db.mealPlans, ids('meal_plans'), (t) => t.id))
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'planType': p.planType,
                'startDate': p.startDate,
                'endDate': p.endDate,
                'status': p.status,
                'facilityId': p.facilityId,
                'facilityName': p.facilityName,
                'warehouse': p.warehouse,
                'notes': p.notes,
                'createdBy': p.createdBy,
                'createdAt': p.createdAt.toIso8601String(),
              })
          .toList(),
      'mealPlanEntries': (await _rows(
              db.mealPlanEntries, ids('meal_plan_entries'), (t) => t.id))
          .map((e) => {
                'id': e.id,
                'planId': e.planId,
                'entryDate': e.entryDate,
                'mealType': e.mealType,
                'itemId': e.itemId,
                'itemCode': e.itemCode,
                'itemName': e.itemName,
                'unitName': e.unitName,
                'factor': e.factor,
                'qtyPerPerson': e.qtyPerPerson,
                'notes': e.notes,
              })
          .toList(),
      'campLedgers':
          (await _rows(db.campLedgers, ids('camp_ledgers'), (t) => t.id))
              .map((l) => {
                    'id': l.id,
                    'campId': l.campId,
                    'campName': l.campName,
                    'itemId': l.itemId,
                    'itemName': l.itemName,
                    'unitName': l.unitName,
                    'year': l.year,
                    'month': l.month,
                    'openingEntitled': l.openingEntitled,
                    'openingStock': l.openingStock,
                    'entitlementTotal': l.entitlementTotal,
                    'transferredIn': l.transferredIn,
                    'issuedDirect': l.issuedDirect,
                    'returnedQty': l.returnedQty,
                    'consumedKitchen': l.consumedKitchen,
                    'strengthSum': l.strengthSum,
                    'strengthDays': l.strengthDays,
                    'status': l.status,
                    'closedBy': l.closedBy,
                    if (l.closedAt != null)
                      'closedAt': l.closedAt!.toIso8601String(),
                  })
              .toList(),
      'campStockLimits': (await _rows(
              db.campStockLimits, ids('camp_stock_limits'), (t) => t.id))
          .map((c) => {
                'id': c.id,
                'campId': c.campId,
                'campName': c.campName,
                'itemId': c.itemId,
                'itemName': c.itemName,
                'minStock': c.minStock,
                'maxStock': c.maxStock,
                'alertDaysBefore': c.alertDaysBefore,
              })
          .toList(),
      'monthlySettlements': (await _rows(
              db.monthlySettlements, ids('monthly_settlements'), (t) => t.id))
          .map((m) => {
                'id': m.id,
                'year': m.year,
                'month': m.month,
                'settledBy': m.settledBy,
                'notes': m.notes,
                'campsCount': m.campsCount,
                'itemsCount': m.itemsCount,
                'totalCredit': m.totalCredit,
                'totalDebit': m.totalDebit,
                'settledAt': m.settledAt.toIso8601String(),
              })
          .toList(),
      // البرقيات والارتباطات: تُنقل بتسلسل Drift الجاهز (toJson) فلا قائمة حقولٍ
      // ثانية تنحرف عن الجدول؛ واختبار الذهاب والإياب يفحص كل عمود.
      'cables': (await _rows(db.cables, ids('cables'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkPersons': (await _rows(db.linkPersons, ids('link_persons'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkStatusLogs':
          (await _rows(db.linkStatusLogs, ids('link_status_logs'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkFinCustodies':
          (await _rows(db.linkFinCustodies, ids('link_fin_custodies'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkClearances':
          (await _rows(db.linkClearances, ids('link_clearances'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkPurchaseContracts': (await _rows(db.linkPurchaseContracts, ids('link_purchase_contracts'), (t) => t.id))
          .map((e) => e.toJson())
          .toList(),
      'linkMoneyReceipts':
          (await _rows(db.linkMoneyReceipts, ids('link_money_receipts'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkArmaments':
          (await _rows(db.linkArmaments, ids('link_armaments'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkFinanceLedger':
          (await _rows(db.linkFinanceLedger, ids('link_finance_ledger'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkCustodySheets':
          (await _rows(db.linkCustodySheets, ids('link_custody_sheets'), (t) => t.id)).map((e) => e.toJson()).toList(),
      'linkCustodySheetRows': (await _rows(db.linkCustodySheetRows, ids('link_custody_sheet_rows'), (t) => t.id))
          .map((e) => e.toJson())
          .toList(),
      'settings':
          (await _rows(db.appSettings, ids('app_settings'), (t) => t.key))
              .where((s) => !SettingsRepo.localOnlyKeys.contains(s.key))
              .map((s) => {'key': s.key, 'value': s.value})
              .toList(),
      // إلغاء تفعيل الأجهزة: يصل الجهاز الملغى بهذه القناة فيتوقف (آخر ختمٍ يفوز).
      'deviceRevocations': await DeviceActivation(db).revocationsForSync(),
      // سجل التغييرات: به يعرف الجهاز الآخر أيّ نسخة أحدث، وما حُذف هنا عمدًا.
      // في التصدير التفاضلي تخرج علامات ما تغيّر وحدها — ومعها شواهد الحذف،
      // فينتقل الحذف كما ينتقل التعديل.
      'syncMarks': (delta ?? (await marks.snapshot()).values)
          .map((m) => m.toMap())
          .toList(),
    };
  }

  /// عدد السجلات التي يحملها [toMap] لو صُدِّر كاملًا (بلا المستخدمين)، **دون
  /// بناء الحمولة**: `COUNT(*)` لكل جدول مزامَن بدل قراءة كل الصفوف وتحويلها
  /// إلى خرائط. يستعمله `GET /info` الذي يحتاج رقمًا واحدًا فقط.
  ///
  /// التطابق مع مجموع قوائم [toMap]: الجداول المزامَنة ([SyncMarks.entities])
  /// ما عدا `users`، والإعدادات بعد استبعاد المفاتيح المحلية، وسطور `sync_marks`.
  Future<int> countRecords() async {
    var total = 0;
    for (final t in db.allTables) {
      final name = t.actualTableName;
      if (name == 'users' || name == 'app_settings' || !SyncMarks.entities.containsKey(name)) continue;
      final q = db.selectOnly(t)..addColumns([countAll()]);
      total += (await q.getSingle()).read(countAll()) ?? 0;
    }
    final settings = db.selectOnly(db.appSettings)
      ..addColumns([countAll()])
      ..where(db.appSettings.key.isIn(SettingsRepo.localOnlyKeys).not());
    total += (await settings.getSingle()).read(countAll()) ?? 0;
    final marks = await db.customSelect('SELECT COUNT(*) AS c FROM ${SyncMarks.table}').getSingle();
    return total + marks.read<int>('c');
  }

  /// سطور جدول واحد، مرشَّحة بمعرّفات ما تغيّر.
  ///
  /// [ids] فارغة ⇒ لا استعلام أصلًا: في الدورة المعتادة لا يتغيّر إلا جدول أو
  /// جدولان، فقراءة السبعة عشر كلها في كل مرة إهدارٌ لبطارية الهاتف.
  Future<List<D>> _rows<T extends HasResultSet, D>(
    ResultSetImplementation<T, D> table,
    Set<String>? ids,
    Expression<String> Function(T) key,
  ) async {
    if (ids == null) return db.select(table).get();
    if (ids.isEmpty) return const [];
    // على دفعات: `IN (?, ?, …)` بعشرات الآلاف يتجاوز حدّ متغيّرات SQLite في
    // الاستعلام الواحد، فتفشل دفعةٌ تفاضلية كبيرة (بعد استيراد Excel أو غيابٍ
    // طويل) في كل دورة.
    const chunk = 500;
    final list = ids.toList();
    final out = <D>[];
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(i, i + chunk > list.length ? list.length : i + chunk);
      out.addAll(await (db.select(table)..where((t) => key(t).isIn(part))).get());
    }
    return out;
  }

  /// حقول تعديل السند وإلغائه المشتركة بين جداول الحركات (سجل المستندات).
  Map<String, dynamic> _edits(
    int editCount,
    String editLog,
    String editedBy,
    String cancelReason,
    String cancelledBy,
    String prevStatus,
  ) =>
      {
        'editCount': editCount,
        'editLog': editLog,
        'editedBy': editedBy,
        'cancelReason': cancelReason,
        'cancelledBy': cancelledBy,
        'prevStatus': prevStatus,
      };

  Map<String, dynamic> _movement({
    required String id,
    required String refNo,
    required String date,
    required String warehouse,
    required String itemId,
    required String itemCode,
    required String itemName,
    required String unitName,
    required double factor,
    required double qty,
    required double baseQty,
    required String status,
    required String notes,
    required String createdBy,
    required DateTime createdAt,
  }) =>
      {
        'id': id,
        'refNo': refNo,
        'date': date,
        'warehouse': warehouse,
        'itemId': itemId,
        'itemCode': itemCode,
        'itemName': itemName,
        'unitName': unitName,
        'factor': factor,
        'qty': qty,
        'baseQty': baseQty,
        'status': status,
        'notes': notes,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  /// يكتب النسخة الاحتياطية إلى ملف ويعيد مساره وعدد السجلات.
  /// يكتب النسخة الاحتياطية إلى ملف. [password] غير فارغة ⇒ يُشفَّر الملف
  /// (انظر [BackupCrypto])؛ فارغة ⇒ JSON مقروء كما كان، للتوافق.
  Future<({String path, int records, bool encrypted})> writeToFile(
    String path, {
    bool includeUsers = false,
    String password = '',
  }) async {
    final map = await toMap(includeUsers: includeUsers);
    final records = map.entries
        .where((e) => e.value is List)
        .fold<int>(0, (sum, e) => sum + (e.value as List).length);

    final file = File(path);
    if (password.isEmpty) {
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
      return (path: path, records: records, encrypted: false);
    }
    // اشتقاق المفتاح (٣١٠ ألف دورة) يعمل في Isolate منفصل: النسخة المجدولة تجري
    // والمستخدم يعمل، فلا يتجمد عليه الرسم.
    final sealed = await compute(_sealTask, (map, password));
    await file.writeAsBytes(sealed, flush: true);
    return (path: path, records: records, encrypted: true);
  }
}

/// تشفير النسخة داخل Isolate: ترميز JSON ثم [BackupCrypto.seal].
Uint8List _sealTask((Map<String, dynamic>, String) a) => BackupCrypto.seal(jsonEncode(a.$1), a.$2);
