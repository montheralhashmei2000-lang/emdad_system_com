import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/movements_repo.dart';
import 'doc_kit.dart';

/// تبويب «المسودات والأوامر» في شاشة الصرف: مسودات الصرف وأوامر التوجيه
/// المعلقة في نطاق المستخدم، مع اعتمادها أو حذفها.
class IssueDraftsView extends StatefulWidget {
  const IssueDraftsView({super.key});

  @override
  State<IssueDraftsView> createState() => _IssueDraftsViewState();
}

class _IssueDraftsViewState extends State<IssueDraftsView> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final MovementsRepo _moves = MovementsRepo(_db);

  List<Issue>? _drafts;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() => _drafts = null);
    final scope = Perm.of(context).scope;
    final rows = await (_db.select(_db.issues)..where((t) => t.status.isIn(MovementsRepo.approvableIssueStatuses))).get();
    // مسودات المستودعات خارج نطاق المستخدم لا تُعرض له أصلًا، لا أن تُعرض ثم تُرفض.
    if (mounted) setState(() => _drafts = [for (final r in rows) if (scope == null || scope.contains(r.warehouse)) r]);
  }

  Map<String, List<Issue>> _group(List<Issue> docs) {
    final g = <String, List<Issue>>{};
    for (final d in docs) {
      g.putIfAbsent(d.refNo.isNotEmpty ? d.refNo : '_${d.id}', () => []).add(d);
    }
    return g;
  }

  @override
  Widget build(BuildContext context) {
    final docs = _drafts;
    if (docs == null) return const ImdLd('جارٍ تحميل المسودات…');
    final groups = _group(docs);
    if (groups.isEmpty) return const ImdICard(child: ImdLdText('لا توجد مسودات أو أوامر معلقة 👌'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdChipsRow(children: [ImdChip('أوامر ومسودات: ${nf(groups.length)}', tone: ImdTone.code)]),
      for (final e in groups.entries)
        () {
          final f = e.value.first;
          final isOrder = f.status == 'ORDER';
          return ImdDocCard(
            head: [
              ImdChip(isOrder ? '📤 أمر توجيه' : '💾 مسودة', tone: isOrder ? ImdTone.ok : ImdTone.pend),
              ImdChip(e.key, tone: ImdTone.code),
              Text(f.recipientDisplay.isEmpty ? '—' : f.recipientDisplay, style: const TextStyle(fontWeight: FontWeight.w700)),
              ImdChip(f.date.isEmpty ? '—' : f.date, tone: ImdTone.off),
              ImdChip('${nf(e.value.length)} صنف', tone: ImdTone.ok),
              ImdDocWarehouse(f.warehouse),
            ],
            actions: [
              ImdButton(label: 'اعتماد وصرف الرصيد', icon: 'check', small: true, onPressed: () => _approveDraft(e.key, e.value)),
              ImdButton(label: 'حذف', icon: 'trash', small: true, kind: ImdBtnKind.danger, onPressed: () => _deleteDraft(e.key, e.value)),
            ],
          );
        }(),
    ]);
  }

  Future<void> _approveDraft(String k, List<Issue> g) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'issue', 'approve')) return;
    if (!perm.canWh(g.first.warehouse)) return showImdToast(context, Perm.scopeBlock(g.first.warehouse));
    if (!await imdConfirm(context, 'اعتماد أمر الصرف وخصم الرصيد المخزني لجميع الأصناف؟')) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      // فحص الرصيد والتجميد والاعتماد في مكان واحد: رصيد مستودع السند لا الإجمالي.
      final res = await _moves.approveIssues(g, actor: actor);
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      showImdToast(context, '✔ اعتُمد السند وتم خصم الرصيد');
      await _loadDrafts();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _deleteDraft(String k, List<Issue> g) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'issue', 'create')) return;
    if (!perm.canWh(g.first.warehouse)) return showImdToast(context, Perm.scopeBlock(g.first.warehouse));
    if (!await imdConfirm(context, 'حذف هذه المسودة نهائياً؟', ok: 'حذف', danger: true)) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.delete(_db.issues)..where((t) => t.id.equals(d.id))).go();
        }
      });
      await AuditRepo(_db).write('ISSUE_DRAFT_DELETED', 'issue', 'حذف مسودة صرف',
          details: {
            'refNo': k,
            'warehouse': g.first.warehouse,
            'target': g.first.recipientDisplay,
            'status': 'DELETED',
            'itemCount': g.length,
            'risk': 'sensitive',
          },
          actor: actor);
      if (mounted) showImdToast(context, '✔ حُذفت المسودة');
      await _loadDrafts();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }
}
