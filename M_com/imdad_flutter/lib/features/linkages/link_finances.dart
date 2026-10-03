import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/access_control.dart';
import 'link_export.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// تبويب «مالية الإمداد» — ثلاثة فروع مترابطة، **بلا ارتباطٍ بالأفراد**:
///
/// * **العهد**: عهدةٌ تخصّ جهةً مسؤولة (مستودع/مطبخ/مكتب…) وتُفتح بالتسليح،
///   مع تنبيهٍ للمتأخرة عن آخر أجل.
/// * **الإخلاءات**: إغلاقٌ ماليٌّ لعهدةٍ أو عقد؛ تسجيله يغلق مرجعه،
///   وحذفه يعيد فتحه.
/// * **العقود**: عقود المشتريات مع المورد والقيمة ومدّة التنفيذ.
class LinkFinancesTab extends StatefulWidget {
  const LinkFinancesTab({super.key, required this.repo, required this.perm});

  final LinkageRepo repo;
  final Perm perm;

  @override
  State<LinkFinancesTab> createState() => _LinkFinancesTabState();
}

class _LinkFinancesTabState extends State<LinkFinancesTab> {
  String _sub = 'custody'; // custody | clearances | contracts
  final _q = TextEditingController();
  String _view = ''; // عامل تصفية الفرع الحالي
  List<LinkFinCustody>? _custodies;
  List<LinkClearance>? _clearances;
  List<LinkPurchaseContract>? _contracts;
  List<String> _holders = const [];

