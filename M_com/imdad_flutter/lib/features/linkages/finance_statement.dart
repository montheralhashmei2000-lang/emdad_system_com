import 'package:flutter/material.dart';

import '../../core/print/document_pdf.dart';
import '../../core/print/print_format.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/repos/linkage_repo.dart';
import 'link_export.dart';
import '../../domain/finance.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// رصيد المالية كنصٍّ مختصر لكل عملة: «−5,000 ر.س · +200 ر.ي».
String financeBalanceText(Map<String, double>? balance) {
  if (balance == null) return '—';
  final parts = [
    for (final e in balance.entries)
      if (e.value.abs() >= 0.005) '${e.value < 0 ? '−' : '+'}${printNum(e.value.abs())} ${FinCurrency.short(e.key)}',
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// كشف حساب مالية لصاحب عهدة.
///
/// * عهده القائمة: المستلمة مدين (−)، والمسلَّمة دائن (+).
/// * الفوائض (+) والعجوزات (−) المعتمدة، وما عُكس منها بإلغاء إخلاء.
/// * الرصيد النهائي لكل عملةٍ على حدة — لا يُجمع يمنيٌّ وسعوديٌّ.
class FinanceStatement extends StatefulWidget {
  const FinanceStatement({super.key, required this.repo, required this.names, this.party = '', this.canExport = false, this.canPrint = false});

  final LinkageRepo repo;
  final List<String> names;
  final String party;

  /// صلاحيتا التصدير والطباعة تُمرَّران من الشاشة؛ الافتراضي مغلق.
  final bool canExport;
  final bool canPrint;

  @override
  State<FinanceStatement> createState() => _FinanceStatementState();
}

class _FinanceStatementState extends State<FinanceStatement> {
  late String _party = widget.party;
  PartyStatement? _st;

  @override
  void initState() {
    super.initState();
    if (_party.isNotEmpty) _load();
  }

  Future<void> _load() async {
    final st = await widget.repo.partyStatement(_party);
    if (mounted) setState(() => _st = st);
  }

  static const _kindLabels = {
    'received': 'عهدة مستلمة',
    'delivered': 'عهدة مسلَّمة',
    'surplus': 'فائض',
    'deficit': 'عجز',
    'reversal': 'عكس',
  };

  List<List<String>> _rows(PartyStatement st) => [
        for (final l in st.lines)
          [
            _d(l.date),
            _kindLabels[l.kind] ?? l.kind,
            l.label,
            l.delta < 0 ? printNum(-l.delta) : '',
            l.delta > 0 ? printNum(l.delta) : '',
            FinCurrency.label(l.currency),
          ],
      ];

  String _balanceNote(PartyStatement st) =>
      st.balance.isEmpty ? 'الرصيد: صفر' : 'الرصيد: ${financeBalanceText(st.balance)}';

  Future<void> _export(PartyStatement st) => linkExportExcel(
        context,
        sheetName: 'كشف حساب مالية',
        fileName: 'كشف-حساب-${st.party}-${isoDay(DateTime.now())}.xlsx',
        headers: const ['التاريخ', 'النوع', 'البيان', 'المدين (−)', 'الدائن (+)', 'العملة'],
        rows: [..._rows(st), ['', '', _balanceNote(st), '', '', '']],
        numericColumns: const {3, 4},
      );

  Future<void> _print(PartyStatement st) async {
    try {
      await DocumentPdf.printDoc(
        doc: PrintDoc(
          title: 'كشف حساب مالية — ${st.party}',
          headers: const ['التاريخ', 'النوع', 'البيان', 'المدين (−)', 'الدائن (+)', 'العملة'],
          columnFlex: const [2, 2, 7, 2, 2, 2],
          rows: _rows(st),
          footerNote: '${_balanceNote(st)} · ${arDate(DateTime.now())}',
          signatureLines: const ['صاحب الحساب\n....................', 'المراجع المالي\n....................'],
        ),
      );
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final st = _st;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdLabeled(
        'صاحب العهدة',
        ImdSelect<String>(
          items: [('', 'اختر…'), for (final n in {...widget.names, if (_party.isNotEmpty) _party}) (n, n)],
          value: _party,
          onChanged: (v) {
            setState(() {
              _party = v ?? '';
              _st = null;
            });
            if (_party.isNotEmpty) _load();
          },
        ),
      ),
      const SizedBox(height: 10),
      if (st == null)
        const ImdEmptyBox('اختر صاحب العهدة لعرض كشف حسابه')
      else ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in st.balance.entries)
            ImdChip(
              'الرصيد (${FinCurrency.label(e.key)}): ${e.value < 0 ? '−' : '+'}${printNum(e.value.abs())} ${FinCurrency.short(e.key)}',
              tone: e.value < 0 ? ImdTone.err : ImdTone.ok,
            ),
          if (st.balance.isEmpty) const ImdChip('الرصيد: صفر', tone: ImdTone.off),
        ]),
        if (widget.canExport || widget.canPrint) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.canPrint) ImdButton.outline(label: 'طباعة الكشف', icon: 'printer', small: true, onPressed: () => _print(st)),
            if (widget.canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: () => _export(st)),
          ]),
        ],
        const SizedBox(height: 4),
        Text('الموجب لصاحب العهدة (دائن) والسالب عليه (مدين). العهد المُخلَّاة تدخل بفائضها أو عجزها فقط.',
            style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 8),
        if (st.lines.isEmpty)
          const ImdEmptyBox('لا حركة على هذا الحساب')
        else
          ImdTable(
            pageSize: 50,
            columns: const [
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('البيان', flex: 3),
              ImdCol('المدين (−)', numeric: true),
              ImdCol('الدائن (+)', numeric: true),
              ImdCol('العملة'),
            ],
            rows: [
              for (final l in st.lines)
                [
                  Text(_d(l.date)),
                  ImdChip(_kindLabels[l.kind] ?? l.kind, tone: l.delta < 0 ? ImdTone.err : ImdTone.ok),
                  Text(l.label),
                  Text(l.delta < 0 ? printNum(-l.delta) : '—'),
                  Text(l.delta > 0 ? printNum(l.delta) : '—'),
                  Text(FinCurrency.label(l.currency)),
                ],
            ],
            empty: 'لا حركة',
            onRowTap: null,
          ),
      ],
    ]);
  }
}
