import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import '../../domain/document_edit.dart';
import 'audit_repo.dart';
import 'movements_repo.dart';

/// سجل المستندات المحفوظة: استلام، صرف، تحويل، مرتجعات — مجمّعة برقم السند.
/// يدعم العرض والتعديل والإلغاء وفق قواعد documents-center.js:
/// التعديل يطبّق **فرق الكميات فقط**، والإلغاء يعكس أثر السند كاملًا.
enum DocKind { receipt, issue, transfer, returnDoc }

extension DocKindX on DocKind {
  String get label => switch (this) {
        DocKind.receipt => 'سند استلام',
        DocKind.issue => 'سند صرف',
        DocKind.transfer => 'تحويل مخزني',
        DocKind.returnDoc => 'مرتجع',
      };

  String get pageId => switch (this) {
        DocKind.receipt => 'receive',
        DocKind.issue => 'issue',
        DocKind.transfer => 'transfer',
        DocKind.returnDoc => 'returns',
      };

  DocumentType get docType => switch (this) {
        DocKind.receipt => DocumentType.receipt,
        DocKind.issue => DocumentType.issue,
        DocKind.transfer => DocumentType.transfer,
        DocKind.returnDoc => DocumentType.returnDoc,
      };
}

class DocumentLineRow {
  DocumentLineRow({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.factor,
    required this.qty,
    required this.baseQty,
    this.itemCode = '',
    this.notes = '',
    this.beneficiaryUnitId = '',
    this.beneficiaryUnitName = '',
    this.cylinderAction = '',
    this.expiryDate = '',
  });

  final String id;
  final String itemId;
  final String itemName;
  final String unitName;
  final double factor;
  double qty;
  double baseQty;
  String itemCode;
  String notes;
  String beneficiaryUnitId;
  String beneficiaryUnitName;
  String cylinderAction;

  /// تاريخ صلاحية الدفعة (سطر الوارد وحده). كان التعديل يُعيد إنشاء السطور بلا
  /// هذا الحقل فتضيع تنبيهات قرب الانتهاء بصمت (M-8).
  String expiryDate;
}

/// سطر واحد في سجل تعديلات السند (`editLog`).
class DocumentEditEntry {
  const DocumentEditEntry({required this.at, required this.by, required this.summary});

  final String at;
  final String by;
  final String summary;
}

class DocumentSummary {
  const DocumentSummary({
    required this.kind,
    required this.refNo,
    required this.date,
    required this.warehouse,
    required this.status,
    required this.party,
    required this.linesCount,
    this.destWarehouse = '',
    this.returnType = 'FROM_UNIT',
    this.condition = 'صالحة',
    this.createdBy = '',
    this.editCount = 0,
    this.notes = '',
    this.editedBy = '',
    this.cancelReason = '',
    this.cancelledBy = '',
    this.prevStatus = '',
    this.editLog = const [],
    this.totalBaseQty = 0,
  });

  final DocKind kind;
  final String refNo;
  final String date;
  final String warehouse;
  final String destWarehouse;
  final String status;

  /// الجهة: المورد أو المستلم أو المستودع المستلم أو جهة المرتجع.
  final String party;
  final int linesCount;
  final String returnType;
  final String condition;
  final String createdBy;
  final int editCount;
  final String notes;
  final String editedBy;
  final String cancelReason;
  final String cancelledBy;
  final String prevStatus;
  final List<DocumentEditEntry> editLog;
  final double totalBaseQty;

  DocumentContext get context => DocumentContext(
        type: kind.docType,
        status: status,
        returnType: returnType,
        condition: condition,
      );

  /// التحويل لا يُعدَّل بعد استلامه، والملغى لا يُعدَّل مطلقًا.
  bool get editable =>
      status != 'CANCELLED' && status != 'REJECTED' && context.editable;

  bool get live => status != 'CANCELLED' && status != 'REJECTED' && status != 'DRAFT';
}

class DocumentsRepo {
  DocumentsRepo(this.db);

  final AppDatabase db;

