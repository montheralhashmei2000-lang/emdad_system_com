import '../../../domain/fuel.dart';
import '../../db/app_database.dart';
import '../../repos/fuel_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'unit_qty_rows.dart' show isRealIsoDate;

/// قالب تفريدة المحروقات: استحقاق وحدةٍ أسبوعيًّا وشهريًّا، لنوع وقودٍ واحد.
///
/// نوع الوقود وتاريخ البداية يُختاران عند الاستيراد (لا عمودين في الملف). والحفظ
/// كله عبر `FuelRepo.saveAllocation` / `deleteAllocation` نفسهما اللتين تستعملهما
/// شاشة التفريدة، فتبقى قواعدهما وتدقيقهما وترقيم `تف-`.
///
/// وكما تفعل الشاشة: الخطة شهرية دائمًا، و`quantityPerPeriod` = الشهري، والشهري
/// الفارغ أو الصفر `= round(الأسبوعي × 4)`.
class FuelAllocationsTemplate {
  FuelAllocationsTemplate(this.db) : _repo = FuelRepo(db);

  final AppDatabase db;
  final FuelRepo _repo;

  // ───────────────────────── التصدير

  /// تفريدات [fuelType] بأرقامها كما تقرؤها الشاشة (`Fuel.weeklyOf/monthlyOf`).
  Future<(List<List<Object?>>, List<String>)> exportRows({required String fuelType}) async {
    if (!FuelType.all.contains(fuelType)) throw StateError('اختر نوع الوقود');
    final units = {for (final u in await _repo.units()) u.id: u};
    final rows = <List<Object?>>[];
    for (final r in await _repo.allocations()) {
      final a = r.allocation;
      if (a.fuelType != fuelType) continue;
      final u = units[a.unitId];
      rows.add([u?.code ?? '', u?.name ?? a.unitName, a.issueLocation, Fuel.weeklyOf(r.calc), Fuel.monthlyOf(r.calc)]);
    }
    final warnings = <String>[
      if (rows.isEmpty) 'لا تفريدة ${FuelType.label(fuelType)} — صُدِّر القالب فارغًا',
    ];
    return (rows, warnings);
  }

