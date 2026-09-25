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

/// طلبيات الإعاشة: الطلب والاعتماد والربط بالمستند المنفِّذ.
///
/// **الطلبية لا تحرّك المخزون.** هي طلبٌ وإذنٌ به، لا حركة. ومن يحرّك الرصيد
/// مستندٌ مستقل له فحوصه وتجميده وسجله:
///
/// * **مخزن فرعي** ← سند تحويل من المخزن الرئيسي، يُنشئه أمين المخزن من شاشة
///   التحويل بخيار «سحب من طلبية» بعد أن يأذن ركن الإمداد.
/// * **المخزن الرئيسي** ← سند توريد يأتي بالإعاشة من خارج الفرقة، تُطابَق به
///   الطلبية لاحقًا.
///
/// وكان الاستلام قبلُ يولّد سند استلام في المستودع الطالب بلا أن يُنقص أحدًا،
/// فيزيد مخزون النظام من العدم كلما حُوِّلت بضاعةٌ بين مستودعين. فصار التنفيذ
/// **ربطًا** بمستندٍ قائم عبر [fulfill]، لا توليدًا لحركة.
class RationRepo {
  RationRepo(this.db);

  final AppDatabase db;

  // ───────────────────────── دليل الجهات

  Future<List<SupplyAuthority>> authorities({bool onlyActive = false}) async {
    final q = db.select(db.supplyAuthorities);
    if (onlyActive) q.where((t) => t.active.equals(true));
    final rows = await q.get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  Future<RationResult> saveAuthority({
    String? id,
    required String name,
    String title = '',
    String notes = '',
    bool active = true,
    String actor = '',
  }) async {
    if (name.trim().isEmpty) {
      return const RationResult(ok: false, error: '✖ اسم الجهة مطلوب');
    }
    final all = await authorities();
    if (all.any((a) => a.id != id && a.name.trim() == name.trim())) {
      return const RationResult(ok: false, error: '✖ توجد جهة بهذا الاسم');
    }
    final newId = id ?? Ids.next('auth');
    await db
        .into(db.supplyAuthorities)
        .insertOnConflictUpdate(SupplyAuthoritiesCompanion.insert(
          id: newId,
          name: name.trim(),
          title: Value(title.trim()),
          notes: Value(notes.trim()),
          active: Value(active),
        ));
    await AuditRepo(db).log(
      action: id == null ? 'authority.create' : 'authority.update',
      entityType: 'جهة إمداد',
      summary: '${id == null ? 'إضافة' : 'تعديل'} الجهة ${name.trim()}',
      details: {'authorityId': newId},
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: newId);
  }

  /// الجهة لا تُحذف إن عُلّقت بها طلبية: حذفها يترك طلبيةً بلا مَن طُلب منه.
  Future<RationResult> deleteAuthority(String id, {String actor = ''}) async {
    final used = await (db.select(db.rationOrders)
          ..where((t) => t.authorityId.equals(id))
          ..limit(1))
        .get();
    if (used.isNotEmpty) {
      return const RationResult(
        ok: false,
        error: '✖ لا تُحذف جهة عليها طلبيات — عطّلها بدل حذفها',
      );
    }
    await (db.delete(db.supplyAuthorities)..where((t) => t.id.equals(id))).go();
    await AuditRepo(db).log(
      action: 'authority.delete',
      entityType: 'جهة إمداد',
      summary: 'حذف جهة إمداد',
      details: {'authorityId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return const RationResult(ok: true);
  }

  // ───────────────────────── قراءة

  /// اسم المخزن الرئيسي، أو فراغ إن لم يُعيَّن.
  Future<String> mainWarehouseName() async {
    final rows = await (db.select(db.warehouses)
          ..where((t) => t.isMain.equals(true))
          ..limit(1))
        .get();
    return rows.isEmpty ? '' : rows.first.name;
  }

  /// الطلبيات المعتمدة الجاهزة للتحويل من [warehouse] — ما يسحبه أمين المخزن.
  Future<List<RationOrderFull>> readyForTransfer(String warehouse) async {
    if (warehouse.trim().isEmpty) return const [];
    final rows = await (db.select(db.rationOrders)
          ..where((t) =>
              t.orderKind.equals(RationKind.branch) &
              t.status.equals(RationStatus.approved) &
              t.supplyingWarehouse.equals(warehouse.trim()))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return [
      for (final o in rows) RationOrderFull(order: o, lines: await lines(o.id)),
    ];
  }

  /// طلبيات المخزن الرئيسي المعتمدة التي تنتظر مطابقةً بسند توريد.
  Future<List<RationOrder>> awaitingReceiptMatch() =>
      (db.select(db.rationOrders)
            ..where((t) =>
                t.orderKind.equals(RationKind.main) &
                t.status.equals(RationStatus.approved))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

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
    String supplyingWarehouse = '',
    required String date,
    required List<RationLineInput> lines,
    String kind = RationKind.branch,
    String authorityId = '',
    String authorityName = '',
    String requiredDate = '',
    String priority = RationPriority.normal,
    String notes = '',
    String actor = '',
  }) async {
    final main = await mainWarehouseName();
    // المخزن الفرعي يطلب من الرئيسي دائمًا، فيُملأ عنه بدل أن يُترك لاختياره.
    final supplying = RationKind.isMain(kind)
        ? ''
        : (supplyingWarehouse.trim().isEmpty ? main : supplyingWarehouse.trim());
    final routeError = RationRules.validateRouting(
      kind: kind,
      requesting: requestingWarehouse,
      supplying: supplying,
      authorityId: authorityId,
      mainWarehouse: main,
    );
    if (routeError != null) {
      return RationResult(ok: false, error: '✖ $routeError');
    }

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
            supplyingWarehouse: Value(supplying),
            orderKind: Value(kind),
            authorityId: Value(RationKind.isMain(kind) ? authorityId : ''),
            authorityName: Value(RationKind.isMain(kind) ? authorityName : ''),
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

  /// تنفيذ الطلبية: **ربطها بمستندٍ قائم، لا توليدُ حركة**.
  ///
  /// كان هذا `receive` فيُنشئ سند استلام في المستودع الطالب بلا أن يُنقص
  /// المورِّد شيئًا — فيزيد مخزون النظام من العدم كلما حُوِّلت بضاعة بين
  /// مستودعين، ويبقى الصنف في رصيد الاثنين معًا.
  ///
  /// أما الآن فالحركة يصنعها مستندها: سندُ تحويلٍ يخرج من الرئيسي ويدخل
  /// الفرعي، أو سندُ توريدٍ يأتي من خارج الفرقة. وهنا تُربط الطلبية بمرجعه
  /// فيُعرف ما وصل مما طُلب.
  Future<RationResult> fulfill(
    String id, {
    required String ref,
    required String kind,
    String date = '',
    String actor = '',
  }) async {
    final full = await byId(id);
    if (full == null) {
      return const RationResult(ok: false, error: '✖ الطلبية غير موجودة');
    }
    if (!RationRules.canFulfill(full.order.status)) {
      return RationResult(
        ok: false,
        error: '✖ لا تُنفَّذ طلبية ${RationStatus.label(full.order.status)} — '
            'تُعتمد أولًا',
      );
    }
    if (ref.trim().isEmpty) {
      return const RationResult(ok: false, error: '✖ مرجع المستند مطلوب');
    }
    final approved = full.lines.where((l) => l.approvedQty > 0).toList();
    if (approved.isEmpty) {
      return const RationResult(
          ok: false, error: '✖ لا سطر معتمَد بكمية — راجع الاعتماد');
    }

    final stamp = date.trim().isEmpty
        ? DateTime.now().toIso8601String().substring(0, 10)
        : date.trim();
    await db.transaction(() async {
      for (final l in full.lines) {
        await (db.update(db.rationOrderLines)..where((t) => t.id.equals(l.id)))
            .write(RationOrderLinesCompanion(receivedQty: Value(l.approvedQty)));
      }
      await (db.update(db.rationOrders)..where((t) => t.id.equals(id))).write(
        RationOrdersCompanion(
          status: const Value(RationStatus.received),
          receivedBy: Value(actor),
          fulfillRef: Value(ref.trim()),
          fulfillKind: Value(kind),
          fulfillDate: Value(stamp),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    await AuditRepo(db).log(
      action: 'ration.fulfill',
      entityType: 'طلبية إعاشة',
      summary: 'تنفيذ الطلبية ${full.order.refNo} بـ'
          '${RationFulfillKind.label(kind)} ${ref.trim()}',
      details: {
        'orderId': id,
        'ref': ref.trim(),
        'kind': kind,
        'lines': approved.length,
      },
      actorEmail: actor,
    );
    return RationResult(ok: true, refNo: full.order.refNo);
  }

  /// ربط طلبية مخزن فرعي بسند التحويل الذي نفّذها.
  Future<RationResult> linkTransfer(
    String id, {
    required String transferRef,
    String date = '',
    String actor = '',
  }) =>
      fulfill(id,
          ref: transferRef,
          kind: RationFulfillKind.transfer,
          date: date,
          actor: actor);

  /// مطابقة طلبية المخزن الرئيسي بسند التوريد الذي جاء بالإعاشة.
  Future<RationResult> matchReceipt(
    String id, {
    required String receiptRef,
    String date = '',
    String actor = '',
  }) =>
      fulfill(id,
          ref: receiptRef,
          kind: RationFulfillKind.receipt,
          date: date,
          actor: actor);

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
