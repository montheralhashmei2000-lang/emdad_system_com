import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/assets.dart';

/// بطاقة باركود الأصل: تُعرض وتُطبع وتُلصق عليه.
///
/// **لماذا باركود لا رمز QR:** الملصق يُلصق على جانب فرن أو خزان، ويُقرأ بماسح
/// USB خطّي كالذي في المستودعات — وهو لا يقرأ QR. والباركود الخطي يُقرأ من
/// مسافة أبعد على سطح منحنٍ.
Future<void> showAssetBarcodeSheet(BuildContext context, Asset asset) {
  final code = AssetRules.barcodeOf(id: asset.id, serialNumber: asset.serialNumber);
  return showImdModal<void>(
    context,
    title: 'باركود: ${asset.name}',
    icon: 'qr-code',
    maxWidth: 460,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ctx.imd.ring),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(
              asset.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AssetType.label(asset.assetType),
              style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 14),
            AssetBarcode(code: code),
            const SizedBox(height: 6),
            Text(
              code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                letterSpacing: 2,
                color: Color(0xFF111111),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        ImdNote(asset.serialNumber.isEmpty
            ? 'لا رقم تسلسلي لهذا الأصل، فالرمز مشتقّ من معرّفه ويبقى ثابتًا ما بقي. '
                'أدخل الرقم التسلسلي إن وُجد على لوحة الصنع ليُطبع بدله.'
            : 'الرمز هو الرقم التسلسلي نفسه المدوَّن على لوحة صنع الأصل.'),
      ],
    ),
    actions: (ctx) => [
      ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
      ImdButton(
        label: 'طباعة الملصق',
        icon: 'printer',
        onPressed: () => printAssetLabel(asset),
      ),
    ],
  );
}

/// رسم Code 128 على الشاشة.
class AssetBarcode extends StatelessWidget {
  const AssetBarcode({super.key, required this.code, this.width = 300, this.height = 74});

  final String code;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _Code128Painter(code)),
      );
}

class _Code128Painter extends CustomPainter {
  const _Code128Painter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    // الخلفية بيضاء دائمًا ولو كانت الواجهة داكنة: الماسح يقرأ التباين، وباركود
    // أبيض على أسود لا يُقرأ بأكثر الأجهزة.
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()..color = const Color(0xFF000000);
    try {
      for (final e in bc.Barcode.code128().make(code, width: size.width, height: size.height)) {
        if (e is bc.BarcodeBar && e.black) {
          canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
        }
      }
    } catch (_) {
      // رمز لا يقبله Code128 (محارف عربية مثلًا) — يبقى الإطار فارغًا والنص
      // أسفله مقروءًا، فلا تنهار الشاشة.
    }
  }

  @override
  bool shouldRepaint(covariant _Code128Painter old) => old.code != code;
}

/// ملصق بحجم بطاقة (٧×٤ سم) يُطبع ويُلصق على الأصل.
Future<void> printAssetLabel(Asset asset) async {
  final code = AssetRules.barcodeOf(id: asset.id, serialNumber: asset.serialNumber);
  // الخط من أصول التطبيق لا من الإنترنت: النظام يعمل في مواقع بلا شبكة،
  // و`PdfGoogleFonts` تُنزّل الخط عند أول طباعة فتفشل هناك بلا سبب ظاهر.
  final family = ImdPrintFonts.of(ImdPrintFonts.defaultFamily);
  final font = pw.Font.ttf(await rootBundle.load(family.regular));
  final bold = pw.Font.ttf(await rootBundle.load(family.bold));
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(7 * PdfPageFormat.cm, 4 * PdfPageFormat.cm,
          marginAll: 3 * PdfPageFormat.mm),
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      textDirection: pw.TextDirection.rtl,
      build: (context) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(asset.name,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(AssetType.label(asset.assetType),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: code,
            width: 5.4 * PdfPageFormat.cm,
            height: 1.4 * PdfPageFormat.cm,
            drawText: false,
          ),
          pw.SizedBox(height: 2),
          pw.Text(code, style: const pw.TextStyle(fontSize: 8, letterSpacing: 1.2)),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}
