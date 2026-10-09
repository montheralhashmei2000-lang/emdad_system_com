import 'dart:typed_data';

import '../../db/app_database.dart';
import '../../repos/audit_repo.dart';
import 'entitlements_template.dart';
import 'items_template.dart';
import 'strength_template.dart';
import 'units_template.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'template_writer.dart';

export 'template_kind.dart';
export 'template_report.dart';
export 'template_table.dart' show TemplateTable;

/// نتيجة التصدير: الملف وما يستحق التنبيه.
class TemplateExport {
  const TemplateExport(this.bytes, this.warnings);
  final List<int> bytes;
  final List<String> warnings;
}

/// واجهة قوالب Excel الأربعة: كشف القالب، تصديره، واستيراده على مرحلتين
/// (تقرير تجريبي بلا كتابة، ثم كتابة بعد التأكيد).
///
/// الاستحقاق له مساران اليوم: هذا، و`ExcelImporter` (ورقة «نسب الاستحقاق»).
/// TODO(excel-templates): توحيد المسارين في مسارٍ واحد بعد استقرار هذا القالب.
class ExcelTemplates {
  ExcelTemplates(this.db);

  final AppDatabase db;

  /// القالب المطابق لعناوين [bytes]، أو `null` إن لم يطابق أيًّا من الأربعة.
  /// يرمي [FormatException] إن لم يكن الملف xlsx صالحًا.
  static TemplateKind? detect(Uint8List bytes) => TemplateTable.fromBytes(bytes).detect();

  /// ملف القالب مملوءًا بالبيانات الحالية (ويصلح قالبًا فارغًا إن لم توجد بيانات).
  ///
  /// التفريدة وحدها تحتاج [campId] و[date] (المعسكر واليوم المعروضان).
  Future<TemplateExport> export(TemplateKind kind, {String? campId, String? date}) async {
    final spec = TemplateSpec.of(kind);
    switch (kind) {
      case TemplateKind.items:
        final (rows, warnings) = await ItemsTemplate(db).exportRows();
        return TemplateExport(TemplateWriter.build(spec, rows), warnings);
      case TemplateKind.units:
        final (rows, warnings) = await UnitsTemplate(db).exportRows();
        return TemplateExport(TemplateWriter.build(spec, rows), warnings);
      case TemplateKind.entitlements:
        final (rows, warnings) = await EntitlementsTemplate(db).exportRows();
        return TemplateExport(TemplateWriter.build(spec, rows), warnings);
      case TemplateKind.strength:
        if (campId == null || date == null) throw StateError('تفريدة المعسكر تحتاج معسكرًا وتاريخًا');
        final (rows, warnings) = await StrengthTemplate(db).exportRows(campId: campId, date: date);
        return TemplateExport(TemplateWriter.build(spec, rows), warnings);
    }
  }

  /// يحلّل الملف ويطبّقه. [dryRun] ⇒ تقرير بلا كتابة.
  Future<TemplateReport> run(
    Uint8List bytes, {
    required ImportMode mode,
    required bool dryRun,
    required bool allowDelete,
    String actor = '',
    String? campId,
    String? date,
  }) async {
    final table = TemplateTable.fromBytes(bytes);
    final kind = table.detect();
    if (kind == null) {
      throw const FormatException('الملف لا يطابق أيًّا من القوالب الأربعة (الأصناف، الوحدات المستفيدة، الاستحقاق، تفريدة المعسكر)');
    }
    final report = switch (kind) {
      TemplateKind.items => await ItemsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.units => await UnitsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.entitlements =>
        await EntitlementsTemplate(db).run(table, mode: mode, dryRun: dryRun, allowDelete: allowDelete),
      TemplateKind.strength => await _strength(table, mode, dryRun, allowDelete, actor, campId, date),
    };
    if (!dryRun) await _audit(report, actor, {if (campId != null) 'campId': campId, if (date != null) 'date': date});
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
