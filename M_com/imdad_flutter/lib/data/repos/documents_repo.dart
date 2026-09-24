import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import '../../domain/document_edit.dart';
import 'audit_repo.dart';

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
              cylinderAction: kind == DocKind.issue || kind == DocKind.receipt
                  ? r.cylinderAction as String
                  : '',
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

  /// فرق الكميات بين الحالة المحفوظة والحالة الجديدة، بوحدة الأساس.
  Future<Map<String, double>> pendingDelta({
    required DocumentSummary doc,
    required List<DocumentLineRow> after,
  }) async {
    final before = await lines(doc.kind, doc.refNo);
    return DocumentEdit.delta(
      context: doc.context,
      before: before.map((l) => DocumentLine(itemId: l.itemId, baseQty: l.baseQty)).toList(),
      after: after.map((l) => DocumentLine(itemId: l.itemId, baseQty: l.baseQty)).toList(),
    );
  }

  /// يطبّق التعديل بعد التحقق من كفاية الرصيد، ويسجّل سبب التعديل في سجل السند.
  Future<EditCheck> applyEdit({
    required DocumentSummary doc,
    required List<DocumentLineRow> after,
    required String reason,
    required Map<String, double> availableBaseQty,
    String editedBy = '',
  }) async {
    final delta = await pendingDelta(doc: doc, after: after);
    final check = DocumentEdit.check(delta: delta, availableBaseQty: availableBaseQty);
    if (!check.ok) return check;

    final stamp = {
      'at': DateTime.now().toIso8601String(),
      'by': editedBy,
      'reason': reason,
      'delta': delta,
    };

    for (final line in after) {
      final baseQty = line.qty * (line.factor <= 0 ? 1 : line.factor);
      await _updateLine(doc.kind, line.id, qty: line.qty, baseQty: baseQty, stamp: stamp);
    }
    // سطور حُذفت من السند: تُزال نهائيًا بعد أن دخل أثرها في الفرق أعلاه.
    final keep = after.map((l) => l.id).toSet();
    for (final old in await lines(doc.kind, doc.refNo)) {
      if (!keep.contains(old.id)) await _deleteLine(doc.kind, old.id);
    }

    await AuditRepo(db).log(
      action: 'document.edit',
      entityType: doc.kind.label,
      summary: 'تعديل ${doc.kind.label} ${doc.refNo} — $reason',
      details: {'refNo': doc.refNo, 'warehouse': doc.warehouse, 'delta': delta},
      risk: AuditRepo.riskHigh,
      actorEmail: editedBy,
    );
    return check;
  }

  /// حفظ التعديل الكامل كما في `saveDocEdit()` بالويب: تُحذف سطور السند وتُكتب
  /// القائمة الجديدة بالكامل ببيانات رأس محدَّثة (التاريخ/المستودع/الجهة)، مع رفع
  /// عدّاد التعديلات وإضافة سطر في سجل التعديلات. الأرصدة تتأثر بالفرق فقط.
  Future<EditCheck> saveEdit({
    required DocumentSummary doc,
    required List<DocumentLineRow> rows,
    required String reason,
    required Map<String, double> availableBaseQty,
    required String date,
    required String warehouse,
    required String party,
    String headNotes = '',
    String actor = '',
  }) async {
    final delta = await pendingDelta(doc: doc, after: rows);
    final check = DocumentEdit.check(delta: delta, availableBaseQty: availableBaseQty);
    if (!check.ok) return check;

    final old = await _rowsOf(doc.kind, doc.refNo);
    if (old.isEmpty) return check;
    final head = old.first;

    final changes = <String>[];
    if (date != doc.date) changes.add('التاريخ ${doc.date} ← $date');
    if (warehouse != doc.warehouse) changes.add('المستودع ${doc.warehouse} ← $warehouse');
    if (party != doc.party) changes.add('الجهة ${doc.party} ← $party');
    if (rows.length != old.length) changes.add('الأصناف ${old.length} ← ${rows.length}');
    if (delta.isNotEmpty) changes.add('فروقات رصيد على ${delta.length} صنف');
    final summary = '${changes.isEmpty ? 'تعديل بيانات' : changes.join('، ')} — السبب: $reason';

    final logJson = jsonEncode([
      ...(jsonDecode(head.editLog as String) as List),
      {'at': _stamp(), 'by': actor, 'summary': summary},
    ]);
    final count = (head.editCount as int) + 1;

    await db.transaction(() async {
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
                ));
        }
      }
    });

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
        'stockDelta': delta,
        'risk': 'critical',
      },
    );
    return check;
  }

  static String _stamp() =>
      DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 16);

  Future<void> _updateLine(
    DocKind kind,
    String id, {
    required double qty,
    required double baseQty,
    required Map<String, dynamic> stamp,
  }) async {
    final rows = await _rowById(kind, id);
    if (rows.isEmpty) return;
    final row = rows.first;
    final log = <dynamic>[...(jsonDecode(row.editLog as String) as List), stamp];
    final count = (row.editCount as int) + 1;

    switch (kind) {
      case DocKind.receipt:
        await (db.update(db.receipts)..where((t) => t.id.equals(id))).write(ReceiptsCompanion(
          qty: Value(qty),
          baseQty: Value(baseQty),
          editCount: Value(count),
          editLog: Value(jsonEncode(log)),
        ));
        break;
      case DocKind.issue:
        await (db.update(db.issues)..where((t) => t.id.equals(id))).write(IssuesCompanion(
          qty: Value(qty),
          baseQty: Value(baseQty),
          editCount: Value(count),
          editLog: Value(jsonEncode(log)),
        ));
        break;
      case DocKind.transfer:
        await (db.update(db.transfers)..where((t) => t.id.equals(id))).write(TransfersCompanion(
          qty: Value(qty),
          baseQty: Value(baseQty),
          editCount: Value(count),
          editLog: Value(jsonEncode(log)),
        ));
        break;
      case DocKind.returnDoc:
        await (db.update(db.returns)..where((t) => t.id.equals(id))).write(ReturnsCompanion(
          qty: Value(qty),
          baseQty: Value(baseQty),
          editCount: Value(count),
          editLog: Value(jsonEncode(log)),
        ));
        break;
    }
  }

  Future<List<dynamic>> _rowById(DocKind kind, String id) {
    switch (kind) {
      case DocKind.receipt:
        return (db.select(db.receipts)..where((t) => t.id.equals(id))).get();
      case DocKind.issue:
        return (db.select(db.issues)..where((t) => t.id.equals(id))).get();
      case DocKind.transfer:
        return (db.select(db.transfers)..where((t) => t.id.equals(id))).get();
      case DocKind.returnDoc:
        return (db.select(db.returns)..where((t) => t.id.equals(id))).get();
    }
  }

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
  Future<EditCheck> cancel({
    required DocumentSummary doc,
    required String reason,
    required Map<String, double> availableBaseQty,
    String cancelledBy = '',
  }) async {
    final rows = await lines(doc.kind, doc.refNo);
    final reversal = DocumentEdit.cancellation(
      context: doc.context,
      lines: rows.map((l) => DocumentLine(itemId: l.itemId, baseQty: l.baseQty)).toList(),
    );
    final check = DocumentEdit.check(delta: reversal, availableBaseQty: availableBaseQty);
    if (!check.ok) return check;

    // الحالة السابقة وسجل التعديل يُقرآن من أول سطر — كل السطور تحمل نفس بيانات الرأس.
    final old = await _rowsOf(doc.kind, doc.refNo);
    if (old.isEmpty) return check;
    final prev = old.first.status as String;
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
        'itemCount': rows.length,
        'reason': reason,
        'reversal': reversal,
        'risk': 'critical',
      },
    );
    return check;
  }
}
