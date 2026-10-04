import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../../core/ids.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart' show ImdTone;
import '../../domain/custody_sheet.dart';
import '../../domain/finance.dart';
import 'doc_numbering.dart';
import 'finance_files.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import '../../core/error_log.dart';

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

  /// الحالات المضافة من المستخدم (مثل «مريض مستشفى») تُحفظ في دليل المسميات
  /// (`link_terms` نوع `status`) ويكون **اسمها هو مفتاحها**، فتُعرض كما كُتبت
  /// وتبقى سجلات الأفراد سليمةً لو حُذفت من الدليل. وهي كلها ذات مدى.
  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.info;
  static bool isDated(String s) => s.isNotEmpty && s != present;
}

/// عملة فاتورة الشراء.
class LinkCurrency {
  static const String sar = 'sar';
  static const String yer = 'yer';

  static const Map<String, String> labels = {sar: 'سعودي', yer: 'يمني'};

  static String label(String c) => labels[c] ?? c;

  /// الاسم في التفقيط: «ريال يمني».
  static String major(String c) => c == yer ? 'ريال يمني' : 'ريال سعودي';

  /// الوحدة الصغرى في التفقيط.
  static String minor(String c) => c == yer ? 'فلس' : 'هللة';

  /// رمز العملة في الجداول المطبوعة.
  static String symbol(String c) => c == yer ? 'ر.ي.' : 'ر.س.';
}

/// سطر أصناف في عقد الشراء. نصٌّ حر بلا صلة بأصناف النظام.
class ContractItem {
  const ContractItem({
    this.name = '',
    this.unit = '',
    this.qty = 0,
    this.price = 0,
    this.total = 0,
    this.invoiceNo = '',
    this.date = '',
    this.note = '',
  });

  final String name;
  final String unit;
  final double qty;
  final double price;

  /// السعر الإجمالي — يُحسب افتراضيًّا (الكمية × السعر) ويقبل التعديل.
  final double total;
  final String invoiceNo;

  /// تاريخ الشراء حسب الفاتورة (يدوي).
  final String date;
  final String note;

  bool get isEmpty =>
      name.trim().isEmpty && unit.trim().isEmpty && qty == 0 && price == 0 && total == 0 && invoiceNo.trim().isEmpty && note.trim().isEmpty;

  /// الإجمالي الافتراضي: الكمية × سعر الوحدة (الكمية الفارغة تُعدّ واحدًا).
  static double autoTotal(double qty, double price) => (qty > 0 ? qty : 1) * price;

  Map<String, Object> toJson() => {
        'name': name,
        'unit': unit,
        'qty': qty,
        'price': price,
        'total': total,
        'invoiceNo': invoiceNo,
        'date': date,
        'note': note,
      };

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static List<ContractItem> decode(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map)
            ContractItem(
              name: '${e['name'] ?? ''}',
              unit: '${e['unit'] ?? ''}',
              qty: _d(e['qty']),
              price: _d(e['price']),
              total: _d(e['total']),
              invoiceNo: '${e['invoiceNo'] ?? ''}',
              date: '${e['date'] ?? ''}',
              note: '${e['note'] ?? ''}',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<ContractItem> items) =>
      jsonEncode([for (final i in items) if (!i.isEmpty) i.toJson()]);

  /// إجمالي القائمة.
  static double sum(Iterable<ContractItem> items) => items.fold(0.0, (s, e) => s + e.total);
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
        if (c.workflow != wfApproved) return;
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

  // ───────────────── إخلاء العهدة المالي ─────────────────

  static const String wfDraft = 'draft';
  static const String wfSent = 'sent';
  static const String wfApproved = 'approved';
  static const Map<String, String> workflowLabels = {wfDraft: 'مسودة', wfSent: 'مُرسل', wfApproved: 'مُعتمد'};

