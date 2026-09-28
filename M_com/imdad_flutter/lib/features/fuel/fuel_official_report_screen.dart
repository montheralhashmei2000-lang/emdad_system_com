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
import '../../domain/fuel_report.dart';
import 'fuel_report_docs.dart';

/// التقارير الرسمية — البرقية اليومية والأسبوعية والشهرية.
///
/// **الشاشة لوحةٌ والورقة ورقة.** كانت الشاشة تحاكي الورق بلونه وحدوده فخرجت
/// وحدها عن لوحة القسم؛ وهي تُقرأ على الشاشة أضعاف ما تُطابَق بالورق. فصارت
/// بجداول النظام وألوانه، والمطبوع يبقى البرقية نفسها حرفًا بحرف.
class FuelOfficialReportScreen extends StatefulWidget {
  const FuelOfficialReportScreen({super.key});

  @override
  State<FuelOfficialReportScreen> createState() =>
      _FuelOfficialReportScreenState();
}

class _FuelOfficialReportScreenState extends State<FuelOfficialReportScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelIssue> _issues = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelTransfer> _transfers = const [];
  FuelSettingsRow? _settings;

  String _period = FuelReportPeriod.daily;
  late String _date = _iso(DateTime.now());
  late String _from = _iso(DateTime.now().subtract(const Duration(days: 6)));
  late String _to = _iso(DateTime.now());
  String _warehouse = '';
  bool _loading = true;

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final warehouses = await _repo.warehouses(onlyActive: true);
    final issues = await _repo.issues();
    final supplies = await _repo.supplies();
    final transfers = await _repo.transfers();
    final settings = await _repo.settings();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _issues = issues;
      _supplies = supplies;
      _transfers = transfers;
      _settings = settings;
      _loading = false;
    });
  }

  FuelDateRange get _range =>
      FuelDateRange.of(_period, date: _date, from: _from, to: _to);

  FuelOfficialReport get _report {
    final names = _warehouse.isEmpty
        ? [for (final w in _warehouses) w.name]
        : <String>[_warehouse];
    return FuelReportBuilder.build(
      period: _period,
      range: _range,
      warehouses: names,
      issues: [
        for (final i in _issues)
          FuelReportIssue(
            date: i.date,
            fuelType: i.fuelType,
            warehouse: i.warehouse,
            qty: i.quantityLiters,
            beneficiary: i.beneficiaryName,
            driver: i.driverName,
            vehicleType: i.vehicleType,
            orderAuthority: i.orderAuthority,
            purpose: i.purpose,
            justification: i.justification,
            notes: i.notes,
            source: i.source,
          ),
      ],
      supplies: [
        for (final s in _supplies)
          FuelReportSupply(
            date: s.date,
            fuelType: s.fuelType,
            warehouse: s.warehouse,
            qty: s.quantityLiters,
            supplier: s.supplierName,
            vehicleType: s.transportVehicleType,
            notes: s.notes,
          ),
      ],
      transfers: [
        for (final t in _transfers)
          FuelReportTransfer(
            date: t.date,
            fuelType: t.fuelType,
            fromWarehouse: t.fromWarehouse,
            toWarehouse: t.toWarehouse,
            qty: t.quantityLiters,
            driver: t.driverName,
            vehicleType: t.transportVehicleType,
            notes: t.notes,
          ),
      ],
    );
  }

  Future<void> _print() async {
    final settings = _settings;
    if (settings == null) return;
    await FuelReportDocs.printOfficial(_db,
        report: _report, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'التقارير الرسمية', icon: 'chart'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final r = _report;

    return ImdPage(children: [
      ImdPageTitle(
        title: 'التقارير الرسمية',
        icon: 'chart',
        subtitle: 'تقرير الحركة اليومية والأسبوعية والشهرية لجميع المعسكرات '
            '— بنفس نموذج البرقية',
        trailing: ImdButton(
            label: 'طباعة التقرير', icon: 'printer', onPressed: _print),
      ),
      ImdICard(
        title: 'نوع التقرير والفترة',
        icon: 'calendar',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdPillTabs<String>(
            value: _period,
            onChanged: (v) => setState(() => _period = v),
            tabs: [
              for (final p in FuelReportPeriod.all)
                ImdTab(p, FuelReportPeriod.label(p)),
            ],
          ),
          const SizedBox(height: 12),
          ImdF2(children: [
            if (_period == FuelReportPeriod.custom) ...[
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
            ] else
              ImdLabeled(
                FuelReportPeriod.dateLabel(_period),
                ImdDateField(
                    value: _date, onChanged: (v) => setState(() => _date = v)),
                size: 11,
              ),
            ImdLabeled(
              'المعسكر / المخزن',
              ImdSelect<String>(
                items: [
                  ('', 'جميع المعسكرات والمخازن'),
                  for (final w in _warehouses) (w.name, w.name),
                ],
                value: _warehouse,
                onChanged: (v) => setState(() => _warehouse = v ?? ''),
              ),
              size: 11,
            ),
          ]),
        ]),
      ),
      ImdKpis(children: [
        ImdKpi(
            label: 'وارد توريدًا',
            value: '${nf(r.grandSupplied)} ${Fuel.unit}'),
        ImdKpi(label: 'صادر بترول', value: nf(r.grandPetrol)),
        ImdKpi(label: 'صادر ديزل', value: nf(r.grandDiesel)),
        ImdKpi(
          label: 'محوَّل بين المعسكرات',
          value: nf(r.grandTransferredOut),
          extra: r.grandTransferredOut == 0
              ? null
              : const ImdChip('لا يزيد وقود الفرقة', tone: ImdTone.off),
        ),
        ImdKpi(
            label: 'إجمالي الصادر',
            value: '${nf(r.grandTotal + r.grandTransferredOut)} ${Fuel.unit}'),
      ]),
      ImdNote(
        'العنوان المطبوع: **${r.title} ${r.range.label} م**. '
        'والترويسة والشعار والتواقيع تُؤخذ من «إعدادات المحروقات» وتظهر في '
        'الورقة المطبوعة.',
      ),
      const SizedBox(height: 16),
      if (r.isEmpty)
        const ImdEmptyBox('لا حركة في هذه الفترة')
      else
        for (final s in r.sections) _camp(s, r.range.label),
      if (r.showSummary) _summary(r),
    ]);
  }

  // ───────────────────────── المعسكر

  Widget _camp(FuelCampSection s, String span) {
    final c = context.imd;
    return ImdPanel(
      title: 'محطة الوقود في ${s.warehouse}',
      icon: 'package',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          ImdChip('وارد توريدًا ${nf(s.suppliedTotal)}',
              tone: s.suppliedTotal == 0 ? ImdTone.off : ImdTone.ok),
          ImdChip('وارد تحويلًا ${nf(s.transferredInTotal)}',
              tone: s.transferredInTotal == 0 ? ImdTone.off : ImdTone.info),
          ImdChip('صادر ${nf(s.issuedTotal)}',
              tone: s.issuedTotal == 0 ? ImdTone.off : ImdTone.code),
          ImdChip('محوَّل منه ${nf(s.transferredOutTotal)}',
              tone: s.transferredOutTotal == 0 ? ImdTone.off : ImdTone.info),
        ]),
        _sub('الوارد', c),
        _incomingTable(s),
        _sub('الصادر من مادة البترول — المنصرف $span م', c),
        _issueTable(s.petrol, s.petrolTotal),
        _sub('الصادر من مادة الديزل — المنصرف $span م', c),
        _issueTable(s.diesel, s.dieselTotal),
        // التحويل يُعرض إن وُجد فقط — جدولٌ فارغ يشغل الشاشة بلا خبر.
        if (s.outgoing.isNotEmpty) ...[
          _sub('المحوَّل إلى المعسكرات', c),
          _outgoingTable(s),
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

  Widget _incomingTable(FuelCampSection s) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا يوجد وارد',
      minWidth: 820,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('جهة التوريد / المصدر'),
        ImdCol('نوع الحركة'),
        ImdCol('الوسيلة'),
        ImdCol('الصنف'),
        ImdCol('الكمية', numeric: true),
      ],
      cards: true,
      rows: [
        for (final r in s.incoming)
          [
            Text('${r.n}',
                textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
            Text(r.supplier,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            // **الوارد نوعان**: توريدٌ يزيد وقود الفرقة، وتحويلٌ ينقله فحسب.
            r.isTransfer
                ? const ImdChip('تحويل داخلي', tone: ImdTone.info)
                : const ImdChip('توريد', tone: ImdTone.ok),
            Text(r.vehicleType),
            ImdChip(FuelType.label(r.fuelType),
                tone:
                    r.fuelType == FuelType.diesel ? ImdTone.code : ImdTone.info),
            Text(nf(r.qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: s.incoming.isEmpty
          ? null
          : [
              const Text(''),
              const Text('الإجمالي',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text('توريد ${nf(s.suppliedTotal)}',
                  style: TextStyle(color: c.muted, fontSize: 12)),
              Text('تحويل ${nf(s.transferredInTotal)}',
                  style: TextStyle(color: c.muted, fontSize: 12)),
              const Text(''),
              Text('${nf(s.incomingTotal)} ${Fuel.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
    );
  }

  Widget _issueTable(List<FuelOfficialIssueRow> rows, double total) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا توجد حركات',
      minWidth: 940,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('الجهة المستفيدة'),
        ImdCol('نوع الوسيلة'),
        ImdCol('جهة الأمر'),
        ImdCol('الغرض'),
        ImdCol('ملاحظة'),
        ImdCol('الكمية', numeric: true),
      ],
      cards: true,
      rows: [
        for (final r in rows)
          [
            Text('${r.n}',
                textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
            Text(r.beneficiary,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(r.vehicleType),
            Text(r.authority),
            Text(r.purpose.isEmpty ? '—' : r.purpose,
                style: TextStyle(color: c.muted)),
            Text(r.notes.isEmpty ? '—' : r.notes,
                style: TextStyle(color: c.muted)),
            Text(nf(r.qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: rows.isEmpty
          ? null
          : [
              const Text(''),
              const Text('الإجمالي',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(''),
              const Text(''),
              const Text(''),
              const Text(''),
              Text('${nf(total)} ${Fuel.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
    );
  }

  Widget _outgoingTable(FuelCampSection s) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا تحويلات',
      minWidth: 860,
      columns: const [
        ImdCol('م', center: true),
        ImdCol('إلى معسكر'),
        ImdCol('الصنف'),
        ImdCol('الوسيلة'),
        ImdCol('السائق'),
        ImdCol('ملاحظة'),
        ImdCol('الكمية', numeric: true),
      ],
      cards: true,
      rows: [
        for (final r in s.outgoing)
          [
            Text('${r.n}',
                textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
            Text(r.toCamp, style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdChip(FuelType.label(r.fuelType),
                tone:
                    r.fuelType == FuelType.diesel ? ImdTone.code : ImdTone.info),
            Text(r.vehicleType),
            Text(r.driver),
            Text(r.notes.isEmpty ? '—' : r.notes,
                style: TextStyle(color: c.muted)),
            Text(nf(r.qty),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
      ],
      footer: [
        const Text(''),
        const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text(''),
        const Text(''),
        const Text(''),
        const Text(''),
        Text('${nf(s.transferredOutTotal)} ${Fuel.unit}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ───────────────────────── الخلاصة

  Widget _summary(FuelOfficialReport r) => ImdPanel(
        title: 'خلاصة جميع المعسكرات',
        icon: 'scale',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdTable(
            empty: 'لا معسكرات',
            minWidth: 940,
            columns: const [
              ImdCol('المعسكر'),
              ImdCol('وارد توريدًا', numeric: true),
              ImdCol('وارد تحويلًا', numeric: true),
              ImdCol('صادر بترول', numeric: true),
              ImdCol('صادر ديزل', numeric: true),
              ImdCol('محوَّل إلى معسكر', numeric: true),
              ImdCol('إجمالي الصادر', numeric: true),
            ],
            cards: true,
            rows: [
              for (final s in r.sections)
                [
                  Text(s.warehouse,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(nf(s.suppliedTotal)),
                  Text(nf(s.transferredInTotal)),
                  Text(nf(s.petrolTotal)),
                  Text(nf(s.dieselTotal)),
                  Text(nf(s.transferredOutTotal)),
                  Text('${nf(s.outTotal)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
            ],
            footer: [
              const Text('الإجمالي',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text(nf(r.grandSupplied),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(nf(r.grandTransferredIn),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(nf(r.grandPetrol),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(nf(r.grandDiesel),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(nf(r.grandTransferredOut),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${nf(r.grandTotal + r.grandTransferredOut)} ${Fuel.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ImdNote(
            'المحوَّل بين المعسكرات يظهر واردًا في معسكرٍ وصادرًا في آخر، فلا '
            'يزيد وقود الفرقة ولا ينقصه — والداخل توريدًا '
            '**${nf(r.grandSupplied)} ${Fuel.unit}**، والخارج صرفًا '
            '**${nf(r.grandTotal)} ${Fuel.unit}**.',
          ),
        ]),
      );
}
