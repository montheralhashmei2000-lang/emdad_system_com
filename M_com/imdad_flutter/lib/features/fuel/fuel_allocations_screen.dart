import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';
import 'fuel_plan_row.dart';
import 'fuel_report_docs.dart';

/// تفريدة المحروقات: خطة توزيع الاستحقاق الأسبوعي والشهري لكل وحدة.
///
/// **وهي غير تفريدة الإعاشة.** تلك مقرَّرٌ للفرد يُضرب في القوة، وهذه مخصَّصٌ
/// للوحدة نفسها: ألفُ لتر أسبوعيًّا لشعبةٍ بصرف النظر عن عدد من فيها.
///
/// والجدولان منفصلان — بترولٌ وديزل — لأن الخطة تُرفع هكذا وتُعتمد هكذا:
/// إجماليُّ البترول رقمٌ يُوقَّع عليه وحده، لا يُخلط بالديزل في مجموعٍ واحد.
class FuelAllocationsScreen extends StatefulWidget {
  const FuelAllocationsScreen({super.key});

  @override
  State<FuelAllocationsScreen> createState() => _FuelAllocationsScreenState();
}

class _FuelAllocationsScreenState extends State<FuelAllocationsScreen> {
  /// قواعد الصرف كما تُذيَّل بها الخطة الورقية.
  static const List<String> rules = [
    'يصرف بداية الشهر بنسبة ٤٠٪، ومنتصف الشهر ٣٠٪، ونهاية الشهر ٣٠٪.',
    'الاحتياط لا يصرف إلا بتوجيه من القائد العام للفرقة أو من يخوله.',
    'أي شعبة لا تستهلك كامل مخصصها يعاد المتبقي إلى بند الاحتياط.',
  ];

  /// أمكنة الصرف المعتادة — تُقترح ولا تُلزم.
  static const List<String> locations = [
    'جميع المعسكرات',
    'مكان عمله',
    'مقر قيادة الفرقة',
    'مقر معسكر الثنية',
    'الوديعة',
    'ينزل على م/الثنية',
  ];

  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelAllocationRow> _rows = const [];
  List<FuelUnit> _units = const [];
  FuelSettingsRow? _settings;

  final _weekly = TextEditingController();
  final _monthly = TextEditingController();
  final _location = TextEditingController(text: 'جميع المعسكرات');
  final _notes = TextEditingController();

  String? _editId;
  String _unitId = '';
  String _fuelType = FuelType.petrol;

  /// مرشّح نوع الوقود في العرض — الكل أو نوعٌ بعينه.
  String _filter = '';

