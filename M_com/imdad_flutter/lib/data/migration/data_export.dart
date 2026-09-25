import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'backup_crypto.dart';
import '../sync/sync_marks.dart';

/// تصدير قاعدة البيانات إلى JSON بنفس بنية ملف نسخة الويب، فيقرأه
/// [WebImporter] مباشرة — نسخة احتياطية ونقل بين الأجهزة في آنٍ واحد.
class DataExporter {
  DataExporter(this.db);

  final AppDatabase db;

  /// [since] يحوّل التصدير إلى **تفاضلي**: لا يخرج إلا ما تغيّر بعد ذلك الختم.
  ///
  /// هذا ما يجعل المزامنة عبر الإنترنت ممكنة: قاعدة كاملة كل ربع ساعة على
  /// بيانات الجوال فاتورةٌ لا تُحتمل، والتغيير اليومي في وحدة إمداد عشرات
  /// السجلات لا عشرات الآلاف.
  ///
  /// والدمج في الطرف الآخر إضافيّ لا استبداليّ ([WebImporter]): ما غاب عن
  /// الحمولة يبقى كما هو، والحذف ينتقل بشاهده في `syncMarks` لا بغياب السجل.
  /// فالحمولة الجزئية آمنة تمامًا — ولولا ذلك لاستحال هذا كله.
  Future<Map<String, dynamic>> toMap({bool includeUsers = false, int? since}) async {
    final marks = SyncMarks(db);
    // **الترتيب هنا ليس اعتباطًا.** علامة الماء تُقرأ **قبل** مسح التغييرات:
    // سجلٌ يُكتب بين القراءتين ختمُه أكبر من العلامة المُعلنة، فيُلتقط في
    // الدورة القادمة. لو عُكس الترتيب لسقط ذلك السجل من الحمولة وسقطت العلامة
    // فوقه — فلا يُطلب مرة أخرى أبدًا، ويضيع بلا أثر.
    final upTo = await marks.maxStamp();
    final delta = since == null ? null : await marks.changedSince(since);

    /// معرّفات ما تغيّر في جدول واحد. `null` ⇒ تصدير كامل بلا ترشيح.
    Set<String>? ids(String entity) {
      if (delta == null) return null;
      return {for (final m in delta) if (m.entity == entity) m.rowId};
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
        if (since != null) 'since': since,
        // علامة الماء التي يحفظها الطرف الآخر ليطلب ما بعدها في المرة القادمة.
        // تُؤخذ من ساعة هذا الجهاز وحده، فلا يفسدها اختلاف ساعتَي الجهازين.
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
                  'saltHex': u.saltHex,
                  'hashHex': u.hashHex,
                  'iterations': u.iterations,
                  'active': u.active,
                  'approved': u.approved,
                })
            .toList(),
      'categories': (await _rows(db.categories, ids('categories'), (t) => t.id))
          .map((c) => {'id': c.id, 'name': c.name, 'description': c.description})
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
                'campIds': w.campIds,
                'notes': w.notes,
              })
          .toList(),
      'suppliers': (await _rows(db.suppliers, ids('suppliers'), (t) => t.id))
          .map((s) => {'id': s.id, 'name': s.name, 'contact': s.contact, 'phone': s.phone, 'city': s.city, 'notes': s.notes})
          .toList(),
      'units': (await _rows(db.beneficiaryUnits, ids('beneficiary_units'), (t) => t.id))
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
                ..._edits(r.editCount, r.editLog, r.editedBy, r.cancelReason, r.cancelledBy, r.prevStatus),
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
                ..._edits(i.editCount, i.editLog, i.editedBy, i.cancelReason, i.cancelledBy, i.prevStatus),
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
                ..._edits(t.editCount, t.editLog, t.editedBy, t.cancelReason, t.cancelledBy, t.prevStatus),
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
                ..._edits(r.editCount, r.editLog, r.editedBy, r.cancelReason, r.cancelledBy, r.prevStatus),
              })
          .toList(),
      'openingBalances': (await _rows(db.openingBalances, ids('opening_balances'), (t) => t.id))
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
      'adjustments': (await _rows(db.adjustments, ids('adjustments'), (t) => t.id))
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
                ..._edits(a.editCount, a.editLog, a.editedBy, a.cancelReason, a.cancelledBy, a.prevStatus),
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
      'kitchenLogs': (await _rows(db.kitchenLogs, ids('kitchen_logs'), (t) => t.id))
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
      'entitlements': (await _rows(db.entitlements, ids('entitlements'), (t) => t.itemId))
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
      'stocktakeLines': (await _rows(db.stocktakeLines, ids('stocktake_lines'), (t) => t.id))
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
      'sensitiveReviews': (await _rows(db.sensitiveReviews, ids('sensitive_reviews'), (t) => t.id))
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
      'assetAssignments':
          (await _rows(db.assetAssignments, ids('asset_assignments'), (t) => t.id))
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
      'rationOrders': (await _rows(db.rationOrders, ids('ration_orders'), (t) => t.id))
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
      'supplyAuthorities':
          (await _rows(db.supplyAuthorities, ids('supply_authorities'), (t) => t.id))
              .map((a) => {
                    'id': a.id,
                    'name': a.name,
                    'title': a.title,
                    'notes': a.notes,
                    'active': a.active,
                    'createdAt': a.createdAt.toIso8601String(),
                  })
              .toList(),
      'rationOrderLines':
          (await _rows(db.rationOrderLines, ids('ration_order_lines'), (t) => t.id))
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
      'mealPlanEntries':
          (await _rows(db.mealPlanEntries, ids('meal_plan_entries'), (t) => t.id))
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
      'campLedgers': (await _rows(db.campLedgers, ids('camp_ledgers'), (t) => t.id))
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
                if (l.closedAt != null) 'closedAt': l.closedAt!.toIso8601String(),
              })
          .toList(),
      'campStockLimits':
          (await _rows(db.campStockLimits, ids('camp_stock_limits'), (t) => t.id))
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
      'monthlySettlements':
          (await _rows(db.monthlySettlements, ids('monthly_settlements'), (t) => t.id))
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
      'settings': (await _rows(db.appSettings, ids('app_settings'), (t) => t.key))
          .map((s) => {'key': s.key, 'value': s.value})
          .toList(),
      // سجل التغييرات: به يعرف الجهاز الآخر أيّ نسخة أحدث، وما حُذف هنا عمدًا.
      // في التصدير التفاضلي تخرج علامات ما تغيّر وحدها — ومعها شواهد الحذف،
      // فينتقل الحذف كما ينتقل التعديل.
      'syncMarks':
          (delta ?? (await marks.snapshot()).values).map((m) => m.toMap()).toList(),
    };
  }

  /// سطور جدول واحد، مرشَّحة بمعرّفات ما تغيّر.
  ///
  /// [ids] فارغة ⇒ لا استعلام أصلًا: في الدورة المعتادة لا يتغيّر إلا جدول أو
  /// جدولان، فقراءة السبعة عشر كلها في كل مرة إهدارٌ لبطارية الهاتف.
  Future<List<D>> _rows<T extends HasResultSet, D>(
    ResultSetImplementation<T, D> table,
    Set<String>? ids,
    Expression<String> Function(T) key,
  ) {
    if (ids != null && ids.isEmpty) return Future.value(const []);
    final q = db.select(table);
    if (ids != null) q.where((t) => key(t).isIn(ids.toList()));
    return q.get();
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
    await file.writeAsBytes(BackupCrypto.seal(jsonEncode(map), password), flush: true);
    return (path: path, records: records, encrypted: true);
  }
}
