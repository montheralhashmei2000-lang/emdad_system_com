import 'package:drift/drift.dart';

import '../../domain/stock_ledger.dart';
import '../../core/ids.dart';
import '../../core/ui/imd_format.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';

/// سطر إدخال في سند (قبل الحفظ).
class DocLineInput {
  const DocLineInput({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.unitName,
    required this.factor,
    required this.qty,
    this.notes = '',
    this.beneficiaryUnitId = '',
    this.beneficiaryUnitName = '',
    this.cylinderAction = '',
  });

  final String itemId;
  final String itemCode;
  final String itemName;
  final String unitName;
  final double factor;
  final double qty;
  final String notes;
  final String beneficiaryUnitId;
  final String beneficiaryUnitName;

  /// عملية الأصناف القابلة للتعبئة (فارغ لغيرها).
  final String cylinderAction;

  double get baseQty => _round(qty * (factor <= 0 ? 1 : factor));

  static double _round(double v) => (v * 1000).round() / 1000;
}

class SaveResult {
  const SaveResult({required this.ok, this.refNo = '', this.error = ''});

  final bool ok;
  final String refNo;
  final String error;
}

/// الحركات المخزنية: الاستلام والصرف والتحويل والمرتجعات + دفتر أرصدة المستودعات.
class MovementsRepo {
  MovementsRepo(this.db);

  final AppDatabase db;

  // ───────── دفتر الأرصدة ─────────
  /// يبني دفتر الأرصدة من كل الحركات المحفوظة (نفس قواعد stock-ledger.js).
  Future<StockLedger> ledger() async {
    final receipts = await db.select(db.receipts).get();
    final issues = await db.select(db.issues).get();
    final transfers = await db.select(db.transfers).get();
    final returns = await db.select(db.returns).get();
    final opening = await db.select(db.openingBalances).get();
    final adjustments = await db.select(db.adjustments).get();

    final moves = <MovementRecord>[
      for (final a in adjustments)
        MovementRecord(
          kind: MovementKind.adjustment,
          warehouse: a.warehouse,
          itemId: a.itemId,
          baseQty: a.baseQty,
          status: a.status,
          date: a.date,
        ),
      for (final o in opening)
        MovementRecord(
          kind: MovementKind.opening,
          warehouse: o.warehouse,
          itemId: o.itemId,
          baseQty: o.qty,
          date: o.date,
        ),
      for (final r in receipts)
        MovementRecord(
          kind: MovementKind.receipt,
          warehouse: r.warehouse,
          itemId: r.itemId,
          baseQty: r.baseQty,
          status: r.status,
          date: r.date,
          cylinderAction: r.cylinderAction,
        ),
      for (final i in issues)
        MovementRecord(
          kind: MovementKind.issue,
          warehouse: i.warehouse,
          itemId: i.itemId,
          baseQty: i.baseQty,
          status: i.status,
          date: i.date,
          cylinderAction: i.cylinderAction,
        ),
      for (final t in transfers)
        MovementRecord(
          kind: MovementKind.transferOut,
          warehouse: t.warehouse,
          destWarehouse: t.destWarehouse,
          itemId: t.itemId,
          baseQty: t.baseQty,
          status: t.status,
          date: t.date,
        ),
      for (final r in returns)
        MovementRecord(
          kind: r.type == 'TO_SUPPLIER' ? MovementKind.returnToSupplier : MovementKind.returnFromUnit,
          warehouse: r.warehouse,
          itemId: r.itemId,
          baseQty: r.baseQty,
          status: r.status,
          condition: r.condition,
          date: r.date,
        ),
    ];
    return StockLedger(moves);
  }

