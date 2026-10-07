part of '../linkage_repo.dart';

/// الأفراد والحالات ودليل المسميات — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkagePersonsRepo on LinkageRepo {
  // ───────────────── الأفراد ─────────────────

  Future<List<LinkPerson>> persons({
    String q = '',
    String status = '',
    String subUnit = '',
    String camp = '',
    String section = '',
    String job = '',
  }) async {
    final rows = await db.select(db.linkPersons).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((p) {
      if (status.isNotEmpty && p.status != status) return false;
      if (subUnit.isNotEmpty && p.subUnit != subUnit) return false;
      if (camp.isNotEmpty && p.camp != camp) return false;
      if (section.isNotEmpty && p.section != section) return false;
      if (job.isNotEmpty && p.job != job) return false;
      if (query.isEmpty) return true;
      final hay = [p.fullName, p.militaryNo, p.phone, p.phone2, p.rank, p.notes]
          .join(' ')
          .toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => a.fullName.compareTo(b.fullName));
    return out;
  }

  Future<LinkPerson?> personById(String id) async {
    if (id.isEmpty) return null;
    final rows = await (db.select(db.linkPersons)..where((t) => t.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// صاحبُ الرقم العسكري إن كان مسجَّلًا لفردٍ آخر — الرقم يُكتب يدويًّا
  /// فيُكتب خطأً مرتين، فالفحص وحده يمنع الالتباس قبل وقوعه. يعيد اسم
  /// صاحبه أو فراغًا.
  Future<String> militaryNoOwner(String no, {String excludeId = ''}) async {
    final v = no.trim();
    if (v.isEmpty) return '';
    final rows = await db.select(db.linkPersons).get();
    for (final p in rows) {
      if (p.militaryNo.trim() == v && p.id != excludeId) return p.fullName;
    }
    return '';
  }

  Future<void> insertPerson(LinkPersonsCompanion e, {String actor = ''}) async {
    await db.into(db.linkPersons).insert(e);
    final name = e.fullName.present ? e.fullName.value : '';
    await AuditRepo(db).log(
      action: 'linkage.person.create',
      entityType: 'linkage',
      summary: 'إضافة فردٍ للقوة البشرية: $name',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> updatePerson(LinkPerson p, LinkPersonsCompanion e, {String actor = ''}) async {
    await (db.update(db.linkPersons)..where((t) => t.id.equals(p.id))).write(e);
    await AuditRepo(db).log(
      action: 'linkage.person.edit',
      entityType: 'linkage',
      summary: 'تعديل بيانات الفرد: ${p.fullName}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> deletePerson(LinkPerson p, {String actor = ''}) async {
    await (db.delete(db.linkPersons)..where((t) => t.id.equals(p.id))).go();
    await (db.delete(db.linkStatusLogs)..where((t) => t.personId.equals(p.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.person.delete',
      entityType: 'linkage',
      summary: 'حذف الفرد: ${p.fullName} (${p.militaryNo})',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ───────────────── الحالات والعودة ─────────────────

  /// تغيير حالة الفرد إلى حالةٍ ذات مدى: تحديثٌ للفرد بسطرٍ في سجل الحالات.
  /// الأيام تُحسب من التاريخين ويمكن تجاوزها بقيمةٍ صريحة.
  Future<void> changeStatus({
    required LinkPerson p,
    required String status,
    required String fromIso,
    required String toIso,
    int? days,
    String notes = '',
    String actor = '',
  }) async {
    final d = days ?? linkDaysBetween(fromIso, toIso);
    await (db.update(db.linkPersons)..where((t) => t.id.equals(p.id))).write(
      LinkPersonsCompanion(
        status: Value(status),
        statusFrom: Value(fromIso),
        statusTo: Value(toIso),
        statusDays: Value(d),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await db.into(db.linkStatusLogs).insert(LinkStatusLogsCompanion.insert(
          id: Ids.next('ls'),
          personId: p.id,
          personName: Value(p.fullName),
          status: status,
          fromDate: Value(fromIso),
          toDate: Value(toIso),
          days: Value(d),
          notes: Value(notes),
          actor: Value(actor),
        ));
    await AuditRepo(db).log(
      action: 'linkage.person.status',
      entityType: 'linkage',
      summary: 'تغيير حالة «${p.fullName}» إلى ${LinkStatus.label(status)}',
      details: {'from': fromIso, 'to': toIso, 'days': d},
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// عودة الفرد من إجازة/غياب: يصير «موجودًا» ويُسجَّل الإجراء المتخذ
  /// (مواصلة عمل / مباشرة عمل) في سجل حالته.
  Future<void> returnToWork({
    required LinkPerson p,
    required String action,
    String notes = '',
    String actor = '',
  }) async {
    final today = isoDay(DateTime.now());
    await (db.update(db.linkPersons)..where((t) => t.id.equals(p.id))).write(
      LinkPersonsCompanion(
        status: const Value(LinkStatus.present),
        statusFrom: Value(today),
        statusTo: const Value(''),
        statusDays: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await db.into(db.linkStatusLogs).insert(LinkStatusLogsCompanion.insert(
          id: Ids.next('ls'),
          personId: p.id,
          personName: Value(p.fullName),
          status: LinkStatus.present,
          fromDate: Value(today),
          days: const Value(0),
          returnAction: Value(action),
          notes: Value(notes),
          actor: Value(actor),
        ));
    await AuditRepo(db).log(
      action: 'linkage.person.return',
      entityType: 'linkage',
      summary: 'عودة «${p.fullName}» — الإجراء: $action',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// سجل حالات فردٍ، الأحدث أولًا.
  Future<List<LinkStatusLog>> statusLog(String personId) async {
    final rows = await (db.select(db.linkStatusLogs)
          ..where((t) => t.personId.equals(personId)))
        .get();
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  /// كل ما ارتبط بالفرد — التسليح فقط (المالية غير مرتبطة بالأفراد).
  Future<LinkPersonRecords> linkedRecords(String personId) async {
    if (personId.isEmpty) return (armaments: const <LinkArmament>[]);
    final armaments = await (db.select(db.linkArmaments)
          ..where((t) => t.personId.equals(personId)))
        .get();
    armaments.sort((a, b) => b.assignedDate.compareTo(a.assignedDate));
    return (armaments: armaments);
  }

  // ───────────────── دليل المسميات ─────────────────


  /// يملأ الدليل بقيمه الافتراضية إن كان فارغًا — يُستدعى عند فتح الشاشة.
  Future<void> ensureSeedTerms() async {
    final any = await (db.select(db.linkTerms)..limit(1)).get();
    if (any.isNotEmpty) return;
    for (final e in LinkageRepo.kDefaultTerms.entries) {
      for (final name in e.value) {
        await db.into(db.linkTerms).insert(
              LinkTermsCompanion.insert(kind: e.key, name: name),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }

  Future<List<LinkTerm>> terms(String kind) async {
    final rows = await (db.select(db.linkTerms)..where((t) => t.kind.equals(kind))).get();
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  /// يحفظ قيمةً جديدة في الدليل إن لم تُسبق — فإضافةُ قسمٍ أو عملٍ تحدث
  /// من حفظ الفرد نفسه دون فتح شاشة أخرى.
  Future<void> addTermIfNew(String kind, String name) async {
    final v = name.trim();
    if (v.isEmpty) return;
    await db.into(db.linkTerms).insert(
          LinkTermsCompanion.insert(kind: kind, name: v),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> deleteTerm(String kind, String name) async {
    await (db.delete(db.linkTerms)
          ..where((t) => t.kind.equals(kind) & t.name.equals(name)))
        .go();
  }
}
