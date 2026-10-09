import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../domain/arabic_words.dart';
import '../../domain/custody_sheet.dart';
import '../../domain/finance.dart';
import 'military_print.dart';
import 'print_format.dart';
import 'voucher_print.dart';
import '../../core/error_log.dart';
import '../../domain/print_forms.dart';

/// طباعة «مسير العهدة» بتنسيق ملف الـPDF المعتمد: صفحة أفقية، ترويسة من
/// مستويين (مبلغ العهدة / مرتجع / المبلغ المنصرف)، شبكة بحدود سوداء، أسطر
/// الإجماليات الملوّنة، وجملة المتبقي بالأحمر.
///
/// عمود «سعر الصرف» يظهر في شاشة الإدخال وحدها (مخفيٌّ في الطباعة كما في الأصل)،
/// وخلية رقم الفاتورة المكرر تُلوَّن بالأحمر الفاتح كما في الإدخال.
class CustodySheetPrint {
  CustodySheetPrint._();

  static const _line = PdfColors.black;
  static const _custodyFill = PdfColor.fromInt(0xFFF8CBAD);
  static const _spentFill = PdfColor.fromInt(0xFFFFD966);
  static const _dupFill = PdfColor.fromInt(0xFFFFC7CE);
  static const _dupText = PdfColor.fromInt(0xFF9C0006);
  static const _red = PdfColor.fromInt(0xFFFF0000);

  /// أعمدة الطباعة من اليمين بأوزان عروض ملف Excel.
  /// 0 تاريخ | 1 عهدة | 2-3 مرتجع (سعودي/يمني) | 4-5 منصرف (سعودي/يمني) |
  /// 6 اسم | 7 بيان | 8 فئة | 9 قيد | 10 فاتورة | 11 محل | 12 ملاحظات
  static const _w = [12.6, 13.7, 10.5, 12.0, 15.3, 15.7, 22.3, 30.4, 10.5, 6.9, 12.8, 28.9, 17.1];

  static double _sumW(int from, int to) => _w.sublist(from, to).fold(0.0, (a, b) => a + b);

  static String _sar(double v) => v == 0 ? '' : '${printMoney(v)} ر.س.';
  static String _yer(double v) => v == 0 ? '' : '${printNum(v)} ر.ي.';