  String _start = DateTime.now().toIso8601String().substring(0, 10);
  bool _active = true;
  bool _disbursable = true;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_weekly, _monthly, _location, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await _repo.allocations();
    final units = await _repo.units(onlyActive: true);
    final settings = await _repo.settings();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _units = units;
      _settings = settings;
      _loading = false;
      if (_editId == null && _weekly.text.trim().isEmpty) {
        imdSetText(_weekly, _num(settings.defaultWeeklyLiters));
        imdSetText(_monthly, _num(settings.defaultMonthlyLiters));
      }
    });
  }

  /// رقمٌ للحقل النصّي: بلا فواصل ولا أرقام عربية، فيُعاد تحليله.
  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  double get _weeklyValue => double.tryParse(_weekly.text.trim()) ?? 0;
  double get _monthlyValue => double.tryParse(_monthly.text.trim()) ?? 0;

  /// الشهري أربعةُ أسابيع ما لم يُكتب بيده: من يكتب الأسبوعي وحده يريد
  /// الشهري تبعًا له، ومن كتب الشهري صراحةً لا يُداس على ما كتب.
  void _onWeeklyChanged(String v) {
    final weekly = double.tryParse(v.trim()) ?? 0;
    final auto = _monthlyValue == 0 || _monthlyValue == _lastAuto;
    if (auto) {
      _lastAuto = weekly * 4;
      imdSetText(_monthly, _num(_lastAuto));
    }
    setState(() {});
  }

  double _lastAuto = 0;

  void _reset() {
    final s = _settings;
    imdSetText(_weekly, s == null ? '' : _num(s.defaultWeeklyLiters));
    imdSetText(_monthly, s == null ? '' : _num(s.defaultMonthlyLiters));
    imdSetText(_location, 'جميع المعسكرات');
    imdSetText(_notes, '');
    setState(() {
      _editId = null;
      _unitId = '';
      _fuelType = FuelType.petrol;
      _start = DateTime.now().toIso8601String().substring(0, 10);
      _active = true;
      _disbursable = true;
      _lastAuto = 0;
    });
  }

  void _edit(FuelAllocationRow row) {
    final a = row.allocation;
    imdSetText(_weekly, _num(Fuel.weeklyOf(row.calc)));
    imdSetText(_monthly, _num(Fuel.monthlyOf(row.calc)));
    imdSetText(_location, a.issueLocation);
    imdSetText(_notes, a.notes);
    setState(() {
      _editId = a.id;
      _unitId = a.unitId;
      _fuelType = a.fuelType;
      _start = a.startDate;
      _active = a.active;
      _disbursable = a.disbursable;
      _lastAuto = 0;
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelAllocations',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    setState(() => _busy = true);
    final unit = _units.where((u) => u.id == _unitId).firstOrNull;
    final monthly =
        _monthlyValue > 0 ? _monthlyValue : Fuel.round(_weeklyValue * 4);
    final res = await _repo.saveAllocation(
      id: _editId,
      unitId: _unitId,
      unitName: unit?.name ?? '',
      fuelType: _fuelType,
      // الخطة شهرية دائمًا، والأسبوعي حصةٌ منها تُقرأ ولا تُراكم مرتين.
      periodType: FuelPeriod.monthly,
      quantityPerPeriod: monthly,
      weeklyLiters: _weeklyValue,
      monthlyLiters: monthly,
      issueLocation: _location.text.trim().isEmpty
          ? 'جميع المعسكرات'
          : _location.text.trim(),
      startDate: _start,
      active: _active,
      disbursable: _disbursable,
      notes: _notes.text.trim(),
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ حُفظت التفريدة ${res.refNo}' : res.error,
        error: !res.ok);
    if (res.ok) {
      _reset();
      await _load();
    }
  }

  Future<void> _delete(FuelAllocationRow row) async {
    if (!Perm.of(context)
        .guard(context, 'fuelAllocations', PermAction.delete)) {
      return;
    }
    if (!await imdConfirm(context, 'حذف تفريدة «${row.allocation.unitName}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.deleteAllocation(
      row.allocation.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذفت التفريدة' : res.error,
        error: !res.ok);
    if (res.ok) {
      if (_editId == row.allocation.id) _reset();
      await _load();
    }
  }

  List<FuelAllocationRow> _of(String fuelType) =>
      _rows.where((r) => r.allocation.fuelType == fuelType).toList();

  Future<void> _printPlan() async {
    final settings = _settings;
    if (settings == null) return;
    if (_rows.isEmpty) {
      showImdToast(context, '✖ لا تفريدات لطباعتها');
      return;
    }
    await FuelReportDocs.printPlan(
      _db,
      settings: settings,
      petrol: _planRows(_of(FuelType.petrol)),
      diesel: _planRows(_of(FuelType.diesel)),
      rules: rules,
    );
  }

  List<FuelPlanRow> _planRows(List<FuelAllocationRow> list) {
    var n = 0;
    return [
      for (final r in list)
        FuelPlanRow(
          n: ++n,
          unit: r.allocation.unitName,
          location: r.allocation.issueLocation.isEmpty
              ? '—'
              : r.allocation.issueLocation,
          weekly: Fuel.weeklyOf(r.calc),
          monthly: Fuel.monthlyOf(r.calc),
          notes: _noteOf(r),
        ),
    ];
  }

  /// «لا يصرف» تُكتب في الملاحظات لا في عمودٍ يُنسى: الورقة تُقرأ سطرًا سطرًا.
  static String _noteOf(FuelAllocationRow r) {
    final a = r.allocation;
    if (a.disbursable) return a.notes;
    return a.notes.isEmpty ? 'لا يصرف' : '${a.notes} — لا يصرف';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تفريدة المحروقات', icon: 'clipboard'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelAllocations');

    return ImdPage(children: [
      ImdPageTitle(
        title: 'تفريدة المحروقات',
        icon: 'clipboard',
        subtitle: 'خطة توزيع الاستحقاق — بترول لجميع الوحدات وديزل لجميع '
            'الوحدات',
        trailing: ImdButton.outline(
            label: 'طباعة الخطة', icon: 'printer', onPressed: _printPlan),
      ),
      ImdPillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          const ImdTab('', 'الكل'),
          for (final t in FuelType.all) ImdTab(t, FuelType.label(t)),
        ],
      ),
      const SizedBox(height: 14),
      if (can)
        ImdPanel(
          title: _editId == null ? 'تفريدة جديدة' : 'تعديل التفريدة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: _form(),
        ),
      if (_rows.isEmpty)
        const ImdEmptyBox(
            'لا توجد تفريدة — أنشئ أول تفريدة لتحديد استحقاقات الوحدات')
      else ...[
        if (_filter != FuelType.diesel)
          _planTable('تفريدة البترول — جميع الوحدات المستفيدة',
              _of(FuelType.petrol), can),
        if (_filter != FuelType.petrol)
          _planTable('تفريدة الديزل — جميع الوحدات المستفيدة',
              _of(FuelType.diesel), can),
        ImdNote('**قواعد الصرف**\n\n${rules.map((r) => '• $r').join('\n')}'),
        const SizedBox(height: 20),
      ],
    ]);
  }

  Widget _form() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdF2(children: [
            ImdLabeled(
              'نوع الصنف *',
              ImdSelect<String>(
                items: [for (final t in FuelType.all) (t, FuelType.label(t))],
                value: _fuelType,
                onChanged: (v) =>
                    setState(() => _fuelType = v ?? FuelType.petrol),
              ),
              size: 11,
            ),
            ImdLabeled(
              'الوحدة المستفيدة *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر الوحدة —'),
                  for (final u in _units) (u.id, u.name),
                ],
                value: _unitId,
                onChanged: (v) => setState(() => _unitId = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'مكان الصرف',
              ImdFld(
                controller: _location,
                hint: 'جميع المعسكرات',
                suggestions: locations,
              ),
              size: 11,
            ),
            ImdLabeled(
              'الاستحقاق الأسبوعي (${Fuel.unit})',
              ImdFld(
                  controller: _weekly,
                  number: true,
                  onChanged: _onWeeklyChanged),
              size: 11,
            ),
            ImdLabeled(
              'الاستحقاق الشهري (${Fuel.unit})',
              ImdFld(
                  controller: _monthly,
                  number: true,
                  onChanged: (_) => setState(() {})),
              size: 11,
            ),
            ImdLabeled(
              'تاريخ بدء الخطة *',
              ImdDateField(
                  value: _start, onChanged: (v) => setState(() => _start = v)),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 8, children: [
            ImdCheckbox(
              value: _disbursable,
              label: 'يُصرف ضمن التفريدة (إلغاء التأشير = احتياط لا يصرف)',
              onChanged: (v) => setState(() => _disbursable = v),
            ),
            if (_editId != null)
              ImdCheckbox(
                value: _active,
                label: 'تفريدة نشطة',
                onChanged: (v) => setState(() => _active = v),
              ),
          ]),
          if (!_disbursable) ...[
            const SizedBox(height: 8),
            const ImdNote(
              'التفريدة **تبقى سارية ويتراكم استحقاقها**، لكنها لا تُصرف حتى '
              'يأذن القائد. الإيقاف عن الصرف غير إيقاف التفريدة.',
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ImdButton(
              label: _editId == null ? 'حفظ التفريدة' : 'حفظ التعديل',
              icon: 'check',
              busy: _busy,
              onPressed: _save,
            ),
            if (_editId != null)
              ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: _reset),
          ]),
        ],
      );

  Widget _planTable(String title, List<FuelAllocationRow> list, bool can) {
    final c = context.imd;
    final weekly = list.fold<double>(0, (s, r) => s + Fuel.weeklyOf(r.calc));
    final monthly = list.fold<double>(0, (s, r) => s + Fuel.monthlyOf(r.calc));
    final issued = list.fold<double>(0, (s, r) => s + r.issued);
    final remaining = list.fold<double>(0, (s, r) => s + r.remaining);
    var n = 0;

    return ImdPanel(
      title: title,
      icon: 'list',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${nf(list.length)} وحدة · أسبوعي ${nf(weekly)} · شهري ${nf(monthly)}',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ),
        ImdTable(
          empty: 'لا توجد بنود لهذا الصنف.',
          minWidth: 1040,
          columns: const [
            ImdCol('م', center: true),
            ImdCol('الوحدة'),
            ImdCol('مكان الصرف'),
            ImdCol('الاستحقاق الأسبوعي', numeric: true),
            ImdCol('الاستحقاق الشهري', numeric: true),
            ImdCol('المصروف', numeric: true),
            ImdCol('المتبقي', numeric: true),
            ImdCol('ملاحظات'),
            ImdCol('', center: true),
          ],
          rows: [
            for (final r in list)
              [
                Text('${++n}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.allocation.unitName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(r.allocation.refNo,
                        style: TextStyle(fontSize: 11, color: c.muted)),
                  ],
                ),
                Text(r.allocation.issueLocation.isEmpty
                    ? '—'
                    : r.allocation.issueLocation),
                Text(nf(Fuel.weeklyOf(r.calc))),
                Text(nf(Fuel.monthlyOf(r.calc))),
                Text(nf(r.issued)),
                Text(nf(r.remaining),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: r.remaining <= 0 ? c.danger : c.text)),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (!r.allocation.disbursable)
                    const ImdChip('لا يصرف', tone: ImdTone.pend),
                  if (!r.allocation.active)
                    const ImdChip('موقوفة', tone: ImdTone.err),
                  if (r.allocation.notes.isNotEmpty)
                    Text(r.allocation.notes,
                        style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
                if (can)
                  Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                    ImdIconButton(
                        icon: 'edit',
                        tooltip: 'تعديل',
                        onPressed: () => _edit(r)),
                    ImdIconButton(
                        icon: 'trash',
                        tooltip: 'حذف',
                        onPressed: () => _delete(r)),
                  ])
                else
                  const SizedBox.shrink(),
              ],
          ],
          // سطر الإجمالي جزءٌ من الجدول لا تعليقٌ تحته: الخطة تُعتمد بمجموعها.
          footer: [
            const Text(''),
            const Text('الإجمالي',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Text(''),
            Text(nf(weekly),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(monthly),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(issued),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(remaining),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text(''),
            const Text(''),
          ],
        ),
      ]),
    );
  }
}
