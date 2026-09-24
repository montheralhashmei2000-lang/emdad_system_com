import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/movements_repo.dart';

/// أوامر التوريد المعلقة — نقل مطابق لـ `renderPendingOrders()`:
/// أوامر الصرف (status=ORDER) مجمّعة برقم المرجع، مع اعتمادها وخصم الرصيد أو رفضها بسبب.
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  final _q = TextEditingController();
  List<Issue>? _docs;

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

  /// `poLoad()`
  Future<void> _load() async {
    final rows = await (_db.select(_db.issues)..where((t) => t.status.equals('ORDER'))).get();
    if (mounted) setState(() => _docs = rows);
  }

  Map<String, List<Issue>> _groups() {
    final q = _q.text.trim().toLowerCase();
    final groups = <String, List<Issue>>{};
    for (final d in _docs ?? const <Issue>[]) {
      if (q.isNotEmpty &&
          ![d.refNo, d.itemName, d.recipientDisplay, d.warehouse].any((v) => v.toLowerCase().contains(q))) {
        continue;
      }
      groups.putIfAbsent(d.refNo.isNotEmpty ? d.refNo : '_${d.id}', () => []).add(d);
    }
    return groups;
  }

  Future<void> _approve(String k, List<Issue> g) async {
    final need = <String, double>{};
    for (final d in g) {
      need[d.itemId] = (need[d.itemId] ?? 0) + d.baseQty;
    }
    // الويب يفحص رصيد الصنف الإجمالي (items.qty) لا رصيد المستودع.
    final totals = await MovementsRepo(_db).balances();
    final items = {for (final i in await _db.select(_db.items).get()) i.id: i};
    for (final e in need.entries) {
      final bal = (items[e.key]?.qty ?? 0) + (totals[e.key] ?? 0);
      if (bal < e.value) {
        if (mounted) {
          showImdToast(context, '✖ الرصيد الحالي لا يكفي لاعتماد الأمر بالكامل (${nf(bal)} متاح، المطلوب ${nf(e.value)})');
        }
        return;
      }
    }
    if (!mounted || !await imdConfirm(context, 'اعتماد أمر الصرف «$k» وخصم الكميات من الرصيد؟')) return;
    if (!mounted) return;
    final by = Perm.of(context).email;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.update(_db.issues)..where((t) => t.id.equals(d.id)))
              .write(IssuesCompanion(status: const Value('COMPLETED'), approvedBy: Value(by)));
        }
      });
      if (!mounted) return;
      showImdToast(context, '✔ اعتُمد الأمر وتم خصم الرصيد');
      await _load();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _reject(List<Issue> g) async {
    final reason = await imdPrompt(context, 'سبب رفض الأمر:');
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    final by = Perm.of(context).email;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.update(_db.issues)..where((t) => t.id.equals(d.id))).write(IssuesCompanion(
            status: const Value('REJECTED'),
            rejectReason: Value(reason.trim()),
            rejectedBy: Value(by),
          ));
        }
      });
      if (!mounted) return;
      showImdToast(context, '✖ رُفض الأمر');
      await _load();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final w = Perm.of(context).writable('pendingOrders');
    final groups = _groups();
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'أوامر التوريد المعلقة',
        icon: 'bell',
        subtitle: 'أوامر الصرف الموجّهة من الإدارة بانتظار اعتماد أمين المستودع أو رفضها مع كتابة المبررات',
      ),
      ImdICard(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 14, color: c.text),
            decoration: imdFieldDecoration(context, hint: 'المرجع أو الصنف أو الجهة المستفيدة…'),
          ),
        ),
      ),
      if (_docs == null)
        const ImdLd('جارٍ التحميل…')
      else if (groups.isEmpty)
        const ImdICard(child: ImdLdText('لا توجد أوامر توريد/صرف معلقة حاليًا 👌'))
      else ...[
        ImdChipsRow(children: [ImdChip('أوامر معلقة: ${nf(groups.length)}', tone: ImdTone.pend)]),
        for (final e in groups.entries) _card(context, e.key, e.value, w),
      ],
    ]);
  }

  /// `.dcard`
  Widget _card(BuildContext context, String k, List<Issue> g, bool w) {
    final c = context.imd;
    final f = g.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ImdChip(k, tone: ImdTone.code),
          Text(f.recipientDisplay.isEmpty ? '—' : f.recipientDisplay,
              style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
          ImdChip(f.date.isEmpty ? '—' : f.date, tone: ImdTone.off),
          ImdChip('${nf(g.length)} صنف', tone: ImdTone.ok),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ImdIcon('warehouse', size: 13, color: c.muted),
            const SizedBox(width: 4),
            Text(f.warehouse, style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(children: [
              for (var i = 0; i < g.length; i++) ...[
                if (i > 0) const TextSpan(text: ' · '),
                TextSpan(text: '${g[i].itemName} '),
                TextSpan(text: nf(g[i].qty), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ${g[i].unitName}'),
              ],
            ]),
            style: TextStyle(fontSize: 13, height: 1.9, color: c.text),
          ),
        ),
        if (w)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ImdRbar(bottom: 0, children: [
              ImdButton(label: 'اعتماد الصرف وخصم الرصيد', icon: 'check', small: true, onPressed: () => _approve(k, g)),
              ImdButton(label: 'رفض الأمر', icon: 'x', small: true, kind: ImdBtnKind.danger, onPressed: () => _reject(g)),
            ]),
          ),
      ]),
    );
  }
}
