import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../data/repos/linkage_repo.dart' show LinkCurrency;
import '../../domain/arabic_words.dart';
import 'military_print.dart';
import 'print_format.dart';
import 'voucher_print.dart';
import '../../core/error_log.dart';

/// طباعة «سند استلام مالي» على نموذج الجهة المعتمد.
///
/// **سندٌ واحد في الصفحة** (النموذج الورقي يحمل سندين؛ هنا يبقى باقي الصفحة
/// فارغًا). كل حقلٍ فارغ يُطبع نقاطًا ليُملأ بخط اليد، فيصلح السند المملوء
/// والنموذج الفارغ ([receipt] = `null`) بالمسار نفسه.
///
/// المبلغ بالحروف **مشتقٌّ من المبلغ رقمًا** — لا يُدخَل ولا يُخزَّن.
class MoneyReceiptPrint {
  MoneyReceiptPrint._();

  static const _line = PdfColors.black;
  static const _titleRed = PdfColor.fromInt(0xFFFF0000);

  /// المبلغ بالحروف؛ فارغ إن لم يُدخل مبلغ.
  static String words(double amount, String currency) => amount <= 0
      ? ''
      : amountInWords(amount, major: LinkCurrency.major(currency), minor: LinkCurrency.minor(currency));

  /// المبلغ رقمًا مع رمز عملته؛ فارغ إن لم يُدخل مبلغ.
  static String figure(double amount, String currency) =>
      amount <= 0 ? '' : '${printMoney(amount)} ${LinkCurrency.symbol(currency)}';

  /// حقلٌ: تسميةٌ فقيمةٌ على سطرٍ منقَّط (نقاطٌ كاملة إن لم توجد قيمة).
  static pw.Widget _field(String label, String value, {double size = 12, int flex = 1}) => pw.Expanded(
        flex: flex,
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Container(
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8, style: pw.BorderStyle.dotted)),
              ),
              child: pw.Text(value.isEmpty ? '' : value,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ]),
      );

  static pw.Widget _box(bool checked) => pw.Container(
        width: 26,
        height: 16,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line, width: 1),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: checked ? pw.Container(width: 14, height: 8, color: _line) : null,
      );

  static pw.Widget _sigColumn(String title, String name) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            pw.Text('الاسم/', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 4),
            pw.Expanded(child: pw.Text(name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
          ]),
          pw.SizedBox(height: 14),
          pw.Text('التوقيع/', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  /// الترويسة: بيانات التاريخ يسارًا، الشعار وسطًا، أسطر الجهة يمينًا.
  static pw.Widget _letterhead(MilitaryPrint engine, Uint8List? logo, LinkMoneyReceipt? r) {
    final date = DateTime.tryParse(r?.receiptDate ?? '');
    final gregorian = date == null
        ? '  /    /  ${DateTime.now().year}م'
        : '${printDate(r!.receiptDate)}م';
    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text('$k $v', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        );
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
        flex: 4,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final l in engine.orgLines)
            if (l.trim().isNotEmpty) pw.Text(l, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.Expanded(
        flex: 3,
        child: pw.Center(
          child: logo == null ? pw.SizedBox(height: 84) : pw.SizedBox(width: 84, height: 84, child: pw.Image(pw.MemoryImage(logo))),
        ),
      ),
      pw.Expanded(
        flex: 4,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          kv('التاريخ:', '  /    /      هـ'),
          kv('الموافق:', gregorian),
          kv('المرفقات:', r?.attachments ?? ''),
        ]),
      ),
    ]);
  }

  /// يبني PDF السند. [receipt] `null` ⇒ نموذجٌ فارغ.
  static Future<Uint8List> build(AppDatabase db, LinkMoneyReceipt? receipt) async {
    final engine = await VoucherPrint.engineOf(db);
    Uint8List? logo = engine.logoBytes;
    if (logo == null) {
      try {
        logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
      } catch (err, stack) {
        ErrorLogger.log('print.moneyReceipt.logo', err, stack);
      }
    }
    final theme = await engine.pdfTheme();
    final r = receipt;
    final cur = r?.currency ?? 'sar';
    final amount = r?.amount ?? 0;
    final date = DateTime.tryParse(r?.receiptDate ?? '') == null ? '' : printDate(r!.receiptDate);

    final voucher = pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 1)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _letterhead(engine, logo, r),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.4, color: _line),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Text('سند استلام مالي',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold, color: _titleRed, decoration: pw.TextDecoration.underline)),
        ),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          pw.Text('استلمت انا/', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 4),
          _field('', r?.receiverName ?? '', flex: 3),
          pw.SizedBox(width: 8),
          pw.Text('( بصفتي)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 4),
          _field('', r?.capacity ?? '', flex: 2),
        ]),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          _field('مبلغ مالي رقماً:(', figure(amount, cur), flex: 2),
          pw.Text(')', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 8),
          _field('كتابتاً(', words(amount, cur), flex: 5),
          pw.Text(')', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          _field('بتاريخ(', date, flex: 2),
          pw.Text(')', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 8),
          _field('وذلك مقابل', r?.purpose ?? '', flex: 5),
        ]),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          pw.Text('كاش', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 6),
          _box(r?.method == 'cash'),
          pw.SizedBox(width: 30),
          pw.Text('حوالة مالية', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 6),
          _box(r?.method == 'transfer'),
          pw.SizedBox(width: 8),
          _field('رقم (', r?.method == 'transfer' ? (r?.transferNo ?? '') : '', flex: 1),
          pw.Text(')', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 18),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _sigColumn('بيانات المسلم', r?.delivererName ?? ''),
          _sigColumn('بيانات المستلم', r?.receiverName ?? ''),
        ]),
      ]),
    );

    final pdf = pw.Document(theme: theme);
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      // سندٌ واحد في أعلى الصفحة؛ الباقي فارغ.
      build: (ctx) => pw.Align(alignment: pw.Alignment.topCenter, child: voucher),
    ));
    return pdf.save();
  }

  /// معاينة الطباعة ثم الأرشفة التلقائية إن مُكِّنت.
  static Future<void> print(AppDatabase db, LinkMoneyReceipt? receipt) async {
    final bytes = await build(db, receipt);
    final name = receipt == null ? 'سند استلام مالي (نموذج فارغ)' : 'سند استلام مالي — ${receipt.receiverName}';
    await MilitaryPrint.show(bytes, name: name);
    if (receipt == null) return;
    try {
      await ArchiveAuto(db).onDocumentPrinted(
        op: 'moneyReceipt',
        title: name,
        docDate: receipt.receiptDate,
        pdfBytes: bytes,
        fileName: '${name.replaceAll(' ', '-')}.pdf',
      );
    } catch (err, stack) {
      ErrorLogger.critical('archive.moneyReceipt', err, stack: stack, userMessage: 'طُبع السند لكن تعذّرت أرشفته تلقائيًّا');
    }
  }
}
