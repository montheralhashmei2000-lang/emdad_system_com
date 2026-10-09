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
import '../../data/repos/stocktake_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart' show FuelType;

/// صفحة الصلاحيات التي يحكمها كل قالب.
String _pageOf(TemplateKind k) => switch (k) {
      TemplateKind.items => 'items',
      TemplateKind.units => 'units',
      TemplateKind.entitlements => 'ratios',
      TemplateKind.strength => 'feeding',
      TemplateKind.openingBalances => 'opening',
      TemplateKind.stocktakeCount => 'stocktake',
      TemplateKind.fuelAllocations => 'fuelAllocations',
    };

/// فعل التصدير. «الأرصدة الافتتاحية» و«تفريدة المحروقات» لا فعل `export` في
/// كتالوجهما (ولا يُعدَّل الكتالوج): التصدير بصلاحية العرض.
String _exportAction(TemplateKind k) => switch (k) {
      TemplateKind.openingBalances || TemplateKind.fuelAllocations => PermAction.view,
      _ => PermAction.export,
    };

/// فعل الاستيراد: الأصناف لها «import» في الكتالوج، وما سواها أدنى ما يلزم
/// لكتابة الموجود وهو التعديل (الدمج يُحدّث). والأرصدة الافتتاحية «create» كما
/// تشترط شاشتها، والعد الفعلي إضافة أو تعديل كشاشة الجرد.
bool _canImport(Perm perm, BuildContext context, TemplateKind k) {
  switch (k) {
    case TemplateKind.items:
      return perm.guard(context, 'items', PermAction.import);
    case TemplateKind.openingBalances:
      return perm.guard(context, 'opening', PermAction.create);
    case TemplateKind.stocktakeCount:
      if (perm.has('stocktake', PermAction.edit) || perm.has('stocktake', PermAction.create)) return true;
      return perm.guard(context, 'stocktake', PermAction.create);
    default:
      return perm.guard(context, _pageOf(k), PermAction.edit);
  }
}

/// زرّ «قوالب Excel» لرأس الشاشة: تصديرُ القالب ببياناته أو استيرادُ ملف.
class ExcelTemplatesButton extends StatelessWidget {
  const ExcelTemplatesButton({
    super.key,
    required this.kind,
    this.campId,
    this.date,
    this.warehouse,
    this.sessionId,
    this.fuelType,
    this.onImported,
  });

  final TemplateKind kind;

  /// المعسكر واليوم المعروضان (للتفريدة وحدها).
  final String? campId;
  final String? date;

  /// المستودع المعروض (للأرصدة الافتتاحية).
  final String? warehouse;

  /// أمر الجرد المختار (للعد الفعلي).
  final String? sessionId;

  /// نوع الوقود المعروض (لتفريدة المحروقات).
  final String? fuelType;

  /// يُنادى بعد استيرادٍ نجح، لتعيد الشاشة تحميل بياناتها.
  final VoidCallback? onImported;

  @override
  Widget build(BuildContext context) => ImdButton.outline(
        label: 'قوالب Excel',
        icon: 'chart',
        small: true,
        onPressed: () => showExcelTemplates(
          context,
          kind: kind,
          campId: campId,
          date: date,
          warehouse: warehouse,
          sessionId: sessionId,
          fuelType: fuelType,
          onImported: onImported,
        ),
      );
}

Future<void> showExcelTemplates(
  BuildContext context, {
  required TemplateKind kind,
  String? campId,
  String? date,
  String? warehouse,
  String? sessionId,
  String? fuelType,
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
          final done = await _export(context, kind, campId, date, warehouse, sessionId, fuelType);
          if (done && ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
      const SizedBox(height: 8),
      ImdButton(
        label: 'استيراد ملف Excel',
        icon: 'upload',
        onPressed: () async {
          Navigator.of(ctx).pop();
          await _import(context, kind, campId, date, warehouse, sessionId, fuelType, onImported);
        },
      ),
    ]),
  );
}

