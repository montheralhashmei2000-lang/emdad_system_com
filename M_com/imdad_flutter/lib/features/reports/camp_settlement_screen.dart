import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/camp_ledger_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/camp_ledger.dart';

/// تصفية الشهر: إغلاق سجلات المعسكرات وترحيل رصيديها إلى الشهر التالي.
class CampSettlementScreen extends StatefulWidget {
  const CampSettlementScreen({super.key});

  @override
  State<CampSettlementScreen> createState() => _CampSettlementScreenState();
}

class _CampSettlementScreenState extends State<CampSettlementScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CampLedgerRepo _repo = CampLedgerRepo(_db);

  List<MonthlySettlement> _history = const [];
  List<CampLedgerRow> _preview = const [];

  int _year = DateTime.now().year;
  int _month = DateTime.now().month == 1 ? 12 : DateTime.now().month - 1;
  bool _loading = true;
  bool _busy = false;
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final history = await _repo.settlements();
    final preview = await _repo.ledgers(year: _year, month: _month);
    final auto = await _repo.isAutoSettle();
    if (!mounted) return;
    setState(() {
      _history = history;
      _preview = preview;
      _auto = auto;
      _loading = false;
      _busy = false;
    });
  }

  bool get _alreadySettled =>
      _history.any((h) => h.year == _year && h.month == _month);

  bool get _monthEnded {
    final today = DateTime.now();
    final end = DateTime(_year, _month + 1, 0);
    return !end.isAfter(DateTime(today.year, today.month, today.day));
  }

  Future<void> _settle() async {
    if (!Perm.of(context).guard(context, 'campSettlement', PermAction.approve)) return;
    final t = CampLedgerCalc.totals([for (final r in _preview) r.amounts]);
    final ok = await imdConfirm(
      context,
      'تصفية $_month/$_year:\n\n'
      '• تُغلق ${nf(_preview.length)} سطرًا فلا تُبنى من جديد\n'
      '• يُرحَّل رصيد الاستحقاق (${nf(t.net)}) ورصيد المخزون (${nf(t.stock)}) '
      'إلى الشهر التالي\n\n'
      'التصفية لا تُلغى. تابع؟',
      ok: 'تصفية الآن',
      cancel: 'مراجعة',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final res = await _repo.closeMonth(
      year: _year,
      month: _month,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      showImdToast(context, res.error, error: true);
      return;
    }
    showImdToast(
      context,
      '✔ صُفّي ${nf(res.camps)} معسكرًا و${nf(res.items)} صنفًا — '
      'رُحّلت الأرصدة إلى ${res.nextMonth}/${res.nextYear}',
    );
    await _load();
  }

  /// تفعيل التصفية التلقائية أو إطفاؤها.
  ///
  /// دالةٌ على الحالة لا مغلقةٌ داخل `build`: السياق هنا هو `State.context`،
  /// فحارس `mounted` يحرسه هو نفسه لا سياقًا آخر.
  Future<void> _toggleAuto(bool v) async {
    if (v &&
        !await imdConfirm(
          context,
          'التصفية التلقائية تُغلق سجلات الشهر المنقضي بلا سؤال، والإغلاق لا '
          'رجعة فيه.\n\n'
          'تُنفَّذ فقط بعد انقضاء الشهر كاملًا، ولشهر واحد في كل مرة. تفعيلها؟',
          ok: 'تفعيل',
          danger: true,
        )) {
      return;
    }
    await _repo.setAutoSettle(v);
    if (!mounted) return;
    setState(() => _auto = v);
    showImdToast(
      context,
      v ? '✔ فُعّلت التصفية التلقائية' : '✔ أُطفئت التصفية التلقائية',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تصفية الشهر', icon: 'lock'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final t = CampLedgerCalc.totals([for (final r in _preview) r.amounts]);
    final open = _preview.where((r) => r.ledger.status == 'OPEN').length;
    final blocked = _alreadySettled || !_monthEnded || open == 0;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'تصفية الشهر',
        icon: 'lock',
        subtitle: 'إغلاق سجلات المعسكرات للشهر وترحيل رصيدَي الاستحقاق والمخزون '
            'إلى الشهر التالي',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled(
              'الشهر',
              ImdSelect<int>(
                items: [for (var m = 1; m <= 12; m++) (m, _monthName(m))],
                value: _month,
                onChanged: (v) {
                  setState(() => _month = v ?? 1);
                  _load();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'السنة',
              ImdSelect<int>(
                items: [
                  for (var y = DateTime.now().year - 3; y <= DateTime.now().year; y++)
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
            ImdChip('سطور مفتوحة: ${nf(open)}', tone: open > 0 ? ImdTone.ok : ImdTone.off),
            if (_alreadySettled) const ImdChip('مُصفّى سلفًا', tone: ImdTone.code),
            if (!_monthEnded) const ImdChip('الشهر لم ينتهِ', tone: ImdTone.pend),
          ]),
        ]),
      ),
      ImdKpis(children: [
        ImdKpi(label: 'سطور السجل', value: nf(_preview.length)),
        ImdKpi(label: 'متبقٍ لهم', value: nf(t.credit)),
        ImdKpi(label: 'متبقٍ عليهم', value: nf(t.debit)),
        ImdKpi(
          label: 'الصافي المُرحَّل',
          value: nf(t.net.abs()),
          extra: ImdChip(
            t.net >= 0 ? 'لصالح المعسكرات' : 'على المعسكرات',
            tone: t.net >= 0 ? ImdTone.ok : ImdTone.err,
          ),
        ),
        ImdKpi(label: 'مخزون مُرحَّل', value: nf(t.stock)),
      ]),
      ImdPanel(
        title: 'التصفية',
        icon: 'lock',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_monthEnded)
            const ImdNote('**لا يُصفّى شهر لم ينتهِ.** التصفية تُثبّت أرقامًا يُبنى '
                'عليها الشهر التالي، وتثبيتها قبل آخر يوم يُسقط حركات لم تقع بعد.')
          else if (_alreadySettled)
            const ImdNote('هذا الشهر مُصفّى، وسطوره مثبّتة. أرقامه صارت أساس الشهر '
                'التالي فلا تُعاد تصفيته.')
          else if (open == 0)
            const ImdNote('لا سطور مفتوحة لهذا الشهر. ابنِ السجل أولًا من «سجل حساب '
                'المعسكر» ← «إعادة بناء السجل».')
          else
            const ImdNote('تُعاد بناء السجلات قبل الإغلاق تلقائيًا، فتُثبَّت أحدث '
                'الأرقام لا أقدمها. **والتصفية لا تُلغى.**'),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
              label: 'تصفية $_month/$_year',
              icon: 'lock',
              kind: ImdBtnKind.danger,
              busy: _busy,
              onPressed: blocked ? null : _settle,
            ),
          ),
          const SizedBox(height: 16),
          ImdCheckbox(
            value: _auto,
            label: 'تصفية الشهر تلقائيًا عند فتح التطبيق بعد انقضائه',
            onChanged: _toggleAuto,
          ),
          const SizedBox(height: 6),
          const ImdNote('التصفية التلقائية **مطفأة افتراضيًا**: إجراءٌ لا يُلغى '
              'لا يعمل بلا إذن صريح. ومع إطفائها يصلك تنبيهٌ بالجرس حين ينقضي '
              'شهر ولم يُصفَّ.'),
        ]),
      ),
      ImdPanel(title: 'سجل التصفيات السابقة', icon: 'list', child: _historyTable()),
    ]);
  }

  Widget _historyTable() => ImdTable(
        empty: 'لا تصفيات سابقة',
        minWidth: 680,
        columns: const [
          ImdCol('الشهر'),
          ImdCol('التاريخ'),
          ImdCol('المعسكرات', numeric: true),
          ImdCol('الأصناف', numeric: true),
          ImdCol('متبقٍ لهم', numeric: true),
          ImdCol('متبقٍ عليهم', numeric: true),
          ImdCol('نُفّذت بواسطة'),
        ],
        rows: [
          for (final h in _history)
            [
              Text('${_monthName(h.month)} ${arDigits('${h.year}')}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(arDigits(h.settledAt.toIso8601String().substring(0, 10))),
              Text(nf(h.campsCount)),
              Text(nf(h.itemsCount)),
              Text(nf(h.totalCredit), style: TextStyle(color: context.imd.success)),
              Text(nf(h.totalDebit), style: TextStyle(color: context.imd.danger)),
              Text(h.settledBy.isEmpty ? '—' : h.settledBy),
            ],
        ],
      );

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  static String _monthName(int m) => _months[(m - 1).clamp(0, 11)];
}
