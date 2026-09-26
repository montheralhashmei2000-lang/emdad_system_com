import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/fuel.dart';
import '../../domain/fuel_daily_report.dart';
import '../../domain/fuel_report.dart';
import 'fuel_daily_pdf.dart';
import 'fuel_paper.dart';

/// تقرير الحركة اليومية للمحروقات — الدفتر اليومي بجميع معسكراته.
///
/// يُعرض كما سيُطبع: ملخصٌ أولًا يُقرأ في نظرة، ثم تفصيلُ كل معسكر في ثلاثة
/// جداول — الوارد، فالمنصرف، فالتحويل إن وُجد — ولكلٍّ إجماليه في ذيله.
class FuelDailyReportScreen extends StatefulWidget {
  const FuelDailyReportScreen({super.key});

  @override
  State<FuelDailyReportScreen> createState() => _FuelDailyReportScreenState();
}

class _FuelDailyReportScreenState extends State<FuelDailyReportScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelOpening> _openings = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelIssue> _issues = const [];
  List<FuelTransfer> _transfers = const [];
  List<FuelAdjustment> _adjustments = const [];
  FuelSettingsRow? _settings;

  late String _from = _iso(DateTime.now());
  late String _to = _iso(DateTime.now());
  String _warehouse = '';
  final Set<String> _kinds = {...FuelMoveKind.all};
  bool _loading = true;

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final warehouses = await _repo.warehouses(onlyActive: true);
    final openings = await _repo.openings();
    final supplies = await _repo.supplies();
    final issues = await _repo.issues();
    final transfers = await _repo.transfers();
    final adjustments = await _repo.adjustments();
    final settings = await _repo.settings();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _openings = openings;
      _supplies = supplies;
      _issues = issues;
      _transfers = transfers;
      _adjustments = adjustments;
      _settings = settings;
      _loading = false;
    });
  }

  FuelDailyReport get _report {
    final names = _warehouse.isEmpty
        ? [for (final w in _warehouses) w.name]
        : <String>[_warehouse];
    return FuelDailyReportBuilder.build(
      range: FuelDateRange(_from, _to),
      warehouses: names,
      fuelTypes: FuelType.all,
      kinds: _kinds.toList(),
      openings: [
        for (final o in _openings)
          FuelDailyOpening(
            warehouse: o.warehouse,
            fuelType: o.fuelType,
            date: o.asOfDate,
            liters: o.liters,
          ),
      ],
      supplies: [
        for (final s in _supplies)
          FuelDailySupply(
            date: s.date,
            refNo: s.refNo,
            warehouse: s.warehouse,
            fuelType: s.fuelType,
            qty: s.quantityLiters,
            supplier: s.supplierName,
            vehicleType: s.transportVehicleType,
            driver: s.driverName,
            notes: s.notes,
          ),
      ],
      issues: [
        for (final i in _issues)
          FuelDailyIssue(
            date: i.date,
            refNo: i.refNo,
            warehouse: i.warehouse,
            fuelType: i.fuelType,
            qty: i.quantityLiters,
            beneficiary: i.beneficiaryName,
            vehicleType: i.vehicleType,
            driver: i.driverName,
            chassisNo: i.chassisNo,
            authority: i.orderAuthority.isEmpty
                ? (i.source == FuelSource.exceptional
                    ? 'أمر استثنائي'
                    : 'استحقاق')
                : i.orderAuthority,
            purpose: i.purpose.isEmpty ? i.justification : i.purpose,
            notes: i.notes,
          ),
      ],
      transfers: [
        for (final t in _transfers)
          FuelDailyTransfer(
            date: t.date,
            refNo: t.refNo,
            fromWarehouse: t.fromWarehouse,
            toWarehouse: t.toWarehouse,
            fuelType: t.fuelType,
            qty: t.quantityLiters,
            vehicleType: t.transportVehicleType,
            driver: t.driverName,
            notes: t.notes,
          ),
      ],
      adjustments: [
        for (final a in _adjustments)
          FuelDailyAdjustment(
            date: a.date,
            warehouse: a.warehouse,
            fuelType: a.fuelType,
            delta: a.delta,
          ),
      ],
    );
  }

  Future<void> _print() async {
    final settings = _settings;
    if (settings == null) return;
    await FuelDailyPdf.printReport(_db, report: _report, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تقرير الحركة اليومية للمحروقات', icon: 'calendar'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final report = _report;

    return ImdPage(children: [
      ImdPageTitle(
        title: 'تقرير الحركة اليومية للمحروقات',
        icon: 'calendar',
        subtitle: 'ملخّصٌ أولًا، ثم حركة كل معسكر: الوارد فالمنصرف فالتحويل — '
            'والرصيد ينتقل من يومٍ إلى تاليه',
        trailing: ImdButton(
            label: 'طباعة التقرير', icon: 'printer', onPressed: _print),
      ),
      ImdICard(
        title: 'نطاق التقرير',
        icon: 'sliders',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled(
              'من تاريخ',
              ImdDateField(
                  value: _from, onChanged: (v) => setState(() => _from = v)),
              size: 11,
            ),
            ImdLabeled(
              'إلى تاريخ',
              ImdDateField(
                  value: _to, onChanged: (v) => setState(() => _to = v)),
              size: 11,
            ),
            ImdLabeled(
              'المعسكر / المحطة',
              ImdSelect<String>(
                items: [
                  ('', 'جميع المعسكرات والمحطات'),
                  for (final w in _warehouses) (w.name, w.name),
                ],
                value: _warehouse,
                onChanged: (v) => setState(() => _warehouse = v ?? ''),
              ),
              size: 11,
            ),
          ]),
          const SizedBox(height: 12),
          ImdLabeled(
            'نوع الحركة',
            Wrap(spacing: 18, runSpacing: 8, children: [
              for (final k in FuelMoveKind.all)
                ImdCheckbox(
                  value: _kinds.contains(k),
                  label: FuelMoveKind.label(k),
                  // آخرُ بابٍ لا يُطفأ: تقريرٌ بلا جدولٍ واحد ورقةٌ بيضاء.
                  onChanged: (v) => setState(() {
                    if (v) {
                      _kinds.add(k);
                    } else if (_kinds.length > 1) {
                      _kinds.remove(k);
                    }
                  }),
                ),
            ]),
            size: 11,
          ),
        ]),
      ),
      FuelPaper(
        minWidth: 900,
        child: _sheet(report),
      ),
    ]);
  }

  Widget _sheet(FuelDailyReport r) {
    final s = _settings!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FuelPaperLetterhead(settings: s),
        const SizedBox(height: 12),
        FuelPaperAddressee(settings: s, span: r.range.label),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '${r.title} — ${r.range.label} م',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: FuelPaper.title,
                fontSize: 15,
                fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 20),
        _summary(r),
        for (final day in r.days) ..._day(r, day),
        const SizedBox(height: 30),
        FuelPaperSignatures(settings: s),
      ],
    );
  }

  // ───────────────────────── الملخّص

  /// **الملخّص قبل التفصيل.** من يقرأ الورقة يسأل أولًا «كم بقي وأين»، ثم
  /// يفتّش عن السند إن استغرب رقمًا — فالإجماليات في الصدر والتفاصيل بعدها.
  Widget _summary(FuelDailyReport r) {
    final adj = r.hasAdjustments;
    final many = r.days.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FuelPaperHeading('ملخّص الحركة اليومية'),
        const SizedBox(height: 6),
        FuelPaperTable(
          headers: [
            if (many) 'اليوم',
            'المعسكر / المحطة',
            'الوقود',
            'الرصيد الافتتاحي / المتبقي من السابق',
            'الوارد',
            'المنصرف',
            'التحويل',
            if (adj) 'تسوية جرد',
            'المتبقي',
          ],
          flex: [
            if (many) 3,
            5,
            2,
            5,
            3,
            3,
            3,
            if (adj) 3,
            3,
          ],
          rows: [
            for (final day in r.days)
              for (final b in day.balances)
                [
                  if (many) FuelDateRange.slash(day.date),
                  b.warehouse,
                  FuelType.label(b.fuelType),
                  nf(b.opening),
                  nf(b.incoming),
                  nf(b.issued),
                  _signed(b.transferNet),
                  if (adj) _signed(b.adjustment),
                  nf(b.closing),
                ],
          ],
          totalRow: [
            if (many) '',
            'الإجمالي',
            '',
            nf(r.totalOf((b) => b.opening)),
            nf(r.totalOf((b) => b.incoming)),
            nf(r.totalOf((b) => b.issued)),
            _signed(r.totalOf((b) => b.transferNet)),
            if (adj) _signed(r.totalOf((b) => b.adjustment)),
            nf(r.totalOf((b) => b.closing)),
          ],
        ),
      ],
    );
  }

  static String _signed(double v) {
    if (v == 0) return '—';
    return v > 0 ? '+${nf(v)}' : '−${nf(-v)}';
  }

  // ───────────────────────── تفصيل اليوم

  static const List<String> _ordinals = [
    'أولًا',
    'ثانيًا',
    'ثالثًا',
    'رابعًا',
    'خامسًا',
    'سادسًا',
    'سابعًا',
    'ثامنًا',
    'تاسعًا',
    'عاشرًا',
  ];

  static String _ordinal(int i) =>
      i < _ordinals.length ? _ordinals[i] : '${i + 1}';

  List<Widget> _day(FuelDailyReport r, FuelDailyDay day) {
    final many = r.days.length > 1;
    final camps = day.camps.where((c) => c.hasAny).toList();
    return [
      const SizedBox(height: 26),
      if (many)
        Center(
          child: Text(
            'حركة يوم ${FuelDateRange.slash(day.date)} م',
            style: const TextStyle(
                color: FuelPaper.title,
                fontSize: 13.5,
                fontWeight: FontWeight.w800),
          ),
        ),
      if (camps.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: FuelPaperHeading('لا توجد حركة في هذا اليوم'),
        ),
      for (var i = 0; i < camps.length; i++) ..._camp(day, camps[i], i),
    ];
  }

  List<Widget> _camp(FuelDailyDay day, FuelDailyCamp c, int index) => [
        const SizedBox(height: 20),
        Text(
          '${_ordinal(index)}: تقرير الحركة اليومية للمحروقات بـ${c.warehouse}',
          style: const TextStyle(
              color: FuelPaper.title,
              fontSize: 13,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'الرصيد أول اليوم: '
          '${_openingLine(c)} — والمتبقي آخره: ${_closingLine(c)}',
          style: const TextStyle(fontSize: 11, color: FuelPaper.muted),
        ),
        if (_kinds.contains(FuelMoveKind.incoming)) ...[
          const SizedBox(height: 12),
          _incomingTable(c),
        ],
        if (_kinds.contains(FuelMoveKind.issued)) ...[
          const SizedBox(height: 14),
          _issuedTable(c),
        ],
        // التحويل يُضاف إن وُجد فقط.
        if (_kinds.contains(FuelMoveKind.transfer) && c.hasTransfers) ...[
          const SizedBox(height: 14),
          _transferTable(c),
        ],
      ];

  String _openingLine(FuelDailyCamp c) => [
        for (final t in FuelType.all)
          '${FuelType.label(t)} ${nf(c.openingOf(t))}',
      ].join(' · ');

  String _closingLine(FuelDailyCamp c) => [
        for (final t in FuelType.all)
          '${FuelType.label(t)} ${nf(c.closingOf(t))}',
      ].join(' · ');

  Widget _incomingTable(FuelDailyCamp c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FuelPaperHeading('الوارد'),
          const SizedBox(height: 6),
          FuelPaperTable(
            headers: const [
              'م',
              'السند',
              'جهة التوريد',
              'الوسيلة',
              'السائق',
              'الصنف',
              'الكمية',
              'ملاحظة',
            ],
            flex: const [1, 3, 6, 3, 3, 2, 3, 3],
            emptyText: 'لا يوجد وارد',
            rows: [
              for (var i = 0; i < c.incoming.length; i++)
                [
                  '${i + 1}',
                  c.incoming[i].refNo,
                  c.incoming[i].party,
                  c.incoming[i].vehicleType,
                  c.incoming[i].driver,
                  FuelType.label(c.incoming[i].fuelType),
                  nf(c.incoming[i].qty),
                  c.incoming[i].notes,
                ],
            ],
            totalRow: [
              '',
              'إجمالي الوارد',
              '',
              '',
              '',
              '',
              '${nf(c.incomingTotal)} ${Fuel.unit}',
              '',
            ],
          ),
        ],
      );

  Widget _issuedTable(FuelDailyCamp c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FuelPaperHeading('المنصرف'),
          const SizedBox(height: 6),
          FuelPaperTable(
            headers: const [
              'م',
              'السند',
              'الجهة المستفيدة',
              'نوع الوسيلة',
              'جهة الأمر',
              'الغرض',
              'الصنف',
              'الكمية',
              'ملاحظة',
            ],
            flex: const [1, 3, 6, 3, 4, 4, 2, 3, 4],
            emptyText: 'لا يوجد منصرف',
            rows: [
              for (var i = 0; i < c.issued.length; i++)
                [
                  '${i + 1}',
                  c.issued[i].refNo,
                  c.issued[i].party,
                  c.issued[i].vehicleType,
                  c.issued[i].authority,
                  c.issued[i].purpose,
                  FuelType.label(c.issued[i].fuelType),
                  nf(c.issued[i].qty),
                  c.issued[i].notes,
                ],
            ],
            totalRow: [
              '',
              'إجمالي المنصرف',
              '',
              '',
              '',
              '',
              '',
              '${nf(c.issuedTotal)} ${Fuel.unit}',
              '',
            ],
          ),
        ],
      );

  Widget _transferTable(FuelDailyCamp c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FuelPaperHeading('التحويل'),
          const SizedBox(height: 6),
          FuelPaperTable(
            headers: const [
              'م',
              'السند',
              'الاتجاه',
              'الطرف الآخر',
              'الوسيلة',
              'السائق',
              'الصنف',
              'الكمية',
            ],
            flex: const [1, 3, 3, 6, 3, 3, 2, 3],
            rows: [
              for (var i = 0; i < c.transfers.length; i++)
                [
                  '${i + 1}',
                  c.transfers[i].refNo,
                  c.transfers[i].outbound ? 'محوَّل منه' : 'محوَّل إليه',
                  c.transfers[i].outbound
                      ? 'إلى ${c.transfers[i].party}'
                      : 'من ${c.transfers[i].party}',
                  c.transfers[i].vehicleType,
                  c.transfers[i].driver,
                  FuelType.label(c.transfers[i].fuelType),
                  nf(c.transfers[i].qty),
                ],
            ],
            totalRow: [
              '',
              'إجمالي التحويل',
              '',
              '',
              '',
              '',
              '',
              '${nf(c.transferTotal)} ${Fuel.unit}',
            ],
          ),
        ],
      );
}
