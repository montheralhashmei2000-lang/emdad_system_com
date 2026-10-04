import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import 'audit_repo.dart';
import '../../core/error_log.dart';

/// اتجاه البرقية.
class CableDirection {
  static const String incoming = 'in';
  static const String outgoing = 'out';

  static const Map<String, String> labels = {
    incoming: 'واردة',
    outgoing: 'صادرة',
  };

  static String label(String k) => labels[k] ?? k;
}

/// تصنيف السرية.
class CableClass {
  static const String normal = 'normal';
  static const String secret = 'secret';
  static const String top = 'top';

  static const Map<String, (String, String)> meta = {
    normal: ('عادي', 'off'),
    secret: ('سري', 'pend'),
    top: ('سري للغاية', 'err'),
  };

  static String label(String k) => meta[k]?.$1 ?? k;
}

/// الأولوية.
class CablePriority {
  static const String normal = 'normal';
  static const String urgent = 'urgent';
  static const String immediate = 'immediate';

  static const Map<String, (String, String)> meta = {
    normal: ('عادي', 'off'),
    urgent: ('عاجل', 'pend'),
    immediate: ('عاجل جدًا', 'err'),
  };

  static String label(String k) => meta[k]?.$1 ?? k;
}

/// حالة المعالجة.
class CableStatus {
  static const String neu = 'new';
  static const String processing = 'processing';
  static const String replied = 'replied';
  static const String archived = 'archived';

  static const Map<String, (String, String)> meta = {
    neu: ('جديد', 'info'),
    processing: ('قيد المعالجة', 'pend'),
    replied: ('تم الرد', 'ok'),
    archived: ('مؤرشف', 'code'),
  };

  static String label(String k) => meta[k]?.$1 ?? k;
}

/// صفٌّ في جدول المرسَل إليهم.
class CableRecipient {
  const CableRecipient({this.name = '', this.unit = '', this.note = ''});

  final String name;
  final String unit;
  final String note;

  bool get isEmpty => name.trim().isEmpty && unit.trim().isEmpty && note.trim().isEmpty;

  Map<String, String> toJson() => {'name': name, 'unit': unit, 'note': note};

  static List<CableRecipient> decode(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map)
            CableRecipient(
              name: '${e['name'] ?? ''}',
              unit: '${e['unit'] ?? ''}',
              note: '${e['note'] ?? ''}',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<CableRecipient> rows) =>
      jsonEncode([for (final r in rows) if (!r.isEmpty) r.toJson()]);
}

/// مستودع البرقيات — مع دعم مرفق PDF واحد لكل برقية.
class CableRepo {
  CableRepo(this.db);
  final AppDatabase db;

