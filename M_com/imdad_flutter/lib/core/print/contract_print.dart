import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/arabic_words.dart';
import 'military_print.dart';
import 'print_format.dart';
import 'voucher_print.dart';

/// طباعة «عقد الشراء» على النموذج المعتمد (قائمة الكمية المستهلكة).
///
/// **الأصناف نصٌّ حرّ** لا صلة له بأصناف النظام. سطر «ما يقابل بالريال السعودي»
/// لا يظهر إلا حين تكون العملة يمنية، بسعر الصرف المُدخل.
///
/// **مواضع خانات التوقيع تتبع طول الأصناف:**
/// * صفحة واحدة ⇒ تحت جدول الأصناف والإجمالي والإقرارين مباشرةً داخل الإطار.
/// * أكثر من صفحة ⇒ في أسفل كل صفحة، تحت مربع إطار النموذج.
class ContractPrint {
  ContractPrint._();

  static const _line = PdfColors.black;
  static const _headFill = PdfColor.fromInt(0xFFD9D9D9);
  static const _totalFill = PdfColor.fromInt(0xFFE5B8B7);

  /// أقل عدد صفوف يظهر في الجدول ليبقى النموذج مكتمل الهيئة كالأصل.
  static const _minRows = 4;
  static const _rowH = 20.0;

  /// أعمدة الجدول (flex) من اليمين: م، الصنف، الوحدة، الكمية، سعر الوحدة،
  /// الإجمالي، رقم الفاتورة، تاريخ الشراء، ملاحظة.
  static const _flex = [5, 24, 9, 9, 11, 12, 11, 13, 13];

  static const _confirmText =
      'يؤكد صحة البيانات المجدولة كلا من البائع والمشتري ويتحملوا كافة المسؤولية أمام الرقابة والتفتيش.';
  static const _attachText = 'مرفق فواتير للأصناف المبينة أعلاه.';

  static pw.Widget _cell(String text,
      {int flex = 1,
      bool bold = false,
      double size = 10,
      pw.TextAlign align = pw.TextAlign.center,
      PdfColor? fill,
      double? height,
      pw.Widget? child}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        height: height,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: pw.BoxDecoration(
          color: fill,
          border: pw.Border.all(color: _line, width: 0.7),
        ),
        child: child ??
            pw.Text(text,
                textAlign: align,
                style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  static int _sum(List<int> f, int from, int to) => f.sublist(from, to).fold(0, (a, b) => a + b);

  static pw.Widget _tableHeader(String cur) {
    const h2 = _rowH * 2;
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _cell('م', flex: _flex[0], bold: true, fill: _headFill, height: h2),
      _cell('اسم الصنف', flex: _flex[1], bold: true, fill: _headFill, height: h2),
      _cell('الوحدة', flex: _flex[2], bold: true, fill: _headFill, height: h2),
      _cell('الكمية', flex: _flex[3], bold: true, fill: _headFill, height: h2),
      pw.Expanded(
        flex: _flex[4] + _flex[5],
        child: pw.Column(children: [
          pw.Row(children: [
            _cell('قيمة الصنف في فاتورة الشراء بالريال ($cur)',
                flex: 1, bold: true, size: 9, fill: _headFill, height: _rowH),
          ]),
          pw.Row(children: [
            _cell('سعر الوحدة', flex: _flex[4], bold: true, fill: _headFill, height: _rowH),
            _cell('السعر الإجمالي', flex: _flex[5], bold: true, fill: _headFill, height: _rowH),
          ]),
        ]),
      ),
      _cell('رقم الفاتورة', flex: _flex[6], bold: true, fill: _headFill, height: h2),
      _cell('تاريخ الشراء', flex: _flex[7], bold: true, fill: _headFill, height: h2),
      _cell('ملاحظة', flex: _flex[8], bold: true, fill: _headFill, height: h2),
    ]);
  }

