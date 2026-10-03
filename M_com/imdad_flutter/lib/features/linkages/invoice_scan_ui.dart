import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/ai/invoice_scan.dart';
import '../../data/repos/settings_repo.dart';

/// ملفٌ جاهز للمسح: اسمه وبايتاته.
typedef PickedInvoiceFile = ({String name, Uint8List bytes});

/// الكاميرا متاحة على الهاتف فقط؛ على ويندوز يُمسح الورق ببرنامج الماسح (أو الطابعة
/// متعددة الوظائف) ويُختار الملف الناتج.
bool get invoiceCameraAvailable => Platform.isAndroid || Platform.isIOS;

/// إعداد المسح: مفتاح الخدمة والنموذج. يعيد الإعدادات المحفوظة أو null عند الإلغاء.
Future<InvoiceAiSettings?> showInvoiceAiSettings(BuildContext context, SettingsRepo repo) async {
  final current = await InvoiceAiSettings.load(repo);
  if (!context.mounted) return null;
  final key = TextEditingController(text: current.apiKey);
  var model = InvoiceAiSettings.models.containsKey(current.model) ? current.model : InvoiceAiSettings.defaultModel;
  final saved = await showImdModal<InvoiceAiSettings>(
    context,
    title: 'إعداد مسح الفواتير',
    icon: 'scan',
    maxWidth: 560,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote(
            'المسح يرسل صورة الفاتورة (أو ملف PDF) عبر الإنترنت إلى خدمة Anthropic لقراءتها واستخراج بياناتها، '
            'ولا يُرسل شيء إلا حين تضغط «مسح فاتورة». لا تمسح مستنداتٍ سريةً لا يجوز خروجها من الجهة. '
            'المفتاح يُحفظ على هذا الجهاز وحده ولا يُزامَن مع الأجهزة الأخرى.'),
        ImdLabeled('مفتاح الخدمة (API key)', ImdFld(controller: key, obscure: true, hint: 'sk-ant-…')),
        ImdLabeled(
            'النموذج',
            ImdSelect<String>(
              items: [for (final e in InvoiceAiSettings.models.entries) (e.key, e.value)],
              value: model,
              onChanged: (v) => setLocal(() => model = v ?? InvoiceAiSettings.defaultModel),
            )),
      ]),
    ),
    actions: (ctx) => [
      ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
      ImdButton(
        label: 'حفظ',
        icon: 'save',
        onPressed: () => Navigator.of(ctx).pop(InvoiceAiSettings(apiKey: key.text.trim(), model: model)),
      ),
    ],
  );
  key.dispose();
  if (saved != null) await saved.save(repo);
  return saved;
}

enum InvoiceSource { camera, file, settings }

/// نافذة اختيار مصدر الفاتورة.
Future<InvoiceSource?> chooseInvoiceSource(BuildContext context) => showImdModal<InvoiceSource>(
      context,
      title: 'مسح فاتورة',
      icon: 'scan',
      maxWidth: 440,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote('تُسحب الأصناف والوحدات والكميات والأسعار ورقم الفاتورة وتاريخها والعملة واسم التاجر '
            'إلى أماكنها في العقد، وتبقى كلها قابلة للتعديل قبل الحفظ.'),
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
        const SizedBox(height: 12),
        ImdButton.outline(label: 'إعداد المسح (المفتاح والنموذج)', icon: 'settings', small: true, onPressed: () => Navigator.of(ctx).pop(InvoiceSource.settings)),
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
