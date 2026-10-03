import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/access_control.dart';
import '../../data/repos/linkage_repo.dart';
import 'link_armament.dart';
import 'link_export.dart';
import 'link_finances.dart';
import 'link_person_sheets.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

class LinkagesScreen extends StatefulWidget {
  const LinkagesScreen({super.key});
  @override
  State<LinkagesScreen> createState() => _LinkagesScreenState();
}

class _LinkagesScreenState extends State<LinkagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('linkages') && !perm.has('personnel')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }
    final repo = LinkageRepo(context.read<AppDatabase>());
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'مركز الارتباطات',
        icon: 'link',
        subtitle: 'القوة البشرية · التنبيهات · مالية الإمداد · التسليح',
      ),
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TabBar(controller: _tabs, isScrollable: true, tabs: const [
            Tab(text: 'القوة البشرية'),
            Tab(text: 'التنبيهات'),
            Tab(text: 'المالية'),
            Tab(text: 'التسليح'),
          ]),
          const SizedBox(height: 12),
          // التبويب المختار يُعرض في تدفق الصفحة نفسها (تمرير واحد) لا في ارتفاعٍ
          // ثابت — فيتكيّف مع الجوال والحاسب دون فيض.
          AnimatedBuilder(
            animation: _tabs,
            builder: (ctx, _) => switch (_tabs.index) {
              0 => LinkPersonnelTab(repo: repo, perm: perm),
              1 => _AlertsTab(repo: repo),
              2 => LinkFinancesTab(repo: repo, perm: perm),
              _ => LinkArmamentTab(repo: repo, perm: perm),
            },
          ),
        ]),
      ),
    ]);
  }
}

class LinkPersonnelTab extends StatefulWidget {
  const LinkPersonnelTab({super.key, required this.repo, required this.perm});
  final LinkageRepo repo;
  final Perm perm;
  @override
  State<LinkPersonnelTab> createState() => _LinkPersonnelTabState();
}

