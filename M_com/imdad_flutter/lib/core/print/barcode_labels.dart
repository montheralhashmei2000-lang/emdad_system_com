import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'print_preview.dart';

import '../ui/imd_format.dart';
import '../ui/imd_tokens.dart';
import '../ui/imd_widgets.dart';
import 'barcode128.dart';

typedef BarcodeLabel = ({String name, String code, String barcode});

/// حجم ملصق الباركود بالمليمتر. **محلي لكل جهاز** (SharedPreferences): الطابعة
/// ولفّة الملصقات تخصّان الجهاز، فلا يُزامَن.
class LabelSize {
  const LabelSize(this.widthMm, this.heightMm);

  final double widthMm;
  final double heightMm;

  static const prefsKey = 'imdad.labelSize';
  static const defaults = LabelSize(35, 25);
  static const presets = [LabelSize(35, 25), LabelSize(50, 30), LabelSize(60, 40)];

  /// حدود «مخصص» المقبولة.
  static const double minMm = 15;
  static const double maxMm = 200;

  bool get isPreset => presets.contains(this);

  String get label => '${mm(widthMm)}×${mm(heightMm)} مم';
  static String mm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static bool valid(double w, double h) => w >= minMm && w <= maxMm && h >= minMm && h <= maxMm;

  static Future<LabelSize> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final parts = (prefs.getString(prefsKey) ?? '').split('x');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]), h = double.tryParse(parts[1]);
        if (w != null && h != null && valid(w, h)) return LabelSize(w, h);
      }
    } catch (_) {
      // تفضيل محلي تالف أو غير متاح ⇒ الافتراضي.
    }
    return defaults;
  }

  static Future<void> save(LabelSize s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, '${s.widthMm}x${s.heightMm}');
  }

  PdfPageFormat get pageFormat =>
      PdfPageFormat(widthMm * PdfPageFormat.mm, heightMm * PdfPageFormat.mm, marginAll: 1.5 * PdfPageFormat.mm);

  @override
  bool operator ==(Object other) => other is LabelSize && other.widthMm == widthMm && other.heightMm == heightMm;

  @override
  int get hashCode => Object.hash(widthMm, heightMm);
}

/// ورقة ملصقات الباركود: شريط (طباعة، إغلاق، عدد الملصقات) ثم معاينة بشبكة 3 أعمدة.
/// الطباعة نفسها صفحةٌ لكل ملصق بحجم [LabelSize] المحفوظ على الجهاز.
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

  /// صفحة PDF لكل ملصق بحجم [size] (طابعات لفّات الملصقات)، لا شبكة على A4.
  static Future<Uint8List> buildPdf(List<BarcodeLabel> labels, {LabelSize size = LabelSize.defaults}) async {
    _font ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: _font!, bold: _bold!));
    final format = size.pageFormat;
    for (final l in labels) {
      doc.addPage(pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => _pdfLabel(l, format.availableWidth, format.availableHeight),
      ));
    }
    return doc.save();
  }

  /// محتوى الملصق مقيسًا على مساحته: الاسم، الكود، الأشرطة، ثم أرقام الباركود.
  static pw.Widget _pdfLabel(BarcodeLabel l, double w, double h) {
    final mods = Barcode128.modules(l.barcode);
    final total = mods.fold<int>(0, (a, b) => a + b).toDouble();
    final fName = (h * 0.13).clamp(5.0, 11.0);
    final fCode = (h * 0.10).clamp(4.5, 9.0);
    final fDigits = (h * 0.10).clamp(4.5, 8.0);
    final barH = (h - (fName + fCode + fDigits) * 1.35).clamp(8.0, h);
    return pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      pw.Text(l.name,
          maxLines: 1,
          style: pw.TextStyle(fontSize: fName, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
      pw.Text('كود: ${l.code}', maxLines: 1, style: pw.TextStyle(fontSize: fCode, color: const PdfColor.fromInt(0xFF555555))),
      pw.SizedBox(
        width: w,
        height: barH,
        child: pw.CustomPaint(
          size: PdfPoint(w, barH),
          painter: (canvas, sz) {
            final s = sz.x / total;
            var x = 0.0;
            var bar = true;
            canvas.setFillColor(PdfColors.black);
            for (final m in mods) {
              if (bar && m > 0) canvas.drawRect(x * s, 0, m * s, sz.y);
              x += m;
              bar = !bar;
            }
            canvas.fillPath();
          },
        ),
      ),
      pw.Text(l.barcode, style: pw.TextStyle(fontSize: fDigits), textDirection: pw.TextDirection.ltr),
    ]);
  }

  static Future<void> printLabels(List<BarcodeLabel> labels) async {
    final bytes = await buildPdf(labels, size: await LabelSize.load());
    await showPrintPreview(bytes, name: 'ملصقات الباركود');
  }
}

/// ملصقٌ واحد في الورقة: الرمز الشريطي فوق نصّه.
class _Label extends StatelessWidget {
  const _Label(this.l);
  final BarcodeLabel l;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: ImdFixedColors.paper,
        border: Border.all(color: const Color(0xFFBBBBBB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Text(l.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: ImdFixedColors.ink, fontFamily: ImdSizes.font)),
        Text('كود: ${l.code}', style: const TextStyle(fontSize: 9, color: Color(0xFF555555))),
        Barcode128View(l.barcode),
      ]),
    );
  }
}