  /// الأرصدة محسوبة داخل قاعدة البيانات بـ SUM/GROUP BY بدل تحميل كل الحركات
  /// إلى الذاكرة كما يفعل [ledger]. القواعد نفسها حرفيًا (انظر `StockLedger`)،
  /// ويثبت التطابق اختبار تكافؤ يقارن المخرجين على البيانات نفسها.
  ///
  /// الفرق يظهر مع كبر البيانات: فحص رصيد صنف واحد كان يقرأ كل سندات النظام.
  Future<Map<String, double>> balances({String? warehouse, List<String>? scope}) async {
    final rows = await _balanceRows();
    final out = <String, double>{};
    for (final (wh, item, qty) in rows) {
      if (warehouse != null && warehouse.isNotEmpty) {
        if (wh != warehouse) continue;
      } else if (scope != null && !scope.contains(wh)) {
        continue;
      }
      out[item] = _roundQty((out[item] ?? 0) + qty);
    }
    return out;
  }

  Future<double> balanceOf(String itemId, {String? warehouse}) async =>
      (await balances(warehouse: warehouse))[itemId] ?? 0;

  /// (المستودع، الصنف، الرصيد) لكل تركيبة لها حركة.
  Future<List<(String, String, double)>> _balanceRows() async {
    const inactive = "('DRAFT','ORDER','CANCELLED','REJECTED')";
    const sql = """
      SELECT wh, item, SUM(q) AS total FROM (
        SELECT warehouse AS wh, item_id AS item, qty AS q FROM opening_balances
        UNION ALL
        -- توريد التعبئة لا يزيد عدد الأسطوانات (انظر `MovementRecord.changesCount`).
        SELECT warehouse, item_id, base_qty FROM receipts
          WHERE status NOT IN $inactive AND cylinder_action <> 'REFILL'
        UNION ALL
        -- الاستبدال لا ينقص العدد: فارغة تدخل وممتلئة تخرج.
        SELECT warehouse, item_id, -base_qty FROM issues
          WHERE status NOT IN $inactive AND cylinder_action <> 'EXCHANGE'
        UNION ALL
        SELECT warehouse, item_id, base_qty FROM adjustments
          WHERE status NOT IN $inactive
        UNION ALL
        SELECT warehouse, item_id, base_qty FROM "returns"
          WHERE type <> 'TO_SUPPLIER' AND condition <> 'تالفة' AND status NOT IN $inactive
        UNION ALL
        SELECT warehouse, item_id, -base_qty FROM "returns"
          WHERE type = 'TO_SUPPLIER' AND status NOT IN $inactive
        UNION ALL
        SELECT warehouse, item_id, -base_qty FROM transfers
          WHERE status NOT IN ('REJECTED','CANCELLED')
        UNION ALL
        SELECT dest_warehouse, item_id, base_qty FROM transfers
          WHERE status = 'RECEIVED'
      )
      -- الحركة الصفرية تُتجاهل قبل الجمع، تمامًا كما يتجاهلها `StockLedger.add`،
      -- وإلا ظهر صنف لم تمسّه حركة حقيقية برصيد صفر.
      WHERE wh <> '' AND item <> '' AND q <> 0
      GROUP BY wh, item
    """;
    final rows = await db.customSelect(sql).get();
    return [
      for (final r in rows)
        (
          r.read<String>('wh'),
          r.read<String>('item'),
          _roundQty(r.read<double>('total')),
        ),
    ];
  }

  static double _roundQty(double v) => (v * 1000).round() / 1000;

  /// رقم أمر الجرد المجمِّد المفتوح على المستودع، أو null إن لم يوجد.
  Future<String?> frozenOrder(String warehouse) async {
    if (warehouse.isEmpty) return null;
    final rows = await (db.select(db.stocktakes)
          ..where((t) =>
              t.warehouse.equals(warehouse) &
              t.freeze.equals(true) &
              t.status.isNotIn(const ['CLOSED', 'CANCELLED'])))
        .get();
    return rows.isEmpty ? null : rows.first.orderNo;
  }

