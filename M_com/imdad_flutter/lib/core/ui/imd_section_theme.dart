import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imd_density.dart';

/// هل يأخذ قسم المحروقات لوحةَ ألوانٍ مستقلّة عن الإمداد؟
///
/// كان القسم يُطبّق لوحةً برتقاليةً خاصّةً به ([ImdColors.fuelLight] /
/// [ImdColors.fuelDark]) بلا خيار، فيبدو التطبيق الواحد تطبيقَين: ألوانُ
/// الأزرار والروابط والشارات تتبدّل كلّها بتبديل القسم، ومن يعمل في القسمين
/// معًا يرى هويّتَين لا هويّة.
///
/// فالافتراض الآن **موحَّد**: المحروقات بأخضر الإمداد نفسه على وندوز وأندرويد،
/// ومن أراد تمييز القسم باللون أعاده من الإعدادات. واللوحة البرتقالية باقيةٌ
/// كما هي، لا تُحذف — التبديل خيارٌ لا هدم.
///
/// القيمة ساكنة كـ[ImdDensity] و[ImdStyle]: السمة تُبنى في `_themeFor` من
/// قراءةٍ ساكنة، وبعد التبديل تُعاد إدارة الشجرة كلها فتلتقطها.
class ImdSectionTheme {
  const ImdSectionTheme._();

  static const String _key = 'imdad.theme.fuelIdentity';

  /// يُستمع إليه لإظهار حالة المفتاح في الإعدادات.
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  /// `true` ⇒ المحروقات بلوحته البرتقالية؛ `false` (الافتراض) ⇒ لوحة الإمداد.
  static bool get distinctFuel => notifier.value;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key) ?? false;
      if (v != notifier.value) {
        notifier.value = v;
        ImdDensity.rebuildAll();
      }
    } catch (_) {
      // التفضيل كماليّ: تعذّر قراءته يُبقي اللوحة الموحَّدة.
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

  static Future<void> toggle() => set(!distinctFuel);
}
