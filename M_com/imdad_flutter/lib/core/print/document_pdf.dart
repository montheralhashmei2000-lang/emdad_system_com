import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../domain/print_layout.dart';
import '../ui/imd_fonts.dart';
import 'print_preview.dart';

/// بناء مستندات PDF عربية (RTL) وفق تخطيط الطباعة القابل للضبط.
/// يُستخدم لسندات الاستلام والصرف والتحويل والمرتجعات وتقارير المركز.
/// قسمٌ معنونٌ في مستندٍ متعدد الجداول.
///
/// السند جدولٌ واحد، والتقرير أقسام: «الوارد» ثم «المنصرف» ثم «التحويل»،
/// لكلٍّ عنوانه وأعمدته وإجماليه. وبناؤها هنا لا في كل تقريرٍ على حدة يجعل
/// أوراق النظام كلها بهيئةٍ واحدة — وبعكس أعمدةٍ صحيحٍ واحد.
class PrintSection {
  const PrintSection({
    required this.title,
    required this.headers,
    required this.rows,
    this.columnFlex = const [],
    this.totalRow,
    this.note = '',
    this.emptyText = '',
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<int> columnFlex;

  /// سطرٌ أخير بخلفيةٍ مميّزة — إجمالي القسم.
  final List<String>? totalRow;

  /// سطرٌ صغير تحت العنوان.
  final String note;

  /// ما يُكتب مكان الجدول إن خلا من سطور.
  final String emptyText;
}

class PrintDoc {
  const PrintDoc({
    required this.title,
    this.headers = const [],
    this.rows = const [],
    this.fieldValues = const {},
    this.leftValues = const {},
    this.footerNote = '',
    this.columnFlex = const [],
    this.sections = const [],
    this.headerLines = const [],
    this.signatureLines = const [],
    this.landscape = false,
  });

  final String title;

  /// عناوين أعمدة الجدول من اليمين إلى اليسار.
  final List<String> headers;
  final List<List<String>> rows;

  /// قيم حقول بيانات السند حسب مفاتيح التخطيط (warehouse, party, notes…).
  final Map<String, String> fieldValues;

  /// قيم الحقول أعلى اليسار (date, entryNo, refNo…).
  final Map<String, String> leftValues;
  final String footerNote;
  final List<int> columnFlex;

  /// أقسام التقرير — إن وُجدت حلّت محل الجدول الواحد.
  final List<PrintSection> sections;

  /// أسطر الجهة أعلى اليمين — تُجاوِز أسطر التخطيط.
  ///
  /// يستعملها قسمٌ له ترويسته الخاصة (كالمحروقات)، فتبقى هيئة الورقة واحدة
  /// ويتبدّل رأسها وحده.
  final List<String> headerLines;

  /// التواقيع: عملُ كلٍّ في سطرٍ واسمه في الذي يليه («العمل\nالاسم»).
  final List<String> signatureLines;

  /// ورقةٌ عرضية — للتقارير كثيرة الأعمدة.
  final bool landscape;
}

class DocumentPdf {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static Uint8List? _logo;

  /// يحمّل خط الطباعة المختار ليظهر النص العربي متصلًا داخل PDF.
  /// الخط المحمَّل حاليًا — يُعاد تحميله عند تغيير الاختيار من الإعدادات.
  static String _loadedFamily = '';

  /// يحمّل خط الطباعة المختار. الحمل مرة واحدة لكل خط، ويُعاد عند تبديله.
  static Future<void> ensureFonts({String family = ImdPrintFonts.defaultFamily}) async {
    final font = ImdPrintFonts.of(family);
    if (_regular != null && _loadedFamily == font.family) return;
    _regular = pw.Font.ttf(await rootBundle.load(font.regular));
    _bold = pw.Font.ttf(await rootBundle.load(font.bold));
    _loadedFamily = font.family;
    try {
      _logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    } catch (_) {
      _logo = null;
    }
  }

  /// سمةُ المستند بخطّ الطباعة المختار.
  ///
  /// **كل ورقةٍ في النظام تمرّ من هنا** — السندات والبرقيات وخطط التفريدة —
  /// فلا تخرج ورقةٌ بخطٍّ غير الذي اختاره المستخدم في الإعدادات.
  ///
  /// ومكتبة pdf تحسب فراغ الكلمات من wordSpacing وحده، وبالقيمة الافتراضية
  /// (١) تلتصق بعض الكلمات العربية («أرز أبيض» ⇒ «أرزأبيض»)؛ والمضاعفة تعيد
  /// الفراغ الطبيعي.
  static Future<pw.ThemeData> pdfTheme(
      {String family = ImdPrintFonts.defaultFamily}) async {
    await ensureFonts(family: family);
    final base = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    return base.copyWith(
      defaultTextStyle: base.defaultTextStyle.copyWith(wordSpacing: 2),
      paragraphStyle: base.paragraphStyle.copyWith(wordSpacing: 2),
      tableCell: base.tableCell.copyWith(wordSpacing: 2),
      tableHeader: base.tableHeader.copyWith(wordSpacing: 2),
    );
  }

  /// شعار النظام المرفق (`assets/logo.png`) بعد [ensureFonts] — تقرأه
  /// الأوراق التي تُبنى خارج قالب السند، كبرقية المحروقات.
  static Uint8List? get logoBytes => _logo;

  static pw.TextAlign _align(PrintAlign a) => switch (a) {
        PrintAlign.right => pw.TextAlign.right,
        PrintAlign.center => pw.TextAlign.center,
        PrintAlign.left => pw.TextAlign.left,
      };

  static Future<Uint8List> build({
    required PrintDoc doc,
    PrintLayout layout = PrintLayout.defaults,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final theme = await pdfTheme(family: layout.fontFamily);
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: doc.landscape ? format.landscape : format,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        header: (context) => context.pageNumber == 1
            ? _header(doc, layout)
            : pw.SizedBox(height: 6),
        footer: (context) => _footer(doc, layout, context),
        build: (context) => [
          if (doc.sections.isEmpty)
            _table(doc, layout)
          else
            for (final sec in doc.sections) ..._section(sec, layout),
          pw.SizedBox(height: 18),
          _signatures(doc, layout),
        ],
      ),
    );
    return pdf.save();
  }

  /// طباعة مباشرة عبر حوار نظام التشغيل (ويندوز) أو الطابعة (أندرويد).
  static Future<void> printDoc({
    required PrintDoc doc,
    PrintLayout layout = PrintLayout.defaults,
  }) async {
    final bytes = await build(doc: doc, layout: layout);
    await showPrintPreview(bytes, name: doc.title);
    // الأرشفة التلقائية للتقارير والمطبوعات — إن مُكِّنت من الإعدادات.
    // قاعدة البيانات تُحلّ من سياق التطبيق، وفشلُ الأرشفة لا يمنع طباعةً تمّت.
    try {
      final ctx = imdNavigatorKey.currentContext;
      if (ctx != null) {
        final db = Provider.of<AppDatabase>(ctx, listen: false);
        await ArchiveAuto(db).onDocumentPrinted(
          op: 'report',
          title: doc.title,
          pdfBytes: bytes,
          fileName: '${doc.title.replaceAll(' ', '-')}.pdf',
        );
      }
    } catch (_) {}
  }

  static Future<void> share({
    required PrintDoc doc,
    PrintLayout layout = PrintLayout.defaults,
    String fileName = 'document.pdf',
  }) async {
    final bytes = await build(doc: doc, layout: layout);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static pw.Widget _header(PrintDoc doc, PrintLayout layout) {
    final right = layout.right.where((l) => l.show).toList();
    final left = layout.left.where((f) => f.show).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // يمين الصفحة: أسطر الجهة — من المستند إن جاء بها، وإلا فمن
            // التخطيط. قسمٌ له ترويسته الخاصة يبدّل رأس الورقة وحده.
            if (doc.headerLines.isNotEmpty)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final l in doc.headerLines)
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(l,
                            style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                  ],
                ),
              )
            else
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: right
                    .map((l) => pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            l.text,
                            textAlign: _align(l.align),
                            style: pw.TextStyle(
                              fontSize: l.size,
                              fontWeight: l.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            if (layout.showLogo && _logo != null)
              pw.Container(
                width: 62,
                height: 62,
                margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: pw.Image(pw.MemoryImage(_logo!)),
              ),
            // يسار الصفحة: حقول السند
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: left
                    .map((f) => _kv(f, doc.leftValues[f.key] ?? ''))
                    .toList(),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 1),
              bottom: pw.BorderSide(width: 1),
            ),
          ),
          child: pw.Text(
            doc.title,
            textAlign: _align(layout.titleAlign),
            style: pw.TextStyle(fontSize: layout.titleSize, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        _infoGrid(doc, layout),
        pw.SizedBox(height: 8),
      ],
    );
  }

  /// حقل عربي: العنوان من اليمين والقيمة من اليسار.
  static pw.Widget _kv(PrintField f, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                '${f.label}:',
                textAlign: _align(f.labelAlign),
                style: pw.TextStyle(
                  fontSize: f.size,
                  fontWeight: f.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Expanded(
              flex: 6,
              child: pw.Text(
                value,
                textAlign: _align(f.valueAlign),
                style: pw.TextStyle(fontSize: f.size),
              ),
            ),
          ],
        ),
      );

  static pw.Widget _infoGrid(PrintDoc doc, PrintLayout layout) {
    final fields = layout.info.where((f) => f.show).toList();
    if (fields.isEmpty) return pw.SizedBox();
    final rows = <pw.Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final a = fields[i];
      final b = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _kv(a, doc.fieldValues[a.key] ?? '')),
          pw.SizedBox(width: 14),
          pw.Expanded(child: b == null ? pw.SizedBox() : _kv(b, doc.fieldValues[b.key] ?? '')),
        ],
      ));
    }
    return pw.Column(children: rows);
  }

  /// `pw.Table` لا تعرف اتجاه النص وترسم الأعمدة يسارًا ليمينًا دائمًا، فتُعكس
  /// الأعمدة (ومعها عروضها) ليبدأ العمود الأول من يمين الصفحة كما في المستند العربي.
  static List<pw.Widget> _section(PrintSection sec, PrintLayout layout) => [
        if (sec.title.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(sec.title,
              style: pw.TextStyle(
                  fontSize: layout.table.size + 1.5,
                  fontWeight: pw.FontWeight.bold)),
        ],
        if (sec.note.isNotEmpty)
          pw.Text(sec.note, style: pw.TextStyle(fontSize: layout.table.size - 1)),
        pw.SizedBox(height: 4),
        if (sec.headers.isEmpty)
          pw.SizedBox()
        else
          _grid(
            headers: sec.headers,
            rows: sec.rows.isEmpty && sec.emptyText.isNotEmpty
                ? [
                    [
                      for (var i = 0; i < sec.headers.length; i++)
                        i == 1 ? sec.emptyText : '',
                    ]
                  ]
                : sec.rows,
            columnFlex: sec.columnFlex,
            layout: layout,
            totalRow: sec.totalRow,
          ),
      ];

  /// جدولٌ عربيّ: **الأعمدة تُعكس** لأن `pw.Table` يرصّ أبناءه من اليسار
  /// مهما كان اتجاه الصفحة — ونسيانُ العكس يقلب الورقة كلها.
  static pw.Widget _grid({
    required List<String> headers,
    required List<List<String>> rows,
    required List<int> columnFlex,
    required PrintLayout layout,
    List<String>? totalRow,
  }) {
    final t = layout.table;
    final n = headers.length;
    final widths = <int, pw.TableColumnWidth>{};
    if (columnFlex.length == n) {
      for (var i = 0; i < n; i++) {
        widths[n - 1 - i] = pw.FlexColumnWidth(columnFlex[i].toDouble());
      }
    }

    pw.Widget cell(String v, int i, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
          child: pw.Text(
            v,
            textAlign: _align(t.alignFor(i, v)),
            style: pw.TextStyle(
                fontSize: t.size,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        );

    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: widths.isEmpty ? null : widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (var i = n - 1; i >= 0; i--)
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: pw.Text(
                  headers[i],
                  textAlign: _align(t.headAlign),
                  style: pw.TextStyle(
                    fontSize: t.size,
                    fontWeight: t.headBold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
        for (final r in rows)
          pw.TableRow(children: [
            for (var i = n - 1; i >= 0; i--)
              cell(i < r.length ? r[i] : '', i),
          ]),
        if (totalRow != null)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (var i = n - 1; i >= 0; i--)
                cell(i < totalRow.length ? totalRow[i] : '', i, bold: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _table(PrintDoc doc, PrintLayout layout) {
    final t = layout.table;
    final n = doc.headers.length;
    final widths = <int, pw.TableColumnWidth>{};
    if (doc.columnFlex.length == n) {
      for (var i = 0; i < n; i++) {
        widths[n - 1 - i] = pw.FlexColumnWidth(doc.columnFlex[i].toDouble());
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: widths.isEmpty ? null : widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (final h in doc.headers.reversed)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: pw.Text(
                  h,
                  textAlign: _align(t.headAlign),
                  style: pw.TextStyle(
                    fontSize: t.size,
                    fontWeight: t.headBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
        ...doc.rows.map((r) => pw.TableRow(
              children: [
                // المحاذاة تتبع رقم العمود الأصلي لا المعكوس.
                for (var i = n - 1; i >= 0; i--)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
                    child: pw.Text(
                      i < r.length ? r[i] : '',
                      textAlign: _align(t.alignFor(i, i < r.length ? r[i] : '')),
                      style: pw.TextStyle(fontSize: t.size),
                    ),
                  ),
              ],
            )),
      ],
    );
  }

  static pw.Widget _signatures(PrintDoc doc, PrintLayout layout) {
    if (doc.signatureLines.isNotEmpty) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in doc.signatureLines)
            pw.Expanded(
              child: pw.Column(children: [
                for (final part in line.split('\n'))
                  pw.Text(part,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: line.split('\n').last == part
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal)),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 110,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(width: 0.8)),
                  ),
                ),
              ]),
            ),
        ],
      );
    }
    final sigs = layout.signatures.where((s) => s.show).toList();
    if (sigs.isEmpty) return pw.SizedBox();
    return pw.Row(
      children: sigs
          .map((s) => pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      s.text,
                      textAlign: _align(s.align),
                      style: pw.TextStyle(
                        fontSize: s.size,
                        fontWeight: s.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                      ),
                    ),
                    pw.SizedBox(height: 26),
                    pw.Container(
                      width: 110,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(width: 0.8)),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  static pw.Widget _footer(PrintDoc doc, PrintLayout layout, pw.Context context) {
    final lines = layout.footer.where((l) => l.show).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (doc.footerNote.isNotEmpty)
          pw.Text(doc.footerNote, style: const pw.TextStyle(fontSize: 9)),
        ...lines.map((l) => pw.Text(
              l.text,
              textAlign: _align(l.align),
              style: pw.TextStyle(
                fontSize: l.size,
                fontWeight: l.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            )),
        pw.Text(
          'صفحة ${context.pageNumber} من ${context.pagesCount}',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }
}
