part of '../issue_screen.dart';

/// الفحص السريع وترويسة السند والتنفيذ والطباعة.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueSubmit on _IssueBase, _IssueAutosave, _IssueRows {
  /// `issValidateLive()`
  List<ImdCheck> _validate() {
    final items = <ImdCheck>[];
    for (final p in IssueRules.headerProblems(_header, today: DateTime.now())) {
      items.add(ImdCheck(p.isError ? 'err' : 'warn', p.title, p.detail));
    }
    final c = _collect();
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في السطور', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل التنفيذ.'));
    if (imdDuplicateCount(c.rows, (r) => '${r.itemId}|${r.unitName}|${r.beneficiaryUnitId}') > 0) {
    }
    final bal = _balError(c.rows);
    if (bal.isNotEmpty) items.add(ImdCheck('err', 'الرصيد لا يكفي', bal.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isNotEmpty) {
      items.add(ImdCheck('ok', 'ملخص سريع',
          'عدد السطور: ${nf(c.rows.length)} — إجمالي الخصم المتوقع: ${nf(c.rows.fold<double>(0, (a, b) => a + b.baseQty))}'));
    }
    return items;
  }

  /// رأس السند الحالي لقواعد [IssueRules].
  IssueHeader get _header => IssueHeader(
        target: IssueTarget.of(_type),
        warehouse: _wh,
        date: _date,
        unitId: _ben,
        unitName: _benName,
        facilityId: _fac,
        facilityLabel: _facLabel,
        customRecipient: _custom.text,
      );

  String get _benName {
    final u = _units.where((x) => x.id == _ben).firstOrNull;
    return u?.name ?? '';
  }

  String get _facLabel {
    final f = _facs.where((x) => x.id == _fac).firstOrNull;
    return f == null ? '' : '${f.name} (${f.fType.toUpperCase() == 'KITCHEN' ? 'مطبخ' : 'فرن'})';
  }

  /// `issSubmit(moveStatus)`
  Future<void> _submit(String status) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'issue', status == 'DRAFT' ? 'create' : 'approve')) return;
    if (_wh.isNotEmpty && !perm.canWh(_wh)) return showImdToast(context, Perm.scopeBlock(_wh));
    final frozen = await _moves.frozenMessage(_wh);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    final header = _header;
    final problems = IssueRules.headerProblems(header, today: DateTime.now());
    if (problems.isNotEmpty) return showImdToast(context, problems.first.message);
    if (_ref.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    final target = header.recipient;
    final c = _collect();
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل');
    final bal = _balError(c.rows);
    if (status == 'COMPLETED' && bal.isNotEmpty) return showImdToast(context, bal);
    setState(() => _busy = true);
    try {
      if (await _moves.hasRefConflict('issues', _ref, 'REJECTED')) {
        if (mounted) showImdToast(context, '✖ يوجد سند صرف سابق بنفس المرجع — استخدم مرجعًا مختلفًا');
        return;
      }
      if (!mounted) return;
      if (status == 'COMPLETED' && !await imdConfirm(context, 'اعتماد سند الصرف النهائي؟\nسيتم خصم الكميات من المستودع مباشرة.')) {
        return;
      }
      if (!mounted) return;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveIssue(
        warehouse: _wh,
        recipientDisplay: target,
        date: _date,
        lines: c.rows,
        targetType: _type,
        unitId: _type == 0 ? _ben : '',
        facilityId: _type == 1 ? _fac : '',
        soldierCount: _strength,
        durationDays: int.tryParse(_days.text.trim()) ?? 1,
        refNo: _ref,
        notes: _notes.text.trim(),
        status: status,
        createdBy: actor?.email ?? '',
        actor: actor,
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      await _clearAutosave();
      _autosavedAt = null;
      if (!mounted) return;
      showImdToast(
          context,
          status == 'COMPLETED'
              ? '🎉 تم تنفيذ أمر الصرف وخصم الرصيد بنجاح'
              : (status == 'ORDER' ? '📤 أُرسل أمر التوجيه للمستودع' : '💾 حُفظت المسودة'));
      await _form();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _print(bool both) {
    if (!Perm.of(context).guard(context, 'issue', 'print')) return;
    final c = _collect();
    if (c.rows.isEmpty) return showImdToast(context, '✖ لا توجد أصناف للطباعة');
    final recipient = switch (_type) {
      0 => _units.where((x) => x.id == _ben).map((u) => '${u.code} — ${u.name}').firstOrNull ?? '—',
      1 => _facLabel.isEmpty ? '—' : _facLabel,
      2 => _custom.text.trim().isEmpty ? '—' : _custom.text.trim(),
      _ => '—',
    };
    final lines = [
      for (final l in c.rows)
        VoucherLine(
          itemName: l.itemName,
          unitName: l.unitName,
          qty: l.qty,
          itemCode: l.itemCode,
          notes: l.notes,
          beneficiary: l.beneficiaryUnitName,
        ),
    ];
    final days = int.tryParse(_days.text.trim()) ?? 1;
    final end = (DateTime.tryParse(_date) ?? DateTime.now()).add(Duration(days: days - 1));
    VoucherPrint.print(
      db: _db,
      title: 'أمر صرف مخزني',
      kind: VoucherKind.issue,
      refNo: _ref,
      date: _date,
      endDate: isoDay(end),
      warehouse: _wh,
      party: recipient,
      notes: _notes.text.trim(),
      strength: nf(_strength),
      days: nf(days),
      lines: lines,
      withReceipt: both,
    );
  }
}
