import 'dart:typed_data';

import '../../db/app_database.dart';
import '../../repos/audit_repo.dart';
import 'entitlements_template.dart';
import 'fuel_allocations_template.dart';
import 'items_template.dart';
import 'opening_template.dart';
import 'stocktake_count_template.dart';
import 'strength_template.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'template_writer.dart';
import 'units_template.dart';

export 'template_kind.dart';
export 'template_report.dart';
export 'template_table.dart' show TemplateTable;

/// نتيجة التصدير: الملف وما يستحق التنبيه.
class TemplateExport {
  const TemplateExport(this.bytes, this.warnings);
  final List<int> bytes;
  final List<String> warnings;
}

/// واجهة قوالب Excel: كشف القالب، تصديره، واستيراده على مرحلتين
/// (تقرير تجريبي بلا كتابة، ثم كتابة بعد التأكيد).
///
/// الاستحقاق له مساران اليوم: هذا، و`ExcelImporter` (ورقة «نسب الاستحقاق»).
/// TODO(excel-templates): توحيد المسارين في مسارٍ واحد بعد استقرار هذا القالب.
class ExcelTemplates {
  ExcelTemplates(this.db);

  final AppDatabase db;

  /// القالب الوحيد المطابق لعناوين [bytes]، أو `null` إن لم يطابق أيًّا منها أو
  /// التبس بأكثر من واحد (الأرصدة الافتتاحية والعد الفعلي عناوينهما واحدة).
  /// يرمي [FormatException] إن لم يكن الملف xlsx صالحًا.
  static TemplateKind? detect(Uint8List bytes) => TemplateTable.fromBytes(bytes).detect();

  /// كل القوالب المطابقة (قائمة فارغة ⇒ لا قالب).
  static List<TemplateKind> detectAll(Uint8List bytes) => TemplateTable.fromBytes(bytes).detectAll();

  /// ملف القالب مملوءًا بالبيانات الحالية (ويصلح قالبًا فارغًا إن لم توجد بيانات).
  ///
  /// كل قالب يحتاج سياقه: التفريدة [campId] و[date]، والأرصدة الافتتاحية
  /// [warehouse]، والعد الفعلي [sessionId]، وتفريدة المحروقات [fuelType].
  Future<TemplateExport> export(
    TemplateKind kind, {
    String? campId,
    String? date,
    String? warehouse,
    String? sessionId,
    String? fuelType,
  }) async {
    final spec = TemplateSpec.of(kind);
    TemplateExport build((List<List<Object?>>, List<String>) r) =>
        TemplateExport(TemplateWriter.build(spec, r.$1), r.$2);
    switch (kind) {
      case TemplateKind.items:
        return build(await ItemsTemplate(db).exportRows());
      case TemplateKind.units:
        return build(await UnitsTemplate(db).exportRows());
      case TemplateKind.entitlements:
        return build(await EntitlementsTemplate(db).exportRows());
      case TemplateKind.strength:
        if (campId == null || date == null) throw StateError('تفريدة المعسكر تحتاج معسكرًا وتاريخًا');
        return build(await StrengthTemplate(db).exportRows(campId: campId, date: date));
      case TemplateKind.openingBalances:
        if (warehouse == null || warehouse.isEmpty) throw StateError('الأرصدة الافتتاحية تحتاج مستودعًا');
        return build(await OpeningTemplate(db).exportRows(warehouse: warehouse));
      case TemplateKind.stocktakeCount:
        if (sessionId == null || sessionId.isEmpty) throw StateError('العد الفعلي يحتاج أمر جرد');
        return build(await StocktakeCountTemplate(db).exportRows(sessionId: sessionId));
      case TemplateKind.fuelAllocations:
        if (fuelType == null || fuelType.isEmpty) throw StateError('تفريدة المحروقات تحتاج نوع وقود');
        return build(await FuelAllocationsTemplate(db).exportRows(fuelType: fuelType));
    }
  }

