import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../home/home_shell.dart';
import '../inventory/doc_kit.dart';
import '../settings/audit_screen.dart';

/// التغييرات الحساسة والمراجعة — نقل `renderSensitiveOps()` / `smqLoad()`:
/// طابور رقابي يجمع الحسابات المعلقة وأوامر الصرف والتحويلات غير المحسومة
/// والأحداث الحساسة/الحرجة غير المُراجعة، مع وسم «تمت المراجعة» لكل حدث.
class SensitiveOpsScreen extends StatefulWidget {
  const SensitiveOpsScreen({super.key});

  @override
  State<SensitiveOpsScreen> createState() => _SensitiveOpsScreenState();
}

/// عنصر في طابور المراجعة.
class _QueueItem {
  const _QueueItem({
    required this.kind,
    required this.level,
    required this.title,
    required this.desc,
    this.refNo = '',
    this.target = '',
    this.warehouse = '',
    this.actor = '',
    this.page = '',
    this.when = '',
    this.logId = '',
  });

  /// USER_PENDING | ISSUE_ORDER | TRANSFER_PENDING | AUDIT_REVIEW
  final String kind;

  /// critical | sensitive
  final String level;
  final String title;
  final String desc;
  final String refNo;
  final String target;
  final String warehouse;
  final String actor;
  final String page;
  final String when;
  final String logId;
}