  static String partyOf(LinkFinCustody c) => c.receiverName.trim().isNotEmpty ? c.receiverName.trim() : c.holder.trim();

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
      counterparty: c.kind == CustodyKind.received ? 'المالية' : partyOf(c),
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
    String workflow = wfApproved,
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
    final approvedBefore = prev?.workflow == wfApproved;
    if (approvedBefore && workflow != wfApproved) {
      throw const LinkBlocked('الإخلاء المُعتمد لا يعود مسودة — احذفه ليُعاد فتح العهدة');
    }
    if (!workflowLabels.containsKey(workflow)) throw const LinkBlocked('حالة الإخلاء غير معروفة');
    // الاعتماد يُغلق العهدة، فلا يجوز لعهدةٍ لم تعد قيد الإخلاء (أُلغيت بعد المسودة).
    if (workflow == wfApproved && !approvedBefore && custody.status != CustodyStatus.open) {
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
      partyName: Value(partyOf(custody)),
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
      if (workflow == wfApproved && !approvedBefore) {
        await _closeCustody(custody, diff, clearanceDate, notes, rowId, no, actor);
      }
    });
    await AuditRepo(db).log(
      action: prev == null ? 'linkage.clearance.create' : 'linkage.clearance.edit',
      entityType: 'linkage',
      summary: '${prev == null ? 'إخلاء' : 'تعديل إخلاء'} العهدة ${custody.custodyNo} ($no) — ${workflowLabels[workflow]} — '
          '${diff.phrase(custodyKind: custody.kind, counterparty: st.counterparty)}'
          '${diff.amount == 0 ? '' : ' ${diff.amount} ${FinCurrency.label(custody.currency)}'}',
      risk: workflow == wfApproved ? AuditRepo.riskHigh : AuditRepo.riskNormal,
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
          partyName: Value(partyOf(custody).isEmpty ? 'غير محدد' : partyOf(custody)),
          custodyId: Value(custody.id),
          clearanceId: Value(clearanceId),
          entryKind: Value(surplus ? 'surplus' : 'deficit'),
          delta: Value(surplus ? diff.amount : -diff.amount),
          currency: Value(custody.currency),
          entryDate: Value(date),
          note: Value('إخلاء ${custody.custodyNo} ($no): ${diff.phrase(custodyKind: custody.kind, counterparty: custody.kind == CustodyKind.received ? 'المالية' : partyOf(custody))}'),
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
      if (partyOf(c) != party || c.status != CustodyStatus.open) continue;
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
      add(partyOf(c), c.currency, c.kind == CustodyKind.received ? -amt : amt);
    }
    for (final e in ledger) {
      add(e.partyName, e.currency, e.delta);
    }
    return out;
  }

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


  /// ما يسحبه سطر المسير من عقد: التاريخ والفئة والمحل والمنصرف بعملة العقد وسعر الصرف.
  /// (المنصرف السعودي لعقدٍ يمني محسوبٌ فلا يدخل المقارنة.)
  static ({String date, String category, String shop, double amount, double rate, bool yer}) rowFromContract(LinkPurchaseContract k) =>
      (date: k.listDate, category: k.title.trim(), shop: k.supplier, amount: k.amount, rate: k.exchangeRate, yer: k.currency == LinkCurrency.yer);

  /// عند تعديل عقدٍ يتحدث ما سُحب منه في المسيرات: كل سطرٍ برقم فاتورة العقد في
  /// مسيرٍ لعهدة العقد نفسها، **لم يعدّله المستخدم** بعد السحب (قيمه ما تزال ما
  /// كان يسحبه العقد القديم). ما عُدِّل يدويًّا يبقى كما هو.
  Future<int> _syncSheetsFromContract(LinkPurchaseContract old, LinkPurchaseContract now) async {
    if (now.custodyId.isEmpty || old.custodyId != now.custodyId) return 0;
    final before = rowFromContract(old);
    final after = rowFromContract(now);
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

  // ───────────────── التسليح ─────────────────

  Future<List<LinkArmament>> armaments({String q = '', String view = ''}) async {
    final rows = await db.select(db.linkArmaments).get();
    final query = q.trim().toLowerCase();
    final out = rows.where((a) {
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

  /// تعديل سجل تسليحٍ محفوظ (السلاح والقرون والذخيرة والتاريخ والملاحظات).
  Future<void> updateArmament(String id, LinkArmamentsCompanion e, {String actor = ''}) async {
    await (db.update(db.linkArmaments)..where((t) => t.id.equals(id))).write(
      e.copyWith(updatedAt: Value(DateTime.now())),
    );
    await AuditRepo(db).log(
      action: 'linkage.armament.update',
      entityType: 'linkage',
      summary:
          'تعديل سجل تسليح «${e.weaponType.present ? e.weaponType.value : ''}» للفرد ${e.personName.present ? e.personName.value : ''}',
      risk: AuditRepo.riskNormal,
      actorEmail: actor,
    );
  }

  /// ردّ السلاح بتاريخه.
  Future<void> returnArmament(LinkArmament a,
      {required String returnedDate, String actor = ''}) async {
    await (db.update(db.linkArmaments)..where((t) => t.id.equals(a.id))).write(
      LinkArmamentsCompanion(
        returned: const Value(true),
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
      // المُخلَّاة والملغاة لا تُنبَّه.
      if (c.cleared || c.status != CustodyStatus.open || c.dueDate.isEmpty) continue;
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

/// رقم فاتورة العقد: المكتوب في رأس العقد، وإلا أول رقمٍ في أسطر الأصناف
/// (عقودٌ حُفظت قبل وجود الحقل).
extension LinkContractInvoice on LinkPurchaseContract {
  String get displayInvoiceNo {
    if (invoiceNo.trim().isNotEmpty) return invoiceNo.trim();
    for (final i in ContractItem.decode(itemsJson)) {
      if (i.invoiceNo.trim().isNotEmpty) return i.invoiceNo.trim();
    }
    return '';
  }

  /// هل رقم الفاتورة [no] هو رقم هذا العقد (بلا فرق حالة أحرف أو فراغات)؟
  bool matchesInvoice(String no) {
    final v = no.trim().toLowerCase();
    if (v.isEmpty) return false;
    return displayInvoiceNo.toLowerCase() == v ||
        ContractItem.decode(itemsJson).any((i) => i.invoiceNo.trim().toLowerCase() == v);
  }
}

/// منعٌ مقصود لعمليةٍ ماليةٍ مخالفةٍ للقواعد (تكرار رقم، حذف مرتبط…). رسالته
/// عربية مقروءة تُعرض للمستخدم كما هي.
class LinkBlocked implements Exception {
  const LinkBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

/// استهلاك عهدة: مجموع عقودها بعملتها، وعددها، وما تعذّر تحويله.
class CustodyUsage {
  const CustodyUsage({this.consumed = 0, this.contracts = 0, this.unconvertible = 0});
  final double consumed;
  final int contracts;
  final int unconvertible;
}

/// تسوية عهدة: ما خُصِّص وما صُرف وما أُرجع، والفرق وطرفه المقابل.
class CustodySettlement {
  const CustodySettlement({
    required this.custody,
    required this.granted,
    required this.spent,
    required this.returned,
    required this.sheets,
    required this.diff,
    required this.counterparty,
  });

  final LinkFinCustody custody;
  final double granted;
  final double spent;
  final double returned;

  /// عدد مسيرات العهدة — صفر يعني أن المصروف صفر لأنه لم يُسجَّل لا لأنه لم يقع.
  final int sheets;
  final CustodyDiff diff;
  final String counterparty;
}

/// سطر في كشف حساب مالية.
class StatementLine {
  const StatementLine({required this.date, required this.label, required this.delta, required this.currency, required this.kind});
  final String date;
  final String label;
  final double delta;
  final String currency;
  final String kind;
}

class PartyStatement {
  const PartyStatement({required this.party, required this.lines, required this.balance});
  final String party;
  final List<StatementLine> lines;

  /// الرصيد لكل عملة: الموجب لصاحب العهدة (دائن)، والسالب عليه (مدين).
  final Map<String, double> balance;
}