  static pw.Widget _c(
    String text, {
    required double flex,
    required double h,
    required double size,
    bool bold = true,
    PdfColor? fill,
    PdfColor color = PdfColors.black,
    pw.Alignment align = pw.Alignment.center,
    double border = 0.6,
    double? height,
  }) =>
      pw.Expanded(
        flex: (flex * 100).round(),
        child: pw.Container(
          height: height ?? h,
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 2),
          decoration: pw.BoxDecoration(color: fill, border: pw.Border.all(color: _line, width: border)),
          // النص الأطول من خليته يصغَّر ليتسع (تقليص الملاءمة في Excel) لا أن يُقصّ.
          // FittedBox لا يقبل عرضًا صفريًّا، فالخلية الفارغة تبقى بلا محتوى.
          child: text.isEmpty
              ? null
              : pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            child: pw.Text(text,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
          ),
        ),
      );

  static pw.Widget _head(double h, double size, String grantCur) {
    pw.Widget c(String t, int i, {double? height, int span = 1}) =>
        _c(t, flex: _sumW(i, i + span), h: h, size: size, height: height);
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      c('التاريخ', 0, height: h * 2),
      pw.Expanded(
        flex: (_w[1] * 100).round(),
        child: pw.Column(children: [
          pw.Row(children: [c('مبلغ العهدة', 1, height: h)]),
          pw.Row(children: [c(grantCur, 1, height: h)]),
        ]),
      ),
      pw.Expanded(
        flex: ((_w[2] + _w[3]) * 100).round(),
        child: pw.Column(children: [
          pw.Row(children: [c('مرتجع', 2, span: 2, height: h)]),
          pw.Row(children: [c('سعودي', 2, height: h), c('يمني', 3, height: h)]),
        ]),
      ),
      pw.Expanded(
        flex: ((_w[4] + _w[5]) * 100).round(),
        child: pw.Column(children: [
          pw.Row(children: [c('المبلغ المنصرف', 4, span: 2, height: h)]),
          pw.Row(children: [c('سعودي', 4, height: h), c('يمني', 5, height: h)]),
        ]),
      ),
      c('الاسم', 6, height: h * 2),
      c('البيان', 7, height: h * 2),
      c('الفئة', 8, height: h * 2),
      c('رقم القيد', 9, height: h * 2),
      c('رقم الفاتورة', 10, height: h * 2),
      c('اسم المحل', 11, height: h * 2),
      c('ملاحظات', 12, height: h * 2),
    ]);
  }

  static pw.Widget _row(LinkCustodySheetRow r, double h, double size, bool dup, bool yerSheet) {
    final v = CustodyRowValues(
      grantSar: r.grantSar,
      returnSar: r.returnSar,
      returnYer: r.returnYer,
      spentSar: r.spentSar,
      spentYer: r.spentYer,
      rate: r.rate,
    );
    pw.Widget c(String t, int i, {PdfColor? fill, PdfColor color = PdfColors.black}) =>
        _c(t, flex: _w[i], h: h, size: size, fill: fill, color: color);
    return pw.Row(children: [
      c(printDate(r.date), 0),
      c(yerSheet ? _yer(r.grantYer) : _sar(r.grantSar), 1),
      c(_sar(v.returnedInSar), 2),
      c(_yer(r.returnYer), 3),
      c(_sar(v.spentInSar), 4),
      c(_yer(r.spentYer), 5),
      c(r.person, 6),
      c(r.statement, 7),
      c(r.category.trim(), 8),
      c(r.entryNo, 9),
      c(r.invoiceNo, 10, fill: dup ? _dupFill : null, color: dup ? _dupText : PdfColors.black),
      c(r.shop, 11),
      c(r.notes, 12),
    ]);
  }

  /// سطر إجمالي: القيمة تمتد على أعمدة التاريخ حتى المنصرف اليمني (0-5)،
  /// والتسمية في عمود البيان، وبقية الخلايا ملوّنة فارغة كالأصل.
  static pw.Widget _totalRow(String label, String value, double h, double size,
      {PdfColor? fill, PdfColor color = PdfColors.black, String? tail}) {
    pw.Widget c(String t, int from, int to, {bool bold = true, PdfColor col = PdfColors.black}) =>
        _c(t, flex: _sumW(from, to), h: h, size: size, fill: fill, color: col, bold: bold);
    return pw.Row(children: [
      c(value, 0, 6, col: color),
      c('', 6, 7),
      c(label, 7, 8, col: color),
      if (tail == null) c('', 8, 13) else c(tail, 8, 13, col: color),
    ]);
  }

  /// يبني ملف PDF للمسير. [rowHeightOverride] للاختبار.
  static Future<Uint8List> build(AppDatabase db, LinkCustodySheet sheet, List<LinkCustodySheetRow> rows) async {
    final engine = await VoucherPrint.engineOf(db, form: PrintForms.custodySheet);
    final theme = await engine.pdfTheme();

    final cur = sheet.currency;
    final yerSheet = cur == FinCurrency.yer;
    final values = [
      for (final r in rows)
        CustodyRowValues(
            grantSar: r.grantSar,
            grantYer: r.grantYer,
            returnSar: r.returnSar,
            returnYer: r.returnYer,
            spentSar: r.spentSar,
            spentYer: r.spentYer,
            rate: r.rate),
    ];
    // الحساب بعملة العهدة؛ والمنصرف يظهر أيضًا بالعملة الأخرى بسعر صرف الأسطر.
    final totals = custodyTotalsIn(values, cur);
    final spentOther = custodyTotalsIn(values, yerSheet ? FinCurrency.sar : FinCurrency.yer).spent;
    String money(double v) => yerSheet ? '${printNum(v)} ر.ي.' : '${printMoney(v)} ر.س.';
    String moneyOther(double v) => yerSheet ? '${printMoney(v)} ر.س.' : '${printNum(v)} ر.ي.';
    final curName = FinCurrency.label(cur);
    final dups = duplicateInvoiceNos([for (final r in rows) r.invoiceNo]);

    // الأسطر الكثيرة تُضغط لتتسع صفحة واحدة كأمر «احتواء الصفحة» في Excel،
    // وما فاق ذلك يُقسَّم على صفحات برأسٍ متكرر.
    const pageH = 595.0 - 2 * 16;
    final extra = 3 + (totals.returned > 0 ? 1 : 0) + (spentOther > 0 ? 1 : 0);
    final slots = rows.length + extra + 3;
    var h = pageH / slots;
    final paginate = h < 9.5;
    if (paginate) h = 13;
    if (h > 15) h = 15;
    final size = (h * 0.62).clamp(5.5, 9.5);

    final sentenceBody = totals.remaining >= 0
        ? 'متبقي لكم من العهدة التشغيلية رقم (${sheet.sheetNo.isEmpty ? '   ' : sheet.sheetNo}) مبلغ وقدره '
        : 'تجاوز المنصرف العهدة التشغيلية رقم (${sheet.sheetNo.isEmpty ? '   ' : sheet.sheetNo}) بمبلغ وقدره ';
    final sentence = sentenceBody + amountInWords(totals.remaining, major: yerSheet ? 'ريال يمني' : 'ريال سعودي', minor: yerSheet ? 'فلس' : 'هللة');

    final holder = sheet.holderName.isNotEmpty ? sheet.holderName : sheet.title;
    pw.Widget metaBox(String label, String value) => pw.Expanded(
          child: pw.Container(
            height: h + 2,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
            child: pw.Text('$label: $value', style: pw.TextStyle(fontSize: size + 1.5, fontWeight: pw.FontWeight.bold)),
          ),
        );

    // رقم العهدة واسم صاحبها **فوق** رؤوس الجدول (لا تحتها)، ويتكرران مع الرأس
    // في كل صفحة، فيبقى الجدول نفسه كما هو.
    final meta = pw.Row(children: [
      metaBox('رقم العهدة', sheet.sheetNo.isEmpty ? '' : sheet.sheetNo),
      metaBox('اسم صاحب العهدة', holder),
    ]);

    final body = <pw.Widget>[
      for (final r in rows)
        _row(r, h, size, dups.contains(normalizeInvoiceNo(r.invoiceNo)), yerSheet),
      _totalRow('اجمالي العهدة بالريال $curName', money(totals.granted), h, size, fill: _custodyFill),
      _totalRow('اجمالي المبلغ المنصرف بالريال $curName', money(totals.spent), h, size, fill: _spentFill),
      if (spentOther > 0)
        _totalRow('المنصرف بالريال ${yerSheet ? 'السعودي' : 'اليمني'} (بسعر صرف الأسطر)', moneyOther(spentOther), h, size, fill: _spentFill),
      if (totals.returned > 0)
        _totalRow('اجمالي المرتجع بالريال $curName', money(totals.returned), h, size),
      _totalRow(
        totals.remaining >= 0 ? 'المتبقي بالريال $curName' : 'العجز بالريال $curName',
        money(totals.remaining.abs()),
        h,
        size,
        color: _red,
        tail: sentence,
      ),
    ];

    final pdf = pw.Document(theme: theme);
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      textDirection: pw.TextDirection.rtl,
      theme: theme,
      margin: const pw.EdgeInsets.all(16),
      header: (ctx) => pw.Column(children: [
        meta,
        pw.SizedBox(height: 4),
        _head(h, size, curName),
      ]),
      // أرقام الصفحات إن زادت عن صفحة.
      footer: (ctx) => ctx.pagesCount > 1
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Center(child: pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8))),
            )
          : pw.SizedBox(),
      build: (ctx) => body,
    ));
    return pdf.save();
  }

  /// معاينة الطباعة ثم الأرشفة التلقائية إن مُكِّنت «مسيرات العهدة».
  static Future<void> print(AppDatabase db, LinkCustodySheet sheet, List<LinkCustodySheetRow> rows) async {
    final bytes = await build(db, sheet, rows);
    final name = 'مسير عهدة ${sheet.sheetNo.isEmpty ? sheet.title : sheet.sheetNo}';
    await MilitaryPrint.show(bytes, name: name);
    try {
      await ArchiveAuto(db).onDocumentPrinted(
        op: 'custodySheet',
        title: sheet.title.isEmpty ? name : '$name — ${sheet.title}',
        docRef: sheet.sheetNo,
        pdfBytes: bytes,
        fileName: '${name.replaceAll(' ', '-')}.pdf',
      );
    } catch (err, stack) {
      ErrorLogger.critical('archive.custodySheet', err, stack: stack, userMessage: 'طُبع المسير لكن تعذّرت أرشفته تلقائيًّا');
    }
  }
}
