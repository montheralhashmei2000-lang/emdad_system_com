part of '../fuel_moves_screen.dart';

/// تبويب التوريد: النموذج والسجل.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesSupply on _FuelMovesBase, _FuelMovesShared {
  // ───────────────────────── التوريد

  List<Widget> _supplyForm() => [
        ImdPanel(
          title: 'بيانات التوريد',
          icon: 'download',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _fuelField(),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('تاريخ التوريد *'),
              ImdLabeled(
                'جهة التوريد *',
                ImdFld(controller: _supplier, hint: 'اسم المورد / الجهة'),
                size: 11,
              ),
              _warehouseField('المخزن المستلم *'),
              ImdLabeled(
                'نوع الوسيلة',
                ImdFld(controller: _transport, hint: 'صهريج / شاحنة'),
                size: 11,
              ),
              ImdLabeled('اسم السائق', ImdFld(controller: _driver), size: 11),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip('الرصيد الحالي: ${nf(_available)} ${Fuel.unit}'),
              if (_capacity > 0) ...[
                ImdChip('السعة ${nf(_capacity)} ${Fuel.unit}',
                    tone: ImdTone.off),
                ImdChip(
                  'المتبقي '
                  '${nf(_capacity - _available < 0 ? 0 : _capacity - _available)} '
                  '${Fuel.unit}',
                  tone: ImdTone.info,
                ),
              ],
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  List<Widget> _supplyLog() {
    final c = context.imd;
    final rows = _search(_supplies,
        (s) => '${s.refNo} ${s.supplierName} ${s.driverName} ${s.warehouse}');
    return [
      ImdPanel(
        title: 'آخر التوريدات',
        icon: 'list',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث برقم السند أو الجهة…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ImdTable(
            empty: 'لا توريد بعد',
            minWidth: 900,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المخزن المستلم'),
              ImdCol('جهة التوريد'),
              ImdCol('الوسيلة'),
              ImdCol('الكمية', numeric: true),
              ImdCol('', center: true),
            ],
            pageSize: 100,
            rows: [
              for (final s in rows)
                [
                  Text(s.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(s.date)),
                  ImdChip(FuelType.label(s.fuelType),
                      tone: s.fuelType == FuelType.diesel
                          ? ImdTone.code
                          : ImdTone.info),
                  Text(s.warehouse),
                  Text(s.supplierName.isEmpty ? '—' : s.supplierName),
                  Text(s.transportVehicleType.isEmpty
                      ? '—'
                      : s.transportVehicleType),
                  Text('${nf(s.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () {
                if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                FuelPrint.supplyVoucher(_db, s);
              }),
                ],
            ],
          ),
        ]),
      ),
    ];
  }
}
