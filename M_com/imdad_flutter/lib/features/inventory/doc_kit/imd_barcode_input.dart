import 'package:flutter/material.dart';
import '../../../core/ui/imd_scan.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';


/// `input.fld.bcinput` + زر الكاميرا (يُضاف تحته كما يفعل forms-ux.js).
class ImdBarcodeInput extends StatefulWidget {
  const ImdBarcodeInput(
      {super.key, required this.hint, required this.onSubmit});
  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  State<ImdBarcodeInput> createState() => _ImdBarcodeInputState();
}


class _ImdBarcodeInputState extends State<ImdBarcodeInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String v) {
    final code = v.trim();
    if (code.isEmpty) return;
    _ctrl.clear();
    _focus.requestFocus();
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    OutlineInputBorder b(double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.accent, width: w),
        );
    // **الكاميرا داخل الحقل لا تحته.** زرٌّ في صندوقٍ مستقل يستقطع سطرًا
    // كاملًا من الشاشة ويباعد بين العين والحقل الذي تنتظره؛ وهي فعلٌ على
    // الحقل نفسه، فموضعها طرفه.
    return CustomPaint(
      foregroundPainter: _DashedRRect(c.accent, 8, 1.2),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        onSubmitted: _go,
        textInputAction: TextInputAction.done,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
            color: c.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: TextStyle(
              color: c.faint,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .8),
          filled: true,
          fillColor: c.accentSoft,
          contentPadding:
              const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
          border: b(0).copyWith(borderSide: BorderSide.none),
          enabledBorder: b(0).copyWith(borderSide: BorderSide.none),
          focusedBorder: b(1.4),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: ImdScanner.supported
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: ImdIconButton(
                    icon: 'camera',
                    tooltip: 'مسح بالكاميرا',
                    onPressed: () async {
                      final v = await ImdScanner.scan(context);
                      if (v != null) _go(v);
                    },
                  ),
                )
              : null,
        ),
      ),
    );
  }
}


class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color, [this.radius = 10, this.width = 1.5]);
  final double radius;
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius))
            .deflate(width / 2);
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRect old) => old.color != color;
}


/// صندوق بإطار متقطع (`border:1px dashed var(--line)`) — منطقة القوة في شاشة الصرف.
class ImdDashedBox extends StatelessWidget {
  const ImdDashedBox(
      {super.key,
      required this.child,
      this.color,
      this.radius = 10,
      this.padding = const EdgeInsets.all(10),
      this.background});
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsets padding;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return CustomPaint(
      foregroundPainter: _DashedRRect(color ?? c.line, radius, 1),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background ?? c.panelFill,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}