  /// رسالة منع الحركة على مستودع مجمّد — نص `wrapGuards` في stocktake-center.js، أو null إن لم يكن مجمّدًا.
  Future<String?> frozenMessage(String warehouse) async {
    final no = await frozenOrder(warehouse);
    if (no == null) return null;
    return '✖ المستودع «$warehouse» مجمّد بسبب أمر الجرد $no — لا يمكن تنفيذ الحركة حتى اعتماد الجرد أو إلغائه';
  }

  // ───────── حفظ السندات ─────────
  /// `rcSave(draft)` — الحفظ كمسودة أو الاعتماد النهائي. عند إعادة حفظ مسودة محمّلة
  /// (`replaceDraft`) تُحذف سطور المسودة القديمة بنفس المرجع أولًا.
  Future<SaveResult> saveReceipt({
    required String warehouse,
    required String supplier,
    required String date,
    required List<DocLineInput> lines,
    String refNo = '',
    String invoiceNo = '',
    String committee = '',
    String supervision = '',
    String audit = '',
    String notes = '',
    bool draft = false,
    bool replaceDraft = false,
    String createdBy = '',
  }) async {
    if (lines.isEmpty) return const SaveResult(ok: false, error: '✖ القائمة فارغة — أضف صنفًا واحدًا على الأقل');
    if (warehouse.isEmpty) return const SaveResult(ok: false, error: '✖ اختر المستودع (أو أضف واحدًا بزر ➕)');
    final frozen = await frozenMessage(warehouse);
    if (frozen != null) return SaveResult(ok: false, error: frozen);
    final ref = refNo.isNotEmpty ? refNo : await nextRef('receipts', 'و-');
    await db.transaction(() async {
      if (replaceDraft) {
        await (db.delete(db.receipts)..where((t) => t.refNo.equals(ref) & t.status.equals('DRAFT'))).go();
      }
      for (final l in lines) {
        await db.into(db.receipts).insert(ReceiptsCompanion.insert(
              id: _newId('rc'),
              refNo: Value(ref),
              date: Value(date),
              warehouse: Value(warehouse),
              itemId: Value(l.itemId),
              itemCode: Value(l.itemCode),
              itemName: Value(l.itemName),
              unitName: Value(l.unitName),
              factor: Value(l.factor),
              qty: Value(l.qty),
              baseQty: Value(l.baseQty),
              status: Value(draft ? 'DRAFT' : 'COMPLETED'),
              notes: Value(l.notes.isEmpty ? notes : l.notes),
              createdBy: Value(createdBy),
              supplier: Value(supplier),
              invoiceNo: Value(invoiceNo),
              committee: Value(committee),
              supervision: Value(supervision),
              audit: Value(audit),
              cylinderAction: Value(l.cylinderAction),
            ));
      }
    });
    await _auditSave(
      action: draft ? 'RECEIPT_DRAFT_SAVED' : 'RECEIPT_COMPLETED',
      entityType: 'receipt',
      summary: draft ? 'حفظ مسودة سند وارد' : 'اعتماد سند وارد',
      refNo: ref,
      warehouse: warehouse,
      target: supplier,
      status: draft ? 'DRAFT' : 'COMPLETED',
      lines: lines,
      actorEmail: createdBy,
    );
    return SaveResult(ok: true, refNo: ref);
  }

  /// `stockErrorFromMap` بعد تغليف stock-ledger.js: رسالة عدم كفاية رصيد المستودع.
  static String stockError(Item? item, String warehouse, double have, double need) =>
      '✖ رصيد «${item?.name ?? ''}» في مستودع «$warehouse» لا يكفي '
      '(${_nfPlain(have)} ${item?.baseUnit ?? ''} متاح، المطلوب ${_nfPlain(need)})';

  static String _nfPlain(double v) => nf((v * 1000).round() / 1000);

  /// `hasRefConflict(col, ref, excludeStatus)` — يوجد مستند بنفس المرجع بحالة غير المستثناة.
  Future<bool> hasRefConflict(String table, String ref, String excludeStatus) async {
    final rows = await db
        .customSelect('SELECT status FROM $table WHERE ref_no = ? LIMIT 20', variables: [Variable.withString(ref)])
        .get();
    return rows.any((r) => excludeStatus.isEmpty || r.data['status'] != excludeStatus);
  }

