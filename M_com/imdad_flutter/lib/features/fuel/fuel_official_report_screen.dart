import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/fuel.dart';
import '../../domain/fuel_report.dart';
import 'fuel_official_pdf.dart';

/// التقارير الرسمية — البرقية اليومية والأسبوعية والشهرية.
///
/// **الشاشة ورقةٌ لا لوحة.** يراها الضابط كما ستخرج من الطابعة: الترويسة
/// نفسها، والجداول نفسها، والتواقيع في مواضعها — فلا يُطبع شيءٌ يفاجئه.
/// ولذلك تخرج هذه الشاشة وحدها عن ألوان القسم الداكنة إلى بياض الورق.
class FuelOfficialReportScreen extends StatefulWidget {
  const FuelOfficialReportScreen({super.key});

  @override
  State<FuelOfficialReportScreen> createState() =>
      _FuelOfficialReportScreenState();
}

class _FuelOfficialReportScreenState extends State<FuelOfficialReportScreen> {
  // ألوان الورقة ثابتةٌ لا تتبع السمة: هذه محاكاةُ ورقٍ مطبوع، وورقُ الوحدة
  // ليس داكنًا ولو كانت الشاشة داكنة.
  static const Color _paper = Color(0xFFF7F1E6);
  static const Color _paperLine = Color(0xFFB9AC91);
  static const Color _paperHead = Color(0xFFEDE4D2);
  static const Color _paperTotal = Color(0xFFE3C75B);
  static const Color _paperTitle = Color(0xFF9B2C1F);
  static const Color _paperText = Color(0xFF2B2620);
  static const Color _paperMuted = Color(0xFF6B6455);

  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelIssue> _issues = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelTransfer> _transfers = const [];
  FuelSettingsRow? _settings;
  Uint8List? _logo;

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
    // الشعار نفسه الذي سيُطبع، فلا تختلف المعاينة عن الورقة.
    final logo = await FuelOfficialPdf.fuelLogo(_db);
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _issues = issues;
      _supplies = supplies;
      _transfers = transfers;
      _settings = settings;
      _logo = logo;
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
    await FuelOfficialPdf.printReport(_db, report: _report, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'التقارير الرسمية', icon: 'chart'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
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
      _sheet(),
    ]);
  }

  // ───────────────────────── الورقة

  Widget _sheet() {
    final report = _report;
    final s = _settings!;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _paperLine),
        borderRadius: BorderRadius.circular(10),
      ),
      // الورقة لا تضيق عن عرضٍ تُقرأ فيه جداولها؛ فإن ضاقت الشاشة زحفت
      // أفقيًّا كما يُزحلق الورق على الطاولة، ولا تُكسر الأعمدة.
      child: LayoutBuilder(builder: (context, box) {
        final width =
            box.maxWidth.isFinite && box.maxWidth > 900 ? box.maxWidth : 900.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(18),
            // **خطّ الورقة خطُّ النظام.** `DefaultTextStyle` يستبدل النمط
            // كله، فنمطٌ مكتوبٌ من الصفر يسقط عائلة الخط ويطبع البرقية
            // بخطٍّ لاتينيّ لا يصل الحروف.
              child: DefaultTextStyle(
                style: (Theme.of(context).textTheme.bodyMedium ??
                        const TextStyle())
                    .copyWith(
                        color: _paperText, fontSize: 12, height: 1.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _letterhead(s),
                    const SizedBox(height: 12),
                    _addressee(s, report),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '${report.title} ${report.range.label} م',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _paperTitle,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final c in report.sections)
                      _camp(c, report.range.label, report.showSummary),
                    if (report.showSummary) _summary(report),
                    const SizedBox(height: 34),
                    _signatures(s),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _letterhead(FuelSettingsRow s) {
    final lines = [s.parentOrg, s.agencyTitle, s.commandTitle, s.branchTitle]
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final logo = _logo;
    final seal = s.sealLines
        .split(RegExp(r'[\n·،]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lines.isEmpty)
                const Text('— لم تُضبط ترويسة التقارير بعد —',
                    style: TextStyle(color: _paperMuted, fontSize: 11)),
              for (final l in lines)
                Text(l,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
        ),
        if (logo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Image.memory(logo, width: 96, height: 96),
          )
        else if (seal.isNotEmpty)
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _paperText, width: 3),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final l in seal)
                  Text(l,
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        const Expanded(child: SizedBox()),
      ],
    );
  }

  Widget _addressee(FuelSettingsRow s, FuelOfficialReport r) => Row(
        children: [
          Expanded(child: _box('إلى : ${s.branchTitle}')),
          Expanded(child: _box('تاريخها: ${r.range.label}')),
        ],
      );

  Widget _box(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: _paperLine)),
        child: Text(text, style: const TextStyle(fontSize: 11.5)),
      );

  Widget _camp(FuelCampSection c, String span, bool showCamp) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          if (showCamp)
            Center(
              child: Text('محطة الوقود في ${c.warehouse}',
                  style: const TextStyle(
                      color: _paperTitle,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 10),
          if (c.incoming.isEmpty)
            const _Heading('لا يوجد وارد')
          else ...[
            const _Heading('الوارد'),
            const SizedBox(height: 6),
            _table(
              headers: const [
                'م',
                'جهة التوريد / المصدر',
                'الباب',
                'الوسيلة',
                'الصنف',
                'الكمية',
              ],
              flex: const [1, 6, 3, 3, 2, 2],
              rows: [
                for (final r in c.incoming)
                  [
                    '${r.n}',
                    r.supplier,
                    r.isTransfer ? 'تحويل داخلي' : 'توريد',
                    r.vehicleType,
                    FuelType.label(r.fuelType),
                    nf(r.qty),
                  ],
              ],
              totalRow: [
                '',
                'الإجمالي',
                'توريد ${nf(c.suppliedTotal)}',
                'تحويل ${nf(c.transferredInTotal)}',
                '',
                '${nf(c.incomingTotal)} ${Fuel.unit}',
              ],
            ),
          ],
          const SizedBox(height: 14),
          _issueTable('الصادر من مادة البترول — المنصرف $span م', c.petrol,
              c.petrolTotal),
          const SizedBox(height: 14),
          _issueTable('الصادر من مادة الديزل — المنصرف $span م', c.diesel,
              c.dieselTotal),
          if (c.outgoing.isNotEmpty) ...[
            const SizedBox(height: 14),
            _outgoingTable(c),
          ],
        ],
      );

  /// المحوَّل إلى المعسكرات الشقيقة — خرج من الخزّان ولم يُصرف لجهة.
  Widget _outgoingTable(FuelCampSection c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('المحوَّل إلى المعسكرات'),
          const SizedBox(height: 6),
          _table(
            headers: const [
              'م',
              'إلى معسكر',
              'الصنف',
              'الوسيلة',
              'السائق',
              'الكمية',
              'ملاحظة',
            ],
            flex: const [1, 6, 2, 3, 3, 2, 3],
            rows: [
              for (final r in c.outgoing)
                [
                  '${r.n}',
                  r.toCamp,
                  FuelType.label(r.fuelType),
                  r.vehicleType,
                  r.driver,
                  nf(r.qty),
                  r.notes,
                ],
            ],
            totalRow: [
              '',
              'الإجمالي',
              '',
              '',
              '',
              '${nf(c.transferredOutTotal)} ${Fuel.unit}',
              '',
            ],
          ),
        ],
      );

  Widget _issueTable(
          String title, List<FuelOfficialIssueRow> rows, double total) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Heading(title),
        const SizedBox(height: 6),
        _table(
          headers: const [
            'م',
            'الجهة المستفيدة',
            'نوع الوسيلة',
            'الكمية',
            'جهة الأمر',
            'الغرض',
            'ملاحظة',
          ],
          flex: const [1, 6, 3, 2, 3, 3, 2],
          rows: [
            for (final r in rows)
              [
                '${r.n}',
                r.beneficiary,
                r.vehicleType,
                nf(r.qty),
                r.authority,
                r.purpose,
                r.notes,
              ],
          ],
          emptyText: 'لا توجد حركات',
          // الإجمالي في خانة الكمية نفسها، لا في آخر السطر: العين تنزل
          // بالعمود فتقرأ المجموع تحت ما جمعته.
          totalRow: [
            '',
            'الإجمالي',
            '',
            '${nf(total)} ${Fuel.unit}',
            '',
            '',
            ''
          ],
        ),
      ]);

  Widget _summary(FuelOfficialReport r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          const _Heading('خلاصة جميع المعسكرات'),
          const SizedBox(height: 6),
          _table(
            headers: const [
              'المعسكر',
              'وارد توريدًا',
              'وارد تحويلًا',
              'صادر بترول',
              'صادر ديزل',
              'محوَّل إلى معسكر',
              'إجمالي الصادر',
            ],
            flex: const [5, 3, 3, 3, 3, 3, 3],
            rows: [
              for (final s in r.sections)
                [
                  s.warehouse,
                  nf(s.suppliedTotal),
                  nf(s.transferredInTotal),
                  nf(s.petrolTotal),
                  nf(s.dieselTotal),
                  nf(s.transferredOutTotal),
                  nf(s.outTotal),
                ],
            ],
            totalRow: [
              'الإجمالي',
              nf(r.grandSupplied),
              nf(r.grandTransferredIn),
              nf(r.grandPetrol),
              nf(r.grandDiesel),
              nf(r.grandTransferredOut),
              nf(r.grandTotal + r.grandTransferredOut),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'المحوَّل بين المعسكرات يظهر واردًا في معسكرٍ وصادرًا في آخر، فلا '
            'يزيد وقود الفرقة ولا ينقصه — والداخل توريدًا '
            '${nf(r.grandSupplied)} ${Fuel.unit}، والخارج صرفًا '
            '${nf(r.grandTotal)} ${Fuel.unit}.',
            style: const TextStyle(fontSize: 10.5, color: _paperMuted),
          ),
        ],
      );

  Widget _signatures(FuelSettingsRow s) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sign('مسؤول محروقات المعسكر', s.signOfficer),
          _sign('ركن إمداد الفرقة الأولى/', s.signSupply),
          _sign('رئيس شعبة الإمداد والتموين /', s.signChief),
        ],
      );

  Widget _sign(String role, String name) => Expanded(
        child: Column(children: [
          Text(role,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(name.trim().isEmpty ? '—' : name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );

  /// جدول الورقة: شبكةٌ بحدودٍ كاملة كما يُرسم في البرقية.
  Widget _table({
    required List<String> headers,
    required List<int> flex,
    required List<List<String>> rows,
    List<String>? totalRow,
    String emptyText = '',
  }) {
    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < flex.length; i++)
        i: FlexColumnWidth(flex[i].toDouble()),
    };
    return Table(
      columnWidths: widths,
      border: TableBorder.all(color: _paperLine, width: 0.8),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _paperHead),
          children: [for (final h in headers) _cell(h, bold: true)],
        ),
        if (rows.isEmpty && emptyText.isNotEmpty)
          TableRow(children: [
            for (var i = 0; i < headers.length; i++)
              _cell(i == 1 ? emptyText : ''),
          ]),
        for (final r in rows) TableRow(children: [for (final v in r) _cell(v)]),
        if (totalRow != null)
          TableRow(
            decoration: const BoxDecoration(color: _paperTotal),
            children: [for (final v in totalRow) _cell(v, bold: true)],
          ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Text(
          text.isEmpty ? '' : arDigits(text),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: _paperText,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
}

/// عنوانٌ أحمر فوق كل جدولٍ في البرقية.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF9B2C1F),
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
      );
}
