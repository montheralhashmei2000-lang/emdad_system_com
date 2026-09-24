import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../inventory/doc_kit.dart';

/// سجل النشاط والتدقيق — نقل `renderAuditTrail()` / `audPaint()`:
/// بطاقة لكل حدث فيها مستوى الخطورة ونوع النشاط والملخّص والتاريخ،
/// ورقائق المرجع والمستودع والهدف وعدد العناصر، ومنفّذ العملية ودوره.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

/// `AUD_ACTION_LBL`
const kAuditActionLabels = <String, String>{
  'RECEIPT_DRAFT_SAVED': 'حفظ مسودة وارد',
  'RECEIPT_COMPLETED': 'اعتماد وارد',
  'RECEIPT_DRAFT_APPROVED': 'اعتماد مسودة وارد',
  'RECEIPT_DRAFT_DELETED': 'حذف مسودة وارد',
  'ISSUE_DRAFT_SAVED': 'حفظ مسودة صرف',
  'ISSUE_ORDER_CREATED': 'إرسال أمر صرف',
  'ISSUE_COMPLETED': 'اعتماد صرف',
  'ISSUE_DRAFT_APPROVED': 'اعتماد أمر/مسودة صرف',
  'ISSUE_DRAFT_DELETED': 'حذف مسودة صرف',
  'TRANSFER_SENT': 'إرسال تحويل',
  'TRANSFER_RECEIVED': 'تأكيد استلام تحويل',
  'TRANSFER_REJECTED': 'رفض تحويل',
  'RETURN_FROM_UNIT': 'مرتجع من وحدة',
  'RETURN_TO_SUPPLIER': 'مرتجع إلى مورد',
  'STOCKTAKE_CREATED': 'إنشاء جلسة جرد',
  'STOCKTAKE_POSTED': 'ترحيل تسوية جرد',
  'STOCKTAKE_CANCELLED': 'إلغاء أمر جرد',
  'STOCKTAKE_DELETED': 'حذف جلسة جرد',
  'OPENING_BALANCE_SET': 'تثبيت رصيد افتتاحي',
  'DOCUMENT_EDITED': 'تعديل مستند محفوظ',
  'DOCUMENT_CANCELLED': 'إلغاء مستند محفوظ',
  'SUPPLIER_CREATED': 'إضافة مورد',
  'SUPPLIER_UPDATED': 'تعديل مورد',
  'SUPPLIER_DELETED': 'حذف مورد',
  'WAREHOUSE_CREATED': 'إضافة مستودع',
  'WAREHOUSE_UPDATED': 'تعديل مستودع',
  'WAREHOUSE_DELETED': 'حذف مستودع',
  'USER_PERMISSIONS_CHANGED': 'تغيير صلاحيات مستخدم',
  'BRANDING_UPDATED': 'تحديث هوية وشعار التطبيق',
  'USER_APPROVED': 'اعتماد وتفعيل مستخدم',
  'USER_REACTIVATED': 'إعادة تفعيل مستخدم',
  'USER_DISABLED': 'إيقاف مستخدم',
  'USER_ROLE_CHANGED': 'تغيير دور مستخدم',
  'SENSITIVE_REVIEW_MARKED': 'تمت مراجعة تغيير حساس',
};

/// خيارات قائمة «كل الأنشطة» في الويب.
const _actionFilter = <String, String>{
  'ALL': 'كل الأنشطة',
  'OPENING_BALANCE_SET': 'أرصدة افتتاحية',
  'STOCKTAKE_POSTED': 'تسويات الجرد',
  'ISSUE_COMPLETED': 'اعتماد الصرف',
  'TRANSFER_SENT': 'التحويلات',
  'RETURN_TO_SUPPLIER': 'مرتجع مورد',
  'SUPPLIER_DELETED': 'حذف مورد',
  'WAREHOUSE_DELETED': 'حذف مستودع',
};

const _roles = <String, String>{'admin': 'مدير النظام', 'user': 'مستخدم'};

/// `audActionLbl(a)`
String auditActionLabel(String action) =>
    kAuditActionLabels[action] ?? (action.isEmpty ? 'نشاط' : action);