  /// كتابة حدث الحفظ في سجل التدقيق بنفس أسماء أحداث الويب (`auditWrite`).
  Future<void> _auditSave({
    required String action,
    required String entityType,
    required String summary,
    required String refNo,
    required String warehouse,
    required String target,
    required String status,
    required List<DocLineInput> lines,
    String risk = 'normal',
    String actorEmail = '',
    Map<String, dynamic> extra = const {},
  }) =>
      AuditRepo(db).write(action, entityType, summary, actorEmail: actorEmail, details: {
        'refNo': refNo,
        'warehouse': warehouse,
        'target': target,
        'status': status,
        'itemCount': lines.length,
        'totalBaseQty': lines.fold<double>(0, (a, l) => a + l.baseQty),
        'risk': risk,
        ...extra,
      });

  Future<SaveResult> saveIssue({
    required String warehouse,
    required String recipientDisplay,
    required String date,
    required List<DocLineInput> lines,
    int targetType = 0,
    String unitId = '',
    String facilityId = '',
    double soldierCount = 0,
    int durationDays = 1,
    String refNo = '',
    String notes = '',
    String status = 'COMPLETED',
    String createdBy = '',
  }) async {
    if (lines.isEmpty) return const SaveResult(ok: false, error: '✖ أضف صنفًا واحدًا على الأقل');
    if (warehouse.isEmpty) return const SaveResult(ok: false, error: '✖ اختر المستودع');
    final frozenMsg = await frozenMessage(warehouse);
    if (frozenMsg != null) return SaveResult(ok: false, error: frozenMsg);

    if (status == 'COMPLETED') {
      final check = (await ledger()).check(
        warehouse: warehouse,
        requiredBaseQty: _sumByItem(lines),
      );
      if (!check.ok) {
        final item = await (db.select(db.items)..where((t) => t.id.equals(check.itemId))).getSingleOrNull();
        return SaveResult(ok: false, error: stockError(item, warehouse, check.available, check.requested));
      }
    }

    final ref = refNo.isNotEmpty ? refNo : await nextRef('issues', 'ص-');
    await db.transaction(() async {
      for (final l in lines) {
        await db.into(db.issues).insert(IssuesCompanion.insert(
              id: _newId('is'),
              refNo: Value(ref),
              date: Value(date),
              warehouse: Value(warehouse),
              itemId: Value(l.itemId),
              itemCode: Value(l.itemCode),
              itemName: Value(l.itemName),
              unitName: Value(l.unitName),
              factor: Value(l.factor),
              qty: Value(l.qty),
              baseQty: Value(l.baseQty),
              status: Value(status),
              notes: Value(l.notes.isEmpty ? notes : l.notes),
              createdBy: Value(createdBy),
              targetType: Value(targetType),
              recipientDisplay: Value(recipientDisplay),
              unitId: Value(unitId),
              facilityId: Value(facilityId),
              beneficiaryUnitId: Value(l.beneficiaryUnitId),
              beneficiaryUnitName: Value(l.beneficiaryUnitName),
              soldierCount: Value(soldierCount),
              durationDays: Value(durationDays),
              cylinderAction: Value(l.cylinderAction),
            ));
      }
    });
    await _auditSave(
      action: status == 'COMPLETED'
          ? 'ISSUE_COMPLETED'
          : (status == 'ORDER' ? 'ISSUE_ORDER_CREATED' : 'ISSUE_DRAFT_SAVED'),
      entityType: 'issue',
      summary: status == 'COMPLETED'
          ? 'اعتماد سند صرف وخصم الرصيد'
          : (status == 'ORDER' ? 'إرسال أمر صرف للمستودع' : 'حفظ مسودة صرف'),
      refNo: ref,
      warehouse: warehouse,
      target: recipientDisplay,
      status: status,
      lines: lines,
      actorEmail: createdBy,
      risk: (status == 'COMPLETED' || status == 'ORDER') ? 'sensitive' : 'normal',
    );
    return SaveResult(ok: true, refNo: ref);
  }

