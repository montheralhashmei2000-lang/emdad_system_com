import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/app_database.dart';
import 'catalog_repo.dart';
import '../../domain/strength.dart';

/// العمليات اليومية: تسجيل القوة (التفريدة)، سجل التشغيل والطهي، ونسب الاستحقاق.
///
/// القاعدة المحورية المنقولة من النسخة الحالية: **القوة تُقرأ ليوم التاريخ المحدد
/// فقط**، ولا تُجمع سجلات أيام أخرى، ولا يُجمع المعسكر مع وحداته.
/// سطر واحد في تفريدة اليوم (وحدة فرعية أو إجمالي المعسكر).
class StrengthEntry {
  const StrengthEntry({
    required this.unitId,
    required this.unitName,
    required this.campName,
    required this.soldierCount,
    required this.officerCount,
    required this.pct,
    this.mode = 'detail',
  });

  final String unitId;
  final String unitName;
  final String campName;

  /// «القوة الفعلية» في الويب.
  final double soldierCount;

  /// «الزيادة» المحسوبة من النسبة.
  final double officerCount;
  final double pct;

  /// camp = إجمالي المعسكر، detail = تفصيل الوحدات.
  final String mode;
}

class DailyRepo {
  DailyRepo(this.db);

  final AppDatabase db;

  // ---------------------------------------------------------------- القوة

  Future<List<Strength>> strengths({String? date, String? campId}) async {
    final q = db.select(db.strengths);
    if (date != null && date.isNotEmpty) {
      q.where((t) => t.strengthDate.equals(date));
    }
    if (campId != null && campId.isNotEmpty) {
      q.where((t) => t.campId.equals(campId));
    }
    return q.get();
  }

  /// يبني حاسبة القوة من كامل السجلات وشجرة الوحدات.
  Future<StrengthCalculator> calculator() async {
    final rows = await db.select(db.strengths).get();
    final units = await db.select(db.beneficiaryUnits).get();
    return calculatorFrom(rows, units);
  }

  static StrengthCalculator calculatorFrom(
    List<Strength> rows,
    List<BeneficiaryUnit> units,
  ) =>
      StrengthCalculator(
        records: rows
            .map((s) => StrengthRecord(
                  unitId: s.unitId,
                  campId: s.campId,
                  date: s.strengthDate,
                  total: s.total,
                  mode: s.mode,
                ))
            .toList(),
        units: units
            .map((u) => UnitNode(
                  id: u.id,
                  parentId: u.parentId,
                  isCamp: u.isCamp,
                  facilityIds: facilityIdsOf(u),
                  name: u.name,
                ))
            .toList(),
      );

  /// يحفظ سجل قوة ليوم محدد. السجل الواحد يُعرَّف بـ (الوحدة + التاريخ)،
  /// فإعادة الإدخال لنفس اليوم تستبدل القيمة ولا تضيف سجلًا ثانيًا.
  Future<void> saveStrength({
    required String unitId,
    required String unitName,
    required String campId,
    required String campName,
    required String date,
    required double soldierCount,
    double officerCount = 0,
    double pct = 0,
    String mode = 'detail',
    String createdBy = '',
  }) async {
    final total = soldierCount + officerCount;
    final existing = await (db.select(db.strengths)
          ..where((t) => t.unitId.equals(unitId) & t.strengthDate.equals(date))
          ..limit(1))
        .get();
    final id = existing.isNotEmpty
        ? existing.first.id
        : Ids.next('st');
    await db.into(db.strengths).insertOnConflictUpdate(StrengthsCompanion.insert(
          id: id,
          unitId: unitId,
          unitName: Value(unitName),
          campId: Value(campId),
          campName: Value(campName),
          strengthDate: date,
          soldierCount: Value(soldierCount),
          officerCount: Value(officerCount),
          total: Value(total),
          pct: Value(pct),
          mode: Value(mode),
          createdBy: Value(createdBy),
        ));
  }

  /// حفظ تفريدة معسكر ليوم كامل (`tfSave()`): تُحذف سجلات اليوم كلها للمعسكر
  /// ثم تُكتب السجلات الجديدة، فلا تبقى وحدة محذوفة من التفريدة السابقة.
  Future<void> saveCampStrength({
    required String campId,
    required String date,
    required List<StrengthEntry> rows,
    String createdBy = '',
  }) async {
    await db.transaction(() async {
      await deleteCampStrength(campId: campId, date: date);
      for (final r in rows) {
        await db.into(db.strengths).insert(StrengthsCompanion.insert(
              id: Ids.next('st'),
              unitId: r.unitId,
              unitName: Value(r.unitName),
              campId: Value(campId),
              campName: Value(r.campName),
              strengthDate: date,
              soldierCount: Value(r.soldierCount),
              officerCount: Value(r.officerCount),
              total: Value(r.soldierCount + r.officerCount),
              pct: Value(r.pct),
              mode: Value(r.mode),
              createdBy: Value(createdBy),
            ));
      }
    });
  }

  Future<void> deleteCampStrength({required String campId, required String date}) =>
      (db.delete(db.strengths)..where((t) => t.campId.equals(campId) & t.strengthDate.equals(date))).go();

  Future<void> deleteStrength(String id) =>
      (db.delete(db.strengths)..where((t) => t.id.equals(id))).go();

  // ------------------------------------------------- سجل التشغيل والطهي

  Future<List<KitchenLog>> kitchenLogs({String? date, String? facilityId}) async {
    final q = db.select(db.kitchenLogs);
    if (date != null && date.isNotEmpty) q.where((t) => t.date.equals(date));
    if (facilityId != null && facilityId.isNotEmpty) {
      q.where((t) => t.facilityId.equals(facilityId));
    }
    return q.get();
  }

  Future<void> saveKitchenLog({
    String? id,
    required String facilityId,
    required String facilityName,
    required String date,
    required String mealType,
    required double strength,
    required String itemId,
    required String itemName,
    required String unitName,
    required double qty,
    required double baseQty,
    double expectedBase = 0,
    String notes = '',
  }) async {
    await db.into(db.kitchenLogs).insertOnConflictUpdate(KitchenLogsCompanion.insert(
          id: id ?? Ids.next('kl'),
          facilityId: facilityId,
          facilityName: Value(facilityName),
          date: date,
          mealType: Value(mealType),
          strength: Value(strength),
          itemId: Value(itemId),
          itemName: Value(itemName),
          unitName: Value(unitName),
          qty: Value(qty),
          baseQty: Value(baseQty),
          expectedBase: Value(expectedBase),
          varianceBase: Value(baseQty - expectedBase),
          notes: Value(notes),
        ));
  }

  Future<void> deleteKitchenLog(String id) =>
      (db.delete(db.kitchenLogs)..where((t) => t.id.equals(id))).go();

  // --------------------------------------------------- نسب الاستحقاق

  Future<List<Entitlement>> entitlements() => db.select(db.entitlements).get();

  Future<void> saveEntitlement({
    required String itemId,
    required String itemName,
    required double qtyPerPerson,
    required String measureUnitName,
    required double measureFactor,
    String notes = '',
  }) =>
      db.into(db.entitlements).insertOnConflictUpdate(EntitlementsCompanion.insert(
            itemId: itemId,
            itemName: Value(itemName),
            qtyPerPerson: Value(qtyPerPerson),
            measureUnitName: Value(measureUnitName),
            measureFactor: Value(measureFactor),
            notes: Value(notes),
            updatedAt: Value(DateTime.now()),
          ));

  Future<void> deleteEntitlement(String itemId) =>
      (db.delete(db.entitlements)..where((t) => t.itemId.equals(itemId))).go();
}
