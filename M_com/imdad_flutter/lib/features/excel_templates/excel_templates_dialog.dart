import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/migration/excel_templates/excel_templates.dart';
import '../../data/repos/catalog_repo.dart';
import '../../domain/access_control.dart';

/// صفحة الصلاحيات التي يحكمها كل قالب.
String _pageOf(TemplateKind k) => switch (k) {
      TemplateKind.items => 'items',
      TemplateKind.units => 'units',
      TemplateKind.entitlements => 'ratios',
      TemplateKind.strength => 'feeding',
    };

/// صلاحية الاستيراد: الأصناف لها «import» في الكتالوج، وما سواها «edit» (الدمج
/// يُحدّث الموجود، فأدنى ما يلزم صلاحية التعديل).
String _importAction(TemplateKind k) => k == TemplateKind.items ? PermAction.import : PermAction.edit;

/// زرّ «قوالب Excel» لرأس الشاشة: تصديرُ القالب ببياناته أو استيرادُ ملف.
class ExcelTemplatesButton extends StatelessWidget {
  const ExcelTemplatesButton({super.key, required this.kind, this.campId, this.date, this.onImported});

  final TemplateKind kind;

  /// المعسكر واليوم المعروضان (للتفريدة وحدها).
  final String? campId;
  final String? date;

  /// يُنادى بعد استيرادٍ نجح، لتعيد الشاشة تحميل بياناتها.
  final VoidCallback? onImported;

  @override
  Widget build(BuildContext context) => ImdButton.outline(
        label: 'قوالب Excel',
        icon: 'chart',
        small: true,
        onPressed: () => showExcelTemplates(context, kind: kind, campId: campId, date: date, onImported: onImported),
      );
}

