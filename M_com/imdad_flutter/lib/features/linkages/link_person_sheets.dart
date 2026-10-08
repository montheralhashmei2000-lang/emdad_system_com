import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/ids.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';

/// نسخ الصورة الشخصية إلى مجلد بيانات التطبيق باسم معرّف الفرد —
/// كأرشيف الملفات: لا مساراتٍ خارجية تفقد ثباتها.
Future<String> linkCopyPersonPhoto(String sourcePath, String personId) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'personnel'));
  if (!await dir.exists()) await dir.create(recursive: true);
  final dst = File(p.join(dir.path, '$personId${p.extension(sourcePath)}'));
  await File(sourcePath).copy(dst.path);
  return dst.path;
}

/// صورة الفرد — دائريّة، ولمن بلا صورة حرفُ اسمه الأول.
class LinkPersonAvatar extends StatelessWidget {
  const LinkPersonAvatar(this.photoPath, this.name, {super.key, this.radius = 16});

  final String photoPath;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final hasPhoto = photoPath.isNotEmpty && File(photoPath).existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.accentSoft,
      backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
      child: hasPhoto
          ? null
          : Text(
              name.isEmpty ? '؟' : name.characters.first,
              style: TextStyle(fontSize: radius * .8, fontWeight: FontWeight.w700, color: c.accent),
            ),
    );
  }
}

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// بطاقة معلومة صغيرة في الملف والنوافذ.
Widget linkInfoCard(String label, String value, ImdColors c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
          Text(value.isEmpty ? '—' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
        ],
      ),
    );

/// نافذة إضافة/تعديل فرد — بياناته كاملة، وإضافة قسمٍ أو عملٍ جديد تتم
/// من الكتابة هنا مباشرة (يُحفظ المسمى في الدليل تلقائيًّا).
///
/// **الرقم العسكري يُكتب يدويًّا كما هو في البطاقة** — لا توليد — فيُفحص
/// عند الحفظ ألّا يكون مسجَّلًا لفردٍ آخر.
Future<bool> showLinkPersonForm(
  BuildContext context, {
  required LinkageRepo repo,
  required List<String> camps,
  required Map<String, List<LinkTerm>> terms,
  LinkPerson? initial,
  required String actor,
}) async {
  final saved = await showImdModal<bool>(
    context,
    title: initial == null ? 'إضافة فردٍ للقوة البشرية' : 'تعديل بيانات: ${initial.fullName}',
    icon: 'user',
    maxWidth: 760,
    builder: (ctx) => _PersonForm(
      repo: repo,
      camps: camps,
      terms: terms,
      initial: initial,
      actor: actor,
    ),
  );
  return saved == true;
}

class _PersonForm extends StatefulWidget {
  const _PersonForm({
    required this.repo,
    required this.camps,
    required this.terms,
    required this.initial,
    required this.actor,
  });

  final LinkageRepo repo;
  final List<String> camps;
  final Map<String, List<LinkTerm>> terms;
  final LinkPerson? initial;
  final String actor;

