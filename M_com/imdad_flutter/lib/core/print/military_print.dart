import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../ui/imd_fonts.dart';
import 'print_preview.dart';

import '../ui/imd_format.dart';

/// محرك الطباعة العسكرية الرسمية — نقل `militaryPrint` من نسخة الويب:
/// ترويسة موحّدة (التاريخ ورقم السند ورقم القيد يسارًا، الشعار وسطًا، أسطر الجهة
/// يمينًا)، جدول بيانات بأقسام، جدول أصناف بترويسة خضراء وصفوف متناوبة،
/// خانات توقيع حسب نوع السند، وترقيم صفحات (١٨ صنفًا في الصفحة الأولى ثم ٢٨).
class MilitaryPrint {
  MilitaryPrint({
    required this.orgLines,
    this.logoBase64 = '',
    this.printedBy = 'مسؤول النظام',
    this.customFooter = '',
    this.approvalLabel = 'مصادقة رئيس شعبة الإمداد والتموين',
    this.approvalVisible = true,
    this.printFont = ImdPrintFonts.defaultFamily,
  });

  /// أسطر الجهة الأربعة (`APP_CFG.orgLine1..4`).
  final List<String> orgLines;

  /// الشعار Base64 — عند غيابه يُرسم مربع أخضر بحرف «إ».
  final String logoBase64;
  final String printedBy;

  /// تذييل النماذج المخصص (`CFG.footer`).
  final String customFooter;

  /// نص مربع المصادقة وظهوره — يُضبطان من «مصمم النماذج المطبوعة».
  final String approvalLabel;
  final bool approvalVisible;

  /// خط الطباعة المختار من «مصمم النماذج المطبوعة».
  final String printFont;

  static const green = PdfColor.fromInt(0xFF2E6B35);
  static const darkGreen = PdfColor.fromInt(0xFF0E6B3E);
  static const gold = PdfColor.fromInt(0xFFB78103);
  static const ink = PdfColor.fromInt(0xFF123524);
  static const grey = PdfColor.fromInt(0xFF555555);
  static const lightRow = PdfColor.fromInt(0xFFFBFDFC);
  static const sectionBg = PdfColor.fromInt(0xFFF0F6F2);
  static const labelBg = PdfColor.fromInt(0xFFFAFAFA);
  static const dotted = PdfColor.fromInt(0xFFBBBBBB);

  /// ألوان عناوين السندات كما في الويب.
  static const titleIssue = PdfColor.fromInt(0xFFC0392B);
  static const titleReceive = green;
  static const titleTransfer = PdfColor.fromInt(0xFF2980B9);
  static const titleReturn = PdfColor.fromInt(0xFF8E44AD);

  static pw.Font? _regular;
  static pw.Font? _bold;

  /// الخط المحمَّل حاليًا — يُعاد تحميله عند تغيير الاختيار من الإعدادات.
  static String _loadedFamily = '';

  /// يحمّل خط الطباعة المختار. الحمل مرة واحدة لكل خط، ويُعاد عند تبديله.
  static Future<void> ensureFonts({String family = ImdPrintFonts.defaultFamily}) async {
    final font = ImdPrintFonts.of(family);
    if (_regular != null && _loadedFamily == font.family) return;
    _regular = pw.Font.ttf(await rootBundle.load(font.regular));
    _bold = pw.Font.ttf(await rootBundle.load(font.bold));
    _loadedFamily = font.family;
  }

  static const _firstPageMax = 18;
  static const _otherPageMax = 28;

