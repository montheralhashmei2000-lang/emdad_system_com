import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/fuel.dart';


/// الاستحقاق مقابل الصرف — أين وقف كل وحدةٍ من حقّها.
class FuelPlanVsIssuedScreen extends StatefulWidget {
  const FuelPlanVsIssuedScreen({super.key});

  @override
  State<FuelPlanVsIssuedScreen> createState() => _FuelPlanVsIssuedScreenState();
}


class _FuelPlanVsIssuedScreenState extends State<FuelPlanVsIssuedScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelAllocationRow> _rows = const [];
  String _filter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.allocations();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<FuelAllocationRow> get _visible => _filter.isEmpty
      ? _rows
      : _rows.where((r) => r.allocation.fuelType == _filter).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'الاستحقاق مقابل الصرف', icon: 'scale'),
        ImdLd('⏳ جارٍ الحساب…'),
      ]);
    }
    final rows = _visible;
    final drained = rows.where((r) => r.entitled > 0 && r.remaining <= 0).length;
    final held = rows.where((r) => !r.allocation.disbursable).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الاستحقاق مقابل الصرف',
        icon: 'scale',
        subtitle: 'ما تراكم لكل وحدة من حقّها وما أخذته منه — ومن استنفد حقّه '
            'لا يُصرف له',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'التفريدات', value: nf(rows.length)),
        ImdKpi(
            label: 'المستحق المتراكم',
            value: nf(rows.fold<double>(0, (t, r) => t + r.entitled))),
        ImdKpi(
            label: 'المصروف',
            value: nf(rows.fold<double>(0, (t, r) => t + r.issued))),
        ImdKpi(
          label: 'استُنفد استحقاقها',
          value: nf(drained),
          extra: drained == 0
              ? null
              : const ImdChip('لا تُصرف', tone: ImdTone.err),
        ),
        ImdKpi(
          label: 'موقوفة عن الصرف',
          value: nf(held),
          extra:
              held == 0 ? null : const ImdChip('بإذن القائد', tone: ImdTone.pend),
        ),
      ]),
      ImdPillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          const ImdTab('', 'الكل'),
          for (final t in FuelType.all) ImdTab(t, FuelType.label(t)),
        ],
      ),
      const SizedBox(height: 14),
      ImdPanel(
        title: 'التفريدات',
        icon: 'scale',
        actions: [
          ImdButton.outline(
              label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
        ],
        child: _table(rows),
      ),
    ]);
  }

  Widget _table(List<FuelAllocationRow> rows) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا تفريدات بعد',
      minWidth: 940,
      columns: const [
        ImdCol('الرمز'),
        ImdCol('الوحدة'),
        ImdCol('الصنف'),
        ImdCol('الشهري', numeric: true),
        ImdCol('المستحق المتراكم', numeric: true),
        ImdCol('المصروف', numeric: true),
        ImdCol('المتبقي', numeric: true),
        ImdCol('الاستهلاك'),
      ],
      pageSize: 50,
      rows: [
        for (final r in rows)
          [
            Text(r.allocation.refNo,
                style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(r.allocation.unitName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdChip(FuelType.label(r.allocation.fuelType),
                tone: r.allocation.fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(nf(Fuel.monthlyOf(r.calc))),
            Text(nf(r.entitled)),
            Text(nf(r.issued)),
            Text(nf(r.remaining),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: r.remaining <= 0 ? c.danger : c.text)),
            _bar(r),
          ],
      ],
    );
  }

  /// شريط ما استُهلك من الاستحقاق — الرقم وحده لا يقول «كم بقي له».
  Widget _bar(FuelAllocationRow a) {
    final c = context.imd;
    if (a.entitled <= 0) return Text('—', style: TextStyle(color: c.muted));
    final used = (a.issued / a.entitled).clamp(0.0, 1.0);
    final color = used >= 1 ? c.danger : (used >= 0.9 ? c.warn : c.success);
    return SizedBox(
      width: 120,
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 7,
              backgroundColor: c.subtle,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${(used * 100).round()}٪',
            style: TextStyle(fontSize: 11, color: c.muted)),
      ]),
    );
  }
}
