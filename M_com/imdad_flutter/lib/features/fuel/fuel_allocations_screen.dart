import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';

/// تفريدة المحروقات: استحقاق كل وحدة من الوقود في كل فترة.
///
/// **وهي غير تفريدة الإعاشة.** تلك مقرَّرٌ للفرد يُضرب في القوة، وهذه مخصَّصٌ
/// للوحدة نفسها: مئتا لتر يوميًّا لمعسكرٍ بصرف النظر عن عدد من فيه.
class FuelAllocationsScreen extends StatefulWidget {
  const FuelAllocationsScreen({super.key});

  @override
  State<FuelAllocationsScreen> createState() => _FuelAllocationsScreenState();
}

class _FuelAllocationsScreenState extends State<FuelAllocationsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelAllocationRow> _rows = const [];
  List<FuelUnit> _units = const [];

  final _qty = TextEditingController();
  final _total = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  String? _editId;
  String _unitId = '';
  String _fuelType = FuelType.diesel;
  String _periodType = FuelPeriod.monthly;
  String _start = DateTime.now().toIso8601String().substring(0, 10);
  String _end = '';
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
    for (final c in [_qty, _total, _location, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await _repo.allocations();
    final units = await _repo.units(onlyActive: true);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _units = units;
      _loading = false;
    });
  }

  void _reset() {
    imdSetText(_qty, '');
    imdSetText(_total, '');
    imdSetText(_location, '');
    imdSetText(_notes, '');
    setState(() {
      _editId = null;
      _unitId = '';
      _fuelType = FuelType.diesel;
      _periodType = FuelPeriod.monthly;
      _start = DateTime.now().toIso8601String().substring(0, 10);
      _end = '';
      _active = true;
      _disbursable = true;
    });
  }

  /// رقمٌ للحقل النصّي: بلا فواصل ولا أرقام عربية، فيُعاد تحليله.
  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _edit(FuelAllocationRow row) {
    final a = row.allocation;
    imdSetText(_qty, a.quantityPerPeriod == 0 ? '' : _num(a.quantityPerPeriod));
    imdSetText(_total, a.totalQuantity == 0 ? '' : _num(a.totalQuantity));
    imdSetText(_location, a.issueLocation);
    imdSetText(_notes, a.notes);
    setState(() {
      _editId = a.id;
      _unitId = a.unitId;
      _fuelType = a.fuelType;
      _periodType = a.periodType;
      _start = a.startDate;
      _end = a.endDate;
      _active = a.active;
      _disbursable = a.disbursable;
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
    final res = await _repo.saveAllocation(
      id: _editId,
      unitId: _unitId,
      unitName: unit?.name ?? '',
      fuelType: _fuelType,
      periodType: _periodType,
      quantityPerPeriod: double.tryParse(_qty.text.trim()) ?? 0,
      totalQuantity: double.tryParse(_total.text.trim()) ?? 0,
      issueLocation: _location.text.trim(),
      startDate: _start,
      endDate: _end,
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
    if (!Perm.of(context).guard(context, 'fuelAllocations', PermAction.delete)) {
      return;
    }
    if (!await imdConfirm(
        context, 'حذف تفريدة «${row.allocation.unitName}»؟',
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تفريدة المحروقات', icon: 'sliders'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelAllocations');
    final active = _rows.where((r) => r.allocation.active).length;
    final held = _rows.where((r) => !r.allocation.disbursable).length;
    final drained = _rows.where((r) => r.entitled > 0 && r.remaining <= 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'تفريدة المحروقات',
        icon: 'sliders',
        subtitle: 'استحقاق كل وحدة من الوقود في كل فترة — يومي أو أسبوعي أو '
            'شهري أو إجمالي فترة محددة',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'التفريدات', value: nf(_rows.length)),
        ImdKpi(label: 'سارية', value: nf(active)),
        ImdKpi(
          label: 'موقوفة عن الصرف',
          value: nf(held),
          extra: held == 0
              ? null
              : const ImdChip('بإذن القائد', tone: ImdTone.pend),
        ),
        ImdKpi(
          label: 'استُنفد استحقاقها',
          value: nf(drained),
          extra: drained == 0 ? null : const ImdChip('لا تُصرف', tone: ImdTone.err),
        ),
      ]),
      if (can)
        ImdPanel(
          title: _editId == null ? 'تفريدة جديدة' : 'تعديل التفريدة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: _form(),
        ),
      ImdPanel(title: 'التفريدات', icon: 'list', child: _table(can)),
    ]);
  }

  Widget _form() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdF2(children: [
            ImdLabeled(
              'الوحدة المستفيدة *',
              ImdSelect<String>(
                items: [
                  ('', '— اختر —'),
                  for (final u in _units) (u.id, u.name),
                ],
                value: _unitId,
                onChanged: (v) => setState(() => _unitId = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'نوع الوقود *',
              ImdSelect<String>(
                items: [for (final t in FuelType.all) (t, FuelType.label(t))],
                value: _fuelType,
                onChanged: (v) =>
                    setState(() => _fuelType = v ?? FuelType.diesel),
              ),
              size: 11,
            ),
            ImdLabeled(
              'نوع الفترة *',
              ImdSelect<String>(
                items: [
                  for (final p in FuelPeriod.all) (p, FuelPeriod.label(p))
                ],
                value: _periodType,
                onChanged: (v) =>
                    setState(() => _periodType = v ?? FuelPeriod.monthly),
              ),
              size: 11,
            ),
            // الفترة المحددة إجماليٌّ لا يتراكم، وغيرها كميةٌ تتكرر.
            if (_periodType == FuelPeriod.custom)
              ImdLabeled(
                'إجمالي الفترة (${Fuel.unit}) *',
                ImdFld(controller: _total, number: true),
                size: 11,
              )
            else
              ImdLabeled(
                'كمية الفترة (${Fuel.unit}) *',
                ImdFld(controller: _qty, number: true),
                size: 11,
              ),
            ImdLabeled(
              'تاريخ البداية *',
              ImdDateField(
                  value: _start, onChanged: (v) => setState(() => _start = v)),
              size: 11,
            ),
            ImdLabeled(
              'تاريخ النهاية',
              ImdDateField(
                  value: _end, onChanged: (v) => setState(() => _end = v)),
              size: 11,
            ),
            ImdLabeled('مكان الصرف', ImdFld(controller: _location), size: 11),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 8, children: [
            ImdCheckbox(
              value: _active,
              label: 'سارية',
              onChanged: (v) => setState(() => _active = v),
            ),
            ImdCheckbox(
              value: _disbursable,
              label: 'تُصرف بلا إذن خاص',
              onChanged: (v) => setState(() => _disbursable = v),
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

  Widget _table(bool can) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا تفريدات بعد',
      minWidth: 1020,
      columns: const [
        ImdCol('الرمز'),
        ImdCol('الوحدة'),
        ImdCol('النوع'),
        ImdCol('الفترة'),
        ImdCol('الكمية', numeric: true),
        ImdCol('المستحق', numeric: true),
        ImdCol('المصروف', numeric: true),
        ImdCol('المتبقي', numeric: true),
        ImdCol('الحالة'),
        ImdCol('', center: true),
      ],
      rows: [
        for (final r in _rows)
          [
            Text(r.allocation.refNo,
                style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(r.allocation.unitName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdChip(FuelType.label(r.allocation.fuelType),
                tone: r.allocation.fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(FuelPeriod.label(r.allocation.periodType)),
            Text(nf(r.allocation.periodType == FuelPeriod.custom
                ? r.allocation.totalQuantity
                : r.allocation.quantityPerPeriod)),
            Text(nf(r.entitled)),
            Text(nf(r.issued)),
            Text(nf(r.remaining),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: r.remaining <= 0 ? c.danger : c.text)),
            Wrap(spacing: 4, runSpacing: 4, children: [
              if (!r.allocation.active)
                const ImdChip('موقوفة', tone: ImdTone.off)
              else if (!r.allocation.disbursable)
                const ImdChip('بإذن القائد', tone: ImdTone.pend)
              else
                const ImdChip('سارية', tone: ImdTone.ok),
            ]),
            if (can)
              Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                ImdIconButton(
                    icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(r)),
                ImdIconButton(
                    icon: 'trash',
                    tooltip: 'حذف',
                    onPressed: () => _delete(r)),
              ])
            else
              const SizedBox.shrink(),
          ],
      ],
    );
  }
}
