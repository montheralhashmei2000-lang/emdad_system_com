import 'package:drift/drift.dart' show Variable;

import '../../db/app_database.dart';
import '../../repos/audit_repo.dart';
import '../../repos/catalog_repo.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'unit_qty_rows.dart';

/// قالب الأرصدة الافتتاحية لمستودع.
///
/// يتبع شاشة «الأرصدة الافتتاحية» حرفيًّا: التثبيت عبر
/// `CatalogRepo.setOpeningBalances` (يحذف سطر الصنف في المستودع ثم يُدرج الجديد)،
/// والكمية بوحدة الصنف **الأساسية** (مجموع كمية × معامل)، وتدقيقٌ `critical`
/// لكل صنف كما تكتب الشاشة.
class OpeningTemplate {
  OpeningTemplate(this.db) : _catalog = CatalogRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;

  // ───────────────────────── التصدير

  /// الأرصدة الافتتاحية المثبَّتة لـ[warehouse]، كلٌّ بوحدة الصنف الأساسية.
  Future<(List<List<Object?>>, List<String>)> exportRows({required String warehouse}) async {
    final items = {for (final i in await _catalog.items()) i.id: i};
    final opens = await (db.select(db.openingBalances)..where((t) => t.warehouse.equals(warehouse))).get();
    final rows = <List<Object?>>[];
    final warnings = <String>[];
    opens.sort((a, b) => a.itemCode.compareTo(b.itemCode));
    for (final o in opens) {
      final item = items[o.itemId];
      if (item == null) {
        warnings.add('رصيد لصنفٍ محذوف «${o.itemName}» لم يُصدَّر');
        continue;
      }
      final units = _catalog.unitsOf(item);
      final base = units.firstWhere((u) => u.isBase, orElse: () => units.first);
      rows.add([item.code, item.name, base.name, o.qty, null, null, null, null]);
    }
    if (rows.isEmpty) warnings.add('لا أرصدة افتتاحية مثبَّتة في «$warehouse» — صُدِّر القالب فارغًا');
    return (rows, warnings);
  }

