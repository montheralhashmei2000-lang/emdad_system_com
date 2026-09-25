import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
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
    if (!mounted) return;

    final now = DateTime.now();
    final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    double sum(Iterable<double> xs) =>
        Fuel.round(xs.fold<double>(0, (a, b) => a + b));

    setState(() {
      _stocks = stocks;
      _alerts = alerts;
      _warehouses = warehouses;
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
        ImdLd('⏳ جارٍ الحساب…'),
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
            label: 'صرف هذا الشهر',
            value: '${nf(_issuedMonth)} ${Fuel.unit}'),
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
      ImdPanel(
          title: 'إشغال المستودعات', icon: 'package', child: _occupancy()),
      if (_alerts.isNotEmpty)
        ImdPanel(
          title: 'تنبيهات تشغيلية',
          icon: 'alert',
          child: ImdStatusList(items: [
            for (final a in _alerts)
              (a.tone == 'danger' ? 'err' : 'warn', a.title, a.hint),
          ]),
        ),
      ImdPanel(title: 'شاشات القسم', icon: 'menu', child: _shortcuts()),
      ImdPanel(
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
    ]);
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
          _OccupancyBar(
            name: w.name,
            stock: _stockOf(w.name),
            capacity: w.capacityLiters,
          ),
      ]),
    ]);
  }

  /// مداخل شاشات القسم — كل بطاقة بعنوانها وسطرٍ يقول ماذا تفعل.
  Widget _shortcuts() => ImdAutoGrid(
        minItem: 230,
        children: [
          for (final s in const [
            ('fuelIssue', 'upload', 'الصرف',
                'سند صرف حسب التفريدة أو أمر استثنائي'),
            ('fuelSupply', 'download', 'التوريد',
                'تسجيل الكميات الواردة للمستودعات'),
            ('fuelAllocations', 'clipboard', 'تفريدة المحروقات',
                'خطة الاستحقاق الأسبوعي والشهري لجميع الوحدات'),
            ('fuelUnits', 'building', 'الوحدات المستفيدة',
                'سجل الجهات المستفيدة من الصرف'),
            ('fuelWarehouses', 'warehouse', 'المستودعات',
                'السعة والأرصدة الحالية'),
            ('fuelTransfer', 'swap', 'التحويل المخزني',
                'نقل الرصيد بين المستودعات'),
            ('fuelVehicles', 'truck', 'سجل المركبات',
                'حركات الصرف حسب رقم الشاصي'),
            ('fuelOpening', 'compass', 'الرصيد الافتتاحي',
                'أرصدة بداية الفترة'),
            ('fuelReports', 'chart', 'التقارير',
                'الأرصدة والاستحقاق مقابل الصرف'),
            ('fuelStocktake', 'clipboard', 'الجرد المخزني',
                'أمر الجرد والعد الفعلي والتسوية'),
            ('fuelConsumption', 'trending', 'تقرير الاستهلاك',
                'حركات الصرف حسب الفترة'),
            ('fuelSettings', 'settings', 'الإعدادات',
                'الحدود والتواقيع وقواعد الصرف'),
          ])
            _ShortcutCard(
              icon: s.$2,
              title: s.$3,
              hint: s.$4,
              onTap: () => ImdNav.of(context).go(s.$1),
            ),
        ],
      );

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

class _OccupancyBar extends StatelessWidget {
  const _OccupancyBar({
    required this.name,
    required this.stock,
    required this.capacity,
  });

  final String name;
  final double stock;
  final double capacity;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final pct = Fuel.occupancy(used: stock, capacity: capacity);
    final known = capacity > 0;
    final color = !known
        ? c.muted
        : (pct >= FuelAlerts.fullPercent
            ? c.warn
            : (pct <= 20 ? c.danger : c.accent));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
        ),
        Text(known ? '${pct.round()}٪' : 'بلا سعة',
            style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: known ? (pct / 100).clamp(0.0, 1.0) : 0,
          minHeight: 8,
          backgroundColor: c.subtle,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        known
            ? '${nf(stock)} ${Fuel.unit} من ${nf(capacity)}'
            : '${nf(stock)} ${Fuel.unit}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: c.muted),
      ),
    ]);
  }
}

class _ShortcutCard extends StatefulWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  State<_ShortcutCard> createState() => _ShortcutCardState();
}

class _ShortcutCardState extends State<_ShortcutCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: _hover ? c.hover : c.subtle,
            border: Border.all(color: _hover ? c.accent : c.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ImdIcon(widget.icon, size: 20, color: c.accent),
              const SizedBox(height: 12),
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
              const SizedBox(height: 4),
              Text(widget.hint,
                  style: TextStyle(fontSize: 12, color: c.muted, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}