class _LinkPersonnelTabState extends State<LinkPersonnelTab> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _status = '', _subUnit = '', _camp = '', _section = '', _job = '';
  int _sortCol = -1;
  bool _sortAsc = true;
  List<LinkPerson>? _persons;
  Map<String, List<LinkTerm>> _terms = const {};
  List<Warehouse> _camps = const [];
  List<LinkAlert> _alerts = const [];
  bool _selectMode = false;
  final Set<String> _selected = {};

  bool get _canCreate => widget.perm.has('personnel', PermAction.create);
  bool get _canEdit => widget.perm.has('personnel', PermAction.edit);
  bool get _canDelete => widget.perm.has('personnel', PermAction.delete);
  bool get _canExport => widget.perm.has('personnel', PermAction.export);
  bool get _canPrint => widget.perm.has('personnel', PermAction.print);

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _debounce?.cancel(); _q.dispose(); super.dispose(); }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () { if (mounted) _load(); });
    setState(() {});
  }

  Future<void> _load() async {
    await widget.repo.ensureSeedTerms();
    final persons = await widget.repo.persons(
      q: _q.text, status: _status, subUnit: _subUnit,
      camp: _camp, section: _section, job: _job);
    final terms = {
      'section': await widget.repo.terms('section'),
      'job': await widget.repo.terms('job'),
      'subunit': await widget.repo.terms('subunit'),
    };
    final camps = await widget.repo.db.select(widget.repo.db.warehouses).get();
    final alerts = await widget.repo.getAlerts();
    if (!mounted) return;
    setState(() {
      _persons = persons; _terms = terms; _camps = camps; _alerts = alerts;
      _selected.removeWhere((id) => !persons.any((p) => p.id == id));
    });
  }

  Future<void> _refresh() async {
    await _load();
    if (mounted) showImdToast(context, '✔ تم التحديث');
  }

  bool get _hasFilter =>
      _q.text.trim().isNotEmpty || _status.isNotEmpty || _subUnit.isNotEmpty ||
      _camp.isNotEmpty || _section.isNotEmpty || _job.isNotEmpty;

  List<LinkPerson> _sortedPersons() {
    final list = [...(_persons ?? const <LinkPerson>[])];
    int cmp(Comparable a, Comparable b) => _sortAsc ? a.compareTo(b) : b.compareTo(a);
    switch (_sortCol) {
      case 0: list.sort((a, b) => cmp(a.fullName, b.fullName));
      case 1: list.sort((a, b) => cmp(a.militaryNo, b.militaryNo));
      case 2: list.sort((a, b) => cmp(a.rank, b.rank));
      case 3: list.sort((a, b) => cmp(a.phone, b.phone));
      case 4: list.sort((a, b) => cmp(a.subUnit, b.subUnit));
      case 5: list.sort((a, b) => cmp(a.camp, b.camp));
      case 6: list.sort((a, b) => cmp(a.section, b.section));
      case 7: list.sort((a, b) => cmp(a.job, b.job));
      case 8: list.sort((a, b) => cmp(LinkStatus.label(a.status), LinkStatus.label(b.status)));
    }
    return list;
  }

  void _toggleSort(int i) => setState(() {
    if (_sortCol == i) { _sortAsc = !_sortAsc; } else { _sortCol = i; _sortAsc = true; }
  });

  Future<void> _addPerson() async {
    if (!_canCreate) return showImdToast(context, '✖ لا تملك صلاحية إضافة الأفراد', error: true);
    final ok = await showLinkPersonForm(context, repo: widget.repo, camps: _camps, terms: _terms, actor: widget.perm.email);
    if (ok) { await _load(); if (mounted) showImdToast(context, '✔ أُضيف الفرد'); }
  }

  Future<void> _editPerson(LinkPerson p) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final ok = await showLinkPersonForm(context, repo: widget.repo, camps: _camps, terms: _terms, initial: p, actor: widget.perm.email);
    if (ok) await _load();
  }

  Future<void> _statusFlow(LinkPerson p) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية تغيير الحالات', error: true);
    if (p.status == LinkStatus.present) {
      if (await showLinkStatusChange(context, repo: widget.repo, person: p, actor: widget.perm.email)) {
        await _load(); if (mounted) showImdToast(context, '✔ سُجّلت الحالة');
      }
      return;
    }
    final choice = await showImdModal<String>(
      context, title: 'الحالة الراهنة: ${LinkStatus.label(p.status)}', icon: 'clock', maxWidth: 480,
      builder: (ctx) => Text('الفرد في حالة «${LinkStatus.label(p.status)}» منذ ${_d(p.statusFrom)}. ما الإجراء؟',
        style: TextStyle(fontSize: 14, color: ctx.imd.text, height: 1.8)),
      actions: (ctx) => [
        ImdButton.outline(label: 'تغيير إلى حالة أخرى', icon: 'swap', onPressed: () => Navigator.of(ctx).pop('change')),
        ImdButton(label: 'تسجيل العودة', icon: 'check-circle', onPressed: () => Navigator.of(ctx).pop('return')),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'return') {
      if (await showLinkReturnAction(context, repo: widget.repo, person: p, actor: widget.perm.email)) {
        await _load(); if (mounted) showImdToast(context, '✔ سُجّلت العودة');
      }
    } else if (await showLinkStatusChange(context, repo: widget.repo, person: p, actor: widget.perm.email)) {
      await _load();
    }
  }

  Future<void> _openProfile(LinkPerson p) async {
    await showLinkPersonProfile(context, repo: widget.repo, person: p, onEdit: () => _editPerson(p), onStatus: () => _statusFlow(p));
    await _load();
  }

  Future<void> _delete(LinkPerson p) async {
    if (!_canDelete) return showImdToast(context, '✖ لا تملك صلاحية الحذف', error: true);
    if (!await imdConfirm(context, 'حذف الفرد «${p.fullName}» نهائيًّا؟', ok: 'حذف نهائي', danger: true)) return;
    await widget.repo.deletePerson(p, actor: widget.perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ حُذف الفرد');
  }

  Future<void> _manageTerms() async {
    await showImdModal<void>(context, title: 'إدارة الأقسام والأعمال', icon: 'sliders', maxWidth: 640,
      builder: (ctx) => _TermsSheet(repo: widget.repo, terms: _terms));
    await _load();
  }

  List<String> _rowText(int i, LinkPerson p) => [
    '${i + 1}', p.fullName, p.militaryNo, p.rank, p.phone, p.phone2,
    p.subUnit, p.camp, p.section, p.job, LinkStatus.label(p.status),
    _d(p.statusFrom), p.statusTo.isEmpty ? '—' : _d(p.statusTo), nf(p.statusDays),
  ];

  static const _headers = [
    'م', 'الاسم', 'الرقم العسكري', 'الرتبة', 'الهاتف', 'هاتف آخر',
    'الوحدة الفرعية', 'المعسكر', 'القسم', 'العمل', 'الحالة', 'من', 'إلى', 'أيام',
  ];

  Future<void> _exportExcel({bool selectedOnly = false}) async {
    if (!_canExport) return showImdToast(context, '✖ لا تملك صلاحية التصدير', error: true);
    var list = _sortedPersons();
    if (selectedOnly && _selected.isNotEmpty) list = list.where((p) => _selected.contains(p.id)).toList();
    await linkExportExcel(context, sheetName: 'القوة البشرية',
      fileName: 'القوة-البشرية-${isoDay(DateTime.now())}.xlsx',
      headers: _headers, rows: [for (var i = 0; i < list.length; i++) _rowText(i, list[i])],
      numericColumns: const {0, 13});
  }

  Future<void> _printRoster() async {
    if (!_canPrint) return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    final list = _sortedPersons();
    try {
      await DocumentPdf.printDoc(doc: PrintDoc(
        title: 'كشف القوة البشرية للإمداد والتموين', landscape: true,
        headers: _headers, rows: [for (var i = 0; i < list.length; i++) _rowText(i, list[i])],
        footerNote: 'عدد الأفراد: ${nf(list.length)} · ${arDate(DateTime.now())}',
        signatureLines: const ['امضاء مسؤول الشاشة\n....................', 'قائد الوحدة\n....................'],
      ));
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  Widget _avatar(ImdColors ctxColors, LinkPerson p, double size) {
    final letter = p.fullName.trim().isEmpty ? '?' : p.fullName.trim().substring(0, 1);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: ctxColors.infoSoft,
      child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.42, color: ctxColors.info)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final all = _persons ?? const <LinkPerson>[];
    final sorted = _sortedPersons();
    final critical = _alerts.where((a) => a.severity == LinkAlertSeverity.critical).length;
    final high = _alerts.where((a) => a.severity == LinkAlertSeverity.high).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي القوة', value: nf(all.length), icon: 'users', color: c.accent),
        for (final e in LinkStatus.meta.entries)
          ImdKpi(label: e.value.$1, value: nf(all.where((p) => p.status == e.key).length),
            icon: e.key == LinkStatus.present ? 'check-circle' : 'clock',
            color: ImdChip.colors(c, e.value.$2).$2),
      ]),
      if (_alerts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Builder(builder: (_) {
          final tone = critical > 0 ? c.danger : high > 0 ? c.warn : c.info;
          final soft = critical > 0 ? c.dangerSoft : high > 0 ? c.warnSoft : c.infoSoft;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              ImdIcon(critical > 0 ? 'alert' : 'bell', size: 20, color: tone),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      critical > 0
                          ? '$critical تنبيه حرج · $high عالي — راجع تبويب التنبيهات'
                          : '${_alerts.length} تنبيه يحتاج انتباهك',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text))),
            ]),
          );
        }),
      ],
      const SizedBox(height: 12),
      ImdPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdGrid(columns: 6, minItemWidth: 165, gap: 12, children: [
          ImdLabeled('بحث', ImdFld(controller: _q, hint: 'الاسم، الرقم العسكري، الهاتف…', onChanged: _onSearchChanged)),
          ImdLabeled('الحالة', ImdSelect<String>(
            items: [('', 'الكل'), for (final e in LinkStatus.meta.entries) (e.key, e.value.$1)],
            value: _status, onChanged: (v) { setState(() => _status = v ?? ''); _load(); })),
          ImdLabeled('الوحدة الفرعية', ImdSelect<String>(
            items: [('', 'الكل'), for (final t in _terms['subunit'] ?? const <LinkTerm>[]) (t.name, t.name)],
            value: _subUnit, onChanged: (v) { setState(() => _subUnit = v ?? ''); _load(); })),
          ImdLabeled('المعسكر', ImdSelect<String>(
            items: [('', 'الكل'), for (final w in _camps) (w.name, w.name)],
            value: _camp, onChanged: (v) { setState(() => _camp = v ?? ''); _load(); })),
          ImdLabeled('القسم', ImdSelect<String>(
            items: [('', 'الكل'), for (final t in _terms['section'] ?? const <LinkTerm>[]) (t.name, t.name)],
            value: _section, onChanged: (v) { setState(() => _section = v ?? ''); _load(); })),
          ImdLabeled('العمل', ImdSelect<String>(
            items: [('', 'الكل'), for (final t in _terms['job'] ?? const <LinkTerm>[]) (t.name, t.name)],
            value: _job, onChanged: (v) { setState(() => _job = v ?? ''); _load(); })),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_canCreate) ImdButton(label: 'إضافة فرد', icon: 'plus', small: true, onPressed: _addPerson),
          ImdButton.outline(label: 'إدارة الأقسام والأعمال', icon: 'sliders', small: true, onPressed: _manageTerms),
          ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _refresh),
          if (_hasFilter) ImdButton.outline(label: 'مسح المرشحات', icon: 'eraser', small: true, onPressed: () {
            _q.clear(); setState(() { _status = _subUnit = _camp = _section = _job = ''; }); _load();
          }),
          ImdButton.outline(label: _selectMode ? 'إلغاء التحديد' : 'تحديد جماعي',
            icon: _selectMode ? 'x' : 'check', small: true,
            onPressed: () => setState(() { _selectMode = !_selectMode; if (!_selectMode) _selected.clear(); })),
          if (_selectMode && _selected.isNotEmpty && _canExport)
            ImdButton.outline(label: 'تصدير المحدد (${_selected.length})', icon: 'download', small: true,
              onPressed: () => _exportExcel(selectedOnly: true)),
          if (_canExport && !_selectMode)
            ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: () => _exportExcel()),
          if (_canPrint) ImdButton.outline(label: 'طباعة الكشف', icon: 'printer', small: true, onPressed: _printRoster),
          ImdChip('النتائج: ${nf(sorted.length)}', tone: ImdTone.ok, icon: 'check'),
        ]),
      ])),
      const SizedBox(height: 16),
      if (_persons == null)
        const ImdLd('جارٍ تحميل القوة البشرية…')
      else if (sorted.isEmpty)
        ImdEmptyState.custom(title: 'لا أفرادٍ مسجَّلين', icon: 'users',
          message: 'سجّل أول فردٍ من قوة الإمداد والتموين.',
          action: _canCreate ? ImdButton(label: 'إضافة فرد', icon: 'plus', onPressed: _addPerson) : null)
      else
        ImdTable(
          columns: [
            if (_selectMode) const ImdCol(''),
            const ImdCol('الاسم', flex: 2),
            const ImdCol('الرقم العسكري'),
            const ImdCol('الرتبة'),
            const ImdCol('الهاتف'),
            const ImdCol('الوحدة'),
            const ImdCol('المعسكر'),
            const ImdCol('القسم'),
            const ImdCol('العمل'),
            const ImdCol('الحالة'),
            const ImdCol(''),
          ],
          rows: [
            for (final p in sorted)
              [
                if (_selectMode)
                  Checkbox(
                      value: _selected.contains(p.id),
                      onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(p.id);
                            } else {
                              _selected.remove(p.id);
                            }
                          })),
                InkWell(
                    onTap: () => _openProfile(p),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _avatar(c, p, 32),
                      const SizedBox(width: 8),
                      Flexible(child: Text(p.fullName, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
                    ])),
                Text(p.militaryNo.isEmpty ? '—' : p.militaryNo),
                Text(p.rank.isEmpty ? '—' : p.rank),
                Text(p.phone.isEmpty ? '—' : p.phone),
                Text(p.subUnit.isEmpty ? '—' : p.subUnit),
                Text(p.camp.isEmpty ? '—' : p.camp),
                Text(p.section.isEmpty ? '—' : p.section),
                Text(p.job.isEmpty ? '—' : p.job),
                ImdChip(LinkStatus.label(p.status), tone: LinkStatus.tone(p.status)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ImdIconButton(icon: 'user', tooltip: 'الملف', onPressed: () => _openProfile(p)),
                  if (_canEdit) ImdIconButton(icon: 'swap', tooltip: 'تغيير الحالة', onPressed: () => _statusFlow(p)),
                  if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _editPerson(p)),
                  if (_canDelete) ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _delete(p)),
                ]),
              ],
          ],
          cards: true,
          empty: 'لا أفراد مطابقين',
          onRowTap: null,
          // عمود التحديد الجماعي يسبق الأعمدة فيُزاح الفهرس به.
          onHeaderTap: (i) => _toggleSort(i - (_selectMode ? 1 : 0)),
          sortIndex: _sortCol + (_selectMode ? 1 : 0),
          sortAsc: _sortAsc,
        ),
    ]);
  }
}