  /// كل المستندات مجمّعة برقم السند، الأحدث أولًا.
  Future<List<DocumentSummary>> list({
    Set<DocKind>? kinds,
    String? from,
    String? to,
    String query = '',
    List<String>? scope,
  }) async {
    final wanted = kinds ?? DocKind.values.toSet();
    final out = <DocumentSummary>[];

    if (wanted.contains(DocKind.receipt)) {
      out.addAll(_group(
        await db.select(db.receipts).get(),
        DocKind.receipt,
        party: (r) => r.supplier,
      ));
    }
    if (wanted.contains(DocKind.issue)) {
      out.addAll(_group(
        await db.select(db.issues).get(),
        DocKind.issue,
        party: (r) => r.recipientDisplay,
      ));
    }
    if (wanted.contains(DocKind.transfer)) {
      out.addAll(_group(
        await db.select(db.transfers).get(),
        DocKind.transfer,
        party: (r) => r.destWarehouse,
        destWarehouse: (r) => r.destWarehouse,
      ));
    }
    if (wanted.contains(DocKind.returnDoc)) {
      out.addAll(_group(
        await db.select(db.returns).get(),
        DocKind.returnDoc,
        party: (r) => r.party,
        returnType: (r) => r.type,
        condition: (r) => r.condition,
      ));
    }

    final q = query.trim().toLowerCase();
    final filtered = out.where((d) {
      if (from != null && from.isNotEmpty && d.date.compareTo(from) < 0) return false;
      if (to != null && to.isNotEmpty && d.date.compareTo(to) > 0) return false;
      if (scope != null &&
          !scope.contains(d.warehouse) &&
          !(d.destWarehouse.isNotEmpty && scope.contains(d.destWarehouse))) {
        return false;
      }
      if (q.isEmpty) return true;
      return d.refNo.toLowerCase().contains(q) ||
          d.party.toLowerCase().contains(q) ||
          d.warehouse.toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.refNo.compareTo(a.refNo);
    });
    return filtered;
  }

  List<DocumentSummary> _group<T extends DataClass>(
    List<T> rows,
    DocKind kind, {
    required String Function(dynamic) party,
    String Function(dynamic)? destWarehouse,
    String Function(dynamic)? returnType,
    String Function(dynamic)? condition,
  }) {
    final byRef = <String, List<dynamic>>{};
    for (final r in rows) {
      final d = r as dynamic;
      byRef.putIfAbsent(d.refNo as String, () => []).add(d);
    }
    return byRef.entries.map((e) {
      final first = e.value.first;
      return DocumentSummary(
        kind: kind,
        refNo: e.key,
        date: first.date as String,
        warehouse: first.warehouse as String,
        destWarehouse: destWarehouse?.call(first) ?? '',
        status: first.status as String,
        party: party(first),
        linesCount: e.value.length,
        returnType: returnType?.call(first) ?? 'FROM_UNIT',
        condition: condition?.call(first) ?? 'صالحة',
        createdBy: first.createdBy as String,
        editCount: first.editCount as int,
        notes: first.notes as String,
        editedBy: first.editedBy as String,
        cancelReason: first.cancelReason as String,
        cancelledBy: first.cancelledBy as String,
        prevStatus: first.prevStatus as String,
        editLog: decodeEditLog(first.editLog as String),
        totalBaseQty: e.value.fold<double>(0, (s, r) => s + (r.baseQty as num).toDouble()),
      );
    }).toList();
  }

