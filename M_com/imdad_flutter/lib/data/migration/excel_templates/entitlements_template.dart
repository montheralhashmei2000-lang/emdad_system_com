import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../../repos/daily_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';

/// قالب الاستحقاق: كمية شهرية للفرد من صنفٍ موجود، بإحدى وحدات الصنف.
///
/// الصنف يُعرف **بكوده** والاسم للتحقق وحده: ملفٌّ كودُه لصنف واسمُه لصنف
/// آخر خطأ في الإدخال يُرفض ولا يُكتب على أحدهما بصمت.
class EntitlementsTemplate {
  EntitlementsTemplate(this.db)
      : _catalog = CatalogRepo(db),
        _daily = DailyRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;
  final DailyRepo _daily;

  // ───────────────────────── التصدير

  Future<(List<List<Object?>>, List<String>)> exportRows() async {
    final items = {for (final i in await _catalog.items()) i.id: i};
    final warnings = <String>[];
    final rows = <List<Object?>>[];
    final ents = await _daily.entitlements();
    ents.sort((a, b) => (items[a.itemId]?.code ?? '').compareTo(items[b.itemId]?.code ?? ''));
    for (final e in ents) {
      final item = items[e.itemId];
      if (item == null) {
        warnings.add('استحقاقٌ لصنفٍ محذوف «${e.itemName}» لم يُصدَّر');
        continue;
      }
      rows.add([item.code, item.name, e.measureUnitName, e.qtyPerPerson]);
    }
    return (rows, warnings);
  }

  // ───────────────────────── الاستيراد

  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
  }) async {
    if (mode == ImportMode.replace && !allowDelete) {
      throw StateError('الاستبدال يحتاج صلاحية الحذف');
    }
    final report = TemplateReport(kind: TemplateKind.entitlements, mode: mode, dryRun: dryRun);

    final byCode = <String, Item>{};
    for (final i in await _catalog.items()) {
      if (i.code.isNotEmpty) byCode.putIfAbsent(i.code, () => i);
    }

    final valid = <_EntRow>[];
    final seen = <String, int>{};
    final protectedIds = <String>{};
    for (final (n, row) in table.dataRows()) {
      final parsed = _parse(table, row, n, byCode);
      if (parsed.error != null) {
        report.failed.add(RowIssue(n, parsed.error!));
        final item = byCode[latinDigits(cellText(table.cell(row, 'كود الصنف')))];
        if (item != null) protectedIds.add(item.id);
        continue;
      }
      final r = parsed.row!;
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
      final existing = {for (final e in await _daily.entitlements()) e.itemId: e};
      for (final r in valid) {
        final old = existing[r.item.id];
        if (!dryRun) {
          await _daily.saveEntitlement(
            itemId: r.item.id,
            itemName: r.item.name,
            qtyPerPerson: r.qty,
            measureUnitName: r.unit.name,
            measureFactor: r.unit.factor,
            notes: old?.notes ?? '', // الملاحظة لا يحملها القالب فلا تُمحى
          );
        }
        old == null ? report.created++ : report.updated++;
      }
      if (mode == ImportMode.replace) {
        final inFile = valid.map((r) => r.item.id).toSet();
        for (final e in existing.values) {
          if (inFile.contains(e.itemId) || protectedIds.contains(e.itemId)) continue;
          if (!dryRun) await _daily.deleteEntitlement(e.itemId);
          report.deleted++; // نسبة الاستحقاق لا يرتبط بها سجلٌّ آخر فلا شيء «يبقى»
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

  ({_EntRow? row, String? error}) _parse(
    TemplateTable t,
    List<XCell?> row,
    int n,
    Map<String, Item> byCode,
  ) {
    final code = latinDigits(cellText(t.cell(row, 'كود الصنف')));
    final name = cellText(t.cell(row, 'اسم الصنف'));
    final unitName = cellText(t.cell(row, 'وحدة الاستحقاق'));
    final qtyCell = t.cell(row, 'الكمية للفرد بالشهر');

    if (code.isEmpty) return (row: null, error: 'كود الصنف مطلوب');
    final item = byCode[code];
    if (item == null) return (row: null, error: 'لا يوجد صنف بالكود «$code» في الأصناف');
    if (name.isEmpty) return (row: null, error: 'اسم الصنف مطلوب');
    if (normalizeHeader(name) != normalizeHeader(item.name)) {
      return (row: null, error: 'الاسم «$name» لا يطابق الصنف ${item.code} «${item.name}»');
    }
    if (unitName.isEmpty) return (row: null, error: 'وحدة الاستحقاق مطلوبة');
    final units = _catalog.unitsOf(item);
    final unit = units.where((u) => normalizeHeader(u.name) == normalizeHeader(unitName)).firstOrNull;
    if (unit == null) {
      return (row: null, error: 'الوحدة «$unitName» ليست من وحدات الصنف (${units.map((u) => u.name).join('، ')})');
    }
    if (!hasContent(qtyCell)) return (row: null, error: 'الكمية للفرد بالشهر مطلوبة');
    final qty = cellNum(qtyCell);
    if (qty == null || qty.isNaN || qty.isInfinite) return (row: null, error: 'الكمية «${cellText(qtyCell)}» ليست رقمًا');
    if (qty < 0) return (row: null, error: 'الكمية يجب أن تكون صفرًا أو أكثر');
    return (row: _EntRow(item: item, unit: unit, qty: qty), error: null);
  }
}

class _EntRow {
  const _EntRow({required this.item, required this.unit, required this.qty});
  final Item item;
  final ItemUnit unit;
  final double qty;
}
