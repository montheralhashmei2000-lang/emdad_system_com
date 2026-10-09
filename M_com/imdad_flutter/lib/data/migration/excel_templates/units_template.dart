import 'package:drift/drift.dart' show Value, Variable;

import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';

/// قالب الوحدات المستفيدة: ثلاثة أعمدة، والشجرة تُبنى من الكود وحده.
///
/// كود بلا «-» ⇒ جذر (`type=camp`)، وكود «أ-ب» ⇒ فرع للجذر «أ». مستويان فقط،
/// كبنية التطبيق (معسكر ← وحدة).
class UnitsTemplate {
  UnitsTemplate(this.db) : _catalog = CatalogRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;

  /// الاختصاصات الخمسة المقبولة، بصيغتها المعتمدة.
  static const List<String> categories = ['معسكر', 'وحدة', 'وحدات إدارية', 'الشعبة الفنية', 'نقاط'];

  /// الاختصاص عند ترك الخلية فارغة.
  static const String defaultCategory = 'وحدة';

  static final RegExp _dashes = RegExp('[‐‑‒–—−]');

  /// الكود مطبَّعًا: أرقام لاتينية وشرطة واحدة وبلا مسافات.
  static String normCode(String raw) =>
      latinDigits(raw).replaceAll(_dashes, '-').replaceAll(RegExp(r'\s+'), '');

  static String? _canonicalCategory(String raw) {
    final n = normalizeHeader(raw);
    for (final c in categories) {
      if (normalizeHeader(c) == n) return c;
    }
    return null;
  }

  // ───────────────────────── التصدير

  /// ترتيب الأكواد: رقميًّا حين يمكن، وإلا نصًّا.
  static int _compareCodes(String a, String b) {
    final ia = int.tryParse(a), ib = int.tryParse(b);
    if (ia != null && ib != null) return ia.compareTo(ib);
    if (ia != null) return -1;
    if (ib != null) return 1;
    return a.compareTo(b);
  }