Future<bool> _export(
  BuildContext context,
  TemplateKind kind,
  String? campId,
  String? date,
  String? warehouse,
  String? sessionId,
  String? fuelType,
) async {
  final perm = Perm.of(context);
  if (!perm.guard(context, _pageOf(kind), _exportAction(kind))) return false;
  final missing = switch (kind) {
    TemplateKind.strength when campId == null || campId.isEmpty => 'اختر معسكرًا أولًا ثم صدّر',
    TemplateKind.openingBalances when warehouse == null || warehouse.isEmpty => 'اختر المستودع أولًا ثم صدّر',
    TemplateKind.stocktakeCount when sessionId == null || sessionId.isEmpty => 'اختر أمر الجرد أولًا ثم صدّر',
    TemplateKind.fuelAllocations when fuelType == null || fuelType.isEmpty => 'اختر نوع الوقود أولًا ثم صدّر',
    _ => null,
  };
  if (missing != null) {
    showImdToast(context, '✖ $missing', error: true);
    return false;
  }
  final db = context.read<AppDatabase>();
  try {
    final out = await ExcelTemplates(db).export(
      kind,
      campId: campId,
      date: date,
      warehouse: warehouse,
      sessionId: sessionId,
      fuelType: fuelType,
    );
    if (!context.mounted) return false;
    // اسم الملف يحمل ما يخصّه (المستودع/نوع الوقود) فلا يُخلط ملفان لسياقين.
    final tag = switch (kind) {
      TemplateKind.openingBalances => ' ${warehouse ?? ''}',
      TemplateKind.fuelAllocations => ' ${FuelType.label(fuelType ?? '')}',
      _ => '',
    };
    final name = '${TemplateSpec.of(kind).title}$tag ${ImdFiles.today()}.xlsx';
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
  String? warehouse,
  String? sessionId,
  String? fuelType,
  VoidCallback? onImported,
) async {
  final picked = await ImdFiles.pick(extensions: const ['xlsx']);
  if (picked == null || !context.mounted) return;
  final (name, bytes) = picked;

  final List<TemplateKind> candidates;
  try {
    candidates = ExcelTemplates.detectAll(bytes);
  } on FormatException catch (e) {
    showImdToast(context, '✖ ${e.message}', error: true);
    return;
  }
  // الأرصدة الافتتاحية والعد الفعلي عناوينهما واحدة: تحسمهما الشاشة التي فُتح
  // منها الاستيراد. وما سواهما قالبٌ واحد يُعرف من عناوينه.
  final TemplateKind? kind = candidates.contains(screenKind)
      ? screenKind
      : candidates.length == 1
          ? candidates.first
          : null;
  if (kind == null) {
    showImdToast(
      context,
      candidates.isEmpty
          ? '✖ «$name» لا يطابق أيًّا من القوالب — صدّر قالبًا من هنا واملأه'
          : '✖ «$name» يصلح للأرصدة الافتتاحية وللعد الفعلي معًا — افتحه من شاشة أحدهما',
      error: true,
    );
    return;
  }

  // الصلاحية على القالب المكتشَف لا على الشاشة التي فُتح منها الزر.
  final perm = Perm.of(context);
  if (!_canImport(perm, context, kind)) return;

  final db = context.read<AppDatabase>();
  final catalog = CatalogRepo(db);
  var camps = const <BeneficiaryUnit>[];
  var warehouses = const <String>[];
  var orders = const <Stocktake>[];
  switch (kind) {
    case TemplateKind.strength:
      camps = [for (final u in await catalog.units()) if (u.isCamp) u];
      if (camps.isEmpty) {
        if (context.mounted) {
          showImdToast(context, '✖ لا معسكرات في الوحدات المستفيدة — استورد قالب الوحدات أولًا', error: true);
        }
        return;
      }
    case TemplateKind.openingBalances:
      // نطاق المستودعات كما تفعل شاشة الأرصدة الافتتاحية.
      warehouses = [for (final w in await catalog.warehouses(scope: perm.scope)) w.name];
      if (warehouses.isEmpty) {
        if (context.mounted) showImdToast(context, '✖ لا مستودعات ضمن نطاقك', error: true);
        return;
      }
    case TemplateKind.stocktakeCount:
      orders = [
        for (final o in await StocktakeRepo(db).sessions(status: StocktakeRepo.counting))
          if (perm.canWh(o.warehouse)) o,
      ];
      if (orders.isEmpty) {
        if (context.mounted) showImdToast(context, '✖ لا أوامر جرد مفتوحة للعد ضمن نطاقك', error: true);
        return;
      }
    default:
      break;
  }
  if (!context.mounted) return;

  final report = await showImdModal<TemplateReport>(
    context,
    title: 'استيراد Excel',
    icon: 'upload',
    maxWidth: 620,
    builder: (ctx) => ExcelImportPreview(
      db: db,
      bytes: bytes,
      fileName: name,
      kind: kind,
      camps: camps,
      initialCampId: camps.any((c) => c.id == campId) ? campId! : (camps.isEmpty ? '' : camps.first.id),
      initialDate: (date != null && date.isNotEmpty) ? date : ImdFiles.today(),
      canDelete: perm.canDelete(_pageOf(kind)),
      actor: perm.email,
      warehouses: warehouses,
      initialWarehouse: warehouses.contains(warehouse) ? warehouse! : (warehouses.isEmpty ? '' : warehouses.first),
      orders: orders,
      initialOrderId: orders.any((o) => o.id == sessionId) ? sessionId! : (orders.isEmpty ? '' : orders.first.id),
      initialFuelType: FuelType.all.contains(fuelType) ? fuelType! : FuelType.petrol,
      canEditCounted: perm.has('stocktake', PermAction.edit),
    ),
  );
  if (report == null || !context.mounted) return;
  showImdToast(context, '✔ ${TemplateSpec.of(report.kind).title}: ${report.summary}');
  onImported?.call();
}

/// نافذة التقرير: القالب المكتشَف، ثم سياقه (معسكر/مستودع/أمر جرد/نوع وقود)
/// ونمط الاستيراد، ثم تقريرٌ يُحدَّث بتغيّر المدخلات — كله بلا كتابة حتى يضغط
/// المستخدم «تنفيذ».
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
    this.warehouses = const [],
    this.initialWarehouse = '',
    this.orders = const [],
    this.initialOrderId = '',
    this.initialFuelType = FuelType.petrol,
    this.canEditCounted = false,
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

  final List<String> warehouses;
  final String initialWarehouse;
  final List<Stocktake> orders;
  final String initialOrderId;
  final String initialFuelType;
  final bool canEditCounted;

  @override
  State<ExcelImportPreview> createState() => _ExcelImportPreviewState();
}

