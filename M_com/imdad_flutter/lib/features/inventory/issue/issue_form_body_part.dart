part of '../issue_screen.dart';

/// جسم نموذج الصرف (البطاقات والجدول والفحص).
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueFormBody on _IssueBase, _IssueBeneficiary, _IssueAutosave, _IssueRows, _IssueSubmit, _IssueRowsView {
  List<Widget> _formBody(BuildContext context) {
    final c = context.imd;
    final headerReady = IssueRules.headerProblems(_header, today: DateTime.now()).isEmpty;
    final collected = _collect();
    final hasRows = _rows.any((row) => row.itemId.isNotEmpty);
    final hasErrors = _validate().any((x) => x.level == 'err');
    final activeStep = !headerReady
        ? 0
        : !hasRows
            ? 1
            : (collected.err.isNotEmpty || hasErrors)
                ? 2
                : 3;
    const nextSteps = [
      'أكمل المستودع والجهة المستفيدة وتأكد من صحة التاريخ.',
      'أضف صنفًا واحدًا على الأقل وحدد وحدته وكميته.',
      'راجع الرصيد والاستحقاق والملاحظات قبل الإرسال.',
      'اكتمل التحقق. اختر الحفظ كمسودة أو الإرسال أو التنفيذ النهائي.',
    ];
    final camps = _units.where((u) => u.parentId.isEmpty).toList();
    final whOpts = _whsForCamp(_parent);
    final campFiltered = _parent.isEmpty ? <Warehouse>[] : _whs.where((w) => _feeds(w, _parent)).toList();
    final whNote = _parent.isEmpty
        ? ''
        : (campFiltered.isNotEmpty
            ? '🏕️ تمت التصفية تلقائيًا: ${nf(campFiltered.length)} مستودع يغذي هذا المعسكر'
            : '⚠ لا يوجد مستودع مرتبط بهذا المعسكر بعد — تُعرض كل المستودعات');
    final subs = _units.where((u) => _parent.isEmpty || u.parentId == _parent).toList();
    final strDateLabel = _strDate.isNotEmpty ? _strDate : _date;
    final noStrength = ((_type == 0 && _ben.isNotEmpty) || (_type == 1 && _fac.isNotEmpty)) && _strength == 0;
    Widget lab(String l, Widget f) => ImdLabeled(l, f, size: 11);

    return [
      ImdGuidePanel(
        child: ImdSoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdWorkflowSteps(
              const ['حدد الجهة المستفيدة', 'اختر الأصناف', 'راجع الاستحقاق', 'اطبع أو نفّذ أو احفظ مسودة'],
              activeIndex: activeStep,
              hints: nextSteps,
            ),
            ImdQuickGrid([
              ('الأصناف', nf(_items.length)),
              ('الوحدات', nf(_units.length)),
              ('المستودعات', nf(_whs.length)),
              ('المطابخ/الأفران', nf(_facs.length)),
            ]),
            const ImdPrintTip('لو محتاج موافقة تشغيلية قبل الخصم الفعلي، استخدم «إشعار للمستودع» أو «مسودة» بدل التنفيذ المباشر.'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ImdICard(
        title: 'نوع التوجيه والجهة المستفيدة',
        icon: 'target',
        child: ImdCompact(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdTargetPills<int>(
            value: _type,
            onChanged: _setType,
            tabs: const [
              ImdTab(0, 'وحدة مستفيدة', icon: 'users'),
              ImdTab(1, 'مطبخ / فرن', icon: 'utensils'),
              ImdTab(2, 'استثنائي / مخصص', icon: 'star'),
              ImdTab(3, 'وحدات متعددة', icon: 'file'),
            ],
          ),
          const SizedBox(height: ImdSizes.compactRowGap),
          ImdFormGrid(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              lab(
                'المستودع المصروف منه *',
                ImdSelect<String>(
                  value: _wh,
                  items: whOpts.isEmpty
                      ? [('', Perm.of(context).scope == null ? '— لا مستودعات —' : '— لا توجد مستودعات ضمن نطاقك —')]
                      : [for (final w in whOpts) (w.name, '${w.code.isNotEmpty ? '${w.code} — ' : ''}${w.name}')],
                  onChanged: (v) {
                    setState(() => _wh = v ?? '');
                    _refreshBal();
                  },
                ),
              ),
              if (whNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: ImdEmojiText(whNote, iconSize: 11, style: TextStyle(fontSize: 11, color: c.muted)),
                ),
            ]),
            lab('تاريخ الصرف', ImdDateField(value: _date, onChanged: (v) { setState(() => _date = v); _scheduleAutosave(); })),
            lab('رقم السند/المرجع', ImdReadonlyField(text: _ref)),
            lab(
              'موعد الصرف القادم',
              ImdReadonlyField(
                text: _nextDue,
                weight: FontWeight.w800,
                bg: c.warnSoft,
                color: _nextDueColor ?? c.warn,
              ),
            ),
          ]),
          const SizedBox(height: ImdSizes.compactRowGap),
          ImdFormGrid(children: [
            if (_type == 0) ...[
              lab(
                'المعسكر / الوحدة الرئيسية',
                ImdSelect<String>(
                  value: _parent,
                  items: [('', 'الكل / لا يوجد'), for (final cp in camps) (cp.id, '${cp.code} — ${cp.name}')],
                  onChanged: (v) => _onParent(v ?? ''),
                ),
              ),
              lab(
                'الوحدة التابعة المستفيدة *',
                ImdSelect<String>(
                  value: _ben,
                  items: [('', '— اختر الوحدة —'), for (final u in subs) (u.id, '${u.code} — ${u.name}')],
                  onChanged: (v) => _onBen(v ?? ''),
                ),
              ),
            ],
            if (_type == 1)
              lab(
                'المطبخ أو الفرن المستلم *',
                ImdSelect<String>(
                  value: _fac,
                  items: [
                    ('', '— اختر المطبخ/الفرن —'),
                    for (final f in _facs) (f.id, '${f.name} (${f.fType.toUpperCase() == 'KITCHEN' ? 'مطبخ' : 'فرن'})'),
                  ],
                  onChanged: (v) {
                    setState(() => _fac = v ?? '');
                    _scheduleAutosave();
                    _fetchStrength();
                  },
                ),
              ),
            if (_type == 2)
              lab('اسم المستلم (للاستثناءات) *', ImdFld(controller: _custom, hint: 'اكتب اسم المستلم / الجهة...', onChanged: (_) => setState(() {}))),
          ]),
          if (_type == 0 || _type == 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ImdDashedBox(
                child: ImdFormGrid(children: [
                  lab('تاريخ إلحاق القوة (حصر القوة)', ImdDateField(value: _strDate, onChanged: (v) {
                    setState(() => _strDate = v);
                    _scheduleAutosave();
                    _fetchStrength();
                  })),
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    lab('إجمالي القوة (أفراد/ضباط)', ImdReadonlyField(text: _num(_strength), bg: c.surface, color: c.accent)),
                    if (noStrength)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('لا توجد تفريدة بتاريخ $strDateLabel — القوة صفر', style: TextStyle(fontSize: 11, color: c.warn)),
                      ),
                  ]),
                  lab('مدة الإعاشة (أيام)', ImdFld(controller: _days, number: true, onChanged: (_) => _recalcAll())),
                ]),
              ),
            ),
          const SizedBox(height: ImdSizes.compactRowGap),
          ImdCollapsibleSection(
            title: 'ملاحظات السند / الغرض من الصرف',
            child: ImdFld(controller: _notes, hint: 'ملاحظات توثيقية حول أمر الصرف...'),
          ),
        ])),
      ),
      // نفس أداة «الاحتساب التلقائي» في شاشة التحويل المخزني: المنطق كان
      // موجودًا هنا (يُحدّث الأسطر المضافة يدويًا) وينقصه ملء الجدول دفعة واحدة.
      if (_strength > 0)
        ImdICard(
          title: 'احتساب تلقائي بالاستحقاقات (بدل إدخال كل صنف يدويًا)',
          icon: 'calculator',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdPrintTip(
                'تُحسب الكمية = الاستحقاق اليومي للفرد × إجمالي القوة × مدة الإعاشة. '
                'القوة تُجلب من تفريدة الجهة المستفيدة أعلاه، والمقرر من شاشة الاستحقاقات.'),
            const SizedBox(height: 10),
            ImdRbar(bottom: 0, children: [
              ImdChip('القوة: ${nf(_strength)}', tone: ImdTone.ok),
              ImdChip('المدة: ${_days.text.trim().isEmpty ? '1' : _days.text.trim()} يوم',
                  tone: ImdTone.code),
              ImdButton(
                label: 'احتساب الأصناف تلقائيًا',
                icon: 'calculator',
                onPressed: _busy ? null : _autoFillFromEntitlements,
              ),
            ]),
          ]),
        ),
      ImdICard(
        title: 'ماسح الباركود / الإضافة السريعة',
        icon: 'tag',
        child: ImdBarcodeInput(hint: 'مرّر قارئ الباركود أو اكتب الكود واضغط Enter…', onSubmit: _scan),
      ),
      if (ImdBp.of(context).mobile)
        for (final (i, r) in _rows.indexed) KeyedSubtree(key: r.key, child: _rowView(context, i + 1, r))
      else
        _desktopTable(context),
      ImdValidationBox(title: 'فحص سريع قبل تنفيذ أمر الصرف', items: _validate()),
    ];
  }
}
