import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/cable_repo.dart';

/// النص الافتراضي لجسم البرقية — يُكتب مسبقًا في البرقية الجديدة ثم يُحرَّر
/// بالكامل يدويًّا.
const String kCableDefaultBody = 'إشارة إلى الموضوع أعلاه، تم الرفع إليكم حسب النظام.\nوالسلام عليكم.';

/// نتيجة حفظ النموذج: معرّف البرقية، وهل طُلبت الطباعة بعد الحفظ.
typedef CableFormResult = ({String id, bool print});

/// نموذج «برقية صادرة/واردة» — يطابق النموذج المطبوع المعتمد:
/// رأس (الاتجاه، الرقم، التاريخ، الساعة، السرية، الأسبقية)، ثم إلى/من/نسخة إلى،
/// فالموضوع، فجدول المرسَل إليهم، فجسم البرقية، فقسم «لاستعمال المركز/المكتب».
///
/// كل الحقول المتغيرة تُكتب بالإدخال اليدوي مع اقتراحٍ مما سبق كتابته،
/// وجسم البرقية نصٌّ حرٌّ بالكامل.
class CableForm extends StatefulWidget {
  const CableForm({super.key, required this.repo, required this.initial, required this.actor, required this.canPrint});

  final CableRepo repo;
  final Cable? initial;
  final String actor;
  final bool canPrint;

  @override
  State<CableForm> createState() => _CableFormState();
}

class _RecipientCtl {
  _RecipientCtl([CableRecipient r = const CableRecipient()])
      : name = TextEditingController(text: r.name),
        unit = TextEditingController(text: r.unit),
        note = TextEditingController(text: r.note);

  final TextEditingController name, unit, note;

  CableRecipient get value => CableRecipient(name: name.text.trim(), unit: unit.text.trim(), note: note.text.trim());

  void dispose() {
    name.dispose();
    unit.dispose();
    note.dispose();
  }
}

class _CableFormState extends State<CableForm> {
  Cable? get _i => widget.initial;

  late String _direction = _i?.direction ?? CableDirection.outgoing;
  late String _classification = _i?.classification ?? CableClass.normal;
  late String _priority = _i?.priority ?? CablePriority.normal;
  late String _status = _i?.status ?? CableStatus.neu;
  late String _date = (_i?.cableDate.isNotEmpty ?? false) ? _i!.cableDate : isoDay(DateTime.now());

  late final _no = TextEditingController(text: _i?.cableNo ?? '');
  late final _time = TextEditingController(text: _i?.cableTime ?? _nowHm());
  late final _to = TextEditingController(text: _i?.toParty ?? '');
  late final _from = TextEditingController(text: _i?.fromParty ?? '');
  late final _cc = TextEditingController(text: _i?.ccParty ?? '');
  late final _subject = TextEditingController(text: _i?.subject ?? '');
  late final _body = TextEditingController(text: _i == null ? kCableDefaultBody : _i!.body);
  late final _replyTo = TextEditingController(text: _i?.replyToNo ?? '');
  late final _notes = TextEditingController(text: _i?.notes ?? '');
  late final _editorName = TextEditingController(text: _i?.editorName ?? '');
  late final _editorRank = TextEditingController(text: _i?.editorRank ?? '');
  late final _editorJob = TextEditingController(text: _i?.editorJob ?? '');
  late final _serial = TextEditingController(text: _i?.serialNo ?? '');
  late final _method = TextEditingController(text: _i?.sendMethod ?? '');
  late final _sendAt = TextEditingController(text: _i?.sendDateTime ?? '');
  late final _specialist = TextEditingController(text: _i?.specialist ?? '');
  late final _receiver = TextEditingController(text: _i?.receiverName ?? '');
  late final _receiveTime = TextEditingController(text: _i?.receiveTime ?? '');

  late final List<_RecipientCtl> _recipients = [
    for (final r in CableRecipient.decode(_i?.recipientsJson ?? '[]')) _RecipientCtl(r),
    if (CableRecipient.decode(_i?.recipientsJson ?? '[]').isEmpty) _RecipientCtl(),
  ];

  Map<String, List<String>> _sug = const {};
  bool _autoNo = true;
  bool _busy = false;

