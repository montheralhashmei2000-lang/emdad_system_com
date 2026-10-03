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
    await showLinkPersonProfile(
      context,
      repo: widget.repo,
      person: person,
      onEdit: () {},
      onStatus: () {},
    );
    await _load();
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
      headers: const ['م', 'الفرد', 'الرقم العسكري', 'نوع السلاح', 'المسلسل', 'الكمية', 'تاريخ التسليم', 'حالة السلاح', 'الحالة'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].personName,
            rows[i].personMilitaryNo,
            rows[i].weaponType,
            rows[i].serialNo,
            nf(rows[i].qty),
            _d(rows[i].assignedDate),
            rows[i].condition,
            rows[i].returned ? 'رُدِّد ${_d(rows[i].returnedDate)}' : 'مسلَّم',
          ],
      ],
      numericColumns: const {0, 5},
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
          columns: const [
            ImdCol('الفرد', flex: 2),
            ImdCol('نوع السلاح'),
            ImdCol('المسلسل'),
            ImdCol('الكمية', numeric: true),
            ImdCol('تاريخ التسليم'),
            ImdCol('حالة السلاح'),
            ImdCol('الحالة'),
            ImdCol(''),
          ],
          rows: [for (final a in _filtered) _row(context, a)],
          cards: true,
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
      Text(_d(a.assignedDate)),
      Text(a.condition.isEmpty ? '—' : a.condition),
      ImdChip(
        a.returned ? 'رُدِّد ${_d(a.returnedDate)}' : 'مسلَّم',
        tone: a.returned ? ImdTone.ok : ImdTone.pend,
        icon: a.returned ? 'undo' : 'shield',
      ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ImdIconButton(icon: 'user', tooltip: 'ملف الفرد', onPressed: () => _openPerson(a.personId)),
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
  const _ArmamentSheet({required this.persons});

  final List<LinkPerson> persons;

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
  String _assignedDate = isoDay(DateTime.now());
  bool _busy = false;

  static const _conditions = ['جيد', 'يحتاج صيانة', 'تالف'];

  @override
  void dispose() {
    for (final c in [_weapon, _serial, _qty, _condition, _notes]) {
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
      await repo.insertArmament(
        LinkArmamentsCompanion(
          id: Value(Ids.next('la')),
          personId: Value(person.id),
          personName: Value(person.fullName),
          personMilitaryNo: Value(person.militaryNo),
          weaponType: Value(_weapon.text.trim()),
          serialNo: Value(_serial.text.trim()),
          qty: Value(int.tryParse(_qty.text.trim()) ?? 1),
          assignedDate: Value(_assignedDate),
          condition: Value(_condition.text.trim()),
          notes: Value(_notes.text.trim()),
          createdAt: Value(DateTime.now()),
        ),
      );
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
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'تسجيل التسليم', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}