class _SensitiveOpsScreenState extends State<SensitiveOpsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();
  String _level = 'ALL';
  bool _loading = true;

  List<_QueueItem> _queue = const [];
  List<AuditLog> _logs = const [];
  Set<String> _reviewed = const {};

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

  /// `smqLoad()`
  Future<void> _load() async {
    final issues = await _db.select(_db.issues).get();
    final transfers = await _db.select(_db.transfers).get();
    final audits = await _db.select(_db.auditLogs).get();
    final reviews = await _db.select(_db.sensitiveReviews).get();
    final users = _perm.admin ? await _db.select(_db.users).get() : <User>[];

    final reviewed = {for (final r in reviews) r.logId};
    final logs = audits
        .where((r) => const {'sensitive', 'critical'}.contains(r.risk.toLowerCase()))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final queue = <_QueueItem>[
      for (final u in users.where((u) => !u.approved))
        _QueueItem(
          kind: 'USER_PENDING',
          level: 'sensitive',
          title: 'مستخدم بانتظار اعتماد',
          desc: 'طلب وصول جديد لم يُحسم بعد — الأفضل مراجعته قبل تراكم الحسابات المعلقة.',
          refNo: u.email,
          target: u.name,
          page: 'usersAccess',
          when: u.updatedAt == null ? '' : _iso(u.updatedAt!),
        ),
      // أمر الصرف والتحويل يُجمَّعان برقم السند فلا يتكرر السطر لكل صنف.
      for (final ref in issues.where((x) => x.status == 'ORDER').map((x) => x.refNo).toSet())
        () {
          final x = issues.firstWhere((i) => i.refNo == ref);
          return _QueueItem(
            kind: 'ISSUE_ORDER',
            level: 'sensitive',
            title: 'أمر صرف بانتظار اعتماد/تنفيذ',
            desc: 'سند صرف موجَّه للمستودع وما زال معلقًا — يحتاج قرارًا تشغيليًا واضحًا.',
            refNo: x.refNo,
            target: x.recipientDisplay,
            warehouse: x.warehouse,
            actor: x.createdBy,
            page: 'pendingOrders',
            when: x.date,
          );
        }(),
      for (final ref in transfers.where((x) => x.status == 'PENDING').map((x) => x.refNo).toSet())
        () {
          final x = transfers.firstWhere((t) => t.refNo == ref);
          return _QueueItem(
            kind: 'TRANSFER_PENDING',
            level: 'sensitive',
            title: 'تحويل مخزني بانتظار الاستلام',
            desc: 'التحويل ما زال معلقًا وقد يُربك الرصيد الفعلي إن طال بقاؤه بلا حسم.',
            refNo: x.refNo,
            target: x.destWarehouse,
            warehouse: x.warehouse,
            actor: x.createdBy,
            page: 'transfer',
            when: x.date,
          );
        }(),
      for (final r in logs.where((r) => !reviewed.contains(r.id)).take(120))
        _QueueItem(
          kind: 'AUDIT_REVIEW',
          level: r.risk.toLowerCase(),
          title: auditActionLabel(r.action),
          desc: r.summary.isEmpty
              ? 'تغيير حساس يحتاج مرور عين إدارية ثانية للتأكيد والإغلاق.'
              : r.summary,
          refNo: r.refNo,
          target: r.target,
          warehouse: r.warehouse,
          actor: r.actorName.isNotEmpty ? r.actorName : r.actorEmail,
          page: 'auditTrail',
          when: r.logDate,
          logId: r.id,
        ),
    ]..sort((a, b) {
        final wa = a.level == 'critical' ? 2 : 1;
        final wb = b.level == 'critical' ? 2 : 1;
        if (wb != wa) return wb - wa;
        return b.when.compareTo(a.when);
      });

    if (!mounted) return;
    setState(() {
      _queue = queue;
      _logs = logs;
      _reviewed = reviewed;
      _loading = false;
    });
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `smqMarkReviewed(logId)`
  Future<void> _markReviewed(String logId) async {
    if (logId.isEmpty) return;
    final note = await imdPrompt(context, 'ملاحظة المراجعة — اختياري', ok: 'تأكيد المراجعة');
    if (note == null) return;
    await _db.into(_db.sensitiveReviews).insertOnConflictUpdate(SensitiveReviewsCompanion.insert(
          id: logId,
          logId: logId,
          reviewedBy: Value(_perm.email),
          note: Value(note.trim()),
        ));
    await AuditRepo(_db).write(
      'SENSITIVE_REVIEW_MARKED',
      'sensitive_review',
      'تمت مراجعة تغيير حساس',
      actorEmail: _perm.email,
      details: {'refNo': logId, 'status': 'REVIEWED', 'target': note.trim(), 'risk': 'normal'},
    );
    if (!mounted) return;
    showImdToast(context, '✔ تم وسم العنصر بأنه تمت مراجعته');
    await _load();
  }

  /// `smqFilterRows(rows)`
  bool _matches({required String level, required List<String> fields}) {
    if (_level != 'ALL' && level.toLowerCase() != _level.toLowerCase()) return false;
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((v) => v.toLowerCase().contains(q));
  }

  List<_QueueItem> get _filteredQueue => _queue
      .where((it) => _matches(
            level: it.level,
            fields: [it.title, it.desc, it.refNo, it.target, it.warehouse, it.actor],
          ))
      .toList();

  List<AuditLog> get _filteredLogs => _logs
      .where((r) => _matches(
            level: r.risk,
            fields: [
              auditActionLabel(r.action),
              r.summary,
              r.refNo,
              r.target,
              r.warehouse,
              r.actorName.isNotEmpty ? r.actorName : r.actorEmail,
            ],
          ))
      .toList();

  void _go(String page) => context.read<ImdNav>().go(page);

  int _count(String kind) => _queue.where((x) => x.kind == kind).length;
  int _auditOpen(String level) =>
      _queue.where((x) => x.kind == 'AUDIT_REVIEW' && x.level == level).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(
          title: 'التغييرات الحساسة والمراجعة',
          icon: 'alert',
          subtitle: 'جارٍ تحليل التغييرات الحساسة وطابور المراجعة…',
        ),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final criticalOpen = _auditOpen('critical');
    final sensitiveOpen = _auditOpen('sensitive');
    final pendingUsers = _count('USER_PENDING');
    final pendingOrders = _count('ISSUE_ORDER');
    final pendingTransfers = _count('TRANSFER_PENDING');
    final score = math.max<int>(
      0,
      100 - math.min<int>(100, criticalOpen * 18 + sensitiveOpen * 4 + pendingUsers * 5),
    );

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'التغييرات الحساسة والمراجعة',
        icon: 'alert',
        subtitle: 'طبقة رقابية فوق التشغيل: أي تغيير كبير، أو قرار حساس، '
            'أو حدث يحتاج عينًا ثانية يجب أن يمر من هنا.',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي الطابور', value: nf(_queue.length)),
        ImdKpi(label: 'حرج غير مُراجع', value: nf(criticalOpen), color: c.danger),
        ImdKpi(label: 'حساس غير مُراجع', value: nf(sensitiveOpen)),
        ImdKpi(label: 'طلبات مستخدمين', value: nf(pendingUsers), color: c.accent),
        ImdKpi(label: 'أوامر صرف معلقة', value: nf(pendingOrders)),
        ImdKpi(label: 'تحويلات معلقة', value: nf(pendingTransfers), color: c.accent),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          centerVertically: true,
          child: Wrap(spacing: 18, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ImdScoreRing(percent: score),
            SizedBox(
              width: 260,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('مؤشر انضباط المراجعة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdChip(
                    criticalOpen > 0 ? 'يوجد عناصر حرجة مفتوحة' : 'لا عناصر حرجة مفتوحة',
                    tone: criticalOpen > 0 ? ImdTone.err : ImdTone.ok,
                  ),
                  ImdChip(
                    pendingOrders + pendingTransfers > 0
                        ? 'يوجد طابور تشغيلي يحتاج قرارًا'
                        : 'الطابور التشغيلي تحت السيطرة',
                    tone: pendingOrders + pendingTransfers > 0 ? ImdTone.pend : ImdTone.ok,
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'كلما قلّ عدد العناصر الحرجة غير المراجَعة، كان القرار الإداري أسرع، '
                  'والنظام أقرب فعلًا إلى تشغيل منضبط.',
                  style: TextStyle(fontSize: 13, height: 2, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
        ImdPanel(
          title: 'أدوات الفرز السريع',
          icon: 'compass',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdSearchBar(
              controller: _q,
              hint: 'بحث بالمرجع أو الجهة أو الوصف…',
              onChanged: (_) => setState(() {}),
              actions: [
                SizedBox(
                  width: 180,
                  child: ImdSelect<String>(
                    dense: true,
                    items: const [('ALL', 'كل المستويات'), ('critical', 'حرج'), ('sensitive', 'حساس')],
                    value: _level,
                    onChanged: (v) => setState(() => _level = v ?? 'ALL'),
                  ),
                ),
                ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
              ],
            ),
            const ImdNote('هذه ليست شاشة سجلات فحسب، بل شاشة قرار: كل عنصر هنا إما يحتاج حسمًا، '
                'وإما يحتاج وسمًا بأنه تمت مراجعته إداريًا.'),
          ]),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'طابور المراجعة الآن',
          icon: 'download',
          child: _filteredQueue.isEmpty
              ? _emptyCard('✅ الطابور نظيف', 'لا توجد عناصر حساسة مفتوحة تطلب تدخلًا الآن.')
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final it in _filteredQueue.take(120)) _queueItem(it),
                ]),
        ),
        ImdPanel(
          title: 'آخر التغييرات الحساسة',
          icon: 'clock',
          child: _filteredLogs.isEmpty
              ? _emptyCard('لا تغيرات حساسة مطابقة', 'غيّر الفلتر أو حدّث الشاشة.')
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final r in _filteredLogs.take(120)) _logCard(r),
                ]),
        ),
      ]),
    ]);
  }

  Widget _emptyCard(String title, String desc) {
    final c = context.imd;
    return ImdSoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ImdEmojiText(title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.accent)),
        const SizedBox(height: 6),
        Text(desc, style: TextStyle(fontSize: 12.5, color: c.muted)),
      ]),
    );
  }

  /// `smqBadge(level)`
  static ImdChip _badge(String level) =>
      level.toLowerCase() == 'critical'
          ? const ImdChip('حرج', tone: ImdTone.err)
          : const ImdChip('حساس', tone: ImdTone.pend);

  /// `smqStatusTxt(item)`
  Widget _statusChip(_QueueItem it) => switch (it.kind) {
        'USER_PENDING' => const ImdChip('بانتظار قرار', tone: ImdTone.pend),
        'ISSUE_ORDER' => const ImdChip('أمر صرف معلق', tone: ImdTone.pend),
        'TRANSFER_PENDING' => const ImdChip('تحويل معلق', tone: ImdTone.pend),
        _ => const ImdChip('مراجعة مطلوبة', tone: ImdTone.code),
      };

  /// عنصر طابور بنقطة حالة ملوّنة (`.status-item`).
  Widget _queueItem(_QueueItem it) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: it.level == 'critical' ? c.danger : c.warn,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _badge(it.level),
              Text(it.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
              _statusChip(it),
              if (it.when.isNotEmpty) ImdChip(it.when, tone: ImdTone.off),
            ]),
            const SizedBox(height: 6),
            Text(it.desc, style: TextStyle(fontSize: 12.8, height: 1.9, color: c.muted)),
            if (_chips(it.refNo, it.warehouse, it.target, it.actor).isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _chips(it.refNo, it.warehouse, it.target, it.actor),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (it.page.isNotEmpty)
                ImdButton.outline(
                  label: 'فتح الشاشة',
                  icon: 'arrow-down-right',
                  small: true,
                  onPressed: () => _go(it.page),
                ),
              if (it.kind == 'AUDIT_REVIEW' && it.logId.isNotEmpty)
                ImdButton(
                  label: 'تمت المراجعة',
                  icon: 'check',
                  small: true,
                  onPressed: () => _markReviewed(it.logId),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _logCard(AuditLog r) {
    final c = context.imd;
    final reviewed = _reviewed.contains(r.id);
    final actor = r.actorName.isNotEmpty ? r.actorName : r.actorEmail;
    return ImdDocCard(
      head: [
        _badge(r.risk),
        ImdChip(auditActionLabel(r.action), tone: ImdTone.code),
        ImdChip(reviewed ? 'تمت المراجعة' : 'غير مُراجع', tone: reviewed ? ImdTone.ok : ImdTone.pend),
        if (r.logDate.isNotEmpty) ImdChip(r.logDate, tone: ImdTone.off),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(r.summary, style: TextStyle(fontSize: 12.8, height: 1.9, color: c.muted)),
        if (_chips(r.refNo, r.warehouse, r.target, actor).isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _chips(r.refNo, r.warehouse, r.target, actor)),
        ],
      ]),
      actions: [
        ImdButton.outline(
          label: 'فتح السجل',
          icon: 'arrow-down-right',
          small: true,
          onPressed: () => _go('auditTrail'),
        ),
        if (!reviewed)
          ImdButton(
            label: 'تمت المراجعة',
            icon: 'check',
            small: true,
            onPressed: () => _markReviewed(r.id),
          ),
      ],
    );
  }

  List<Widget> _chips(String refNo, String warehouse, String target, String actor) => [
        if (refNo.isNotEmpty) ImdChip(refNo, tone: ImdTone.code),
        if (warehouse.isNotEmpty) ImdChip(warehouse, tone: ImdTone.off, icon: 'warehouse'),
        if (target.isNotEmpty) ImdChip(target, tone: ImdTone.off, icon: 'target'),
        if (actor.isNotEmpty) ImdChip(actor, tone: ImdTone.off, icon: 'user'),
      ];
}
