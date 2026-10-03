import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../repos/settings_repo.dart';
import 'invoice_models.dart';
import 'ocr_words.dart';

/// محرك قراءة النص من صورة (OCR). **مجاني ويعمل دون إنترنت**: لا شيء يغادر الجهاز.
abstract class OcrEngine {
  /// كلمات الصورة بمواضعها (hOCR). الموضع ضروري لإعادة بناء صفوف الجداول.
  Future<List<OcrWord>> recognize(String imagePath);
}

/// أندرويد/iOS: Tesseract مضمَّن في التطبيق عبر `flutter_tesseract_ocr`، وبيانات
/// العربية والإنجليزية من `assets/tessdata`.
class MobileTesseractOcr implements OcrEngine {
  @override
  Future<List<OcrWord>> recognize(String imagePath) async {
    try {
      final hocr = await FlutterTesseractOcr.extractHocr(
        imagePath,
        language: 'ara+eng',
        args: {'psm': '4', 'preserve_interword_spaces': '1'},
      );
      return parseHocr(hocr);
    } catch (e) {
      throw InvoiceScanException('تعذّرت قراءة الصورة: $e');
    }
  }
}

/// ويندوز/لينكس/ماك: يستعمل برنامج Tesseract المجاني إن وُجد على الجهاز، ببيانات
/// العربية المضمَّنة في التطبيق (فلا حاجة لتنزيل لغات).
class DesktopTesseractOcr implements OcrEngine {
  DesktopTesseractOcr(this.executable);

  final String executable;

  /// مجلد بيانات اللغات: تُنسخ إليه الملفات المضمَّنة مرةً واحدة.
  static Future<String> tessdataDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'tessdata'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final cfg = jsonDecode(await rootBundle.loadString('assets/tessdata_config.json')) as Map<String, dynamic>;
    for (final f in (cfg['files'] as List).cast<String>()) {
      final target = File(p.join(dir.path, f));
      if (!await target.exists()) {
        final data = await rootBundle.load('assets/tessdata/$f');
        await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
    }
    return dir.path;
  }

  @override
  Future<List<OcrWord>> recognize(String imagePath) async {
    final data = await tessdataDir();
    final ProcessResult r;
    try {
      r = await Process.run(
        executable,
        [imagePath, 'stdout', '-l', 'ara+eng', '--psm', '4', '--tessdata-dir', data, '-c', 'preserve_interword_spaces=1', '-c', 'tessedit_create_hocr=1'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(minutes: 3));
    } on ProcessException {
      throw InvoiceScanException('تعذّر تشغيل Tesseract من: $executable');
    }
    if (r.exitCode != 0) {
      throw InvoiceScanException('فشل Tesseract (${r.exitCode}): ${'${r.stderr}'.trim()}');
    }
    return parseHocr('${r.stdout}');
  }

  /// مواضع التثبيت المعتادة على ويندوز (مثبّت UB-Mannheim الذي يضعه winget).
  static const _windowsPaths = [
    r'C:\Program Files\Tesseract-OCR\tesseract.exe',
    r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
  ];

  /// يبحث عن Tesseract: المسار المحفوظ في الإعدادات، فمتغير PATH، فالمواضع المعتادة.
  static Future<String?> locate({String saved = ''}) async {
    if (saved.isNotEmpty && await File(saved).exists()) return saved;
    final exe = Platform.isWindows ? 'tesseract.exe' : 'tesseract';
    for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final f = File(p.join(dir, exe));
      if (await f.exists()) return f.path;
    }
    for (final path in [
      if (Platform.isWindows) ..._windowsPaths,
      if (Platform.isMacOS) ...['/opt/homebrew/bin/tesseract', '/usr/local/bin/tesseract'],
      if (Platform.isLinux) '/usr/bin/tesseract',
    ]) {
      if (await File(path).exists()) return path;
    }
    return null;
  }
}

/// إعداد مسار Tesseract المحلي (لا يُزامَن): `SettingsRepo.localOnlyKeys['ocr']`.
class OcrSettings {
  static const String key = 'ocr';

  static Future<String> savedPath(SettingsRepo repo) async => '${(await repo.read(key))['tesseractPath'] ?? ''}';

  static Future<void> savePath(SettingsRepo repo, String path) => repo.write(key, {'tesseractPath': path});
}

/// المحرك المناسب للجهاز، أو `null` إن لم يتوفر (ويندوز بلا Tesseract مثبّت).
Future<OcrEngine?> createOcrEngine(SettingsRepo repo) async {
  if (Platform.isAndroid || Platform.isIOS) return MobileTesseractOcr();
  final exe = await DesktopTesseractOcr.locate(saved: await OcrSettings.savedPath(repo));
  return exe == null ? null : DesktopTesseractOcr(exe);
}
