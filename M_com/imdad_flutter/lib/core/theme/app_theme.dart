import 'package:flutter/material.dart';

import '../ui/imd_fonts.dart';
import '../ui/imd_tokens.dart';

/// انتقالٌ بتلاشٍ فقط بلا انزلاقٍ جانبي — أقرب لِما تعتاده تطبيقات سطح
/// المكتب الأصيلة من انزلاق الصفحات في متصفح الويب. يُستعمل لمنصّات سطح
/// المكتب وحدها؛ الجوّال يبقى على انتقاله الافتراضي المعتاد.
class _ImdFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _ImdFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

/// سمة التطبيق — أخضر مؤسسي على خلفية محايدة فاتحة،
/// ونسخةٌ داكنة مقابلة لها.
class AppTheme {
  // لا ألوان هنا: كل سمةٍ تُبنى من لوحتها في [ImdColors] — المصدر الوحيد.
  static ThemeData light({String font = ImdFonts.defaultFamily}) =>
      _base(font: font, brightness: Brightness.light, tokens: ImdColors.light);

  static ThemeData dark({String font = ImdFonts.defaultFamily}) =>
      _base(font: font, brightness: Brightness.dark, tokens: ImdColors.dark);

  /// سمة قسم المحروقات — داكنة بلمسة زيتونية، بلوحة [ImdColors.fuel].
  ///
  /// القسم منفصل فعلًا لا اسمًا: هويّته البصرية تُعرّف من يعمل فيه أنه ليس
  /// في شاشات الإعاشة قبل أن يقرأ عنوان الشاشة.
  static ThemeData fuel({String font = ImdFonts.defaultFamily}) =>
      _base(font: font, brightness: Brightness.dark, tokens: ImdColors.fuel);

  /// النمط الكلاسيكي الفاتح: لوحة [ImdColors.classicLight] وخط [font] (Tahoma).
  static ThemeData classic({String font = 'Tahoma'}) =>
      _base(font: font, brightness: Brightness.light, tokens: ImdColors.classicLight);

  /// قسم المحروقات بهويّته: برتقالي محروق، فاتحًا أو داكنًا بحسب [dark]. الحقول
  /// والجداول والقشرة هي نفسها — اللوحة وحدها تتبدّل.
  static ThemeData fuelSection({required bool dark, String font = ImdFonts.defaultFamily}) => _base(
        font: font,
        brightness: dark ? Brightness.dark : Brightness.light,
        tokens: dark ? ImdColors.fuelDark : ImdColors.fuelLight,
      );

  static ThemeData _base({
    required String font,
    required Brightness brightness,
    required ImdColors tokens,
  }) {
    final primary = tokens.accent;
    final background = tokens.bg;
    final surface = tokens.surface;
    final outline = tokens.line;
    final onSurface = tokens.text;
    final muted = tokens.muted;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      surface: surface,
      outline: outline,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: ImdFonts.normalize(font),
      extensions: [
        tokens,
      ],
      // كثافةٌ أعلى على سطح المكتب (مبنيّة على المنصّة كـ[ImdBp.touch] لا عرض
      // الشاشة): مكثّفة على وندوز/لينكس/ماك، وتبقى معتادة على الجوال بلا أي
      // أثر — تمامًا كيف تتكثّف تطبيقات سطح المكتب الأصيلة مقارنةً بالجوال.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // لا تموّج Material على سطح المكتب: التطبيقات الأصيلة تكتفي بتلوين الحالة
      // (hover/pressed). التموّج يبقى على اللمس حيث هو المعتاد.
      splashFactory: ImdBp.touch ? null : NoSplash.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: tokens.onAccent,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
      // تلاشٍ بلا انزلاقٍ على سطح المكتب وحده — الجوّال يبقى على انتقاله
      // الافتراضي المعتاد فلا يتغيّر سلوكه.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: _ImdFadePageTransitionsBuilder(),
        TargetPlatform.linux: _ImdFadePageTransitionsBuilder(),
        TargetPlatform.macOS: _ImdFadePageTransitionsBuilder(),
      }),
      // شريطٌ رفيع يتمدّد عند المرور أو السحب ويختفي حين لا تمرير — كأشرطة
      // ويندوز الأصيلة، لا شريطًا سميكًا ثابت الظهور كصفحات الويب. الجداول
      // العريضة تُظهر شريطها الأفقي صراحةً حيث يلزم التنبيه إلى أعمدة مخفية.
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        thickness: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged) ? 10.0 : 6.0),
        radius: const Radius.circular(5),
        // من onSurface لا لونين ثابتين: داكنٌ واضح على الفاتح وفاتحٌ واضح على
        // الداكن — بلا فرعين يدويين قد ينسيهما أحدٌ عند إضافة سمةٍ ثالثة.
        thumbColor: WidgetStateProperty.resolveWith((states) => onSurface.withValues(
            alpha: states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged) ? .55 : .35)),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: TextStyle(
          color: tokens.onText,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
