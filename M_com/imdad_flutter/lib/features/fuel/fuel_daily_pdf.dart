import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/print/document_pdf.dart';
import '../../core/print/print_preview.dart';
import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/fuel.dart';
import '../../domain/fuel_daily_report.dart';
import '../../domain/fuel_report.dart';
import 'fuel_official_pdf.dart';

/// طباعة تقرير الحركة اليومية للمحروقات.
///
/// ترتيب الورقة هو ترتيب الشاشة حرفًا بحرف: ترويسةٌ، فملخّصٌ بالإجماليات،
/// فتفصيلُ كل معسكر في ثلاثة جداول لكلٍّ إجماليه — والتواقيع **في ذيل كل
/// صفحة** لا في آخر التقرير، لأن الصفحات تُفصل وتُوزَّع.
class FuelDailyPdf {
  const FuelDailyPdf._();

  static const PdfColor _line = PdfColor.fromInt(0xFF9A8F78);
  static const PdfColor _head = PdfColor.fromInt(0xFFEDE4D2);
  static const PdfColor _total = PdfColor.fromInt(0xFFE3C75B);
  static const PdfColor _title = PdfColor.fromInt(0xFF9B2C1F);

  static const List<String> _ordinals = [
    'أولًا',
    'ثانيًا',
    'ثالثًا',
    'رابعًا',
    'خامسًا',
    'سادسًا',
    'سابعًا',
    'ثامنًا',
    'تاسعًا',
    'عاشرًا',
  ];

  static String _ordinal(int i) =>
      i < _ordinals.length ? _ordinals[i] : '${i + 1}';

  static Future<void> printReport(
    AppDatabase db, {
    required FuelDailyReport report,
    required FuelSettingsRow settings,
  }) async {
    final bytes = await build(
      report: report,
      settings: settings,
      logo: await FuelOfficialPdf.fuelLogo(db),
      theme: await DocumentPdf.pdfTheme(
          family: (await SettingsRepo(db).printLayout()).fontFamily),
    );
    await showPrintPreview(bytes, name: report.title);
  }