  /// يحلّل الملف ويطبّقه. [dryRun] ⇒ تقرير بلا كتابة.
  ///
  /// [expected] القالب الذي فُتح الاستيراد من شاشته: يحسم التباس قوالب عناوينها
  /// واحدة، ويُهمَل إن لم يطابق الملف.
  Future<TemplateReport> run(
    Uint8List bytes, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
    String actor = '',
    TemplateKind? expected,
    String? campId,
    String? date,
    String? warehouse,
    String? sessionId,
    String? fuelType,
    bool canEditCounted = false,
  }) async {
    final table = TemplateTable.fromBytes(bytes);
    final candidates = table.detectAll();
    final kind = candidates.contains(expected)
        ? expected!
        : candidates.length == 1
            ? candidates.first
            : null;
    if (kind == null) {
      throw FormatException(candidates.isEmpty
          ? 'الملف لا يطابق أيًّا من القوالب (الأصناف، الوحدات المستفيدة، الاستحقاق، تفريدة المعسكر، '
              'الأرصدة الافتتاحية، العد الفعلي، تفريدة المحروقات)'
          : 'الملف يطابق أكثر من قالب (عناوين الأرصدة الافتتاحية والعد الفعلي واحدة) — افتحه من شاشة أحدهما');
    }
    final report = switch (kind) {
      TemplateKind.items => await ItemsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.units => await UnitsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.entitlements =>
        await EntitlementsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.strength => await _strength(table, mode, dryRun, allowDelete, actor, campId, date),
      TemplateKind.openingBalances => await _opening(table, mode, dryRun, allowDelete, actor, warehouse, date),
      TemplateKind.stocktakeCount => await _stocktake(table, mode, dryRun, sessionId, canEditCounted),
      TemplateKind.fuelAllocations => await _fuel(table, mode, dryRun, allowDelete, actor, fuelType, date),
    };
    if (!dryRun) {
      await _audit(report, actor, {
        if (campId != null && kind == TemplateKind.strength) 'campId': campId,
        if (date != null) 'date': date,
        if (warehouse != null && kind == TemplateKind.openingBalances) 'warehouse': warehouse,
        if (sessionId != null && kind == TemplateKind.stocktakeCount) 'sessionId': sessionId,
        if (fuelType != null && kind == TemplateKind.fuelAllocations) 'fuelType': fuelType,
      });
    }
    return report;
  }

  Future<TemplateReport> _strength(
    TemplateTable table,
    ImportMode mode,
    bool dryRun,
    bool allowDelete,
    String actor,
    String? campId,
    String? date,
  ) {
    if (campId == null || date == null) {
      throw StateError('تفريدة المعسكر تحتاج معسكرًا وتاريخًا');
    }
    return StrengthTemplate(db).run(
      table,
      mode: mode,
      dryRun: dryRun,
      allowDelete: allowDelete,
      campId: campId,
      date: date,
      actor: actor,
    );
  }

  Future<TemplateReport> _fuel(
    TemplateTable table,
    ImportMode mode,
    bool dryRun,
    bool allowDelete,
    String actor,
    String? fuelType,
    String? date,
  ) {
    if (fuelType == null || date == null) {
      throw StateError('تفريدة المحروقات تحتاج نوع وقود وتاريخ بداية');
    }
    return FuelAllocationsTemplate(db).run(
      table,
      mode: mode,
      dryRun: dryRun,
      allowDelete: allowDelete,
      fuelType: fuelType,
      startDate: date,
      actor: actor,
    );
  }

  Future<TemplateReport> _stocktake(
    TemplateTable table,
    ImportMode mode,
    bool dryRun,
    String? sessionId,
    bool canEditCounted,
  ) {
    if (sessionId == null || sessionId.isEmpty) throw StateError('العد الفعلي يحتاج أمر جرد');
    return StocktakeCountTemplate(db).run(
      table,
      mode: mode,
      dryRun: dryRun,
      sessionId: sessionId,
      canEditCounted: canEditCounted,
    );
  }

  Future<TemplateReport> _opening(
    TemplateTable table,
    ImportMode mode,
    bool dryRun,
    bool allowDelete,
    String actor,
    String? warehouse,
    String? date,
  ) {
    if (warehouse == null || date == null) {
      throw StateError('الأرصدة الافتتاحية تحتاج مستودعًا وتاريخًا');
    }
    return OpeningTemplate(db).run(
      table,
      mode: mode,
      dryRun: dryRun,
      allowDelete: allowDelete,
      warehouse: warehouse,
      date: date,
      actor: actor,
    );
  }

  Future<void> _audit(TemplateReport r, String actor, Map<String, dynamic> extra) {
    final title = TemplateSpec.of(r.kind).title;
    return AuditRepo(db).log(
      action: 'excel.template.import',
      entityType: 'استيراد Excel',
      summary: 'استيراد قالب «$title» (${r.mode == ImportMode.replace ? 'استبدال' : 'دمج'}): ${r.summary}',
      risk: r.mode == ImportMode.replace ? AuditRepo.riskHigh : AuditRepo.riskNormal,
      actorEmail: actor,
      details: {
        'kind': r.kind.name,
        'mode': r.mode.name,
        'created': r.created,
        'updated': r.updated,
        'deleted': r.deleted,
        'kept': r.kept,
        'failed': r.failedCount,
        ...extra,
      },
    );
  }
}