  static pw.Widget _itemRow(int no, ContractItem? it) {
    String n(double v) => v == 0 ? '' : printNum(v);
    return pw.Row(children: [
      _cell(it == null ? '' : '$no', flex: _flex[0], fill: _headFill, height: _rowH),
      _cell(it?.name ?? '', flex: _flex[1], height: _rowH, size: 9.5),
      _cell(it?.unit ?? '', flex: _flex[2], height: _rowH, size: 9.5),
      _cell(it == null ? '' : n(it.qty), flex: _flex[3], height: _rowH),
      _cell(it == null ? '' : n(it.price), flex: _flex[4], height: _rowH),
      _cell(it == null ? '' : n(it.total), flex: _flex[5], height: _rowH),
      _cell(it?.invoiceNo ?? '', flex: _flex[6], height: _rowH),
      _cell(it == null || it.date.isEmpty ? '' : '${printDate(it.date)}م', flex: _flex[7], height: _rowH, size: 9),
      _cell(it?.note ?? '', flex: _flex[8], height: _rowH, size: 9),
    ]);
  }

  /// صف إجماليٍّ ملوّن: تسمية تمتد على الأعمدة الخمسة الأولى، فقيمة، فبيان.
  static pw.Widget _totalRow({required String label, required String value, required String words}) {
    return pw.Row(children: [
      _cell(label, flex: _sum(_flex, 0, 5), bold: true, fill: _totalFill, height: _rowH),
      _cell(value, flex: _flex[5], bold: true, fill: _totalFill, height: _rowH),
      _cell(words, flex: _sum(_flex, 6, 9), bold: true, size: 9.5, fill: _totalFill, height: _rowH),
    ]);
  }

