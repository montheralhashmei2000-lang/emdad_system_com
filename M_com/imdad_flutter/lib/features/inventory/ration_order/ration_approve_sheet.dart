part of '../ration_order_screen.dart';

/// ورقة الاعتماد: سطرًا سطرًا، بالمطلوب والمتاح والمعتمَد.
///
/// كان الاعتماد إقرارًا للمطلوب كلّه بضغطة، مع أن [RationRepo.approve] يقبل
/// كمياتٍ مقلَّصة و[RationRules.validateApproved] يحرسها. فكانت القدرة موجودة
/// في الطبقات ولا سبيل إليها من الشاشة.
class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.full, required this.available});

  final RationOrderFull full;

  /// رصيد المستودع المورِّد لكل صنف.
  final Map<String, double> available;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  late final Map<String, TextEditingController> _qty = {
    for (final l in widget.full.lines)
      l.id: TextEditingController(text: '${l.requestedQty}'),
  };

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _valueOf(String lineId) =>
      double.tryParse((_qty[lineId]?.text ?? '').trim()) ?? 0;

  double _availableFor(RationOrderLine l) => widget.available[l.itemId] ?? 0;

  void _setAll(double Function(RationOrderLine) pick) {
    setState(() {
      for (final l in widget.full.lines) {
        imdSetText(_qty[l.id]!, '${pick(l)}');
      }
    });
  }

  /// أخطاء تمنع الاعتماد — تُحسب من قاعدة المجال نفسها لا من نسخةٍ منها.
  String? get _error => RationRules.validateApproved([
        for (final l in widget.full.lines)
          RationLineDraft(
            itemId: l.itemId,
            requestedQty: l.requestedQty,
            approvedQty: _valueOf(l.id),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final lines = widget.full.lines;
    final error = _error;
    final total = lines.fold<double>(0, (s, l) => s + _valueOf(l.id));
    final short = lines.where((l) => _valueOf(l.id) > _availableFor(l)).length;
    final cut = lines.where((l) => _valueOf(l.id) < l.requestedQty).length;
    final empty = lines.every((l) => _valueOf(l.id) <= 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'المورِّد «${widget.full.order.supplyingWarehouse}» — '
          'الكمية المعتمدة لا تتجاوز المطلوبة، وقد تقلّ عنها.',
          style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.6),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ImdButton.outline(
            label: 'اعتماد كامل المطلوب',
            icon: 'check',
            small: true,
            onPressed: () => _setAll((l) => l.requestedQty),
          ),
          ImdButton.outline(
            label: 'تقليص إلى المتاح',
            icon: 'scale',
            small: true,
            onPressed: () => _setAll(
              (l) => l.requestedQty < _availableFor(l)
                  ? l.requestedQty
                  : _availableFor(l),
            ),
          ),
          ImdButton.outline(
            label: 'تصفير الكل',
            icon: 'x',
            small: true,
            onPressed: () => _setAll((_) => 0),
          ),
        ]),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in lines) _lineRow(l),
              ],
            ),
          ),
        ),
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Text(
              [
                'الإجمالي المعتمد: ${nf(total)}',
                if (cut > 0) 'مقلَّص: $cut سطرًا',
                if (short > 0) 'يتجاوز رصيد المورِّد: $short سطرًا',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12.5,
                color: short > 0 ? c.danger : c.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text('✖ $error',
              style: TextStyle(
                  fontSize: 12.5, color: c.danger, fontWeight: FontWeight.w600)),
        ] else if (empty) ...[
          const SizedBox(height: 8),
          Text(
            '✖ كل السطور بصفر — لا شيء يُستلم. اعتمد كميةً أو ارفض الطلبية.',
            style: TextStyle(
                fontSize: 12.5, color: c.danger, fontWeight: FontWeight.w600),
          ),
        ] else if (short > 0) ...[
          const SizedBox(height: 8),
          Text(
            '⚠ الاعتماد يتجاوز رصيد المورِّد — سيُرفض السند عند الاستلام إن لم '
            'يصل التوريد قبله.',
            style: TextStyle(fontSize: 12.5, color: c.warn, height: 1.6),
          ),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ImdButton.outline(
              label: 'إلغاء', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          ImdButton(
            label: 'اعتماد',
            icon: 'check',
            onPressed: error != null || empty
                ? null
                : () => Navigator.of(context).pop({
                      for (final l in lines) l.id: _valueOf(l.id),
                    }),
          ),
        ]),
      ],
    );
  }

  Widget _lineRow(RationOrderLine l) {
    final c = context.imd;
    final have = _availableFor(l);
    final want = _valueOf(l.id);
    final over = want > have;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l.itemCode} · ${l.itemName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                'مطلوب ${nf(l.requestedQty)} ${l.unitName} · '
                'متاح ${nf(have)}',
                style: TextStyle(
                    fontSize: 11.5, color: over ? c.danger : c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: ImdFld(
            controller: _qty[l.id]!,
            number: true,
            hint: 'معتمد',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 6),
        ImdIconButton(
          icon: 'scale',
          tooltip: 'اجعلها المتاح',
          onPressed: () => setState(() => imdSetText(
              _qty[l.id]!, '${l.requestedQty < have ? l.requestedQty : have}')),
        ),
      ]),
    );
  }
}
