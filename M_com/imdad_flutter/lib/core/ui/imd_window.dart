import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// وضعا نافذة سطح المكتب (ويندوز فقط؛ على غيره لا يفعل شيئًا).
///
/// • **الدخول**: نافذة صغيرة بمقاس بطاقة الدخول وحدها، بلا شريط عنوان ولا
///   تكبير — لا تُعرض شاشة كاملة فارغة حول حقلين.
/// • **الرئيسية**: شريط العنوان بأزرار التصغير والتكبير والإغلاق، والنافذة مكبَّرة.
///
/// المقاسات هنا منطقية، وويندوز يضربها في نسبة التكبير (١٥٠٪ مثلًا). المقاس
/// الثابت القديم (1280×820) صار على شاشة 1080 بتكبير ١٥٠٪ أطول من الشاشة
/// (1230 بكسل)، فتوسّطت النافذة وخرج شريط عنوانها فوق حافة الشاشة — ولذلك
/// اختفت أزرار الإغلاق والتكبير. التكبير (maximize) يضمنها بأي مقاس وأي نسبة.
class ImdWindow {
  const ImdWindow._();

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// مقاس نافذة الدخول (منطقي).
  static const Size loginSize = Size(440, 530);

  /// نافذة الدخول المدمجة.
  static Future<void> login() => _guard(() async {
        if (await windowManager.isMaximized()) await windowManager.unmaximize();
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        await windowManager.setMinimumSize(loginSize);
        await windowManager.setSize(loginSize);
        await windowManager.setResizable(false);
        await windowManager.setMaximizable(false);
        await windowManager.center();
      });

  /// النافذة الرئيسية: شريط العنوان ظاهر والنافذة مكبَّرة على الشاشة.
  static Future<void> main() => _guard(() async {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.setMaximizable(true);
        // حد أدنى بمقاس هاتف: الواجهة متجاوبة حتى 360 بكسل.
        await windowManager.setMinimumSize(const Size(360, 600));
        await windowManager.maximize();
      });

  /// إغلاق التطبيق مباشرة (زر «خروج» في نافذة الدخول: لا شيء يضيع هناك).
  static Future<void> exit() => _guard(() => windowManager.destroy());

  /// الإضافة غير مُهيّأة في الاختبارات وعلى غير ويندوز: لا يمنع ذلك الواجهة.
  static Future<void> _guard(Future<void> Function() f) async {
    if (!supported) return;
    try {
      await f();
    } catch (_) {}
  }
}
