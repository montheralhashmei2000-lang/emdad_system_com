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
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/access_control.dart';
import 'link_export.dart';
import 'link_finances.dart' show LinkPersonPicker;
import 'link_person_sheets.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// تبويب «تسليح الإمداد» — أسلحة الأفراد بتسليمها وردّها، كل سجلٍ مرتبطٌ
/// بفردٍ من القوة البشرية بمعرّفه وملفُّه يُفتح من السجل، مع تصدير Excel.
class LinkArmamentTab extends StatefulWidget {
  const LinkArmamentTab({super.key, required this.repo, required this.perm});

  final LinkageRepo repo;
  final Perm perm;

  @override
  State<LinkArmamentTab> createState() => _LinkArmamentTabState();
}

class _LinkArmamentTabState extends State<LinkArmamentTab> {
  final _q = TextEditingController();
  String _view = ''; // '' | out | returned
  List<LinkArmament>? _rows;
  List<LinkPerson> _persons = const [];

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
    final rows = await widget.repo.armaments();
    final persons = await widget.repo.persons();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _persons = persons;
    });
  }

  List<LinkArmament> get _filtered {
    final q = _q.text.trim().toLowerCase();
    return (_rows ?? const <LinkArmament>[]).where((a) {
      if (_view == 'out' && a.returned) return false;
      if (_view == 'returned' && !a.returned) return false;
      if (q.isEmpty) return true;
      return [a.personName, a.personMilitaryNo, a.weaponType, a.serialNo].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openPerson(String personId) async {
    final person = await widget.repo.personById(personId);
    if (!mounted) return;
    if (person == null) {
      showImdToast(context, 'السجل يحفظ لقطة اسم الفرد فقط — ملفه غير موجود');
      return;
    }
    // أزرار الملف تعمل كما في شاشة القوة البشرية: التعديل وتغيير الحالة.
    await showLinkPersonProfile(
      context,
      repo: widget.repo,
      person: person,
      onEdit: () => _editPerson(person),
      onStatus: () => _changeStatus(person),
    );
    await _load();
  }

  Future<void> _editPerson(LinkPerson p) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final repo = widget.repo;
    await repo.ensureSeedTerms();
    final terms = {
      'section': await repo.terms('section'),
      'job': await repo.terms('job'),
      'subunit': await repo.terms('subunit'),
      'status': await repo.terms('status'),
    };
    final camps = {
      for (final u in await CatalogRepo(repo.db).camps())
        if (u.name.trim().isNotEmpty) u.name.trim(),
    }.toList()
      ..sort();
    if (!mounted) return;
    final ok = await showLinkPersonForm(context, repo: repo, camps: camps, terms: terms, initial: p, actor: widget.perm.email);
    if (ok) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظت بيانات الفرد');
    }
  }

  Future<void> _changeStatus(LinkPerson p) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية تغيير الحالات', error: true);
    final ok = p.status == LinkStatus.present
        ? await showLinkStatusChange(context, repo: widget.repo, person: p, actor: widget.perm.email)
        : await showLinkReturnAction(context, repo: widget.repo, person: p, actor: widget.perm.email);
    if (ok) {
      await _load();
      if (mounted) showImdToast(context, '✔ سُجّلت الحالة');
    }
  }

  Future<void> _edit(LinkArmament a) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: 'تعديل تسليم: ${a.personName}',
      icon: 'edit',
      maxWidth: 700,
      builder: (ctx) => _ArmamentSheet(persons: _persons, initial: a),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ التعديل');
    }
  }

  Future<void> _add() async {
    if (!_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    if (_persons.isEmpty) return showImdToast(context, '✖ سجّل الأفراد أولًا في تبويب القوة البشرية', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: 'تسليم سلاح',
      icon: 'shield',
      maxWidth: 700,
      builder: (ctx) => _ArmamentSheet(persons: _persons),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ سُجّل التسليم');
    }
  }

  Future<void> _export() async {
    final rows = _filtered;
    await linkExportExcel(
      context,
      sheetName: 'تسليح الإمداد',
      fileName: 'تسليح-الإمداد-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الفرد', 'الرقم العسكري', 'نوع السلاح', 'المسلسل', 'الكمية', 'عدد القرون', 'نوع القرون', 'الذخيرة المستلمة', 'تاريخ التسليم', 'حالة السلاح', 'الحالة'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].personName,
            rows[i].personMilitaryNo,
            rows[i].weaponType,
            rows[i].serialNo,
            nf(rows[i].qty),
            nf(rows[i].magazines),
            rows[i].magazineType,
            nf(rows[i].ammoQty),
            _d(rows[i].assignedDate),
            rows[i].condition,
            rows[i].returned ? 'رُدِّد ${_d(rows[i].returnedDate)}' : 'مسلَّم',
          ],
      ],
      numericColumns: const {0, 5, 6, 8},
    );
  }

  Future<void> _return(LinkArmament a) async {
    if (!_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    var date = isoDay(DateTime.now());
    final ok = await showImdModal<bool>(
      context,
      title: 'ردّ السلاح: ${a.weaponType}',
      icon: 'undo',
      maxWidth: 460,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdNote('ردّ السلاح المسلَّم للفرد ${a.personName} — يُغلق السجل ويبقى محفوظًا.'),
        ImdLabeled('تاريخ الردّ', ImdDateField(value: date, onChanged: (v) => date = v)),
      ]),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'تأكيد الردّ', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    if (ok != true) return;
    await widget.repo.returnArmament(a, returnedDate: date, actor: widget.perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ رُدِّع السلاح');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final all = _rows ?? const <LinkArmament>[];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdKpis(children: [
        ImdKpi(label: 'سلاحٌ مسلَّم حاليًّا', value: nf(all.where((a) => !a.returned).length), icon: 'shield', color: c.accent),
        ImdKpi(label: 'مُردَّد', value: nf(all.where((a) => a.returned).length), icon: 'undo', color: c.success),
        ImdKpi(
            label: 'أنواع السلاح',
            value: nf(all.map((a) => a.weaponType).where((t) => t.isNotEmpty).toSet().length),
            icon: 'tag',
            color: c.info),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالفرد أو نوع السلاح أو المسلسل…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [
              ImdTab('', 'الكل'),
              ImdTab('out', 'مسلَّم'),
              ImdTab('returned', 'مُردَّد'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport)
            ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _export),
          if (_canCreate) ImdButton(label: 'تسليم سلاح', icon: 'plus', onPressed: _add),
        ],
      ),
      if (_rows == null)
        const ImdLd('جارٍ تحميل التسليح…')
      else if (_filtered.isEmpty)
        const ImdEmptyBox('لا سجلات تسليحٍ مطابقة')
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('الفرد', flex: 2),
            ImdCol('نوع السلاح'),
            ImdCol('المسلسل'),
            ImdCol('الكمية', numeric: true),
            ImdCol('القرون'),
            ImdCol('الذخيرة', numeric: true),
            ImdCol('تاريخ التسليم'),
            ImdCol('حالة السلاح'),
            ImdCol('الحالة'),
            ImdCol(''),
          ],
          rows: [for (final a in _filtered) _row(context, a)],
          empty: 'لا سجلاتٍ مطابقة',
          onRowTap: null,
        ),
    ]);
  }

  List<Widget> _row(BuildContext context, LinkArmament a) {
    final c = context.imd;
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(a.personName.isEmpty ? '—' : a.personName, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
        if (a.personMilitaryNo.isNotEmpty)
          Text('رقم عسكري: ${a.personMilitaryNo}', style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
      Text(a.weaponType.isEmpty ? '—' : a.weaponType, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(a.serialNo.isEmpty ? '—' : a.serialNo),
      Text(nf(a.qty)),
      Text(a.magazines == 0 && a.magazineType.isEmpty
          ? '—'
          : [if (a.magazines > 0) nf(a.magazines), if (a.magazineType.isNotEmpty) a.magazineType].join(' · ')),
      Text(a.ammoQty > 0 ? nf(a.ammoQty) : '—'),
      Text(_d(a.assignedDate)),
      Text(a.condition.isEmpty ? '—' : a.condition),
      ImdChip(
        a.returned ? 'رُدِّد ${_d(a.returnedDate)}' : 'مسلَّم',
        tone: a.returned ? ImdTone.ok : ImdTone.pend,
        icon: a.returned ? 'undo' : 'shield',
      ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ImdIconButton(icon: 'user', tooltip: 'ملف الفرد', onPressed: () => _openPerson(a.personId)),
        if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل التسليم', onPressed: () => _edit(a)),
        if (!a.returned && _canEdit) ImdIconButton(icon: 'undo', tooltip: 'ردّ السلاح', onPressed: () => _return(a)),
        if (_canDelete)
          ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف',
              kind: ImdBtnKind.danger,
              onPressed: () async {
                if (!await imdConfirm(context, 'حذف سجل تسليح «${a.weaponType}» للفرد ${a.personName} نهائيًّا؟',
                    ok: 'حذف', danger: true)) {
                  return;
                }
                await widget.repo.deleteArmament(a, actor: widget.perm.email);
                await _load();
              }),
      ]),
    ];
  }
}

