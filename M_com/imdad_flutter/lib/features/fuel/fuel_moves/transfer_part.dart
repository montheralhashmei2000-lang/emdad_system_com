part of '../fuel_moves_screen.dart';

/// تبويب التحويل: النموذج والسجل.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesTransfer on _FuelMovesBase, _FuelMovesActions, _FuelMovesShared {
  // ───────────────────────── التحويل

  List<Widget> _transferForm() => [
        ImdPanel(
          title: 'سند تحويل مخزني جديد',
          icon: 'swap',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _warehouseField('من مستودع *'),
              ImdLabeled(
                'إلى مستودع *',
                ImdSelect<String>(
                  items: [
                    ('', '— اختر —'),
                    for (final w in _warehouses)
                      if (w.name != _warehouse) (w.name, w.name),
                  ],
                  value: _toWarehouse,
                  onChanged: (v) => setState(() => _toWarehouse = v ?? ''),
                ),
                size: 11,
              ),
              _fuelField(label: 'الصنف *'),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('التاريخ *'),
              ImdLabeled('السائق', ImdFld(controller: _driver), size: 11),
              ImdLabeled('وسيلة النقل', ImdFld(controller: _transport),
                  size: 11),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip(
                'المتاح في المصدر: ${nf(_available)} ${Fuel.unit}',
                tone: _available <= 0 ? ImdTone.err : ImdTone.ok,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  List<Widget> _transferLog() {
    final c = context.imd;
    if (_transfers.isEmpty) {
      return const [
        ImdEmptyState.noData(
          title: 'لا توجد تحويلات بعد',
          message: 'استخدم النموذج أعلاه لنقل الرصيد',
        ),
      ];
    }
    return [
      ImdPanel(
        title: 'سجل التحويل',
        icon: 'list',
        child: ImdTable(
          empty: 'لا تحويلات بعد',
          minWidth: 980,
          columns: const [
            ImdCol('السند'),
            ImdCol('التاريخ'),
            ImdCol('النوع'),
            ImdCol('من ← إلى'),
            ImdCol('السائق'),
            ImdCol('الكمية', numeric: true),
            ImdCol('الحالة'),
            ImdCol('', center: true),
          ],
          pageSize: 100,
          rows: [
            for (final t in _transfers)
              [
                Text(t.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
                Text(arDigits(t.date)),
                ImdChip(FuelType.label(t.fuelType),
                    tone: t.fuelType == FuelType.diesel
                        ? ImdTone.code
                        : ImdTone.info),
                Text('${t.fromWarehouse} ← ${t.toWarehouse}'),
                Text(t.driverName.isEmpty ? '—' : t.driverName),
                Text('${nf(t.quantityLiters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (FuelRepo.isReverse(t.notes))
                    const ImdChip('عكس', tone: ImdTone.pend),
                  if (FuelRepo.reversedAlready(_transfers, t.refNo))
                    const ImdChip('معكوس', tone: ImdTone.off),
                ]),
                Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () {
                if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                FuelPrint.transferVoucher(_db, t);
              }),
                  if (!FuelRepo.isReverse(t.notes) &&
                      !FuelRepo.reversedAlready(_transfers, t.refNo))
                    ImdIconButton(
                        icon: 'undo',
                        tooltip: 'عكس السند',
                        onPressed: () => _reverse(t)),
                ]),
              ],
          ],
        ),
      ),
    ];
  }
}
