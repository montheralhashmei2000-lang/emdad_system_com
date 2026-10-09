import '../../core/security/perm.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/fuel.dart';
import 'fuel_print.dart';
import '../../domain/print_forms.dart';

/// تقرير استهلاك المحروقات — من يشرب، وكم، وبأي نسبة.
///
/// **التجميع هو التقرير.** قائمةُ سنداتٍ بالتاريخ تُقرأ ولا يُخرج منها قرار؛
/// أما «هذه المركبة أخذت ثلث الديزل» فقرارٌ بنفسها.
class FuelConsumptionScreen extends StatefulWidget {
  const FuelConsumptionScreen({super.key});

  @override
  State<FuelConsumptionScreen> createState() => _FuelConsumptionScreenState();
}

class _FuelConsumptionScreenState extends State<FuelConsumptionScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelConsumptionMove> _moves = const [];
  List<FuelWarehouse> _warehouses = const [];
  List<FuelUnit> _units = const [];
  List<FuelIssue> _issues = const [];
  List<FuelAllocationRow> _allocations = const [];
  String _unit = '';

  late String _from;
  String _to = '';
  String _warehouse = '';
  String _fuelType = '';
  String _groupBy = FuelGroupBy.unit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = _iso(DateTime(now.year, now.month, 1));
    _to = _iso(now);
    _load();
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    final issues = await _repo.issues();
    final warehouses = await _repo.warehouses();
    final units = await _repo.units();
    final allocations = await _repo.allocations();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _units = units;
      _issues = issues;
      _allocations = allocations;
      _moves = [
        for (final i in issues)
          FuelConsumptionMove(
            date: i.date,
            fuelType: i.fuelType,
            warehouse: i.warehouse,
            liters: i.quantityLiters,
            beneficiary: i.beneficiaryName,
            chassisNo: i.chassisNo,
            vehicleType: i.vehicleType,
          ),
      ];
      _loading = false;
    });
  }

  List<FuelConsumptionMove> get _filtered {
    final base = FuelConsumption.filter(
      _moves,
      from: _from,
      to: _to,
      warehouse: _warehouse,
      fuelType: _fuelType,
    );
    if (_unit.isEmpty) return base;
    return base.where((m) => m.beneficiary == _unit).toList();
  }

  /// السندات المطابقة للمرشّحات — لتُطبع فُرادى من الجدول.
  List<FuelIssue> get _filteredIssues => _issues.where((i) {
        if (_from.isNotEmpty && i.date.compareTo(_from) < 0) return false;
        if (_to.isNotEmpty && i.date.compareTo(_to) > 0) return false;
        if (_warehouse.isNotEmpty && i.warehouse != _warehouse) return false;
        if (_fuelType.isNotEmpty && i.fuelType != _fuelType) return false;
        if (_unit.isNotEmpty && i.beneficiaryName != _unit) return false;
        return true;
      }).toList();

  /// «تفريدة تف-٠٠٠٠٣٣ — الدوريات» أو «أمر استثنائي»: الورقة تُقرأ بالسند
  /// الذي صُرف عليه، لا باسم الجهة وحده.
  String _party(FuelIssue i) {
    if (i.source == FuelSource.exceptional) return 'أمر استثنائي';
    final a = _allocations
        .where((x) => x.allocation.id == i.allocationId)
        .firstOrNull;
    final unit = i.beneficiaryName.isEmpty
        ? (_units.where((u) => u.id == i.beneficiaryUnitId).firstOrNull?.name ??
            '—')
        : i.beneficiaryName;
    return a == null ? unit : 'تفريدة ${a.allocation.refNo} — $unit';
  }

  Future<void> _print() async {
    if (!Perm.of(context).guard(context, 'fuelConsumption', 'print')) return;
    final rows = FuelConsumption.group(_filtered, _groupBy);
    if (rows.isEmpty) {
      showImdToast(context, '✖ لا حركات في هذا المدى');
      return;
    }
    final total = FuelConsumption.total(_filtered);
    final layout = await SettingsRepo(_db).printLayoutFor(PrintForms.fuelConsumption);
    if (!mounted) return;
    var i = 1;
    await DocumentPdf.printDoc(
      layout: layout,
      doc: PrintDoc(
        title: 'تقرير استهلاك المحروقات — حسب ${FuelGroupBy.label(_groupBy)}',
        headers: const [
          'م',
          'البند',
          'السندات',
          'بترول',
          'ديزل',
          'الإجمالي',
          'النسبة',
        ],
        columnFlex: const [1, 6, 2, 2, 2, 3, 2],
        rows: [
          for (final r in rows)
            [
              '${i++}',
              r.label,
              nf(r.count),
              nf(r.petrol),
              nf(r.diesel),
              nf(r.liters),
              '${(r.shareOf(total) * 100).round()}٪',
            ],
        ],
        leftValues: {'date': _to, 'refNo': 'استهلاك'},
        fieldValues: {
          'warehouse': _warehouse.isEmpty ? 'كافة المستودعات' : _warehouse,
          'party': 'من $_from إلى $_to',
        },
        footerNote: 'الإجمالي ${nf(total)} ${Fuel.unit} في '
            '${nf(_filtered.length)} سندًا · متوسط يومي '
            '${nf(FuelConsumption.dailyAverage(_filtered, from: _from, to: _to))} '
            '${Fuel.unit}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تقرير الاستهلاك', icon: 'trending'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final moves = _filtered;
    final rows = FuelConsumption.group(moves, _groupBy);
    final total = FuelConsumption.total(moves);

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'تقرير الاستهلاك',
        icon: 'trending',
        subtitle: 'من يشرب الوقود وكم وبأي نسبة — مجمَّعًا بالجهة أو المركبة '
            'أو المستودع أو النوع',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي المصروف', value: '${nf(total)} ${Fuel.unit}'),
        ImdKpi(
            label: 'بترول',
            value: nf(FuelConsumption.totalOf(moves, FuelType.petrol))),
        ImdKpi(
            label: 'ديزل',
            value: nf(FuelConsumption.totalOf(moves, FuelType.diesel))),
        ImdKpi(label: 'عدد السندات', value: nf(moves.length)),
        ImdKpi(
          label: 'المتوسط اليومي',
          value: nf(FuelConsumption.dailyAverage(moves, from: _from, to: _to)),
          extra: const ImdChip('على أيام المدى', tone: ImdTone.off),
        ),
      ]),
      ImdICard(
        title: 'فلاتر التقرير',
        icon: 'sliders',
        child: ImdF2(children: [
          ImdLabeled(
            'من تاريخ',
            ImdDateField(
                value: _from, onChanged: (v) => setState(() => _from = v)),
            size: 11,
          ),
          ImdLabeled(
            'إلى تاريخ',
            ImdDateField(value: _to, onChanged: (v) => setState(() => _to = v)),
            size: 11,
          ),
          ImdLabeled(
            'المستودع',
            ImdSelect<String>(
              items: [
                ('', 'الكل'),
                for (final w in _warehouses) (w.name, w.name),
              ],
              value: _warehouse,
              onChanged: (v) => setState(() => _warehouse = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled(
            'الوحدة',
            ImdSelect<String>(
              items: [
                ('', 'كل الوحدات'),
                for (final u in _units) (u.name, u.name),
              ],
              value: _unit,
              onChanged: (v) => setState(() => _unit = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled(
            'نوع الوقود',
            ImdSelect<String>(
              items: [
                ('', 'الكل'),
                for (final t in FuelType.all) (t, FuelType.label(t)),
              ],
              value: _fuelType,
              onChanged: (v) => setState(() => _fuelType = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled(
            ' ',
            Wrap(spacing: 10, runSpacing: 8, children: [
              ImdButton.outline(
                  label: 'تحديث',
                  icon: 'refresh',
                  small: true,
                  onPressed: _load),
              ImdButton.outline(
                  label: 'طباعة التقرير',
                  icon: 'printer',
                  small: true,
                  onPressed: _print),
            ]),
            size: 11,
          ),
        ]),
      ),
      ImdItabs(
        value: _groupBy,
        onChanged: (v) => setState(() => _groupBy = v),
        tabs: [
          for (final g in FuelGroupBy.all) ImdTab(g, FuelGroupBy.label(g)),
        ],
      ),
      ImdPanel(
        title: 'الاستهلاك حسب ${FuelGroupBy.label(_groupBy)}',
        icon: 'chart',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (rows.isNotEmpty) ...[
            _chart(rows),
            const SizedBox(height: 16),
          ],
          _table(rows, total),
        ]),
      ),
      ImdPanel(
        title: 'حركات الصرف',
        icon: 'list',
        child: _moveTable(),
      ),
    ]);
  }

  /// أكبر ثمانية بنودٍ رسمًا: عشرون عمودًا متلاصقة لا تُقرأ، والجدول تحتها
  /// يُتمّ البقية.
  Widget _chart(List<FuelConsumptionRow> rows) {
    final c = context.imd;
    final top = rows.take(8).toList();
    return ImdVBarChart(
      labels: [for (final r in top) r.label],
      height: 230,
      series: [
        ImdSeries('لتر', [for (final r in top) r.liters], c.accent),
      ],
    );
  }

  Widget _moveTable() {
    final c = context.imd;
    final rows = _filteredIssues;
    return ImdTable(
      empty: 'لا حركات صرف في هذا المدى',
      minWidth: 900,
      columns: const [
        ImdCol('التاريخ'),
        ImdCol('السند'),
        ImdCol('المستودع'),
        ImdCol('الصنف'),
        ImdCol('الجهة'),
        ImdCol('الكمية', numeric: true),
        ImdCol('', center: true),
      ],
      pageSize: 50,
      rows: [
        for (final i in rows)
          [
            Text(arDigits(i.date)),
            Text(i.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(i.warehouse),
            ImdChip(FuelType.label(i.fuelType),
                tone: i.fuelType == FuelType.diesel
                    ? ImdTone.code
                    : ImdTone.info),
            Text(_party(i)),
            Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdIconButton(
              icon: 'printer',
              tooltip: 'طباعة السند',
              onPressed: () {
                if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                FuelPrint.issueVoucher(
                _db,
                i,
                allocation: _allocations
                    .where((a) => a.allocation.id == i.allocationId)
                    .firstOrNull,
              );
              },
            ),
          ],
      ],
    );
  }

  Widget _table(List<FuelConsumptionRow> rows, double total) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا حركات صرف في هذا المدى',
      minWidth: 820,
      columns: const [
        ImdCol('البند'),
        ImdCol('السندات', numeric: true),
        ImdCol('بترول', numeric: true),
        ImdCol('ديزل', numeric: true),
        ImdCol('الإجمالي', numeric: true),
        ImdCol('النسبة'),
      ],
      rows: [
        for (final r in rows)
          [
            Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(nf(r.count)),
            Text(r.petrol == 0 ? '—' : nf(r.petrol)),
            Text(r.diesel == 0 ? '—' : nf(r.diesel)),
            Text('${nf(r.liters)} ${Fuel.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            // الشريط يُري الحصّة قبل قراءة الرقم.
            SizedBox(
              width: 120,
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: r.shareOf(total).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: c.subtle,
                      valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${(r.shareOf(total) * 100).round()}٪',
                    style: TextStyle(fontSize: 11, color: c.muted)),
              ]),
            ),
          ],
      ],
    );
  }
}
