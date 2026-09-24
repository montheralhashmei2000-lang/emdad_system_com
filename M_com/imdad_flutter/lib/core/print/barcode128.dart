import 'package:flutter/material.dart';

/// باركود Code 128-B — نقل حرفي لـ `bcSvg()` في نسخة الويب (نفس الجداول ونفس المجموع الاختباري).
class Barcode128 {
  static const _p = [
    '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
    '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
    '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
    '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
    '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
    '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
    '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
    '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
    '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
    '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
    '114131', '311141', '411131', '211412', '211214', '211232',
  ];
  static const _stop = '2331112';

  /// عرض كل وحدة (شريط/فراغ بالتناوب) بدءًا بشريط.
  static List<int> modules(String text) {
    final vals = <int>[104];
    var sum = 104;
    for (var i = 0; i < text.length; i++) {
      final v = text.codeUnitAt(i) - 32;
      vals.add(v);
      sum += v * (i + 1);
    }
    vals.add(sum % 103);
    final bars = StringBuffer();
    for (final v in vals) {
      bars.write((v >= 0 && v < _p.length) ? _p[v] : _p[0]);
    }
    bars.write(_stop);
    return bars.toString().split('').map(int.parse).toList();
  }
}

/// رسم الباركود مثل SVG الويب: viewBox بعرض مجموع الوحدات × 74، أشرطة بارتفاع 60 والنص أسفلها.
class Barcode128View extends StatelessWidget {
  const Barcode128View(this.value, {super.key, this.width = 170, this.height = 70});

  final String value;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _BarcodePainter(value)),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.value);
  final String value;

  @override
  void paint(Canvas canvas, Size size) {
    final mods = Barcode128.modules(value);
    final total = mods.fold<int>(0, (a, b) => a + b).toDouble();
    // preserveAspectRatio الافتراضي (xMidYMid meet)
    final scale = (size.width / total) < (size.height / 74) ? size.width / total : size.height / 74;
    final dx = (size.width - total * scale) / 2;
    final dy = (size.height - 74 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, total, 74), Paint()..color = Colors.white);
    final black = Paint()..color = Colors.black;
    var x = 0.0;
    var bar = true;
    for (final w in mods) {
      if (bar && w > 0) canvas.drawRect(Rect.fromLTWH(x, 0, w.toDouble(), 60), black);
      x += w;
      bar = !bar;
    }
    final tp = TextPainter(
      text: TextSpan(text: value, style: const TextStyle(fontSize: 9, color: Colors.black, fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(total / 2 - tp.width / 2, 72 - tp.height + 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.value != value;
}