class _AuditScreenState extends State<AuditScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();

  final _q = TextEditingController();
  String _action = 'ALL';
  String _risk = 'ALL';
  List<AuditLog> _docs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await (_db.select(_db.auditLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(600))
        .get();
    if (!mounted) return;
    setState(() {
      _docs = rows;
      _loading = false;
    });
  }

  /// `audPaint()` — الفلترة نفسها (النشاط، الخطورة، البحث الحر).
  List<AuditLog> _rows() {
    final q = _q.text.trim().toLowerCase();
    return _docs.where((r) {
      if (_action != 'ALL' && r.action != _action) return false;
      if (_risk != 'ALL' && r.risk.toLowerCase() != _risk.toLowerCase()) return false;
      if (q.isEmpty) return true;
      return [r.summary, r.refNo, r.actorName, r.actorEmail, r.entityType, r.warehouse, r.target, r.status]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  /// `audRiskChip(risk)`
  static (String, ImdTone) _riskChip(String risk) => switch (risk.toLowerCase()) {
        'critical' => ('حرج', ImdTone.err),
        'sensitive' => ('حساس', ImdTone.pend),
        _ => ('عادي', ImdTone.ok),
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final critical = rows.where((r) => r.risk.toLowerCase() == 'critical').length;
    final sensitive = rows.where((r) => r.risk.toLowerCase() == 'sensitive').length;
    final users = {
      for (final r in rows)
        if ((r.actorEmail.isNotEmpty ? r.actorEmail : r.actorName).trim().isNotEmpty)
          (r.actorEmail.isNotEmpty ? r.actorEmail : r.actorName).trim(),
    }.length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'سجل النشاط والتدقيق',
        icon: 'eye',
        subtitle: 'شاشة محاسبة تشغيلية: مَن عمل ماذا، متى، وعلى أي مستند أو كيان — '
            'مع تمييز العمليات الحساسة والحرجة',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث بالمرجع أو المستخدم أو الملخص أو الكيان…',
            onChanged: (_) => setState(() {}),
            actions: [
              SizedBox(
                width: 220,
                child: ImdSelect<String>(
                  dense: true,
                  items: [for (final e in _actionFilter.entries) (e.key, e.value)],
                  value: _action,
                  onChanged: (v) => setState(() => _action = v ?? 'ALL'),
                ),
              ),
              SizedBox(
                width: 180,
                child: ImdSelect<String>(
                  dense: true,
                  items: const [
                    ('ALL', 'كل المستويات'),
                    ('critical', 'حرج'),
                    ('sensitive', 'حساس'),
                    ('normal', 'عادي'),
                  ],
                  value: _risk,
                  onChanged: (v) => setState(() => _risk = v ?? 'ALL'),
                ),
              ),
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
            ],
          ),
          const SizedBox(height: 4),
          ImdChipsRow(bottom: 0, children: [
            ImdChip('السجلات: ${nf(rows.length)}', tone: ImdTone.ok),
            ImdChip('حساسة: ${nf(sensitive)}', tone: ImdTone.pend),
            ImdChip('حرجة: ${nf(critical)}', tone: ImdTone.err),
            ImdChip('مستخدمون ظاهرون: ${nf(users)}', tone: ImdTone.off),
          ]),
        ]),
      ),
      if (_loading)
        const ImdLd('⏳ جارٍ تحميل سجل النشاط…')
      else if (rows.isEmpty)
        const ImdICard(
          child: ImdLd('لا توجد سجلات مطابقة حتى الآن — '
              'السجل يبدأ بالامتلاء تلقائيًا من لحظة تفعيل هذه المرحلة.'),
        )
      else
        for (final r in rows.take(250)) _card(r),
    ]);
  }

  Widget _card(AuditLog r) {
    final c = context.imd;
    final (riskLabel, riskTone) = _riskChip(r.risk);
    final when = r.logDate.isEmpty ? '—' : r.logDate;
    final actor = r.actorName.isNotEmpty
        ? r.actorName
        : (r.actorEmail.isNotEmpty ? r.actorEmail : 'مستخدم غير معروف');

    final details = <Widget>[
      if (r.refNo.isNotEmpty) ImdChip(r.refNo, tone: ImdTone.code),
      if (r.warehouse.isNotEmpty) ImdChip(r.warehouse, tone: ImdTone.off, icon: 'warehouse'),
      if (r.target.isNotEmpty) ImdChip(r.target, tone: ImdTone.off, icon: 'target'),
      if (r.itemCount > 0) ImdChip('${nf(r.itemCount)} عنصر', tone: ImdTone.ok),
      if (r.qty != 0) ImdChip('إجمالي ${nf(r.qty)}', tone: ImdTone.off),
    ];

    return ImdDocCard(
      head: [
        ImdChip(riskLabel, tone: riskTone),
        ImdChip(auditActionLabel(r.action), tone: ImdTone.code),
        Text(r.summary.isEmpty ? 'نشاط تشغيلي' : r.summary,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        ImdChip(when, tone: ImdTone.off),
        if (r.status.isNotEmpty) ImdChip(r.status, tone: ImdTone.pend),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: details),
          ),
        ImdEmojiText(
          '👤 $actor'
          '${r.actorRole.isEmpty ? '' : ' • ${_roles[r.actorRole] ?? r.actorRole}'}'
          '${r.entityType.isEmpty ? '' : ' • كيان: ${r.entityType}'}',
          style: TextStyle(fontSize: 13, height: 2, color: c.muted),
        ),
        if (_hasDetails(r)) ...[
          const SizedBox(height: 10),
          ImdNote(r.details),
        ],
      ]),
    );
  }

  static bool _hasDetails(AuditLog r) {
    try {
      final m = jsonDecode(r.details);
      return m is Map && m.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
