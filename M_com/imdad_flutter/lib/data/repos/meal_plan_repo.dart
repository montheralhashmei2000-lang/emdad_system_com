import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/meal_plan.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';

/// خطة مع مدخلاتها.
class MealPlanFull {
  const MealPlanFull({required this.plan, required this.entries});

  final MealPlan plan;
  final List<MealPlanEntry> entries;

  DateSpan get span => DateSpan(plan.startDate, plan.endDate);

  List<MealEntry> get domainEntries => [
        for (final e in entries)
          MealEntry(
            entryDate: e.entryDate,
            mealType: e.mealType,
            itemId: e.itemId,
            qtyPerPerson: e.qtyPerPerson,
            factor: e.factor,
            itemName: e.itemName,
            unitName: e.unitName,
          ),
      ];
}

class MealPlanResult {
  const MealPlanResult({required this.ok, this.error = '', this.planId = ''});

  final bool ok;
  final String error;
  final String planId;
}

/// خطط الوجبات: بناؤها وتنشيطها واستنساخها، وحساب احتياجها من القوة المسجّلة.
class MealPlanRepo {
  MealPlanRepo(this.db);

  final AppDatabase db;

  // ───────────────────────── قراءة

  Future<List<MealPlan>> plans({String status = '', List<String>? scope}) async {
    final q = db.select(db.mealPlans);
    if (status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (scope != null) {
      q.where((t) => t.warehouse.isIn(scope) | t.warehouse.equals(''));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    return q.get();
  }

  Future<MealPlanFull?> byId(String id) async {
    final rows = await (db.select(db.mealPlans)..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty) return null;
    return MealPlanFull(plan: rows.first, entries: await entries(id));
  }

  Future<List<MealPlanEntry>> entries(String planId) async {
    final rows = await (db.select(db.mealPlanEntries)
          ..where((t) => t.planId.equals(planId)))
        .get();
    // الترتيب بالتاريخ ثم بترتيب الوجبة في اليوم لا بأبجدية رمزها: الفطور قبل
    // الغداء قبل العشاء، وترتيب الحروف يضع العشاء أولًا.
    rows.sort((a, b) {
      final d = a.entryDate.compareTo(b.entryDate);
      if (d != 0) return d;
      return MealType.all.indexOf(a.mealType).compareTo(MealType.all.indexOf(b.mealType));
    });
    return rows;
  }

  /// الخطة النشطة التي تغطي [date] لهذا المرفق — مصدرُ احتياج اليوم.
  Future<MealPlanFull?> activeOn(String date, {String facilityId = ''}) async {
    final rows = await (db.select(db.mealPlans)
          ..where((t) => t.status.equals(MealPlanStatus.active)))
        .get();
    for (final p in rows) {
      if (facilityId.isNotEmpty && p.facilityId.isNotEmpty && p.facilityId != facilityId) {
        continue;
      }
      if (DateSpan(p.startDate, p.endDate).contains(date)) {
        return MealPlanFull(plan: p, entries: await entries(p.id));
      }
    }
    return null;
  }

  // ───────────────────────── كتابة

  Future<MealPlanResult> savePlan({
    String? id,
    required String name,
    required String planType,
    required DateSpan span,
    String facilityId = '',
    String facilityName = '',
    String warehouse = '',
    String notes = '',
    String actor = '',
  }) async {
    for (final error in [
      MealPlanRules.validateName(name),
      MealPlanRules.validateSpan(span),
    ]) {
      if (error != null) return MealPlanResult(ok: false, error: '✖ $error');
    }

    final planId = id ?? Ids.next('mpl');
    final existing = id == null ? null : await byId(id);
    await db.into(db.mealPlans).insertOnConflictUpdate(MealPlansCompanion.insert(
          id: planId,
          name: name.trim(),
          planType: Value(planType),
          startDate: Value(span.start),
          endDate: Value(span.end),
          status: Value(existing?.plan.status ?? MealPlanStatus.draft),
          facilityId: Value(facilityId),
          facilityName: Value(facilityName),
          warehouse: Value(warehouse),
          notes: Value(notes),
          createdBy: Value(existing?.plan.createdBy ?? actor),
          updatedAt: Value(id == null ? null : DateTime.now()),
        ));

    // تضييق المدى يترك مدخلات خارجه معلَّقة: تُحذف هنا، وإلا احتُسبت في
    // الاحتياج وهي في يوم لا تعرضه الشاشة.
    if (existing != null) {
      await (db.delete(db.mealPlanEntries)
            ..where((t) =>
                t.planId.equals(planId) &
                (t.entryDate.isSmallerThanValue(span.start) |
                    t.entryDate.isBiggerThanValue(span.end))))
          .go();
    }

    await AuditRepo(db).log(
      action: id == null ? 'mealplan.create' : 'mealplan.update',
      entityType: 'خطة وجبات',
      summary: '${id == null ? 'إنشاء' : 'تعديل'} خطة «${name.trim()}»',
      details: {'planId': planId, 'from': span.start, 'to': span.end},
      actorEmail: actor,
    );
    return MealPlanResult(ok: true, planId: planId);
  }

  /// إضافة صنف إلى وجبة يوم. التكرار يُجمَّع في سطر واحد لا يُضاعَف.
  Future<MealPlanResult> addEntry({
    required String planId,
    required String entryDate,
    required String mealType,
    required String itemId,
    required String itemCode,
    required String itemName,
    required String unitName,
    required double factor,
    required double qtyPerPerson,
    String notes = '',
  }) async {
    final full = await byId(planId);
    if (full == null) return const MealPlanResult(ok: false, error: '✖ الخطة غير موجودة');
    final dateError = MealPlanRules.validateEntryDate(entryDate, full.span);
    if (dateError != null) return MealPlanResult(ok: false, error: '✖ $dateError');
    if (qtyPerPerson <= 0) {
      return const MealPlanResult(ok: false, error: '✖ الكمية للفرد أكبر من صفر');
    }

    final twin = full.entries.where((e) =>
        e.entryDate == entryDate && e.mealType == mealType && e.itemId == itemId);
    if (twin.isNotEmpty) {
      await (db.update(db.mealPlanEntries)..where((t) => t.id.equals(twin.first.id)))
          .write(MealPlanEntriesCompanion(
        qtyPerPerson: Value(twin.first.qtyPerPerson + qtyPerPerson),
      ));
      return MealPlanResult(ok: true, planId: planId);
    }

    await db.into(db.mealPlanEntries).insert(MealPlanEntriesCompanion.insert(
          id: Ids.next('mpe'),
          planId: planId,
          entryDate: Value(entryDate),
          mealType: Value(mealType),
          itemId: Value(itemId),
          itemCode: Value(itemCode),
          itemName: Value(itemName),
          unitName: Value(unitName),
          factor: Value(factor),
          qtyPerPerson: Value(qtyPerPerson),
          notes: Value(notes),
        ));
    return MealPlanResult(ok: true, planId: planId);
  }

  Future<void> deleteEntry(String entryId) =>
      (db.delete(db.mealPlanEntries)..where((t) => t.id.equals(entryId))).go();

  /// نسخ وجبات يوم إلى يوم آخر — أكثر ما يُختصر به بناء خطة شهرية.
  Future<int> copyDay({
    required String planId,
    required String from,
    required String to,
  }) async {
    final full = await byId(planId);
    if (full == null || !full.span.contains(to)) return 0;
    final source = full.entries.where((e) => e.entryDate == from).toList();
    if (source.isEmpty) return 0;
    await db.transaction(() async {
      await (db.delete(db.mealPlanEntries)
            ..where((t) => t.planId.equals(planId) & t.entryDate.equals(to)))
          .go();
      for (final e in source) {
        await db.into(db.mealPlanEntries).insert(MealPlanEntriesCompanion.insert(
              id: Ids.next('mpe'),
              planId: planId,
              entryDate: Value(to),
              mealType: Value(e.mealType),
              itemId: Value(e.itemId),
              itemCode: Value(e.itemCode),
              itemName: Value(e.itemName),
              unitName: Value(e.unitName),
              factor: Value(e.factor),
              qtyPerPerson: Value(e.qtyPerPerson),
              notes: Value(e.notes),
            ));
      }
    });
    return source.length;
  }

  /// استنساخ خطة إلى مدى جديد — تُزاح تواريخ المدخلات بفارق البداية.
  Future<MealPlanResult> duplicate({
    required String sourceId,
    required String newName,
    required String newStart,
    String actor = '',
  }) async {
    final src = await byId(sourceId);
    if (src == null) return const MealPlanResult(ok: false, error: '✖ الخطة المصدر غير موجودة');
    final start = DateTime.tryParse(newStart);
    final oldStart = DateTime.tryParse(src.plan.startDate);
    if (start == null || oldStart == null) {
      return const MealPlanResult(ok: false, error: '✖ تاريخ البداية غير صالح');
    }
    final shift = start.difference(oldStart).inDays;
    final span = DateSpan(
      newStart,
      MealPlanRules.ymd(DateTime.parse(src.plan.endDate).add(Duration(days: shift))),
    );

    final created = await savePlan(
      name: newName,
      planType: src.plan.planType,
      span: span,
      facilityId: src.plan.facilityId,
      facilityName: src.plan.facilityName,
      warehouse: src.plan.warehouse,
      notes: src.plan.notes,
      actor: actor,
    );
    if (!created.ok) return created;

    await db.transaction(() async {
      for (final e in src.entries) {
        final shifted = DateTime.parse(e.entryDate).add(Duration(days: shift));
        await db.into(db.mealPlanEntries).insert(MealPlanEntriesCompanion.insert(
              id: Ids.next('mpe'),
              planId: created.planId,
              entryDate: Value(MealPlanRules.ymd(shifted)),
              mealType: Value(e.mealType),
              itemId: Value(e.itemId),
              itemCode: Value(e.itemCode),
              itemName: Value(e.itemName),
              unitName: Value(e.unitName),
              factor: Value(e.factor),
              qtyPerPerson: Value(e.qtyPerPerson),
              notes: Value(e.notes),
            ));
      }
    });
    return created;
  }

  /// تنشيط خطة. يُرفض إن غطّت خطةٌ نشطة أخرى المدى نفسه على المرفق نفسه.
  ///
  /// خطتان نشطتان على مطبخ واحد في يوم واحد تعنيان احتياجين متناقضين لليوم
  /// نفسه — ولا يعرف أحد أيهما يُطبخ.
  Future<MealPlanResult> activate(String id, {String actor = ''}) async {
    final full = await byId(id);
    if (full == null) return const MealPlanResult(ok: false, error: '✖ الخطة غير موجودة');
    if (full.entries.isEmpty) {
      return const MealPlanResult(ok: false, error: '✖ لا تُنشَّط خطة بلا وجبات');
    }
    final others = await plans(status: MealPlanStatus.active);
    for (final p in others) {
      if (p.id == id) continue;
      if (p.facilityId != full.plan.facilityId) continue;
      if (DateSpan(p.startDate, p.endDate).overlaps(full.span)) {
        return MealPlanResult(
          ok: false,
          error: '✖ الخطة «${p.name}» نشطة على المدى نفسه — أرشِفها أولًا',
        );
      }
    }
    await _setStatus(id, MealPlanStatus.active, actor: actor, verb: 'تنشيط');
    return MealPlanResult(ok: true, planId: id);
  }

  Future<void> archive(String id, {String actor = ''}) =>
      _setStatus(id, MealPlanStatus.archived, actor: actor, verb: 'أرشفة');

  Future<MealPlanResult> delete(String id, {String actor = ''}) async {
    final full = await byId(id);
    if (full == null) return const MealPlanResult(ok: false, error: '✖ الخطة غير موجودة');
    if (full.plan.status == MealPlanStatus.active) {
      return const MealPlanResult(ok: false, error: '✖ لا تُحذف خطة نشطة — أرشِفها أولًا');
    }
    await db.transaction(() async {
      await (db.delete(db.mealPlanEntries)..where((t) => t.planId.equals(id))).go();
      await (db.delete(db.mealPlans)..where((t) => t.id.equals(id))).go();
    });
    await AuditRepo(db).log(
      action: 'mealplan.delete',
      entityType: 'خطة وجبات',
      summary: 'حذف خطة «${full.plan.name}»',
      details: {'planId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return MealPlanResult(ok: true, planId: id);
  }

  Future<void> _setStatus(
    String id,
    String status, {
    required String actor,
    required String verb,
  }) async {
    await (db.update(db.mealPlans)..where((t) => t.id.equals(id))).write(
      MealPlansCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
    );
    await AuditRepo(db).log(
      action: 'mealplan.$status',
      entityType: 'خطة وجبات',
      summary: '$verb خطة الوجبات',
      details: {'planId': id, 'status': status},
      actorEmail: actor,
    );
  }

  // ───────────────────────── الاحتياج

  /// قوة كل يوم في المدى: مجموع سجلات التفريدة لذلك اليوم.
  ///
  /// تُقرأ من `strengths` مباشرة لأن الخطة تحتاج القوة يومًا بيوم، لا إجمالًا
  /// ولا متوسطًا.
  Future<Map<String, int>> personsByDay(DateSpan span) async {
    final rows = await (db.select(db.strengths)
          ..where((t) =>
              t.strengthDate.isBiggerOrEqualValue(span.start) &
              t.strengthDate.isSmallerOrEqualValue(span.end)))
        .get();
    final out = <String, int>{};
    for (final r in rows) {
      // سطور «المعسكر» تُجمع مع تفصيل وحداته لو أُخذ الاثنان، فيتضاعف العدد.
      if (r.mode == 'camp') continue;
      out.update(r.strengthDate, (v) => v + r.total.round(),
          ifAbsent: () => r.total.round());
    }
    if (out.isEmpty) {
      for (final r in rows) {
        out.update(r.strengthDate, (v) => v + r.total.round(),
            ifAbsent: () => r.total.round());
      }
    }
    return out;
  }

  /// احتياج الخطة كاملةً من القوة المسجّلة فعلًا.
  Future<List<MealRequirement>> requirements(String planId, {DateSpan? within}) async {
    final full = await byId(planId);
    if (full == null) return const [];
    final persons = await personsByDay(within ?? full.span);
    return MealPlanCalc.requirements(
      entries: full.domainEntries,
      personsByDay: persons,
      within: within,
    );
  }
}
