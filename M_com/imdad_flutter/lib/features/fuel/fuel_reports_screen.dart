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
import 'fuel_print.dart';

/// تقارير المحروقات: أرصدة المستودعات، والاستحقاق مقابل الصرف.
///
/// **الرقمان اللذان يُسأل عنهما دائمًا**: كم بقي في الخزّان، وكم أخذت كل وحدة
/// من حقّها. والأول يُقرأ من الحركات، والثاني من التفريدة — وكلاهما محسوبٌ
/// لا مخزَّن، فلا يفترق تقريرٌ عن شاشة.
class FuelReportsScreen extends StatefulWidget {
  const FuelReportsScreen({super.key});

  @override
  State<FuelReportsScreen> createState() => _FuelReportsScreenState();
}

class _FuelReportsScreenState extends State<FuelReportsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelStock> _stocks = const [];
  List<FuelAllocationRow> _allocations = const [];
  String _tab = 'stocks';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stocks = await _repo.stocks();
    final allocations = await _repo.allocations();
    if (!mounted) return;
    setState(() {
      _stocks = stocks;
      _allocations = allocations;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تقارير المحروقات', icon: 'chart'),
        ImdLd('⏳ جارٍ الحساب…'),
      ]);
    }
    final total = _stocks.fold<double>(0, (s, x) => s + x.stock);
    final drained =
        _allocations.where((a) => a.entitled > 0 && a.remaining <= 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'تقارير المحروقات',
        icon: 'chart',
        subtitle: 'الافتتاحي + التوريد + المحوَّل إليه − المحوَّل منه − '
            'المصروف ± فرق الجرد = الرصيد الحالي',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'الرصيد الكلي', value: '${nf(total)} ${Fuel.unit}'),
        ImdKpi(label: 'المستودعات', value: nf(_stocks.length ~/ 2)),
        ImdKpi(label: 'التفريدات', value: nf(_allocations.length)),
        ImdKpi(
          label: 'استُنفد استحقاقها',
          value: nf(drained),
          extra:
              drained == 0 ? null : const ImdChip('لا تُصرف', tone: ImdTone.err),
        ),
      ]),
      ImdICard(
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton.outline(
              label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
          ImdButton.outline(
            label: 'طباعة كشف الأرصدة',
            icon: 'printer',
            small: true,
            onPressed: () => FuelPrint.stocksReport(_db, _stocks),
          ),
        ]),
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('stocks', 'أرصدة المستودعات', icon: 'package'),
          ImdTab('plan', 'الاستحقاق مقابل الصرف', icon: 'scale'),
        ],
      ),
      if (_tab == 'stocks')
        ImdPanel(
            title: 'أرصدة المستودعات — محسوبة من الحركات',
            icon: 'package',
            child: _stocksTable())
      else
        ImdPanel(
            title: 'الاستحقاق مقابل الصرف',
            icon: 'scale',
            child: _planTable()),
    ]);
  }

  Widget _stocksTable() {
    final c = context.imd;
    return ImdTable(
      empty: 'لا مستودعات محروقات بعد',
      minWidth: 960,
      columns: const [
        ImdCol('المستودع'),
        ImdCol('الصنف'),
        ImdCol('الافتتاحي', numeric: true),
        ImdCol('التوريد', numeric: true),
        ImdCol('محوَّل إليه', numeric: true),
        ImdCol('محوَّل منه', numeric: true),
        ImdCol('الصرف', numeric: true),
        ImdCol('التسويات', numeric: true),
        ImdCol('الرصيد', numeric: true),
      ],
      rows: [
        for (final s in _stocks)
          [
            Text(s.warehouse,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdChip(FuelType.label(s.fuelType),
                tone: s.fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(nf(s.opening)),
            Text(nf(s.supplied)),
            Text(nf(s.transferredIn)),
            Text(s.transferredOut == 0 ? '—' : '−${nf(s.transferredOut)}'),
            Text(nf(s.issued)),
            Text(s.adjustments == 0 ? '—' : nf(s.adjustments),
                style: TextStyle(
                    color: s.adjustments < 0 ? c.danger : c.muted)),
            Text('${nf(s.stock)} ${Fuel.unit}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: s.empty ? c.danger : c.text)),
          ],
      ],
    );
  }

  Widget _planTable() {
    final c = context.imd;
    return ImdTable(
      empty: 'لا تفريدات بعد',
      minWidth: 900,
      columns: const [
        ImdCol('الرمز'),
        ImdCol('الوحدة'),
        ImdCol('النوع'),
        ImdCol('الفترة'),
        ImdCol('المستحق', numeric: true),
        ImdCol('المصروف', numeric: true),
        ImdCol('المتبقي', numeric: true),
        ImdCol('الاستهلاك'),
      ],
      rows: [
        for (final a in _allocations)
          [
            Text(a.allocation.refNo,
                style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(a.allocation.unitName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(FuelType.label(a.allocation.fuelType)),
            Text(FuelPeriod.label(a.allocation.periodType)),
            Text(nf(a.entitled)),
            Text(nf(a.issued)),
            Text(nf(a.remaining),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: a.remaining <= 0 ? c.danger : c.text)),
            _bar(a),
          ],
      ],
    );
  }

  /// شريط ما استُهلك من الاستحقاق — الرقم وحده لا يقول «كم بقي له».
  Widget _bar(FuelAllocationRow a) {
    final c = context.imd;
    if (a.entitled <= 0) {
      return Text('—', style: TextStyle(color: c.muted));
    }
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

/// سجل المركبات — ما شربته كل مركبة بشاصيها.
///
/// **الشاصي هو ما يُحاسب عليه.** السائق يتبدّل والوحدة تتبدّل، ورقم الشاصي
/// يبقى — وبه وحده يُكشف صرفٌ متكرر لمركبةٍ واحدة بأسماء سائقين مختلفين.
class FuelVehiclesScreen extends StatefulWidget {
  const FuelVehiclesScreen({super.key});

  @override
  State<FuelVehiclesScreen> createState() => _FuelVehiclesScreenState();
}

class _FuelVehiclesScreenState extends State<FuelVehiclesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelChassisLog> _logs = const [];
  List<FuelIssue> _issues = const [];
  final _q = TextEditingController();
  String _open = '';
  bool _loading = true;

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
    final logs = await _repo.chassisLogs();
    final issues = await _repo.issues();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _issues = issues;
      _loading = false;
    });
  }

  List<FuelChassisLog> get _visible {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs
        .where((v) =>
            v.chassisNo.toLowerCase().contains(q) ||
            v.vehicleType.toLowerCase().contains(q) ||
            v.lastDriver.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'سجل المركبات', icon: 'truck'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final total = _logs.fold<double>(0, (s, v) => s + v.liters);
    final noChassis =
        _issues.where((i) => i.chassisNo.trim().isEmpty).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'سجل المركبات',
        icon: 'truck',
        subtitle: 'ما شربته كل مركبة بشاصيها — السائق يتبدّل والشاصي يبقى',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'المركبات', value: nf(_logs.length)),
        ImdKpi(
            label: 'إجمالي ما صُرف لها',
            value: '${nf(total)} ${Fuel.unit}'),
        ImdKpi(
          label: 'صرف بلا شاصي',
          value: nf(noChassis),
          extra: noChassis == 0
              ? null
              : const ImdChip('لا يُحاسب عليه', tone: ImdTone.pend),
        ),
      ]),
      ImdICard(
        child: ImdSearchBar(
          controller: _q,
          hint: 'بحث بالشاصي أو نوع المركبة أو السائق…',
          onChanged: (_) => setState(() {}),
          actions: [
            ImdButton.outline(
                label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
          ],
        ),
      ),
      if (noChassis > 0)
        ImdNote(
          'يوجد ${nf(noChassis)} سند صرف بلا رقم شاصي، فلا يدخل هذا السجل. '
          'ويمكن **اشتراط الشاصي** في كل صرف من «إعدادات المحروقات».',
        ),
      ImdPanel(
        title: 'المركبات',
        icon: 'list',
        child: ImdTable(
          empty: 'لا مركبات بعد — يظهر هنا كل شاصي صُرف له وقود',
          minWidth: 820,
          onRowTap: (i) => setState(
              () => _open = _open == _visible[i].chassisNo ? '' : _visible[i].chassisNo),
          columns: const [
            ImdCol('رقم الشاصي'),
            ImdCol('نوع المركبة'),
            ImdCol('آخر سائق'),
            ImdCol('آخر صرف'),
            ImdCol('عدد المرات', numeric: true),
            ImdCol('الإجمالي', numeric: true),
          ],
          rows: [
            for (final v in _visible)
              [
                Text(v.chassisNo,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(v.vehicleType.isEmpty ? '—' : v.vehicleType),
                Text(v.lastDriver.isEmpty ? '—' : v.lastDriver),
                Text(arDigits(v.lastDate)),
                Text(nf(v.count)),
                Text('${nf(v.liters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
          ],
        ),
      ),
      if (_open.isNotEmpty)
        ImdPanel(
          title: 'سندات المركبة $_open',
          icon: 'file',
          child: ImdTable(
            empty: 'لا سندات',
            minWidth: 760,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المستودع'),
              ImdCol('المستفيد'),
              ImdCol('السائق'),
              ImdCol('الكمية', numeric: true),
            ],
            rows: [
              for (final i in _issues.where((x) => x.chassisNo.trim() == _open))
                [
                  Text(i.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(i.date)),
                  Text(FuelType.label(i.fuelType)),
                  Text(i.warehouse),
                  Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
                  Text(i.driverName.isEmpty ? '—' : i.driverName),
                  Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ),
    ]);
  }
}
