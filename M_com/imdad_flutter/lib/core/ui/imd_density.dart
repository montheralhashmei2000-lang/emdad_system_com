import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imd_style.dart';
import 'imd_tokens.dart';

/// وضع «الكثافة العالية»: صفوفٌ ومسافاتٌ أضيق ليتّسع الجدول لبياناتٍ أكثر.
///
/// **القيمة ساكنة لا سياقية** كـ[ImdBp.touch]: مقاسات [ImdSizes] دوالُّ قراءةٍ
/// ساكنة تُستدعى من مئات المواضع، فتحويلها كلها إلى `context` يكسر توقيعاتها.
/// وبعد التبديل تُعاد إدارة الشجرة كلها بـ[rebuildAll] فتلتقط القيمة الجديدة
/// وتبقى حالة الشاشات كما هي.
///
/// **لا يمسّ أهداف اللمس**: على الجوال (أندرويد) تبقى الحقول والأزرار بمقاسها
/// المريح للإصبع، والتضييق يقع على حشوات الجداول والصفحات وحدها.
class ImdDensity {
  const ImdDensity._();

  static const String _key = 'imdad.density.high';

  /// يُستمع إليه لإظهار حالة المفتاح (شريط الحالة).
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get isHigh => notifier.value;

  /// الكثافة العالية فعّالةٌ فعلًا: على اللمس لا تُضيَّق الأهداف.
  static bool get compactTargets => isHigh && !ImdBp.touch;

  /// حشوة خلية جسم الجدول رأسيًّا.
  static double get cellPadV => isHigh ? 4 : 9;

  /// حشوة خلية رأس الجدول رأسيًّا.
  static double get headPadV => isHigh ? 6 : 10;

  /// حجم خطّ خلايا الجسم.
  static double get cellFont => ImdStyle.classic ? 12 : (isHigh ? 12.5 : 13.5);

  /// الفاصل بين بطاقات الصفوف على الجوال.
  static double get cardGap => isHigh ? 6 : 10;

  /// عامل تصغير المسافات بين لوحات الصفحة (≤ 1).
  static double get spaceFactor => isHigh ? .6 : 1;

  /// يقرأ التفضيل المحفوظ — يُنادى مرةً عند إقلاع القشرة.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key) ?? false;
      if (v != notifier.value) {
        notifier.value = v;
        rebuildAll();
      }
    } catch (_) {
      // التفضيل كماليّ: تعذّر قراءته يُبقي الوضع المريح.
    }
  }

  /// يبدّل الوضع ويحفظه ويُعيد رسم الواجهة.
  static Future<void> set(bool high) async {
    if (notifier.value == high) return;
    notifier.value = high;
    rebuildAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, high);
    } catch (_) {
      // الحفظ كماليّ؛ الوضع يسري في الجلسة الحالية على أي حال.
    }
  }

  static Future<void> toggle() => set(!isHigh);

  /// يُعلِّم كل عناصر الشجرة للإعادة دون هدمها (الحالة محفوظة).
  ///
  /// هو ما يفعله الإطار نفسه عند تغيّر السمة أو اللغة. يُؤجَّل لما بعد الإطار
  /// الحالي لأنه قد يُنادى من داخل `build`/معالج نقر.
  static void rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = WidgetsBinding.instance.rootElement;
      if (root != null) mark(root);
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}
