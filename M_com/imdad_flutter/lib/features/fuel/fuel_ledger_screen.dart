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

export 'fuel_stocks_report_screen.dart';
export 'fuel_plan_vs_issued_screen.dart';


/// حركةٌ واحدة في كشف حساب المستودع.
class _Move {
  const _Move({
    required this.date,
    required this.refNo,
    required this.kind,
    required this.detail,
    required this.inQty,
    required this.outQty,
    required this.tone,
  });

  final String date;
  final String refNo;
  final String kind;
  final String detail;
  final double inQty;
  final double outQty;
  final ImdTone tone;
}


/// كشف حركة المستودع — كل ما دخل وخرج بترتيبه، والرصيد يمشي معه.
///
/// **هذا هو الكشف الذي يُطلب عند الخلاف.** التقارير الأخرى تقول كم؛ وهذا
/// وحده يقول متى وبأي سند، فيُوضع الإصبع على السطر الذي اختلّ عنده الرصيد.
class FuelLedgerScreen extends StatefulWidget {
  const FuelLedgerScreen({super.key});

  @override
  State<FuelLedgerScreen> createState() => _FuelLedgerScreenState();
}


class _FuelLedgerScreenState extends State<FuelLedgerScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelIssue> _issues = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelTransfer> _transfers = const [];
  List<FuelOpening> _openings = const [];

  String _warehouse = '';
  String _fuelType = FuelType.petrol;
  late String _from;
  late String _to;
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
    final warehouses = await _repo.warehouses();
    final issues = await _repo.issues();
    final supplies = await _repo.supplies();
    final transfers = await _repo.transfers();
    final openings = await _repo.openings();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _issues = issues;
      _supplies = supplies;
      _transfers = transfers;
      _openings = openings;
      if (_warehouse.isEmpty && warehouses.isNotEmpty) {
        _warehouse = warehouses.first.name;
      }
      _loading = false;
    });
  }

  bool _mine(String date) =>
      (_from.isEmpty || date.compareTo(_from) >= 0) &&
      (_to.isEmpty || date.compareTo(_to) <= 0);

  /// ما استقرّ في الخزّان قبل أول يومٍ في المدى — وبه يبدأ الكشف.
  double get _broughtForward {
    var v = 0.0;
    for (final o in _openings) {
      if (o.warehouse == _warehouse &&
          o.fuelType == _fuelType &&
          (_from.isEmpty || o.asOfDate.compareTo(_from) < 0)) {
        v += o.liters;
      }
    }
    for (final s in _supplies) {
      if (s.warehouse == _warehouse &&
          s.fuelType == _fuelType &&
          s.date.compareTo(_from) < 0) {
        v += s.quantityLiters;
      }
    }
    for (final t in _transfers) {
      if (t.fuelType != _fuelType || t.date.compareTo(_from) >= 0) continue;
      if (t.toWarehouse == _warehouse) v += t.quantityLiters;
      if (t.fromWarehouse == _warehouse) v -= t.quantityLiters;
    }
    for (final i in _issues) {
      if (i.warehouse == _warehouse &&
          i.fuelType == _fuelType &&
          i.date.compareTo(_from) < 0) {
        v -= i.quantityLiters;
      }
    }
    return Fuel.round(v);
  }

  List<_Move> get _moves {
    final out = <_Move>[
      for (final o in _openings)
        if (o.warehouse == _warehouse &&
            o.fuelType == _fuelType &&
            _mine(o.asOfDate))
          _Move(
            date: o.asOfDate,
            refNo: '—',
            kind: 'رصيد افتتاحي',
            detail: o.note.isEmpty ? '—' : o.note,
            inQty: o.liters,
            outQty: 0,
            tone: ImdTone.off,
          ),
      for (final s in _supplies)
        if (s.warehouse == _warehouse &&
            s.fuelType == _fuelType &&
            _mine(s.date))
          _Move(
            date: s.date,
            refNo: s.refNo,
            kind: 'توريد',
            detail: s.supplierName.isEmpty ? '—' : s.supplierName,
            inQty: s.quantityLiters,
            outQty: 0,
            tone: ImdTone.ok,
          ),
      for (final t in _transfers)
        if (t.fuelType == _fuelType && _mine(t.date)) ...[
          if (t.toWarehouse == _warehouse)
            _Move(
              date: t.date,
              refNo: t.refNo,
              kind: 'محوَّل إليه',
              detail: 'من ${t.fromWarehouse}',
              inQty: t.quantityLiters,
              outQty: 0,
              tone: ImdTone.info,
            ),
          if (t.fromWarehouse == _warehouse)
            _Move(
              date: t.date,
              refNo: t.refNo,
              kind: 'محوَّل منه',
              detail: 'إلى ${t.toWarehouse}',
              inQty: 0,
              outQty: t.quantityLiters,
              tone: ImdTone.info,
            ),
        ],
      for (final i in _issues)
        if (i.warehouse == _warehouse &&
            i.fuelType == _fuelType &&
            _mine(i.date))
          _Move(
            date: i.date,
            refNo: i.refNo,
            kind: 'صرف',
            detail: [
              if (i.beneficiaryName.isNotEmpty) i.beneficiaryName,
              if (i.vehicleType.isNotEmpty) i.vehicleType,
              if (i.chassisNo.isNotEmpty) i.chassisNo,
            ].join(' · '),
            inQty: 0,
            outQty: i.quantityLiters,
            tone: i.source == FuelSource.exceptional
                ? ImdTone.pend
                : ImdTone.code,
          ),
    ];
    // بالتاريخ ثم برقم السند، فيقرأ اليومُ الواحد بترتيب دفتره.
    out.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.refNo.compareTo(b.refNo);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'كشف حركة المستودع', icon: 'list'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    if (_warehouses.isEmpty) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'كشف حركة المستودع', icon: 'list'),
        ImdEmptyBox('عرّف مستودعًا أولًا من شاشة البيانات الأساسية'),
      ]);
    }

    final moves = _moves;
    final opening = _broughtForward;
    final totalIn = moves.fold<double>(0, (t, m) => t + m.inQty);
    final totalOut = moves.fold<double>(0, (t, m) => t + m.outQty);
    final closing = Fuel.round(opening + totalIn - totalOut);

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'كشف حركة المستودع',
        icon: 'list',
        subtitle: 'كل ما دخل الخزّان وخرج منه بترتيبه، والرصيد يمشي مع كل سطر',
      ),
      ImdICard(
        title: 'نطاق الكشف',
        icon: 'sliders',
        child: ImdF2(children: [
          ImdLabeled(
            'المستودع',
            ImdSelect<String>(
              items: [for (final w in _warehouses) (w.name, w.name)],
              value: _warehouse,
              onChanged: (v) => setState(() => _warehouse = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled(
            'الصنف',
            ImdSelect<String>(
              items: [for (final t in FuelType.all) (t, FuelType.label(t))],
              value: _fuelType,
              onChanged: (v) =>
                  setState(() => _fuelType = v ?? FuelType.petrol),
            ),
            size: 11,
          ),
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
        ]),
      ),
      ImdKpis(children: [
        ImdKpi(
          label: 'رصيد ما قبل المدى',
          value: '${nf(opening)} ${Fuel.unit}',
          extra: const ImdChip('مُرحَّل', tone: ImdTone.off),
        ),
        ImdKpi(label: 'الوارد في المدى', value: nf(totalIn)),
        ImdKpi(label: 'الصادر في المدى', value: nf(totalOut)),
        ImdKpi(
          label: 'الرصيد في آخر المدى',
          value: '${nf(closing)} ${Fuel.unit}',
          extra: closing < 0
              ? const ImdChip('رصيد سالب', tone: ImdTone.err)
              : null,
        ),
      ]),
      ImdPanel(
        title: 'الحركة — $_warehouse · ${FuelType.label(_fuelType)}',
        icon: 'list',
        child: _table(moves, opening, closing),
      ),
    ]);
  }

  Widget _table(List<_Move> moves, double opening, double closing) {
    final c = context.imd;
    var running = opening;
    return ImdTable(
      empty: 'لا حركة على هذا المستودع في المدى',
      minWidth: 1000,
      columns: const [
        ImdCol('التاريخ'),
        ImdCol('السند'),
        ImdCol('البيان'),
        ImdCol('التفصيل'),
        ImdCol('وارد', numeric: true),
        ImdCol('صادر', numeric: true),
        ImdCol('الرصيد', numeric: true),
      ],
      pageSize: 50,
      values: () {
        var run = opening;
        return [
          [arDigits(_from), '—', 'رصيد مُرحَّل', 'ما استقرّ في الخزّان قبل بداية المدى', '—', '—', '${nf(opening)} ${Fuel.unit}'],
          for (final m in moves)
            () {
              run = Fuel.round(run + m.inQty - m.outQty);
              return [
                arDigits(m.date),
                m.refNo,
                m.kind,
                m.detail.isEmpty ? '—' : m.detail,
                m.inQty == 0 ? '—' : nf(m.inQty),
                m.outQty == 0 ? '—' : nf(m.outQty),
                '${nf(run)} ${Fuel.unit}',
              ];
            }(),
        ];
      }(),
      rows: [
        // السطر الأول رصيدٌ مُرحَّل لا حركة، فيُميَّز ولا يُجمع مع الوارد.
        [
          Text(arDigits(_from), style: TextStyle(color: c.muted)),
          Text('—', style: TextStyle(color: c.muted)),
          const ImdChip('رصيد مُرحَّل', tone: ImdTone.off),
          Text('ما استقرّ في الخزّان قبل بداية المدى',
              style: TextStyle(color: c.muted, fontSize: 12)),
          const Text('—'),
          const Text('—'),
          Text('${nf(opening)} ${Fuel.unit}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        for (final m in moves)
          () {
            running = Fuel.round(running + m.inQty - m.outQty);
            return [
              Text(arDigits(m.date)),
              Text(m.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
              ImdChip(m.kind, tone: m.tone),
              Text(m.detail.isEmpty ? '—' : m.detail),
              Text(m.inQty == 0 ? '—' : nf(m.inQty),
                  style: TextStyle(color: m.inQty == 0 ? c.muted : c.success)),
              Text(m.outQty == 0 ? '—' : nf(m.outQty),
                  style: TextStyle(color: m.outQty == 0 ? c.muted : c.danger)),
              Text('${nf(running)} ${Fuel.unit}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: running < 0 ? c.danger : c.text)),
            ];
          }(),
      ],
      footer: [
        const Text(''),
        const Text(''),
        const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text(''),
        Text(nf(moves.fold<double>(0, (t, m) => t + m.inQty)),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(nf(moves.fold<double>(0, (t, m) => t + m.outQty)),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${nf(closing)} ${Fuel.unit}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