Future<void> showExcelTemplates(
  BuildContext context, {
  required TemplateKind kind,
  String? campId,
  String? date,
  VoidCallback? onImported,
}) {
  final spec = TemplateSpec.of(kind);
  return showImdModal<void>(
    context,
    title: 'قوالب Excel — ${spec.title}',
    icon: 'chart',
    maxWidth: 480,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdNote('كل قالب ملف Excel بورقتين: «البيانات» و«التعليمات». يُكشف القالب من عناوين '
          'الأعمدة، ويظهر لك تقرير بالناجح والفاشل وأسبابه قبل أن يُكتب أي شيء.'),
      const SizedBox(height: 12),
      ImdButton.outline(
        label: 'تصدير القالب ببياناته الحالية',
        icon: 'download',
        onPressed: () async {
          final done = await _export(context, kind, campId, date);
          if (done && ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
      const SizedBox(height: 8),
      ImdButton(
        label: 'استيراد ملف Excel',
        icon: 'upload',
        onPressed: () async {
          Navigator.of(ctx).pop();
          await _import(context, kind, campId, date, onImported);
        },
      ),
    ]),
  );
}

Future<bool> _export(BuildContext context, TemplateKind kind, String? campId, String? date) async {
  final perm = Perm.of(context);
  if (!perm.guard(context, _pageOf(kind), PermAction.export)) return false;
  if (kind == TemplateKind.strength && (campId == null || campId.isEmpty)) {
    showImdToast(context, '✖ اختر معسكرًا أولًا ثم صدّر', error: true);
    return false;
  }
  final db = context.read<AppDatabase>();
  try {
    final out = await ExcelTemplates(db).export(kind, campId: campId, date: date);
    if (!context.mounted) return false;
    final name = '${TemplateSpec.of(kind).title} ${ImdFiles.today()}.xlsx';
    final saved = await ImdFiles.saveBytes(context, name, out.bytes);
    if (!context.mounted || saved == null) return false;
    showImdToast(context, out.warnings.isEmpty ? '✔ صُدِّر القالب' : '⚠ صُدِّر القالب — ${out.warnings.join(' · ')}');
    return true;
  } catch (e) {
    if (context.mounted) showImdToast(context, '✖ تعذّر التصدير: $e', error: true);
    return false;
  }
}

Future<void> _import(
  BuildContext context,
  TemplateKind screenKind,
  String? campId,
  String? date,
  VoidCallback? onImported,
) async {
  final picked = await ImdFiles.pick(extensions: const ['xlsx']);
  if (picked == null || !context.mounted) return;
  final (name, bytes) = picked;

  final TemplateKind? kind;
  try {
    kind = ExcelTemplates.detect(bytes);
  } on FormatException catch (e) {
    showImdToast(context, '✖ ${e.message}', error: true);
    return;
  }
  if (kind == null) {
    showImdToast(
      context,
      '✖ «$name» لا يطابق أيًّا من القوالب الأربعة (الأصناف، الوحدات المستفيدة، الاستحقاق، تفريدة المعسكر) — '
      'صدّر قالبًا من هنا واملأه',
      error: true,
    );
    return;
  }

  // الصلاحية على القالب المكتشَف لا على الشاشة التي فُتح منها الزر.
  final perm = Perm.of(context);
  if (!perm.guard(context, _pageOf(kind), _importAction(kind))) return;

  final db = context.read<AppDatabase>();
  final camps = kind == TemplateKind.strength
      ? [for (final u in await CatalogRepo(db).units()) if (u.isCamp) u]
      : const <BeneficiaryUnit>[];
  if (!context.mounted) return;
  if (kind == TemplateKind.strength && camps.isEmpty) {
    showImdToast(context, '✖ لا معسكرات في الوحدات المستفيدة — استورد قالب الوحدات أولًا', error: true);
    return;
  }

  final report = await showImdModal<TemplateReport>(
    context,
    title: 'استيراد Excel',
    icon: 'upload',
    maxWidth: 620,
    builder: (ctx) => ExcelImportPreview(
      db: db,
      bytes: bytes,
      fileName: name,
      kind: kind!,
      camps: camps,
      initialCampId: camps.any((c) => c.id == campId) ? campId! : (camps.isEmpty ? '' : camps.first.id),
      initialDate: (date != null && date.isNotEmpty) ? date : ImdFiles.today(),
      canDelete: perm.canDelete(_pageOf(kind)),
      actor: perm.email,
    ),
  );
  if (report == null || !context.mounted) return;
  showImdToast(context, '✔ ${TemplateSpec.of(report.kind).title}: ${report.summary}');
  onImported?.call();
}

/// نافذة التقرير: القالب المكتشَف، ثم نمط الاستيراد، ثم تقريرٌ يُحدَّث بتغيّر
/// المدخلات — كله بلا كتابة حتى يضغط المستخدم «تنفيذ».
class ExcelImportPreview extends StatefulWidget {
  const ExcelImportPreview({
    super.key,
    required this.db,
    required this.bytes,
    required this.fileName,
    required this.kind,
    required this.camps,
    required this.initialCampId,
    required this.initialDate,
    required this.canDelete,
    required this.actor,
  });

  final AppDatabase db;
  final Uint8List bytes;
  final String fileName;
  final TemplateKind kind;
  final List<BeneficiaryUnit> camps;
  final String initialCampId;
  final String initialDate;
  final bool canDelete;
  final String actor;

  @override
  State<ExcelImportPreview> createState() => _ExcelImportPreviewState();
}

class _ExcelImportPreviewState extends State<ExcelImportPreview> {
  ImportMode _mode = ImportMode.merge;
  late String _campId = widget.initialCampId;
  late String _date = widget.initialDate;
  TemplateReport? _report;
  String? _error;
  bool _busy = true;
  int _seq = 0;

  late final ExcelTemplates _xt = ExcelTemplates(widget.db);

  @override
  void initState() {
    super.initState();
    _preview();
  }

  Future<TemplateReport> _run({required bool dryRun}) => _xt.run(
        widget.bytes,
        mode: _mode,
        dryRun: dryRun,
        allowDelete: widget.canDelete,
        actor: widget.actor,
        campId: widget.kind == TemplateKind.strength ? _campId : null,
        date: widget.kind == TemplateKind.strength ? _date : null,
      );

  /// تقرير تجريبي؛ الأقدم منه يُهمَل إن سبقه أحدث (تغيّر النمط أثناء الحساب).
  Future<void> _preview() async {
    final mine = ++_seq;
    setState(() => _busy = true);
    TemplateReport? report;
    String? error;
    try {
      report = await _run(dryRun: true);
    } on FormatException catch (e) {
      error = e.message;
    } on StateError catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (!mounted || mine != _seq) return;
    setState(() {
      _report = report;
      _error = error;
      _busy = false;
    });
  }

  Future<void> _execute() async {
    if (_mode == ImportMode.replace) {
      final r = _report!;
      final ok = await imdConfirm(
        context,
        'الاستبدال سيحذف ${nf(r.deleted)} سجلًّا ليس في الملف. لا يمكن التراجع عنه. متابعة؟',
        ok: 'استبدال',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final report = await _run(dryRun: false);
      if (mounted) Navigator.of(context).pop(report);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذّر الاستيراد: $e';
      });
    }
  }

  bool get _canRun {
    final r = _report;
    if (_busy || _error != null || r == null) return false;
    return r.ok > 0 || r.deleted > 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final spec = TemplateSpec.of(widget.kind);
    final r = _report;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        ImdChip('القالب المكتشَف: ${spec.title}', tone: ImdTone.ok, icon: 'check'),
        ImdChip(widget.fileName, tone: ImdTone.code),
      ]),
      const SizedBox(height: 12),
      if (widget.kind == TemplateKind.strength) ...[
        ImdGrid(columns: 2, minItemWidth: 200, gap: 10, children: [
          ImdLabeled(
            'المعسكر',
            ImdSelect<String>(
              title: 'المعسكر',
              items: [for (final u in widget.camps) (u.id, u.name)],
              value: _campId,
              onChanged: (v) {
                setState(() => _campId = v ?? _campId);
                _preview();
              },
            ),
          ),
          ImdLabeled(
            'تاريخ التفريدة',
            ImdDateField(
              value: _date,
              onChanged: (v) {
                setState(() => _date = v);
                _preview();
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ],
      ImdLabeled(
        'نمط الاستيراد',
        ImdSelect<ImportMode>(
          title: 'نمط الاستيراد',
          items: [
            (ImportMode.merge, 'دمج (إضافة/تحديث الموجود)'),
            if (widget.canDelete) (ImportMode.replace, 'استبدال الموجود كلياً'),
          ],
          value: _mode,
          onChanged: (v) {
            setState(() => _mode = v ?? ImportMode.merge);
            _preview();
          },
        ),
      ),
      if (!widget.canDelete)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('الاستبدال يحتاج صلاحية الحذف، وهي غير ممنوحة لك.',
              style: TextStyle(fontSize: 12, color: c.muted)),
        ),
      const SizedBox(height: 12),
      if (_busy && r == null)
        const ImdLd('جارٍ فحص الملف…')
      else if (_error != null)
        ImdNote('✖ $_error')
      else if (r != null)
        _reportView(r, c),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy && r == null ? null : () => Navigator.of(context).pop()),
        const SizedBox(width: 8),
        ImdButton(
          label: _mode == ImportMode.replace ? 'تنفيذ الاستبدال' : 'تنفيذ الاستيراد',
          icon: 'check',
          busy: _busy && r != null,
          onPressed: _canRun ? _execute : null,
        ),
      ]),
    ]);
  }

  Widget _reportView(TemplateReport r, ImdColors c) {
    const maxLines = 40;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        ImdChip('ناجح ${nf(r.ok)}', tone: ImdTone.ok),
        if (r.created > 0) ImdChip('جديد ${nf(r.created)}', tone: ImdTone.info),
        if (r.updated > 0) ImdChip('محدَّث ${nf(r.updated)}', tone: ImdTone.info),
        ImdChip('فاشل ${nf(r.failedCount)}', tone: r.failedCount > 0 ? ImdTone.off : ImdTone.code),
        if (r.mode == ImportMode.replace) ...[
          ImdChip('حُذف ${nf(r.deleted)}', tone: ImdTone.off),
          ImdChip('بقي ${nf(r.kept)} (له ارتباطات)', tone: ImdTone.pend),
        ],
      ]),
      if (r.failed.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('الصفوف الفاشلة', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.danger)),
        _lines([for (final f in r.failed.take(maxLines)) f.toString()], r.failed.length - maxLines, c.danger),
      ],
      if (r.warnings.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('تنبيهات', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.muted)),
        _lines(r.warnings.take(maxLines).toList(), r.warnings.length - maxLines, c.text2),
      ],
    ]);
  }

  Widget _lines(List<String> lines, int more, Color color) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(l, style: TextStyle(fontSize: 12.5, height: 1.6, color: color)),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('…و ${nf(more)} أخرى', style: TextStyle(fontSize: 12, color: color)),
              ),
          ]),
        ),
      );
}
