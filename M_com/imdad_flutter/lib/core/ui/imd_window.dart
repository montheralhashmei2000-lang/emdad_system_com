import 'dart:io' as io show exit;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show Window, WindowEffect;
import 'package:window_manager/window_manager.dart';
import '../../core/error_log.dart';

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

  static bool get supported => Platform.isWindows;

  /// `true` حين فُعّل تأثير Mica فعلًا — الشريطان العلوي والجانبي يخفّفان
  /// عتمتهما حينئذٍ ليظهر خلفهما، وتبقى بقية الواجهة معتمةً للقراءة.
  static final ValueNotifier<bool> micaActive = ValueNotifier(false);

  /// Mica لا يدعمه إلا ويندوز 11 (البناء 22000 فما فوق).
  static bool get _isWindows11 {
    final m = RegExp(r'Build (\d+)').firstMatch(Platform.operatingSystemVersion);
    return m != null && (int.tryParse(m.group(1)!) ?? 0) >= 22000;
  }

  /// يفعّل Mica خلف النافذة على ويندوز 11 وحده؛ غير ذلك لا يفعل شيئًا، وفشله
  /// لا يمسّ الواجهة (أسطحها معتمة أصلًا فتبدو كما كانت).
  static Future<void> syncMica(ThemeMode mode) async {
    if (!supported || !_isWindows11) return;
    try {
      if (!_micaReady) {
        await Window.initialize();
        _micaReady = true;
      }
      final dark = mode == ThemeMode.dark ||
          (mode == ThemeMode.system &&
              PlatformDispatcher.instance.platformBrightness == Brightness.dark);
      await Window.setEffect(effect: WindowEffect.mica, dark: dark);
      micaActive.value = true;
    } catch (e) {
      micaActive.value = false;
      debugPrint('ImdWindow: تعذّر تفعيل Mica — $e');
    }
  }

  static bool _micaReady = false;

  /// مقاس نافذة الدخول (منطقي).
  static const Size loginSize = Size(440, 460);

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

  /// النافذة الرئيسية: شريط العنوان الأصلي ظاهر (يدعم Snap وMica) والنافذة مكبَّرة.
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
  /// المستخدم داخل التطبيق. والمهلة قصيرة لأن ما يُنهى هنا (إغلاق منفذٍ
  /// ومسح جلسة) لا يستغرق أكثر من أجزاءٍ من الثانية في الحالة السليمة.
  static const Duration exitGrace = Duration(milliseconds: 800);

  /// مهلة هدم النافذة قبل الإنهاء القسري.
  static const Duration destroyGrace = Duration(milliseconds: 400);

  /// إغلاق التطبيق: إنهاءٌ نظيف ثم هدم النافذة ثم إنهاء العملية فورًا.
  ///
  /// بعد `destroy()` يبقى محرّك Flutter وخيط قاعدة البيانات يُفكّكان ثوانيَ يراها
  /// المستخدم تعليقًا بعد تأكيد الخروج؛ فتُنهى العملية صراحةً بعد أن أُغلق كل ما
  /// يلزم إغلاقه (المنافذ، والجلسة). أندرويد يتولّى إنهاءه النظام بعد
  /// `SystemNavigator.pop` لذا لا يُنهى هنا.
  /// إنهاء العملية. تُستبدل في الاختبارات وحدها: على ويندوز يقتل `io.exit`
  /// عملية الاختبار نفسها فتظهر الاختبارات اللاحقة «لا تكتمل».
  @visibleForTesting
  static void Function(int code) processExit = io.exit;

  static Future<void> exit() async {
    final hook = onBeforeExit;
    if (hook != null) {
      try {
        await hook().timeout(exitGrace);
      } catch (err, stack) {
        ErrorLogger.log('window.exitHook', err, stack);
      }
    }
    if (!supported) return;
    try {
      await windowManager.destroy().timeout(destroyGrace);
    } catch (_) {
      // متوقع: انتهت مهلة هدم النافذة أو رفضتها: تُنهى العملية بعدها صراحةً على أي حال.
    }
    processExit(0);
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
