import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';

/// سجل التدقيق: أثر لا يُحذف للأحداث الحساسة (تعديل سند، إلغاؤه، اعتماد جرد،
/// تغيير صلاحيات، إنشاء مستخدم، محاولات دخول فاشلة).
class AuditRepo {
  AuditRepo(this.db);

  final AppDatabase db;

  static const String riskNormal = 'normal';
  static const String riskHigh = 'high';

  /// المدة التي تُحفَظ بها الأحداث **العادية** قبل التقليم.
  ///
  /// عالية الخطورة لا تُحذف أبدًا مهما طال العمر: تغييرُ صلاحية وإلغاءُ سند
  /// واعتمادُ جرد هي أثرُ المساءلة وسببُ وجود الجدول أصلًا. أما العادية فتُكتب
  /// بمعدّل مئاتٍ في اليوم، وتُزامَن إلى كل جهاز، فتصير بعد سنوات أكبرَ جداول
  /// النظام وأثقلَ ما يُنقل — بلا من يقرؤها. وسنتان أطولُ من أي مراجعة دورية.
  static const Duration normalTtl = Duration(days: 730);

  /// حدّ الحذف في التشغيلة الواحدة.
  ///
  /// كل حذفٍ يولّد شاهدًا في `sync_marks` يُنقل إلى النظراء، فحذف عشرات
  /// الألوف دفعةً واحدة يُثقل أول مزامنة بعده. التقليم يتوزّع على إقلاعات.
  static const int pruneBatch = 2000;

  /// يحذف دفعةً من الأحداث العادية التي تجاوزت [normalTtl]، ويعيد عددها.
  Future<int> prune({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(normalTtl);
    final stale = await (db.select(db.auditLogs)
          ..where((t) =>
              t.risk.equals(riskHigh).not() &
              t.createdAt.isSmallerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(pruneBatch))
        .get();
    if (stale.isEmpty) return 0;
    final ids = [for (final r in stale) r.id];
    await (db.delete(db.auditLogs)..where((t) => t.id.isIn(ids))).go();
    return ids.length;
  }

  Future<void> log({
    required String action,
    required String summary,
    String entityType = '',
    Map<String, dynamic> details = const {},
    String risk = riskNormal,
    String actorEmail = '',
  }) async {
    final now = DateTime.now();
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: Ids.next('aud'),
          action: action,
          entityType: Value(entityType),
          summary: Value(summary),
          details: Value(jsonEncode(details)),
          risk: Value(risk),
          actorEmail: Value(actorEmail),
          logDate: Value(
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          ),
        ));
  }

  /// `auditWrite(action, entityType, summary, details)` في الويب — نفس الحقول المستخرجة من details.
  Future<void> write(
    String action,
    String entityType,
    String summary, {
    Map<String, dynamic> details = const {},
    User? actor,
    String actorEmail = '',
  }) async {
    try {
      num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
      final qty = n(details['totalBaseQty']) != 0 ? n(details['totalBaseQty']) : n(details['qty']);
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
            id: Ids.next('aud'),
            action: action,
            entityType: Value(entityType),
            summary: Value(summary),
            risk: Value('${details['risk'] ?? 'normal'}'),
            refNo: Value('${details['refNo'] ?? ''}'),
            warehouse: Value('${details['warehouse'] ?? ''}'),
            target: Value('${details['target'] ?? ''}'),
            status: Value('${details['status'] ?? ''}'),
            itemCount: Value(n(details['itemCount']).toInt()),
            qty: Value(qty.toDouble()),
            actorEmail: Value(actor?.email ?? actorEmail),
            actorName: Value(actor != null
                ? (actor.name.isNotEmpty ? actor.name : actor.email)
                : actorEmail),
            actorRole: Value(actor?.role ?? 'user'),
            logDate: Value(DateTime.now().toIso8601String().substring(0, 10)),
            details: Value(jsonEncode(details)),
          ));
    } catch (_) {}
  }

  Future<List<AuditLog>> recent({int limit = 300, String risk = '', String query = ''}) async {
    final rows = await (db.select(db.auditLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    final q = query.trim().toLowerCase();
    return rows.where((r) {
      if (risk.isNotEmpty && r.risk != risk) return false;
      if (q.isEmpty) return true;
      return r.summary.toLowerCase().contains(q) ||
          r.action.toLowerCase().contains(q) ||
          r.actorEmail.toLowerCase().contains(q);
    }).toList();
  }
}
