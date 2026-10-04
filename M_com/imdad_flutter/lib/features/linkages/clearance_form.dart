import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/print_format.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/finance_files.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/finance.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

/// نموذج الإخلاء: عهدة (الرئيسي)، أو عقد، أو حر.
///
/// **إخلاء العهدة:** تختار العهدة فتُسحب أرقامها من المسيرات — المخصص، والمصروف،
/// والمرتجع، والفرق وصياغته بحسب نوع العهدة — وهي للقراءة فقط: يحسبها المستودع
/// عند الحفظ. «مسودة» و«مُرسل» لا يُغلقان العهدة؛ **«مُعتمد» وحده** يُغلقها ويكتب
/// الفائض/العجز في دفتر رصيد المالية، وهو يحتاج صلاحية الاعتماد.
class ClearanceForm extends StatefulWidget {
  const ClearanceForm({
    super.key,
    required this.openCustodies,
    required this.openContracts,
    required this.kind,
    required this.refId,
    required this.actor,
    required this.canApprove,
    this.initial,
    this.readOnly = false,
  });

  /// العهد قيد الإخلاء التي ليس لها إخلاء بعد.
  final List<LinkFinCustody> openCustodies;
  final List<LinkPurchaseContract> openContracts;
  final String kind;
  final String refId;
  final String actor;
  final bool canApprove;

  /// إخلاء عهدةٍ قائم للتعديل.
  final LinkClearance? initial;

  /// عرضٌ بلا حفظ لمن لا يملك صلاحية التعديل.
  final bool readOnly;

  @override
  State<ClearanceForm> createState() => _ClearanceFormState();
}

class _ClearanceFormState extends State<ClearanceForm> {
  LinkClearance? get _i => widget.initial;

  late String _kind = _i?.kind ?? widget.kind;
  late String _refId = _i?.refId ?? widget.refId;
  late String _workflow = _i?.workflow ?? (widget.canApprove ? LinkageRepo.wfApproved : LinkageRepo.wfDraft);
  late String _date = _i?.clearanceDate ?? isoDay(DateTime.now());
  late String _review = _i?.reviewDate ?? '';
  late final _no = TextEditingController(text: _i?.clearanceNo ?? '');
  late final _docNo = TextEditingController(text: _i?.docNo ?? '');
  late final _clearer = TextEditingController(text: _i?.clearerName ?? '');
  late final _adminNotes = TextEditingController(text: _i?.adminNotes ?? '');
  late final _notes = TextEditingController(text: _i?.notes ?? '');
  // عقد/حر
  late final _party = TextEditingController(text: _i?.partyName ?? '');
  late final _title = TextEditingController(text: _i?.refTitle ?? '');
  late final _amount = TextEditingController(text: _i == null || _i!.amount == 0 ? '' : _i!.amount.toString());

  FinAttachment? _attach;
  FinAttachment? _newlyAdded;
  CustodySettlement? _st;
  String _suggestedNo = '';
  bool _busy = false;

  bool get _isCustody => _kind == LinkClearanceKind.custody;
  bool get _lockedApproved => _i != null && _i!.workflow == LinkageRepo.wfApproved;

  @override
  void initState() {
    super.initState();
    if (_i != null && _i!.attachPath.isNotEmpty) {
      _attach = FinAttachment(name: _i!.attachName, path: _i!.attachPath, sha256: _i!.attachSha256);
    }
    _loadSuggestion();
    _fillFromRef();
  }