  @override
  State<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<_PersonForm> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.fullName ?? '');
  late final TextEditingController _mil = TextEditingController(text: widget.initial?.militaryNo ?? '');
  late final TextEditingController _rank = TextEditingController(text: widget.initial?.rank ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final TextEditingController _phone2 = TextEditingController(text: widget.initial?.phone2 ?? '');
  late final TextEditingController _section =
      TextEditingController(text: widget.initial?.section ?? '');
  late final TextEditingController _job = TextEditingController(text: widget.initial?.job ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late String _subUnit = widget.initial?.subUnit ?? '';
  late String _camp = widget.initial?.camp ?? '';
  late String _photo = widget.initial?.photoPath ?? '';
  String? _newPhotoSource; // مسار الصورة المنتقاة قبل نسخها
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _mil, _rank, _phone, _phone2, _section, _job, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: false);
    final path = res?.paths.first;
    if (path == null || !mounted) return;
    setState(() {
      _newPhotoSource = path;
      _photo = path; // معاينة فورية قبل النسخ النهائي عند الحفظ
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showImdToast(context, '✖ اسم الفرد مطلوب', error: true);
      return;
    }
    // الرقم العسكري مكتوبٌ يدويًّا — يُفحص ألا يملكه فردٌ آخر.
    final owner = await widget.repo.militaryNoOwner(_mil.text, excludeId: widget.initial?.id ?? '');
    if (!mounted) return;
    if (owner.isNotEmpty) {
      showImdToast(context, '✖ الرقم العسكري «${_mil.text.trim()}» مسجَّل مسبقًا للفرد: $owner', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = widget.initial?.id ?? Ids.next('lp');
      // الصورة الجديدة تُنسخ إلى بيانات التطبيق باسم المعرّف.
      if (_newPhotoSource != null) {
        _photo = await linkCopyPersonPhoto(_newPhotoSource!, id);
      } else if (_photo.isEmpty && (widget.initial?.photoPath.isNotEmpty ?? false)) {
        _photo = widget.initial!.photoPath;
      }
      // المسميات الجديدة تُدوَّن في الدليل فتُقترح على من بعده.
      await widget.repo.addTermIfNew('subunit', _subUnit);
      await widget.repo.addTermIfNew('section', _section.text);
      await widget.repo.addTermIfNew('job', _job.text);

      final data = LinkPersonsCompanion(
        fullName: Value(_name.text.trim()),
        militaryNo: Value(_mil.text.trim()),
        rank: Value(_rank.text.trim()),
        phone: Value(_phone.text.trim()),
        phone2: Value(_phone2.text.trim()),
        photoPath: Value(_photo),
        subUnit: Value(_subUnit.trim()),
        camp: Value(_camp.trim()),
        section: Value(_section.text.trim()),
        job: Value(_job.text.trim()),
        notes: Value(_notes.text.trim()),
        createdBy: Value(widget.actor),
        updatedAt: Value(DateTime.now()),
      );
      if (widget.initial == null) {
        await widget.repo.insertPerson(
            data.copyWith(id: Value(id), createdAt: Value(DateTime.now())),
            actor: widget.actor);
      } else {
        await widget.repo.updatePerson(widget.initial!, data, actor: widget.actor);
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
    final subunitItems = [
      ('', 'بلا تحديد'),
      for (final t in widget.terms['subunit'] ?? const <LinkTerm>[]) (t.name, t.name)
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // الصورة والهوية — الصورة أول الصف لتبقى واضحة حتى في النافذة الضيقة.
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        LinkPersonAvatar(_photo, _name.text, radius: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ImdButton.outline(label: 'اختيار صورة شخصية', icon: 'camera', small: true, onPressed: _pickPhoto),
            if (_photo.isNotEmpty)
              ImdButton.outline(
                  label: 'إزالة الصورة',
                  icon: 'trash',
                  small: true,
                  onPressed: () => setState(() {
                        _photo = '';
                        _newPhotoSource = null;
                      })),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      ImdGrid(columns: 4, minItemWidth: 170, gap: 10, children: [
        ImdLabeled('الاسم الكامل *', ImdFld(controller: _name)),
        ImdLabeled('الرقم العسكري', ImdFld(controller: _mil, hint: 'يُكتب يدويًّا كما في البطاقة')),
        ImdLabeled('الرتبة', ImdFld(controller: _rank)),
        ImdLabeled('الهاتف', ImdFld(controller: _phone, number: true)),
        ImdLabeled('هاتف آخر', ImdFld(controller: _phone2, number: true)),
        ImdLabeled('الوحدة الفرعية', ImdSelect<String>(items: subunitItems, value: _subUnit, onChanged: (v) => setState(() => _subUnit = v ?? ''))),
        ImdLabeled(
          'المعسكر',
          ImdSelect<String>(
            items: [
              ('', 'بلا تحديد'),
              for (final w in {...widget.camps, if (_camp.isNotEmpty) _camp}) (w, w),
            ],
            value: _camp,
            onChanged: (v) => setState(() => _camp = v ?? ''),
          ),
        ),
        ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      ]),
      ImdGrid(columns: 2, minItemWidth: 240, gap: 10, children: [
        ImdLabeled('القسم (مخزن، مطبخ، فرن، سائق… — اكتب جديدًا لإضافته)', ImdFld(controller: _section, suggestions: [for (final t in widget.terms['section'] ?? const <LinkTerm>[]) t.name])),
        ImdLabeled('العمل (معلم أرز، معلم خباز… — اكتب جديدًا لإضافته)', ImdFld(controller: _job, suggestions: [for (final t in widget.terms['job'] ?? const <LinkTerm>[]) t.name])),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'حفظ الفرد', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}

/// تغيير حالة الفرد إلى حالةٍ ذات مدى (غياب/مهمة/إجازة/إذن/فرار) —
/// من تاريخٍ إلى تاريخٍ بعدد أيامٍ يُحسب من التاريخين ويُعدَّل يدويًّا.
Future<bool> showLinkStatusChange(
  BuildContext context, {
  required LinkageRepo repo,
  required LinkPerson person,
  required String actor,
}) async {
  final saved = await showImdModal<bool>(
    context,
    title: 'تغيير الحالة: ${person.fullName}',
    icon: 'clock',
    maxWidth: 560,
    builder: (ctx) => _StatusForm(repo: repo, person: person, actor: actor),
  );
  return saved == true;
}

class _StatusForm extends StatefulWidget {
  const _StatusForm({required this.repo, required this.person, required this.actor});

  final LinkageRepo repo;
  final LinkPerson person;
  final String actor;

  @override
  State<_StatusForm> createState() => _StatusFormState();
}

class _StatusFormState extends State<_StatusForm> {
  String _status = LinkStatus.leave;
  String _from = isoDay(DateTime.now());
  String _to = '';
  final _days = TextEditingController();
  final _notes = TextEditingController();
  final _newStatus = TextEditingController();
  List<String> _custom = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final t = await widget.repo.terms('status');
    if (mounted) setState(() => _custom = [for (final e in t) e.name]);
  }

  /// حالةٌ جديدة من نوعٍ يختاره المستخدم (مريض مستشفى، مهمة…) تُحفظ للمرات القادمة.
  Future<void> _addStatus() async {
    final v = _newStatus.text.trim();
    if (v.isEmpty) return;
    await widget.repo.addTermIfNew('status', v);
    _newStatus.clear();
    _status = v;
    await _loadCustom();
  }

  @override
  void dispose() {
    _newStatus.dispose();
    _days.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// الأيام تُحسب آليًّا من التاريخين — ويبقى تعديلها يدويًّا بقرارٍ إداري.
  void _recalc() {
    final d = linkDaysBetween(_from, _to);
    imdSetText(_days, d > 0 ? '$d' : '');
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final manual = int.tryParse(_days.text.trim());
    await widget.repo.changeStatus(
      p: widget.person,
      status: _status,
      fromIso: _from,
      toIso: _to,
      days: manual,
      notes: _notes.text,
      actor: widget.actor,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in [...LinkStatus.dated, ..._custom.where((c) => !LinkStatus.dated.contains(c))])
          ImdChip(
            LinkStatus.label(s),
            tone: _status == s ? LinkStatus.tone(s) : ImdTone.off,
            icon: _status == s ? 'check' : null,
            onTap: () => setState(() => _status = s),
          ),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: ImdLabeled('حالة جديدة (مريض مستشفى، مهمة…)', ImdFld(controller: _newStatus))),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ImdButton.outline(label: 'إضافة', icon: 'plus', small: true, onPressed: _addStatus),
        ),
      ]),
      const SizedBox(height: 12),
      ImdGrid(columns: 3, minItemWidth: 170, gap: 10, children: [
        ImdLabeled('من تاريخ', ImdDateField(value: _from, onChanged: (v) { _from = v; _recalc(); })),
        ImdLabeled('إلى تاريخ (فراغه = مستمرة)', ImdDateField(value: _to, onChanged: (v) { _to = v; _recalc(); })),
        ImdLabeled('عدد الأيام', ImdFld(controller: _days, number: true, onChanged: (_) => setState(() {}))),
      ]),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'حفظ الحالة', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}

/// العودة من إجازة/غياب: إجراءٌ إداريٌّ يُسجَّل — مواصلة عملٍ أو مباشرة عمل.
Future<bool> showLinkReturnAction(
  BuildContext context, {
  required LinkageRepo repo,
  required LinkPerson person,
  required String actor,
}) async {
  final saved = await showImdModal<bool>(
    context,
    title: 'عودة: ${person.fullName}',
    icon: 'check-circle',
    maxWidth: 500,
    builder: (ctx) => _ReturnForm(repo: repo, person: person, actor: actor),
  );
  return saved == true;
}

class _ReturnForm extends StatefulWidget {
  const _ReturnForm({required this.repo, required this.person, required this.actor});

  final LinkageRepo repo;
  final LinkPerson person;
  final String actor;

  @override
  State<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<_ReturnForm> {
  String _action = kLinkReturnActions.first;
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.repo.returnToWork(p: widget.person, action: _action, notes: _notes.text, actor: widget.actor);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdSegmented<String>(
        tabs: [for (final a in kLinkReturnActions) ImdTab(a, a, icon: 'check')],
        value: _action,
        onChanged: (v) => setState(() => _action = v),
      ),
      const SizedBox(height: 12),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'تأكيد العودة', icon: 'check', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}

/// ملف الفرد: هويته وصورته، فسجلاته المرتبطة (عهدُه وسلاحه وعقوده من
/// المركزين المالي والتسليحي)، ثم سجل حالاته — ومنه يُفتح التعديل
/// وتغيير الحالة والعودة.
Future<void> showLinkPersonProfile(
  BuildContext context, {
  required LinkageRepo repo,
  required LinkPerson person,
  required VoidCallback onEdit,
  required VoidCallback onStatus,
}) async {
  final logs = await repo.statusLog(person.id);
  final linked = await repo.linkedRecords(person.id);
  if (!context.mounted) return;
  await showImdModal<void>(
    context,
    title: person.fullName,
    icon: 'user',
    maxWidth: 820,
    builder: (ctx) {
      final c = ctx.imd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          LinkPersonAvatar(person.photoPath, person.fullName, radius: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ImdChip(LinkStatus.label(person.status), tone: LinkStatus.tone(person.status)),
              if (person.statusFrom.isNotEmpty || person.statusTo.isNotEmpty)
                ImdChip(
                  '${_d(person.statusFrom)} ← ${person.statusTo.isEmpty ? 'مستمرة' : _d(person.statusTo)}'
                  '${person.statusDays > 0 ? ' · ${nf(person.statusDays)} يوم' : ''}',
                  tone: ImdTone.off,
                  icon: 'calendar',
                ),
              ImdChip(person.subUnit.isEmpty ? 'بلا وحدة فرعية' : person.subUnit, tone: ImdTone.code, icon: 'tent'),
              if (person.camp.isNotEmpty) ImdChip(person.camp, tone: ImdTone.off, icon: 'pin'),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ImdGrid(columns: 5, minItemWidth: 140, gap: 8, children: [
          linkInfoCard('الرقم العسكري', person.militaryNo, c),
          linkInfoCard('الرتبة', person.rank, c),
          linkInfoCard('الهاتف', person.phone, c),
          linkInfoCard('هاتف آخر', person.phone2, c),
          linkInfoCard('القسم', person.section, c),
          linkInfoCard('العمل', person.job, c),
          linkInfoCard('الوحدة الفرعية', person.subUnit, c),
          linkInfoCard('المعسكر', person.camp, c),
          linkInfoCard('أُضيف', _d(isoDay(person.createdAt)), c),
          linkInfoCard('ملاحظات', person.notes, c),
        ]),
        const SizedBox(height: 14),

        // ───── سجلاته المرتبطة: التسليح (المالية غير مرتبطة بالأفراد) ─────
        Row(children: [
          Text('سجلاته المرتبطة',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(width: 10),
          ImdChip('${nf(linked.armaments.length)} سلاح', tone: ImdTone.pend, icon: 'zap'),
        ]),
        const SizedBox(height: 8),
        if (linked.armaments.isEmpty)
          const ImdNote('لا سلاحًا مرتبطًا بهذا الفرد بعد — يُسجَّل من شاشة التسليح.')
        else
          for (final a in linked.armaments)
            _recordLine(c, 'zap', ImdTone.pend, 'سلاح',
                '${a.weaponType}${a.serialNo.isEmpty ? '' : ' · ${a.serialNo}'} · سُلّم ${_d(a.assignedDate)}',
                a.returned ? 'رُدِّد ${_d(a.returnedDate)}' : 'مسلَّم', a.returned ? ImdTone.ok : ImdTone.pend),
        const SizedBox(height: 14),

        Text('سجل الحالات',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          const ImdNote('لا تغييراتٍ مسجَّلة بعد — سجل الحالات يُبنى من كل تغيير حالةٍ أو عودة.')
        else
          for (var i = 0; i < logs.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.bg,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ImdChip(LinkStatus.label(logs[i].status), tone: LinkStatus.tone(logs[i].status)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [
                      if (LinkStatus.isDated(logs[i].status))
                        'من ${_d(logs[i].fromDate)} إلى ${logs[i].toDate.isEmpty ? 'الآن' : _d(logs[i].toDate)}'
                            '${logs[i].days > 0 ? ' · ${nf(logs[i].days)} يوم' : ''}',
                      if (logs[i].returnAction.isNotEmpty) 'الإجراء عند العودة: ${logs[i].returnAction}',
                      if (logs[i].notes.isNotEmpty) logs[i].notes,
                    ].join(' — '),
                    style: TextStyle(fontSize: 13, color: c.text, height: 1.6),
                  ),
                ),
                Text(_d(isoDay(logs[i].createdAt)), style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
          ],
      ]);
    },
    actions: (ctx) => [
      ImdButton.outline(label: 'تعديل البيانات', icon: 'edit', onPressed: () { Navigator.of(ctx).pop(); onEdit(); }),
      ImdButton(label: 'تغيير الحالة / العودة', icon: 'clock', onPressed: () { Navigator.of(ctx).pop(); onStatus(); }),
    ],
  );
}

/// سطر سجلٍ مرتبط في الملف: شارةُ النوع، البيان، وشارةُ الحالة.
Widget _recordLine(ImdColors c, String icon, ImdTone tone, String kind, String body,
    String stateLabel, ImdTone stateTone) {
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: c.bg,
      border: Border.all(color: c.line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      ImdChip(kind, tone: tone, icon: icon),
      const SizedBox(width: 10),
      Expanded(
        child: Text(body,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.text, height: 1.5)),
      ),
      const SizedBox(width: 8),
      ImdChip(stateLabel, tone: stateTone),
    ]),
  );
}
