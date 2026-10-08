part of '../fuel_moves_screen.dart';

/// تبويب الرصيد الافتتاحي: النموذج والسجل.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesOpening on _FuelMovesBase, _FuelMovesActions, _FuelMovesShared {
  // ───────────────────────── الرصيد الافتتاحي

  List<Widget> _openingForm() => [
        ImdPanel(
          title: 'رصيد افتتاحي جديد',
          icon: 'compass',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _warehouseField('المستودع *'),
              _fuelField(label: 'الصنف *'),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('اعتبارًا من *'),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظة', ImdFld(controller: _notes, maxLines: 2)),
            const SizedBox(height: 10),
            const ImdNote(
              'الرصيد الافتتاحي هو ما كان في الخزّان **قبل أن يبدأ '
              'النظام**. ولا يُستعمل لتصحيح فرقٍ بعد التشغيل — ذلك بابه '
              'الجرد، فيبقى له أثرٌ ولجنةٌ وتاريخ.',
            ),
          ]),
        ),
      ];

  List<Widget> _openingLog() {
    final c = context.imd;
    final can = Perm.of(context).writable('fuelMoves');
    return [
      ImdPanel(
        title: 'الأرصدة الافتتاحية',
        icon: 'list',
        child: ImdTable(
          empty: 'لا أرصدة افتتاحية — أدخل أرصدة بداية الفترة لتصح التقارير',
          minWidth: 780,
          columns: const [
            ImdCol('المستودع'),
            ImdCol('الصنف'),
            ImdCol('اعتبارًا من'),
            ImdCol('الرصيد', numeric: true),
            ImdCol('ملاحظة'),
            ImdCol('', center: true),
          ],
          pageSize: 100,
          rows: [
            for (final o in _openings)
              [
                Text(o.warehouse,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdChip(FuelType.label(o.fuelType),
                    tone: o.fuelType == FuelType.diesel
                        ? ImdTone.code
                        : ImdTone.info),
                Text(arDigits(o.asOfDate)),
                Text('${nf(o.liters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(o.note.isEmpty ? '—' : o.note,
                    style: TextStyle(color: c.muted)),
                if (can)
                  ImdIconButton(
                      icon: 'trash',
                      tooltip: 'حذف',
                      onPressed: () => _deleteOpening(o))
                else
                  const SizedBox.shrink(),
              ],
          ],
        ),
      ),
    ];
  }
}