  Future<SaveResult> saveTransfer({
    required String fromWarehouse,
    required String toWarehouse,
    required String date,
    required List<DocLineInput> lines,
    String campId = '',
    String campName = '',
    double strength = 0,
    int durationDays = 1,
    String refNo = '',
    String notes = '',
    String createdBy = '',
  }) async {
    if (lines.isEmpty) return const SaveResult(ok: false, error: 'لا توجد أصناف في السند');
    if (fromWarehouse.isEmpty || toWarehouse.isEmpty) {
      return const SaveResult(ok: false, error: 'اختر المستودع المصدر والهدف');
    }
    if (fromWarehouse == toWarehouse) {
      return const SaveResult(ok: false, error: 'لا يمكن التحويل إلى نفس المستودع');
    }

    final check = (await ledger()).check(
      warehouse: fromWarehouse,
      requiredBaseQty: _sumByItem(lines),
    );
    if (!check.ok) {
      return SaveResult(
        ok: false,
        error: 'رصيد المستودع «$fromWarehouse» لا يكفي (${_fmt(check.available)} متاح)',
      );
    }

    final frozen = await frozenOrder(fromWarehouse);
    if (frozen != null) {
      return SaveResult(ok: false, error: 'المستودع مجمّد بأمر الجرد $frozen — لا تُقبل أي حركة حتى اعتماده');
    }
    final ref = refNo.isNotEmpty ? refNo : await nextRef('transfers', 'ح-');
    await db.transaction(() async {
      for (final l in lines) {
        await db.into(db.transfers).insert(TransfersCompanion.insert(
              id: _newId('tr'),
              refNo: Value(ref),
              date: Value(date),
              warehouse: Value(fromWarehouse),
              itemId: Value(l.itemId),
              itemCode: Value(l.itemCode),
              itemName: Value(l.itemName),
              unitName: Value(l.unitName),
              factor: Value(l.factor),
              qty: Value(l.qty),
              baseQty: Value(l.baseQty),
              status: const Value('PENDING'),
              notes: Value(l.notes.isEmpty ? notes : l.notes),
              createdBy: Value(createdBy),
              destWarehouse: Value(toWarehouse),
              campId: Value(campId),
              campName: Value(campName),
              strength: Value(strength),
              durationDays: Value(durationDays),
            ));
      }
    });
    await _auditSave(
      action: 'TRANSFER_SENT',
      entityType: 'transfer',
      summary: 'إرسال تحويل مخزني معلق',
      refNo: ref,
      warehouse: fromWarehouse,
      target: toWarehouse,
      status: 'PENDING',
      lines: lines,
      actorEmail: createdBy,
      risk: 'sensitive',
    );
    return SaveResult(ok: true, refNo: ref);
  }

  /// استلام تحويل معلّق في المستودع الهدف (يضيف الرصيد هناك).
  Future<void> receiveTransfer(String refNo, {String receivedBy = ''}) async {
    final rows = await (db.select(db.transfers)..where((t) => t.refNo.equals(refNo))).get();
    await (db.update(db.transfers)..where((t) => t.refNo.equals(refNo) & t.status.equals('PENDING')))
        .write(const TransfersCompanion(status: Value('RECEIVED')));
    if (rows.isNotEmpty) {
      await AuditRepo(db).log(
        action: 'transfer.receive',
        entityType: 'تحويل مخزني',
        summary: 'استلام التحويل $refNo في مستودع ${rows.first.destWarehouse}',
        details: {'refNo': refNo, 'from': rows.first.warehouse, 'to': rows.first.destWarehouse},
        actorEmail: receivedBy,
      );
    }
  }