class _ExcelImportPreviewState extends State<ExcelImportPreview> {
  ImportMode _mode = ImportMode.merge;
  late String _campId = widget.initialCampId;
  late String _date = widget.initialDate;
  late String _warehouse = widget.initialWarehouse;
  late String _orderId = widget.initialOrderId;
  late String _fuelType = widget.initialFuelType;
  TemplateReport? _report;
  String? _error;
  bool _busy = true;
  int _seq = 0;

  late final ExcelTemplates _xt = ExcelTemplates(widget.db);

  /// العد الفعلي دمجٌ فقط — الاستبدال غير موجود في شاشة الجرد.
  bool get _mergeOnly => widget.kind == TemplateKind.stocktakeCount;

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
        expected: widget.kind,
        campId: widget.kind == TemplateKind.strength ? _campId : null,
        date: switch (widget.kind) {
          TemplateKind.strength || TemplateKind.openingBalances || TemplateKind.fuelAllocations => _date,
          _ => null,
        },
        warehouse: widget.kind == TemplateKind.openingBalances ? _warehouse : null,
        sessionId: widget.kind == TemplateKind.stocktakeCount ? _orderId : null,
        fuelType: widget.kind == TemplateKind.fuelAllocations ? _fuelType : null,
        canEditCounted: widget.canEditCounted,
      );

  /// تقرير تجريبي؛ الأقدم منه يُهمَل إن سبقه أحدث (تغيّر المدخل أثناء الحساب).
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

  /// حقول السياق الخاصة بكل قالب.
  List<Widget> _contextFields() {
    switch (widget.kind) {
      case TemplateKind.strength:
        return [
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
            _dateField('تاريخ التفريدة'),
          ]),
        ];
      case TemplateKind.openingBalances:
        return [
          ImdGrid(columns: 2, minItemWidth: 200, gap: 10, children: [
            ImdLabeled(
              'المستودع',
              ImdSelect<String>(
                title: 'المستودع',
                items: [for (final w in widget.warehouses) (w, w)],
                value: _warehouse,
                onChanged: (v) {
                  setState(() => _warehouse = v ?? _warehouse);
                  _preview();
                },
              ),
            ),
            _dateField('تاريخ الرصيد الافتتاحي'),
          ]),
        ];
      case TemplateKind.stocktakeCount:
        return [
          ImdLabeled(
            'أمر الجرد (المفتوح للعد)',
            ImdSelect<String>(
              title: 'أمر الجرد',
              items: [for (final o in widget.orders) (o.id, '${o.orderNo} — ${o.warehouse} — ${o.date}')],
              value: _orderId,
              onChanged: (v) {
                setState(() => _orderId = v ?? _orderId);
                _preview();
              },
            ),
          ),
        ];
      case TemplateKind.fuelAllocations:
        return [
          ImdGrid(columns: 2, minItemWidth: 200, gap: 10, children: [
            ImdLabeled(
              'نوع الوقود',
              ImdSelect<String>(
                title: 'نوع الوقود',
                items: [for (final t in FuelType.all) (t, FuelType.label(t))],
                value: _fuelType,
                onChanged: (v) {
                  setState(() => _fuelType = v ?? _fuelType);
                  _preview();
                },
              ),
            ),
            _dateField('تاريخ بداية التفريدة (للجديدة فقط)'),
          ]),
        ];
      case TemplateKind.items:
      case TemplateKind.units:
      case TemplateKind.entitlements:
        return const [];
    }
  }

  Widget _dateField(String label) => ImdLabeled(
        label,
        ImdDateField(
          value: _date,
          onChanged: (v) {
            setState(() => _date = v);
            _preview();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final spec = TemplateSpec.of(widget.kind);
    final r = _report;
    final fields = _contextFields();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        ImdChip('القالب المكتشَف: ${spec.title}', tone: ImdTone.ok, icon: 'check'),
        ImdChip(widget.fileName, tone: ImdTone.code),
      ]),
      const SizedBox(height: 12),
      if (fields.isNotEmpty) ...[...fields, const SizedBox(height: 10)],
      if (_mergeOnly)
        Text('العد الفعلي دمجٌ فقط: يُستبدل عدّ الأسطر الواردة ويُترك غيرها.',
            style: TextStyle(fontSize: 12, color: c.muted))
      else ...[
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
      ],
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
        if (r.unchanged > 0) ImdChip('بلا تغيير ${nf(r.unchanged)}', tone: ImdTone.code),
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
