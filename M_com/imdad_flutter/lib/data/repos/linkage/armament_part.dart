part of '../linkage_repo.dart';

/// التسليح وإضافات Pro — نقلٌ حرفيّ من `LinkageRepo` (امتدادٌ في المكتبة نفسها، فالواجهة العامة لم تتغير).
extension LinkageArmamentRepo on LinkageRepo {
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
          body: 'الرقم العسكري: ${p.militaryNo.isEmpty ? "—" : p.militaryNo} · منذ ${LinkageRepo._d(p.statusFrom)}',
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
          body: 'انتهت في ${LinkageRepo._d(p.statusTo)} · لم يُسجَّل عودة بعد',
          personId: p.id,
          personName: p.fullName,
        ));
      } else if (daysLeft <= leaveWarnDays) {
        alerts.add(LinkAlert(
          type: LinkAlertType.statusEnding,
          severity: LinkAlertSeverity.medium,
          title: 'تنتهي قريبًا «${LinkStatus.label(p.status)}»: ${p.fullName}',
          body: daysLeft == 0 ? 'تنتهي اليوم' : 'متبقي $daysLeft يوم · حتى ${LinkageRepo._d(p.statusTo)}',
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
          body: 'الجهة: ${c.holder.isEmpty ? "—" : c.holder} · الأجل كان ${LinkageRepo._d(c.dueDate)}',
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
          body: 'انتهى في ${LinkageRepo._d(ct.endDate)} · ما زال «قيد التنفيذ»',
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
}