  Future<(List<List<Object?>>, List<String>)> exportRows() async {
    final all = await _catalog.unitsUnsorted();
    final warnings = <String>[];
    final byId = {for (final u in all) u.id: u};
    final roots = all.where((u) => u.parentId.isEmpty || !byId.containsKey(u.parentId)).toList()
      ..sort((a, b) => _compareCodes(a.code, b.code));
    final rows = <List<Object?>>[];
    var odd = 0, foreignCategory = 0;

    void add(BeneficiaryUnit u, BeneficiaryUnit? parent) {
      rows.add([u.code, u.name, u.category.isEmpty ? null : u.category]);
      final dashed = u.code.contains('-');
      final prefixOk = parent != null && u.code.startsWith('${parent.code}-');
      if (parent == null ? dashed : !prefixOk) odd++;
      if (u.category.isNotEmpty && _canonicalCategory(u.category) == null) foreignCategory++;
    }

    for (final root in roots) {
      add(root, null);
      final kids = all.where((u) => u.parentId == root.id).toList()
        ..sort((a, b) => _compareCodes(a.code, b.code));
      for (final k in kids) {
        add(k, root);
      }
    }
    if (odd > 0) {
      warnings.add('$odd وحدة كودها لا يطابق ترميز الشجرة (جذر بلا "-" وفرع بكود "جذر-رقم") — '
          'أعد ترميزها في الملف قبل استيراده وإلا تغيّر موقعها في الشجرة');
    }
    if (foreignCategory > 0) {
      warnings.add('$foreignCategory وحدة اختصاصها خارج الخمسة المعتمدة — ستُرفض عند الاستيراد حتى تُصحَّح');
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
    final report = TemplateReport(kind: TemplateKind.units, mode: mode, dryRun: dryRun);

    // ── 1) التحقق صفًّا صفًّا.
    final valid = <_UnitRow>[];
    final seen = <String, int>{};
    final protectedCodes = <String>{};
    for (final (n, row) in table.dataRows()) {
      final r = _parse(table, row, n, report);
      if (r == null) {
        final code = normCode(cellText(table.cell(row, 'الكود')));
        if (code.isNotEmpty) protectedCodes.add(code);
        continue;
      }
      final dup = seen[r.code];
      if (dup != null) {
        report.failed.add(RowIssue(n, 'الكود ${r.code} مكرر في الملف (أول ظهور في الصف $dup)'));
        continue;
      }
      seen[r.code] = n;
      valid.add(r);
    }
    if (mode == ImportMode.replace && valid.isEmpty) {
      report.warnings.add('لا صفوف صالحة في الملف — لم يُحذف شيء حمايةً للبيانات');
      return report;
    }

    Future<void> apply() async {
      final existing = <String, BeneficiaryUnit>{};
      for (final u in await _catalog.unitsUnsorted()) {
        if (u.code.isNotEmpty) existing.putIfAbsent(u.code, () => u);
      }
      final ids = <String, String>{}; // كود ← معرّف (قائم أو جديد)
      final names = <String, String>{};
      var placeholder = 0;

      // الجذور أولًا ثم الفروع: ترتيب الملف لا يهم.
      valid.sort((a, b) => a.isRoot == b.isRoot ? 0 : (a.isRoot ? -1 : 1));
      final okCodes = <String>{};

      for (final r in valid) {
        final old = existing[r.code];
        String parentId = '', parentName = '';
        if (!r.isRoot) {
          final pCode = r.parentCode!;
          if (ids.containsKey(pCode)) {
            parentId = ids[pCode]!;
            parentName = names[pCode]!;
          } else {
            final p = existing[pCode];
            if (p == null) {
              report.failed.add(RowIssue(r.sheetRow, 'الجذر «$pCode» غير موجود في الملف ولا في الوحدات'));
              protectedCodes.add(r.code);
              continue;
            }
            if (!p.isCamp && p.parentId.isNotEmpty) {
              report.failed.add(RowIssue(r.sheetRow, 'الكود «$pCode» فرعٌ لا جذر فلا يحمل فروعًا'));
              protectedCodes.add(r.code);
              continue;
            }
            parentId = p.id;
            parentName = p.name;
          }
        }

        final category = r.category ?? ((old?.category.isNotEmpty ?? false) ? old!.category : defaultCategory);
        if (old != null && r.isRoot && old.parentId.isNotEmpty) {
          report.warnings.add('الوحدة ${r.code} «${old.name}» كانت فرعًا فصارت جذرًا');
        }
        if (old != null && !r.isRoot && old.isCamp) {
          report.warnings.add('الوحدة ${r.code} «${old.name}» كانت معسكرًا فصارت فرعًا');
        }

        String id;
        if (dryRun) {
          id = old?.id ?? 'dry-${placeholder++}';
        } else {
          id = await _catalog.saveUnit(
            id: old?.id,
            code: r.code,
            name: r.name,
            type: r.isRoot ? 'camp' : 'unit',
            parentId: parentId,
            parentName: parentName,
            category: category,
          );
          // اسم الجذر منسوخ في فروعه (`parentName`): تسمية الجذر تُجرى على فروعه
          // القائمة التي لم ترد في الملف.
          if (old != null && r.isRoot && old.name != r.name) {
            await (db.update(db.beneficiaryUnits)..where((t) => t.parentId.equals(old.id)))
                .write(BeneficiaryUnitsCompanion(parentName: Value(r.name)));
          }
        }
        ids[r.code] = id;
        names[r.code] = r.name;
        okCodes.add(r.code);
        old == null ? report.created++ : report.updated++;
      }

      if (mode == ImportMode.replace) await _replace(okCodes, protectedCodes, report, dryRun);
    }

    if (dryRun) {
      await apply();
    } else {
      await db.transaction(apply);
    }
    return report;
  }

  /// الاستبدال: ما ليس في الملف يُحذف ما لم يكن له ارتباط أو فروع باقية.
  Future<void> _replace(Set<String> inFile, Set<String> protectedCodes, TemplateReport report, bool dryRun) async {
    final all = await _catalog.unitsUnsorted();
    final candidates = all.where((u) => !inFile.contains(u.code) && !protectedCodes.contains(u.code)).toList();
    final gone = <String>{};
    // الفروع قبل الجذور، فالجذر يُحذف متى ذهبت فروعه كلُّها.
    candidates.sort((a, b) => (a.parentId.isEmpty ? 1 : 0).compareTo(b.parentId.isEmpty ? 1 : 0));
    for (final u in candidates) {
      final hasLiveChild = all.any((k) => k.parentId == u.id && !gone.contains(k.id));
      if (hasLiveChild || await _hasTies(u.id, u.name)) {
        report.kept++;
        continue;
      }
      if (!dryRun) await _catalog.deleteUnit(u.id);
      gone.add(u.id);
      report.deleted++;
    }
  }

  /// أماكن تشير إلى الوحدة بمعرّفها (أو باسمها في الصرف): سندات وتفريدات
  /// وأصول ودفتر معسكر. وحدةٌ لها أثرٌ هنا لا تُحذف.
  static const List<(String, String)> _refs = [
    ('strengths', 'unit_id'),
    ('strengths', 'camp_id'),
    ('issues', 'unit_id'),
    ('issues', 'beneficiary_unit_id'),
    ('transfers', 'camp_id'),
    ('returns', 'beneficiary_unit_id'),
    ('assets', 'beneficiary_unit_id'),
    ('asset_assignments', 'beneficiary_unit_id'),
    ('fuel_issues', 'beneficiary_unit_id'),
    ('camp_ledgers', 'camp_id'),
    ('camp_stock_limits', 'camp_id'),
  ];

  Future<bool> _hasTies(String id, String name) async {
    final exists = [
      for (final (t, c) in _refs) 'EXISTS(SELECT 1 FROM $t WHERE $c = ?1)',
      "EXISTS(SELECT 1 FROM issues WHERE beneficiary_unit_name = ?2 AND ?2 <> '')",
    ].join(' OR ');
    final rows = await db.customSelect(
      'SELECT 1 AS x WHERE $exists',
      variables: [Variable.withString(id), Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  _UnitRow? _parse(TemplateTable t, List<XCell?> row, int n, TemplateReport report) {
    _UnitRow? fail(String why) {
      report.failed.add(RowIssue(n, why));
      return null;
    }

    final code = normCode(cellText(t.cell(row, 'الكود')));
    final name = cellText(t.cell(row, 'الاسم'));
    final rawCat = cellText(t.cell(row, 'الاختصاص'));

    if (code.isEmpty) return fail('الكود مطلوب');
    if (name.isEmpty) return fail('الاسم مطلوب');

    final parts = code.split('-');
    if (parts.any((p) => p.isEmpty)) return fail('الكود «$code» غير صالح (شرطة في غير موضعها)');
    if (parts.length > 2) return fail('الكود «$code» أعمق من مستويين — الشجرة جذر وفرع فقط');

    String? category;
    if (rawCat.isNotEmpty) {
      category = _canonicalCategory(rawCat);
      if (category == null) {
        return fail('الاختصاص «$rawCat» ليس من الخمسة (${categories.join('، ')})');
      }
    }
    return _UnitRow(
      sheetRow: n,
      code: code,
      name: name,
      category: category,
      parentCode: parts.length == 2 ? parts.first : null,
    );
  }
}

class _UnitRow {
  const _UnitRow({
    required this.sheetRow,
    required this.code,
    required this.name,
    required this.category,
    required this.parentCode,
  });

  final int sheetRow;
  final String code;
  final String name;

  /// `null` ⇒ الخلية فارغة: الافتراضي لجديدٍ، والقائم يبقى على اختصاصه.
  final String? category;
  final String? parentCode;

  bool get isRoot => parentCode == null;
}
