import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../../core/ids.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart' show ImdTone;
import '../db/app_database.dart';
import 'audit_repo.dart';

/// حالات الفرد وبياناتها للعرض — المصدر الوحيد للمفاتيح والنبرات.
class LinkStatus {
  static const String present = 'present';
  static const String absent = 'absent';
  static const String mission = 'mission';
  static const String leave = 'leave';
  static const String permission = 'permission';
  static const String deserter = 'deserter';

  /// المفتاح ⇒ (التسمية، النبرة).
  static const Map<String, (String, ImdTone)> meta = {
    present: ('موجود', ImdTone.ok),
    absent: ('غياب', ImdTone.pend),
    mission: ('مهمة', ImdTone.info),
    leave: ('إجازة', ImdTone.code),
    permission: ('إذن', ImdTone.pend),
    deserter: ('فرار', ImdTone.err),
  };

  /// حالات «ذات مدى» تُؤرَّخ من/إلى — «موجود» لا يحتاج مدى.
  static const List<String> dated = [absent, mission, leave, permission, deserter];

  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.off;
  static bool isDated(String s) => dated.contains(s);
}

/// أنواع الإخلاء.
class LinkClearanceKind {
  static const String custody = 'custody';
  static const String contract = 'contract';
  static const String other = 'other';

  static const Map<String, (String, ImdTone)> meta = {
    custody: ('عهدة', ImdTone.code),
    contract: ('عقد', ImdTone.info),
    other: ('حر', ImdTone.off),
  };

  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.off;
}

/// حالات عقد المشتريات.
class LinkContractStatus {
  static const String open = 'open';
  static const String done = 'done';
  static const String canceled = 'canceled';

  static const Map<String, (String, ImdTone)> meta = {
    open: ('قيد التنفيذ', ImdTone.info),
    done: ('منفَّذ', ImdTone.ok),
    canceled: ('ملغى', ImdTone.err),
  };

  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.off;
}

/// إجراء العودة من إجازة/غياب.
const List<String> kLinkReturnActions = ['مواصلة عمل', 'مباشرة عمل'];

/// عدد أيام مدىٍ مؤرَّخ — شاملُ الطرفين (إجازة من 5 إلى 5 = يومٌ واحد).
int linkDaysBetween(String fromIso, String toIso) {
  final a = DateTime.tryParse(fromIso);
  final b = DateTime.tryParse(toIso);
  if (a == null || b == null) return 0;
  final d = DateUtils.dateOnly(b).difference(DateUtils.dateOnly(a)).inDays + 1;
  return d > 0 ? d : 0;
}

/// سجلات فردٍ مرتبطة به — التسليح فقط: العهد والعقود والإخلاءات مالية الإمداد
/// وليست مرتبطةً بالأفراد.
typedef LinkPersonRecords = ({List<LinkArmament> armaments});

/// مستودع الارتباطات: القوة البشرية وحالاتها المؤرخة وإجراءات العودة،
/// ودليل المسميات (أقسام/أعمال/وحدات فرعية)، والعهد والإخلاءات، وعقود
/// المشتريات، والتسليح — وكل ارتباطٍ بالفرد بمعرّفه ولقطة اسمه ورقمه.
class LinkageRepo {
  LinkageRepo(this.db);

