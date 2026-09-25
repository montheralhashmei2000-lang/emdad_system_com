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
        await _leaveFullScreen();
        if (await windowManager.isMaximized()) await windowManager.unmaximize();
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        await windowManager.setMinimumSize(loginSize);
        await windowManager.setSize(loginSize);
        await windowManager.setResizable(false);
        await windowManager.setMaximizable(false);
        await windowManager.center();
      });

  /// النافذة الرئيسية: شريط العنوان ظاهر والنافذة مكبَّرة على الشاشة.
  ///
  /// **الترتيب هنا ليس اعتباطًا.** نافذة الدخول تُلغي `setResizable` و
  /// `setMaximizable`، وويندوز ينفّذ ذلك بنزع نمطَي النافذة `WS_THICKFRAME`
  /// و`WS_MAXIMIZEBOX`. وإعادةُ شريط العنوان قبل إعادتهما تُعيد الشريط بلا
  /// زرَّي التكبير والتصغير، والتكبيرُ بعدها لا يقع أصلًا لأن النافذة ما
  /// زالت غير قابلة للتكبير. فتُعاد الأنماط أولًا، ثم الشريط، ثم التكبير.
  static Future<void> main() => _guard(() async {
        await _leaveFullScreen();
        await windowManager.setResizable(true);
        await windowManager.setMaximizable(true);
        await windowManager.setMinimizable(true);
        // حد أدنى بمقاس هاتف: الواجهة متجاوبة حتى 360 بكسل.
        await windowManager.setMinimumSize(const Size(360, 600));
        await windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
          windowButtonVisibility: true,
        );
        await windowManager.maximize();

        // التحقق بعد التنفيذ: الاستدعاءات أعلاه لا تُرجع خطأً إن لم تقع،
        // فيبقى المستخدم أمام نافذة صغيرة بلا أزرار ولا يعرف لماذا. وإعادةُ
        // المحاولة مرةً بعد إفساح المجال لحلقة رسائل ويندوز تكفي عمليًّا.
        if (!await windowManager.isMaximized()) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await windowManager.setTitleBarStyle(
            TitleBarStyle.normal,
            windowButtonVisibility: true,
          );
          await windowManager.maximize();
        }
      });

  /// ويندوز يستعيد وضع النافذة السابق: إن تُركت في ملء الشاشة فُتحت كذلك،
  /// بلا شريط عنوان ولا أزرار. فكل وضع يبدأ بالخروج منه.
  static Future<void> _leaveFullScreen() async {
    if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
  }

  /// ما يجب إنهاؤه قبل إغلاق التطبيق — يسجّله `main()` عند الإقلاع.
  ///
  /// خادم المزامنة ومقبس الاكتشاف ومؤقّت المزامنة تبقى مفتوحةً بعد إغلاق
  /// النافذة، فتتأخّر نهاية العملية ثوانيَ يظنّها المستخدم تعليقًا. إنهاؤها
  /// أولًا يجعل الإغلاق فوريًّا.
  static Future<void> Function()? onBeforeExit;

  /// مهلة الإنهاء النظيف — بعدها يُغلق على أي حال.
  ///
  /// الإغلاق لا ينتظر شبكةً متعثّرة: مقبسٌ لا يُغلق ليس سببًا كافيًا لحبس
  /// المستخدم داخل التطبيق.
  static const Duration exitGrace = Duration(seconds: 2);

  /// إغلاق التطبيق: إنهاءٌ نظيف ثم هدم النافذة.
  static Future<void> exit() async {
    final hook = onBeforeExit;
    if (hook != null) {
      try {
        await hook().timeout(exitGrace);
      } catch (_) {}
    }
    if (!supported) return;
    try {
      await windowManager.destroy();
    } catch (_) {}
  }

  /// الإضافة غير مُهيّأة في الاختبارات وعلى غير ويندوز: لا يمنع ذلك الواجهة.
  static Future<void> _guard(Future<void> Function() f) async {
    if (!supported) return;
    try {
      await f();
    } catch (e) {
      // لا يُسقط الواجهة، لكنه لا يُكتَم أيضًا: عطلُ نافذةٍ صامتٌ يُشخَّص
      // بالتخمين ساعاتٍ، وسطرٌ في السجل يكفي.
      debugPrint('ImdWindow: تعذّر ضبط النافذة — $e');
    }
  }
}
