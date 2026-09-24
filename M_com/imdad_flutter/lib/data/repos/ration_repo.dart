import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/ration_order.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import 'movements_repo.dart';

/// سطر طلبية كما تُدخله الشاشة.
class RationLineInput {
  const RationLineInput({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.unitName,
    required this.factor,
    required this.requestedQty,
    this.approvedQty = 0,
    this.notes = '',
  });

  final String itemId;
  final String itemCode;
  final String itemName;
  final String unitName;
  final double factor;
  final double requestedQty;
  final double approvedQty;
  final String notes;

  RationLineDraft get draft =>
      RationLineDraft(itemId: itemId, requestedQty: requestedQty, approvedQty: approvedQty);
}

/// طلبية مع سطورها — ما تعرضه الشاشة وما تطبعه.
class RationOrderFull {
  const RationOrderFull({required this.order, required this.lines});

  final RationOrder order;
  final List<RationOrderLine> lines;

  double get totalRequested => lines.fold(0, (s, l) => s + l.requestedQty);
  double get totalApproved => lines.fold(0, (s, l) => s + l.approvedQty);
}

class RationResult {
  const RationResult({required this.ok, this.error = '', this.refNo = ''});

  final bool ok;
  final String error;
  final String refNo;
}

/// طلبيات الإعاشة: الطلب والاعتماد والاستلام.
///
/// **الاستلام يولّد سند استلام حقيقي.** طلبيةٌ تُعلَّم «مستلمة» بلا أن يتحرك
/// الرصيد ورقةٌ تكذب على صاحبها: يظن المستودع أن البضاعة دخلت وهي لم تدخل،
/// فيصرف ما لا يملك. لذلك يمرّ الاستلام بـ[MovementsRepo.saveReceipt] نفسه
/// الذي يمرّ به أي استلام آخر — بفحوصه وتجميده وسجله.
class RationRepo {
  RationRepo(this.db);

  final AppDatabase db;

  // ───────────────────────── قراءة

