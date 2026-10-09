import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';

/// قالب الأصناف: عشرة أعمدة، ثلاث وحدات كحدٍّ أقصى، الأولى هي الأساس.
class ItemsTemplate {
  ItemsTemplate(this.db) : _catalog = CatalogRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  // ───────────────────────── التصدير

  /// صفوف ورقة «البيانات» من أصناف القاعدة، وتحذيرات (أكثر من ثلاث وحدات).
  Future<(List<List<Object?>>, List<String>)> exportRows() async {
    final rows = <List<Object?>>[];
    final warnings = <String>[];
    for (final item in await _catalog.items()) {
      final units = _catalog.unitsOf(item);
      final base = units.firstWhere((u) => u.isBase, orElse: () => units.first);
      final others = units.where((u) => u != base).toList()..sort((a, b) => a.factor.compareTo(b.factor));
      if (others.length > 2) {
        warnings.add('الصنف «${item.name}» له ${units.length} وحدات — صُدّرت ثلاث فقط');
      }
      final chosen = [base, ...others.take(2)];
      final defaultIdx = item.reportUnit.isEmpty ? -1 : chosen.indexWhere((u) => u.name == item.reportUnit);
      rows.add([
        item.code,
        item.name,
        item.categoryName,
        for (var i = 0; i < 3; i++) ...[
          i < chosen.length ? chosen[i].name : null,
          i < chosen.length ? chosen[i].factor : null,
        ],
        defaultIdx < 0 ? null : defaultIdx + 1,
      ]);
    }
    return (rows, warnings);
  }

  // ───────────────────────── الاستيراد

