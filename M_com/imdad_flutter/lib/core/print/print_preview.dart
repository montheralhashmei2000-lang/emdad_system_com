import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../ui/imd_form.dart';
import '../ui/imd_tokens.dart';
import '../ui/imd_widgets.dart';

/// مفتاح التنقّل العام — تحتاجه المعاينة لأن الطباعة تُستدعى من طبقة الطباعة
/// التي لا تملك `BuildContext`، ولا داعي لتمرير السياق عبر كل نداء طباعة.
final GlobalKey<NavigatorState> imdNavigatorKey = GlobalKey<NavigatorState>();

/// معاينة المستند قبل إرساله إلى الطابعة.
///
/// كانت الطباعة تذهب مباشرة إلى حوار الطابعة، فلا يرى المستخدم ما سيُطبع إلا
/// بعد خروج الورق. الآن يُعرض المستند أولًا، ولا يُطبع إلا بضغط «طباعة».
///
/// إن تعذّر إيجاد سياق واجهة (طباعة من خلفية أو من اختبار) يُرسل المستند إلى
/// الطابعة مباشرة بدل أن تفشل العملية.
Future<void> showPrintPreview(Uint8List bytes, {required String name}) async {
  final context = imdNavigatorKey.currentContext;
  if (context == null) {
    await _sendToPrinter(bytes, name);
    return;
  }

  final confirmed = await showImdModal<bool>(
    context,
    title: 'معاينة الطباعة',
    icon: 'printer',
    maxWidth: 940,
    builder: (ctx) {
      // ارتفاع ثابت: جسم النافذة داخل `SingleChildScrollView` فلا حدّ عُلويًا له.
      final height = math.min(MediaQuery.sizeOf(ctx).height * .62, 620.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            name,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ctx.imd.muted),
          ),
        ),
        SizedBox(
          height: height,
          child: PdfPreview(
            build: (_) async => bytes,
            // شريط الأدوات الإنجليزي مستبدَل بأزرار النافذة العربية أسفلها.
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            loadingWidget: const ImdLd('جارٍ تجهيز المعاينة…'),
            pdfFileName: name,
          ),
        ),
      ]);
    },
    actions: (ctx) => [
      ImdButton.outline(label: 'إغلاق', icon: 'x', onPressed: () => Navigator.of(ctx).pop(false)),
      ImdButton(label: 'طباعة', icon: 'printer', onPressed: () => Navigator.of(ctx).pop(true)),
    ],
  );

  if (confirmed == true) await _sendToPrinter(bytes, name);
}

Future<void> _sendToPrinter(Uint8List bytes, String name) =>
    Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
