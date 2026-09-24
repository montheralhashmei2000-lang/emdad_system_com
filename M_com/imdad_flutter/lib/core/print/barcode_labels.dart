import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'print_preview.dart';

import '../ui/imd_format.dart';
import '../ui/imd_tokens.dart';
import '../ui/imd_widgets.dart';
import 'barcode128.dart';

typedef BarcodeLabel = ({String name, String code, String barcode});

/// ورقة ملصقات الباركود — مقابل `#bcSheet` في الويب: شريط (طباعة، إغلاق، عدد الملصقات) ثم شبكة 3 أعمدة.
class BarcodeLabelsSheet extends StatelessWidget {
  const BarcodeLabelsSheet({super.key, required this.labels});

  final List<BarcodeLabel> labels;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F2),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  ImdButton(label: 'طباعة (حفظ PDF)', icon: 'printer', onPressed: () => printLabels(labels)),
                  ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(context).pop()),
                  ImdChip('${nf(labels.length)} ملصق', tone: ImdTone.code),
                ]),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: LayoutBuilder(builder: (context, cons) {
                    final w = (cons.maxWidth - 12) / 3;
                    return Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final l in labels) SizedBox(width: w, child: _Label(l)),
                    ]);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static pw.Font? _font;
  static pw.Font? _bold;

  static Future<Uint8List> buildPdf(List<BarcodeLabel> labels) async {
    _font ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: _font!, bold: _bold!));
    const cols = 3;
    final rows = <List<BarcodeLabel>>[];
    for (var i = 0; i < labels.length; i += cols) {
      rows.add(labels.sublist(i, (i + cols).clamp(0, labels.length)));
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.rtl,
      build: (_) => [
        for (final r in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) pw.SizedBox(width: 6),
                pw.Expanded(child: j < r.length ? _pdfLabel(r[j]) : pw.SizedBox()),
              ],
            ]),
          ),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _pdfLabel(BarcodeLabel l) {
    final mods = Barcode128.modules(l.barcode);
    final total = mods.fold<int>(0, (a, b) => a + b).toDouble();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFBBBBBB), style: pw.BorderStyle.dashed),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(children: [
        pw.Text(l.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        pw.Text('كود: ${l.code}', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF555555))),
        pw.SizedBox(
          width: 127,
          height: 52,
          child: pw.CustomPaint(
            size: const PdfPoint(127, 52),
            painter: (canvas, size) {
              final s = size.x / total;
              final barH = size.y * 60 / 74;
              var x = 0.0;
              var bar = true;
              canvas.setFillColor(PdfColors.black);
              for (final w in mods) {
                if (bar && w > 0) canvas.drawRect(x * s, size.y - barH, w * s, barH);
                x += w;
                bar = !bar;
              }
              canvas.fillPath();
            },
          ),
        ),
        pw.Text(l.barcode, style: const pw.TextStyle(fontSize: 7), textDirection: pw.TextDirection.ltr),
      ]),
    );
  }

  static Future<void> printLabels(List<BarcodeLabel> labels) async {
    final bytes = await buildPdf(labels);
    await showPrintPreview(bytes, name: 'ملصقات الباركود');
  }
}

/// `.lbl`
class _Label extends StatelessWidget {
  const _Label(this.l);
  final BarcodeLabel l;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFBBBBBB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Text(l.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, fontFamily: ImdSizes.font)),
        Text('كود: ${l.code}', style: const TextStyle(fontSize: 9, color: Color(0xFF555555))),
        Barcode128View(l.barcode),
      ]),
    );
  }
}