  // ───────────────────────── الاستيراد

  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
    required String fuelType,
    required String startDate,
    String actor = '',
  }) async {
    if (mode == ImportMode.replace && !allowDelete) {
      throw StateError('الاستبدال يحتاج صلاحية الحذف');
    }
    if (!FuelType.all.contains(fuelType)) throw const FormatException('اختر نوع الوقود');
    if (!isRealIsoDate(startDate)) throw const FormatException('تاريخ البداية غير صالح — الصيغة YYYY-MM-DD');
    final report = TemplateReport(kind: TemplateKind.fuelAllocations, mode: mode, dryRun: dryRun);

    final units = await _repo.units();
    final ofType = [
      for (final r in await _repo.allocations())
        if (r.allocation.fuelType == fuelType) r,
    ];

    // ── 1) التحقق صفًّا صفًّا.
    final valid = <_AllocRow>[];
    final seen = <String, int>{};
    final protectedAllocs = <String>{};
    for (final (n, row) in table.dataRows()) {
      final res = _parse(table, row, n, units);
      if (res.row == null) {
        report.failed.add(RowIssue(n, res.error!));
        // وحدة عُرفت ثم فشل صفّها: تفريداتها تبقى (خطأ كتابة ليس أمر حذف).
        if (res.unit != null) {
          protectedAllocs.addAll([
            for (final r in ofType)
              if (r.allocation.unitId == res.unit!.id) r.allocation.id,
          ]);
        }
        continue;
      }
      final r = res.row!;
      final dup = seen[r.unit.id];
      if (dup != null) {
        report.failed.add(RowIssue(n, 'الوحدة «${r.unit.name}» مكررة في الملف (أول ظهور في الصف $dup)'));
        continue;
      }
      final mine = ofType.where((x) => x.allocation.unitId == r.unit.id).toList();
      if (mine.length > 1) {
        report.failed.add(RowIssue(
            n, 'للوحدة «${r.unit.name}» ${mine.length} تفريدات ${FuelType.label(fuelType)} — لا يُعرف أيّها يُحدَّث'));
        protectedAllocs.addAll(mine.map((x) => x.allocation.id));
        continue;
      }
      final existing = mine.firstOrNull?.allocation;
      // قاعدة `saveAllocation` بعينها: النهاية لا تسبق البداية (الباقية لا تتغير بالتحديث).
      if (existing != null && existing.endDate.isNotEmpty && existing.endDate.compareTo(existing.startDate) < 0) {
        report.failed.add(RowIssue(n, 'تفريدة الوحدة القائمة نهايتها قبل بدايتها — صحّحها من شاشة التفريدة أولًا'));
        protectedAllocs.add(existing.id);
        continue;
      }
      seen[r.unit.id] = n;
      valid.add(r.withExisting(existing));
    }
    if (mode == ImportMode.replace && valid.isEmpty) {
      report.warnings.add('لا صفوف صالحة في الملف — لم يُحذف شيء حمايةً للبيانات');
      return report;
    }

    // ── 2) التطبيق.
    Future<void> apply() async {
      final written = <String>{};
      for (final r in valid) {
        final old = r.existing;
        if (!dryRun) {
          final res = await _repo.saveAllocation(
            id: old?.id,
            unitId: r.unit.id,
            unitName: r.unit.name,
            fuelType: fuelType,
            // الخطة شهرية دائمًا كما تحفظها الشاشة؛ والأسبوعي حصةٌ منها تُقرأ.
            periodType: FuelPeriod.monthly,
            quantityPerPeriod: r.monthly,
            code: old?.refNo ?? '',
            weeklyLiters: r.weekly,
            monthlyLiters: r.monthly,
            issueLocation: r.location,
            // التحديث يُبقي تاريخ البداية والنهاية والحالة والملاحظة: تغيير البداية
            // يمسّ حساب ما استُحقّ منذ بدأت التفريدة، فلا يُفرض من نافذة الاستيراد.
            startDate: old?.startDate ?? startDate,
            endDate: old?.endDate ?? '',
            active: old?.active ?? true,
            disbursable: old?.disbursable ?? true,
            notes: old?.notes ?? '',
            actor: actor,
          );
          if (!res.ok) {
            report.failed.add(RowIssue(r.sheetRow, res.error.replaceFirst('✖ ', '')));
            if (old != null) written.add(old.id);
            continue;
          }
        }
        if (old != null) written.add(old.id);
        old == null ? report.created++ : report.updated++;
      }

      if (mode == ImportMode.replace) {
        for (final row in ofType) {
          final a = row.allocation;
          if (written.contains(a.id) || protectedAllocs.contains(a.id)) continue;
          if (dryRun) {
            // `deleteAllocation` ترفض ما صُرف عليه: التقرير يقيس ذلك نفسه.
            final issued = await (db.select(db.fuelIssues)
                  ..where((t) => t.allocationId.equals(a.id))
                  ..limit(1))
                .get();
            issued.isNotEmpty ? report.kept++ : report.deleted++;
            continue;
          }
          final res = await _repo.deleteAllocation(a.id, actor: actor);
          res.ok ? report.deleted++ : report.kept++;
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

  ({_AllocRow? row, String? error, FuelUnit? unit}) _parse(
    TemplateTable t,
    List<XCell?> row,
    int n,
    List<FuelUnit> units,
  ) {
    ({_AllocRow? row, String? error, FuelUnit? unit}) fail(String why, [FuelUnit? unit]) =>
        (row: null, error: why, unit: unit);

    final code = latinDigits(cellText(t.cell(row, 'كود الوحدة')));
    final name = cellText(t.cell(row, 'الوحدة المستفيدة'));
    if (name.isEmpty) return fail('الوحدة المستفيدة مطلوبة');

    // الكود موجود ⇒ تطابقٌ به وحده ثم يُتحقق الاسم؛ فارغ ⇒ تطابق بالاسم.
    final FuelUnit unit;
    if (code.isNotEmpty) {
      final byCode = units.where((u) => latinDigits(u.code).trim().toLowerCase() == code.toLowerCase()).toList();
      if (byCode.isEmpty) return fail('لا توجد وحدة محروقات بالكود «$code»');
      if (byCode.length > 1) return fail('الكود «$code» مكرر بين وحدات المحروقات فلا تُعرف الوحدة');
      unit = byCode.single;
      if (normalizeHeader(unit.name) != normalizeHeader(name)) {
        return fail('الاسم «$name» لا يطابق وحدة الكود «$code» «${unit.name}»', unit);
      }
    } else {
      final byName = units.where((u) => normalizeHeader(u.name) == normalizeHeader(name)).toList();
      if (byName.isEmpty) return fail('لا توجد وحدة محروقات باسم «$name»');
      if (byName.length > 1) return fail('الاسم «$name» مكرر بين وحدات المحروقات فلا تُعرف الوحدة');
      unit = byName.single;
    }
    if (!unit.active) return fail('وحدة المحروقات «${unit.name}» معطَّلة', unit);

    final location = cellText(t.cell(row, 'موقع الصرف / معسكر الصرف'));
    if (location.isEmpty) return fail('موقع الصرف مطلوب', unit);

    final weeklyCell = t.cell(row, 'الاستحقاق أسبوعي (لتر)');
    if (!hasContent(weeklyCell)) return fail('الاستحقاق الأسبوعي مطلوب', unit);
    final weekly = cellNum(weeklyCell);
    if (weekly == null || weekly.isNaN || weekly.isInfinite) {
      return fail('الاستحقاق الأسبوعي «${cellText(weeklyCell)}» ليس رقمًا', unit);
    }
    if (weekly < 0) return fail('الاستحقاق الأسبوعي يجب أن يكون صفرًا أو أكثر', unit);

    double? typedMonthly;
    final monthlyCell = t.cell(row, 'الاستحقاق شهري (لتر)');
    if (hasContent(monthlyCell)) {
      typedMonthly = cellNum(monthlyCell);
      if (typedMonthly == null || typedMonthly.isNaN || typedMonthly.isInfinite) {
        return fail('الاستحقاق الشهري «${cellText(monthlyCell)}» ليس رقمًا', unit);
      }
      if (typedMonthly < 0) return fail('الاستحقاق الشهري يجب أن يكون صفرًا أو أكثر', unit);
    }
    // مستقلٌّ عن الأسبوعي متى كُتب (> 0)؛ وفارغًا أو صفرًا يتبع الأسبوعي × 4 كالشاشة.
    final monthly = (typedMonthly != null && typedMonthly > 0) ? typedMonthly : Fuel.round(weekly * 4);
    if (monthly <= 0) return fail('الاستحقاق الأسبوعي والشهري صفر', unit);

    return (
      row: _AllocRow(sheetRow: n, unit: unit, location: location, weekly: weekly, monthly: monthly),
      error: null,
      unit: unit,
    );
  }
}

class _AllocRow {
  const _AllocRow({
    required this.sheetRow,
    required this.unit,
    required this.location,
    required this.weekly,
    required this.monthly,
    this.existing,
  });

  final int sheetRow;
  final FuelUnit unit;
  final String location;
  final double weekly;
  final double monthly;

  /// التفريدة القائمة للوحدة والنوع (إن وُجدت) — تُحدَّث ولا تُكرَّر.
  final FuelAllocation? existing;

  _AllocRow withExisting(FuelAllocation? a) =>
      _AllocRow(sheetRow: sheetRow, unit: unit, location: location, weekly: weekly, monthly: monthly, existing: a);
}
