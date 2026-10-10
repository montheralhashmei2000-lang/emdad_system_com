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
import 'fuel_print.dart';
import '../inventory/doc_kit/imd_sticky_page.dart';

/// أرصدة المستودعات — مكوّنات الرصيد لا الرصيد وحده.
///
/// **الرقم وحده لا يُراجَع.** أمينٌ يقول «عندي تسعة عشر ألفًا» لا يُصدَّق ولا
/// يُكذَّب؛ أما «افتتاحي ٢٥٬٠٠٠ + توريد ١٢٬٠٠٠ − صرف ٥٬١٥٩ − محوَّل ٢٬٠٠٠»
/// فمعادلةٌ تُطابَق سطرًا سطرًا مع السندات.
class FuelStocksReportScreen extends StatefulWidget {
  const FuelStocksReportScreen({super.key});

  @override
  State<FuelStocksReportScreen> createState() => _FuelStocksReportScreenState();
}


class _FuelStocksReportScreenState extends State<FuelStocksReportScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelStock> _stocks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stocks = await _repo.stocks();
    if (!mounted) return;
    setState(() {
      _stocks = stocks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'أرصدة المستودعات', icon: 'package'),
        ImdLd('⏳ جارٍ الحساب…'),
      ]);
    }
    final c = context.imd;
    double sum(double Function(FuelStock) of) =>
        _stocks.fold<double>(0, (t, s) => t + of(s));

    // كشاشات الإمداد: أزرار التقرير في شريطٍ ملتصق بالأسفل، والنتائج تمرّ تحته.
    return ImdStickyPage(
      sticky: ImdStickyActions(children: [
        ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
        ImdButton(
          label: 'طباعة الكشف',
          icon: 'printer',
          onPressed: () {
            if (!Perm.of(context).guard(context, 'fuelReports', 'print')) return;
            FuelPrint.stocksReport(_db, _stocks);
          },
        ),
      ]),
      after: [
        const SizedBox(height: 14),
      ImdPanel(
        title: 'مكوّنات الرصيد — محسوبة من السندات',
        icon: 'package',
        child: ImdTable(
          empty: 'لا مستودعات محروقات بعد',
          minWidth: 980,
          columns: const [
            ImdCol('المستودع'),
            ImdCol('الصنف'),
            ImdCol('الافتتاحي', numeric: true),
            ImdCol('التوريد', numeric: true),
            ImdCol('محوَّل إليه', numeric: true),
            ImdCol('محوَّل منه', numeric: true),
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
                Text(nf(s.transferredIn)),
                Text(s.transferredOut == 0 ? '—' : '−${nf(s.transferredOut)}'),
                Text(s.issued == 0 ? '—' : '−${nf(s.issued)}'),
                Text(s.adjustments == 0 ? '—' : nf(s.adjustments),
                    style:
                        TextStyle(color: s.adjustments < 0 ? c.danger : c.muted)),
                Text('${nf(s.stock)} ${Fuel.unit}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: s.empty ? c.danger : c.text)),
              ],
          ],
          footer: [
            const Text('الإجمالي',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Text(''),
            Text(nf(sum((s) => s.opening)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(sum((s) => s.supplied)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(sum((s) => s.transferredIn)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(sum((s) => s.transferredOut)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(sum((s) => s.issued)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(nf(sum((s) => s.adjustments)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${nf(sum((s) => s.stock))} ${Fuel.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      ],
      children: [
      const ImdPageTitle(
        title: 'أرصدة المستودعات',
        icon: 'package',
        subtitle: 'الافتتاحي + التوريد + المحوَّل إليه − المحوَّل منه − '
            'المصروف ± فرق الجرد = الرصيد الحالي',
      ),
      ImdKpis(children: [
        ImdKpi(
            label: 'الرصيد الكلي',
            value: '${nf(sum((s) => s.stock))} ${Fuel.unit}'),
        ImdKpi(
            label: 'بترول',
            value: nf(_stocks
                .where((s) => s.fuelType == FuelType.petrol)
                .fold<double>(0, (t, s) => t + s.stock))),
        ImdKpi(
            label: 'ديزل',
            value: nf(_stocks
                .where((s) => s.fuelType == FuelType.diesel)
                .fold<double>(0, (t, s) => t + s.stock))),
        ImdKpi(
          label: 'خانات فارغة',
          value: nf(_stocks.where((s) => s.empty).length),
          extra: _stocks.any((s) => s.empty)
              ? const ImdChip('لا يُصرف منها', tone: ImdTone.err)
              : null,
        ),
      ]),
      ],
    );
  }
}
