part of '../fuel_moves_screen.dart';

/// تبويب الصرف: النموذج وبطاقة الاستحقاق والسجل.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesIssue on _FuelMovesBase, _FuelMovesActions, _FuelMovesShared {
  /// أنواع الوسائل المعتادة — تُقترح ولا تُلزم.
  static const List<String> vehicles = [
    'شاص',
    'هايلوكس',
    'مولد',
    'دينة',
    'قاطرة',
    'كرار',
    'ماطور ماء',
    'ماطور الطلاء',
    'دراجة نارية',
    'وسيلة مدني',
    'باص مدني',
    'برادو',
  ];

  // ───────────────────────── الصرف

  List<Widget> _issueForm() => [
        ImdPanel(
          title: 'بيانات الصرف',
          icon: 'file',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _fuelField(),
              _warehouseField('المخزن *'),
              _dateField('التاريخ *'),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip(
                'الرصيد المتاح في المخزن: ${nf(_available)} ${Fuel.unit}',
                tone: _available <= 0 ? ImdTone.err : ImdTone.ok,
              ),
            ]),
          ]),
        ),
        ImdPanel(
          title: 'مصدر الصرف',
          icon: 'scale',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdPillTabs<String>(
              value: _source,
              onChanged: (v) => setState(() {
                _source = v;
                _allocationId = '';
                imdSetText(_orderAuthority,
                    v == FuelSource.allocation ? 'استحقاق' : '');
              }),
              tabs: [
                for (final s in FuelSource.all) ImdTab(s, FuelSource.label(s)),
              ],
            ),
            const SizedBox(height: 14),
            if (_source == FuelSource.allocation) ...[
              ImdLabeled(
                'التفريدة *',
                ImdSelect<String>(
                  items: [
                    ('', '— اختر التفريدة —'),
                    for (final a in _pickable)
                      (
                        a.allocation.id,
                        '${a.allocation.refNo} — ${a.allocation.unitName} '
                            '— ${nf(a.allocation.quantityPerPeriod)} '
                            '${Fuel.unit}'
                      ),
                  ],
                  value: _allocationId,
                  onChanged: (v) => _pickAllocation(v ?? ''),
                ),
                size: 11,
              ),
              if (_allocation != null) ...[
                const SizedBox(height: 12),
                _allocationBox(_allocation!),
              ],
            ] else ...[
              if (!_allowExceptional)
                const ImdNote(
                    'الصرف الاستثنائي **موقوف من الإعدادات** — لن يُحفظ.'),
              ImdF2(children: [
                ImdLabeled(
                  'الوحدة المستفيدة',
                  ImdSelect<String>(
                    items: [
                      ('', '— اختر الوحدة (اختياري) —'),
                      for (final u in _units) (u.id, u.name),
                    ],
                    value: _unitId,
                    onChanged: (v) => setState(() => _unitId = v ?? ''),
                  ),
                  size: 11,
                ),
              ]),
              const SizedBox(height: 10),
              ImdLabeled(
                'مبرر الأمر الاستثنائي *',
                ImdFld(
                    controller: _justification,
                    maxLines: 2,
                    hint: 'اذكر سبب الصرف الاستثنائي…'),
              ),
              const SizedBox(height: 8),
              const ImdNote(
                'الأمر الاستثنائي يخرج عن كل تفريدة، فيلزمه **مبرر وجهة '
                'أمر** ويُسجَّل في التدقيق عالي الخطورة.',
              ),
            ],
          ]),
        ),
        ImdPanel(
          title: 'الجهة المستفيدة وجهة الأمر',
          icon: 'building',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLdText('تظهر كما هي في اليومية الرسمية'),
            const SizedBox(height: 10),
            ImdF2(children: [
              ImdLabeled(
                'الجهة المستفيدة',
                ImdFld(
                    controller: _beneficiary,
                    hint: 'الاسم كما سيظهر في التقرير'),
                size: 11,
              ),
              ImdLabeled(
                'جهة الأمر',
                ImdFld(
                  controller: _orderAuthority,
                  hint: 'استحقاق / مكتب القائد',
                  suggestions: Fuel.orderAuthorities,
                ),
                size: 11,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled(
              'الغرض',
              ImdFld(
                  controller: _purpose, hint: 'إصلاح الاتصالات / تشغيل مولد…'),
            ),
          ]),
        ),
        ImdPanel(
          title: 'بيانات الوسيلة والكمية',
          icon: 'truck',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              ImdLabeled(
                'اسم السائق',
                ImdFld(controller: _driver, hint: 'اختياري'),
                size: 11,
              ),
              ImdLabeled(
                'نوع الوسيلة *',
                ImdFld(
                  controller: _vehicle,
                  hint: 'شاص / هايلوكس / مولد',
                  suggestions: vehicles,
                ),
                size: 11,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled(
              _chassisRequired ? 'رقم الشاصي *' : 'رقم الشاصي (اختياري)',
              Row(children: [
                Expanded(
                  child: ImdFld(
                    controller: _chassis,
                    hint: 'يدويًا أو بمسح الكاميرا',
                    onChanged: _onChassis,
                  ),
                ),
                if (ImdScanner.supported) ...[
                  const SizedBox(width: 8),
                  ImdScanButton(controller: _chassis, onScanned: _onChassis),
                ],
              ]),
            ),
            if (_lastForChassis != null) ...[
              const SizedBox(height: 6),
              const ImdLdText(
                  'وُجدت حركة سابقة لهذه المركبة — عُبّئ السائق ونوع '
                  'الوسيلة تلقائيًا إن كانا فارغين.'),
            ],
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  Widget _allocationBox(FuelAllocationRow a) {
    final c = context.imd;
    final err = _allocationError;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.subtle,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        _kv('الوحدة', a.allocation.unitName),
        _kv(
            'مكان الصرف',
            a.allocation.issueLocation.isEmpty
                ? '—'
                : a.allocation.issueLocation),
        _kv('الاستحقاق الأسبوعي', '${nf(Fuel.weeklyOf(a.calc))} ${Fuel.unit}'),
        _kv('الكمية المقررة',
            '${nf(a.allocation.quantityPerPeriod)} ${Fuel.unit}'),
        _kv('المتبقي من الاستحقاق', '${nf(a.remaining)} ${Fuel.unit}',
            strong: true),
        if (err != null) ...[
          const SizedBox(height: 8),
          Text(err, style: TextStyle(fontSize: 12, color: c.danger)),
        ],
      ]),
    );
  }

  Widget _kv(String k, String v, {bool strong = false}) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: c.muted)),
          Text(v,
              style: TextStyle(
                fontSize: 12.5,
                color: strong ? c.accent : c.text,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              )),
        ],
      ),
    );
  }

  List<Widget> _issueLog() {
    final c = context.imd;
    final rows = _search(
        _issues,
        (i) => '${i.refNo} ${i.chassisNo} ${i.driverName} ${i.beneficiaryName} '
            '${i.orderAuthority} ${i.purpose} ${i.warehouse}');
    return [
      ImdPanel(
        title: 'سجل الصرف',
        icon: 'list',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث برقم السند أو الجهة أو الشاصي…',
            onChanged: (_) => setState(() {}),
            actions: [
              ImdButton.outline(
                label: 'طباعة كشف الصرف',
                icon: 'printer',
                small: true,
                onPressed: () {
                  if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                  if (_issues.isEmpty) {
                    showImdToast(context, '✖ لا سندات للطباعة');
                  } else {
                    FuelPrint.issuesReport(_db, rows);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ImdTable(
            empty: 'لا صرف بعد',
            minWidth: 1000,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المستودع'),
              ImdCol('الجهة المستفيدة'),
              ImdCol('جهة الأمر'),
              ImdCol('الوسيلة'),
              ImdCol('الكمية', numeric: true),
              ImdCol('', center: true),
            ],
            pageSize: 100,
            rows: [
              for (final i in rows)
                [
                  Text(i.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(i.date)),
                  ImdChip(FuelType.label(i.fuelType),
                      tone: i.fuelType == FuelType.diesel
                          ? ImdTone.code
                          : ImdTone.info),
                  Text(i.warehouse),
                  Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
                  i.source == FuelSource.exceptional
                      ? ImdChip(
                          i.orderAuthority.isEmpty
                              ? 'أمر استثنائي'
                              : i.orderAuthority,
                          tone: ImdTone.pend)
                      : Text(i.orderAuthority.isEmpty
                          ? 'استحقاق'
                          : i.orderAuthority),
                  Text(i.vehicleType.isEmpty ? '—' : i.vehicleType),
                  Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () => _printIssue(i)),
                ],
            ],
          ),
        ]),
      ),
    ];
  }
}
