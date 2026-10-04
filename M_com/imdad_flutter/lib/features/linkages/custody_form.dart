import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/finance_files.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/finance.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

String _fmt(double v) {
  if (v == 0) return '';
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// نموذج العهدة المالية (مستلمة من المالية، أو مسلَّمة لشخص).
///
/// * رقم العهدة: يُكتب يدويًّا، وإن تُرك فارغًا يُولَّد `عهدة-00001`، ولا يتكرر.
/// * المُسلِّم/المستلم: نصٌّ حر باقتراحات (الأفراد والجهات السابقة). في «المستلمة»
///   يبدأ المُسلِّم «المالية» والمستلم المستخدم الحالي، وفي «المسلَّمة» العكس.
/// * سعر الصرف لا يظهر إلا مع العملة اليمنية.
/// * الحقول القديمة (مسلسل/كمية/وحدة/قيمة) مخفية افتراضيًّا في تبويب «متقدم».
class CustodyForm extends StatefulWidget {
  const CustodyForm({super.key, required this.names, required this.initial, required this.actor, required this.userName});

  /// اقتراحات الأسماء (أفراد القوة البشرية وما سبق كتابته).
  final List<String> names;
  final LinkFinCustody? initial;
  final String actor;

  /// اسم المستخدم الحالي — الافتراضي في خانة «أنا».
  final String userName;

  @override
  State<CustodyForm> createState() => _CustodyFormState();
}

class _CustodyFormState extends State<CustodyForm> {
  static const _financeName = 'المالية';

  LinkFinCustody? get _i => widget.initial;

  late String _kind = _i?.kind ?? CustodyKind.received;
  late String _currency = _i?.currency ?? FinCurrency.sar;
  late String _status = _i?.status ?? CustodyStatus.open;
  late String _date = _i?.custodyDate ?? isoDay(DateTime.now());
  late String _due = _i?.dueDate ?? '';
  String _tab = 'main'; // main | adv
  bool _showLegacy = false;

  late final _no = TextEditingController(text: _i?.custodyNo ?? '');
  late final _amount = TextEditingController(text: _fmt(_i?.amount ?? 0));
  late final _rate = TextEditingController(text: _fmt(_i?.exchangeRate ?? 0));
  late final _purpose = TextEditingController(text: _i?.title ?? '');
  late final _giver = TextEditingController(text: _i?.giverName ?? '');
  late final _receiver = TextEditingController(text: _i?.receiverName ?? '');
  late final _notes = TextEditingController(text: _i?.notes ?? '');
  late final _sourceDoc = TextEditingController(text: _i?.sourceDocNo ?? '');
  late final _costCenter = TextEditingController(text: _i?.costCenter ?? '');
  late final _serial = TextEditingController(text: _i?.serialNo ?? '');
  late final _qty = TextEditingController(text: _i == null ? '' : _fmt(_i!.qty));
  late final _unit = TextEditingController(text: _i?.unit ?? '');
  late final _legacyValue = TextEditingController(text: _fmt(_i?.valueAmount ?? 0));
  late List<FinAttachment> _files = FinAttachment.decode(_i?.attachmentsJson ?? '[]');
  final List<FinAttachment> _added = [];
  String _suggestedNo = '';
  bool _busy = false;

  bool get _isYer => _currency == FinCurrency.yer;
  bool get _cleared => _status == CustodyStatus.cleared;

  @override
  void initState() {
    super.initState();
    _showLegacy = _i != null && (_i!.serialNo.isNotEmpty || _i!.unit.isNotEmpty || _i!.valueAmount != 0 && _i!.amount == 0);
    if (_i == null) _applyKindDefaults(force: true);
    _loadSuggestion();
  }

  Future<void> _loadSuggestion() async {
    final n = await LinkageRepo(context.read<AppDatabase>()).nextCustodyNo();
    if (mounted) setState(() => _suggestedNo = n);
  }

  /// الافتراضيات بحسب النوع. لا تُكتب فوق خانةٍ عدّلها المستخدم بيده.
  void _applyKindDefaults({bool force = false}) {
    final me = widget.userName;
    bool free(TextEditingController c, String other) => force || c.text.trim().isEmpty || c.text.trim() == other;
    if (_kind == CustodyKind.received) {
      if (free(_giver, me)) _giver.text = _financeName;
      if (free(_receiver, _financeName)) _receiver.text = me;
    } else {
      if (free(_giver, _financeName)) _giver.text = me;
      if (free(_receiver, me)) _receiver.text = '';
    }
  }

  @override
  void dispose() {
    for (final c in [_no, _amount, _rate, _purpose, _giver, _receiver, _notes, _sourceDoc, _costCenter, _serial, _qty, _unit, _legacyValue]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'], allowMultiple: true);
    if (res == null) return;
    try {
      for (final f in res.files) {
        if (f.path == null) continue;
        final a = await FinanceFiles.save(f.path!, prefix: 'custody');
        _added.add(a);
        _files = [..._files, a];
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e', error: true);
    }
  }

  Future<void> _removeFile(FinAttachment a) async {
    setState(() => _files = [for (final f in _files) if (f.path != a.path) f]);
    // الملف المضاف في هذه الجلسة وحدها يُحذف فورًا؛ المحفوظ يُحذف بعد الحفظ.
    if (_added.any((x) => x.path == a.path)) {
      _added.removeWhere((x) => x.path == a.path);
      await FinanceFiles.delete(a.path);
    }
  }

  Future<void> _save() async {
    if (_purpose.text.trim().isEmpty) return showImdToast(context, '✖ الغرض من العهدة مطلوب', error: true);
    if (_num(_amount.text) <= 0 && !(_i != null && _i!.amount == 0)) {
      return showImdToast(context, '✖ أدخل مبلغ العهدة', error: true);
    }
    if (_isYer && _num(_rate.text) <= 0) return showImdToast(context, '✖ أدخل سعر الصرف للعملة اليمنية', error: true);
    setState(() => _busy = true);
    final repo = LinkageRepo(context.read<AppDatabase>());
    final holder = _kind == CustodyKind.received ? _giver.text.trim() : _receiver.text.trim();
    final data = LinkFinCustodiesCompanion(
      custodyNo: Value(_no.text.trim()),
      kind: Value(_kind),
      title: Value(_purpose.text.trim()),
      holder: Value(holder),
      giverName: Value(_giver.text.trim()),
      receiverName: Value(_receiver.text.trim()),
      amount: Value(_num(_amount.text)),
      currency: Value(_currency),
      exchangeRate: Value(_isYer ? _num(_rate.text) : 0),
      valueAmount: Value(_showLegacy ? _num(_legacyValue.text) : (_i?.valueAmount ?? 0)),
      serialNo: Value(_serial.text.trim()),
      qty: Value(_qty.text.trim().isEmpty ? 1 : _num(_qty.text)),
      unit: Value(_unit.text.trim()),
      custodyDate: Value(_date),
      dueDate: Value(_due),
      status: Value(_status),
      sourceDocNo: Value(_sourceDoc.text.trim()),
      costCenter: Value(_costCenter.text.trim()),
      attachmentsJson: Value(FinAttachment.encode(_files)),
      notes: Value(_notes.text.trim()),
      updatedAt: Value(DateTime.now()),
    );
    try {
      if (_i == null) {
        await repo.insertCustody(
          data.copyWith(id: Value(Ids.next('lc')), createdBy: Value(widget.actor), createdAt: Value(DateTime.now())),
          actor: widget.actor,
        );
      } else {
        await repo.updateCustody(_i!, data, actor: widget.actor);
        // ملفات المحفوظ التي أزالها المستخدم تُحذف بعد نجاح الحفظ.
        final keep = {for (final f in _files) f.path};
        for (final old in FinAttachment.decode(_i!.attachmentsJson)) {
          if (!keep.contains(old.path)) await FinanceFiles.delete(old.path);
        }
      }
    } on LinkBlocked catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showImdToast(context, '✖ ${e.message}', error: true);
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _main() {
    final names = widget.names;
    final received = _kind == CustodyKind.received;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 3, minItemWidth: 190, gap: 10, children: [
        ImdLabeled(
          'رقم العهدة',
          ImdFld(
            controller: _no,
            hint: _suggestedNo.isEmpty ? 'يُولَّد تلقائيًّا' : 'فارغ = $_suggestedNo',
            suffix: ImdIconButton(icon: 'refresh', tooltip: 'ترقيم تلقائي', onPressed: () => setState(() => _no.text = _suggestedNo)),
          ),
        ),
        ImdLabeled(
          'نوع العهدة',
          ImdSelect<String>(
            items: [for (final e in CustodyKind.labels.entries) (e.key, '${e.value} — ${e.key == CustodyKind.received ? 'استلمتها من المالية' : 'صرفتها لشخص'}')],
            value: _kind,
            onChanged: (v) => setState(() {
              _kind = v ?? CustodyKind.received;
              _applyKindDefaults();
            }),
          ),
        ),
        ImdLabeled('تاريخ العهدة', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
        ImdLabeled('المبلغ *', ImdFld(controller: _amount, number: true)),
        ImdLabeled(
          'العملة',
          ImdSelect<String>(
            items: [for (final e in FinCurrency.labels.entries) (e.key, e.value)],
            value: _currency,
            onChanged: (v) => setState(() => _currency = v ?? FinCurrency.sar),
          ),
        ),
        if (_isYer) ImdLabeled('سعر الصرف * (يمني لكل سعودي)', ImdFld(controller: _rate, number: true)),
        ImdLabeled('المُسلِّم${received ? ' (المالية أو غيرها)' : ' (أنا)'}', ImdFld(controller: _giver, suggestions: names)),
        ImdLabeled('المستلم${received ? ' (أنا)' : ''}', ImdFld(controller: _receiver, suggestions: names)),
        ImdLabeled(
          'الحالة',
          _cleared
              ? const Align(alignment: AlignmentDirectional.centerStart, child: ImdChip('تم الإخلاء', tone: ImdTone.ok, icon: 'check-circle'))
              : ImdSelect<String>(
                  items: [(CustodyStatus.open, CustodyStatus.labels[CustodyStatus.open]!), (CustodyStatus.canceled, CustodyStatus.labels[CustodyStatus.canceled]!)],
                  value: _status,
                  onChanged: (v) => setState(() => _status = v ?? CustodyStatus.open),
                ),
        ),
      ]),
      ImdLabeled('الغرض من العهدة *', ImdFld(controller: _purpose)),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
    ]);
  }

  Widget _advanced(ImdColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 3, minItemWidth: 190, gap: 10, children: [
        ImdLabeled('رقم مستند الاستلام الأصلي (من المالية)', ImdFld(controller: _sourceDoc)),
        ImdLabeled('تاريخ الاستحقاق (آخر أجل للإخلاء)', ImdDateField(value: _due, onChanged: (v) => setState(() => _due = v))),
        ImdLabeled('مركز التكلفة (للمشروع)', ImdFld(controller: _costCenter)),
      ]),
      const SizedBox(height: 10),
      Text('المرفقات', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in _files) ImdChip(f.name, tone: ImdTone.code, icon: 'x', onTap: () => _removeFile(f)),
        ImdButton.outline(label: 'إرفاق صورة / PDF', icon: 'upload', small: true, onPressed: _pick),
      ]),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
          label: _showLegacy ? 'إخفاء الحقول القديمة' : 'إظهار الحقول القديمة',
          icon: _showLegacy ? 'x' : 'archive',
          small: true,
          onPressed: () => setState(() => _showLegacy = !_showLegacy),
        ),
      ),
      if (_showLegacy) ...[
        const SizedBox(height: 8),
        const ImdNote('حقول عهد الأعيان القديمة: اختيارية، والنموذج الجديد يعتمد على المبلغ والعملة.'),
        ImdGrid(columns: 4, minItemWidth: 150, gap: 10, children: [
          ImdLabeled('المسلسل / البطاقة', ImdFld(controller: _serial)),
          ImdLabeled('الكمية', ImdFld(controller: _qty, number: true)),
          ImdLabeled('الوحدة', ImdFld(controller: _unit)),
          ImdLabeled('القيمة (قديم)', ImdFld(controller: _legacyValue, number: true)),
        ]),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdSegmented<String>(
        tabs: const [ImdTab('main', 'بيانات العهدة', icon: 'shield'), ImdTab('adv', 'متقدم', icon: 'sliders')],
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      const SizedBox(height: 12),
      if (_tab == 'main') _main() else _advanced(c),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(
          label: 'إلغاء',
          onPressed: _busy
              ? null
              : () async {
                  // ملفات أُرفقت ولم تُحفظ لا تبقى يتيمة على القرص.
                  for (final a in _added) {
                    await FinanceFiles.delete(a.path);
                  }
                  if (context.mounted) Navigator.of(context).pop(false);
                },
        ),
        ImdButton(label: 'حفظ العهدة', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}