  /// يحلّل [table] ويطبّقه. مع [dryRun] لا يُكتب شيء ويُرجع التقرير نفسه.
  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
  }) async {
    if (mode == ImportMode.replace && !allowDelete) {
      throw StateError('الاستبدال يحتاج صلاحية الحذف');
    }
    final report = TemplateReport(kind: TemplateKind.items, mode: mode, dryRun: dryRun);

    // ── 1) التحقق: كل صف على حدة، وفشله لا يوقف الباقي.
    final valid = <_ItemRow>[];
    final firstSeen = <String, int>{};
    final protectedCodes = <String>{};
    for (final (n, row) in table.dataRows()) {
      final parsed = _parse(table, row);
      if (parsed.error != null) {
        report.failed.add(RowIssue(n, parsed.error!));
        final code = latinDigits(cellText(table.cell(row, 'كود الصنف')));
        if (code.isNotEmpty) protectedCodes.add(code);
        continue;
      }
      final r = parsed.row!;
      final dupOf = firstSeen[r.code];
      if (dupOf != null) {
        report.failed.add(RowIssue(n, 'كود ${r.code} مكرر في الملف (أول ظهور في الصف $dupOf)'));
        continue;
      }
      firstSeen[r.code] = n;
      valid.add(r);
    }

    if (mode == ImportMode.replace && valid.isEmpty) {
      report.warnings.add('لا صفوف صالحة في الملف — لم يُحذف شيء حمايةً للبيانات');
      return report;
    }

    // ── 2) التطبيق (أو محاكاته).
    Future<void> apply() async {
      final existing = <String, Item>{};
      for (final i in await _catalog.items()) {
        if (i.code.isNotEmpty) existing.putIfAbsent(i.code, () => i);
      }
      final cats = {for (final c in await _catalog.categories()) c.name: c.id};

      for (final r in valid) {
        final old = existing[r.code];
        var units = r.units;
        var reportUnit = r.reportUnit;

        if (old != null && await _catalog.hasMovements(old.id)) {
          // وحدات صنفٍ له حركات لا تُبدَّل: المعاملات تحكم أرصدةً مسجَّلة.
          final oldUnits = _catalog.unitsOf(old);
          if (!_sameUnits(oldUnits, r.units)) {
            report.warnings.add('الصنف ${r.code}: له حركات فلم تُغيَّر وحداته');
          }
          units = oldUnits;
          if (reportUnit.isNotEmpty && !units.any((u) => u.name == reportUnit)) {
            report.warnings.add('الصنف ${r.code}: وحدة التقارير «$reportUnit» ليست من وحداته القائمة فتُركت');
            reportUnit = '';
          }
        }

        var categoryId = '';
        if (r.category.isNotEmpty) {
          categoryId = cats[r.category] ?? '';
          if (categoryId.isEmpty && !dryRun) {
            categoryId = await _catalog.saveCategory(name: r.category);
            cats[r.category] = categoryId;
          }
        }

        if (!dryRun) {
          await _catalog.saveItem(
            id: old?.id,
            code: r.code,
            name: r.name,
            categoryId: r.category.isEmpty ? (old?.categoryId ?? '') : categoryId,
            categoryName: r.category.isEmpty ? (old?.categoryName ?? '') : r.category,
            baseUnit: units.firstWhere((u) => u.isBase, orElse: () => units.first).name,
            units: units,
            // أعمدة لا يحملها القالب تُحفظ كما هي بدل أن يمحوها التحديث.
            minQty: old?.minQty ?? 0,
            barcode: old?.barcode ?? '',
            isRefillable: old?.isRefillable ?? false,
            reportUnit: reportUnit.isNotEmpty ? reportUnit : (old?.reportUnit ?? ''),
          );
        }
        old == null ? report.created++ : report.updated++;
      }

      if (mode == ImportMode.replace) {
        final inFile = valid.map((r) => r.code).toSet();
        for (final item in await _catalog.items()) {
          if (inFile.contains(item.code) || protectedCodes.contains(item.code)) continue;
          if (await _catalog.hasMovements(item.id)) {
            report.kept++;
            continue;
          }
          if (!dryRun) await _catalog.deleteItem(item.id);
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

  static bool _sameUnits(List<ItemUnit> a, List<ItemUnit> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name || (a[i].factor - b[i].factor).abs() > 1e-9) return false;
    }
    return true;
  }

  /// صفٌّ واحد: الصف المقبول أو سبب الرفض.
  ({_ItemRow? row, String? error}) _parse(TemplateTable t, List<XCell?> row) {
    XCell? cell(String h) => t.cell(row, h);

    final code = latinDigits(cellText(cell('كود الصنف')));
    final name = cellText(cell('اسم الصنف'));
    if (code.isEmpty) return (row: null, error: 'كود الصنف مطلوب');
    if (!_digitsOnly.hasMatch(code)) return (row: null, error: 'كود الصنف «$code» يجب أن يكون أرقامًا فقط');
    if (name.isEmpty) return (row: null, error: 'اسم الصنف مطلوب');

    final unitNames = [for (final k in ['وحدة 1', 'وحدة 2', 'وحدة 3']) cellText(cell(k))];
    final factorCells = [for (final k in ['معامل 1', 'معامل 2', 'معامل 3']) cell(k)];

    if (unitNames[0].isEmpty) return (row: null, error: 'وحدة 1 مطلوبة (الوحدة الصغرى)');

    // معامل 1: فارغ أو 1 بأي تمثيل (1، 1.0، 1.00)، وإلا رفض.
    if (hasContent(factorCells[0])) {
      final f = cellNum(factorCells[0]);
      if (f == null) return (row: null, error: 'معامل 1 ليس رقمًا');
      if ((f - 1).abs() > 1e-9) return (row: null, error: 'معامل 1 يجب أن يساوي 1 (وحدة 1 هي الأساس) وقد كُتب ${cellText(factorCells[0])}');
    }

    final units = <ItemUnit>[ItemUnit(name: unitNames[0], factor: 1, isBase: true)];
    for (var i = 1; i < 3; i++) {
      final nm = unitNames[i];
      final has = hasContent(factorCells[i]);
      if (nm.isEmpty) {
        if (has) return (row: null, error: 'معامل ${i + 1} بلا وحدة ${i + 1}');
        continue;
      }
      if (!has) return (row: null, error: 'معامل ${i + 1} مطلوب مع وحدة ${i + 1}');
      final f = cellNum(factorCells[i]);
      if (f == null) return (row: null, error: 'معامل ${i + 1} ليس رقمًا');
      if (f <= 0) return (row: null, error: 'معامل ${i + 1} يجب أن يكون أكبر من صفر');
      if (units.any((u) => u.name == nm)) return (row: null, error: 'الوحدة «$nm» مكررة في الصنف');
      units.add(ItemUnit(name: nm, factor: f));
    }

    var reportUnit = '';
    final j = cell('رقم الوحدة الافتراضية');
    if (hasContent(j)) {
      final v = cellNum(j);
      if (v == null || v != v.roundToDouble() || v < 1 || v > 3) {
        return (row: null, error: 'رقم الوحدة الافتراضية يجب أن يكون 1 أو 2 أو 3');
      }
      final idx = v.toInt() - 1;
      if (unitNames[idx].isEmpty) return (row: null, error: 'رقم الوحدة الافتراضية ${idx + 1} يشير إلى وحدة غير مكتوبة');
      reportUnit = unitNames[idx];
    }

    return (
      row: _ItemRow(code: code, name: name, category: cellText(cell('التصنيف')), units: units, reportUnit: reportUnit),
      error: null,
    );
  }
}

class _ItemRow {
  const _ItemRow({
    required this.code,
    required this.name,
    required this.category,
    required this.units,
    required this.reportUnit,
  });

  final String code;
  final String name;
  final String category;
  final List<ItemUnit> units;
  final String reportUnit;
}
