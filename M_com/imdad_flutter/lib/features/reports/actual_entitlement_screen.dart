import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/export/excel_export.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/meal_plan_repo.dart';
import '../../data/repos/reports_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/date_span.dart';
import '../../domain/entitlement_actual.dart';
import '../../domain/entitlements.dart' as ent;
import '../../domain/meal_plan.dart';

/// حساب الاستحقاق الفعلي: المستحق على مدى مقابل المصروف فعلًا.
///
/// المصروف يُقرأ من [ReportsRepo] التي توحّد سندات النظام كلها في `MoveRow`
/// واحدة — بحالتها، فلا تدخل مسودة ولا ملغى في الحساب.
class ActualEntitlementScreen extends StatefulWidget {
  const ActualEntitlementScreen({super.key});

  @override
  State<ActualEntitlementScreen> createState() => _ActualEntitlementScreenState();
}

class _ActualEntitlementScreenState extends State<ActualEntitlementScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();

  ReportData? _data;
  List<MealPlan> _plans = const [];
  List<ActualRow> _rows = const [];
  Map<String, int> _persons = const {};

  String _source = EntitlementSource.scale;
  String _planId = '';
  String _period = PeriodKind.monthly;
  String _anchor = DateSpan.ymd(DateTime.now());
  String _customStart = '';
  String _customEnd = '';
  String _unitId = '';
  String _warehouse = '';

  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  DateSpan get _span => PeriodKind.resolve(
        _period,
        _anchor,
        customStart: _customStart,
        customEnd: _customEnd,
      );

  Future<void> _boot() async {
    final scope = Perm.of(context).scope;
    final data = await ReportsRepo(_db).load(scope: scope);
    final plans = await MealPlanRepo(_db).plans(scope: scope);
    if (!mounted) return;
    setState(() {
      _data = data;
      _plans = plans;
      _loading = false;
    });
    await _compute();
  }

  Future<void> _compute() async {
    final data = _data;
    if (data == null) return;
    final span = _span;
    if (!span.isValid) {
      setState(() => _rows = const []);
      return;
    }
    setState(() => _busy = true);

    final persons = await MealPlanRepo(_db).personsByDay(span);
    final items = await CatalogRepo(_db).items();
    final names = {for (final i in items) i.id: i.name};
    final units = {for (final i in items) i.id: i.baseUnit};

    // المستحق: من نسب المقرر أو من خطة وجبات.
    var entitled = <String, double>{};
    if (_source == EntitlementSource.plan) {
      if (_planId.isNotEmpty) {
        final needs = await MealPlanRepo(_db).requirements(_planId, within: span);
        entitled = {for (final n in needs) n.itemId: n.baseQty};
      }
    } else {
      final rows = await DailyRepo(_db).entitlements();
      final scales = [
        for (final e in rows)
          ent.Entitlement(
            itemId: e.itemId,
            itemName: e.itemName,
            qtyPerPerson: e.qtyPerPerson,
            measureUnitName: e.measureUnitName,
            measureFactor: e.measureFactor,
          ),
      ];
      entitled = ActualEntitlement.fromScale(
        scales: scales,
        personsByDay: persons,
        days: span.days,
      );
    }

    // المصروف: حركات المدى بعد الترشيح بالمستودع والوحدة.
    final moves = [
      for (final m in data.moves)
        if (m.date.isNotEmpty && span.contains(m.date))
          if (_warehouse.isEmpty || m.warehouse == _warehouse)
            if (_unitId.isEmpty || m.unitId == _unitId)
              ConsumptionMove(
                itemId: m.itemId,
                type: m.type,
                baseQty: m.baseQty,
                active: m.active,
              ),
    ];

    final rows = ActualEntitlement.compute(
      entitled: entitled,
      moves: moves,
      names: names,
      units: units,
    );
    if (!mounted) return;
    setState(() {
      _persons = persons;
      _rows = rows;
      _busy = false;
    });
  }

  // ───────────────────────── الإخراج

  List<String> get _headers => const [
        'م',
        'الصنف',
        'المستحق',
        'المصروف',
        'المرتجع',
        'الصافي',
        'نسبة الاستهلاك',
        'الوحدة',
      ];

  List<List<String>> _exportRows() {
    var i = 0;
    return [
      for (final r in _rows)
        [
          nf(++i),
          r.itemName,
          nf(r.entitled),
          nf(r.issued),
          nf(r.returned),
          nf(r.balance),
          '${nf(r.ratio * 100)}٪',
          r.unitName,
        ],
    ];
  }

  String get _title {
    final src = EntitlementSource.label(_source);
    final plan = _source == EntitlementSource.plan && _planId.isNotEmpty
        ? ' (${_plans.where((p) => p.id == _planId).firstOrNull?.name ?? ''})'
        : '';
    return 'حساب الاستحقاق الفعلي — $src$plan';
  }

  Future<void> _print() async {
    if (!Perm.of(context).guard(context, 'actualEntitlement', PermAction.print)) return;
    if (_rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للطباعة', error: true);
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    final t = ActualEntitlement.totals(_rows);
    if (!mounted) return;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: _title,
        headers: _headers,
        rows: _exportRows(),
        leftValues: {'date': ReportsRepo.today()},
        fieldValues: {
          'warehouse': _warehouse.isEmpty ? 'كل المستودعات' : _warehouse,
          'notes': 'الفترة ${_span.start} إلى ${_span.end} (${_span.days} يومًا) — '
              'المستحق ${nf(t.entitled)} · المصروف ${nf(t.consumed)} · '
              'الصافي ${nf(t.balance)}',
        },
      ),
      layout: layout,
    );
  }

  Future<void> _export() async {
    if (!Perm.of(context).guard(context, 'actualEntitlement', PermAction.export)) return;
    if (_rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للتصدير', error: true);
      return;
    }
    final bytes = ExcelExport.build(
      sheetName: 'الاستحقاق الفعلي',
      headers: _headers,
      rows: _exportRows(),
    );
    if (!mounted) return;
    final path = await ImdFiles.saveBytes(
      context,
      'الاستحقاق_الفعلي_${_span.start}_${_span.end}.xlsx',
      bytes,
    );
    if (path != null && mounted) showImdToast(context, '✔ صُدِّر الملف');
  }

  // ───────────────────────── الواجهة

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'حساب الاستحقاق الفعلي', icon: 'calculator'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final span = _span;
    final t = ActualEntitlement.totals(_rows);
    final missingDays = span.dates.where((d) => (_persons[d] ?? 0) == 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'حساب الاستحقاق الفعلي',
        icon: 'calculator',
        subtitle: 'ما يستحقه المستفيدون على مدى مقابل ما صُرف لهم فعلًا — '
            'والمرتجع مخصوم من المصروف',
      ),
      _filters(),
      if (_source == EntitlementSource.plan && _planId.isEmpty)
        const ImdNote('اختر خطة وجبات ليُحسب المستحق منها.')
      else ...[
        ImdKpis(children: [
          ImdKpi(label: 'إجمالي المستحق', value: nf(t.entitled)),
          ImdKpi(label: 'إجمالي المصروف', value: nf(t.consumed)),
          ImdKpi(
            label: t.balance >= 0 ? 'المتبقي لهم' : 'المصروف زائدًا',
            value: nf(t.balance.abs()),
            extra: ImdChip(
              t.balance >= 0 ? 'ضمن الاستحقاق' : 'تجاوز',
              tone: t.balance >= 0 ? ImdTone.ok : ImdTone.err,
            ),
          ),
          ImdKpi(label: 'أيام الفترة', value: nf(span.days)),
          ImdKpi(
            label: 'أيام بلا تفريدة',
            value: nf(missingDays),
            extra: missingDays == 0 ? null : const ImdChip('حساب ناقص', tone: ImdTone.pend),
          ),
        ]),
        if (missingDays > 0)
          ImdNote(_source == EntitlementSource.plan
              ? 'يوجد ${nf(missingDays)} يومًا بلا قوة مسجّلة — احتياج تلك الأيام '
                  'يُحسب **صفرًا**، فالمستحق أقل من حقيقته.'
              : 'يوجد ${nf(missingDays)} يومًا بلا قوة مسجّلة. المتوسط يُحسب من '
                  'الأيام المسجّلة وحدها، فلا يخفضه الإهمال الإداري.'),
        if (_rows.isNotEmpty) _chart(),
        ImdPanel(
          title: 'التفصيل بالصنف',
          icon: 'list',
          child: _table(),
        ),
      ],
    ]);
  }

  Widget _filters() {
    final span = _span;
    final custom = _period == PeriodKind.custom;
    final perm = Perm.of(context);
    return ImdICard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdF2(children: [
          ImdLabeled(
            'مصدر الاستحقاق',
            ImdSelect<String>(
              items: [for (final s in EntitlementSource.all) (s, EntitlementSource.label(s))],
              value: _source,
              onChanged: (v) {
                setState(() => _source = v ?? EntitlementSource.scale);
                _compute();
              },
            ),
            size: 11,
          ),
          if (_source == EntitlementSource.plan)
            ImdLabeled(
              'الخطة',
              ImdSelect<String>(
                hint: 'اختر خطة',
                items: [for (final p in _plans) (p.id, p.name)],
                value: _planId.isEmpty ? null : _planId,
                onChanged: (v) {
                  setState(() => _planId = v ?? '');
                  _compute();
                },
              ),
              size: 11,
            ),
          ImdLabeled(
            'نوع الفترة',
            ImdSelect<String>(
              items: [for (final k in PeriodKind.all) (k, PeriodKind.label(k))],
              value: _period,
              onChanged: (v) {
                setState(() {
                  _period = v ?? PeriodKind.monthly;
                  if (_period == PeriodKind.custom && _customStart.isEmpty) {
                    _customStart = span.start;
                    _customEnd = span.end;
                  }
                });
                _compute();
              },
            ),
            size: 11,
          ),
          if (!custom)
            ImdLabeled(
              'التاريخ المرجعي',
              ImdDateField(
                value: _anchor,
                onChanged: (v) {
                  setState(() => _anchor = v);
                  _compute();
                },
              ),
              size: 11,
            ),
          if (custom) ...[
            ImdLabeled(
              'من',
              ImdDateField(
                value: _customStart,
                onChanged: (v) {
                  setState(() => _customStart = v);
                  _compute();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'إلى',
              ImdDateField(
                value: _customEnd,
                onChanged: (v) {
                  setState(() => _customEnd = v);
                  _compute();
                },
              ),
              size: 11,
            ),
          ],
          ImdLabeled(
            'الوحدة المستفيدة',
            ImdSelect<String>(
              items: [
                ('', 'كل الوحدات'),
                for (final u in _data?.units ?? const <BeneficiaryUnit>[]) (u.id, u.name),
              ],
              value: _unitId,
              onChanged: (v) {
                setState(() => _unitId = v ?? '');
                _compute();
              },
            ),
            size: 11,
          ),
          ImdLabeled(
            'المستودع',
            ImdSelect<String>(
              items: [
                ('', 'كل المستودعات'),
                for (final w in _data?.warehouses ?? const <Warehouse>[])
                  if (perm.canWh(w.name)) (w.name, w.name),
              ],
              value: _warehouse,
              onChanged: (v) {
                setState(() => _warehouse = v ?? '');
                _compute();
              },
            ),
            size: 11,
          ),
        ]),
        const SizedBox(height: 10),
        ImdChipsRow(bottom: 0, children: [
          ImdChip('${arDigits(span.start)} ← ${arDigits(span.end)}', tone: ImdTone.code),
          ImdChip('${nf(span.days)} يومًا', tone: ImdTone.info),
          if (_busy) const ImdChip('جارٍ الحساب…', tone: ImdTone.pend),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton.outline(
            label: 'إعادة الحساب',
            icon: 'refresh',
            small: true,
            busy: _busy,
            onPressed: _compute,
          ),
          ImdButton.outline(label: 'طباعة', icon: 'printer', small: true, onPressed: _print),
          ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _export),
        ]),
      ]),
    );
  }

  /// أكبر عشرة أصناف انحرافًا — لا كل الأصناف: رسمٌ بخمسين عمودًا لا يُقرأ.
  Widget _chart() {
    final top = _rows.take(10).toList();
    final c = context.imd;
    return ImdPanel(
      title: 'المستحق مقابل المصروف — أكبر عشرة انحرافًا',
      icon: 'chart',
      child: Column(children: [
        SizedBox(
          height: 280,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: c.ring, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    getTitlesWidget: (v, _) => Text(
                      nf(v),
                      style: TextStyle(fontSize: 9, color: c.muted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= top.length) return const SizedBox.shrink();
                      final name = top[i].itemName;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          name.length > 8 ? '${name.substring(0, 8)}…' : name,
                          style: TextStyle(fontSize: 9, color: c.muted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (final (i, r) in top.indexed)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: r.entitled,
                      color: c.accent,
                      width: 9,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      toY: r.consumed < 0 ? 0 : r.consumed,
                      color: c.warn,
                      width: 9,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const ImdChipsRow(bottom: 0, children: [
          ImdChip('المستحق', tone: ImdTone.info),
          ImdChip('المصروف', tone: ImdTone.pend),
        ]),
      ]),
    );
  }

  Widget _table() => ImdTable(
        empty: 'لا توجد بيانات لهذه الفترة',
        minWidth: 760,
        columns: const [
          ImdCol('الصنف'),
          ImdCol('المستحق', numeric: true),
          ImdCol('المصروف', numeric: true),
          ImdCol('المرتجع', numeric: true),
          ImdCol('الصافي', numeric: true),
          ImdCol('نسبة الاستهلاك'),
        ],
        rows: [
          for (final r in _rows)
            [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(r.itemName)),
                if (r.unentitled) ...[
                  const SizedBox(width: 6),
                  const ImdChip('بلا استحقاق', tone: ImdTone.err),
                ],
              ]),
              Text(nf(r.entitled)),
              Text(nf(r.issued)),
              Text(r.returned == 0 ? '—' : nf(r.returned)),
              Text(
                nf(r.balance),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: r.balance >= 0 ? context.imd.success : context.imd.danger,
                ),
              ),
              _ratioBar(r),
            ],
        ],
      );

  Widget _ratioBar(ActualRow r) {
    if (r.entitled <= 0) {
      return Text('—', style: TextStyle(color: context.imd.faint));
    }
    final pct = (r.ratio * 100).clamp(0, 200).toDouble();
    final c = context.imd;
    final color = pct > 100 ? c.danger : (pct >= 80 ? c.success : c.warn);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 70,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 200,
            minHeight: 7,
            backgroundColor: c.subtle,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${nf(pct)}٪', style: TextStyle(fontSize: 12, color: color)),
    ]);
  }
}