  /// `buildPages()` — يقسّم الأصناف على صفحات ويبني المستند كاملًا.
  Future<Uint8List> build({
    required Map<String, String> master,
    required List<List<String>> rows,
    required String title,
    required PdfColor titleColor,
    required String type,
    List<String>? headers,
    String? receiptNote,
    String? signatureToken,
  }) async {
    await ensureFonts(family: printFont);
    // مكتبة pdf تحسب فراغ الكلمات من wordSpacing وحده، وبالقيمة الافتراضية (١)
    // تلتصق بعض الكلمات العربية («أرز أبيض» ⇒ «أرزأبيض»). المضاعفة تعيد الفراغ الطبيعي.
    final base = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    final theme = base.copyWith(
      defaultTextStyle: base.defaultTextStyle.copyWith(wordSpacing: 2),
      paragraphStyle: base.paragraphStyle.copyWith(wordSpacing: 2),
      tableCell: base.tableCell.copyWith(wordSpacing: 2),
      tableHeader: base.tableHeader.copyWith(wordSpacing: 2),
    );
    final pdf = pw.Document(theme: theme);

    final chunks = <List<List<String>>>[];
    if (rows.isEmpty) {
      chunks.add(const []);
    } else {
      chunks.add(rows.take(_firstPageMax).toList());
      var left = rows.skip(_firstPageMax).toList();
      while (left.isNotEmpty) {
        chunks.add(left.take(_otherPageMax).toList());
        left = left.skip(_otherPageMax).toList();
      }
    }

    final date = master['start_date']?.isNotEmpty == true
        ? master['start_date']!
        : (master['date'] ?? isoDay(DateTime.now()));
    final ref = master['ref'] ?? '';
    final cols = headers ??
        (master['is_multi_unit'] == 'true'
            ? const ['م', 'اسم الصنف', 'الكمية', 'الوحدة', 'الوحدة المستفيدة', 'ملاحظات']
            : const ['م', 'الكود', 'اسم الصنف', 'الكمية', 'الوحدة', 'ملاحظات']);

    final logo = _logoBytes();
    for (final (i, chunk) in chunks.indexed) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              header(
                date: date,
                ref: ref,
                title: title,
                titleColor: titleColor,
                refLabel: _refLabel(type),
                // الإعداد هو الحاكم؛ وحين يكون مفعّلًا يظهر في السندات التي
                // تحتاج مصادقة فقط (التوريد والعمل اليومي).
                showApproval:
                    approvalVisible && (type == 'receive' || type == 'daily_work'),
                logo: logo,
              ),
              if (i == 0) ..._infoTable(type, master, date),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('جدول الأصناف والمواد:',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green)),
                pw.Text('صفحة ${nf(i + 1)} من ${nf(chunks.length)}',
                    style: const pw.TextStyle(fontSize: 10, color: grey)),
              ]),
              pw.SizedBox(height: 4),
              itemsTable(cols, chunk),
              if (type == 'receipt' && receiptNote != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8, right: 6),
                  child: pw.Text(receiptNote,
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ink)),
                ),
              pw.Spacer(),
              signatures(type, master),
              if (customFooter.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Center(
                    child: pw.Text(customFooter,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkGreen)),
                  ),
                ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(children: [
                  pw.Divider(color: dotted, thickness: 0.5),
                  if (signatureToken != null && signatureToken.isNotEmpty)
                    signatureStamp(signatureToken),
                  pw.Text('طُبع بواسطة: $printedBy — ${_stamp()}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ]),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  Uint8List? _logoBytes() {
    if (logoBase64.isEmpty) return null;
    try {
      return base64Decode(logoBase64);
    } catch (_) {
      return null;
    }
  }

  static String _refLabel(String type) => switch (type) {
        'issue' => 'رقم أمر الصرف',
        'receipt' || 'transfer_receipt' => 'رقم الاستلام',
        'receive' => 'رقم سند التوريد',
        'transfer' => 'رقم إذن التحويل',
        'return_unit' || 'return_supplier' => 'رقم سند المرتجع',
        _ => 'رقم السند',
      };

  static String _stamp() {
    final n = DateTime.now();
    return arDigits('${n.year}/${n.month}/${n.day} ${n.hour}:${n.minute.toString().padLeft(2, '0')}');
  }

  /// `documentHeader()`
  pw.Widget header({
    required String date,
    required String ref,
    required String title,
    required PdfColor titleColor,
    required String refLabel,
    required bool showApproval,
    Uint8List? logo,
  }) {
    final refDisplay = ref.isEmpty ? '................' : ref;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // يمين: أسطر الجهة.
        pw.Expanded(
          flex: 36,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            for (final (i, line) in orgLines.indexed)
              if (line.trim().isNotEmpty)
                pw.Text(line,
                    style: pw.TextStyle(
                      fontSize: i == 0 ? 14 : 12,
                      fontWeight: pw.FontWeight.bold,
                      color: i == 0 ? darkGreen : ink,
                      lineSpacing: 1.3,
                    )),
          ]),
        ),
        // وسط: الشعار.
        pw.Expanded(
          flex: 28,
          child: pw.Center(
            child: logo != null
                ? pw.SizedBox(width: 72, height: 72, child: pw.Image(pw.MemoryImage(logo)))
                : pw.Container(
                    width: 72,
                    height: 72,
                    decoration: pw.BoxDecoration(
                      color: darkGreen,
                      borderRadius: pw.BorderRadius.circular(16),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text('إ',
                        style: pw.TextStyle(
                            fontSize: 34,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFFF0B429))),
                  ),
          ),
        ),
        // يسار: التاريخ والمرجع ورقم القيد، وربما مربع المصادقة.
        pw.Expanded(
          flex: 36,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            _headLine('التاريخ:', date, bold: false),
            _headLine('$refLabel:', refDisplay, valueColor: gold),
            _headLine('رقم القيد:', '............', bold: false),
            if (showApproval) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                width: 160,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: green, width: 1.5),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: const PdfColor.fromInt(0xFFF9FBF9),
                ),
                child: pw.Column(children: [
                  pw.Text(approvalLabel,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkGreen)),
                  pw.Divider(color: dotted, thickness: 0.5, height: 8),
                  pw.SizedBox(height: 8),
                  pw.Text('التوقيع: ...................',
                      style: const pw.TextStyle(fontSize: 8, color: grey)),
                ]),
              ),
            ],
          ]),
        ),
      ]),
      pw.SizedBox(height: 4),
      pw.Container(height: 2.5, color: green),
      pw.SizedBox(height: 6),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text('المرجع: $refDisplay',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: grey)),
        ),
        pw.Expanded(
          flex: 6,
          child: pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: titleColor, width: 2)),
              ),
              child: pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 17, fontWeight: pw.FontWeight.bold, color: titleColor)),
            ),
          ),
        ),
        pw.Expanded(flex: 2, child: pw.SizedBox()),
      ]),
      pw.SizedBox(height: 8),
    ]);
  }

  pw.Widget _headLine(String label, String value, {bool bold = true, PdfColor? valueColor}) =>
      pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 4),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor,
            )),
      ]);

  /// `sectionHeader(title)`
  pw.Widget _section(String title) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: const pw.BoxDecoration(
          color: sectionBg,
          border: pw.Border(bottom: pw.BorderSide(color: green, width: 1.5)),
        ),
        child: pw.Text(title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green)),
      );

  /// `infoRow2Cols(labelRight, valRight, labelLeft, valLeft)`
  pw.Widget _info2(String labelRight, String valRight, String labelLeft, String valLeft) =>
      pw.Row(children: [
        _infoCell(labelRight, isLabel: true, flex: 15),
        _infoCell(valRight, flex: 35),
        _infoCell(labelLeft, isLabel: true, flex: 15),
        _infoCell(valLeft, flex: 35),
      ]);

  pw.Widget _infoCell(String text, {bool isLabel = false, required int flex}) => pw.Expanded(
        flex: flex,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: isLabel ? labelBg : null,
            border: const pw.Border(bottom: pw.BorderSide(color: dotted, width: 0.5)),
          ),
          child: pw.Text(text.isEmpty ? '—' : text,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: isLabel ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
      );

  /// جدول البيانات أعلى السند حسب نوعه.
  List<pw.Widget> _infoTable(String type, Map<String, String> m, String date) {
    String v(String k) => m[k] ?? '';
    final children = <pw.Widget>[];

    switch (type) {
      case 'issue':
        children.addAll([
          _section('بيانات المخزن والتوجيه'),
          _info2('جهة الصرف', v('warehouse'), 'التوجيه',
              'يتم صرف الأصناف المبينة في الجدول أدناه'),
          _section('بيانات الجهة المستفيدة'),
          _info2('اسم الوحدة', v('beneficiary'), 'قوة الأفراد', v('strength')),
          _info2('من تاريخ', v('start_date'), 'إلى تاريخ', v('end_date')),
          _info2('نوع الصرف', 'إعاشة لمدة ${v('days').isEmpty ? '١' : v('days')} يوم',
              'المبررات والملاحظات', v('notes')),
        ]);
      case 'receipt':
        children.addAll([
          _section('بيانات المستلم'),
          _info2('الاسم', '.................................', 'الرتبة',
              '.................................'),
          _section('بيانات الجهة المستفيدة'),
          _info2('الوحدة المستفيدة', v('beneficiary'), 'قوة الأفراد', v('strength')),
          _info2('تاريخ الاستلام', date, 'نوع الصرف',
              'إعاشة لمدة ${v('days').isEmpty ? '١' : v('days')} يوم'),
        ]);
      case 'receive':
        children.addAll([
          _section('بيانات سند التوريد'),
          _info2('المستودع', v('warehouse'), 'رقم السند', v('ref')),
          _info2('الجهة الموردة', v('supplier'), 'تاريخ التوريد', v('date')),
          _info2('رقم الفاتورة / التاجر', v('invoiceNo'), 'ملاحظات السند', v('notes')),
        ]);
      case 'transfer':
        children.addAll([
          _section('بيانات التحويل المخزني'),
          _info2('المستودع المصدر', v('warehouse'), 'المستودع المستقبل', v('destWarehouse')),
          _info2('حالة التحويل', v('statusLabel'), 'المرجع', v('ref')),
          _info2('مبررات وملاحظات', v('notes'), 'تاريخ الإرسال', v('date')),
        ]);
      case 'return_unit':
      case 'return_supplier':
        final isUnit = type == 'return_unit';
        children.addAll([
          _section(isUnit ? 'بيانات مرتجع من وحدة مستفيدة' : 'بيانات مرتجع إلى مورّد'),
          _info2('المستودع', v('warehouse'), isUnit ? 'الوحدة المرتجعة' : 'الجهة الموردة',
              v('party')),
          _info2('حالة الأصناف', v('condition'), 'تاريخ المرتجع', v('date')),
          _info2('مرجع السند الأصلي', v('origRef'), 'مبررات وملاحظات', v('notes')),
        ]);
      case 'report':
        children.addAll([
          _section('محددات التقرير'),
          _info2('المستودع', v('warehouse').isEmpty ? 'الكل' : v('warehouse'), 'الجهة',
              v('party').isEmpty ? 'الكل' : v('party')),
          if (v('notes').isNotEmpty) _info2('ملاحظات', v('notes'), '', ''),
        ]);
    }
    if (children.isEmpty) return const [];
    return [
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children),
      ),
      pw.SizedBox(height: 8),
    ];
  }

  /// `itemsTable(headers, rows)` — جدول الأصناف بترويسة خضراء وصفوف متناوبة.
  ///
  /// `pw.Table` في مكتبة pdf لا تعرف اتجاه النص إطلاقًا وترسم الأعمدة يسارًا
  /// ليمينًا دائمًا، فيُعكس ترتيب الأعمدة يدويًا ليبدأ عمود «م» من اليمين.
  pw.Widget itemsTable(List<String> headers, List<List<String>> rows) {
    final cols = headers.reversed.toList();
    final data = [
      for (final r in rows)
        [
          // تُكمَّل الخلايا الناقصة قبل العكس حتى لا تنزاح الأعمدة.
          for (var c = headers.length - 1; c >= 0; c--) c < r.length ? r[c] : '',
        ],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.7),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: green),
          children: [
            for (final h in cols)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                alignment: pw.Alignment.center,
                child: pw.Text(h,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
          ],
        ),
        if (data.isEmpty)
          pw.TableRow(children: [
            for (var i = 0; i < cols.length; i++)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                alignment: pw.Alignment.center,
                child: i == 0 ? pw.Text('لا توجد أصناف', style: const pw.TextStyle(fontSize: 11)) : pw.SizedBox(),
              ),
          ])
        else
          for (final (i, row) in data.indexed)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isEven ? lightRow : PdfColors.white),
              children: [
                for (final cell in row)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    alignment: pw.Alignment.center,
                    child: pw.Text(cell,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 10.5)),
                  ),
              ],
            ),
      ],
    );
  }

  /// رمز التحقق من التوقيع الإلكتروني: يقرأه أي جهاز بكاميرته فيتحقق من أن
  /// الورقة التي بين يديه هي ما وقّعه القائد فعلًا، بلا وصول إلى قاعدة البيانات.
  pw.Widget signatureStamp(String token) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: token,
              width: 46,
              height: 46,
              drawText: false,
            ),
            pw.SizedBox(width: 8),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('موقَّع إلكترونيًا',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold, color: darkGreen)),
                pw.Text('امسح الرمز للتحقق من صحة المستند',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      );

  /// `signatures(type, masterInfo)`
  pw.Widget signatures(String type, Map<String, String> master) {
    pw.Widget box(String title, [String value = '...........................']) => pw.Expanded(
          child: pw.Column(children: [
            pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            pw.Text(value, style: const pw.TextStyle(fontSize: 10, color: grey)),
          ]),
        );

    if (type == 'issue' || type == 'transfer' || type == 'report') {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 20),
        child: pw.Row(children: [box('ركن إدارة الإمداد'), box('مكتب إدارة الإمداد')]),
      );
    }
    if (type == 'receive') {
      final wh = master['warehouse']?.isNotEmpty == true ? master['warehouse']! : 'المستودع الرئيسي';
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18),
        child: pw.Row(children: [
          box('ركن إدارة الإمداد'),
          box('مدير مخزن ($wh)'),
          box('المراجعة والتدقيق',
              master['audit']?.isNotEmpty == true ? master['audit']! : '...........................'),
          box('الرقابة والتفتيش',
              master['supervision']?.isNotEmpty == true
                  ? master['supervision']!
                  : '...........................'),
        ]),
      );
    }
    final wh = master['warehouse']?.isNotEmpty == true ? master['warehouse']! : 'المستودع';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18),
      child: pw.Row(children: [box('الجهة المسلّمة ($wh)'), box('المستلم / المعتمد')]),
    );
  }

  // ───────── واجهات السندات ─────────
  /// `printIssueVoucher()`
  Future<Uint8List> issueVoucher(Map<String, String> master, List<List<String>> rows,
          {String? signatureToken}) =>
      build(
        signatureToken: signatureToken,
        master: master,
        rows: rows,
        title: 'أمر صرف مخزني',
        titleColor: titleIssue,
        type: 'issue',
      );

  /// `printReceiveVoucher()`
  Future<Uint8List> receiveVoucher(Map<String, String> master, List<List<String>> rows,
          {String? signatureToken}) =>
      build(
        signatureToken: signatureToken,
        master: master,
        rows: rows,
        title: 'سند توريد مخزني',
        titleColor: titleReceive,
        type: 'receive',
      );

  /// `printTransferVoucher()`
  Future<Uint8List> transferVoucher(Map<String, String> master, List<List<String>> rows,
          {String? signatureToken}) =>
      build(
        signatureToken: signatureToken,
        master: master,
        rows: rows,
        title: 'إذن تحويل مخزني',
        titleColor: titleTransfer,
        type: 'transfer',
      );

  /// `printReturnVoucher()`
  Future<Uint8List> returnVoucher(
    Map<String, String> master,
    List<List<String>> rows, {
    required bool fromUnit,
    String? signatureToken,
  }) =>
      build(
        signatureToken: signatureToken,
        master: master,
        rows: rows,
        title: fromUnit ? 'سند مرتجع من وحدة مستفيدة' : 'سند مرتجع إلى مورّد',
        titleColor: titleReturn,
        type: fromUnit ? 'return_unit' : 'return_supplier',
      );

  /// `printGenericReport()` — تقرير مجمّع بعناوين أعمدة حرة.
  Future<Uint8List> report({
    required Map<String, String> master,
    required List<List<String>> rows,
    required List<String> headers,
    required String title,
    PdfColor color = titleReturn,
  }) =>
      build(
        master: master,
        rows: rows,
        headers: headers,
        title: title,
        titleColor: color,
        type: 'report',
      );

  /// `printIssueWithReceipt()` — أمر الصرف ثم إشعار الاستلام في ملف واحد.
  Future<Uint8List> issueWithReceipt(Map<String, String> master, List<List<String>> rows,
      {String? signatureToken}) async {
    final issue = await issueVoucher(master, rows, signatureToken: signatureToken);
    final receipt = await build(
      signatureToken: signatureToken,
      master: master,
      rows: rows,
      title: 'استلام مخزني (إشعار)',
      titleColor: titleReceive,
      type: 'receipt',
      receiptNote: 'استلمت أنا الموضحة بياناتي أعلاه الأصناف المبينة في الجدول بتمامها وكمالها.',
    );
    // ملفان منفصلان يُدمجان بإعادة البناء في مستند واحد أسهل من دمج بايتات PDF.
    return _merge([issue, receipt]);
  }

  static Future<Uint8List> _merge(List<Uint8List> docs) async {
    if (docs.length == 1) return docs.first;
    final out = pw.Document();
    for (final d in docs) {
      await for (final page in Printing.raster(d, dpi: 150)) {
        final img = await page.toPng();
        out.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(img), fit: pw.BoxFit.contain),
        ));
      }
    }
    return out.save();
  }

  /// يعرض نافذة الطباعة/حفظ PDF (`printHtml` في الويب).
  /// تُعرض معاينة أولًا، ولا تُرسل إلى الطابعة إلا بتأكيد المستخدم.
  static Future<void> show(Uint8List bytes, {String name = 'مستند'}) =>
      showPrintPreview(bytes, name: name);
}
