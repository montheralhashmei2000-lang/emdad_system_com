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
import '../../data/repos/catalog_repo.dart';
import 'link_armament.dart';
import 'link_export.dart';
import 'link_finances.dart';
import 'link_person_sheets.dart';
import 'roster_picker.dart';
import 'roster_tables.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// شاشة «المالية»: العهد والإخلاءات وعقود الشراء ومسير العهدة — تبويباتها داخل الشاشة.
class LinkFinancesScreen extends StatelessWidget {
  const LinkFinancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('linkages')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'المالية',
        icon: 'dollar',
        subtitle: 'العهد · الإخلاءات · عقود الشراء · مسير العهدة',
      ),
      ImdPanel(child: LinkFinancesTab(repo: LinkageRepo(context.read<AppDatabase>()), perm: perm)),
    ]);
  }
}

/// شاشة «التسليح»: الأسلحة المسلَّمة للأفراد وحالاتها.
class LinkArmamentScreen extends StatelessWidget {
  const LinkArmamentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('linkages')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'التسليح',
        icon: 'target',
        subtitle: 'الأسلحة المسلَّمة للأفراد وحالاتها',
      ),
      ImdPanel(child: LinkArmamentTab(repo: LinkageRepo(context.read<AppDatabase>()), perm: perm)),
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
  List<String> _camps = const [];
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
      'status': await widget.repo.terms('status'),
    };
    // المعسكرات من دليل الوحدات المستفيدة (أسماء المعسكرات) لا من المستودعات.
    final camps = {for (final u in await CatalogRepo(widget.repo.db).camps()) if (u.name.trim().isNotEmpty) u.name.trim()}.toList()..sort();
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

  /// الحالات المعروفة ثم المضافة من المستخدم.
  List<String> get _allStatuses => [
        ...LinkStatus.meta.keys,
        for (final t in _terms['status'] ?? const <LinkTerm>[])
          if (!LinkStatus.meta.containsKey(t.name)) t.name,
      ];

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

  List<String> _rowText(int i, LinkPerson p) => rosterRow(i, p);

  static const _headers = rosterHeaders;

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
    // المستخدم يحدّد الجداول المراد طباعتها (الكشف الكامل مختارٌ افتراضيًّا).
    final chosen = await pickRosterTables(context, list);
    if (chosen == null || chosen.isEmpty || !mounted) return;
    const signatures = ['امضاء مسؤول الشاشة\n....................', 'قائد الوحدة\n....................'];
    final note = 'عدد الأفراد: ${nf(list.length)} · ${arDate(DateTime.now())}';
    try {
      await DocumentPdf.printDoc(
        doc: chosen.length == 1 && chosen.contains(rosterFullKey)
            // الكشف وحده: الجدول الأصلي كما كان.
            ? PrintDoc(
                title: 'كشف القوة البشرية للإمداد والتموين', landscape: true,
                headers: _headers, rows: [for (var i = 0; i < list.length; i++) _rowText(i, list[i])],
                footerNote: note, signatureLines: signatures,
              )
            : PrintDoc(
                title: 'كشف القوة البشرية للإمداد والتموين', landscape: true,
                sections: buildRosterSections(list, chosen),
                footerNote: note, signatureLines: signatures,
              ),
      );
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
        for (final e in _allStatuses)
          ImdKpi(label: LinkStatus.label(e), value: nf(all.where((p) => p.status == e).length),
            icon: e == LinkStatus.present ? 'check-circle' : 'clock',
            color: ImdChip.colors(c, LinkStatus.tone(e)).$2),
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
                          ? '$critical تنبيه حرج · $high عالي — تجدها في جرس التنبيهات أعلى الشاشة'
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
            items: [('', 'الكل'), for (final e in _allStatuses) (e, LinkStatus.label(e))],
            value: _status, onChanged: (v) { setState(() => _status = v ?? ''); _load(); })),
          ImdLabeled('الوحدة الفرعية', ImdSelect<String>(
            items: [('', 'الكل'), for (final t in _terms['subunit'] ?? const <LinkTerm>[]) (t.name, t.name)],
            value: _subUnit, onChanged: (v) { setState(() => _subUnit = v ?? ''); _load(); })),
          ImdLabeled('المعسكر', ImdSelect<String>(
            items: [('', 'الكل'), for (final w in {..._camps, if (_camp.isNotEmpty) _camp}) (w, w)],
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
          pageSize: 50,
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

class LinkTermsPanel extends StatefulWidget {
  const LinkTermsPanel({super.key, required this.repo, this.canEdit = false});
  final LinkageRepo repo;

  /// إضافة المسميات وحذفها تحتاج صلاحية التعديل؛ الافتراضي قراءةٌ فقط.
  final bool canEdit;
  @override
  State<LinkTermsPanel> createState() => _LinkTermsPanelState();
}

class _LinkTermsPanelState extends State<LinkTermsPanel> {
  final _subunit = TextEditingController();
  final _section = TextEditingController();
  final _job = TextEditingController();
  final _status = TextEditingController();
  Map<String, List<LinkTerm>> _terms = const {};

  @override
  void initState() { super.initState(); _reload(); }

  Future<void> _reload() async {
    final t = {for (final k in const ['subunit', 'section', 'job', 'status']) k: await widget.repo.terms(k)};
    if (mounted) setState(() => _terms = t);
  }

  @override
  void dispose() { _subunit.dispose(); _section.dispose(); _job.dispose(); _status.dispose(); super.dispose(); }

  Widget _kind(ImdColors c, String kind, String label, TextEditingController ctrl, List<LinkTerm> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 8),
      if (items.isEmpty)
        Text('لا قيمٍ بعد — أضف أول اسمٍ أدناه.', style: TextStyle(fontSize: 12.5, color: c.muted))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in items)
            ImdChip(t.name, tone: ImdTone.code, icon: widget.canEdit ? 'x' : null, onTap: !widget.canEdit ? null : () async {
              await widget.repo.deleteTerm(kind, t.name); await _reload();
            }),
        ]),
      if (widget.canEdit) ...[
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: ImdFld(controller: ctrl, hint: 'إضافة اسمٍ جديد…')),
        const SizedBox(width: 8),
        ImdButton(label: 'إضافة', icon: 'plus', small: true, onPressed: () async {
          await widget.repo.addTermIfNew(kind, ctrl.text); ctrl.clear(); await _reload();
        }),
      ]),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('هذه المسميات تملأ اقتراحات نموذج الفرد وقوائم التصفية، والحالات المضافة تظهر عند تغيير حالة الفرد.'),
      const SizedBox(height: 6),
      _kind(c, 'subunit', 'الوحدات الفرعية', _subunit, _terms['subunit'] ?? const []),
      const SizedBox(height: 16),
      _kind(c, 'section', 'الأقسام', _section, _terms['section'] ?? const []),
      const SizedBox(height: 16),
      _kind(c, 'job', 'الأعمال', _job, _terms['job'] ?? const []),
      const SizedBox(height: 16),
      _kind(c, 'status', 'الحالات المضافة (مريض مستشفى، مهمة…)', _status, _terms['status'] ?? const []),
    ]);
  }
}