  static pw.Widget _sigBox(String title, {bool withPrint = true}) {
    pw.Widget field(String l) => pw.Expanded(
          child: pw.Text('$l ..........', style: const pw.TextStyle(fontSize: 8.5)),
        );
    return pw.Expanded(
      child: pw.Container(
        height: 50,
        padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 3),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.7)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Spacer(),
          pw.Row(children: [field('الاسم/'), field('التوقيع/'), if (withPrint) field('البصمة/')]),
        ]),
      ),
    );
  }

  /// خانات التوقيع: المستلمة ×2، التنفيذية ×2، الرقابة والتفتيش ×2، البائع ×2.
  static const double _sigHeight = 4 * 50 + 3 * 4;

  static pw.Widget _signatures() {
    pw.Widget row(String a, {bool withPrint = true}) => pw.Row(children: [
          _sigBox(a, withPrint: withPrint),
          pw.SizedBox(width: 4),
          _sigBox(a, withPrint: withPrint),
        ]);
    return pw.Column(children: [
      row('الجهة المستلمة'),
      pw.SizedBox(height: 4),
      row('الجهة التنفيذية'),
      pw.SizedBox(height: 4),
      row('الرقابة والتفتيش'),
      pw.SizedBox(height: 4),
      row('البائع', withPrint: false),
    ]);
  }

  /// ترويسة الجهة: أسطر الجهة يمينًا، الشعار وسطًا، بيانات العقد يسارًا.
  static pw.Widget _letterhead(MilitaryPrint engine, Uint8List? logo, LinkPurchaseContract c, List<ContractItem> items) {
    final invoices = {for (final i in items) if (i.invoiceNo.trim().isNotEmpty) i.invoiceNo.trim()};
    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text('$k $v', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        );
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
        flex: 4,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final l in engine.orgLines)
            if (l.trim().isNotEmpty) pw.Text(l, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.Expanded(
        flex: 2,
        child: pw.Center(
          child: logo == null ? pw.SizedBox(height: 64) : pw.SizedBox(width: 64, height: 64, child: pw.Image(pw.MemoryImage(logo))),
        ),
      ),
      pw.Expanded(
        flex: 4,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          kv('التاريخ:', c.listDate.isEmpty ? '' : '${printDate(c.listDate)}م'),
          kv('رقم العقد:', c.contractNo),
          kv('مرفقات:', '( ${invoices.isEmpty ? '   ' : invoices.length} )'),
          if (c.notes.trim().isNotEmpty) kv('ملاحظات:', c.notes.trim()),
        ]),
      ),
    ]);
  }

  /// سطر «ما يقابل بالريال السعودي» لا يظهر إلا للعملة اليمنية وبسعر صرف مُدخل.
  static bool showsSarEquivalent(LinkPurchaseContract c) => c.currency == LinkCurrency.yer && c.exchangeRate > 0;

  /// يبني ملف PDF للعقد. [forcePaged] للاختبار فقط.
  static Future<Uint8List> build(AppDatabase db, LinkPurchaseContract c, {bool? forcePaged}) async {
    final engine = await VoucherPrint.engineOf(db);
    Uint8List? logo = engine.logoBytes;
    if (logo == null) {
      try {
        logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
      } catch (_) {}
    }
    final theme = await engine.pdfTheme();
    final items = ContractItem.decode(c.itemsJson);
    final cur = LinkCurrency.label(c.currency);
    final total = ContractItem.sum(items);
    final rows = [for (var i = 0; i < items.length; i++) _itemRow(i + 1, items[i])];
    for (var i = items.length; i < _minRows; i++) {
      rows.add(_itemRow(i + 1, null));
    }

    final body = <pw.Widget>[
      _letterhead(engine, logo, c, items),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'عقد شراء ${c.title}${c.supplier.trim().isEmpty ? '' : ' من ${c.supplier.trim()}'}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          'قائمة الكمية المستهلكة: بتاريخ ${c.listDate.isEmpty ? '   /   /      ' : printDate(c.listDate)}م',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 8),
      _tableHeader(cur),
      ...rows,
      _totalRow(
        label: 'الإجمالي بالريال $cur على حسب الفاتورة',
        value: printNum(total),
        words: amountInWords(total, major: LinkCurrency.major(c.currency), minor: LinkCurrency.minor(c.currency)),
      ),
      // سطر المقابل بالسعودي: لا يظهر إلا للعملة اليمنية وبسعر صرف مُدخل.
      if (showsSarEquivalent(c))
        _totalRow(
          label: 'ما يقابل بالريال السعودي',
          value: printMoney(total / c.exchangeRate),
          words: 'الإجمالي ÷ سعر الصرف: ${printNum(c.exchangeRate)} ريال يمني',
        ),
      pw.SizedBox(height: 8),
      pw.Text('- $_confirmText', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 3),
      pw.Text('- $_attachText', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
    ];

    const margin = 28.0;
    pw.Widget frame({required double reserveBottom}) => pw.Positioned.fill(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(bottom: reserveBottom),
            child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 1.2))),
          ),
        );

    Future<(Uint8List, int)> make(bool paged) async {
      final pdf = pw.Document(theme: theme);
      pdf.addPage(pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: theme,
          margin: const pw.EdgeInsets.all(margin),
          // الإطار يحيط بالمحتوى؛ وفي وضع الصفحات المتعددة يترك أسفل الصفحة لخانات التوقيع.
          buildBackground: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(margin - 8),
              child: pw.Stack(children: [frame(reserveBottom: paged ? _sigHeight + 6 : 0)]),
            ),
          ),
        ),
        footer: paged ? (ctx) => pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: _signatures()) : null,
        // رأس الجدول يتكرر في الصفحات التالية فيُقرأ كل عمود دون الرجوع للأولى.
        header: paged
            ? (ctx) => ctx.pageNumber > 1
                ? pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6, left: 6, right: 6),
                    child: _tableHeader(cur),
                  )
                : pw.SizedBox()
            : null,
        build: (ctx) => [
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6), child: pw.Column(children: [...body])),
          if (!paged) pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6), child: _signatures()),
        ],
      ));
      final pages = pdf.document.pdfPageList.pages.length;
      return (await pdf.save(), pages);
    }

    if (forcePaged == true) return (await make(true)).$1;
    final single = await make(false);
    if (forcePaged == false || single.$2 <= 1) return single.$1;
    return (await make(true)).$1;
  }

  /// معاينة الطباعة ثم الأرشفة التلقائية إن مُكِّنت «عقود الشراء».
  static Future<void> print(AppDatabase db, LinkPurchaseContract c) async {
    final bytes = await build(db, c);
    final name = 'عقد شراء ${c.contractNo.isEmpty ? c.title : c.contractNo}';
    await MilitaryPrint.show(bytes, name: name);
    try {
      await ArchiveAuto(db).onDocumentPrinted(
        op: 'contract',
        title: '$name — ${c.supplier}',
        docRef: c.contractNo,
        docDate: c.listDate,
        pdfBytes: bytes,
        fileName: '${name.replaceAll(' ', '-')}.pdf',
      );
    } catch (_) {}
  }
}