  Future<Directory> storageDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'cables'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<Cable>> list({
    String q = '',
    String direction = '',
    String status = '',
    String classification = '',
    String priority = '',
    bool onlyWithAttach = false,
  }) async {
    final rows = await db.select(db.cables).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((c) {
      if (direction.isNotEmpty && c.direction != direction) return false;
      if (status.isNotEmpty && c.status != status) return false;
      if (classification.isNotEmpty && c.classification != classification) {
        return false;
      }
      if (priority.isNotEmpty && c.priority != priority) return false;
      if (onlyWithAttach && c.attachPath.isEmpty) return false;
      if (query.isEmpty) return true;
      final hay = [
        c.cableNo,
        c.subject,
        c.body,
        c.fromParty,
        c.toParty,
        c.ccParty,
        c.recipientsJson,
        c.editorName,
        c.serialNo,
        c.attachName,
        c.notes,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) {
      final d = b.cableDate.compareTo(a.cableDate);
      if (d != 0) return d;
      return b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  /// الرقم التالي بصيغة النموذج: خمس خانات ثم لاحقة الاتجاه — `00024-ص` للصادرة
  /// و`00024-و` للواردة. يُقترح عند فتح النموذج ويبقى قابلًا للتعديل يدويًّا.
  Future<String> nextCableNo(String direction) async {
    final suffix = direction == CableDirection.outgoing ? 'ص' : 'و';
    final rows = await db.select(db.cables).get();
    var max = 0;
    for (final c in rows) {
      if (c.direction != direction) continue;
      final m = RegExp(r'^(\d+)').firstMatch(c.cableNo.trim());
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > max) max = n;
    }
    return '${(max + 1).toString().padLeft(5, '0')}-$suffix';
  }

  /// قيم سبق كتابتها في حقل متغيّر (إلى/من/الوحدة…) — تُقترح عند الكتابة.
  Future<List<String>> suggestions(String field) async {
    final rows = await db.select(db.cables).get();
    final seen = <String>{};
    for (final c in rows) {
      switch (field) {
        case 'to':
          seen.add(c.toParty);
        case 'from':
          seen.add(c.fromParty);
        case 'cc':
          seen.addAll(c.ccParty.split('\n'));
        case 'editor':
          seen.add(c.editorName);
        case 'rank':
          seen.add(c.editorRank);
        case 'job':
          seen.add(c.editorJob);
        case 'method':
          seen.add(c.sendMethod);
        case 'recipient':
          for (final r in CableRecipient.decode(c.recipientsJson)) {
            seen.add(r.name);
          }
        case 'unit':
          for (final r in CableRecipient.decode(c.recipientsJson)) {
            seen.add(r.unit);
          }
      }
    }
    return (seen.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort());
  }

  Future<Cable?> byId(String id) async {
    if (id.isEmpty) return null;
    final rows =
        await (db.select(db.cables)..where((t) => t.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, int>> stats() async {
    final rows = await db.select(db.cables).get();
    return {
      'total': rows.length,
      'in': rows.where((c) => c.direction == CableDirection.incoming).length,
      'out': rows.where((c) => c.direction == CableDirection.outgoing).length,
      'new': rows.where((c) => c.status == CableStatus.neu).length,
      'processing':
          rows.where((c) => c.status == CableStatus.processing).length,
      'replied': rows.where((c) => c.status == CableStatus.replied).length,
      'archived': rows.where((c) => c.status == CableStatus.archived).length,
      'secret': rows
          .where((c) =>
              c.classification == CableClass.secret ||
              c.classification == CableClass.top)
          .length,
      'urgent': rows
          .where((c) =>
              c.priority == CablePriority.urgent ||
              c.priority == CablePriority.immediate)
          .length,
      'withAttach': rows.where((c) => c.attachPath.isNotEmpty).length,
    };
  }

  Future<void> insert(CablesCompanion e, {String actor = ''}) async {
    await db.into(db.cables).insert(e);
    final subj = e.subject.present ? e.subject.value : '';
    final no = e.cableNo.present ? e.cableNo.value : '';
    await AuditRepo(db).log(
      action: 'cable.create',
      entityType: 'cable',
      summary: 'إضافة برقية: $no — $subj',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> update(Cable c, CablesCompanion e, {String actor = ''}) async {
    await (db.update(db.cables)..where((t) => t.id.equals(c.id))).write(
      e.copyWith(updatedAt: Value(DateTime.now())),
    );
    await AuditRepo(db).log(
      action: 'cable.edit',
      entityType: 'cable',
      summary: 'تعديل برقية: ${c.cableNo} — ${c.subject}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> setStatus(Cable c, String status, {String actor = ''}) async {
    await (db.update(db.cables)..where((t) => t.id.equals(c.id))).write(
      CablesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'cable.status',
      entityType: 'cable',
      summary:
          'تغيير حالة البرقية ${c.cableNo} إلى ${CableStatus.label(status)}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// إرفاق PDF — ينسخ الملف ويحدّث الحقول. يحذف المرفق القديم إن وُجد.
  Future<Cable> attachPdf(
    Cable c, {
    required String sourcePath,
    String actor = '',
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw StateError('الملف غير موجود: $sourcePath');
    }
    final bytes = await src.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final originalName = p.basename(sourcePath);
    final ext = p.extension(sourcePath).toLowerCase();
    if (ext != '.pdf') {
      throw StateError('يُقبل مرفق PDF فقط');
    }

    if (c.attachPath.isNotEmpty) {
      final old = File(c.attachPath);
      if (await old.exists()) {
        try {
          await old.delete();
        } catch (err, stack) {
          ErrorLogger.log('cable.attachmentDelete', err, stack);
        }
      }
    }

    final dir = await storageDir();
    final dst = File(p.join(dir.path, '${c.id}.pdf'));
    await dst.writeAsBytes(bytes, flush: true);

    await (db.update(db.cables)..where((t) => t.id.equals(c.id))).write(
      CablesCompanion(
        attachName: Value(originalName),
        attachPath: Value(dst.path),
        attachSize: Value(bytes.length),
        attachSha256: Value(digest),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await AuditRepo(db).log(
      action: 'cable.attach',
      entityType: 'cable',
      summary: 'إرفاق PDF بالبرقية ${c.cableNo}: $originalName',
      details: {'size': bytes.length, 'sha256': digest},
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );

    return (await byId(c.id))!;
  }

  /// إزالة المرفق من البرقية ومن القرص.
  Future<Cable> removeAttachment(Cable c, {String actor = ''}) async {
    if (c.attachPath.isNotEmpty) {
      final f = File(c.attachPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (err, stack) {
          ErrorLogger.log('cable.attachmentDelete', err, stack);
        }
      }
    }
    await (db.update(db.cables)..where((t) => t.id.equals(c.id))).write(
      CablesCompanion(
        attachName: const Value(''),
        attachPath: const Value(''),
        attachSize: const Value(0),
        attachSha256: const Value(''),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'cable.detach',
      entityType: 'cable',
      summary: 'إزالة مرفق البرقية ${c.cableNo}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
    return (await byId(c.id))!;
  }

  Future<bool> verifyAttachment(Cable c) async {
    if (c.attachPath.isEmpty || c.attachSha256.isEmpty) return true;
    final f = File(c.attachPath);
    if (!await f.exists()) return false;
    final dig = sha256.convert(await f.readAsBytes()).toString();
    return dig == c.attachSha256;
  }

  Future<void> delete(Cable c, {String actor = ''}) async {
    if (c.attachPath.isNotEmpty) {
      final f = File(c.attachPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (err, stack) {
          ErrorLogger.log('cable.attachmentDelete', err, stack);
        }
      }
    }
    await (db.delete(db.cables)..where((t) => t.id.equals(c.id))).go();
    await AuditRepo(db).log(
      action: 'cable.delete',
      entityType: 'cable',
      summary: 'حذف برقية: ${c.cableNo} — ${c.subject}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  static String formatSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes ب';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
}