  static Future<Uint8List> build({
    required FuelDailyReport report,
    required FuelSettingsRow settings,
    Uint8List? logo,
    pw.ThemeData? theme,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    theme ??= await DocumentPdf.pdfTheme();
    logo ??= DocumentPdf.logoBytes;
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format.landscape,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 16),
        // التواقيع ذيلُ كل صفحة: الصفحات تُفصل وتُوزَّع، فصفحةٌ بلا توقيعٍ
        // ورقةٌ لا تُعتمد.
        footer: (context) => _footer(settings, context),
        build: (context) => [
          FuelOfficialPdf.letterhead(settings, logo),
          pw.SizedBox(height: 8),
          _addressee(settings, report),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              '${report.title} — ${report.range.label} م',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _title),
            ),
          ),
          pw.SizedBox(height: 12),
          ..._summary(report),
          for (final day in report.days) ..._day(report, day),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _addressee(FuelSettingsRow s, FuelDailyReport r) => pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        children: [
          pw.TableRow(children: [
            _cell('إلى : ${s.branchTitle}'),
            _cell('تاريخها: ${r.range.label}'),
          ]),
        ],
      );

  static pw.Widget _footer(FuelSettingsRow s, pw.Context ctx) => pw.Column(
        children: [
          pw.Divider(color: _line, height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sign(s.roleOfficer, s.signOfficer),
              _sign(s.roleSupply, s.signSupply),
              _sign(s.roleChief, s.signChief),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7)),
          ),
        ],
      );

  static pw.Widget _sign(String role, String name) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(role.trim().isEmpty ? '—' : role,
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 2),
          pw.Text(name.trim().isEmpty ? '—' : name,
              style:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  // ───────────────────────── الملخّص

  static List<pw.Widget> _summary(FuelDailyReport r) {
    final adj = r.hasAdjustments;
    final many = r.days.length > 1;
    return [
      _heading('ملخّص الحركة اليومية'),
      pw.SizedBox(height: 4),
      _table(
        headers: [
          if (many) 'اليوم',
          'المعسكر / المحطة',
          'الوقود',
          'الرصيد الافتتاحي / المتبقي من السابق',
          'الوارد',
          'المنصرف',
          'التحويل',
          if (adj) 'تسوية جرد',
          'المتبقي',
        ],
        flex: [
          if (many) 3,
          5,
          2,
          5,
          3,
          3,
          3,
          if (adj) 3,
          3,
        ],
        rows: [
          for (final day in r.days)
            for (final b in day.balances)
              [
                if (many) FuelDateRange.slash(day.date),
                b.warehouse,
                FuelType.label(b.fuelType),
                nf(b.opening),
                nf(b.incoming),
                nf(b.issued),
                _signed(b.transferNet),
                if (adj) _signed(b.adjustment),
                nf(b.closing),
              ],
        ],
        totalRow: [
          if (many) '',
          'الإجمالي',
          '',
          nf(r.totalOf((b) => b.opening)),
          nf(r.totalOf((b) => b.incoming)),
          nf(r.totalOf((b) => b.issued)),
          _signed(r.totalOf((b) => b.transferNet)),
          if (adj) _signed(r.totalOf((b) => b.adjustment)),
          nf(r.totalOf((b) => b.closing)),
        ],
      ),
    ];
  }

  static String _signed(double v) {
    if (v == 0) return '—';
    return v > 0 ? '+${nf(v)}' : '−${nf(-v)}';
  }

  // ───────────────────────── تفصيل الأيام

  static List<pw.Widget> _day(FuelDailyReport r, FuelDailyDay day) {
    final many = r.days.length > 1;
    final camps = day.camps.where((c) => c.hasAny).toList();
    return [
      pw.SizedBox(height: 16),
      if (many)
        pw.Center(
          child: pw.Text('حركة يوم ${FuelDateRange.slash(day.date)} م',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _title)),
        ),
      if (camps.isEmpty) _heading('لا توجد حركة في هذا اليوم'),
      for (var i = 0; i < camps.length; i++) ..._camp(camps[i], i),
    ];
  }

  static List<pw.Widget> _camp(FuelDailyCamp c, int index) => [
        pw.SizedBox(height: 12),
        pw.Text(
          '${_ordinal(index)}: تقرير الحركة اليومية للمحروقات بـ${c.warehouse}',
          style: pw.TextStyle(
              fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _title),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'الرصيد أول اليوم: ${_line1(c, opening: true)} — '
          'والمتبقي آخره: ${_line1(c, opening: false)}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        if (c.incoming.isNotEmpty || c.issued.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _incoming(c),
        ],
        pw.SizedBox(height: 8),
        _issued(c),
        // التحويل يُضاف إن وُجد فقط.
        if (c.hasTransfers) ...[
          pw.SizedBox(height: 8),
          _transfers(c),
        ],
      ];

  static String _line1(FuelDailyCamp c, {required bool opening}) => [
        for (final t in FuelType.all)
          '${FuelType.label(t)} '
              '${nf(opening ? c.openingOf(t) : c.closingOf(t))}',
      ].join(' · ');

  static pw.Widget _incoming(FuelDailyCamp c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _heading('الوارد'),
          pw.SizedBox(height: 3),
          _table(
            headers: const [
              'م',
              'السند',
              'جهة التوريد',
              'الوسيلة',
              'السائق',
              'الصنف',
              'الكمية',
              'ملاحظة',
            ],
            flex: const [1, 3, 6, 3, 3, 2, 3, 3],
            emptyText: 'لا يوجد وارد',
            rows: [
              for (var i = 0; i < c.incoming.length; i++)
                [
                  '${i + 1}',
                  c.incoming[i].refNo,
                  c.incoming[i].party,
                  c.incoming[i].vehicleType,
                  c.incoming[i].driver,
                  FuelType.label(c.incoming[i].fuelType),
                  nf(c.incoming[i].qty),
                  c.incoming[i].notes,
                ],
            ],
            totalRow: [
              '',
              'إجمالي الوارد',
              '',
              '',
              '',
              '',
              '${nf(c.incomingTotal)} ${Fuel.unit}',
              '',
            ],
          ),
        ],
      );

  static pw.Widget _issued(FuelDailyCamp c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _heading('المنصرف'),
          pw.SizedBox(height: 3),
          _table(
            headers: const [
              'م',
              'السند',
              'الجهة المستفيدة',
              'نوع الوسيلة',
              'جهة الأمر',
              'الغرض',
              'الصنف',
              'الكمية',
              'ملاحظة',
            ],
            flex: const [1, 3, 6, 3, 4, 4, 2, 3, 4],
            emptyText: 'لا يوجد منصرف',
            rows: [
              for (var i = 0; i < c.issued.length; i++)
                [
                  '${i + 1}',
                  c.issued[i].refNo,
                  c.issued[i].party,
                  c.issued[i].vehicleType,
                  c.issued[i].authority,
                  c.issued[i].purpose,
                  FuelType.label(c.issued[i].fuelType),
                  nf(c.issued[i].qty),
                  c.issued[i].notes,
                ],
            ],
            totalRow: [
              '',
              'إجمالي المنصرف',
              '',
              '',
              '',
              '',
              '',
              '${nf(c.issuedTotal)} ${Fuel.unit}',
              '',
            ],
          ),
        ],
      );

  static pw.Widget _transfers(FuelDailyCamp c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _heading('التحويل'),
          pw.SizedBox(height: 3),
          _table(
            headers: const [
              'م',
              'السند',
              'الاتجاه',
              'الطرف الآخر',
              'الوسيلة',
              'السائق',
              'الصنف',
              'الكمية',
            ],
            flex: const [1, 3, 3, 6, 3, 3, 2, 3],
            rows: [
              for (var i = 0; i < c.transfers.length; i++)
                [
                  '${i + 1}',
                  c.transfers[i].refNo,
                  c.transfers[i].outbound ? 'محوَّل منه' : 'محوَّل إليه',
                  c.transfers[i].outbound
                      ? 'إلى ${c.transfers[i].party}'
                      : 'من ${c.transfers[i].party}',
                  c.transfers[i].vehicleType,
                  c.transfers[i].driver,
                  FuelType.label(c.transfers[i].fuelType),
                  nf(c.transfers[i].qty),
                ],
            ],
            totalRow: [
              '',
              'إجمالي التحويل',
              '',
              '',
              '',
              '',
              '',
              '${nf(c.transferTotal)} ${Fuel.unit}',
            ],
          ),
        ],
      );

  // ───────────────────────── لبنات

  static pw.Widget _heading(String text) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _title)),
      );

  static pw.Widget _table({
    required List<String> headers,
    required List<int> flex,
    required List<List<String>> rows,
    List<String>? totalRow,
    String emptyText = '',
  }) =>
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: {
          for (var i = 0; i < flex.length; i++)
            i: pw.FlexColumnWidth(flex[i].toDouble()),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _head),
            children: [for (final h in headers) _cell(h, bold: true)],
          ),
          if (rows.isEmpty && emptyText.isNotEmpty)
            pw.TableRow(children: [
              for (var i = 0; i < headers.length; i++)
                _cell(i == 1 ? emptyText : ''),
            ]),
          for (final r in rows)
            pw.TableRow(children: [for (final v in r) _cell(v)]),
          if (totalRow != null)
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _total),
              children: [for (final v in totalRow) _cell(v, bold: true)],
            ),
        ],
      );

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
}