  Future<List<RationOrder>> orders({
    String status = '',
    List<String>? scope,
  }) async {
    final q = db.select(db.rationOrders);
    if (status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (scope != null) {
      // الفرع يرى ما طلبه وما طُلب منه: طرفا الطلبية كلاهما صاحب شأن.
      q.where((t) =>
          t.requestingWarehouse.isIn(scope) | t.supplyingWarehouse.isIn(scope));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.get();
  }

  Future<RationOrderFull?> byId(String id) async {
    final rows = await (db.select(db.rationOrders)..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty) return null;
    return RationOrderFull(order: rows.first, lines: await lines(id));
  }

  Future<List<RationOrderLine>> lines(String orderId) =>
      (db.select(db.rationOrderLines)..where((t) => t.orderId.equals(orderId))).get();

  /// عدد الطلبيات التي تنتظر إجراءً — تُعرض في لوحة المدير.
  Future<int> openCount({List<String>? scope}) async {
    final rows = await orders(scope: scope);
    return rows.where((o) => RationStatus.open.contains(o.status)).length;
  }

  // ───────────────────────── كتابة

  /// حفظ مسودة أو تعديلها. السطور تُستبدل كاملةً — الطلبية وحدة واحدة لا
  /// سطور مستقلة، ودمج التعديل سطرًا سطرًا يترك سطورًا يتيمة عند الحذف.
  Future<RationResult> save({
    String? id,
    required String requestingWarehouse,
    required String supplyingWarehouse,
    required String date,
    required List<RationLineInput> lines,
    String requiredDate = '',
    String priority = RationPriority.normal,
    String notes = '',
    String actor = '',
  }) async {
    final whError = RationRules.validateWarehouses(
      requesting: requestingWarehouse,
      supplying: supplyingWarehouse,
    );
    if (whError != null) return RationResult(ok: false, error: '✖ $whError');

    final dateError = RationRules.validateRequiredDate(date, requiredDate);
    if (dateError != null) return RationResult(ok: false, error: '✖ $dateError');

    final lineError = RationRules.validateLines([for (final l in lines) l.draft]);
    if (lineError != null) return RationResult(ok: false, error: '✖ $lineError');

    if (id != null) {
      final existing = await byId(id);
      if (existing == null) return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
      if (!RationRules.canEdit(existing.order.status)) {
        return RationResult(
          ok: false,
          error: '✖ لا تُعدَّل طلبية ${RationStatus.label(existing.order.status)}',
        );
      }
    }

    final orderId = id ?? Ids.next('rq');
    final ref = id == null
        ? await MovementsRepo(db).nextRef('ration_orders', 'ط-')
        : (await byId(orderId))!.order.refNo;

    await db.transaction(() async {
      await db.into(db.rationOrders).insertOnConflictUpdate(RationOrdersCompanion.insert(
            id: orderId,
            refNo: Value(ref),
            requestingWarehouse: Value(requestingWarehouse),
            supplyingWarehouse: Value(supplyingWarehouse),
            date: Value(date),
            requiredDate: Value(requiredDate),
            status: const Value(RationStatus.draft),
            priority: Value(priority),
            notes: Value(notes),
            createdBy: Value(actor),
            updatedAt: Value(id == null ? null : DateTime.now()),
          ));
      await (db.delete(db.rationOrderLines)..where((t) => t.orderId.equals(orderId))).go();
      for (final l in lines) {
        await db.into(db.rationOrderLines).insert(RationOrderLinesCompanion.insert(
              id: Ids.next('rql'),
              orderId: orderId,
              itemId: Value(l.itemId),
              itemCode: Value(l.itemCode),
              itemName: Value(l.itemName),
              unitName: Value(l.unitName),
              factor: Value(l.factor),
              requestedQty: Value(l.requestedQty),
              approvedQty: Value(l.approvedQty),
              notes: Value(l.notes),
            ));
      }
    });

    await AuditRepo(db).log(
      action: id == null ? 'ration.create' : 'ration.update',
      entityType: 'طلبية إعاشة',
      summary: '${id == null ? 'إنشاء' : 'تعديل'} الطلبية $ref',
      details: {'orderId': orderId, 'lines': lines.length},
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: ref);
  }

  Future<RationResult> submit(String id, {String actor = ''}) =>
      _transition(id, 'submit', actor: actor, summary: 'إرسال');

  /// الاعتماد قد يقلّص الكميات: [approved] تربط معرّف السطر بالكمية المعتمدة،
  /// وما لم يُذكر فيها يُعتمد بكامل المطلوب.
  Future<RationResult> approve(
    String id, {
    Map<String, double> approved = const {},
    String actor = '',
  }) async {
    final full = await byId(id);
    if (full == null) return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
    if (!RationRules.canApprove(full.order.status)) {
      return RationResult(
        ok: false,
        error: '✖ لا تُعتمد طلبية ${RationStatus.label(full.order.status)}',
      );
    }

    final drafts = [
      for (final l in full.lines)
        RationLineDraft(
          itemId: l.itemId,
          requestedQty: l.requestedQty,
          approvedQty: approved[l.id] ?? l.requestedQty,
        ),
    ];
    final error = RationRules.validateApproved(drafts);
    if (error != null) return RationResult(ok: false, error: '✖ $error');

    await db.transaction(() async {
      for (final l in full.lines) {
        await (db.update(db.rationOrderLines)..where((t) => t.id.equals(l.id)))
            .write(RationOrderLinesCompanion(
          approvedQty: Value(approved[l.id] ?? l.requestedQty),
        ));
      }
      await (db.update(db.rationOrders)..where((t) => t.id.equals(id))).write(
        RationOrdersCompanion(
          status: const Value(RationStatus.approved),
          approvedBy: Value(actor),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    await AuditRepo(db).log(
      action: 'ration.approve',
      entityType: 'طلبية إعاشة',
      summary: 'اعتماد الطلبية ${full.order.refNo}',
      details: {'orderId': id},
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: full.order.refNo);
  }

  /// الاستلام: يولّد سند استلام في المستودع الطالب ثم يقفل الطلبية.
  ///
  /// الكمية المستلمة هي المعتمدة، والصفر يُتخطّى: سطرٌ اعتُمد بصفر لم يُورَّد،
  /// وإدخاله في السند يضيف حركةً بلا بضاعة.
  Future<RationResult> receive(String id, {String actor = ''}) async {
    final full = await byId(id);
    if (full == null) return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
    if (!RationRules.canReceive(full.order.status)) {
      return RationResult(
        ok: false,
        error: '✖ لا تُستلم طلبية ${RationStatus.label(full.order.status)} — '
            'تُعتمد أولًا',
      );
    }

    final docLines = [
      for (final l in full.lines)
        if (l.approvedQty > 0)
          DocLineInput(
            itemId: l.itemId,
            itemCode: l.itemCode,
            itemName: l.itemName,
            unitName: l.unitName,
            factor: l.factor,
            qty: l.approvedQty,
            notes: l.notes,
          ),
    ];
    if (docLines.isEmpty) {
      return const RationResult(ok: false, error: '✖ لا سطر معتمَد بكمية — راجع الاعتماد');
    }

    // السند يمرّ بالمسار المعتاد: تجميد المستودع وفحوصه وسجله كلها تنطبق.
    final saved = await MovementsRepo(db).saveReceipt(
      warehouse: full.order.requestingWarehouse,
      supplier: 'طلبية ${full.order.refNo} — ${full.order.supplyingWarehouse}',
      date: DateTime.now().toIso8601String().substring(0, 10),
      lines: docLines,
      notes: 'استلام طلبية إعاشة ${full.order.refNo}',
      createdBy: actor,
    );
    if (!saved.ok) return RationResult(ok: false, error: saved.error);

    await db.transaction(() async {
      for (final l in full.lines) {
        await (db.update(db.rationOrderLines)..where((t) => t.id.equals(l.id)))
            .write(RationOrderLinesCompanion(receivedQty: Value(l.approvedQty)));
      }
      await (db.update(db.rationOrders)..where((t) => t.id.equals(id))).write(
        RationOrdersCompanion(
          status: const Value(RationStatus.received),
          receivedBy: Value(actor),
          receiptRef: Value(saved.refNo),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    await AuditRepo(db).log(
      action: 'ration.receive',
      entityType: 'طلبية إعاشة',
      summary: 'استلام الطلبية ${full.order.refNo} بالسند ${saved.refNo}',
      details: {'orderId': id, 'receiptRef': saved.refNo, 'lines': docLines.length},
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: saved.refNo);
  }

  Future<RationResult> reject(String id, {required String reason, String actor = ''}) async {
    final error = RationRules.validateRejectReason(reason);
    if (error != null) return RationResult(ok: false, error: '✖ $error');
    return _transition(
      id,
      'reject',
      actor: actor,
      summary: 'رفض',
      extra: RationOrdersCompanion(rejectReason: Value(reason.trim())),
      risk: AuditRepo.riskHigh,
    );
  }

  Future<RationResult> delete(String id, {String actor = ''}) async {
    final full = await byId(id);
    if (full == null) return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
    if (!RationRules.canDelete(full.order.status)) {
      return RationResult(
        ok: false,
        error: '✖ لا تُحذف طلبية ${RationStatus.label(full.order.status)} — '
            'أثرها المخزني قائم',
      );
    }
    await db.transaction(() async {
      await (db.delete(db.rationOrderLines)..where((t) => t.orderId.equals(id))).go();
      await (db.delete(db.rationOrders)..where((t) => t.id.equals(id))).go();
    });
    await AuditRepo(db).log(
      action: 'ration.delete',
      entityType: 'طلبية إعاشة',
      summary: 'حذف الطلبية ${full.order.refNo}',
      details: {'orderId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: full.order.refNo);
  }

  /// انتقال حالة تحكمه [RationRules.next] — لا حالة تُكتب إلا بإذنه.
  Future<RationResult> _transition(
    String id,
    String action, {
    required String actor,
    required String summary,
    RationOrdersCompanion? extra,
    String risk = AuditRepo.riskNormal,
  }) async {
    final full = await byId(id);
    if (full == null) return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
    final next = RationRules.next(full.order.status, action);
    if (next == null) {
      return RationResult(
        ok: false,
        error: '✖ لا يصحّ هذا الإجراء على طلبية ${RationStatus.label(full.order.status)}',
      );
    }
    await (db.update(db.rationOrders)..where((t) => t.id.equals(id))).write(
      (extra ?? const RationOrdersCompanion()).copyWith(
        status: Value(next),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'ration.$action',
      entityType: 'طلبية إعاشة',
      summary: '$summary الطلبية ${full.order.refNo}',
      details: {'orderId': id, 'to': next},
      risk: risk,
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: full.order.refNo);
  }
}
