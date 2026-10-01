import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';

/// رمز QR يُمسح بكاميرا أي جهاز (ماسح التطبيق أو كاميرا الهاتف).
///
/// الخلفية بيضاء دائمًا وحولها هامشٌ هادئ (quiet zone) ولو كانت الواجهة داكنة:
/// الماسح يقرأ التباين، والـQR أبيض على أسود لا يُقرأ بأكثر الأجهزة، والهامشُ
/// من شرط المواصفة لا زينة.
class ImdQr extends StatelessWidget {
  const ImdQr(this.data, {super.key, this.size = 220});

  final String data;

  /// الضلع الخارجي بما فيه الهامش.
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'رمز QR',
        image: true,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _QrPainter(data)),
        ),
      );
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.data);

  final String data;

  /// الهامش الهادئ: وحدتان من وحدات الرمز على الأقل، وهنا نسبةٌ من الضلع.
  static const double _quiet = .06;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pad = size.shortestSide * _quiet;
    final side = size.shortestSide - pad * 2;
    final paint = Paint()..color = const Color(0xFF000000);
    try {
      final elements = bc.Barcode.qrCode(errorCorrectLevel: bc.BarcodeQRCorrectionLevel.medium)
          .make(data, width: side, height: side);
      for (final e in elements) {
        if (e is bc.BarcodeBar && e.black) {
          canvas.drawRect(Rect.fromLTWH(pad + e.left, pad + e.top, e.width, e.height), paint);
        }
      }
    } catch (_) {
      // نصٌّ أطول من سعة QR — يبقى الإطار الأبيض فارغًا والنص معروضٌ بجواره.
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.data != data;
}