  // ───────────────────────── الاستيراد

  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
    required String warehouse,
    required String date,
    String actor = '',
  }) async {
    if (mode == ImportMode.replace && !allowDelete) {
      throw StateError('الاستبدال يحتاج صلاحية الحذف');
    }
    if (!isRealIsoDate(date)) throw const FormatException('التاريخ غير صالح — الصيغة YYYY-MM-DD');
    if (!(await _catalog.warehouses()).any((w) => w.name == warehouse)) {
      throw const FormatException('اختر مستودعًا من قائمة المستودعات');
    }
    final report = TemplateReport(kind: TemplateKind.openingBalances, mode: mode, dryRun: dryRun);
    final parser = await UnitQtyParser.create(_catalog);

    // ── 1) التحقق صفًّا صفًّا.
    final valid = <UnitQtyRow>[];
    final seen = <String, int>{};
    final protectedIds = <String>{};
    for (final (n, row) in table.dataRows()) {
      final p = parser.parse(table, row, n, allowedUnits: parser.allUnits);
      if (p.row == null) {
        report.failed.add(RowIssue(n, p.error!));
        if (p.item != null) protectedIds.add(p.item!.id);
        continue;
      }
      final r = p.row!;
      final dup = seen[r.item.id];
      if (dup != null) {
        report.failed.add(RowIssue(n, 'الصنف ${r.item.code} مكرر في الملف (أول ظهور في الصف $dup)'));
        continue;
      }
      seen[r.item.id] = n;
      valid.add(r);
    }
    if (mode == ImportMode.replace && valid.isEmpty) {
      report.warnings.add('لا صفوف صالحة في الملف — لم يُحذف شيء حمايةً للبيانات');
      return report;
    }

    Future<void> apply() async {
      final existing = <String, OpeningBalance>{};
      for (final o in await (db.select(db.openingBalances)..where((t) => t.warehouse.equals(warehouse))).get()) {
        existing[o.itemId] = o;
      }

      for (final r in valid) {
        existing.containsKey(r.item.id) ? report.updated++ : report.created++;
      }

      if (!dryRun && valid.isNotEmpty) {
        // تثبيتٌ لا إضافة: يحذف سطر الصنف في المستودع ثم يُدرج الجديد (كالشاشة).
        await _catalog.setOpeningBalances(
          warehouse,
          actor,
          [for (final r in valid) (item: r.item, qty: r.baseQty)],
          date: date,
        );
        for (final r in valid) {
          await AuditRepo(db).write(
            'OPENING_BALANCE_SET',
            'openingBalance',
            'تثبيت رصيد افتتاحي لصنف',
            actorEmail: actor,
            details: {
              'refNo': r.item.code,
              'qty': r.baseQty,
              'typed': r.parts.map((p) => '${p.$2} ${p.$1.name}').join(' + '),
              'unit': r.item.baseUnit,
              'target': r.item.name,
              'warehouse': warehouse,
              'status': 'OPENING_SET',
              'source': 'excel',
              'risk': 'critical',
            },
          );
        }
      }

      if (mode == ImportMode.replace) {
        final inFile = valid.map((r) => r.item.id).toSet();
        for (final o in existing.values) {
          if (inFile.contains(o.itemId) || protectedIds.contains(o.itemId)) continue;
          // حذف الافتتاحي بعد حركاتٍ على الصنف في المستودع يترك رصيدًا سالبًا.
          if (await _hasMovementsIn(o.itemId, warehouse)) {
            report.kept++;
            continue;
          }
          if (!dryRun) {
            await (db.delete(db.openingBalances)..where((t) => t.id.equals(o.id))).go();
            await AuditRepo(db).write(
              'OPENING_BALANCE_CLEARED',
              'openingBalance',
              'حذف رصيد افتتاحي لصنف (استبدال من Excel)',
              actorEmail: actor,
              details: {
                'refNo': o.itemCode,
                'qty': o.qty,
                'target': o.itemName,
                'warehouse': warehouse,
                'status': 'OPENING_CLEARED',
                'source': 'excel',
                'risk': 'critical',
              },
            );
          }
          report.deleted++;
        }
      }
    }

    if (dryRun) {
      await apply();
    } else {
      await db.transaction(apply);
    }
    return report;
  }

  /// حركةٌ مؤثّرة في رصيد الصنف داخل [warehouse]: وارد أو صرف أو مرتجع أو تسوية
  /// فيه، أو تحويلٌ منه أو إليه. المسودات والملغاة لا تُحسب — لا أثر لها في الرصيد
  /// (نفس الحالات غير الفعّالة التي يستثنيها دفتر الأرصدة).
  Future<bool> _hasMovementsIn(String itemId, String warehouse) async {
    const live = "status NOT IN ('DRAFT','ORDER','CANCELLED','REJECTED')";
    final rows = await db.customSelect(
      '''
      SELECT 1 AS x WHERE
        EXISTS (SELECT 1 FROM receipts WHERE item_id = ?1 AND warehouse = ?2 AND $live) OR
        EXISTS (SELECT 1 FROM issues WHERE item_id = ?1 AND warehouse = ?2 AND $live) OR
        EXISTS (SELECT 1 FROM returns WHERE item_id = ?1 AND warehouse = ?2 AND $live) OR
        EXISTS (SELECT 1 FROM adjustments WHERE item_id = ?1 AND warehouse = ?2 AND $live) OR
        EXISTS (SELECT 1 FROM transfers WHERE item_id = ?1 AND (warehouse = ?2 OR dest_warehouse = ?2) AND $live)
      ''',
      variables: [Variable.withString(itemId), Variable.withString(warehouse)],
    ).get();
    return rows.isNotEmpty;
  }
}
