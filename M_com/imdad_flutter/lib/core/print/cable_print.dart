import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../data/repos/cable_repo.dart';
import '../ui/imd_format.dart';
import 'military_print.dart';
import 'voucher_print.dart';

/// طباعة نموذج «برقية صادرة/واردة» المعتمد.
///
/// الحقول المتغيرة (إلى، من، نسخة إلى، الموضوع، المرسَل إليهم، بيانات المركز)
/// تُملأ من إدخال المستخدم، وجسم البرقية نصٌّ حرّ يُكتب يدويًّا. أمّا الرقم
/// والتاريخ والساعة فتأتي من السجل نفسه.
class CablePrint {
  CablePrint._();

  static const _line = PdfColor.fromInt(0xFF222222);
  static const _label = PdfColor.fromInt(0xFFEDEDED);

  static String _date(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : arDate(dt);
  }

  /// يبني ملف PDF للبرقية بترويسة الجهة والشعار من إعدادات الهوية.
  static Future<Uint8List> build(AppDatabase db, Cable c) async {
    final engine = await VoucherPrint.engineOf(db);
    // شعار الهوية المحفوظ في الإعدادات، وإلا الشعار المضمَّن مع التطبيق.
    Uint8List? logo = engine.logoBytes;
    if (logo == null) {
      try {
        logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
      } catch (_) {}
    }
    final pdf = pw.Document(theme: await engine.pdfTheme());
    final recipients = CableRecipient.decode(c.recipientsJson);
    final out = c.direction == CableDirection.outgoing;
    final kindLabel = out ? 'برقية صادرة' : 'برقية واردة';
    final cls = CableClass.label(c.classification);
    final prio = CablePriority.label(c.priority);

    pw.Widget cell(String text,
            {bool bold = false, bool shaded = false, double size = 11, pw.TextAlign align = pw.TextAlign.right}) =>
        pw.Container(
          color: shaded ? _label : null,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(text.isEmpty ? ' ' : text,
              textAlign: align,
              style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    pw.TableRow row(List<pw.Widget> cells) => pw.TableRow(children: cells);

    // الجدول الأول: إلى/رقم — من/تاريخ — نسخة إلى (ثلاثة أسطر) مع ساعة/سرية/أسبقية.
    final info = pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.6),
      },
      children: [
        row([cell('إلى: ${c.toParty}', bold: true), cell('رقم البرقية', shaded: true, bold: true), cell(c.cableNo, bold: true)]),
        row([cell('من: ${c.fromParty}', bold: true), cell('تاريخها', shaded: true, bold: true), cell(_date(c.cableDate))]),
        row([
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            constraints: const pw.BoxConstraints(minHeight: 66),
            child: pw.Text('نسخة إلى:\n${c.ccParty}',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Container(
            color: _label,
            child: pw.Column(children: [
              cell('ساعة الإنشاء', bold: true),
              cell('درجة السرية', bold: true),
              cell('درجة الأسبقية', bold: true),
            ]),
          ),
          pw.Column(children: [cell(c.cableTime), cell(cls, bold: true), cell(prio, bold: true)]),
        ]),
      ],
    );

    final subject = pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text('م/ ${c.subject}', style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
    );

    final rec = recipients.isEmpty ? const [CableRecipient()] : recipients;
    final recTable = pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.8),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        row([cell('م', shaded: true, bold: true, align: pw.TextAlign.center), cell('الاسم', shaded: true, bold: true), cell('الوحدة', shaded: true, bold: true), cell('ملاحظة', shaded: true, bold: true)]),
        for (final (i, r) in rec.indexed)
          row([cell(nf(i + 1), align: pw.TextAlign.center), cell(r.name), cell(r.unit), cell(r.note)]),
      ],
    );

    final editor = [c.editorRank, c.editorName].where((e) => e.trim().isNotEmpty).join(' / ');
    final centerBox = pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          color: _label,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Center(
              child: pw.Text('لاستعمال المركز / المكتب', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.6),
          children: [
            row([cell('الإرسال', bold: true, shaded: true, align: pw.TextAlign.center), cell('الاستقبال', bold: true, shaded: true, align: pw.TextAlign.center)]),
            row([
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                cell('محرر البرقية / الرتبة: $editor', size: 10),
                cell('الوظيفة: ${c.editorJob}', size: 10),
                cell('تسلسل / نرس: ${c.serialNo}', size: 10),
                cell('الوقت والتاريخ: ${c.sendDateTime}', size: 10),
                cell('وسيلة الإرسال: ${c.sendMethod}', size: 10),
                cell('مختص: ${c.specialist}', size: 10),
                cell('التوقيع:', size: 10),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                cell('وقت الاستلام: ${c.receiveTime}', size: 10),
                cell('اسم المأمور: ${c.receiverName}', size: 10),
                cell('التوقيع:', size: 10),
              ]),
            ]),
          ],
        ),
      ]),
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 26),
      build: (ctx) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('درجة السرية: $cls', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('درجة الأسبقية: $prio', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Column(children: [
              if (logo != null) pw.SizedBox(width: 70, height: 70, child: pw.Image(pw.MemoryImage(logo))),
              pw.SizedBox(height: 4),
              pw.Text('$kindLabel برقم ${c.cableNo}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.Expanded(child: pw.SizedBox()),
        ]),
        pw.SizedBox(height: 10),
        info,
        pw.SizedBox(height: 6),
        subject,
        pw.SizedBox(height: 6),
        recTable,
        pw.SizedBox(height: 14),
        // جسم البرقية: نصٌّ حرّ يكتبه المستخدم بيده.
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text(c.body, style: const pw.TextStyle(fontSize: 12.5, lineSpacing: 5)),
        ),
        pw.SizedBox(height: 22),
        if (editor.isNotEmpty || c.editorJob.isNotEmpty)
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Column(children: [
              pw.Text(editor, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(c.editorJob, style: const pw.TextStyle(fontSize: 11)),
            ]),
          ),
        pw.SizedBox(height: 18),
        centerBox,
      ],
    ));
    return pdf.save();
  }

  /// يعرض معاينة الطباعة ثم يُؤرشف النسخة تلقائيًّا إن مُكِّنت الأرشفة للبرقيات.
  static Future<void> print(AppDatabase db, Cable c) async {
    final bytes = await build(db, c);
    await MilitaryPrint.show(bytes, name: 'برقية ${c.cableNo}');
    // فشل الأرشفة لا يمنع طباعةً تمّت، كبقية المطبوعات.
    try {
      await ArchiveAuto(db).onDocumentPrinted(
        op: 'cable',
        title: 'برقية ${c.cableNo} — ${c.subject}',
        docRef: c.cableNo,
        docDate: c.cableDate,
        pdfBytes: bytes,
        fileName: 'برقية-${c.cableNo}.pdf',
      );
    } catch (_) {}
  }
}
