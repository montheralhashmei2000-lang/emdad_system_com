import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/print/document_pdf.dart';
import '../../core/print/print_preview.dart';
import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/fuel.dart';
import '../../domain/fuel_report.dart';

/// طباعة البرقية الرسمية للمحروقات — بنفس نموذج الورقة المرفوعة.
///
/// **لا تمرّ على [PrintDoc]**: ذاك سندٌ بجدولٍ واحد، والبرقية أقسامُ معسكرات
/// لكل قسمٍ ثلاثة جداول وخلاصةٌ تحتها. ولو حُشرت في قالب السند لخرجت ورقةً
/// أخرى غير التي يعرفها من يوقّع عليها.
class FuelOfficialPdf {
  const FuelOfficialPdf._();

  static const PdfColor _line = PdfColor.fromInt(0xFF9A8F78);
  static const PdfColor _head = PdfColor.fromInt(0xFFEDE4D2);
  static const PdfColor _total = PdfColor.fromInt(0xFFE3C75B);
  static const PdfColor _title = PdfColor.fromInt(0xFF9B2C1F);

  static Future<void> printReport(
    AppDatabase db, {
    required FuelOfficialReport report,
    required FuelSettingsRow settings,
  }) async {
    final bytes = await build(
      report: report,
      settings: settings,
      logo: await fuelLogo(db),
      theme: await DocumentPdf.pdfTheme(
          family: (await SettingsRepo(db).printLayout()).fontFamily),
    );
    await showPrintPreview(bytes, name: report.title);
  }