  bool get _canCreate => widget.perm.has('linkages', PermAction.create);
  bool get _canEdit => widget.perm.has('linkages', PermAction.edit);
  bool get _canDelete => widget.perm.has('linkages', PermAction.delete);
  bool get _canExport => widget.perm.has('linkages', PermAction.export);

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
    final custodies = await widget.repo.custodies();
    final clearances = await widget.repo.clearances();
    final contracts = await widget.repo.contracts();
    final holders = await widget.repo.terms('holder');
    if (!mounted) return;
    setState(() {
      _custodies = custodies;
      _clearances = clearances;
      _contracts = contracts;
      _holders = [for (final t in holders) t.name];
    });
  }

  void _switch(String v) => setState(() {
        _sub = v;
        _view = '';
        _q.clear();
      });

  // ───────────────── العهد ─────────────────

  /// عهدةٌ قائمةٌ تجاوزت آخر أجلها.
  bool _overdue(LinkFinCustody e) =>
      !e.cleared &&
      e.dueDate.isNotEmpty &&
      (DateTime.tryParse(e.dueDate)?.isBefore(DateTime.now()) ?? false);

  List<LinkFinCustody> get _custodyRows {
    final q = _q.text.trim().toLowerCase();
    return (_custodies ?? const <LinkFinCustody>[]).where((c) {
      if (_view == 'open' && c.cleared) return false;
      if (_view == 'cleared' && !c.cleared) return false;
      if (q.isEmpty) return true;
      return [c.custodyNo, c.holder, c.title, c.serialNo].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _addOrEditCustody([LinkFinCustody? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    if (initial != null && !_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: initial == null ? 'تسجيل عهدة' : 'تعديل العهدة: ${initial.title}',
      icon: 'shield',
      maxWidth: 760,
      builder: (ctx) => _CustodySheet(holders: _holders, initial: initial, actor: widget.perm.email),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظت العهدة');
    }
  }

  Future<void> _exportCustodies() async {
    final rows = _custodyRows;
    await linkExportExcel(
      context,
      sheetName: 'العهد',
      fileName: 'العهد-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الرقم', 'الجهة المسؤولة', 'البيان', 'المسلسل', 'الكمية', 'الوحدة', 'القيمة', 'التسليم', 'آخر أجل', 'الحالة', 'تاريخ الإخلاء'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].custodyNo,
            rows[i].holder,
            rows[i].title,
            rows[i].serialNo,
            nf(rows[i].qty),
            rows[i].unit,
            nf(rows[i].valueAmount),
            _d(rows[i].custodyDate),
            _d(rows[i].dueDate),
            rows[i].cleared ? 'مُخلّاة' : (_overdue(rows[i]) ? 'متأخرة' : 'قائمة'),
            rows[i].cleared ? _d(rows[i].clearedDate) : '',
          ],
      ],
      numericColumns: const {0, 5, 7},
    );
  }

  // ───────────────── الإخلاءات ─────────────────

  List<LinkClearance> get _clearanceRows {
    final q = _q.text.trim().toLowerCase();
    return (_clearances ?? const <LinkClearance>[]).where((c) {
      if (_view.isNotEmpty && c.kind != _view) return false;
      if (q.isEmpty) return true;
      return [c.clearanceNo, c.refTitle, c.partyName, c.notes].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  /// [preset]: إخلاءٌ يُفتح من صف عهدةٍ أو عقد فيحمل مرجعه جاهزًا.
  Future<void> _addClearance({String kind = LinkClearanceKind.custody, String refId = ''}) async {
    if (!_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: 'تسجيل إخلاء',
      icon: 'check-circle',
      maxWidth: 700,
      builder: (ctx) => _ClearanceSheet(
        openCustodies: [for (final c in _custodies ?? const <LinkFinCustody>[]) if (!c.cleared) c],
        openContracts: [for (final c in _contracts ?? const <LinkPurchaseContract>[]) if (c.status == LinkContractStatus.open) c],
        kind: kind,
        refId: refId,
        actor: widget.perm.email,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ سُجّل الإخلاء');
    }
  }

  Future<void> _deleteClearance(LinkClearance e) async {
    if (!await imdConfirm(
      context,
      'حذف الإخلاء «${e.refTitle.isEmpty ? e.clearanceNo : e.refTitle}»؟ ستعود العهدة/العقد المرتبط إلى حالته القائمة.',
      ok: 'حذف',
      danger: true,
    )) {
      return;
    }
    await widget.repo.deleteClearance(e, actor: widget.perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ حُذف الإخلاء');
  }

  Future<void> _exportClearances() async {
    final rows = _clearanceRows;
    await linkExportExcel(
      context,
      sheetName: 'الإخلاءات',
      fileName: 'الإخلاءات-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الرقم', 'النوع', 'المرجع', 'الجهة', 'المبلغ', 'التاريخ', 'ملاحظات'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].clearanceNo,
            LinkClearanceKind.label(rows[i].kind),
            rows[i].refTitle,
            rows[i].partyName,
            nf(rows[i].amount),
            _d(rows[i].clearanceDate),
            rows[i].notes,
          ],
      ],
      numericColumns: const {0, 5},
    );
  }

  // ───────────────── عقود المشتريات ─────────────────

  List<LinkPurchaseContract> get _contractRows {
    final q = _q.text.trim().toLowerCase();
    return (_contracts ?? const <LinkPurchaseContract>[]).where((c) {
      if (_view.isNotEmpty && c.status != _view) return false;
      if (q.isEmpty) return true;
      return [c.contractNo, c.title, c.supplier].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _addOrEditContract([LinkPurchaseContract? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    if (initial != null && !_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: initial == null ? 'عقد مشتريات جديد' : 'تعديل العقد: ${initial.title}',
      icon: 'clipboard',
      maxWidth: 780,
      builder: (ctx) => _ContractSheet(initial: initial, actor: widget.perm.email),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ العقد');
    }
  }

  Future<void> _exportContracts() async {
    final rows = _contractRows;
    await linkExportExcel(
      context,
      sheetName: 'عقود المشتريات',
      fileName: 'عقود-المشتريات-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الرقم', 'الموضوع', 'المورد', 'القيمة', 'التوقيع', 'البداية', 'النهاية', 'الحالة'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].contractNo,
            rows[i].title,
            rows[i].supplier,
            nf(rows[i].amount),
            _d(rows[i].signDate),
            _d(rows[i].startDate),
            _d(rows[i].endDate),
            LinkContractStatus.label(rows[i].status),
          ],
      ],
      numericColumns: const {0, 4},
    );
  }

  // ───────────────── الواجهة ─────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdSegmented<String>(
        tabs: const [
          ImdTab('custody', 'العهد', icon: 'shield'),
          ImdTab('clearances', 'الإخلاءات', icon: 'check-circle'),
          ImdTab('contracts', 'العقود', icon: 'clipboard'),
        ],
        value: _sub,
        onChanged: _switch,
      ),
      const SizedBox(height: 14),
      if (_sub == 'custody')
        ..._custodyView(c)
      else if (_sub == 'clearances')
        ..._clearanceView(c)
      else
        ..._contractView(c),
    ]);
  }

  List<Widget> _custodyView(ImdColors c) {
    final all = _custodies ?? const <LinkFinCustody>[];
    final overdueCount = all.where(_overdue).length;
    return [
      ImdKpis(children: [
        ImdKpi(label: 'عهد قائمة', value: nf(all.where((e) => !e.cleared).length), icon: 'shield', color: c.accent),
        ImdKpi(label: 'مُخلّاة', value: nf(all.where((e) => e.cleared).length), icon: 'check-circle', color: c.success),
        ImdKpi(label: 'متأخرة عن الإخلاء', value: nf(overdueCount), icon: 'hourglass', color: overdueCount > 0 ? c.danger : c.muted),
        ImdKpi(label: 'قيمة العهد القائمة', value: nf(all.where((e) => !e.cleared).fold<double>(0, (s, e) => s + e.valueAmount)), icon: 'dollar', color: c.info),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو الجهة أو البيان أو المسلسل…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [ImdTab('', 'الكل'), ImdTab('open', 'قائمة'), ImdTab('cleared', 'مُخلّاة')],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportCustodies),
          if (_canCreate) ImdButton(label: 'تسجيل عهدة', icon: 'plus', onPressed: _addOrEditCustody),
        ],
      ),
      if (_custodies == null)
        const ImdLd('جارٍ تحميل العهد…')
      else if (_custodyRows.isEmpty)
        const ImdEmptyBox('لا عهدٍ مطابقة')
      else
        ImdTable(
          columns: const [
            ImdCol('الرقم'),
            ImdCol('الجهة المسؤولة', flex: 2),
            ImdCol('البيان', flex: 2),
            ImdCol('المسلسل'),
            ImdCol('القيمة', numeric: true),
            ImdCol('التسليم'),
            ImdCol('الحالة', flex: 2),
            ImdCol(''),
          ],
          rows: [for (final e in _custodyRows) _custodyRow(c, e)],
          cards: true,
          empty: 'لا عهدٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _custodyRow(ImdColors c, LinkFinCustody e) {
    final overdue = _overdue(e);
    return [
      Text(e.custodyNo.isEmpty ? '—' : e.custodyNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text(e.holder.isEmpty ? '—' : e.holder, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text('${e.title}${e.qty == 1 ? '' : ' × ${nf(e.qty)}${e.unit.isEmpty ? '' : ' ${e.unit}'}'}',
          style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(e.serialNo.isEmpty ? '—' : e.serialNo),
      Text(e.valueAmount == 0 ? '—' : nf(e.valueAmount)),
      Text(_d(e.custodyDate)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ImdChip(
          e.cleared ? 'مُخلّاة ${_d(e.clearedDate)}' : overdue ? 'متأخرة ${nf(linkDaysBetween(e.dueDate, isoDay(DateTime.now())))} يوم' : 'قائمة',
          tone: e.cleared ? ImdTone.ok : overdue ? ImdTone.err : ImdTone.pend,
          icon: e.cleared ? 'check-circle' : overdue ? 'alert' : 'hourglass',
        ),
        if (!e.cleared && e.dueDate.isNotEmpty)
          Text('آخر أجل ${_d(e.dueDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: overdue ? c.danger : c.muted)),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (!e.cleared && _canCreate)
          ImdIconButton(icon: 'check-circle', tooltip: 'تسجيل إخلاء', onPressed: () => _addClearance(refId: e.id)),
        if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _addOrEditCustody(e)),
        if (_canDelete)
          ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف',
              kind: ImdBtnKind.danger,
              onPressed: () async {
                if (!await imdConfirm(context, 'حذف عهدة «${e.title}» وإخلاءاتها نهائيًّا؟', ok: 'حذف', danger: true)) return;
                await widget.repo.deleteCustody(e, actor: widget.perm.email);
                await _load();
              }),
      ]),
    ];
  }

  List<Widget> _clearanceView(ImdColors c) {
    final all = _clearances ?? const <LinkClearance>[];
    return [
      ImdKpis(children: [
        ImdKpi(label: 'الإخلاءات', value: nf(all.length), icon: 'check-circle', color: c.accent),
        ImdKpi(label: 'إخلاء عهد', value: nf(all.where((e) => e.kind == LinkClearanceKind.custody).length), icon: 'shield', color: c.info),
        ImdKpi(label: 'إخلاء عقود', value: nf(all.where((e) => e.kind == LinkClearanceKind.contract).length), icon: 'clipboard', color: c.warn),
        ImdKpi(label: 'إجمالي المبالغ المسوّاة', value: nf(all.fold<double>(0, (s, e) => s + e.amount)), icon: 'dollar', color: c.success),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو المرجع أو الجهة…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [
              ImdTab('', 'الكل'),
              ImdTab(LinkClearanceKind.custody, 'عهد'),
              ImdTab(LinkClearanceKind.contract, 'عقود'),
              ImdTab(LinkClearanceKind.other, 'حر'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportClearances),
          if (_canCreate) ImdButton(label: 'تسجيل إخلاء', icon: 'plus', onPressed: _addClearance),
        ],
      ),
      if (_clearances == null)
        const ImdLd('جارٍ تحميل الإخلاءات…')
      else if (_clearanceRows.isEmpty)
        const ImdEmptyBox('لا إخلاءاتٍ مطابقة')
      else
        ImdTable(
          columns: const [
            ImdCol('الرقم'),
            ImdCol('النوع'),
            ImdCol('المرجع', flex: 2),
            ImdCol('الجهة', flex: 2),
            ImdCol('المبلغ', numeric: true),
            ImdCol('التاريخ'),
            ImdCol(''),
          ],
          rows: [
            for (final e in _clearanceRows)
              [
                Text(e.clearanceNo.isEmpty ? '—' : e.clearanceNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                ImdChip(LinkClearanceKind.label(e.kind), tone: LinkClearanceKind.tone(e.kind)),
                Text(e.refTitle.isEmpty ? '—' : e.refTitle, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                Text(e.partyName.isEmpty ? '—' : e.partyName),
                Text(e.amount == 0 ? '—' : nf(e.amount)),
                Text(_d(e.clearanceDate)),
                if (_canDelete)
                  ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _deleteClearance(e))
                else
                  const SizedBox.shrink(),
              ],
          ],
          cards: true,
          empty: 'لا إخلاءاتٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _contractView(ImdColors c) {
    final all = _contracts ?? const <LinkPurchaseContract>[];
    return [
      ImdKpis(children: [
        ImdKpi(label: 'العقود', value: nf(all.length), icon: 'clipboard', color: c.accent),
        ImdKpi(label: 'القيمة الإجمالية', value: nf(all.fold<double>(0, (s, e) => s + e.amount)), icon: 'dollar', color: c.info),
        ImdKpi(label: 'قيد التنفيذ', value: nf(all.where((e) => e.status == LinkContractStatus.open).length), icon: 'hourglass', color: c.warn),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو الموضوع أو المورد…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [
              ImdTab('', 'الكل'),
              ImdTab(LinkContractStatus.open, 'قيد التنفيذ'),
              ImdTab(LinkContractStatus.done, 'منفَّذ'),
              ImdTab(LinkContractStatus.canceled, 'ملغى'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportContracts),
          if (_canCreate) ImdButton(label: 'عقد جديد', icon: 'plus', onPressed: _addOrEditContract),
        ],
      ),
      if (_contracts == null)
        const ImdLd('جارٍ تحميل العقود…')
      else if (_contractRows.isEmpty)
        const ImdEmptyBox('لا عقودٍ مطابقة')
      else
        ImdTable(
          columns: const [
            ImdCol('الرقم'),
            ImdCol('الموضوع', flex: 2),
            ImdCol('المورد'),
            ImdCol('القيمة', numeric: true),
            ImdCol('التوقيع'),
            ImdCol('النهاية'),
            ImdCol('الحالة'),
            ImdCol(''),
          ],
          rows: [for (final e in _contractRows) _contractRow(c, e)],
          cards: true,
          empty: 'لا عقودٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _contractRow(ImdColors c, LinkPurchaseContract e) {
    return [
      Text(e.contractNo.isEmpty ? '—' : e.contractNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text(e.title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(e.supplier.isEmpty ? '—' : e.supplier),
      Text(nf(e.amount)),
      Text(_d(e.signDate)),
      Text(_d(e.endDate)),
      ImdChip(LinkContractStatus.label(e.status), tone: LinkContractStatus.tone(e.status)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (e.status == LinkContractStatus.open && _canCreate)
          ImdIconButton(
              icon: 'check-circle',
              tooltip: 'تسجيل إخلاء',
              onPressed: () => _addClearance(kind: LinkClearanceKind.contract, refId: e.id)),
        if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _addOrEditContract(e)),
        if (_canDelete)
          ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف',
              kind: ImdBtnKind.danger,
              onPressed: () async {
                if (!await imdConfirm(context, 'حذف العقد «${e.title}» نهائيًّا؟', ok: 'حذف', danger: true)) return;
                await widget.repo.deleteContract(e, actor: widget.perm.email);
                await _load();
              }),
      ]),
    ];
  }
}

// ═══════════════ نماذج العهدة والإخلاء والعقد ═══════════════

/// منتقي الفرد المشترك — القوائم المالية والتسليحية كلها تربط سجلها بفردٍ
/// من القوة البشرية بهذه القائمة نفسها.
class LinkPersonPicker extends StatelessWidget {
  const LinkPersonPicker({super.key, required this.persons, required this.value, required this.onChanged, this.optional = false});

  final List<LinkPerson> persons;
  final String value;
  final ValueChanged<String> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return ImdSelect<String>(
      items: [
        if (optional) ('', 'بلا ارتباط'),
        for (final p in persons) (p.id, p.militaryNo.isEmpty ? p.fullName : '${p.fullName} — ${p.militaryNo}'),
      ],
      value: value,
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _CustodySheet extends StatefulWidget {
  const _CustodySheet({required this.holders, required this.initial, required this.actor});

  final List<String> holders;
  final LinkFinCustody? initial;
  final String actor;

  @override
  State<_CustodySheet> createState() => _CustodySheetState();
}

class _CustodySheetState extends State<_CustodySheet> {
  late final _no = TextEditingController(text: widget.initial?.custodyNo ?? '');
  late final _holder = TextEditingController(text: widget.initial?.holder ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _serial = TextEditingController(text: widget.initial?.serialNo ?? '');
  late final _qty = TextEditingController(text: widget.initial == null ? '1' : nf(widget.initial!.qty));
  late final _unit = TextEditingController(text: widget.initial?.unit ?? '');
  late final _value = TextEditingController(text: widget.initial == null || widget.initial!.valueAmount == 0 ? '' : widget.initial!.valueAmount.toString());
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late String _custodyDate = widget.initial?.custodyDate ?? isoDay(DateTime.now());
  late String _dueDate = widget.initial?.dueDate ?? '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_no, _holder, _title, _serial, _qty, _unit, _value, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(BuildContext ctx) async {
    if (_holder.text.trim().isEmpty) return showImdToast(ctx, '✖ الجهة المسؤولة عن العهدة مطلوبة', error: true);
    if (_title.text.trim().isEmpty) return showImdToast(ctx, '✖ بيان العهدة مطلوب', error: true);
    setState(() => _busy = true);
    final repo = LinkageRepo(ctx.read<AppDatabase>());
    final data = LinkFinCustodiesCompanion(
      custodyNo: Value(_no.text.trim()),
      holder: Value(_holder.text.trim()),
      title: Value(_title.text.trim()),
      serialNo: Value(_serial.text.trim()),
      qty: Value(double.tryParse(_qty.text.trim()) ?? 1),
      unit: Value(_unit.text.trim()),
      valueAmount: Value(double.tryParse(_value.text.trim()) ?? 0),
      custodyDate: Value(_custodyDate),
      dueDate: Value(_dueDate),
      notes: Value(_notes.text.trim()),
      updatedAt: Value(DateTime.now()),
    );
    if (widget.initial == null) {
      await repo.insertCustody(
        data.copyWith(id: Value(Ids.next('lc')), createdBy: Value(widget.actor), createdAt: Value(DateTime.now())),
        actor: widget.actor,
      );
    } else {
      await repo.updateCustody(widget.initial!, data, actor: widget.actor);
    }
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 3, minItemWidth: 180, gap: 10, children: [
        ImdLabeled('رقم العهدة', ImdFld(controller: _no)),
        ImdLabeled('الجهة المسؤولة * (اكتب جديدًا لإضافته)', ImdFld(controller: _holder, suggestions: widget.holders)),
        ImdLabeled('بيان العهدة *', ImdFld(controller: _title)),
        ImdLabeled('المسلسل / البطاقة', ImdFld(controller: _serial)),
        ImdLabeled('الكمية', ImdFld(controller: _qty, number: true)),
        ImdLabeled('الوحدة', ImdFld(controller: _unit)),
        ImdLabeled('القيمة', ImdFld(controller: _value, number: true)),
        ImdLabeled('تاريخ التسليم', ImdDateField(value: _custodyDate, onChanged: (v) => setState(() => _custodyDate = v))),
        ImdLabeled('آخر أجل للإخلاء', ImdDateField(value: _dueDate, onChanged: (v) => setState(() => _dueDate = v))),
      ]),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'حفظ العهدة', icon: 'save', busy: _busy, onPressed: () => _save(context)),
      ]),
    ]);
  }
}

class _ClearanceSheet extends StatefulWidget {
  const _ClearanceSheet({
    required this.openCustodies,
    required this.openContracts,
    required this.kind,
    required this.refId,
    required this.actor,
  });

  final List<LinkFinCustody> openCustodies;
  final List<LinkPurchaseContract> openContracts;
  final String kind;
  final String refId;
  final String actor;

  @override
  State<_ClearanceSheet> createState() => _ClearanceSheetState();
}

class _ClearanceSheetState extends State<_ClearanceSheet> {
  late String _kind = widget.kind;
  late String _refId = widget.refId;
  final _no = TextEditingController();
  final _party = TextEditingController();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _date = isoDay(DateTime.now());
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fillFromRef();
  }

  @override
  void dispose() {
    for (final c in [_no, _party, _title, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// اختيار المرجع يملأ الجهة والبيان والمبلغ؛ ويبقى كلها قابلًا للتعديل.
  void _fillFromRef() {
    if (_kind == LinkClearanceKind.custody) {
      for (final c in widget.openCustodies) {
        if (c.id == _refId) {
          _party.text = c.holder;
          _title.text = c.title;
          _amount.text = c.valueAmount == 0 ? '' : c.valueAmount.toString();
        }
      }
    } else if (_kind == LinkClearanceKind.contract) {
      for (final c in widget.openContracts) {
        if (c.id == _refId) {
          _party.text = c.supplier;
          _title.text = c.title;
          _amount.text = c.amount == 0 ? '' : c.amount.toString();
        }
      }
    }
  }

  Future<void> _save(BuildContext ctx) async {
    if (_kind != LinkClearanceKind.other && _refId.isEmpty) {
      return showImdToast(ctx, '✖ اختر العهدة أو العقد المراد إخلاؤه', error: true);
    }
    if (_kind == LinkClearanceKind.other && _title.text.trim().isEmpty) {
      return showImdToast(ctx, '✖ بيان الإخلاء مطلوب', error: true);
    }
    setState(() => _busy = true);
    await LinkageRepo(ctx.read<AppDatabase>()).addClearance(
      kind: _kind,
      refId: _kind == LinkClearanceKind.other ? '' : _refId,
      clearanceNo: _no.text.trim(),
      clearanceDate: _date,
      partyName: _party.text.trim(),
      refTitle: _title.text.trim(),
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      notes: _notes.text.trim(),
      actor: widget.actor,
    );
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final refs = _kind == LinkClearanceKind.custody
        ? [for (final c in widget.openCustodies) (c.id, '${c.custodyNo.isEmpty ? '' : '${c.custodyNo} · '}${c.title} — ${c.holder}')]
        : [for (final c in widget.openContracts) (c.id, '${c.contractNo.isEmpty ? '' : '${c.contractNo} · '}${c.title} — ${c.supplier}')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('تسجيل الإخلاء يُغلق العهدة (مُخلّاة) أو العقد (منفَّذ) ويبقى محفوظًا، وحذفه يُعيد فتح مرجعه.'),
      ImdGrid(columns: 2, minItemWidth: 220, gap: 10, children: [
        ImdLabeled(
            'نوع الإخلاء',
            ImdSelect<String>(
              items: [for (final e in LinkClearanceKind.meta.entries) (e.key, e.value.$1)],
              value: _kind,
              onChanged: (v) => setState(() {
                _kind = v ?? LinkClearanceKind.custody;
                _refId = '';
              }),
            )),
        if (_kind != LinkClearanceKind.other)
          ImdLabeled(
              _kind == LinkClearanceKind.custody ? 'العهدة *' : 'العقد *',
              ImdSelect<String>(
                items: [('', 'اختر…'), ...refs],
                value: _refId,
                onChanged: (v) => setState(() {
                  _refId = v ?? '';
                  _fillFromRef();
                }),
              )),
        ImdLabeled('رقم الإخلاء', ImdFld(controller: _no)),
        ImdLabeled('تاريخ الإخلاء', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
        ImdLabeled('الجهة المُخلى طرفها', ImdFld(controller: _party)),
        ImdLabeled(_kind == LinkClearanceKind.other ? 'البيان *' : 'البيان', ImdFld(controller: _title)),
        ImdLabeled('المبلغ المسوّى', ImdFld(controller: _amount, number: true)),
      ]),
      ImdLabeled('بيان / ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'تسجيل الإخلاء', icon: 'check-circle', busy: _busy, onPressed: () => _save(context)),
      ]),
    ]);
  }
}

class _ContractSheet extends StatefulWidget {
  const _ContractSheet({required this.initial, required this.actor});

  final LinkPurchaseContract? initial;
  final String actor;

  @override
  State<_ContractSheet> createState() => _ContractSheetState();
}

class _ContractSheetState extends State<_ContractSheet> {
  late final _no = TextEditingController(text: widget.initial?.contractNo ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _supplier = TextEditingController(text: widget.initial?.supplier ?? '');
  late final _amount = TextEditingController(text: widget.initial == null || widget.initial!.amount == 0 ? '' : widget.initial!.amount.toString());
  late final _items = TextEditingController(text: widget.initial?.itemsSummary ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late String _signDate = widget.initial?.signDate ?? '';
  late String _startDate = widget.initial?.startDate ?? '';
  late String _endDate = widget.initial?.endDate ?? '';
  late String _status = widget.initial?.status ?? LinkContractStatus.open;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_no, _title, _supplier, _amount, _items, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(BuildContext ctx) async {
    if (_title.text.trim().isEmpty) return showImdToast(ctx, '✖ موضوع العقد مطلوب', error: true);
    setState(() => _busy = true);
    final repo = LinkageRepo(ctx.read<AppDatabase>());
    final data = LinkPurchaseContractsCompanion(
      contractNo: Value(_no.text.trim()),
      title: Value(_title.text.trim()),
      supplier: Value(_supplier.text.trim()),
      amount: Value(double.tryParse(_amount.text.trim()) ?? 0),
      signDate: Value(_signDate),
      startDate: Value(_startDate),
      endDate: Value(_endDate),
      status: Value(_status),
      itemsSummary: Value(_items.text.trim()),
      notes: Value(_notes.text.trim()),
      updatedAt: Value(DateTime.now()),
    );
    if (widget.initial == null) {
      await repo.insertContract(
        data.copyWith(id: Value(Ids.next('lk')), createdBy: Value(widget.actor), createdAt: Value(DateTime.now())),
        actor: widget.actor,
      );
    } else {
      await repo.updateContract(widget.initial!, data, actor: widget.actor);
    }
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 4, minItemWidth: 165, gap: 10, children: [
        ImdLabeled('رقم العقد', ImdFld(controller: _no)),
        ImdLabeled('الموضوع *', ImdFld(controller: _title)),
        ImdLabeled('المورد', ImdFld(controller: _supplier)),
        ImdLabeled('القيمة', ImdFld(controller: _amount, number: true)),
        ImdLabeled('تاريخ التوقيع', ImdDateField(value: _signDate, onChanged: (v) => setState(() => _signDate = v))),
        ImdLabeled('تاريخ البداية', ImdDateField(value: _startDate, onChanged: (v) => setState(() => _startDate = v))),
        ImdLabeled('تاريخ النهاية', ImdDateField(value: _endDate, onChanged: (v) => setState(() => _endDate = v))),
        ImdLabeled('الحالة', ImdSelect<String>(items: [for (final e in LinkContractStatus.meta.entries) (e.key, e.value.$1)], value: _status, onChanged: (v) => setState(() => _status = v ?? LinkContractStatus.open))),
      ]),
      ImdLabeled('ملخص البنود', ImdFld(controller: _items, maxLines: 2)),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'حفظ العقد', icon: 'save', busy: _busy, onPressed: () => _save(context)),
      ]),
    ]);
  }
}
