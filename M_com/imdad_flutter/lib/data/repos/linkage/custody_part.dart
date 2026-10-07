part of '../linkage_repo.dart';

/// العهد والإخلاءات — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkageCustodyRepo on LinkageRepo {
  // ───────────────── العهد ─────────────────

  Future<List<LinkFinCustody>> custodies({String q = '', String view = ''}) async {
    final rows = await db.select(db.linkFinCustodies).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((c) {
      if (view == 'open' && c.cleared) return false;
      if (view == 'cleared' && !c.cleared) return false;
      if (query.isEmpty) return true;
      final hay = [c.custodyNo, c.holder, c.title, c.serialNo, c.notes].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => b.custodyDate.compareTo(a.custodyDate));
    return out;
  }

  Future<void> insertCustody(LinkFinCustodiesCompanion e, {String actor = ''}) async {
    var data = e;
    final no = data.custodyNo.present ? data.custodyNo.value.trim() : '';
    // الرقم الفارغ يُولَّد، والمكتوب لا يتكرر.
    final finalNo = no.isEmpty ? await nextCustodyNo() : no;
    if (await custodyNoTaken(finalNo)) throw LinkBlocked('رقم العهدة «$finalNo» مستخدم لعهدة أخرى');
    data = data.copyWith(custodyNo: Value(finalNo), cleared: Value((data.status.present ? data.status.value : CustodyStatus.open) == CustodyStatus.cleared));
    await db.into(db.linkFinCustodies).insert(data);
    for (final n in [
      if (data.holder.present) data.holder.value,
      if (data.giverName.present) data.giverName.value,
      if (data.receiverName.present) data.receiverName.value,
    ]) {
      if (n.trim().isNotEmpty) await addTermIfNew('holder', n);
    }
    await AuditRepo(db).log(
      action: 'linkage.custody.create',
      entityType: 'linkage',
      summary: 'تسجيل عهدة $finalNo «${data.title.present ? data.title.value : ''}» — '
          '${CustodyKind.label(data.kind.present ? data.kind.value : CustodyKind.received)} '
          '${data.amount.present ? data.amount.value : 0} ${FinCurrency.label(data.currency.present ? data.currency.value : FinCurrency.sar)}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> updateCustody(LinkFinCustody c, LinkFinCustodiesCompanion e, {String actor = ''}) async {
    final no = e.custodyNo.present ? e.custodyNo.value.trim() : c.custodyNo;
    if (no.isEmpty) throw const LinkBlocked('رقم العهدة مطلوب');
    if (no != c.custodyNo && await custodyNoTaken(no, excludeId: c.id)) {
      throw LinkBlocked('رقم العهدة «$no» مستخدم لعهدة أخرى');
    }
    // العهدة المُخلَّاة لا يُعدَّل مبلغها ولا عملتها ولا نوعها: الإخلاء بُني عليها.
    if (c.status == CustodyStatus.cleared) {
      final moneyChanged = (e.amount.present && e.amount.value != c.amount) ||
          (e.currency.present && e.currency.value != c.currency) ||
          (e.kind.present && e.kind.value != c.kind);
      if (moneyChanged) throw const LinkBlocked('العهدة مُخلَّاة — لا يُعدَّل مبلغها أو عملتها أو نوعها. احذف الإخلاء أولًا.');
    }
    // الإلغاء لا يجوز لعهدةٍ لها إخلاء.
    if (e.status.present && e.status.value == CustodyStatus.canceled && c.status == CustodyStatus.cleared) {
      throw const LinkBlocked('لا تُلغى عهدة مُخلَّاة');
    }
    final status = e.status.present ? e.status.value : c.status;
    await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(c.id))).write(
      e.copyWith(custodyNo: Value(no), cleared: Value(status == CustodyStatus.cleared)),
    );
    for (final n in [
      if (e.holder.present) e.holder.value,
      if (e.giverName.present) e.giverName.value,
      if (e.receiverName.present) e.receiverName.value,
    ]) {
      if (n.trim().isNotEmpty) await addTermIfNew('holder', n);
    }
    await AuditRepo(db).log(
      action: 'linkage.custody.edit',
      entityType: 'linkage',
      summary: 'تعديل عهدة ${c.custodyNo} «${c.title}»',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// الارتباطات التي تمنع حذف العهدة: عقودٌ ومسيراتٌ وإخلاءات. أسماؤها للرسالة.
  Future<List<String>> custodyLinks(String custodyId) async {
    final contracts = await (db.select(db.linkPurchaseContracts)..where((t) => t.custodyId.equals(custodyId))).get();
    final sheets = await (db.select(db.linkCustodySheets)..where((t) => t.custodyId.equals(custodyId))).get();
    final clears = await (db.select(db.linkClearances)
          ..where((t) => t.kind.equals(LinkClearanceKind.custody) & t.refId.equals(custodyId)))
        .get();
    return [
      if (contracts.isNotEmpty) '${contracts.length} عقد',
      if (sheets.isNotEmpty) '${sheets.length} مسير',
      if (clears.isNotEmpty) '${clears.length} إخلاء',
    ];
  }

  /// يمنع الحذف إذا كانت العهدة مرتبطة بعقدٍ أو مسيرٍ أو إخلاء — المنع هنا في
  /// المستودع لا في الواجهة وحدها، فلا يتجاوزه استيرادٌ أو مزامنة.
  Future<void> deleteCustody(LinkFinCustody c, {String actor = ''}) async {
    final links = await custodyLinks(c.id);
    if (links.isNotEmpty) {
      throw LinkBlocked('لا تُحذف العهدة ${c.custodyNo} لارتباطها بـ${links.join(' و')}. احذف الارتباطات أولًا.');
    }
    await (db.delete(db.linkFinCustodies)..where((t) => t.id.equals(c.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.custody.delete',
      entityType: 'linkage',
      summary: 'حذف عهدة ${c.custodyNo} «${c.title}» — ${c.giverName.isEmpty ? c.holder : c.giverName} ← ${c.receiverName}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  /// رقم العهدة التالي بصيغة `عهدة-00001`: أعلى رقمٍ موجود بهذه الصيغة + 1.
  Future<String> nextCustodyNo() async {
    final rows = await db.select(db.linkFinCustodies).get();
    var max = 0;
    for (final r in rows) {
      final m = RegExp(r'^عهدة-(\d+)$').firstMatch(r.custodyNo.trim());
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > max) max = n;
    }
    return 'عهدة-${(max + 1).toString().padLeft(5, '0')}';
  }

  Future<bool> custodyNoTaken(String no, {String excludeId = ''}) async {
    final v = no.trim().toLowerCase();
    if (v.isEmpty) return false;
    final rows = await db.select(db.linkFinCustodies).get();
    return rows.any((r) => r.id != excludeId && r.custodyNo.trim().toLowerCase() == v);
  }

  /// المبلغ المُستهلك من كل عهدة = مجموع عقودها المرتبطة، محوَّلًا إلى عملة العهدة
  /// بسعر صرف العقد (أو العهدة). عقدٌ يلزم تحويله بلا سعرٍ صالح لا يُحتسب ويُعدّ
  /// في [CustodyUsage.unconvertible] ليُنبَّه إليه.
  Future<Map<String, CustodyUsage>> custodyUsage() async {
    final custodies = await db.select(db.linkFinCustodies).get();
    final contracts = await db.select(db.linkPurchaseContracts).get();
    final out = <String, CustodyUsage>{};
    for (final c in custodies) {
      var consumed = 0.0;
      var count = 0;
      var bad = 0;
      for (final k in contracts) {
        if (k.custodyId != c.id) continue;
        count++;
        final rate = k.exchangeRate > 0 ? k.exchangeRate : c.exchangeRate;
        final v = convertAmount(k.amount, from: k.currency, to: c.currency, rate: rate);
        if (v == null) {
          bad++;
        } else {
          consumed += v;
        }
      }
      out[c.id] = CustodyUsage(consumed: consumed, contracts: count, unconvertible: bad);
    }
    return out;
  }

  // ───────────────── الإخلاءات ─────────────────

  Future<List<LinkClearance>> clearances({String q = '', String kind = ''}) async {
    final rows = await db.select(db.linkClearances).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((c) {
      if (kind.isNotEmpty && c.kind != kind) return false;
      if (query.isEmpty) return true;
      final hay = [c.clearanceNo, c.refTitle, c.partyName, c.notes].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => b.clearanceDate.compareTo(a.clearanceDate));
    return out;
  }

  /// يسجّل إخلاءً ويُغلق مرجعه في معاملةٍ واحدة:
  /// العهدة تصير «مُخلّاة»، والعقد «منفَّذًا»، والإخلاء الحر لا مرجع له.
  Future<void> addClearance({
    required String kind,
    String refId = '',
    String clearanceNo = '',
    required String clearanceDate,
    String partyName = '',
    String refTitle = '',
    double amount = 0,
    String notes = '',
    String actor = '',
  }) async {
    var party = partyName;
    var title = refTitle;
    // إخلاء العهدة له مسارٌ خاصّ: أرقامه من المسيرات ويكتب الدفتر.
    if (kind == LinkClearanceKind.custody && refId.isNotEmpty) {
      await saveCustodyClearance(
        custodyId: refId,
        clearanceNo: clearanceNo,
        clearanceDate: clearanceDate,
        notes: notes,
        actor: actor,
      );
      return;
    }
    await db.transaction(() async {
      if (kind == LinkClearanceKind.contract && refId.isNotEmpty) {
        final c = await (db.select(db.linkPurchaseContracts)..where((t) => t.id.equals(refId))).getSingleOrNull();
        if (c != null) {
          title = title.isEmpty ? c.title : title;
          party = party.isEmpty ? c.supplier : party;
          await (db.update(db.linkPurchaseContracts)..where((t) => t.id.equals(refId))).write(
            LinkPurchaseContractsCompanion(
              status: const Value(LinkContractStatus.done),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
      await db.into(db.linkClearances).insert(LinkClearancesCompanion(
            id: Value(Ids.next('lq')),
            clearanceNo: Value(clearanceNo),
            kind: Value(kind),
            refId: Value(refId),
            refTitle: Value(title),
            partyName: Value(party),
            amount: Value(amount),
            clearanceDate: Value(clearanceDate),
            notes: Value(notes),
            createdBy: Value(actor),
            createdAt: Value(DateTime.now()),
          ));
    });
    await AuditRepo(db).log(
      action: 'linkage.clearance.create',
      entityType: 'linkage',
      summary: 'إخلاء ${LinkClearanceKind.label(kind)} «$title» — $party',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// حذف الإخلاء يُعيد فتح مرجعه (عهدة قائمة / عقد قيد التنفيذ).
  Future<void> deleteClearance(LinkClearance c, {String actor = ''}) async {
    await db.transaction(() async {
      await (db.delete(db.linkClearances)..where((t) => t.id.equals(c.id))).go();
      if (c.refId.isEmpty) return;
      if (c.kind == LinkClearanceKind.custody) {
        // المسودة لم تُغلق العهدة، فلا شيء يُعاد فتحه ولا قيد يُعكس.
        if (c.workflow != LinkageRepo.wfApproved) return;
        await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(c.refId))).write(
          const LinkFinCustodiesCompanion(
            cleared: Value(false),
            status: Value(CustodyStatus.open),
            outcome: Value(''),
            outcomeAmount: Value(0),
            clearedDate: Value(''),
            clearanceNotes: Value(''),
          ),
        );
        // قيد الدفتر لا يُمحى: يُعكس بقيدٍ مضاد فيبقى الأثر قابلًا للتدقيق.
        final entries = await (db.select(db.linkFinanceLedger)..where((t) => t.clearanceId.equals(c.id))).get();
        final reversed = entries.where((e) => e.entryKind == 'reversal').length;
        if (reversed == 0) {
          for (final e in entries) {
            await db.into(db.linkFinanceLedger).insert(LinkFinanceLedgerCompanion(
                  id: Value(Ids.next('lg')),
                  partyName: Value(e.partyName),
                  custodyId: Value(e.custodyId),
                  clearanceId: Value(e.clearanceId),
                  entryKind: const Value('reversal'),
                  delta: Value(-e.delta),
                  currency: Value(e.currency),
                  entryDate: Value(isoDay(DateTime.now())),
                  note: Value('عكس: ${e.note}'),
                  createdAt: Value(DateTime.now()),
                ));
          }
        }
      } else if (c.kind == LinkClearanceKind.contract) {
        await (db.update(db.linkPurchaseContracts)..where((t) => t.id.equals(c.refId))).write(
          const LinkPurchaseContractsCompanion(status: Value(LinkContractStatus.open)),
        );
      }
    });
    await FinanceFiles.delete(c.attachPath);
    await AuditRepo(db).log(
      action: 'linkage.clearance.delete',
      entityType: 'linkage',
      summary: 'حذف إخلاء «${c.refTitle}» وإعادة فتح مرجعه',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }
}
