import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/export/excel_export.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/camp_ledger_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/reports_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/camp_ledger.dart';
import '../../domain/variance_tracker.dart';

/// سجل حساب المعسكر — رصيد الاستحقاق ورصيد المخزون، شهرًا بشهر.
class CampLedgerScreen extends StatefulWidget {
  const CampLedgerScreen({super.key});

  @override
  State<CampLedgerScreen> createState() => _CampLedgerScreenState();
}

class _CampLedgerScreenState extends State<CampLedgerScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CampLedgerRepo _repo = CampLedgerRepo(_db);

  List<BeneficiaryUnit> _camps = const [];
  List<CampLedgerRow> _rows = const [];
  List<VarianceDay> _variance = const [];

  String _campId = '';
  String _varianceItemId = '';
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final camps = await CatalogRepo(_db).camps();
    if (!mounted) return;
    setState(() {
      _camps = camps;
      _campId = camps.isEmpty ? '' : camps.first.id;
      _loading = false;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_campId.isEmpty) return;
    setState(() => _busy = true);
    final rows = await _repo.ledgers(year: _year, month: _month, campId: _campId);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _busy = false;
      if (_varianceItemId.isNotEmpty &&
          !rows.any((r) => r.ledger.itemId == _varianceItemId)) {
        _varianceItemId = '';
        _variance = const [];
      }
    });
  }

  Future<void> _rebuild() async {
    if (!Perm.of(context).guard(context, 'campLedger', PermAction.edit)) return;
    setState(() => _busy = true);
    final n = await _repo.rebuild(
      year: _year,
      month: _month,
      campId: _campId,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, n > 0 ? '✔ أُعيد بناء $n سطرًا' : '✖ لا حركة ولا استحقاق لهذا الشهر',
        error: n == 0);
    await _load();
  }

  Future<void> _showVariance(String itemId) async {
    setState(() => _busy = true);
    final series = await _repo.variance(
      campId: _campId,
      itemId: itemId,
      year: _year,
      month: _month,
    );
    if (!mounted) return;
    setState(() {
      _varianceItemId = itemId;
      _variance = series;
      _busy = false;
    });
  }

  List<String> get _headers => const [
        'م',
        'الصنف',
        'مُرحَّل استحقاق',
        'المستحق',
        'محوَّل',
        'صرف مباشر',
        'مرتجع',
        'رصيد الاستحقاق',
        'الحالة',
        'مُرحَّل مخزون',
        'مستهلك',
        'رصيد المخزون',
      ];

  List<List<String>> _exportRows() {
    var i = 0;
    return [
      for (final r in _rows)
        [
          nf(++i),
          r.ledger.itemName,
          nf(r.amounts.openingEntitled),
          nf(r.amounts.entitlementTotal),
          nf(r.amounts.transferredIn),
          nf(r.amounts.issuedDirect),
          nf(r.amounts.returnedQty),
          nf(r.amounts.entitlementBalance),
          r.amounts.entitlementStatus.label,
          nf(r.amounts.openingStock),
          nf(r.amounts.consumedKitchen),
          nf(r.amounts.stockBalance),
        ],
    ];
  }

  String get _campName => _camps.where((c) => c.id == _campId).firstOrNull?.name ?? '';

  Future<void> _print() async {
    if (!Perm.of(context).guard(context, 'campLedger', PermAction.print)) return;
    if (_rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للطباعة', error: true);
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    final t = CampLedgerCalc.totals([for (final r in _rows) r.amounts]);
    if (!mounted) return;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'سجل حساب المعسكر — $_campName ($_month/$_year)',
        headers: _headers,
        rows: _exportRows(),
        leftValues: {'date': ReportsRepo.today()},
        fieldValues: {
          'party': _campName,
          'notes': 'متبقٍ لهم ${nf(t.credit)} · متبقٍ عليهم ${nf(t.debit)} · '
              'الصافي ${nf(t.net)}',
        },
      ),
      layout: layout,
    );
  }

  Future<void> _export() async {
    if (!Perm.of(context).guard(context, 'campLedger', PermAction.export)) return;
    if (_rows.isEmpty) return;
    final bytes = ExcelExport.build(
      sheetName: 'سجل المعسكر',
      headers: _headers,
      rows: _exportRows(),
    );
    if (!mounted) return;
    final path = await ImdFiles.saveBytes(
      context,
      'سجل_${_campName}_$_year-$_month.xlsx',
      bytes,
    );
    if (path != null && mounted) showImdToast(context, '✔ صُدِّر الملف');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'سجل حساب المعسكر', icon: 'calculator'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    if (_camps.isEmpty) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'سجل حساب المعسكر', icon: 'calculator'),
        ImdNote('لا توجد معسكرات معرَّفة. عرّفها من «الوحدات المستفيدة» أولًا.'),
      ]);
    }
    final t = CampLedgerCalc.totals([for (final r in _rows) r.amounts]);
    final closed = _rows.any((r) => r.ledger.status == 'CLOSED');
    final impossible = _rows.where((r) => r.amounts.stockImpossible).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'سجل حساب المعسكر',
        icon: 'calculator',
        subtitle: 'رصيدان لكل صنف: **رصيد الاستحقاق** (هل أخذ حقه؟) و**رصيد '
            'المخزون** (كم بقي عنده؟)',
      ),
      _filters(closed),
      ImdKpis(children: [
        ImdKpi(label: 'متبقٍ لهم', value: nf(t.credit)),
        ImdKpi(label: 'متبقٍ عليهم', value: nf(t.debit)),
        ImdKpi(
          label: 'صافي الاستحقاق',
          value: nf(t.net.abs()),
          extra: ImdChip(
            t.net >= 0 ? 'لصالح المعسكر' : 'على المعسكر',
            tone: t.net >= 0 ? ImdTone.ok : ImdTone.err,
          ),
        ),
        ImdKpi(label: 'مخزون المعسكر', value: nf(t.stock)),
        ImdKpi(label: 'الأصناف', value: nf(_rows.length)),
      ]),
      if (impossible > 0)
        ImdNote('${nf(impossible)} صنفًا رصيد مخزونه **سالب** — استهلاكٌ في المطبخ '
            'أكثر مما استُلم. راجع سندات الاستلام أو سجل الطهي لتلك الأصناف.'),
      ImdPanel(title: 'تفصيل الأصناف', icon: 'list', child: _table()),
      if (_variance.isNotEmpty)
        ImdPanel(
          title: 'الانحراف اليومي — '
              '${_rows.where((r) => r.ledger.itemId == _varianceItemId).firstOrNull?.ledger.itemName ?? ''}',
          icon: 'trending',
          child: _varianceTable(),
        ),
    ]);
  }

  Widget _filters(bool closed) => ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled(
              'المعسكر',
              ImdSelect<String>(
                items: [for (final c in _camps) (c.id, c.name)],
                value: _campId,
                onChanged: (v) {
                  setState(() {
                    _campId = v ?? '';
                    _variance = const [];
                    _varianceItemId = '';
                  });
                  _load();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'الشهر',
              ImdSelect<int>(
                items: [for (var m = 1; m <= 12; m++) (m, _monthName(m))],
                value: _month,
                onChanged: (v) {
                  setState(() => _month = v ?? DateTime.now().month);
                  _load();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'السنة',
              ImdSelect<int>(
                items: [
                  for (var y = DateTime.now().year - 3; y <= DateTime.now().year + 1; y++)
                    (y, arDigits('$y')),
                ],
                value: _year,
                onChanged: (v) {
                  setState(() => _year = v ?? DateTime.now().year);
                  _load();
                },
              ),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          ImdChipsRow(bottom: 0, children: [
            if (closed) const ImdChip('الشهر مُصفّى — الأرقام مثبّتة', tone: ImdTone.code),
            if (_busy) const ImdChip('جارٍ الحساب…', tone: ImdTone.pend),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ImdButton.outline(
              label: 'إعادة بناء السجل',
              icon: 'refresh',
              small: true,
              busy: _busy,
              onPressed: closed ? null : _rebuild,
            ),
            ImdButton.outline(label: 'طباعة', icon: 'printer', small: true, onPressed: _print),
            ImdButton.outline(
                label: 'تصدير Excel', icon: 'download', small: true, onPressed: _export),
          ]),
          if (closed)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: ImdNote('الشهر مُصفّى: أرقامه صارت أساس الشهر التالي، فلا تُبنى '
                  'من جديد حتى لا تنكسر سلسلة الترحيل.'),
            ),
        ]),
      );

  Widget _table() => ImdTable(
        empty: 'لا سجلات — اضغط «إعادة بناء السجل» بعد إدخال التفريدة والحركات',
        minWidth: 1000,
        columns: const [
          ImdCol('الصنف'),
          ImdCol('مُرحَّل', numeric: true),
          ImdCol('المستحق', numeric: true),
          ImdCol('المُسلَّم', numeric: true),
          ImdCol('رصيد الاستحقاق', numeric: true),
          ImdCol('الحالة'),
          ImdCol('المستهلك', numeric: true),
          ImdCol('رصيد المخزون', numeric: true),
          ImdCol('', center: true),
        ],
        rows: [
          for (final r in _rows)
            [
              Text(r.ledger.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(nf(r.amounts.openingEntitled)),
              Text(nf(r.amounts.entitlementTotal)),
              Text(nf(r.amounts.delivered)),
              Text(
                nf(r.amounts.entitlementBalance),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: switch (r.amounts.entitlementStatus) {
                    LedgerStatus.credit => context.imd.success,
                    LedgerStatus.debit => context.imd.danger,
                    LedgerStatus.balanced => context.imd.muted,
                  },
                ),
              ),
              ImdChip(
                r.amounts.entitlementStatus.label,
                tone: switch (r.amounts.entitlementStatus) {
                  LedgerStatus.credit => ImdTone.ok,
                  LedgerStatus.debit => ImdTone.err,
                  LedgerStatus.balanced => ImdTone.off,
                },
              ),
              Text(nf(r.amounts.consumedKitchen)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  nf(r.amounts.stockBalance),
                  style: TextStyle(
                    color: r.amounts.stockImpossible ? context.imd.danger : null,
                    fontWeight: r.amounts.stockImpossible ? FontWeight.w700 : null,
                  ),
                ),
                if (r.amounts.stockImpossible) ...[
                  const SizedBox(width: 6),
                  const ImdChip('مستحيل', tone: ImdTone.err),
                ],
              ]),
              ImdIconButton(
                icon: 'trending',
                tooltip: 'الانحراف اليومي',
                onPressed: () => _showVariance(r.ledger.itemId),
              ),
            ],
        ],
      );

  Widget _varianceTable() {
    final s = VarianceTracker.summary(_variance);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('الانحراف يقيس فرق قوة كل يوم عن متوسط الشهر الذي صُرف على أساسه. '
          'الصافي يقارب الصفر دائمًا — والفائدة في **الأطراف**: يومٌ انحرافه كبير '
          'يعني قوةً تبدّلت فجأةً، وهي إما حركة وحدات أو خطأ تفريدة.'),
      const SizedBox(height: 10),
      ImdChipsRow(children: [
        ImdChip('المتوسط: ${nf(_variance.first.average)}', tone: ImdTone.info),
        if (s.maxCredit != null)
          ImdChip('أعلى يوم: ${arDigits(s.maxCredit!.date)} (+${nf(s.maxCredit!.variance)})',
              tone: ImdTone.ok),
        if (s.maxDebit != null)
          ImdChip('أدنى يوم: ${arDigits(s.maxDebit!.date)} (${nf(s.maxDebit!.variance)})',
              tone: ImdTone.err),
      ]),
      const SizedBox(height: 8),
      ImdTable(
        empty: 'لا تفريدة لهذا الشهر',
        minWidth: 520,
        columns: const [
          ImdCol('اليوم'),
          ImdCol('القوة', numeric: true),
          ImdCol('المتوسط', numeric: true),
          ImdCol('الانحراف', numeric: true),
          ImdCol('التراكمي', numeric: true),
        ],
        rows: [
          for (final d in _variance)
            [
              Text(arDigits(d.date)),
              Text(nf(d.actual)),
              Text(nf(d.average)),
              Text(
                '${d.variance > 0 ? '+' : ''}${nf(d.variance)}',
                style: TextStyle(
                  color: d.isCredit
                      ? context.imd.success
                      : (d.isDebit ? context.imd.danger : context.imd.muted),
                ),
              ),
              Text(nf(d.cumulative)),
            ],
        ],
      ),
    ]);
  }

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  static String _monthName(int m) => _months[(m - 1).clamp(0, 11)];
}
