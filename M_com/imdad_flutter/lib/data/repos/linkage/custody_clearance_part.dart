part of '../linkage_repo.dart';

/// إخلاء العهدة المالي — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkageCustodyClearanceRepo on LinkageRepo {
  // ───────────────── إخلاء العهدة المالي ─────────────────


  /// تسوية العهدة: المخصص، والمصروف والمرتجع من مسيراتها (بعملة العهدة)، والفرق.
  ///
  /// الفرق = المخصص − المصروف − المرتجع — نفس معادلة «المتبقي» في المسير، فلا يختلف
  /// رقم الإخلاء عن رقم المسير. المخصص هو مبلغ العهدة نفسه.
  Future<CustodySettlement?> custodySettlement(String custodyId) async {
    final c = await custodyById(custodyId);
    if (c == null) return null;
    final sheets = await (db.select(db.linkCustodySheets)..where((t) => t.custodyId.equals(custodyId))).get();
    var spent = 0.0, returned = 0.0;
    for (final s in sheets) {
      final rows = await (db.select(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(s.id))).get();
      final t = custodyTotalsIn([
        for (final r in rows)
          CustodyRowValues(
              grantSar: r.grantSar, grantYer: r.grantYer, returnSar: r.returnSar, returnYer: r.returnYer, spentSar: r.spentSar, spentYer: r.spentYer, rate: r.rate)
      ], c.currency);
      spent += t.spent;
      returned += t.returned;
    }
    // العهد القديمة بلا مبلغ جديد تقرأ قيمتها القديمة.
    final granted = c.amount != 0 ? c.amount : c.valueAmount;
    return CustodySettlement(
      custody: c,
      granted: granted,
      spent: spent,
      returned: returned,
      sheets: sheets.length,
      diff: CustodyDiff.of(granted: granted, spent: spent + returned),
      counterparty: c.kind == CustodyKind.received ? 'المالية' : LinkageRepo.partyOf(c),
    );
  }

  /// رقم الإخلاء: `إخلاء-{رمز الجهاز}-{YYYYMM}-{تسلسل}`، التسلسل من أعلى رقم بالصيغة نفسها.
  Future<String> nextClearanceNo() async {
    var code = 'XXXX';
    try {
      code = await DocNumbering(db).deviceCode();
    } catch (err, stack) {
      ErrorLogger.log('linkage.deviceCode', err, stack);
    }
    final now = DateTime.now();
    final head = 'إخلاء-$code-${now.year}${now.month.toString().padLeft(2, '0')}-';
    final rows = await db.select(db.linkClearances).get();
    var max = 0;
    for (final r in rows) {
      final n = r.clearanceNo.trim();
      if (!n.startsWith(head)) continue;
      final v = int.tryParse(n.substring(head.length)) ?? 0;
      if (v > max) max = v;
    }
    return '$head${(max + 1).toString().padLeft(5, '0')}';
  }

  /// إخلاءات العهدة الواحدة المتعددة — لا تنشأ محليًّا (المنع في [saveCustodyClearance])
  /// لكنها قد تأتي من مزامنة جهازين أخليا العهدة نفسها دون اتصال. تُعرض للمراجعة.
  Future<Map<String, List<LinkClearance>>> duplicateClearances() async {
    final rows = await (db.select(db.linkClearances)..where((t) => t.kind.equals(LinkClearanceKind.custody) & t.refId.equals('').not())).get();
    final by = <String, List<LinkClearance>>{};
    for (final r in rows) {
      (by[r.refId] ??= []).add(r);
    }
    by.removeWhere((_, v) => v.length < 2);
    return by;
  }

  /// يحفظ إخلاء عهدة (جديدًا أو تعديلًا). **الأرقام تُحسب هنا من المسيرات** لا
  /// من الواجهة، فلا يُدخل أحدٌ مبلغًا مخالفًا. الاعتماد وحده يُغلق العهدة ويكتب
  /// الفائض أو العجز في دفتر رصيد المالية، في معاملةٍ واحدة.
  Future<LinkClearance> saveCustodyClearance({
    String? id,
    required String custodyId,
    String clearanceNo = '',
    required String clearanceDate,
    String workflow = LinkageRepo.wfApproved,
    String docNo = '',
    String clearerName = '',
    String reviewDate = '',
    String adminNotes = '',
    String notes = '',
    String attachName = '',
    String attachPath = '',
    String attachSha256 = '',
    String actor = '',
  }) async {
    final st = await custodySettlement(custodyId);
    if (st == null) throw const LinkBlocked('العهدة غير موجودة');
    final custody = st.custody;
    final existing = await (db.select(db.linkClearances)
          ..where((t) => t.kind.equals(LinkClearanceKind.custody) & t.refId.equals(custodyId)))
        .get();
    LinkClearance? prev;
    if (id == null) {
      if (existing.isNotEmpty) {
        throw LinkBlocked('العهدة ${custody.custodyNo} لها إخلاء بالفعل (${existing.first.clearanceNo}) — لا تُخلَّى مرتين');
      }
      if (custody.status != CustodyStatus.open) {
        throw LinkBlocked('العهدة ${custody.custodyNo} ${CustodyStatus.label(custody.status)} — لا تُخلَّى');
      }
    } else {
      prev = existing.where((e) => e.id == id).firstOrNull;
      if (prev == null) throw const LinkBlocked('الإخلاء غير موجود لهذه العهدة');
    }
    final approvedBefore = prev?.workflow == LinkageRepo.wfApproved;
    if (approvedBefore && workflow != LinkageRepo.wfApproved) {
      throw const LinkBlocked('الإخلاء المُعتمد لا يعود مسودة — احذفه ليُعاد فتح العهدة');
    }
    if (!LinkageRepo.workflowLabels.containsKey(workflow)) throw const LinkBlocked('حالة الإخلاء غير معروفة');
    // الاعتماد يُغلق العهدة، فلا يجوز لعهدةٍ لم تعد قيد الإخلاء (أُلغيت بعد المسودة).
    if (workflow == LinkageRepo.wfApproved && !approvedBefore && custody.status != CustodyStatus.open) {
      throw LinkBlocked('العهدة ${custody.custodyNo} ${CustodyStatus.label(custody.status)} — لا يُعتمد إخلاؤها');
    }

    final no = clearanceNo.trim().isNotEmpty ? clearanceNo.trim() : (prev?.clearanceNo.isNotEmpty == true ? prev!.clearanceNo : await nextClearanceNo());
    final clashes = (await db.select(db.linkClearances).get()).any((e) => e.id != id && e.clearanceNo.trim().toLowerCase() == no.toLowerCase());
    if (clashes) throw LinkBlocked('رقم الإخلاء «$no» مستخدم');

    final diff = st.diff;
    // المُعتمد سابقًا يحتفظ بأرقامه المجمَّدة وقت الاعتماد.
    final money = approvedBefore
        ? const LinkClearancesCompanion()
        : LinkClearancesCompanion(
            amount: Value(st.spent),
            grantedAmount: Value(st.granted),
            spentAmount: Value(st.spent),
            diffType: Value(diff.type),
            surplusAmount: Value(diff.type == CustodyOutcome.surplus ? diff.amount : 0),
            deficitAmount: Value(diff.type == CustodyOutcome.deficit ? diff.amount : 0),
            currency: Value(custody.currency),
            counterpartyName: Value(st.counterparty),
            custodyNo: Value(custody.custodyNo),
          );
    final common = LinkClearancesCompanion(
      clearanceNo: Value(no),
      kind: const Value(LinkClearanceKind.custody),
      refId: Value(custodyId),
      refTitle: Value(custody.title),
      partyName: Value(LinkageRepo.partyOf(custody)),
      clearanceDate: Value(clearanceDate),
      notes: Value(notes),
      workflow: Value(workflow),
      docNo: Value(docNo.trim()),
      clearerName: Value(clearerName.trim()),
      reviewDate: Value(reviewDate),
      adminNotes: Value(adminNotes.trim()),
      attachName: Value(attachName),
      attachPath: Value(attachPath),
      attachSha256: Value(attachSha256),
    );
    final rowId = id ?? Ids.next('lq');
    await db.transaction(() async {
      if (prev == null) {
        await db.into(db.linkClearances).insert(
              common.copyWith(id: Value(rowId), createdBy: Value(actor), createdAt: Value(DateTime.now())),
            );
        await (db.update(db.linkClearances)..where((t) => t.id.equals(rowId))).write(money);
      } else {
        await (db.update(db.linkClearances)..where((t) => t.id.equals(rowId))).write(common);
        if (!approvedBefore) await (db.update(db.linkClearances)..where((t) => t.id.equals(rowId))).write(money);
      }
      if (workflow == LinkageRepo.wfApproved && !approvedBefore) {
        await _closeCustody(custody, diff, clearanceDate, notes, rowId, no, actor);
      }
    });
    await AuditRepo(db).log(
      action: prev == null ? 'linkage.clearance.create' : 'linkage.clearance.edit',
      entityType: 'linkage',
      summary: '${prev == null ? 'إخلاء' : 'تعديل إخلاء'} العهدة ${custody.custodyNo} ($no) — ${LinkageRepo.workflowLabels[workflow]} — '
          '${diff.phrase(custodyKind: custody.kind, counterparty: st.counterparty)}'
          '${diff.amount == 0 ? '' : ' ${diff.amount} ${FinCurrency.label(custody.currency)}'}',
      risk: workflow == LinkageRepo.wfApproved ? AuditRepo.riskHigh : AuditRepo.riskNormal,
      actorEmail: actor,
    );
    return (await db.select(db.linkClearances).get()).firstWhere((e) => e.id == rowId);
  }

  /// اعتماد الإخلاء: العهدة «تم الإخلاء» بنتيجتها، والفائض/العجز قيدٌ في الدفتر.
  Future<void> _closeCustody(LinkFinCustody custody, CustodyDiff diff, String date, String notes, String clearanceId, String no, String actor) async {
    await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(custody.id))).write(LinkFinCustodiesCompanion(
      status: const Value(CustodyStatus.cleared),
      cleared: const Value(true),
      clearedDate: Value(date),
      clearanceNotes: Value(notes),
      outcome: Value(diff.type),
      outcomeAmount: Value(diff.amount),
      updatedAt: Value(DateTime.now()),
    ));
    if (diff.type == CustodyOutcome.matched) return;
    final surplus = diff.type == CustodyOutcome.surplus;
    await db.into(db.linkFinanceLedger).insert(LinkFinanceLedgerCompanion(
          id: Value(Ids.next('lg')),
          partyName: Value(LinkageRepo.partyOf(custody).isEmpty ? 'غير محدد' : LinkageRepo.partyOf(custody)),
          custodyId: Value(custody.id),
          clearanceId: Value(clearanceId),
          entryKind: Value(surplus ? 'surplus' : 'deficit'),
          delta: Value(surplus ? diff.amount : -diff.amount),
          currency: Value(custody.currency),
          entryDate: Value(date),
          note: Value('إخلاء ${custody.custodyNo} ($no): ${diff.phrase(custodyKind: custody.kind, counterparty: custody.kind == CustodyKind.received ? 'المالية' : LinkageRepo.partyOf(custody))}'),
          createdBy: Value(actor),
          createdAt: Value(DateTime.now()),
        ));
  }

  /// كشف حساب مالية لصاحب عهدة: عهده القائمة (المستلمة مدين −، المسلَّمة دائن +)
  /// وقيود الفائض (+) والعجز (−) المعتمدة. الرصيد لكل عملةٍ على حدة.
  Future<PartyStatement> partyStatement(String party) async {
    final custodies = await db.select(db.linkFinCustodies).get();
    final ledger = await (db.select(db.linkFinanceLedger)..where((t) => t.partyName.equals(party))).get();
    final lines = <StatementLine>[];
    for (final c in custodies) {
      if (LinkageRepo.partyOf(c) != party || c.status != CustodyStatus.open) continue;
      final amt = c.amount != 0 ? c.amount : c.valueAmount;
      lines.add(StatementLine(
        date: c.custodyDate,
        label: 'عهدة ${CustodyKind.label(c.kind)} ${c.custodyNo} — ${c.title}',
        delta: c.kind == CustodyKind.received ? -amt : amt,
        currency: c.currency,
        kind: c.kind,
      ));
    }
    for (final e in ledger) {
      lines.add(StatementLine(date: e.entryDate, label: e.note, delta: e.delta, currency: e.currency, kind: e.entryKind));
    }
    lines.sort((a, b) => a.date.compareTo(b.date));
    final balance = <String, double>{};
    for (final l in lines) {
      balance[l.currency] = (balance[l.currency] ?? 0) + l.delta;
    }
    return PartyStatement(party: party, lines: lines, balance: balance);
  }

  /// أرصدة كل أصحاب العهد: الاسم ⇒ (العملة ⇒ الرصيد).
  Future<Map<String, Map<String, double>>> partyBalances() async {
    final custodies = await db.select(db.linkFinCustodies).get();
    final ledger = await db.select(db.linkFinanceLedger).get();
    final out = <String, Map<String, double>>{};
    void add(String party, String cur, double v) {
      if (party.isEmpty) return;
      final m = out[party] ??= {};
      m[cur] = (m[cur] ?? 0) + v;
    }

    for (final c in custodies) {
      if (c.status != CustodyStatus.open) continue;
      final amt = c.amount != 0 ? c.amount : c.valueAmount;
      add(LinkageRepo.partyOf(c), c.currency, c.kind == CustodyKind.received ? -amt : amt);
    }
    for (final e in ledger) {
      add(e.partyName, e.currency, e.delta);
    }
    return out;
  }
}