class _AlertsTab extends StatefulWidget {
  const _AlertsTab({required this.repo});
  final LinkageRepo repo;
  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  List<LinkAlert>? _alerts;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final a = await widget.repo.getAlerts();
    if (mounted) setState(() => _alerts = a);
  }
  Color _sevColor(ImdColors c, LinkAlertSeverity s) => switch (s) {
    LinkAlertSeverity.critical => c.danger,
    LinkAlertSeverity.high => c.warn,
    LinkAlertSeverity.medium => c.info,
    LinkAlertSeverity.low => c.muted,
  };
  String _sevLabel(LinkAlertSeverity s) => switch (s) {
    LinkAlertSeverity.critical => 'حرج',
    LinkAlertSeverity.high => 'عالي',
    LinkAlertSeverity.medium => 'متوسط',
    LinkAlertSeverity.low => 'منخفض',
  };
  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    if (_alerts == null) return const ImdLd('جارٍ تحميل التنبيهات…');
    if (_alerts!.isEmpty) {
      return const ImdEmptyState.custom(title: 'لا تنبيهات حاليًا', icon: 'check-circle',
        message: 'كل الحالات والعهد والعقود ضمن الحدود الطبيعية.');
    }
    return ListView.separated(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _alerts!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final a = _alerts![i];
        final col = _sevColor(c, a.severity);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: col.withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ImdIcon('alert', color: col, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: c.text))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(_sevLabel(a.severity), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: col)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(a.body, style: TextStyle(fontSize: 13, color: c.muted, height: 1.5)),
            ])),
          ]),
        );
      },
    );
  }
}

