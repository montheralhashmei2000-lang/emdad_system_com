import '../../core/security/perm.dart';
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
import '../../domain/fuel_daily_report.dart';
import '../../domain/fuel_report.dart';
import 'fuel_report_docs.dart';

/// تقرير الحركة اليومية للمحروقات — الدفتر اليومي بجميع معسكراته.
///
/// ملخّصٌ أولًا يُقرأ في نظرة، ثم تفصيلُ كل معسكر في ثلاثة جداول — الوارد،
/// فالمنصرف، فالتحويل إن وُجد — ولكلٍّ إجماليه في ذيله.
///
/// **الشاشة لوحةٌ والورقة ورقة**: هنا جداول النظام وألوانه كبقية تقارير
/// القسم، وفي الطابعة البرقية بترويستها وتواقيعها.
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
    if (!Perm.of(context).guard(context, 'fuelReports', 'print')) return;
    final settings = _settings;
    if (settings == null) return;
    await FuelReportDocs.printDaily(_db,
        report: _report, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تقرير الحركة اليومية للمحروقات', icon: 'calendar'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final r = _report;

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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      ImdKpis(children: [
        ImdKpi(
          label: 'رصيد أول المدى',
          value: '${nf(_openingTotal(r))} ${Fuel.unit}',
          extra: const ImdChip('مُرحَّل', tone: ImdTone.off),
        ),
        ImdKpi(label: 'الوارد', value: nf(r.totalOf((b) => b.incoming))),
        ImdKpi(label: 'المنصرف', value: nf(r.totalOf((b) => b.issued))),
        ImdKpi(
          label: 'المحوَّل',
          value: nf(r.totalOf((b) => b.transferOut)),
          extra: r.totalOf((b) => b.transferOut) == 0
              ? null
              : const ImdChip('بين المعسكرات', tone: ImdTone.info),
        ),
        ImdKpi(
            label: 'رصيد آخر المدى',
            value: '${nf(_closingTotal(r))} ${Fuel.unit}'),
      ]),
      _summary(r),
      if (r.isEmpty)
        const ImdEmptyBox('لا حركة في هذا المدى')
      else
        for (final day in r.days) ..._day(r, day),
    ]);
  }

  /// أرصدة أول يومٍ وآخره — لا مجموع الأعمدة كلها، فذاك يجمع اليوم بتاليه.
  double _openingTotal(FuelDailyReport r) => r.days.isEmpty
      ? 0
      : r.days.first.balances.fold<double>(0, (t, b) => t + b.opening);

  double _closingTotal(FuelDailyReport r) => r.days.isEmpty
      ? 0
      : r.days.last.balances.fold<double>(0, (t, b) => t + b.closing);

  static String _signed(double v) {
    if (v == 0) return '—';
    return v > 0 ? '+${nf(v)}' : '−${nf(-v)}';
  }

  // ───────────────────────── الملخّص

  /// **الملخّص قبل التفصيل.** من يقرأ يسأل أولًا «كم بقي وأين»، ثم يفتّش عن
  /// السند إن استغرب رقمًا — فالإجماليات في الصدر والتفاصيل بعدها.
  Widget _summary(FuelDailyReport r) {
    final c = context.imd;
    final adj = r.hasAdjustments;
    final many = r.days.length > 1;
    return ImdPanel(
      title: 'ملخّص الحركة اليومية',
      icon: 'scale',
      child: ImdTable(
        empty: 'لا معسكرات',
        minWidth: adj ? 1040 : 940,
        columns: [
          if (many) const ImdCol('اليوم'),
          const ImdCol('المعسكر / المحطة'),
          const ImdCol('الوقود'),
          const ImdCol('الافتتاحي / المتبقي من السابق', numeric: true),
          const ImdCol('الوارد', numeric: true),
          const ImdCol('المنصرف', numeric: true),
          const ImdCol('التحويل', numeric: true),
          if (adj) const ImdCol('تسوية جرد', numeric: true),
          const ImdCol('المتبقي', numeric: true),
        ],
        pageSize: 50,
        rows: [
          for (final day in r.days)
            for (final b in day.balances)
              [
                if (many) Text(arDigits(day.date)),
                Text(b.warehouse,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdChip(FuelType.label(b.fuelType),
                    tone: b.fuelType == FuelType.diesel
                        ? ImdTone.code
                        : ImdTone.info),
                Text(nf(b.opening), style: TextStyle(color: c.muted)),
                Text(b.incoming == 0 ? '—' : nf(b.incoming),
                    style: TextStyle(
                        color: b.incoming == 0 ? c.muted : c.success)),
                Text(b.issued == 0 ? '—' : nf(b.issued),
                    style:
                        TextStyle(color: b.issued == 0 ? c.muted : c.danger)),
                Text(_signed(b.transferNet),
                    style: TextStyle(
                        color: b.transferNet == 0 ? c.muted : c.info)),
                if (adj)
                  Text(_signed(b.adjustment),
                      style: TextStyle(
                          color: b.adjustment == 0 ? c.muted : c.warn)),
                Text('${nf(b.closing)} ${Fuel.unit}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: b.closing < 0 ? c.danger : c.text)),
              ],
        ],
        footer: [
          if (many) const Text(''),
          const Text('الإجمالي',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const Text(''),
          Text(nf(r.totalOf((b) => b.opening)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(nf(r.totalOf((b) => b.incoming)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(nf(r.totalOf((b) => b.issued)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(_signed(r.totalOf((b) => b.transferNet)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (adj)
            Text(_signed(r.totalOf((b) => b.adjustment)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(nf(r.totalOf((b) => b.closing)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
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
    if (camps.isEmpty) return const [];
    return [
      if (many)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            ImdChip('حركة يوم ${arDigits(day.date)}', tone: ImdTone.info),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: context.imd.line, height: 1)),
          ]),
        ),
      for (var i = 0; i < camps.length; i++) _camp(camps[i], i),
    ];
  }

  Widget _camp(FuelDailyCamp c, int index) {
    final t = context.imd;
    return ImdPanel(
      title: '${_ordinal(index)}: الحركة اليومية بـ${c.warehouse}',
      icon: 'package',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          for (final f in FuelType.all)
            ImdChip(
              '${FuelType.label(f)}: أول اليوم ${nf(c.openingOf(f))} ← '
              'آخره ${nf(c.closingOf(f))}',
              tone: f == FuelType.diesel ? ImdTone.code : ImdTone.info,
            ),
        ]),
        if (_kinds.contains(FuelMoveKind.incoming)) ...[
          _sub('الوارد', t),
          _incomingTable(c),
        ],
        if (_kinds.contains(FuelMoveKind.issued)) ...[
          _sub('المنصرف', t),
          _issuedTable(c),
        ],
        // التحويل يُضاف إن وُجد فقط.
        if (_kinds.contains(FuelMoveKind.transfer) && c.hasTransfers) ...[
          _sub('التحويل', t),
          _transferTable(c),
        ],
      ]),
    );
  }

  Widget _sub(String text, ImdColors c) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: c.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _incomingTable(FuelDailyCamp c) {
    final t = context.imd;
    return ImdTable(
      empty: 'لا يوجد وارد',
      minWidth: 900,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('السند'),
        ImdCol('جهة التوريد'),
        ImdCol('الوسيلة'),
        ImdCol('السائق'),
        ImdCol('الصنف'),
        ImdCol('ملاحظة'),
        ImdCol('الكمية', numeric: true),
      ],
      pageSize: 50,
      rows: [
        for (var i = 0; i < c.incoming.length; i++)
          [
            Text('${i + 1}',
                textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
            Text(c.incoming[i].refNo,
                style: TextStyle(color: t.muted, fontSize: 12.5)),
            Text(c.incoming[i].party,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(c.incoming[i].vehicleType),
            Text(c.incoming[i].driver),
            ImdChip(FuelType.label(c.incoming[i].fuelType),
                tone: c.incoming[i].fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(c.incoming[i].notes.isEmpty ? '—' : c.incoming[i].notes,
                style: TextStyle(color: t.muted)),
            Text(nf(c.incoming[i].qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: c.incoming.isEmpty
          ? null
          : [
              const Text(''),
              const Text('إجمالي الوارد',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              Text('${nf(c.incomingTotal)} ${Fuel.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
    );
  }

  Widget _issuedTable(FuelDailyCamp c) {
    final t = context.imd;
    return ImdTable(
      empty: 'لا يوجد منصرف',
      minWidth: 1020,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('السند'),
        ImdCol('الجهة المستفيدة'),
        ImdCol('نوع الوسيلة'),
        ImdCol('جهة الأمر'),
        ImdCol('الغرض'),
        ImdCol('الصنف'),
        ImdCol('ملاحظة'),
        ImdCol('الكمية', numeric: true),
      ],
      pageSize: 50,
      rows: [
        for (var i = 0; i < c.issued.length; i++)
          [
            Text('${i + 1}',
                textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
            Text(c.issued[i].refNo,
                style: TextStyle(color: t.muted, fontSize: 12.5)),
            Text(c.issued[i].party,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(c.issued[i].vehicleType),
            Text(c.issued[i].authority),
            Text(c.issued[i].purpose.isEmpty ? '—' : c.issued[i].purpose,
                style: TextStyle(color: t.muted)),
            ImdChip(FuelType.label(c.issued[i].fuelType),
                tone: c.issued[i].fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(c.issued[i].notes.isEmpty ? '—' : c.issued[i].notes,
                style: TextStyle(color: t.muted)),
            Text(nf(c.issued[i].qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: c.issued.isEmpty
          ? null
          : [
              const Text(''),
              const Text('إجمالي المنصرف',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              Text('${nf(c.issuedTotal)} ${Fuel.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
    );
  }

  Widget _transferTable(FuelDailyCamp c) {
    final t = context.imd;
    return ImdTable(
      empty: 'لا تحويلات',
      minWidth: 900,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('السند'),
        ImdCol('الاتجاه'),
        ImdCol('الطرف الآخر'),
        ImdCol('الوسيلة'),
        ImdCol('السائق'),
        ImdCol('الصنف'),
        ImdCol('الكمية', numeric: true),
      ],
      pageSize: 50,
      rows: [
        for (var i = 0; i < c.transfers.length; i++)
          [
            Text('${i + 1}',
                textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
            Text(c.transfers[i].refNo,
                style: TextStyle(color: t.muted, fontSize: 12.5)),
            c.transfers[i].outbound
                ? const ImdChip('محوَّل منه', tone: ImdTone.pend)
                : const ImdChip('محوَّل إليه', tone: ImdTone.ok),
            Text(
                c.transfers[i].outbound
                    ? 'إلى ${c.transfers[i].party}'
                    : 'من ${c.transfers[i].party}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(c.transfers[i].vehicleType),
            Text(c.transfers[i].driver),
            ImdChip(FuelType.label(c.transfers[i].fuelType),
                tone: c.transfers[i].fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(nf(c.transfers[i].qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: [
        const Text(''),
        const Text('إجمالي التحويل',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const Text(''),
        const Text(''),
        const Text(''),
        const Text(''),
        const Text(''),
        Text('${nf(c.transferTotal)} ${Fuel.unit}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
