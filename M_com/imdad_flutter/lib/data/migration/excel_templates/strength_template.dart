import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../../repos/daily_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'template_writer.dart';

/// قالب تفريدة المعسكر: قوة كل وحدة من وحدات معسكرٍ في يومٍ واحد.
///
/// الملف لا يحمل المعسكر ولا التاريخ — يُختاران عند الاستيراد (والتصدير يأخذهما
/// من الشاشة). والعمود «نسبة الزيادة» هو **عدد** الزيادة لا النسبة المئوية،
/// ليصحّ `الإجمالي = القوة + الزيادة`؛ والنسبة المئوية المحفوظة (`pct`) تُشتق
/// منه: `الزيادة ÷ القوة × 100`.
class StrengthTemplate {
  StrengthTemplate(this.db)
      : _catalog = CatalogRepo(db),
        _daily = DailyRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;
  final DailyRepo _daily;

  /// عنوان صف المجاميع في آخر الجدول.
  static const String totalLabel = 'الإجمالي';

  static bool _isTotalRow(String name) => normalizeHeader(name) == normalizeHeader(totalLabel);

  /// `DateTime.tryParse` متسامحٌ يُدوِّر «2026-13-45» إلى تاريخٍ آخر بدل رفضه، فيُقارَن
  /// الناتج بالمدخل: ما لم يعد كما كُتب فليس تاريخًا حقيقيًّا.
  static bool _validDate(String date) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}' == date;
  }

  static double _pctOf(double base, double inc) =>
      base <= 0 ? 0 : (inc / base * 100 * 10000).round() / 10000;

  // ───────────────────────── التصدير

  /// صفوف تفريدة [campId] ليوم [date]، ثم صف المجاميع بمعادلات `SUM`.
  ///
  /// عمود «الإجمالي» معادلة `=B{n}+C{n}` لكل صف، لا قيمة جامدة: يعدّل المستخدم
  /// القوة في Excel فيتبعها المجموع.
  Future<(List<List<Object?>>, List<String>)> exportRows({required String campId, required String date}) async {
    final rows = await _daily.strengths(date: date, campId: campId);
    final warnings = <String>[];
    // ترتيب الوحدات كما في شجرتها (كودًا) لا كما حُفظت.
    final units = {for (final u in await _catalog.unitsUnsorted()) u.id: u};
    rows.sort((a, b) => (units[a.unitId]?.code ?? a.unitName).compareTo(units[b.unitId]?.code ?? b.unitName));

    final out = <List<Object?>>[];
    for (final (i, s) in rows.indexed) {
      final r = i + 2; // الصف 1 للعناوين
      out.add([s.unitName, s.soldierCount, s.officerCount, TFormula('B$r+C$r')]);
    }
    if (out.isNotEmpty) {
      final last = out.length + 1;
      out.add([
        totalLabel,
        TFormula('SUM(B2:B$last)'),
        TFormula('SUM(C2:C$last)'),
        TFormula('SUM(D2:D$last)'),
      ]);
    } else {
      warnings.add('لا تفريدة محفوظة لهذا المعسكر في $date — صُدِّر القالب فارغًا');
    }
    return (out, warnings);
  }

  // ───────────────────────── الاستيراد

  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
    required String campId,
    required String date,
    String actor = '',
  }) async {
    if (mode == ImportMode.replace && !allowDelete) {
      throw StateError('الاستبدال يحتاج صلاحية الحذف');
    }
    if (!_validDate(date)) {
      throw const FormatException('التاريخ غير صالح — الصيغة YYYY-MM-DD');
    }
    final all = await _catalog.unitsUnsorted();
    final camp = all.where((u) => u.id == campId).firstOrNull;
    if (camp == null || !camp.isCamp) {
      throw const FormatException('اختر معسكرًا من الوحدات المستفيدة');
    }
    final report = TemplateReport(kind: TemplateKind.strength, mode: mode, dryRun: dryRun);

    // وحدات المعسكر بأسمائها. اسمٌ يتكرر بين الأبناء لا يُعرف صاحبه فيُرفض.
    final byName = <String, List<BeneficiaryUnit>>{};
    for (final u in all.where((u) => u.parentId == camp.id)) {
      (byName[normalizeHeader(u.name)] ??= []).add(u);
    }

    // ── 1) التحقق.
    final valid = <_StrengthRow>[];
    final seen = <String, int>{};
    for (final (n, row) in table.dataRows()) {
      final name = cellText(table.cell(row, 'اسم الوحدة'));
      if (_isTotalRow(name)) continue; // صف المجاميع في آخر الجدول
      final parsed = _parse(table, row, name, camp, byName, report, n);
      if (parsed == null) continue;
      final dup = seen[parsed.unit.id];
      if (dup != null) {
        report.failed.add(RowIssue(n, 'الوحدة «${parsed.unit.name}» مكررة في الملف (أول ظهور في الصف $dup)'));
        continue;
      }
      seen[parsed.unit.id] = n;
      valid.add(parsed);
    }

    // صف المعسكر نفسه (وضع «إجمالي المعسكر») لا يُخلط بصفوف الوحدات.
    final campRows = valid.where((r) => r.isCampRow).toList();
    if (campRows.isNotEmpty && campRows.length != valid.length) {
      for (final r in campRows) {
        report.failed.add(RowIssue(r.sheetRow, 'صف المعسكر نفسه لا يُخلط بصفوف وحداته في تفريدة واحدة'));
      }
      valid.removeWhere((r) => r.isCampRow);
    }

    if (mode == ImportMode.replace && valid.isEmpty) {
      report.warnings.add('لا صفوف صالحة في الملف — لم يُحذف شيء حمايةً للبيانات');
      return report;
    }

    Future<void> apply() async {
      final existing = await _daily.strengths(date: date, campId: campId);
      final fileMode = valid.any((r) => r.isCampRow) ? 'camp' : 'detail';
      final byUnit = {for (final s in existing) s.unitId: s};
      final other = existing.where((s) => s.mode != fileMode).toList();

      for (final r in valid) {
        byUnit[r.unit.id] == null ? report.created++ : report.updated++;
      }

      if (mode == ImportMode.replace) {
        // اليوم كله للملف: ما ليس فيه يُحذف. لا شيء «يبقى» — التفريدة بلا ارتباطات.
        final inFile = valid.map((r) => r.unit.id).toSet();
        report.deleted += existing.where((s) => !inFile.contains(s.unitId)).length;
        if (!dryRun) {
          await _daily.saveCampStrength(
            campId: campId,
            date: date,
            createdBy: actor,
            rows: [
              for (final r in valid)
                StrengthEntry(
                  unitId: r.unit.id,
                  unitName: r.unit.name,
                  campName: camp.name,
                  soldierCount: r.base,
                  officerCount: r.inc,
                  pct: _pctOf(r.base, r.inc),
                  mode: fileMode,
                ),
            ],
          );
        }
        return;
      }

      // دمج: وحدات اليوم غير الواردة تبقى. أما سجلات الوضع الآخر (إجمالي
      // المعسكر مقابل تفصيل الوحدات) فتتعارض مع الملف وتُحذف — يُحصى مرتين لو بقيت.
      if (other.isNotEmpty) {
        report.warnings.add('حُذفت ${other.length} سجل(ات) بوضع '
            '${fileMode == 'camp' ? 'تفصيل الوحدات' : 'إجمالي المعسكر'} لأن الملف بالوضع الآخر');
        report.deleted += other.length;
        if (!dryRun) {
          for (final s in other) {
            await _daily.deleteStrength(s.id);
          }
        }
      }
      if (!dryRun) {
        for (final r in valid) {
          await _daily.saveStrength(
            unitId: r.unit.id,
            unitName: r.unit.name,
            campId: campId,
            campName: camp.name,
            date: date,
            soldierCount: r.base,
            officerCount: r.inc,
            pct: _pctOf(r.base, r.inc),
            mode: fileMode,
            createdBy: actor,
          );
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

  _StrengthRow? _parse(
    TemplateTable t,
    List<XCell?> row,
    String name,
    BeneficiaryUnit camp,
    Map<String, List<BeneficiaryUnit>> byName,
    TemplateReport report,
    int n,
  ) {
    _StrengthRow? fail(String why) {
      report.failed.add(RowIssue(n, why));
      return null;
    }

    if (name.isEmpty) return fail('اسم الوحدة مطلوب');
    final norm = normalizeHeader(name);
    final isCampRow = norm == normalizeHeader(camp.name);
    final BeneficiaryUnit unit;
    if (isCampRow) {
      unit = camp;
    } else {
      final found = byName[norm] ?? const <BeneficiaryUnit>[];
      if (found.isEmpty) return fail('الوحدة «$name» ليست من وحدات المعسكر «${camp.name}»');
      if (found.length > 1) return fail('اسم الوحدة «$name» مكرر بين وحدات المعسكر فلا تُعرف');
      unit = found.first;
    }

    final baseCell = t.cell(row, 'القوة الفعلية');
    if (!hasContent(baseCell)) return fail('القوة الفعلية مطلوبة');
    final base = cellNum(baseCell);
    if (base == null) return fail('القوة الفعلية «${cellText(baseCell)}» ليست رقمًا');
    if (base < 0 || (base - base.roundToDouble()).abs() > 1e-9) {
      return fail('القوة الفعلية يجب أن تكون عددًا صحيحًا ≥ 0');
    }

    // نسبة الزيادة: القيمة كما في الملف (لا إعادة حساب). فارغة ⇒ صفر.
    final incCell = t.cell(row, 'نسبة الزيادة');
    double inc = 0;
    if (hasContent(incCell)) {
      final v = cellNum(incCell);
      if (v == null) return fail('نسبة الزيادة «${cellText(incCell)}» ليست رقمًا');
      if (v < 0) return fail('نسبة الزيادة لا يمكن أن تكون سالبة');
      inc = v;
    }

    // الإجمالي: القيمة المحسوبة المخزَّنة في الخلية إن وُجدت، وإلا B+C. يُقارَن
    // ولا يُعتمد — المحفوظ دائمًا B+C، فاختلافهما تحذيرٌ لا رفض.
    final sum = base + inc;
    final totalCell = t.cell(row, 'الإجمالي');
    final cached = totalCell?.number;
    if (cached != null && (cached - sum).abs() > 1e-6) {
      report.warnings.add('صف $n: الإجمالي في الملف ($cached) لا يساوي القوة + الزيادة ($sum) — اعتُمد $sum');
    }
    return _StrengthRow(sheetRow: n, unit: unit, base: base, inc: inc, isCampRow: isCampRow);
  }
}

class _StrengthRow {
  const _StrengthRow({
    required this.sheetRow,
    required this.unit,
    required this.base,
    required this.inc,
    required this.isCampRow,
  });

  final int sheetRow;
  final BeneficiaryUnit unit;
  final double base;
  final double inc;
  final bool isCampRow;
}
