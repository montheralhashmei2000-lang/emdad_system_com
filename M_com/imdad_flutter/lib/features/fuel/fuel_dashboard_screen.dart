import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_occupancy_bar.dart';
import '../../core/ui/imd_shimmer.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/fuel.dart';
import '../home/home_shell.dart';
import 'fuel_print.dart';

/// الشاشة الرئيسية لقسم المحروقات.
///
/// **لوحةٌ تُقرأ ويُنطلق منها**: الأرقام التي تُسأل كل صباح أعلاها، ثم إشغال
/// كل خزّان، ثم مداخل شاشات القسم — فمن يفتح النظام يجد ما يريد في شاشةٍ
/// واحدة بدل أن يتصفّح القائمة بحثًا عنه.
///
/// والرصيد محسوبٌ من سنداته لا مقروءٌ من عمود، فما تراه اللوحة هو ما تراه
/// التقارير — لا رقمان لخزّانٍ واحد.
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
  List<FuelWarehouse> _warehouses = const [];
  List<FuelIssue> _issues = const [];
  List<FuelAllocationRow> _allocations = const [];
  double _issuedMonth = 0;
  double _suppliedMonth = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stocks = await _repo.stocks();
    final alerts = await _repo.alerts();
    final warehouses = await _repo.warehouses();
    final issues = await _repo.issues();
    final supplies = await _repo.supplies();
    final allocations = await _repo.allocations();
    if (!mounted) return;

    final now = DateTime.now();
    final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    double sum(Iterable<double> xs) =>
        Fuel.round(xs.fold<double>(0, (a, b) => a + b));

    setState(() {
      _stocks = stocks;
      _alerts = alerts;
      _warehouses = warehouses;
      _issues = issues;
      _allocations = allocations;
      _issuedMonth = sum(issues
          .where((i) => i.date.compareTo(from) >= 0)
          .map((i) => i.quantityLiters));
      _suppliedMonth = sum(supplies
          .where((x) => x.date.compareTo(from) >= 0)
          .map((x) => x.quantityLiters));
      _loading = false;
    });
  }

  double _total([String? type]) => Fuel.round(_stocks
      .where((s) => type == null || s.fuelType == type)
      .fold<double>(0, (sum, s) => sum + s.stock));

  double _stockOf(String warehouse) => Fuel.round(_stocks
      .where((s) => s.warehouse == warehouse)
      .fold<double>(0, (sum, s) => sum + s.stock));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'قسم المحروقات', icon: 'zap'),
        ImdShimmerKpis(count: 6),
        ImdShimmerTable(rows: 4, columns: 3),
      ]);
    }
    final danger = _alerts.where((a) => a.tone == 'danger').length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'قسم المحروقات',
        icon: 'zap',
        subtitle: 'شعبة الإمداد والتموين — بترول وديزل باللتر فقط',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي الرصيد', value: '${nf(_total())} ${Fuel.unit}'),
        ImdKpi(
            label: 'بترول',
            value: '${nf(_total(FuelType.petrol))} ${Fuel.unit}'),
        ImdKpi(
            label: 'ديزل',
            value: '${nf(_total(FuelType.diesel))} ${Fuel.unit}'),
        ImdKpi(
            label: 'صرف هذا الشهر', value: '${nf(_issuedMonth)} ${Fuel.unit}'),
        ImdKpi(
            label: 'توريد هذا الشهر',
            value: '${nf(_suppliedMonth)} ${Fuel.unit}'),
        ImdKpi(
          label: 'تنبيهات حرجة',
          value: nf(danger),
          extra: danger == 0
              ? null
              : const ImdChip('يحتاج إجراء', tone: ImdTone.err),
        ),
      ]),
      // نفس إيقاع dashboard_screen.dart: صفوف ImdGrid2 بلوحتين جنبًا إلى جنب،
      // لا لوحاتٌ مكدَّسة بعرضٍ كامل — الشكل واحد وإن اختلف المحتوى.
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'إشغال المستودعات',
          icon: 'package',
          child: _occupancy(),
        ),
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'شاشات القسم',
          icon: 'zap',
          child: _shortcuts(),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'أرصدة الخزّانات',
          icon: 'trending',
          child: _chart(),
        ),
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'تنبيهات تشغيلية',
          icon: 'alert',
          child: _alerts.isEmpty
              ? const ImdLdText('لا توجد تنبيهاتٌ تشغيلية الآن.')
              : ImdStatusList(items: [
                  for (final a in _alerts)
                    (a.tone == 'danger' ? 'err' : 'warn', a.title, a.hint),
                ]),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'أرصدة المستودعات',
          icon: 'chart',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                ImdButton.outline(
                    label: 'تحديث',
                    icon: 'refresh',
                    small: true,
                    onPressed: _load),
                ImdButton.outline(
                  label: 'طباعة كشف الأرصدة',
                  icon: 'printer',
                  small: true,
                  onPressed: () => FuelPrint.stocksReport(_db, _stocks),
                ),
              ]),
            ),
            _stockTable(),
          ]),
        ),
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'آخر حركات الصرف',
          icon: 'upload',
          child: _recent(),
        ),
      ]),
    ]);
  }

  /// أعمدةُ كل خزّان: بترولٌ وديزل جنبًا إلى جنب.
  ///
  /// الجدول تحته يقول الرقم، والرسم يقول **أين يختل التوازن** — خزّانٌ مليء
  /// بالبترول فارغٌ من الديزل لا يُرى في عمودٍ من أرقام.
  Widget _chart() {
    final c = context.imd;
    final names = [for (final w in _warehouses) w.name];
    if (names.isEmpty) return const SizedBox.shrink();
    double of(String w, String type) => _stocks
        .where((s) => s.warehouse == w && s.fuelType == type)
        .fold<double>(0, (sum, s) => sum + s.stock);
    return ImdVBarChart(
      labels: names,
      height: 240,
      series: [
        ImdSeries('بترول', [for (final w in names) of(w, FuelType.petrol)],
            c.success),
        ImdSeries(
            'ديزل', [for (final w in names) of(w, FuelType.diesel)], c.info),
      ],
    );
  }

  Widget _recent() {
    final c = context.imd;
    final rows = _issues.take(6).toList();
    if (rows.isEmpty) {
      return const ImdLdText('لا توجد حركات بعد.');
    }
    return ImdTable(
      empty: 'لا توجد حركات بعد',
      minWidth: 760,
      columns: const [
        ImdCol('السند'),
        ImdCol('التاريخ'),
        ImdCol('المستودع'),
        ImdCol('الجهة المستفيدة'),
        ImdCol('النوع'),
        ImdCol('الكمية', numeric: true),
        ImdCol('', center: true),
      ],
      pageSize: 50,
      cards: true,
      rows: [
        for (final i in rows)
          [
            Text(i.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(arDigits(i.date)),
            Text(i.warehouse),
            Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
            ImdChip(FuelType.label(i.fuelType),
                tone: i.fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdIconButton(
              icon: 'printer',
              tooltip: 'طباعة السند',
              onPressed: () => FuelPrint.issueVoucher(
                _db,
                i,
                allocation: _allocations
                    .where((a) => a.allocation.id == i.allocationId)
                    .firstOrNull,
              ),
            ),
          ],
      ],
    );
  }

  /// شريط لكل خزّان: النسبة تُري ما لا يُريه الرقم — خزّانان برصيدٍ واحد
  /// وسعتين مختلفتين ليسا في حالٍ واحدة.
  Widget _occupancy() {
    final c = context.imd;
    if (_warehouses.isEmpty) {
      return const ImdEmptyBox(
          'لا مستودعات محروقات — عرّف خزّانًا وسعته من «المستودعات»');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('من السعة الكلية — بترول وديزل معًا',
            style: TextStyle(fontSize: 12.5, color: c.muted)),
      ),
      ImdAutoGrid(minItem: 240, children: [
        for (final w in _warehouses)
          ImdOccupancyBar(
            name: w.name,
            used: _stockOf(w.name),
            capacity: w.capacityLiters,
            unit: Fuel.unit,
          ),
      ]),
    ]);
  }

  /// مداخل القسم — نفس نمط «مركز الإجراءات السريعة» في dashboard_screen.dart
  /// حرفيًّا: شريط أزرارٍ صغيرة بأيقونةٍ وعنوانٍ فقط، لا بطاقاتٍ بوصفٍ تحتها.
  Widget _shortcuts() => ImdRbar(children: [
        for (final s in const [
          ('fuelMoves', 'swap', 'حركة المحروقات'),
          ('fuelAllocations', 'clipboard', 'تفريدة المحروقات'),
          ('fuelData', 'database', 'البيانات الأساسية'),
          ('fuelReports', 'chart', 'التقارير'),
          ('fuelStocktake', 'clipboard', 'الجرد المخزني'),
          ('fuelSettings', 'settings', 'الإعدادات'),
          ('fuelIssue', 'upload', 'صرف محروقات'),
          ('fuelSupply', 'download', 'توريد محروقات'),
          ('fuelDaily', 'calendar', 'الحركة اليومية'),
          ('fuelLedger', 'list', 'كشف حركة المستودع'),
        ])
          ImdButton.outline(
            label: s.$3,
            icon: s.$2,
            small: true,
            onPressed: () => ImdNav.of(context).go(s.$1),
          ),
      ]);

  Widget _stockTable() {
    final c = context.imd;
    return ImdTable(
      empty: 'لا مستودعات بعد',
      minWidth: 900,
      columns: const [
        ImdCol('المستودع'),
        ImdCol('الصنف'),
        ImdCol('الافتتاحي', numeric: true),
        ImdCol('التوريد', numeric: true),
        ImdCol('التحويل', numeric: true),
        ImdCol('الصرف', numeric: true),
        ImdCol('التسويات', numeric: true),
        ImdCol('الرصيد', numeric: true),
      ],
      cards: true,
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
            Text(nf(Fuel.round(s.transferredIn - s.transferredOut))),
            Text(nf(s.issued)),
            Text(s.adjustments == 0 ? '0' : nf(s.adjustments),
                style:
                    TextStyle(color: s.adjustments < 0 ? c.danger : c.muted)),
            Text('${nf(s.stock)} ${Fuel.unit}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: s.empty ? c.danger : c.text)),
          ],
      ],
    );
  }
}