  static String _nowHm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _autoNo = _i == null;
    _loadHints();
  }

  Future<void> _loadHints() async {
    final keys = ['to', 'from', 'cc', 'editor', 'rank', 'job', 'method', 'recipient', 'unit'];
    final out = <String, List<String>>{};
    for (final k in keys) {
      out[k] = await widget.repo.suggestions(k);
    }
    if (_autoNo && _no.text.isEmpty) _no.text = await widget.repo.nextCableNo(_direction);
    if (!mounted) return;
    setState(() => _sug = out);
  }

  @override
  void dispose() {
    for (final c in [
      _no, _time, _to, _from, _cc, _subject, _body, _replyTo, _notes, _editorName, _editorRank,
      _editorJob, _serial, _method, _sendAt, _specialist, _receiver, _receiveTime,
    ]) {
      c.dispose();
    }
    for (final r in _recipients) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool print}) async {
    if (_subject.text.trim().isEmpty) {
      return showImdToast(context, '✖ الموضوع مطلوب', error: true);
    }
    setState(() => _busy = true);
    final id = _i?.id ?? Ids.next('cb');
    final isEdit = _i != null;
    final companion = CablesCompanion(
      id: Value(id),
      direction: Value(_direction),
      cableNo: Value(_no.text.trim()),
      cableDate: Value(_date),
      cableTime: Value(_time.text.trim()),
      subject: Value(_subject.text.trim()),
      body: Value(_body.text.trim()),
      fromParty: Value(_from.text.trim()),
      toParty: Value(_to.text.trim()),
      ccParty: Value(_cc.text.trim()),
      recipientsJson: Value(CableRecipient.encode([for (final r in _recipients) r.value])),
      classification: Value(_classification),
      priority: Value(_priority),
      status: Value(_status),
      replyToNo: Value(_replyTo.text.trim()),
      editorName: Value(_editorName.text.trim()),
      editorRank: Value(_editorRank.text.trim()),
      editorJob: Value(_editorJob.text.trim()),
      serialNo: Value(_serial.text.trim()),
      sendMethod: Value(_method.text.trim()),
      sendDateTime: Value(_sendAt.text.trim()),
      specialist: Value(_specialist.text.trim()),
      receiverName: Value(_receiver.text.trim()),
      receiveTime: Value(_receiveTime.text.trim()),
      notes: Value(_notes.text.trim()),
      createdBy: isEdit ? const Value.absent() : Value(widget.actor),
    );
    try {
      if (isEdit) {
        await widget.repo.update(_i!, companion, actor: widget.actor);
      } else {
        await widget.repo.insert(companion, actor: widget.actor);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      return showImdToast(context, '✖ $e', error: true);
    }
    if (!mounted) return;
    Navigator.of(context).pop<CableFormResult>((id: id, print: print));
  }

  Widget _section(ImdColors c, String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
      );

  Widget _recipientRow(int i) {
    final r = _recipients[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(builder: (ctx, box) {
        final fields = [
          ImdLabeled('الاسم', ImdFld(controller: r.name, suggestions: _sug['recipient'] ?? const [])),
          ImdLabeled('الوحدة', ImdFld(controller: r.unit, suggestions: _sug['unit'] ?? const [])),
          ImdLabeled('ملاحظة', ImdFld(controller: r.note)),
        ];
        final del = _recipients.length > 1
            ? ImdIconButton(
                icon: 'trash',
                tooltip: 'حذف الصف',
                kind: ImdBtnKind.danger,
                onPressed: () => setState(() => _recipients.removeAt(i).dispose()))
            : const SizedBox.shrink();
        if (box.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('م ${nf(i + 1)}', style: TextStyle(fontWeight: FontWeight.w700, color: ctx.imd.muted)),
            ...fields,
            Align(alignment: AlignmentDirectional.centerEnd, child: del),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, bottom: 10),
            child: Text(nf(i + 1), style: TextStyle(fontWeight: FontWeight.w700, color: ctx.imd.muted)),
          ),
          for (final f in fields) Expanded(child: Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: f)),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: del),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ───── الرأس: الاتجاه والرقم والتاريخ والتصنيف ─────
      ImdGrid(columns: 4, minItemWidth: 170, gap: 12, children: [
        ImdLabeled(
            'الاتجاه',
            ImdSelect<String>(
              items: [for (final e in CableDirection.labels.entries) (e.key, e.value)],
              value: _direction,
              onChanged: (v) async {
                setState(() => _direction = v ?? CableDirection.outgoing);
                if (_autoNo) {
                  final n = await widget.repo.nextCableNo(_direction);
                  if (mounted) setState(() => _no.text = n);
                }
              },
            )),
        ImdLabeled(
            'رقم البرقية',
            ImdFld(
              controller: _no,
              onChanged: (_) => _autoNo = false,
              suffix: ImdIconButton(
                icon: 'refresh',
                tooltip: 'ترقيم تلقائي',
                onPressed: () async {
                  final n = await widget.repo.nextCableNo(_direction);
                  if (!mounted) return;
                  _autoNo = true;
                  setState(() => _no.text = n);
                },
              ),
            )),
        ImdLabeled('تاريخها', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
        ImdLabeled('ساعة الإنشاء', ImdFld(controller: _time, hint: 'HH:mm')),
        ImdLabeled(
            'درجة السرية',
            ImdSelect<String>(
              items: [for (final e in CableClass.meta.entries) (e.key, e.value.$1)],
              value: _classification,
              onChanged: (v) => setState(() => _classification = v ?? CableClass.normal),
            )),
        ImdLabeled(
            'درجة الأسبقية',
            ImdSelect<String>(
              items: [for (final e in CablePriority.meta.entries) (e.key, e.value.$1)],
              value: _priority,
              onChanged: (v) => setState(() => _priority = v ?? CablePriority.normal),
            )),
        ImdLabeled(
            'الحالة',
            ImdSelect<String>(
              items: [for (final e in CableStatus.meta.entries) (e.key, e.value.$1)],
              value: _status,
              onChanged: (v) => setState(() => _status = v ?? CableStatus.neu),
            )),
        ImdLabeled('رد على برقية رقم', ImdFld(controller: _replyTo)),
      ]),

      // ───── إلى / من / نسخة إلى ─────
      _section(c, 'الجهات'),
      ImdGrid(columns: 3, minItemWidth: 220, gap: 12, children: [
        ImdLabeled('إلى', ImdFld(controller: _to, suggestions: _sug['to'] ?? const [])),
        ImdLabeled('من', ImdFld(controller: _from, suggestions: _sug['from'] ?? const [])),
        ImdLabeled('نسخة إلى (سطرٌ لكل جهة)', ImdFld(controller: _cc, maxLines: 3)),
      ]),
      ImdLabeled('م / الموضوع *', ImdFld(controller: _subject)),

      // ───── جدول المرسَل إليهم ─────
      _section(c, 'المرسَل إليهم'),
      for (var i = 0; i < _recipients.length; i++) _recipientRow(i),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
            label: 'إضافة صف', icon: 'plus', small: true, onPressed: () => setState(() => _recipients.add(_RecipientCtl()))),
      ),

      // ───── جسم البرقية: نصّ حرّ ─────
      _section(c, 'جسم البرقية'),
      ImdFld(controller: _body, maxLines: 9, hint: 'اكتب نص البرقية…'),

      // ───── لاستعمال المركز / المكتب ─────
      _section(c, 'لاستعمال المركز / المكتب'),
      ImdGrid(columns: 3, minItemWidth: 190, gap: 12, children: [
        ImdLabeled('محرر البرقية', ImdFld(controller: _editorName, suggestions: _sug['editor'] ?? const [])),
        ImdLabeled('الرتبة', ImdFld(controller: _editorRank, suggestions: _sug['rank'] ?? const [])),
        ImdLabeled('الوظيفة', ImdFld(controller: _editorJob, suggestions: _sug['job'] ?? const [])),
        ImdLabeled('تسلسل / نرس', ImdFld(controller: _serial)),
        ImdLabeled('وسيلة الإرسال', ImdFld(controller: _method, suggestions: _sug['method'] ?? const [])),
        ImdLabeled('الوقت والتاريخ', ImdFld(controller: _sendAt, hint: '8:55 م — ٠٣/١٠/٢٠٢٦')),
        ImdLabeled('مختص', ImdFld(controller: _specialist)),
        ImdLabeled('اسم المأمور (الاستقبال)', ImdFld(controller: _receiver)),
        ImdLabeled('وقت الاستلام', ImdFld(controller: _receiveTime)),
      ]),
      ImdLabeled('ملاحظات داخلية (لا تُطبع)', ImdFld(controller: _notes)),
      if (_i != null && _i!.attachPath.isNotEmpty)
        ImdNote('المرفق الحالي: ${_i!.attachName} (${CableRepo.formatSize(_i!.attachSize)}) — أدِر المرفق من عرض البرقية.'),

      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop()),
        if (widget.canPrint)
          ImdButton.outline(label: 'حفظ وطباعة', icon: 'printer', busy: _busy, onPressed: () => _save(print: true)),
        ImdButton(label: _i == null ? 'إضافة' : 'حفظ', icon: 'check', busy: _busy, onPressed: () => _save(print: false)),
      ]),
    ]);
  }
}
