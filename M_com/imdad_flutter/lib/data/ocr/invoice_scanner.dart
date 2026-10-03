import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import 'invoice_models.dart';
import 'invoice_text_parser.dart';
import 'ocr_engine.dart';
import 'ocr_words.dart';

/// يقرأ فاتورة (صورة أو PDF) بمحرك OCR محلي مجاني ثم يحلّل نصّها إلى حقولها.
/// **لا يُرسل شيء خارج الجهاز، ولا يحتاج إنترنت.**
class InvoiceScanner {
  InvoiceScanner(this.engine, {this.workDir});

  final OcrEngine engine;

  /// مجلد العمل المؤقت (للاختبار).
  final Directory? workDir;

  /// نوع الملف من بصمته: jpeg/png/webp/gif/pdf، أو null.
  static String? mediaTypeOf(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    if (b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return 'application/pdf';
    return null;
  }

  /// أكبر ضلع للصورة قبل القراءة: صور الهاتف الكبيرة تُبطئ OCR ولا تحسّنه؛
  /// والصور الصغيرة تُكبَّر إلى حد يقرؤه Tesseract جيدًا (نحو ٣٠٠ نقطة/بوصة).
  static const int _maxSide = 3000;
  static const int _minSide = 1800;

  /// يعيد الصورة بحجم مناسب للقراءة (PNG)، أو كما هي إن كانت مناسبة.
  static Future<Uint8List> fitForOcr(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    final longest = w > h ? w : h;
    if (longest <= _maxSide && longest >= _minSide) return bytes;
    final target = longest > _maxSide ? _maxSide : _minSide;
    final k = target / longest;
    final c2 = await ui.instantiateImageCodec(bytes, targetWidth: (w * k).round(), targetHeight: (h * k).round());
    final f2 = await c2.getNextFrame();
    final data = await f2.image.toByteData(format: ui.ImageByteFormat.png);
    f2.image.dispose();
    c2.dispose();
    if (data == null) throw InvoiceScanException('تعذّر تجهيز الصورة للقراءة');
    return data.buffer.asUint8List();
  }

  Future<List<OcrWord>> _readImage(Uint8List png, Directory dir, String name) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(png, flush: true);
    return engine.recognize(f.path);
  }

  /// أسطر الملف المقروءة (بعد إعادة بناء الصفوف بالمواضع). صفحات PDF تُقرأ بالترتيب.
  Future<List<String>> readLines(Uint8List bytes) async {
    final type = mediaTypeOf(bytes);
    if (type == null) throw InvoiceScanException('نوع الملف غير مدعوم — استعمل صورة (jpg/png/webp) أو PDF');
    final dir = await (workDir ?? Directory.systemTemp).createTemp('inv_scan_');
    try {
      if (type == 'application/pdf') {
        final lines = <String>[];
        var page = 0;
        // صفحات الـPDF تُحوَّل صورًا بدقة ٢٠٠ نقطة/بوصة ثم تُقرأ بالترتيب.
        await for (final r in Printing.raster(bytes, dpi: 200)) {
          page++;
          final png = await r.toPng();
          lines.addAll(wordsToLines(await _readImage(png, dir, 'page$page.png')));
        }
        if (page == 0) throw InvoiceScanException('ملف PDF بلا صفحات');
        return lines;
      }
      final png = await fitForOcr(bytes);
      return wordsToLines(await _readImage(png, dir, 'scan.png'));
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// يمسح ملفًا واحدًا ويعيد فاتورته (واحدة).
  Future<List<ScannedInvoice>> scan(Uint8List bytes) async {
    final lines = await readLines(bytes);
    if (lines.every((l) => l.trim().isEmpty)) throw InvoiceScanException('لم أقرأ أي نص في الصورة — جرّب صورة أوضح وأكثر إضاءة');
    return InvoiceTextParser.parse(lines.join('\n'));
  }
}

/// ملاحظة للمستخدم تُرافق كل مسح: القراءة الآلية تحتاج مراجعة.
const String kOcrReviewNote = 'القراءة آلية (OCR): الأرقام أدق من الحروف العربية — راجع كل صنف وسعر قبل الحفظ.';