  @override
  void dispose() {
    for (final c in [_no, _docNo, _clearer, _adminNotes, _notes, _party, _title, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  LinkageRepo get _repo => LinkageRepo(context.read<AppDatabase>());

  Future<void> _loadSuggestion() async {
    final n = await _repo.nextClearanceNo();
    if (mounted) setState(() => _suggestedNo = n);
  }

  /// اختيار المرجع يملأ الأرقام: للعهدة من تسوية المسيرات، وللعقد من بياناته.
  Future<void> _fillFromRef() async {
    if (_refId.isEmpty) return;
    if (_isCustody) {
      final st = await _repo.custodySettlement(_refId);
      if (mounted) setState(() => _st = st);
    } else if (_kind == LinkClearanceKind.contract) {
      for (final c in widget.openContracts) {
        if (c.id == _refId && _i == null) {
          setState(() {
            _party.text = c.supplier;
            _title.text = c.title;
            _amount.text = c.amount == 0 ? '' : c.amount.toString();
          });
        }
      }
    }
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg']);
    final path = res?.files.firstOrNull?.path;
    if (path == null) return;
    try {
      final a = await FinanceFiles.save(path, prefix: 'clearance');
      if (_newlyAdded != null) await FinanceFiles.delete(_newlyAdded!.path);
      _newlyAdded = a;
      if (mounted) setState(() => _attach = a);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e', error: true);
    }
  }

  Future<void> _save() async {
    if (_kind != LinkClearanceKind.other && _refId.isEmpty) {
      return showImdToast(context, '✖ اختر ${_isCustody ? 'العهدة' : 'العقد'} المراد إخلاؤه', error: true);
    }
    if (_kind == LinkClearanceKind.other && _title.text.trim().isEmpty) {
      return showImdToast(context, '✖ بيان الإخلاء مطلوب', error: true);
    }
    setState(() => _busy = true);
    final repo = _repo;
    try {
      if (_isCustody) {
        await repo.saveCustodyClearance(
          id: _i?.id,
          custodyId: _refId,
          clearanceNo: _no.text,
          clearanceDate: _date,
          workflow: _workflow,
          docNo: _docNo.text,
          clearerName: _clearer.text,
          reviewDate: _review,
          adminNotes: _adminNotes.text,
          notes: _notes.text.trim(),
          attachName: _attach?.name ?? '',
          attachPath: _attach?.path ?? '',
          attachSha256: _attach?.sha256 ?? '',
          actor: widget.actor,
        );
        // الملف القديم المُستبدَل يُحذف بعد نجاح الحفظ.
        if (_i != null && _i!.attachPath.isNotEmpty && _i!.attachPath != (_attach?.path ?? '')) {
          await FinanceFiles.delete(_i!.attachPath);
        }
      } else {
        await repo.addClearance(
          kind: _kind,
          refId: _kind == LinkClearanceKind.other ? '' : _refId,
          clearanceNo: _no.text.trim(),
          clearanceDate: _date,
          partyName: _party.text.trim(),
          refTitle: _title.text.trim(),
          amount: _num(_amount.text),
          notes: _notes.text.trim(),
          actor: widget.actor,
        );
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

  Future<void> _cancel() async {
    if (_newlyAdded != null) await FinanceFiles.delete(_newlyAdded!.path);
    if (mounted) Navigator.of(context).pop(false);
  }

  /// بطاقة التسوية: المخصص والمصروف والمرتجع والفرق بصياغته.
  Widget _settlement(ImdColors c) {
    final st = _st;
    if (st == null) return const ImdNote('اختر العهدة لتُسحب أرقامها من المسيرات.');
    final cur = FinCurrency.short(st.custody.currency);
    String m(double v) => '${printMoney(v)} $cur';
    final d = st.diff;
    final tone = d.type == CustodyOutcome.matched ? c.success : d.type == CustodyOutcome.surplus ? c.info : c.danger;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (st.sheets == 0)
        const ImdNote('لا مسير لهذه العهدة — المصروف صفر لأنه لم يُسجَّل بعد. افتح مسير العهدة قبل الإخلاء إن كان هناك صرف.'),
      const SizedBox(height: 6),
      ImdGrid(columns: 4, minItemWidth: 170, gap: 10, children: [
        _fact(c, 'رقم العهدة', st.custody.custodyNo),
        _fact(c, 'المبلغ المخصص للعهدة', m(st.granted)),
        _fact(c, 'مجموع المسير (المصروف)', m(st.spent)),
        _fact(c, 'المرتجع', m(st.returned)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(ImdSizes.radius), border: Border.all(color: tone.withValues(alpha: 0.5))),
        child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ImdChip(CustodyOutcome.label(d.type), tone: d.type == CustodyOutcome.matched ? ImdTone.ok : d.type == CustodyOutcome.surplus ? ImdTone.info : ImdTone.err),
          Text(d.amount == 0 ? '' : m(d.amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: tone)),
          Text(d.phrase(custodyKind: st.custody.kind, counterparty: st.counterparty), style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
        ]),
      ),
      const SizedBox(height: 4),
      if (_lockedApproved) const ImdNote('الإخلاء مُعتمد: أرقامه مجمَّدة وقت الاعتماد. ما يظهر أعلاه محسوبٌ من المسيرات الحالية للمقارنة.'),
    ]);
  }

  Widget _fact(ImdColors c, String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final refs = _isCustody
        ? [
            for (final x in widget.openCustodies) (x.id, '${x.custodyNo} · ${x.title} — ${printNum(x.amount != 0 ? x.amount : x.valueAmount)} ${FinCurrency.short(x.currency)}'),
            // عهدة إخلاءٍ قائم تبقى في القائمة ولو لم تعد «قيد الإخلاء».
            if (_i != null && !widget.openCustodies.any((x) => x.id == _refId)) (_refId, _i!.custodyNo.isEmpty ? _i!.refTitle : '${_i!.custodyNo} · ${_i!.refTitle}'),
          ]
        : [for (final x in widget.openContracts) (x.id, '${x.contractNo.isEmpty ? '' : '${x.contractNo} · '}${x.title} — ${x.supplier}')];
    final workflows = [
      for (final e in LinkageRepo.workflowLabels.entries)
        if (e.key != LinkageRepo.wfApproved || widget.canApprove || _workflow == LinkageRepo.wfApproved) (e.key, e.value),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.readOnly) const ImdNote('وضع العرض فقط — لا تملك صلاحية التعديل، فلا يظهر زر الحفظ.'),
      ImdNote(_isCustody
          ? 'الاعتماد يُغلق العهدة (تم الإخلاء) ويسجّل الفائض أو العجز في رصيد المالية. المسودة والمُرسل لا يُغلقان العهدة.'
          : 'تسجيل الإخلاء يُغلق العقد (منفَّذ) ويبقى محفوظًا، وحذفه يُعيد فتح مرجعه.'),
      const SizedBox(height: 8),
      ImdGrid(columns: 3, minItemWidth: 220, gap: 10, children: [
        ImdLabeled(
            'نوع الإخلاء',
            ImdSelect<String>(
              items: [for (final e in LinkClearanceKind.meta.entries) (e.key, e.value.$1)],
              value: _kind,
              onChanged: _i != null
                  ? null
                  : (v) => setState(() {
                        _kind = v ?? LinkClearanceKind.custody;
                        _refId = '';
                        _st = null;
                      }),
            )),
        if (_kind != LinkClearanceKind.other)
          ImdLabeled(
              _isCustody ? 'العهدة *' : 'العقد *',
              ImdSelect<String>(
                items: [('', 'اختر…'), ...refs],
                value: refs.any((r) => r.$1 == _refId) ? _refId : '',
                onChanged: _i != null
                    ? null
                    : (v) {
                        setState(() => _refId = v ?? '');
                        _fillFromRef();
                      },
              )),
        ImdLabeled(
          'رقم الإخلاء',
          ImdFld(
            controller: _no,
            hint: _suggestedNo.isEmpty ? 'يُولَّد تلقائيًّا' : 'فارغ = $_suggestedNo',
            suffix: ImdIconButton(icon: 'refresh', tooltip: 'ترقيم تلقائي', onPressed: () => setState(() => _no.text = _suggestedNo)),
          ),
        ),
        ImdLabeled('تاريخ الإخلاء', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
        if (_isCustody)
          ImdLabeled(
              'حالة الإخلاء',
              _lockedApproved
                  ? const Align(alignment: AlignmentDirectional.centerStart, child: ImdChip('مُعتمد', tone: ImdTone.ok, icon: 'check-circle'))
                  : ImdSelect<String>(items: workflows, value: _workflow, onChanged: (v) => setState(() => _workflow = v ?? LinkageRepo.wfDraft))),
      ]),
      const SizedBox(height: 10),
      if (_isCustody) ...[
        _settlement(c),
        const SizedBox(height: 10),
        ImdGrid(columns: 3, minItemWidth: 220, gap: 10, children: [
          ImdLabeled('رقم صك / مستند الإخلاء المالي (من المالية)', ImdFld(controller: _docNo)),
          ImdLabeled('اسم المُخلِّي (من المالية)', ImdFld(controller: _clearer)),
          ImdLabeled('تاريخ المراجعة', ImdDateField(value: _review, onChanged: (v) => setState(() => _review = v))),
        ]),
        ImdLabeled('الملاحظات الإدارية', ImdFld(controller: _adminNotes, maxLines: 2)),
        const SizedBox(height: 6),
        Text('صورة الإخلاء المالي', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_attach != null)
            ImdChip(_attach!.name, tone: ImdTone.code, icon: 'x', onTap: () => setState(() => _attach = null)),
          ImdButton.outline(label: _attach == null ? 'رفع صورة / PDF' : 'استبدال الملف', icon: 'upload', small: true, onPressed: _pick),
        ]),
      ] else
        ImdGrid(columns: 3, minItemWidth: 220, gap: 10, children: [
          ImdLabeled('الجهة المُخلى طرفها', ImdFld(controller: _party)),
          ImdLabeled(_kind == LinkClearanceKind.other ? 'البيان *' : 'البيان', ImdFld(controller: _title)),
          ImdLabeled('المبلغ المسوّى', ImdFld(controller: _amount, number: true)),
        ]),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: widget.readOnly ? 'إغلاق' : 'إلغاء', onPressed: _busy ? null : _cancel),
        if (!widget.readOnly)
          ImdButton(
          label: _i == null ? (_isCustody && _workflow != LinkageRepo.wfApproved ? 'حفظ الإخلاء' : 'تسجيل الإخلاء') : 'حفظ التعديل',
          icon: 'check-circle',
          busy: _busy,
          onPressed: _save,
        ),
      ]),
    ]);
  }
}