  Future<void> rejectTransfer(String refNo, String reason, {String rejectedBy = ''}) async {
    await (db.update(db.transfers)..where((t) => t.refNo.equals(refNo) & t.status.equals('PENDING')))
        .write(TransfersCompanion(status: const Value('REJECTED'), rejectReason: Value(reason)));
    await AuditRepo(db).log(
      action: 'transfer.reject',
      entityType: 'تحويل مخزني',
      summary: 'رفض التحويل $refNo — $reason',
      details: {'refNo': refNo, 'reason': reason},
      risk: AuditRepo.riskHigh,
      actorEmail: rejectedBy,
    );
  }

  /// التحويلات المعلّقة الواردة إلى مستودعات المستخدم (بانتظار الاستلام).
  Future<List<Transfer>> pendingIncoming({List<String>? scope}) async {
    final rows = await (db.select(db.transfers)..where((t) => t.status.equals('PENDING'))).get();
    final filtered =
        scope == null ? rows : rows.where((t) => scope.contains(t.destWarehouse)).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  /// أوامر الصرف التي تنتظر الاعتماد (لا أثر لها على الرصيد قبل اعتمادها).
  Future<List<Issue>> issueOrders({List<String>? scope}) async {
    final rows = await (db.select(db.issues)..where((t) => t.status.equals('ORDER'))).get();
    final filtered = scope == null ? rows : rows.where((i) => scope.contains(i.warehouse)).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  /// اعتماد أمر صرف: يتحول إلى سند منصرف بعد التأكد من كفاية رصيد المستودع.
  Future<SaveResult> approveIssueOrder(String refNo, {String approvedBy = ''}) async {
    final rows = await (db.select(db.issues)..where((t) => t.refNo.equals(refNo))).get();
    if (rows.isEmpty) return const SaveResult(ok: false, error: 'أمر الصرف غير موجود');
    final warehouse = rows.first.warehouse;

    final frozen = await frozenOrder(warehouse);
    if (frozen != null) {
      return SaveResult(ok: false, error: 'المستودع مجمّد بأمر الجرد $frozen');
    }

    final required = <String, double>{};
    for (final r in rows) {
      required[r.itemId] = _round((required[r.itemId] ?? 0) + r.baseQty);
    }
    final check = (await ledger()).check(warehouse: warehouse, requiredBaseQty: required);
    if (!check.ok) {
      final item =
          await (db.select(db.items)..where((t) => t.id.equals(check.itemId))).getSingleOrNull();
      return SaveResult(
        ok: false,
        error: 'رصيد «${item?.name ?? check.itemId}» في مستودع «$warehouse» لا يكفي '
            '(${_fmt(check.available)} متاح، المطلوب ${_fmt(check.requested)})',
      );
    }

    await (db.update(db.issues)..where((t) => t.refNo.equals(refNo) & t.status.equals('ORDER')))
        .write(const IssuesCompanion(status: Value('COMPLETED')));
    await AuditRepo(db).log(
      action: 'issue.approve',
      entityType: 'أمر صرف',
      summary: 'اعتماد أمر الصرف $refNo من مستودع $warehouse',
      details: {'refNo': refNo, 'warehouse': warehouse},
      actorEmail: approvedBy,
    );
    return SaveResult(ok: true, refNo: refNo);
  }

  Future<void> cancelIssueOrder(String refNo, String reason, {String cancelledBy = ''}) async {
    await (db.update(db.issues)..where((t) => t.refNo.equals(refNo) & t.status.equals('ORDER')))
        .write(IssuesCompanion(status: const Value('CANCELLED'), notes: Value('ملغى: $reason')));
    await AuditRepo(db).log(
      action: 'issue.cancelOrder',
      entityType: 'أمر صرف',
      summary: 'إلغاء أمر الصرف $refNo — $reason',
      details: {'refNo': refNo, 'reason': reason},
      risk: AuditRepo.riskHigh,
      actorEmail: cancelledBy,
    );
  }

  Future<SaveResult> saveReturn({
    required String warehouse,
    required String party,
    required String date,
    required List<DocLineInput> lines,
    String type = 'FROM_UNIT', // FROM_UNIT | TO_SUPPLIER
    String condition = 'صالحة',
    String origRef = '',
    String refNo = '',
    String notes = '',
    String createdBy = '',
  }) async {
    if (lines.isEmpty) return const SaveResult(ok: false, error: '✖ أضف صنفًا واحدًا على الأقل');
    if (warehouse.isEmpty) return const SaveResult(ok: false, error: '✖ اختر المستودع');
    final frozenMsg = await frozenMessage(warehouse);
    if (frozenMsg != null) return SaveResult(ok: false, error: frozenMsg);

    if (type == 'TO_SUPPLIER') {
      final check = (await ledger()).check(
        warehouse: warehouse,
        requiredBaseQty: _sumByItem(lines),
      );
      if (!check.ok) {
        final item = await (db.select(db.items)..where((t) => t.id.equals(check.itemId))).getSingleOrNull();
        return SaveResult(
          ok: false,
          error: '✖ الرصيد المتاح من «${item?.name ?? ''}» لا يكفي لإرجاعه للمورّد '
              '(${_fmt(check.available)} ${item?.baseUnit ?? ''})',
        );
      }
    }

    final ref = refNo.isNotEmpty ? refNo : await nextRef('returns', 'رد-');
    await db.transaction(() async {
      for (final l in lines) {
        await db.into(db.returns).insert(ReturnsCompanion.insert(
              id: _newId('re'),
              refNo: Value(ref),
              date: Value(date),
              warehouse: Value(warehouse),
              itemId: Value(l.itemId),
              itemCode: Value(l.itemCode),
              itemName: Value(l.itemName),
              unitName: Value(l.unitName),
              factor: Value(l.factor),
              qty: Value(l.qty),
              baseQty: Value(l.baseQty),
              notes: Value(l.notes.isEmpty ? notes : l.notes),
              createdBy: Value(createdBy),
              party: Value(party),
              type: Value(type),
              condition: Value(condition),
              origRef: Value(origRef),
            ));
      }
    });
    final toSupplier = type == 'TO_SUPPLIER';
    final good = condition != 'تالفة';
    await _auditSave(
      action: toSupplier ? 'RETURN_TO_SUPPLIER' : 'RETURN_FROM_UNIT',
      entityType: 'return',
      summary: toSupplier
          ? 'تسجيل مرتجع إلى المورد وخصم الرصيد'
          : (good ? 'تسجيل مرتجع من وحدة وإضافة الرصيد' : 'تسجيل مرتجع من وحدة كتالف'),
      refNo: ref,
      warehouse: warehouse,
      target: party,
      status: toSupplier ? 'TO_SUPPLIER' : (good ? 'GOOD' : 'DAMAGED'),
      lines: lines,
      risk: toSupplier || !good ? 'sensitive' : 'normal',
      actorEmail: createdBy,
      extra: toSupplier ? {'origRef': origRef} : const {},
    );
    return SaveResult(ok: true, refNo: ref);
  }

  /// رقم مرجع تسلسلي بنفس نمط النظام الحالي: «و-000001».
  Future<String> nextRef(String table, String prefix) async {
    final rows = await db.customSelect('SELECT ref_no AS r FROM $table').get();
    var max = 0;
    for (final row in rows) {
      final v = (row.data['r'] ?? '').toString();
      final m = RegExp(r'(\d+)').firstMatch(v);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > max) max = n;
      }
    }
    return '$prefix${(max + 1).toString().padLeft(6, '0')}';
  }

  static Map<String, double> _sumByItem(List<DocLineInput> lines) {
    final out = <String, double>{};
    for (final l in lines) {
      if (l.itemId.isEmpty) continue;
      out[l.itemId] = (out[l.itemId] ?? 0) + l.baseQty;
    }
    return out;
  }

  static double _round(double v) => (v * 1000).round() / 1000;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static String _newId(String prefix) =>
      Ids.next(prefix);
}