  /// قراءة `editLog` المخزَّن كـ JSON — يتجاهل أي سطر تالف بدل أن يُسقِط الشاشة.
  static List<DocumentEditEntry> decodeEditLog(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return [
        for (final e in parsed.whereType<Map>())
          DocumentEditEntry(
            at: '${e['at'] ?? ''}',
            by: '${e['by'] ?? ''}',
            summary: '${e['summary'] ?? e['reason'] ?? ''}',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<DocumentLineRow>> lines(DocKind kind, String refNo) async {
    final rows = await _rowsOf(kind, refNo);
    return rows
        .map((r) => DocumentLineRow(
              id: r.id as String,
              itemId: r.itemId as String,
              itemName: r.itemName as String,
              unitName: r.unitName as String,
              factor: (r.factor as num).toDouble(),
              qty: (r.qty as num).toDouble(),
              baseQty: (r.baseQty as num).toDouble(),
              itemCode: r.itemCode as String,
              notes: r.notes as String,
              beneficiaryUnitId: kind == DocKind.issue ? r.beneficiaryUnitId as String : '',
              beneficiaryUnitName: kind == DocKind.issue ? r.beneficiaryUnitName as String : '',
              cylinderAction: r.cylinderAction as String,
              expiryDate: kind == DocKind.receipt ? r.expiryDate as String : '',
            ))
        .toList();
  }

  /// صفوف السند الخام — تُستخدم في نافذة العرض والطباعة لقراءة حقول الرأس الخاصة بكل نوع.
  Future<List<dynamic>> rawLines(DocKind kind, String refNo) => _rowsOf(kind, refNo);

  Future<List<dynamic>> _rowsOf(DocKind kind, String refNo) async {
    switch (kind) {
      case DocKind.receipt:
        return (db.select(db.receipts)..where((t) => t.refNo.equals(refNo))).get();
      case DocKind.issue:
        return (db.select(db.issues)..where((t) => t.refNo.equals(refNo))).get();
      case DocKind.transfer:
        return (db.select(db.transfers)..where((t) => t.refNo.equals(refNo))).get();
      case DocKind.returnDoc:
        return (db.select(db.returns)..where((t) => t.refNo.equals(refNo))).get();
    }
  }

  /// الحالات التي لا أثر لها على الرصيد — كما في `MovementsRepo._balanceRows`.
  static const Set<String> _inactive = {'DRAFT', 'ORDER', 'CANCELLED', 'REJECTED'};

  /// أثر سطور سندٍ على أرصدة المستودعات: (المستودع، الصنف) ← الكمية بوحدة الأساس.
  ///
  /// **مرآةٌ حرفيّة لـ`MovementsRepo._balanceRows`** — الحالات غير الفاعلة،
  /// واستثناء الأسطوانات، والتحويل يُنقص المصدر ما لم يُرفض أو يُلغَ ويزيد الهدف
  /// إذا استُلم، والمرتجع التالف بلا أثر. كان الفحص بالصنف وحده على رصيد كل
  /// مستودعات النطاق مجموعًا، والتحويل بلا فحص إطلاقًا (H-4).
  static Map<(String, String), double> stockEffect({
    required DocKind kind,
    required String status,
    required String warehouse,
    String destWarehouse = '',
    String returnType = 'FROM_UNIT',
    String condition = 'صالحة',
    required Iterable<({String itemId, double baseQty, String cylinderAction})> lines,
  }) {
    final out = <(String, String), double>{};
    void add(String wh, String item, double q) {
      if (wh.isEmpty || item.isEmpty || q == 0) return;
      final k = (wh, item);
      out[k] = _r3((out[k] ?? 0) + q);
    }

    for (final l in lines) {
      switch (kind) {
        case DocKind.receipt:
          if (!_inactive.contains(status) && l.cylinderAction != 'REFILL') add(warehouse, l.itemId, l.baseQty);
        case DocKind.issue:
          if (!_inactive.contains(status) && l.cylinderAction != 'EXCHANGE' && l.cylinderAction != 'SEND_REFILL') {
            add(warehouse, l.itemId, -l.baseQty);
          }
        case DocKind.transfer:
          if (status != 'REJECTED' && status != 'CANCELLED') add(warehouse, l.itemId, -l.baseQty);
          if (status == 'RECEIVED') add(destWarehouse, l.itemId, l.baseQty);
        case DocKind.returnDoc:
          if (_inactive.contains(status)) continue;
          if (returnType == 'TO_SUPPLIER') {
            add(warehouse, l.itemId, -l.baseQty);
          } else if (condition != 'تالفة') {
            add(warehouse, l.itemId, l.baseQty);
          }
      }
    }
    return out;
  }

  static double _r3(double v) => (v * 1000).round() / 1000;

  /// أثر صفوف السند المحفوظة كما هي في القاعدة.
  static Map<(String, String), double> _effectOfRows(DocKind kind, List<dynamic> rows) {
    if (rows.isEmpty) return const {};
    final head = rows.first;
    return stockEffect(
      kind: kind,
      status: head.status as String,
      warehouse: head.warehouse as String,
      destWarehouse: kind == DocKind.transfer ? head.destWarehouse as String : '',
      returnType: kind == DocKind.returnDoc ? head.type as String : 'FROM_UNIT',
      condition: kind == DocKind.returnDoc ? head.condition as String : 'صالحة',
      lines: [
        for (final r in rows)
          (itemId: r.itemId as String, baseQty: (r.baseQty as num).toDouble(), cylinderAction: r.cylinderAction as String),
      ],
    );
  }

  /// يفحص انتقال الأرصدة من [before] إلى [after]: لا مستودعَ مجمَّدٌ بأمر جرد
  /// يُمسّ، ولا رصيد (مستودع × صنف) ينزل تحت الصفر. يُستدعى **داخل** معاملة
  /// الكتابة نفسها فلا تفصل بين الفحص والكتابة فجوةٌ يمرّ فيها سندٌ آخر.
  Future<EditCheck> _checkTransition(
    Map<(String, String), double> before,
    Map<(String, String), double> after,
  ) async {
    final moves = MovementsRepo(db);
    final keys = {...before.keys, ...after.keys};
    for (final wh in {for (final k in keys) k.$1}) {
      final frozen = await moves.frozenMessage(wh);
      if (frozen != null) return EditCheck(ok: false, warehouse: wh, error: frozen);
    }
    final balances = <String, Map<String, double>>{};
    for (final k in keys) {
      final delta = _r3((after[k] ?? 0) - (before[k] ?? 0));
      if (delta >= 0) continue;
      final have = (balances[k.$1] ??= await moves.balances(warehouse: k.$1))[k.$2] ?? 0;
      if (have + delta < -1e-9) {
        return EditCheck(ok: false, itemId: k.$2, warehouse: k.$1, available: have, needed: -delta);
      }
    }
    return const EditCheck(ok: true);
  }

  /// حفظ التعديل الكامل: تُحذف سطور السند وتُكتب
  /// القائمة الجديدة بالكامل ببيانات رأس محدَّثة (التاريخ/المستودع/الجهة)، مع رفع
  /// عدّاد التعديلات وإضافة سطر في سجل التعديلات.
  ///
  /// الرصيد يُفحص بالفرق **لكل مستودع** (ومنه تغيير المستودع نفسه، والتحويل
  /// بمستودعيه)، ويُرفض المستودع المجمَّد بأمر جرد — والفحص والكتابة في معاملة
  /// واحدة على صفوف السند كما هي الآن لا كما عُرضت.
  Future<EditCheck> saveEdit({
    required DocumentSummary doc,
    required List<DocumentLineRow> rows,
    required String reason,
    required String date,
    required String warehouse,
    required String party,
    String headNotes = '',
    String actor = '',
  }) async {
    var summary = '';
    final stockDelta = <String, double>{};
    final check = await db.transaction<EditCheck>(() async {
      final old = await _rowsOf(doc.kind, doc.refNo);
      if (old.isEmpty) return const EditCheck(ok: false, error: '✖ السند غير موجود — حدّث القائمة');
      final head = old.first;
      final status = head.status as String;
      final ctx = DocumentContext(type: doc.kind.docType, status: status);
      if (status == 'CANCELLED' || status == 'REJECTED' || !ctx.editable) {
        return const EditCheck(ok: false, error: '✖ هذا السند لا يُعدَّل بحالته الحالية — حدّث القائمة');
      }
      final after = stockEffect(
        kind: doc.kind,
        status: status,
        warehouse: warehouse,
        destWarehouse: doc.kind == DocKind.transfer ? party : '',
        returnType: doc.kind == DocKind.returnDoc ? head.type as String : 'FROM_UNIT',
        condition: doc.kind == DocKind.returnDoc ? head.condition as String : 'صالحة',
        lines: [
          for (final r in rows)
            (itemId: r.itemId, baseQty: _r3(r.qty * (r.factor <= 0 ? 1 : r.factor)), cylinderAction: r.cylinderAction),
        ],
      );
      final before = _effectOfRows(doc.kind, old);
      final verdict = await _checkTransition(before, after);
      if (!verdict.ok) return verdict;
      final delta = <String, double>{
        for (final k in {...before.keys, ...after.keys})
          if (_r3((after[k] ?? 0) - (before[k] ?? 0)) != 0) '${k.$1}|${k.$2}': _r3((after[k] ?? 0) - (before[k] ?? 0)),
      };

    final changes = <String>[];
    if (date != doc.date) changes.add('التاريخ ${doc.date} ← $date');
    if (warehouse != doc.warehouse) changes.add('المستودع ${doc.warehouse} ← $warehouse');
    if (party != doc.party) changes.add('الجهة ${doc.party} ← $party');
    if (rows.length != old.length) changes.add('الأصناف ${old.length} ← ${rows.length}');
    if (delta.isNotEmpty) changes.add('فروقات رصيد على ${delta.length} صنف');
    summary = '${changes.isEmpty ? 'تعديل بيانات' : changes.join('، ')} — السبب: $reason';

    final logJson = jsonEncode([
      ...(jsonDecode(head.editLog as String) as List),
      {'at': _stamp(), 'by': actor, 'summary': summary},
    ]);
    final count = (head.editCount as int) + 1;

    {
      for (final l in old) {
        await _deleteLine(doc.kind, l.id as String);
      }
      for (final r in rows) {
        final factor = r.factor <= 0 ? 1.0 : r.factor;
        final base = (r.qty * factor * 1000).round() / 1000;
        final notes = r.notes.isNotEmpty ? r.notes : headNotes;
        switch (doc.kind) {
          case DocKind.receipt:
            final o = head as Receipt;
            await db.into(db.receipts).insert(ReceiptsCompanion.insert(
                  id: Ids.next('rc'),
                  refNo: Value(doc.refNo),
                  date: Value(date),
                  warehouse: Value(warehouse),
                  itemId: Value(r.itemId),
                  itemCode: Value(r.itemCode),
                  itemName: Value(r.itemName),
                  unitName: Value(r.unitName),
                  factor: Value(factor),
                  qty: Value(r.qty),
                  baseQty: Value(base),
                  status: Value(o.status),
                  notes: Value(notes),
                  createdBy: Value(o.createdBy),
                  createdAt: Value(o.createdAt),
                  editCount: Value(count),
                  editLog: Value(logJson),
                  editedBy: Value(actor),
                  supplier: Value(party),
                  invoiceNo: Value(o.invoiceNo),
                  committee: Value(o.committee),
                  supervision: Value(o.supervision),
                  audit: Value(o.audit),
                  cylinderAction: Value(r.cylinderAction),
                  expiryDate: Value(r.expiryDate),
                ));
          case DocKind.issue:
            final o = head as Issue;
            await db.into(db.issues).insert(IssuesCompanion.insert(
                  id: Ids.next('is'),
                  refNo: Value(doc.refNo),
                  date: Value(date),
                  warehouse: Value(warehouse),
                  itemId: Value(r.itemId),
                  itemCode: Value(r.itemCode),
                  itemName: Value(r.itemName),
                  unitName: Value(r.unitName),
                  factor: Value(factor),
                  qty: Value(r.qty),
                  baseQty: Value(base),
                  status: Value(o.status),
                  notes: Value(notes),
                  createdBy: Value(o.createdBy),
                  createdAt: Value(o.createdAt),
                  editCount: Value(count),
                  editLog: Value(logJson),
                  editedBy: Value(actor),
                  targetType: Value(o.targetType),
                  recipientDisplay: Value(party),
                  unitId: Value(o.unitId),
                  facilityId: Value(o.facilityId),
                  beneficiaryUnitId: Value(r.beneficiaryUnitId),
                  beneficiaryUnitName: Value(r.beneficiaryUnitName),
                  soldierCount: Value(o.soldierCount),
                  officerCount: Value(o.officerCount),
                  durationDays: Value(o.durationDays),
                  approvedBy: Value(o.approvedBy),
                  cylinderAction: Value(r.cylinderAction),
                ));
          case DocKind.transfer:
            final o = head as Transfer;
            await db.into(db.transfers).insert(TransfersCompanion.insert(
                  id: Ids.next('tr'),
                  refNo: Value(doc.refNo),
                  date: Value(date),
                  warehouse: Value(warehouse),
                  itemId: Value(r.itemId),
                  itemCode: Value(r.itemCode),
                  itemName: Value(r.itemName),
                  unitName: Value(r.unitName),
                  factor: Value(factor),
                  qty: Value(r.qty),
                  baseQty: Value(base),
                  status: Value(o.status),
                  notes: Value(notes),
                  createdBy: Value(o.createdBy),
                  createdAt: Value(o.createdAt),
                  editCount: Value(count),
                  editLog: Value(logJson),
                  editedBy: Value(actor),
                  destWarehouse: Value(party),
                  campId: Value(o.campId),
                  campName: Value(o.campName),
                  strength: Value(o.strength),
                  durationDays: Value(o.durationDays),
                  cylinderAction: Value(r.cylinderAction),
                ));
          case DocKind.returnDoc:
            final o = head as Return;
            await db.into(db.returns).insert(ReturnsCompanion.insert(
                  id: Ids.next('re'),
                  refNo: Value(doc.refNo),
                  date: Value(date),
                  warehouse: Value(warehouse),
                  itemId: Value(r.itemId),
                  itemCode: Value(r.itemCode),
                  itemName: Value(r.itemName),
                  unitName: Value(r.unitName),
                  factor: Value(factor),
                  qty: Value(r.qty),
                  baseQty: Value(base),
                  status: Value(o.status),
                  notes: Value(notes),
                  createdBy: Value(o.createdBy),
                  createdAt: Value(o.createdAt),
                  editCount: Value(count),
                  editLog: Value(logJson),
                  editedBy: Value(actor),
                  party: Value(party),
                  type: Value(o.type),
                  condition: Value(o.condition),
                  origRef: Value(o.origRef),
                  // التعديل يعيد إنشاء السطور: ما لم يُنقل هنا يضيع، ومنه ربط الوحدة (v11).
                  beneficiaryUnitId: Value(o.beneficiaryUnitId),
                  beneficiaryUnitName: Value(o.beneficiaryUnitName),
                  cylinderAction: Value(r.cylinderAction),
                ));
        }
      }
    }
      // الفرق مُسجَّلٌ بمفتاح «مستودع|صنف» لسجل التدقيق.
      stockDelta.addAll(delta);
      return verdict;
    });
    if (!check.ok) return check;

    await AuditRepo(db).write(
      'DOCUMENT_EDITED',
      'document',
      'تعديل ${doc.kind.label} ${doc.refNo}',
      details: {
        'refNo': doc.refNo,
        'docType': doc.kind.name,
        'warehouse': warehouse,
        'target': party,
        'status': doc.status,
        'itemCount': rows.length,
        'reason': reason,
        'summary': summary,
        'stockDelta': stockDelta,
        'risk': 'critical',
      },
    );
    return check;
  }

  static String _stamp() =>
      DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 16);

  Future<void> _deleteLine(DocKind kind, String id) async {
    switch (kind) {
      case DocKind.receipt:
        await (db.delete(db.receipts)..where((t) => t.id.equals(id))).go();
        break;
      case DocKind.issue:
        await (db.delete(db.issues)..where((t) => t.id.equals(id))).go();
        break;
      case DocKind.transfer:
        await (db.delete(db.transfers)..where((t) => t.id.equals(id))).go();
        break;
      case DocKind.returnDoc:
        await (db.delete(db.returns)..where((t) => t.id.equals(id))).go();
        break;
    }
  }

  /// إلغاء السند: يعكس أثره كاملًا لأن دفتر الأرصدة يتجاهل الحالة CANCELLED.
  ///
  /// الرصيد يُفحص لكل مستودع يمسّه الإلغاء — ومنه **مستودع الاستلام** حين يُلغى
  /// تحويلٌ مُستلَم (كان التحويل بلا فحص فيسحب الإلغاء رصيدًا صُرف هناك) —
  /// ويُرفض المستودع المجمَّد بأمر جرد، والفحص والكتابة في معاملة واحدة.
  Future<EditCheck> cancel({
    required DocumentSummary doc,
    required String reason,
    String cancelledBy = '',
  }) async {
    var rowsCount = 0;
    var prev = '';
    var reversal = <String, double>{};
    final check = await db.transaction<EditCheck>(() async {
      final old = await _rowsOf(doc.kind, doc.refNo);
      if (old.isEmpty) return const EditCheck(ok: false, error: '✖ السند غير موجود — حدّث القائمة');
      prev = old.first.status as String;
      if (prev == 'CANCELLED') return const EditCheck(ok: false, error: '✖ السند ملغى سلفًا');
      final before = _effectOfRows(doc.kind, old);
      final verdict = await _checkTransition(before, const {});
      if (!verdict.ok) return verdict;
      rowsCount = old.length;
      reversal = {for (final e in before.entries) '${e.key.$1}|${e.key.$2}': _r3(-e.value)};
      final logJson = jsonEncode([
        ...(jsonDecode(old.first.editLog as String) as List),
        {'at': _stamp(), 'by': cancelledBy, 'summary': 'إلغاء المستند — السبب: $reason'},
      ]);
    switch (doc.kind) {
      case DocKind.receipt:
        await (db.update(db.receipts)..where((t) => t.refNo.equals(doc.refNo)))
            .write(ReceiptsCompanion(
          status: const Value('CANCELLED'),
          prevStatus: Value(prev),
          cancelReason: Value(reason),
          cancelledBy: Value(cancelledBy),
          editLog: Value(logJson),
        ));
        break;
      case DocKind.issue:
        await (db.update(db.issues)..where((t) => t.refNo.equals(doc.refNo))).write(IssuesCompanion(
          status: const Value('CANCELLED'),
          prevStatus: Value(prev),
          cancelReason: Value(reason),
          cancelledBy: Value(cancelledBy),
          editLog: Value(logJson),
        ));
        break;
      case DocKind.transfer:
        await (db.update(db.transfers)..where((t) => t.refNo.equals(doc.refNo)))
            .write(TransfersCompanion(
          status: const Value('CANCELLED'),
          prevStatus: Value(prev),
          cancelReason: Value(reason),
          cancelledBy: Value(cancelledBy),
          editLog: Value(logJson),
        ));
        break;
      case DocKind.returnDoc:
        await (db.update(db.returns)..where((t) => t.refNo.equals(doc.refNo)))
            .write(ReturnsCompanion(
          status: const Value('CANCELLED'),
          prevStatus: Value(prev),
          cancelReason: Value(reason),
          cancelledBy: Value(cancelledBy),
          editLog: Value(logJson),
        ));
        break;
    }
      return verdict;
    });
    if (!check.ok) return check;

    await AuditRepo(db).write(
      'DOCUMENT_CANCELLED',
      'document',
      'إلغاء ${doc.kind.label} ${doc.refNo}',
      details: {
        'refNo': doc.refNo,
        'docType': doc.kind.name,
        'warehouse': doc.warehouse,
        'target': doc.party,
        'status': prev,
        'itemCount': rowsCount,
        'reason': reason,
        'reversal': reversal,
        'risk': 'critical',
      },
    );
    return check;
  }
}