class _TermsSheet extends StatefulWidget {
  const _TermsSheet({required this.repo, required this.terms});
  final LinkageRepo repo;
  final Map<String, List<LinkTerm>> terms;
  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  final _subunit = TextEditingController();
  final _section = TextEditingController();
  final _job = TextEditingController();
  @override
  void dispose() { _subunit.dispose(); _section.dispose(); _job.dispose(); super.dispose(); }

  Widget _kind(ImdColors c, String kind, String label, TextEditingController ctrl, List<LinkTerm> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 8),
      if (items.isEmpty)
        Text('لا قيمٍ بعد — أضف أول اسمٍ أدناه.', style: TextStyle(fontSize: 12.5, color: c.muted))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in items)
            ImdChip(t.name, tone: ImdTone.code, icon: 'x', onTap: () async {
              await widget.repo.deleteTerm(kind, t.name); setState(() {});
            }),
        ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: ImdFld(controller: ctrl, hint: 'إضافة اسمٍ جديد…')),
        const SizedBox(width: 8),
        ImdButton(label: 'إضافة', icon: 'plus', small: true, onPressed: () async {
          await widget.repo.addTermIfNew(kind, ctrl.text); ctrl.clear(); setState(() {});
        }),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('هذه المسميات تملأ اقتراحات نموذج الفرد وقوائم التصفية.'),
      const SizedBox(height: 6),
      _kind(c, 'subunit', 'الوحدات الفرعية', _subunit, widget.terms['subunit'] ?? const []),
      const SizedBox(height: 16),
      _kind(c, 'section', 'الأقسام', _section, widget.terms['section'] ?? const []),
      const SizedBox(height: 16),
      _kind(c, 'job', 'الأعمال', _job, widget.terms['job'] ?? const []),
    ]);
  }
}