  static Future<Uint8List> build({
    required FuelOfficialReport report,
    required FuelSettingsRow settings,
    Uint8List? logo,
    pw.ThemeData? theme,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    // **الورقة بخطّ النظام**: البرقية ورقةٌ رسمية كالسند، فلا تخرج بخطّ
    // المكتبة الافتراضي الذي لا يصل الحروف العربية.
    theme ??= await DocumentPdf.pdfTheme();
    logo ??= DocumentPdf.logoBytes;
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        build: (context) => [
          _letterhead(settings, logo),
          pw.SizedBox(height: 10),
          _addressee(settings, report),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              '${report.title} ${report.range.label} م',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _title),
            ),
          ),
          for (final s in report.sections)
            ..._camp(s, report.range.label, report.sections.length > 1),
          if (report.showSummary) ..._summary(report),
          pw.SizedBox(height: 26),
          _signatures(settings),
        ],
      ),
    );
    return pdf.save();
  }

  /// خطة توزيع الاستحقاق — نفس ورقة البرقية، جدولٌ لكل مادة.
  static Future<void> printPlan(
    AppDatabase db, {
    required FuelSettingsRow settings,
    required List<FuelPlanRow> petrol,
    required List<FuelPlanRow> diesel,
    List<String> rules = const [],
  }) async {
    final bytes = await buildPlan(
      settings: settings,
      petrol: petrol,
      diesel: diesel,
      rules: rules,
      logo: await fuelLogo(db),
      theme: await DocumentPdf.pdfTheme(
          family: (await SettingsRepo(db).printLayout()).fontFamily),
    );
    await showPrintPreview(bytes, name: 'خطة توزيع الاستحقاق');
  }

  static Future<Uint8List> buildPlan({
    required FuelSettingsRow settings,
    required List<FuelPlanRow> petrol,
    required List<FuelPlanRow> diesel,
    List<String> rules = const [],
    Uint8List? logo,
    pw.ThemeData? theme,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    theme ??= await DocumentPdf.pdfTheme();
    logo ??= DocumentPdf.logoBytes;
    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        build: (context) => [
          _letterhead(settings, logo),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'مقترح خطة توزيع الاستحقاق الشهري للمحروقات',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _title),
            ),
          ),
          pw.SizedBox(height: 12),
          _planTable('تفريدة البترول — جميع الوحدات المستفيدة', petrol),
          pw.SizedBox(height: 14),
          _planTable('تفريدة الديزل — جميع الوحدات المستفيدة', diesel),
          if (rules.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('قواعد الصرف',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _title)),
            for (final r in rules)
              pw.Bullet(text: r, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 24),
          _signatures(settings),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _planTable(String title, List<FuelPlanRow> rows) {
    final weekly = rows.fold<double>(0, (s, r) => s + r.weekly);
    final monthly = rows.fold<double>(0, (s, r) => s + r.monthly);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _title)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(6),
            2: pw.FlexColumnWidth(4),
            3: pw.FlexColumnWidth(3),
            4: pw.FlexColumnWidth(3),
            5: pw.FlexColumnWidth(4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _head),
              children: [
                for (final h in [
                  'م',
                  'الوحدة',
                  'مكان الصرف',
                  'الاستحقاق الأسبوعي',
                  'الاستحقاق الشهري',
                  'ملاحظات',
                ])
                  _cell(h, bold: true),
              ],
            ),
            for (final r in rows)
              pw.TableRow(children: [
                _cell('${r.n}'),
                _cell(r.unit),
                _cell(r.location),
                _cell(nf(r.weekly)),
                _cell(nf(r.monthly)),
                _cell(r.notes),
              ]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _total),
              children: [
                _cell('', bold: true),
                _cell('الإجمالي', bold: true),
                _cell('', bold: true),
                _cell(nf(weekly), bold: true),
                _cell(nf(monthly), bold: true),
                _cell('', bold: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// شعار الورقة: ما رفعه المستخدم في «هوية الجهة» أولًا، فإن لم يرفع شيئًا
  /// فشعار النظام المرفق. والدائرة النصية آخرُ ما يُلجأ إليه.
  static Future<Uint8List?> fuelLogo(AppDatabase db) async {
    final id = await SettingsRepo(db).identity();
    if (id.logoBase64.trim().isNotEmpty) {
      try {
        return base64Decode(id.logoBase64.trim());
      } catch (_) {
        // شعارٌ محفوظ بصيغةٍ تالفة لا يمنع طباعة الورقة.
      }
    }
    await DocumentPdf.ensureFonts();
    return DocumentPdf.logoBytes;
  }

  static pw.Widget _letterhead(FuelSettingsRow s, Uint8List? logo) {
    final seal = s.sealLines.trim().isEmpty
        ? const <String>[]
        : s.sealLines.split(RegExp(r'[\n·،]')).map((e) => e.trim()).toList();
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final l in [
                s.parentOrg,
                s.agencyTitle,
                s.commandTitle,
                s.branchTitle,
              ])
                if (l.trim().isNotEmpty)
                  pw.Text(l,
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        if (logo != null)
          pw.Container(
            width: 76,
            height: 76,
            margin: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Image(pw.MemoryImage(logo)),
          )
        else if (seal.isNotEmpty)
          pw.Container(
            width: 62,
            height: 62,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(width: 2),
            ),
            alignment: pw.Alignment.center,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                for (final l in seal)
                  pw.Text(l,
                      style: pw.TextStyle(
                          fontSize: 7, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        pw.Expanded(child: pw.SizedBox()),
      ],
    );
  }

  static pw.Widget _addressee(FuelSettingsRow s, FuelOfficialReport r) =>
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        children: [
          pw.TableRow(children: [
            _cell('إلى : ${s.branchTitle}', align: pw.TextAlign.right),
            _cell('تاريخها: ${r.range.label}', align: pw.TextAlign.right),
          ]),
        ],
      );

  static List<pw.Widget> _camp(FuelCampSection s, String span, bool showCamp) {
    return [
      pw.SizedBox(height: 14),
      if (showCamp)
        pw.Center(
          child: pw.Text('محطة الوقود في ${s.warehouse}',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: _title)),
        ),
      pw.SizedBox(height: 6),
      if (s.incoming.isEmpty)
        pw.Text('لا يوجد وارد',
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _title))
      else ...[
        pw.Text('الوارد',
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _title)),
        pw.SizedBox(height: 4),
        _incomingTable(s),
      ],
      pw.SizedBox(height: 8),
      _issueTable(
          'الصادر من مادة البترول — المنصرف $span م', s.petrol, s.petrolTotal),
      pw.SizedBox(height: 8),
      _issueTable(
          'الصادر من مادة الديزل — المنصرف $span م', s.diesel, s.dieselTotal),
      if (s.outgoing.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _outgoingTable(s),
      ],
    ];
  }

  /// المحوَّل إلى المعسكرات الشقيقة — يخرج من الخزّان ولا يُصرف لجهة.
  static pw.Widget _outgoingTable(FuelCampSection s) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('المحوَّل إلى المعسكرات',
              style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _title)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(6),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(3),
              4: pw.FlexColumnWidth(3),
              5: pw.FlexColumnWidth(2),
              6: pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _head),
                children: [
                  for (final h in [
                    'م',
                    'إلى معسكر',
                    'الصنف',
                    'الوسيلة',
                    'السائق',
                    'الكمية',
                    'ملاحظة',
                  ])
                    _cell(h, bold: true),
                ],
              ),
              for (final r in s.outgoing)
                pw.TableRow(children: [
                  _cell('${r.n}'),
                  _cell(r.toCamp),
                  _cell(FuelType.label(r.fuelType)),
                  _cell(r.vehicleType),
                  _cell(r.driver),
                  _cell(nf(r.qty)),
                  _cell(r.notes),
                ]),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _total),
                children: [
                  _cell('', bold: true),
                  _cell('الإجمالي', bold: true),
                  _cell('', bold: true),
                  _cell('', bold: true),
                  _cell('', bold: true),
                  _cell('${nf(s.transferredOutTotal)} ${Fuel.unit}',
                      bold: true),
                  _cell('', bold: true),
                ],
              ),
            ],
          ),
        ],
      );

  static pw.Widget _incomingTable(FuelCampSection s) => pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(6),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(3),
          4: pw.FlexColumnWidth(2),
          5: pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _head),
            children: [
              for (final h in [
                'م',
                'جهة التوريد / المصدر',
                'الباب',
                'الوسيلة',
                'الصنف',
                'الكمية',
              ])
                _cell(h, bold: true),
            ],
          ),
          for (final r in s.incoming)
            pw.TableRow(children: [
              _cell('${r.n}'),
              _cell(r.supplier),
              _cell(r.isTransfer ? 'تحويل داخلي' : 'توريد'),
              _cell(r.vehicleType),
              _cell(FuelType.label(r.fuelType)),
              _cell(nf(r.qty)),
            ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _total),
            children: [
              _cell('', bold: true),
              _cell('الإجمالي', bold: true),
              _cell('توريد ${nf(s.suppliedTotal)}', bold: true),
              _cell('تحويل ${nf(s.transferredInTotal)}', bold: true),
              _cell('', bold: true),
              _cell('${nf(s.incomingTotal)} ${Fuel.unit}', bold: true),
            ],
          ),
        ],
      );

  static pw.Widget _issueTable(
      String title, List<FuelOfficialIssueRow> rows, double total) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _title)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(6),
            2: pw.FlexColumnWidth(3),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(3),
            5: pw.FlexColumnWidth(3),
            6: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _head),
              children: [
                for (final h in [
                  'م',
                  'الجهة المستفيدة',
                  'نوع الوسيلة',
                  'الكمية',
                  'جهة الأمر',
                  'الغرض',
                  'ملاحظة',
                ])
                  _cell(h, bold: true),
              ],
            ),
            if (rows.isEmpty)
              pw.TableRow(children: [
                _cell(''),
                _cell('لا توجد حركات'),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
              ]),
            for (final r in rows)
              pw.TableRow(children: [
                _cell('${r.n}'),
                _cell(r.beneficiary),
                _cell(r.vehicleType),
                _cell(nf(r.qty)),
                _cell(r.authority),
                _cell(r.purpose),
                _cell(r.notes),
              ]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _total),
              children: [
                _cell('', bold: true),
                _cell('الإجمالي', bold: true),
                _cell('', bold: true),
                _cell('${nf(total)} ${Fuel.unit}', bold: true),
                _cell('', bold: true),
                _cell('', bold: true),
                _cell('', bold: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static List<pw.Widget> _summary(FuelOfficialReport r) => [
        pw.SizedBox(height: 16),
        pw.Text('خلاصة جميع المعسكرات',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold, color: _title)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.6),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _head),
              children: [
                for (final h in [
                  'المعسكر',
                  'وارد توريدًا',
                  'وارد تحويلًا',
                  'صادر بترول',
                  'صادر ديزل',
                  'محوَّل إلى معسكر',
                  'إجمالي الصادر',
                ])
                  _cell(h, bold: true),
              ],
            ),
            for (final s in r.sections)
              pw.TableRow(children: [
                _cell(s.warehouse),
                _cell(nf(s.suppliedTotal)),
                _cell(nf(s.transferredInTotal)),
                _cell(nf(s.petrolTotal)),
                _cell(nf(s.dieselTotal)),
                _cell(nf(s.transferredOutTotal)),
                _cell(nf(s.outTotal)),
              ]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _total),
              children: [
                _cell('الإجمالي', bold: true),
                _cell(nf(r.grandSupplied), bold: true),
                _cell(nf(r.grandTransferredIn), bold: true),
                _cell(nf(r.grandPetrol), bold: true),
                _cell(nf(r.grandDiesel), bold: true),
                _cell(nf(r.grandTransferredOut), bold: true),
                _cell(nf(r.grandTotal + r.grandTransferredOut), bold: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'المحوَّل بين المعسكرات يظهر واردًا في معسكرٍ وصادرًا في آخر، فلا '
          'يزيد وقود الفرقة ولا ينقصه — والداخل توريدًا '
          '${nf(r.grandSupplied)} ${Fuel.unit}، والخارج صرفًا '
          '${nf(r.grandTotal)} ${Fuel.unit}.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ];

  static pw.Widget _signatures(FuelSettingsRow s) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sign('مسؤول محروقات المعسكر', s.signOfficer),
          _sign('ركن إمداد الفرقة الأولى/', s.signSupply),
          _sign('رئيس شعبة الإمداد والتموين /', s.signChief),
        ],
      );

  static pw.Widget _sign(String role, String name) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(role, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 3),
          pw.Text(name.trim().isEmpty ? '—' : name,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _cell(String text,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
}

/// سطرٌ في خطة توزيع الاستحقاق المطبوعة.
class FuelPlanRow {
  const FuelPlanRow({
    required this.n,
    required this.unit,
    required this.location,
    required this.weekly,
    required this.monthly,
    required this.notes,
  });

  final int n;
  final String unit;
  final String location;
  final double weekly;
  final double monthly;
  final String notes;
}