  final AppDatabase db;

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
    var out = rows.where((p) {
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
        status: Value(LinkStatus.present),
        statusFrom: Value(today),
        statusTo: Value(''),
        statusDays: Value(0),
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

  /// القيم الافتراضية التي يُ seeded بها الدليل أول مرة.
  static const Map<String, List<String>> kDefaultTerms = {
    'section': ['مخزن', 'مطبخ', 'فرن', 'سائق', 'مكتب', 'مختص'],
    'job': ['معلم أرز', 'معلم مشكل', 'معلم شواية', 'معلم خباز', 'معلم عجان'],
    'subunit': ['إمداد', 'محروقات', 'مياه'],
    // الجهات المسؤولة عن العهد (مالية الإمداد).
    'holder': ['المستودع الرئيسي', 'المطبخ', 'الفرن', 'مكتب الإمداد', 'الورشة'],
  };

  /// يملأ الدليل بقيمه الافتراضية إن كان فارغًا — يُستدعى عند فتح الشاشة.
  Future<void> ensureSeedTerms() async {
    final any = await (db.select(db.linkTerms)..limit(1)).get();
    if (any.isNotEmpty) return;
    for (final e in kDefaultTerms.entries) {
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
    await db.into(db.linkFinCustodies).insert(e);
    final holder = e.holder.present ? e.holder.value : '';
    if (holder.isNotEmpty) await addTermIfNew('holder', holder);
    await AuditRepo(db).log(
      action: 'linkage.custody.create',
      entityType: 'linkage',
      summary: 'تسجيل عهدة «${e.title.present ? e.title.value : ''}» — الجهة: $holder',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> updateCustody(LinkFinCustody c, LinkFinCustodiesCompanion e, {String actor = ''}) async {
    await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(c.id))).write(e);
    final holder = e.holder.present ? e.holder.value : '';
    if (holder.isNotEmpty) await addTermIfNew('holder', holder);
    await AuditRepo(db).log(
      action: 'linkage.custody.edit',
      entityType: 'linkage',
      summary: 'تعديل عهدة «${c.title}»',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// حذف العهدة يحذف إخلاءاتها أيضًا — لا إخلاء بلا مرجع.
  Future<void> deleteCustody(LinkFinCustody c, {String actor = ''}) async {
    await db.transaction(() async {
      await (db.delete(db.linkClearances)
            ..where((t) => t.kind.equals(LinkClearanceKind.custody) & t.refId.equals(c.id)))
          .go();
      await (db.delete(db.linkFinCustodies)..where((t) => t.id.equals(c.id))).go();
    });
    await AuditRepo(db).log(
      action: 'linkage.custody.delete',
      entityType: 'linkage',
      summary: 'حذف عهدة «${c.title}» — الجهة: ${c.holder}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
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
    await db.transaction(() async {
      if (kind == LinkClearanceKind.custody && refId.isNotEmpty) {
        final c = await (db.select(db.linkFinCustodies)..where((t) => t.id.equals(refId))).getSingleOrNull();
        if (c != null) {
          title = title.isEmpty ? c.title : title;
          party = party.isEmpty ? c.holder : party;
          await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(refId))).write(
            LinkFinCustodiesCompanion(
              cleared: const Value(true),
              clearedDate: Value(clearanceDate),
              clearanceNotes: Value(notes),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      } else if (kind == LinkClearanceKind.contract && refId.isNotEmpty) {
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
        await (db.update(db.linkFinCustodies)..where((t) => t.id.equals(c.refId))).write(
          const LinkFinCustodiesCompanion(
            cleared: Value(false),
            clearedDate: Value(''),
            clearanceNotes: Value(''),
          ),
        );
      } else if (c.kind == LinkClearanceKind.contract) {
        await (db.update(db.linkPurchaseContracts)..where((t) => t.id.equals(c.refId))).write(
          const LinkPurchaseContractsCompanion(status: Value(LinkContractStatus.open)),
        );
      }
    });
    await AuditRepo(db).log(
      action: 'linkage.clearance.delete',
      entityType: 'linkage',
      summary: 'حذف إخلاء «${c.refTitle}» وإعادة فتح مرجعه',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ───────────────── عقود المشتريات ─────────────────

  Future<List<LinkPurchaseContract>> contracts({String q = '', String status = ''}) async {
    final rows = await db.select(db.linkPurchaseContracts).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((c) {
      if (status.isNotEmpty && c.status != status) return false;
      if (query.isEmpty) return true;
      final hay = [c.contractNo, c.title, c.supplier, c.itemsSummary].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => b.signDate.compareTo(a.signDate));
    return out;
  }

  Future<void> insertContract(LinkPurchaseContractsCompanion e, {String actor = ''}) async {
    await db.into(db.linkPurchaseContracts).insert(e);
    await AuditRepo(db).log(
      action: 'linkage.contract.create',
      entityType: 'linkage',
      summary: 'تسجيل عقد مشتريات: ${e.title.present ? e.title.value : ''}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> updateContract(
      LinkPurchaseContract c, LinkPurchaseContractsCompanion e,
      {String actor = ''}) async {
    await (db.update(db.linkPurchaseContracts)..where((t) => t.id.equals(c.id))).write(e);
    await AuditRepo(db).log(
      action: 'linkage.contract.edit',
      entityType: 'linkage',
      summary: 'تعديل عقد: ${c.title}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> deleteContract(LinkPurchaseContract c, {String actor = ''}) async {
    await (db.delete(db.linkPurchaseContracts)..where((t) => t.id.equals(c.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.contract.delete',
      entityType: 'linkage',
      summary: 'حذف عقد: ${c.title}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ───────────────── التسليح ─────────────────

  Future<List<LinkArmament>> armaments({String q = '', String view = ''}) async {
    final rows = await db.select(db.linkArmaments).get();
    final query = q.trim().toLowerCase();
    var out = rows.where((a) {
      if (view == 'out' && a.returned) return false;
      if (view == 'returned' && !a.returned) return false;
      if (query.isEmpty) return true;
      final hay = [
        a.personName,
        a.personMilitaryNo,
        a.weaponType,
        a.serialNo,
        a.condition,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    out.sort((a, b) => b.assignedDate.compareTo(a.assignedDate));
    return out;
  }

  Future<void> insertArmament(LinkArmamentsCompanion e, {String actor = ''}) async {
    await db.into(db.linkArmaments).insert(e);
    await AuditRepo(db).log(
      action: 'linkage.armament.assign',
      entityType: 'linkage',
      summary:
          'تسليم سلاح «${e.weaponType.present ? e.weaponType.value : ''}» للفرد ${e.personName.present ? e.personName.value : ''}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// ردّ السلاح بتاريخه.
  Future<void> returnArmament(LinkArmament a,
      {required String returnedDate, String actor = ''}) async {
    await (db.update(db.linkArmaments)..where((t) => t.id.equals(a.id))).write(
      LinkArmamentsCompanion(
        returned: Value(true),
        returnedDate: Value(returnedDate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await AuditRepo(db).log(
      action: 'linkage.armament.return',
      entityType: 'linkage',
      summary: 'ردّ سلاح «${a.weaponType}» من الفرد ${a.personName}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  Future<void> deleteArmament(LinkArmament a, {String actor = ''}) async {
    await (db.delete(db.linkArmaments)..where((t) => t.id.equals(a.id))).go();
    await AuditRepo(db).log(
      action: 'linkage.armament.delete',
      entityType: 'linkage',
      summary: 'حذف سجل تسليح «${a.weaponType}» — الفرد: ${a.personName}',
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
  }

  // ═══════════════════ إضافات النسخة Pro ═══════════════════

  /// إحصائيات القوة البشرية — تُعرض في لوحة المؤشرات.
  Future<Map<String, int>> personnelStats() async {
    final rows = await db.select(db.linkPersons).get();
    final stats = <String, int>{
      'total': rows.length,
      for (final k in LinkStatus.meta.keys) k: 0,
    };
    for (final p in rows) {
      stats[p.status] = (stats[p.status] ?? 0) + 1;
    }
    return stats;
  }

  /// تنبيهات ذكية: إجازات/غياب منتهية أو قريبة الانتهاء، فرار، عهد متأخرة، عقود تنتهي قريبًا.
  Future<List<LinkAlert>> getAlerts({int leaveWarnDays = 3, int contractWarnDays = 14}) async {
    final alerts = <LinkAlert>[];
    final today = DateTime.now();

    // 1) حالات مؤرخة منتهية أو قريبة
    final persons = await db.select(db.linkPersons).get();
    for (final p in persons) {
      if (p.status == LinkStatus.deserter) {
        alerts.add(LinkAlert(
          type: LinkAlertType.deserter,
          severity: LinkAlertSeverity.critical,
          title: 'فرار: ${p.fullName}',
          body: 'الرقم العسكري: ${p.militaryNo.isEmpty ? "—" : p.militaryNo} · منذ ${_d(p.statusFrom)}',
          personId: p.id,
          personName: p.fullName,
        ));
        continue;
      }
      if (!LinkStatus.isDated(p.status) || p.statusTo.isEmpty) continue;
      final end = DateTime.tryParse(p.statusTo);
      if (end == null) continue;
      final daysLeft = DateUtils.dateOnly(end).difference(DateUtils.dateOnly(today)).inDays;
      if (daysLeft < 0) {
        alerts.add(LinkAlert(
          type: LinkAlertType.statusExpired,
          severity: LinkAlertSeverity.high,
          title: 'انتهت حالة «${LinkStatus.label(p.status)}»: ${p.fullName}',
          body: 'انتهت في ${_d(p.statusTo)} · لم يُسجَّل عودة بعد',
          personId: p.id,
          personName: p.fullName,
        ));
      } else if (daysLeft <= leaveWarnDays) {
        alerts.add(LinkAlert(
          type: LinkAlertType.statusEnding,
          severity: LinkAlertSeverity.medium,
          title: 'تنتهي قريبًا «${LinkStatus.label(p.status)}»: ${p.fullName}',
          body: daysLeft == 0 ? 'تنتهي اليوم' : 'متبقي $daysLeft يوم · حتى ${_d(p.statusTo)}',
          personId: p.id,
          personName: p.fullName,
        ));
      }
    }

    // 2) عهد متأخرة (dueDate فات ولم تُخلَّ)
    final custodies = await db.select(db.linkFinCustodies).get();
    for (final c in custodies) {
      if (c.cleared || c.dueDate.isEmpty) continue;
      final due = DateTime.tryParse(c.dueDate);
      if (due == null) continue;
      if (DateUtils.dateOnly(due).isBefore(DateUtils.dateOnly(today))) {
        alerts.add(LinkAlert(
          type: LinkAlertType.custodyOverdue,
          severity: LinkAlertSeverity.high,
          title: 'عهدة متأخرة: ${c.title}',
          body: 'الجهة: ${c.holder.isEmpty ? "—" : c.holder} · الأجل كان ${_d(c.dueDate)}',
          relatedId: c.id,
        ));
      }
    }

    // 3) عقود تنتهي قريبًا
    final contracts = await db.select(db.linkPurchaseContracts).get();
    for (final ct in contracts) {
      if (ct.status != LinkContractStatus.open || ct.endDate.isEmpty) continue;
      final end = DateTime.tryParse(ct.endDate);
      if (end == null) continue;
      final daysLeft = DateUtils.dateOnly(end).difference(DateUtils.dateOnly(today)).inDays;
      if (daysLeft < 0) {
        alerts.add(LinkAlert(
          type: LinkAlertType.contractExpired,
          severity: LinkAlertSeverity.high,
          title: 'عقد منتهٍ: ${ct.title}',
          body: 'انتهى في ${_d(ct.endDate)} · ما زال «قيد التنفيذ»',
          relatedId: ct.id,
        ));
      } else if (daysLeft <= contractWarnDays) {
        alerts.add(LinkAlert(
          type: LinkAlertType.contractEnding,
          severity: LinkAlertSeverity.medium,
          title: 'عقد ينتهي قريبًا: ${ct.title}',
          body: daysLeft == 0 ? 'ينتهي اليوم' : 'متبقي $daysLeft يوم · ${ct.contractNo}',
          relatedId: ct.id,
        ));
      }
    }

    // ترتيب: حرج → عالي → متوسط
    alerts.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return alerts;
  }

  static String _d(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? (iso.isEmpty ? '—' : iso) : iso; // keep raw; UI formats
  }
}

/// نوع التنبيه.
enum LinkAlertType {
  deserter,
  statusExpired,
  statusEnding,
  custodyOverdue,
  contractExpired,
  contractEnding,
}

/// شدة التنبيه.
enum LinkAlertSeverity { critical, high, medium, low }

/// تنبيه ذكي مرتبط بالقوة البشرية أو المالية أو العقود.
class LinkAlert {
  const LinkAlert({
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    this.personId = '',
    this.personName = '',
    this.relatedId = '',
  });

  final LinkAlertType type;
  final LinkAlertSeverity severity;
  final String title;
  final String body;
  final String personId;
  final String personName;
  final String relatedId;
}
