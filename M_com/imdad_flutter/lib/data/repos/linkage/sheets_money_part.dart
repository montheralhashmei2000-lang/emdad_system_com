part of '../linkage_repo.dart';

/// مسير العهدة واستلام المبالغ — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkageSheetsMoneyRepo on LinkageRepo {
  // ───────────────── مسير العهدة ─────────────────

  Future<List<LinkCustodySheet>> custodySheets({String q = ''}) async {
    final rows = await db.select(db.linkCustodySheets).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((s) {
      if (query.isEmpty) return true;
      return [s.sheetNo, s.title, s.notes].join(' ').toLowerCase().contains(query);
    }).toList();
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// مسيرات عهدةٍ واحدة (بلا فرز).
  Future<List<LinkCustodySheet>> custodySheetsOf(String custodyId) =>
      (db.select(db.linkCustodySheets)..where((t) => t.custodyId.equals(custodyId))).get();

  /// كل أسطر كل المسيرات (للاقتراحات والإجماليات).
  Future<List<LinkCustodySheetRow>> allSheetRows() => db.select(db.linkCustodySheetRows).get();

  Future<List<LinkCustodySheetRow>> sheetRows(String sheetId) async {
    final rows = await (db.select(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(sheetId))).get();
    rows.sort((a, b) => a.seq.compareTo(b.seq));
    return rows;
  }

  /// يحفظ المسير وأسطره دفعةً واحدة (حفظٌ واحد لا حفظ لكل سطر).
  Future<String> saveCustodySheet({
    String? id,
    required String sheetNo,
    required String title,
    required double defaultRate,
    required String notes,
    required List<LinkCustodySheetRowsCompanion> rows,
    String custodyId = '',
    String currency = 'sar',
    String holderName = '',
    String actor = '',
  }) async {
    // المسير مرتبطٌ بعهدة: العهدة موجودة، وقيد الإخلاء عند الإنشاء، وغير مُخلَّاة عند التعديل.
    final previous = id == null ? null : await (db.select(db.linkCustodySheets)..where((t) => t.id.equals(id))).getSingleOrNull();
    final oldCustody = await custodyById(previous?.custodyId ?? '');
    if (oldCustody != null && oldCustody.status == CustodyStatus.cleared) {
      throw LinkBlocked('المسير يخص العهدة ${oldCustody.custodyNo} وهي مُخلَّاة — احذف الإخلاء أولًا');
    }
    if (custodyId.isNotEmpty) {
      final c = await custodyById(custodyId);
      if (c == null) throw const LinkBlocked('العهدة المحددة غير موجودة');
      if (c.status != CustodyStatus.open && custodyId != previous?.custodyId) {
        throw LinkBlocked('العهدة ${c.custodyNo} ${CustodyStatus.label(c.status)} — لا يُفتح لها مسير');
      }
    }
    final sheetId = id ?? Ids.next('ls');
    await db.transaction(() async {
      if (id == null) {
        await db.into(db.linkCustodySheets).insert(LinkCustodySheetsCompanion(
              id: Value(sheetId),
              sheetNo: Value(sheetNo),
              title: Value(title),
              custodyId: Value(custodyId),
              currency: Value(currency),
              holderName: Value(holderName),
              defaultRate: Value(defaultRate),
              notes: Value(notes),
              createdBy: Value(actor),
              createdAt: Value(DateTime.now()),
            ));
      } else {
        await (db.update(db.linkCustodySheets)..where((t) => t.id.equals(id))).write(LinkCustodySheetsCompanion(
          sheetNo: Value(sheetNo),
          title: Value(title),
          custodyId: Value(custodyId),
          currency: Value(currency),
          holderName: Value(holderName),
          defaultRate: Value(defaultRate),
          notes: Value(notes),
          updatedAt: Value(DateTime.now()),
        ));
        await (db.delete(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(id))).go();
      }
      var seq = 0;
      for (final r in rows) {
        await db.into(db.linkCustodySheetRows).insert(
              r.copyWith(id: Value(Ids.next('lr')), sheetId: Value(sheetId), seq: Value(seq++)),
            );
      }
    });
    await AuditRepo(db).log(
      action: id == null ? 'linkage.sheet.create' : 'linkage.sheet.edit',
      entityType: 'linkage',
      summary: '${id == null ? 'إنشاء' : 'تعديل'} مسير عهدة رقم $sheetNo — ${rows.length} سطر'
          '${custodyId.isEmpty ? '' : ' — للعهدة ${(await custodyById(custodyId))?.custodyNo ?? ''}'}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
    return sheetId;
  }

  Future<void> deleteCustodySheet(LinkCustodySheet s, {String actor = ''}) async {
    final linked = await custodyById(s.custodyId);
    if (linked != null && linked.status == CustodyStatus.cleared) {
      throw LinkBlocked('المسير يخص العهدة ${linked.custodyNo} وهي مُخلَّاة — احذف الإخلاء أولًا');
    }
    await db.transaction(() async {
      await (db.delete(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(s.id))).go();
      await (db.delete(db.linkCustodySheets)..where((t) => t.id.equals(s.id))).go();
    });
    await AuditRepo(db).log(
      action: 'linkage.sheet.delete',
      entityType: 'linkage',
      summary: 'حذف مسير عهدة رقم ${s.sheetNo}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ───────────────── استلام مبلغ مالي ─────────────────

  Future<LinkMoneyReceipt> moneyReceiptById(String id) =>
      (db.select(db.linkMoneyReceipts)..where((t) => t.id.equals(id))).getSingle();

  /// سندات استلام المبالغ، الأحدث أولًا.
  Future<List<LinkMoneyReceipt>> moneyReceipts() async {
    final rows = await db.select(db.linkMoneyReceipts).get();
    rows.sort((a, b) {
      final byDate = b.receiptDate.compareTo(a.receiptDate);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return rows;
  }

  /// يحفظ السند: جديدًا إن لم يوجد، وإلا تعديلًا.
  Future<void> saveMoneyReceipt(LinkMoneyReceiptsCompanion e, {String actor = ''}) async {
    final existing = await (db.select(db.linkMoneyReceipts)..where((t) => t.id.equals(e.id.value))).getSingleOrNull();
    if (existing == null) {
      await db.into(db.linkMoneyReceipts).insert(e);
    } else {
      await (db.update(db.linkMoneyReceipts)..where((t) => t.id.equals(e.id.value)))
          .write(e.copyWith(updatedAt: Value(DateTime.now())));
    }
    await AuditRepo(db).log(
      action: existing == null ? 'linkage.money_receipt.create' : 'linkage.money_receipt.update',
      entityType: 'linkage',
      summary: '${existing == null ? 'تسجيل' : 'تعديل'} سند استلام مبلغ مالي — المستلم: ${e.receiverName.present ? e.receiverName.value : ''}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> deleteMoneyReceipt(LinkMoneyReceipt r, {String actor = ''}) async {
    await (db.delete(db.linkMoneyReceipts)..where((t) => t.id.equals(r.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.money_receipt.delete',
      entityType: 'linkage',
      summary: 'حذف سند استلام مبلغ مالي — المستلم: ${r.receiverName}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }
}
