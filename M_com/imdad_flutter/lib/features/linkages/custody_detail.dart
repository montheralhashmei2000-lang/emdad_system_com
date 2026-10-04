import 'package:flutter/material.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/print/print_format.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/finance.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// تفاصيل العهدة: ملخص مالي وتبويباتها الفرعية. تبويب «العقود المرتبطة» يعرض كل
/// العقود التي استخدمت هذه العهدة بتصنيفها ومحلها وعملتها وإجماليها وتاريخها
/// ورقم فاتورتها، ومجموعها محوَّلًا إلى عملة العهدة.
class CustodyDetail extends StatefulWidget {
  const CustodyDetail({super.key, required this.repo, required this.custodyId});

  final LinkageRepo repo;
  final String custodyId;

  @override
  State<CustodyDetail> createState() => _CustodyDetailState();
}

class _CustodyDetailState extends State<CustodyDetail> {
  String _tab = 'contracts';
  LinkFinCustody? _custody;
  List<LinkPurchaseContract> _contracts = const [];
  CustodyUsage _usage = const CustodyUsage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.repo.custodies();
    final c = all.where((x) => x.id == widget.custodyId).firstOrNull;
    final contracts = await widget.repo.contractsOfCustody(widget.custodyId);
    final usage = (await widget.repo.custodyUsage())[widget.custodyId] ?? const CustodyUsage();
    if (!mounted) return;
    setState(() {
      _custody = c;
      _contracts = contracts;
      _usage = usage;
    });
  }

  /// مبلغ العقد بعملة العهدة، أو null إن تعذّر التحويل.
  double? _inCustodyCurrency(LinkFinCustody c, LinkPurchaseContract k) =>
      convertAmount(k.amount, from: k.currency, to: c.currency, rate: k.exchangeRate > 0 ? k.exchangeRate : c.exchangeRate);

  @override
  Widget build(BuildContext context) {
    final t = context.imd;
    final c = _custody;
    if (c == null) return const ImdLd('جارٍ التحميل…');
    final cur = FinCurrency.short(c.currency);
    final remaining = c.amount - _usage.consumed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        ImdChip(c.custodyNo, tone: ImdTone.code),
        ImdChip(CustodyKind.label(c.kind), tone: c.kind == CustodyKind.received ? ImdTone.info : ImdTone.pend),
        ImdChip(CustodyStatus.label(c.status), tone: c.status == CustodyStatus.open ? ImdTone.pend : c.status == CustodyStatus.cleared ? ImdTone.ok : ImdTone.off),
      ]),
      const SizedBox(height: 8),
      Text(c.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.text)),
      const SizedBox(height: 10),
      ImdKpis(children: [
        ImdKpi(label: 'مبلغ العهدة', value: '${nf(c.amount)} $cur', icon: 'dollar', color: t.accent),
        ImdKpi(label: 'المستهلك (العقود)', value: '${nf(_usage.consumed)} $cur', icon: 'clipboard', color: t.info),
        ImdKpi(label: 'المتبقي', value: '${nf(remaining)} $cur', icon: 'scale', color: remaining < 0 ? t.danger : t.success),
        ImdKpi(label: 'عدد العقود', value: nf(_usage.contracts), icon: 'file', color: t.muted),
      ]),
      const SizedBox(height: 10),
      ImdSegmented<String>(
        tabs: const [ImdTab('contracts', 'العقود المرتبطة', icon: 'clipboard')],
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      const SizedBox(height: 10),
      if (_usage.unconvertible > 0)
        ImdNote('${nf(_usage.unconvertible)} عقد بعملة تخالف عملة العهدة ولا سعر صرف له — لم يُحتسب في المستهلك.'),
      if (_contracts.isEmpty)
        const ImdEmptyBox('لا عقود مرتبطة بهذه العهدة — اختر العهدة في حقل «العهدة المرتبطة» بمحرر العقد')
      else
        ImdTable(
          columns: const [
            ImdCol('رقم العقد'),
            ImdCol('التصنيف', flex: 2),
            ImdCol('المحل / التاجر', flex: 2),
            ImdCol('العملة'),
            ImdCol('الإجمالي', numeric: true),
            ImdCol('بعملة العهدة', numeric: true),
            ImdCol('التاريخ'),
            ImdCol('رقم الفاتورة'),
          ],
          rows: [
            for (final k in _contracts)
              [
                Text(k.contractNo.isEmpty ? '—' : k.contractNo),
                Text(k.title, style: TextStyle(fontWeight: FontWeight.w600, color: t.text)),
                Text(k.supplier.isEmpty ? '—' : k.supplier),
                ImdChip(LinkCurrency.label(k.currency), tone: k.currency == LinkCurrency.yer ? ImdTone.pend : ImdTone.info),
                Text(printNum(k.amount)),
                Text(_inCustodyCurrency(c, k) == null ? 'يلزم سعر صرف' : printNum(_inCustodyCurrency(c, k)!)),
                Text(_d(k.listDate)),
                Text(k.displayInvoiceNo.isEmpty ? '—' : k.displayInvoiceNo),
              ],
          ],
          cards: true,
          empty: 'لا عقود',
          onRowTap: null,
        ),
    ]);
  }
}
