import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imd_density.dart';

/// النمط «الكلاسيكي» الاختياري: مسطّحٌ بلا ظلال وزواياه 2 وخطه أصغر وحدوده
/// رمادية رفيعة — على طريقة أنظمة سطح المكتب التقليدية (DevExpress).
///
/// **اختياريٌّ وفوق السمة لا بديلٌ عنها**: الفاتح والداكن والمحروقات تبقى كما هي
/// وهذا النمط يعدّل الشكل (زوايا/ظلال/خط/خلفية) فوقها. والقيمة ساكنة كـ[ImdDensity]
/// لأن [ImdSizes] دوالُّ قراءةٍ ساكنة؛ وبعد التبديل تُعاد إدارة الشجرة كلها
/// فتلتقطها وتبقى حالة الشاشات.
class ImdStyle {
  const ImdStyle._();

  static const String _key = 'imdad.style.classic';

  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get classic => notifier.value;

  /// عائلة الخط في النمط الكلاسيكي — خطوط النظام تُسقط تلقائيًّا إلى ما يتوفّر.
  static const String classicFont = 'Tahoma';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key) ?? false;
      if (v != notifier.value) {
        notifier.value = v;
        ImdDensity.rebuildAll();
      }
    } catch (_) {
      // التفضيل كماليّ: تعذّر قراءته يُبقي النمط الحديث.
    }
  }

  static Future<void> set(bool on) async {
    if (notifier.value == on) return;
    notifier.value = on;
    ImdDensity.rebuildAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {
      // يسري في الجلسة الحالية على أي حال.
    }
  }

  static Future<void> toggle() => set(!classic);
}