// ═════════════════════ نموذج التسليم ═════════════════════

class _ArmamentSheet extends StatefulWidget {
  const _ArmamentSheet({required this.persons, this.initial});

  final List<LinkPerson> persons;

  /// سجلٌّ محفوظ يُعدَّل بدل تسجيل تسليمٍ جديد.
  final LinkArmament? initial;

  @override
  State<_ArmamentSheet> createState() => _ArmamentSheetState();
}

class _ArmamentSheetState extends State<_ArmamentSheet> {
  String _personId = '';
  final _weapon = TextEditingController();
  final _serial = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _condition = TextEditingController();
  final _notes = TextEditingController();
  final _mags = TextEditingController();
  final _magType = TextEditingController();
  final _ammo = TextEditingController();
  String _assignedDate = isoDay(DateTime.now());
  bool _busy = false;

  static const _conditions = ['جيد', 'يحتاج صيانة', 'تالف'];
  static const _magTypes = ['صيني', 'روسي'];

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a == null) return;
    _personId = a.personId;
    _weapon.text = a.weaponType;
    _serial.text = a.serialNo;
    _qty.text = '${a.qty}';
    _condition.text = a.condition;
    _notes.text = a.notes;
    _mags.text = a.magazines > 0 ? '${a.magazines}' : '';
    _magType.text = a.magazineType;
    _ammo.text = a.ammoQty > 0 ? '${a.ammoQty}' : '';
    _assignedDate = a.assignedDate.isEmpty ? _assignedDate : a.assignedDate;
  }

  @override
  void dispose() {
    for (final c in [_weapon, _serial, _qty, _condition, _notes, _mags, _magType, _ammo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_personId.isEmpty) {
      showImdToast(context, '✖ اختر الفرد', error: true);
      return;
    }
    if (_weapon.text.trim().isEmpty) {
      showImdToast(context, '✖ نوع السلاح مطلوب', error: true);
      return;
    }
    setState(() => _busy = true);
    final person = widget.persons.firstWhere((p) => p.id == _personId);
    final repo = LinkageRepo(context.read<AppDatabase>());
    try {
      final initial = widget.initial;
      final companion = LinkArmamentsCompanion(
        id: Value(initial?.id ?? Ids.next('la')),
        personId: Value(person.id),
        personName: Value(person.fullName),
        personMilitaryNo: Value(person.militaryNo),
        weaponType: Value(_weapon.text.trim()),
        serialNo: Value(_serial.text.trim()),
        qty: Value(int.tryParse(_qty.text.trim()) ?? 1),
        magazines: Value(int.tryParse(_mags.text.trim()) ?? 0),
        magazineType: Value(_magType.text.trim()),
        ammoQty: Value(int.tryParse(_ammo.text.trim()) ?? 0),
        assignedDate: Value(_assignedDate),
        condition: Value(_condition.text.trim()),
        notes: Value(_notes.text.trim()),
        createdAt: initial == null ? Value(DateTime.now()) : const Value.absent(),
      );
      if (initial == null) {
        await repo.insertArmament(companion);
      } else {
        await repo.updateArmament(initial.id, companion);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showImdToast(context, '✖ $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdLabeled('الفرد *', LinkPersonPicker(persons: widget.persons, value: _personId, onChanged: (v) => setState(() => _personId = v))),
      ImdGrid(columns: 5, minItemWidth: 150, gap: 10, children: [
        ImdLabeled('نوع السلاح *', ImdFld(controller: _weapon)),
        ImdLabeled('الرقم المسلسل', ImdFld(controller: _serial)),
        ImdLabeled('الكمية', ImdFld(controller: _qty, number: true)),
        ImdLabeled('حالة السلاح', ImdFld(controller: _condition, suggestions: _conditions)),
        ImdLabeled('تاريخ التسليم', ImdDateField(value: _assignedDate, onChanged: (v) => setState(() => _assignedDate = v))),
      ]),
      ImdGrid(columns: 3, minItemWidth: 150, gap: 10, children: [
        ImdLabeled('عدد القرون (المخازن)', ImdFld(controller: _mags, number: true)),
        ImdLabeled('نوع القرون', ImdFld(controller: _magType, hint: 'صيني / روسي / نص حر', suggestions: _magTypes)),
        ImdLabeled('عدد الذخيرة المستلمة', ImdFld(controller: _ammo, number: true)),
      ]),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: widget.initial == null ? 'تسجيل التسليم' : 'حفظ التعديل', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}
