part of '../linkage_repo.dart';

/// عقود المشتريات — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkageContractsRepo on LinkageRepo {
  // ───────────────── عقود المشتريات ─────────────────

  Future<List<LinkPurchaseContract>> contracts({String q = '', String status = ''}) async {
    final rows = await db.select(db.linkPurchaseContracts).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((c) {
      if (status.isNotEmpty && c.status != status) return false;
      if (query.isEmpty) return true;
      final hay = [c.contractNo, c.title, c.supplier, c.itemsJson, c.notes].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => b.listDate.compareTo(a.listDate));
    return out;
  }

  Future<LinkFinCustody?> custodyById(String id) async {
    if (id.isEmpty) return null;
    return (db.select(db.linkFinCustodies)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// ربط عقدٍ بعهدة: العهدة يجب أن تكون موجودة وقيد الإخلاء. عقدٌ واحد = عهدة
  /// واحدة، فالحقل مفردٌ في العقد نفسه ولا يمكن أن يخدم عهدتين.
  Future<void> _assertCanLinkContract(String custodyId) async {
    if (custodyId.isEmpty) return;
    final c = await custodyById(custodyId);
    if (c == null) throw const LinkBlocked('العهدة المرتبطة غير موجودة');
    if (c.status != CustodyStatus.open) {
      throw LinkBlocked('العهدة ${c.custodyNo} ${CustodyStatus.label(c.status)} — لا يُربط بها عقد جديد');
    }
  }

  Future<void> insertContract(LinkPurchaseContractsCompanion e, {String actor = ''}) async {
    final custodyId = e.custodyId.present ? e.custodyId.value : '';
    await _assertCanLinkContract(custodyId);
    await db.into(db.linkPurchaseContracts).insert(e);
    await AuditRepo(db).log(
      action: 'linkage.contract.create',
      entityType: 'linkage',
      summary: 'تسجيل عقد مشتريات: ${e.title.present ? e.title.value : ''}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
    await _logCustodyUse(custodyId, e.contractNo.present ? e.contractNo.value : '', e.title.present ? e.title.value : '', actor, used: true);
  }

  /// يسجّل في العهدة (سجل التدقيق) أنها استُخدمت في عقد أو فُكَّ ارتباطه بها.
  Future<void> _logCustodyUse(String custodyId, String contractNo, String title, String actor, {required bool used}) async {
    final c = await custodyById(custodyId);
    if (c == null) return;
    final ref = contractNo.trim().isEmpty ? '«$title»' : 'رقم $contractNo «$title»';
    await AuditRepo(db).log(
      action: used ? 'linkage.custody.contract_linked' : 'linkage.custody.contract_unlinked',
      entityType: 'linkage',
      summary: used ? 'استُخدمت العهدة ${c.custodyNo} في عقد $ref' : 'فُكَّ ارتباط العقد $ref من العهدة ${c.custodyNo}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> updateContract(
      LinkPurchaseContract c, LinkPurchaseContractsCompanion e,
      {String actor = ''}) async {
    final newCustody = e.custodyId.present ? e.custodyId.value : c.custodyId;
    final linked = await custodyById(c.custodyId);
    // عقدٌ مرتبط بعهدةٍ مُخلَّاة: الإخلاء بُني على مبالغه، فلا تتغير.
    if (linked != null && linked.status == CustodyStatus.cleared) {
      final changed = newCustody != c.custodyId ||
          (e.amount.present && e.amount.value != c.amount) ||
          (e.currency.present && e.currency.value != c.currency) ||
          (e.exchangeRate.present && e.exchangeRate.value != c.exchangeRate) ||
          (e.itemsJson.present && e.itemsJson.value != c.itemsJson);
      if (changed) throw LinkBlocked('العقد مرتبط بالعهدة ${linked.custodyNo} وهي مُخلَّاة — احذف الإخلاء أولًا');
    }
    if (newCustody != c.custodyId) await _assertCanLinkContract(newCustody);
    await (db.update(db.linkPurchaseContracts)..where((t) => t.id.equals(c.id))).write(e);
    await AuditRepo(db).log(
      action: 'linkage.contract.edit',
      entityType: 'linkage',
      summary: 'تعديل عقد: ${c.title}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
    final fresh = await (db.select(db.linkPurchaseContracts)..where((t) => t.id.equals(c.id))).getSingle();
    final synced = await _syncSheetsFromContract(c, fresh);
    if (synced > 0) {
      await AuditRepo(db).log(
        action: 'linkage.sheet.synced_from_contract',
        entityType: 'linkage',
        summary: 'تحديث $synced سطر في مسيرات العهدة من تعديل العقد «${c.title}»',
        risk: AuditRepo.riskNormal,
        actorEmail: actor,
      );
    }
    final no = e.contractNo.present ? e.contractNo.value : c.contractNo;
    if (newCustody != c.custodyId) {
      await _logCustodyUse(c.custodyId, c.contractNo, c.title, actor, used: false);
      await _logCustodyUse(newCustody, no, c.title, actor, used: true);
    }
  }

  Future<void> deleteContract(LinkPurchaseContract c, {String actor = ''}) async {
    final linked = await custodyById(c.custodyId);
    if (linked != null && linked.status == CustodyStatus.cleared) {
      throw LinkBlocked('العقد مرتبط بالعهدة ${linked.custodyNo} وهي مُخلَّاة — احذف الإخلاء أولًا');
    }
    await (db.delete(db.linkPurchaseContracts)..where((t) => t.id.equals(c.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.contract.delete',
      entityType: 'linkage',
      summary: 'حذف عقد: ${c.title}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }



  /// عند تعديل عقدٍ يتحدث ما سُحب منه في المسيرات: كل سطرٍ برقم فاتورة العقد في
  /// مسيرٍ لعهدة العقد نفسها، **لم يعدّله المستخدم** بعد السحب (قيمه ما تزال ما
  /// كان يسحبه العقد القديم). ما عُدِّل يدويًّا يبقى كما هو.
  Future<int> _syncSheetsFromContract(LinkPurchaseContract old, LinkPurchaseContract now) async {
    if (now.custodyId.isEmpty || old.custodyId != now.custodyId) return 0;
    final before = LinkageRepo.rowFromContract(old);
    final after = LinkageRepo.rowFromContract(now);
    final sheets = await (db.select(db.linkCustodySheets)..where((t) => t.custodyId.equals(now.custodyId))).get();
    var changed = 0;
    for (final s in sheets) {
      final rows = await (db.select(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(s.id))).get();
      for (final r in rows) {
        if (!(old.matchesInvoice(r.invoiceNo) || now.matchesInvoice(r.invoiceNo))) continue;
        final untouched = r.date == before.date &&
            r.category.trim() == before.category &&
            r.shop == before.shop &&
            (before.yer ? r.spentYer == before.amount : r.spentSar == before.amount && r.spentYer == 0) &&
            (!before.yer || r.rate == before.rate);
        if (!untouched) continue;
        final rate = after.yer ? (after.rate > 0 ? after.rate : r.rate) : r.rate;
        await (db.update(db.linkCustodySheetRows)..where((t) => t.id.equals(r.id))).write(LinkCustodySheetRowsCompanion(
          date: Value(after.date),
          category: Value(after.category),
          shop: Value(after.shop),
          spentYer: Value(after.yer ? after.amount : 0),
          spentSar: Value(after.yer ? (rate > 0 ? after.amount / rate : 0) : after.amount),
          rate: Value(rate),
        ));
        changed++;
      }
    }
    return changed;
  }

  /// العقود المرتبطة بعهدة، الأحدث تاريخًا أولًا.
  Future<List<LinkPurchaseContract>> contractsOfCustody(String custodyId) async {
    final rows = await (db.select(db.linkPurchaseContracts)..where((t) => t.custodyId.equals(custodyId))).get();
    rows.sort((a, b) => b.listDate.compareTo(a.listDate));
    return rows;
  }
}
