import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'imd_format.dart';
import 'imd_tokens.dart';

// رسوم بيانية مرسومة يدويًا بمظهر Chart.js كما تظهر في نسخة الويب:
// خط الشبكة #e7eee9، لون النصوص #66756c، المحور الصادي يبدأ من الصفر، ووسيلة الإيضاح أسفل الرسم.

const _gridColor = Color(0xFFE7EEE9);
const _tickColor = Color(0xFF66756C);

class ImdSeries {
  const ImdSeries(this.label, this.values, this.color);
  final String label;
  final List<num> values;
  final Color color;
}

/// «خطوات» المحور كما يحسبها Chart.js تقريبًا (niceNum).
List<double> _niceTicks(double maxV, {int maxTicks = 11}) {
  if (maxV <= 0) return [for (var i = 0; i <= 10; i++) i / 10];
  double nice(double range, bool round) {
    final exp = (math.log(range) / math.ln10).floorToDouble();
    final f = range / math.pow(10, exp);
    double nf;
    if (round) {
      nf = f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10;
    } else {
      nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10;
    }
    return nf * math.pow(10, exp);
  }

  final step = math.max(1.0, nice(nice(maxV, false) / (maxTicks - 1), true));
  final top = (maxV / step).ceil() * step;
  return [for (var v = 0.0; v <= top + 1e-9; v += step) v];
}

/// Chart.js يعرض القيم بعدد خانات الخطوة: الصفر «0» والباقي «0.1 … 1.0» عند خطوة كسرية.
String _tickLabel(double v, List<double> ticks) {
  final fractional = ticks.length > 1 && (ticks[1] - ticks[0]) < 1;
  if (v == 0) return '0';
  return fractional ? v.toStringAsFixed(1) : v.toInt().toString();
}

TextPainter _tp(String s, {double size = 12, Color color = _tickColor}) => TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontFamily: null)),
      textDirection: TextDirection.ltr,
    )..layout();

/// مخطط خطي متعدد السلاسل مع تعبئة شفافة وانحناء 0.35.
class ImdLineChart extends StatelessWidget {
  const ImdLineChart({super.key, required this.labels, required this.series, this.height = 280});

  final List<String> labels;
  final List<ImdSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Expanded(child: CustomPaint(size: Size.infinite, painter: _LinePainter(labels, series))),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [
                for (final s in series)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 40,
                      height: 12,
                      decoration: BoxDecoration(
                        color: s.color.withValues(alpha: .125),
                        border: Border.all(color: s.color, width: 2.4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(s.label, style: const TextStyle(fontSize: 12, color: _tickColor)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.labels, this.series);
  final List<String> labels;
  final List<ImdSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = series.expand((s) => s.values).fold<num>(0, math.max).toDouble();
    final ticks = maxV <= 0 ? [for (var i = 0; i <= 10; i++) i / 10] : _niceTicks(maxV);
    final top = ticks.last;
    final yLabelW = ticks.map((t) => _tp(_tickLabel(t, ticks)).width).fold<double>(0, math.max) + 10;
    const bottomH = 22.0;
    final plot = Rect.fromLTRB(yLabelW, 6, size.width - 6, size.height - bottomH);
    final grid = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = plot.bottom - (t / top) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = _tp(_tickLabel(t, ticks));
      tp.paint(canvas, Offset(plot.left - tp.width - 8, y - tp.height / 2));
    }
    final n = labels.length;
    double xOf(int i) => n <= 1 ? plot.center.dx : plot.left + plot.width * i / (n - 1);
    // تسميات المحور السيني: 8 كحد أقصى (autoSkip).
    final skip = (n / 8).ceil().clamp(1, 1000);
    for (var i = 0; i < n; i += skip) {
      final tp = _tp(labels[i]);
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, plot.bottom + 6));
    }
    for (final s in series) {
      final pts = [
        for (var i = 0; i < n; i++) Offset(xOf(i), plot.bottom - ((i < s.values.length ? s.values[i] : 0) / top) * plot.height)
      ];
      if (pts.isEmpty) continue;
      final path = _smooth(pts, .35);
      final fill = Path.from(path)
        ..lineTo(pts.last.dx, plot.bottom)
        ..lineTo(pts.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: .125));
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
      for (final p in pts) {
        canvas.drawCircle(p, 2.5, Paint()..color = s.color.withValues(alpha: .125));
        canvas.drawCircle(
          p,
          2.5,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  /// منحنى بيزيه بتوتر مثل Chart.js (tension).
  Path _smooth(List<Offset> p, double t) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i > 0 ? p[i - 1] : p[i];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p2;
      final c1 = p1 + (p2 - p0) * (t / 2);
      final c2 = p2 - (p3 - p1) * (t / 2);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.labels != labels || old.series != series;
}

/// مخطط أعمدة أفقية (indexAxis: 'y') بزوايا 8 وسماكة 20.
class ImdHBarChart extends StatelessWidget {
  const ImdHBarChart({
    super.key,
    required this.labels,
    required this.values,
    this.color = const Color(0xFF0E6B3E),
    this.height = 280,
  });

  final List<String> labels;
  final List<num> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(size: Size.infinite, painter: _HBarPainter(labels, values, color)),
    );
  }
}

class _HBarPainter extends CustomPainter {
  _HBarPainter(this.labels, this.values, this.color);
  final List<String> labels;
  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.fold<num>(0, math.max).toDouble();
    final ticks = maxV <= 0 ? [for (var i = 0; i <= 5; i++) i / 5] : _niceTicks(maxV, maxTicks: 8);
    final top = ticks.last;
    // التسميات على يسار المحور (Chart.js يرسم الاتجاه LTR في اللوحة).
    final labelW = labels.map((l) => _tp(l).width).fold<double>(0, math.max) + 10;
    const bottomH = 22.0;
    final plot = Rect.fromLTRB(labelW, 6, size.width - 12, size.height - bottomH);
    final grid = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    for (final t in ticks) {
      final x = plot.left + (t / top) * plot.width;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final tp = _tp(_tickLabel(t, ticks));
      tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 6));
    }
    final n = labels.length;
    if (n == 0) return;
    final band = plot.height / n;
    for (var i = 0; i < n; i++) {
      final cy = plot.top + band * i + band / 2;
      final tp = _tp(labels[i]);
      tp.paint(canvas, Offset(plot.left - tp.width - 8, cy - tp.height / 2));
      final w = (values[i] / top) * plot.width;
      if (w <= 0) continue;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(plot.left, cy - 10, w, 20),
        topRight: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
        topLeft: const Radius.circular(8),
        bottomLeft: const Radius.circular(8),
      );
      canvas.drawRRect(r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _HBarPainter old) => old.labels != labels || old.values != values;
}

/// `.score-ring` — حلقة مؤشر بنسبة مئوية.
class ImdScoreRing extends StatelessWidget {
  const ImdScoreRing({super.key, required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return SizedBox(
      width: 112,
      height: 112,
      child: CustomPaint(
        painter: _RingPainter(percent / 100, c.accent, c.subtle),
        child: Center(
          child: Container(
            width: 78,
            height: 78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Text('${nf(percent)}%',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c.text, height: 1.2)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.on, this.off);
  final double p;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(rect, Paint()..color = off);
    // conic-gradient يبدأ من الأعلى باتجاه عقارب الساعة.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * p.clamp(0, 1), true, Paint()..color = on);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p || old.on != on;
}
