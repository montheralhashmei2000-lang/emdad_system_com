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

/// لوحة المحروقات: الرصيد والتنبيهات وسجل المركبات.
///
/// الرصيد هنا محسوبٌ من سنداته لا مقروءٌ من عمود، فما تراه اللوحة هو ما
/// تراه التقارير — لا رقمان لخزّانٍ واحد.
class FuelDashboardScreen extends StatefulWidget {
  const FuelDashboardScreen({super.key});

  @override
  State<FuelDashboardScreen> createState() => _FuelDashboardScreenState();
}

class _FuelDashboardScreenState extends State<FuelDashboardScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelStock> _stocks = const [];
  List<FuelAlert> _alerts = const [];
  List<FuelChassisLog> _chassis = const [];
  String _tab = 'stock';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stocks = await _repo.stocks();
    final alerts = await _repo.alerts();
    final chassis = await _repo.chassisLogs();
    if (!mounted) return;
    setState(() {
      _stocks = stocks;
      _alerts = alerts;
      _chassis = chassis;
      _loading = false;
    });
  }

  double _total(String type) => _stocks
      .where((s) => s.fuelType == type)
      .fold<double>(0, (sum, s) => sum + s.stock);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'لوحة المحروقات', icon: 'zap'),
        ImdLd('⏳ جارٍ الحساب…'),
      ]);
    }
    final danger = _alerts.where((a) => a.tone == 'danger').length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'لوحة المحروقات',
        icon: 'zap',
        subtitle: 'رصيد كل مستودع من البترول والديزل، وما يوشك أن ينفد، '
            'وسجل ما صرفته كل مركبة',
      ),
      ImdKpis(children: [
        ImdKpi(
            label: 'إجمالي الديزل',
            value: '${nf(_total(FuelType.diesel))} ${Fuel.unit}'),
        ImdKpi(
            label: 'إجمالي البترول',
            value: '${nf(_total(FuelType.petrol))} ${Fuel.unit}'),
        ImdKpi(label: 'المستودعات', value: nf(_stocks.length ~/ 2)),
        ImdKpi(
          label: 'تنبيهات حرجة',
          value: nf(danger),
          extra: danger == 0
              ? null
              : const ImdChip('يحتاج إجراء', tone: ImdTone.err),
        ),
        ImdKpi(label: 'مركبات مسجّلة', value: nf(_chassis.length)),
      ]),
      ImdICard(
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton.outline(
              label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
        ]),
      ),
      if (_alerts.isNotEmpty)
        ImdPanel(
          title: 'تنبيهات تشغيلية',
          icon: 'alert',
          child: ImdStatusList(items: [
            for (final a in _alerts)
              (a.tone == 'danger' ? 'err' : 'warn', a.title, a.hint),
          ]),
        ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('stock', 'أرصدة المستودعات', icon: 'package'),
          ImdTab('chassis', 'سجل المركبات', icon: 'truck'),
        ],
      ),
      const SizedBox(height: 4),
      if (_tab == 'stock')
        ImdPanel(title: 'رصيد كل مستودع', icon: 'package', child: _stockTable())
      else
        ImdPanel(
            title: 'ما صرفته كل مركبة', icon: 'truck', child: _chassisTable()),
    ]);
  }

  Widget _stockTable() {
    final c = context.imd;
    return ImdTable(
      empty: 'لا مستودعات — عرّف مستودعًا وحدّد سعته من شاشة المستودعات',
      minWidth: 980,
      columns: const [
        ImdCol('المستودع'),
        ImdCol('النوع'),
        ImdCol('افتتاحي', numeric: true),
        ImdCol('وارد', numeric: true),
        ImdCol('محوَّل إليه', numeric: true),
        ImdCol('محوَّل منه', numeric: true),
        ImdCol('مصروف', numeric: true),
        ImdCol('فرق جرد', numeric: true),
        ImdCol('الرصيد', numeric: true),
        ImdCol('الإشغال'),
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
            Text(nf(s.transferredOut)),
            Text(nf(s.issued)),
            // الفرق يُعرض بإشارته: نقصٌ أحمر وزيادةٌ محايدة.
            Text(
              s.adjustments == 0 ? '—' : nf(s.adjustments),
              style: TextStyle(
                  color: s.adjustments < 0 ? c.danger : c.muted),
            ),
            Text('${nf(s.stock)} ${Fuel.unit}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: s.empty ? c.danger : c.text)),
            _occupancy(s),
          ],
      ],
    );
  }

  /// شريط الإشغال: الرقم وحده لا يُري الفرق بين خزّانٍ يكاد يمتلئ وآخر يكاد
  /// يفرغ إذا اختلفت سعتاهما.
  Widget _occupancy(FuelStock s) {
    final c = context.imd;
    if (s.capacityLiters <= 0) {
      return Text('بلا سعة', style: TextStyle(color: c.muted, fontSize: 12));
    }
    final pct = s.occupancy;
    final color = pct >= FuelAlerts.fullPercent
        ? c.warn
        : (pct <= 20 ? c.danger : c.success);
    return SizedBox(
      width: 110,
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: c.subtle,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${pct.round()}%',
            style: TextStyle(fontSize: 11, color: c.muted)),
      ]),
    );
  }

  Widget _chassisTable() => ImdTable(
        empty: 'لا مركبات بعد — يظهر هنا كل شاصي صُرف له وقود',
        minWidth: 720,
        columns: const [
          ImdCol('رقم الشاصي'),
          ImdCol('نوع المركبة'),
          ImdCol('آخر سائق'),
          ImdCol('آخر صرف'),
          ImdCol('عدد المرات', numeric: true),
          ImdCol('الإجمالي', numeric: true),
        ],
        rows: [
          for (final v in _chassis)
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
      );
}
