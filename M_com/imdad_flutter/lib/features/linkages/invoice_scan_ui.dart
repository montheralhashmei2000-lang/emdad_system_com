import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ui/imd_widgets.dart';
import '../../data/ocr/ocr_engine.dart';
import '../../data/repos/settings_repo.dart';

/// ملفٌ جاهز للمسح: اسمه وبايتاته.
typedef PickedInvoiceFile = ({String name, Uint8List bytes});

/// الكاميرا متاحة على الهاتف فقط؛ على ويندوز يُمسح الورق ببرنامج الماسح (أو الطابعة
/// متعددة الوظائف) ويُختار الملف الناتج.
bool get invoiceCameraAvailable => Platform.isAndroid || Platform.isIOS;

/// حالة المسح على سطح المكتب: يحتاج برنامج Tesseract المجاني. يبيّن إن كان مثبّتًا،
/// وكيف يُثبَّت، ويتيح تحديد مساره يدويًّا. يعيد true إذا صار جاهزًا.
Future<bool> showOcrSetup(BuildContext context, SettingsRepo repo) async {
  var path = await DesktopTesseractOcr.locate(saved: await OcrSettings.savedPath(repo));
  if (!context.mounted) return false;
  final ok = await showImdModal<bool>(
    context,
    title: 'إعداد مسح الفواتير',
    icon: 'scan',
    maxWidth: 560,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote('المسح يعمل بالكامل على جهازك ودون إنترنت، ومجانًا: لا يُرسَل شيء إلى أي جهة.\n'
            'يحتاج برنامج Tesseract (مجاني ومفتوح المصدر) مثبّتًا على الحاسوب مرةً واحدة؛ بيانات اللغة العربية مضمَّنة في التطبيق.'),
        ImdChip(path == null ? 'Tesseract غير مثبّت' : 'جاهز: $path', tone: path == null ? ImdTone.err : ImdTone.ok, icon: path == null ? 'alert' : 'check-circle'),
        if (path == null) ...[
          const SizedBox(height: 10),
          const Text('للتثبيت على ويندوز: افتح «PowerShell» واكتب الأمر التالي ثم أعد فتح هذه النافذة:'),
          const SizedBox(height: 6),
          const SelectableText('winget install UB-Mannheim.TesseractOCR', style: TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 6),
          const Text('أو نزّل المثبّت من صفحة UB-Mannheim/tesseract على GitHub. وإن ثبّتّه في مكانٍ غير معتاد فاختر ملف tesseract.exe يدويًّا:'),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ImdButton.outline(
              label: 'إعادة الفحص',
              icon: 'refresh',
              small: true,
              onPressed: () async {
                final f = await DesktopTesseractOcr.locate(saved: await OcrSettings.savedPath(repo));
                setLocal(() => path = f);
              }),
          ImdButton.outline(
              label: 'اختيار tesseract يدويًّا',
              icon: 'folder',
              small: true,
              onPressed: () async {
                final r = await FilePicker.platform.pickFiles(type: FileType.any);
                final chosen = r?.files.firstOrNull?.path;
                if (chosen == null) return;
                await OcrSettings.savePath(repo, chosen);
                setLocal(() => path = chosen);
              }),
        ]),
      ]),
    ),
    actions: (ctx) => [ImdButton(label: 'تم', onPressed: () => Navigator.of(ctx).pop(path != null))],
  );
  return ok == true;
}

enum InvoiceSource { camera, file, settings }

/// نافذة اختيار مصدر الفاتورة.
Future<InvoiceSource?> chooseInvoiceSource(BuildContext context) => showImdModal<InvoiceSource>(
      context,
      title: 'مسح فاتورة',
      icon: 'scan',
      maxWidth: 440,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote('تُقرأ الفاتورة على جهازك دون إنترنت ومجانًا، وتُسحب الأصناف والوحدات والكميات والأسعار '
            'ورقم الفاتورة وتاريخها والعملة واسم التاجر إلى أماكنها في العقد، وتبقى كلها قابلة للتعديل قبل الحفظ.'),
        if (invoiceCameraAvailable) ...[
          ImdButton(label: 'تصوير بكاميرا الهاتف', icon: 'camera', onPressed: () => Navigator.of(ctx).pop(InvoiceSource.camera)),
          const SizedBox(height: 8),
        ],
        ImdButton(
            label: 'اختيار ملف ممسوح (صورة أو PDF)',
            icon: 'upload',
            onPressed: () => Navigator.of(ctx).pop(InvoiceSource.file)),
        const SizedBox(height: 8),
        const Text('ملف الماسح الضوئي: امسح الورقة ببرنامج الماسح أو الطابعة واحفظها صورةً أو PDF ثم اخترها هنا.',
            style: TextStyle(fontSize: 12)),
        if (!invoiceCameraAvailable) ...[
          const SizedBox(height: 12),
          ImdButton.outline(label: 'حالة المسح وتثبيت Tesseract', icon: 'settings', small: true, onPressed: () => Navigator.of(ctx).pop(InvoiceSource.settings)),
        ],
      ]),
    );

/// يلتقط صورة بالكاميرا، أو يختار ملفًّا/ملفاتٍ ممسوحة.
Future<List<PickedInvoiceFile>> pickInvoiceFiles(InvoiceSource source) async {
  if (source == InvoiceSource.camera) {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 88);
    if (x == null) return const [];
    return [(name: x.name, bytes: await x.readAsBytes())];
  }
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'],
    allowMultiple: true,
    withData: true,
  );
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.bytes != null) (name: f.name, bytes: f.bytes!),
  ];
}

/// نافذة تقدّم غير قابلة للإغلاق أثناء المسح. تُغلق بـ[Navigator.pop] من المستدعي.
void showScanProgress(BuildContext context, ValueNotifier<String> message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Flexible(
              child: ValueListenableBuilder<String>(
                valueListenable: message,
                builder: (_, m, __) => Text(m),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
