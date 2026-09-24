import 'package:flutter/material.dart';

import '../ui/imd_fonts.dart';
import '../ui/imd_tokens.dart';

/// سمة التطبيق — نفس لوحة ألوان نسخة الويب (أخضر مؤسسي على خلفية محايدة فاتحة)
/// مع نسخة داكنة مطابقة لما اعتُمد في النظام الحالي.
class AppTheme {
  static const Color accent = Color(0xFF0F766E);
  static const Color accentHover = Color(0xFF115E59);
  static const Color bgLight = Color(0xFFF7F7F8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color lineLight = Color(0xFFE3E3E8);
  static const Color textLight = Color(0xFF202123);
  static const Color mutedLight = Color(0xFF5B5E6B);

  static const Color bgDark = Color(0xFF171717);
  static const Color surfaceDark = Color(0xFF212121);
  static const Color lineDark = Color(0xFF303036);
  static const Color textDark = Color(0xFFECECF1);
  static const Color accentDark = Color(0xFF2DD4BF);

  static ThemeData light({String font = ImdFonts.defaultFamily}) => _base(
        font: font,
        brightness: Brightness.light,
        primary: accent,
        background: bgLight,
        surface: surfaceLight,
        outline: lineLight,
        onSurface: textLight,
        muted: mutedLight,
      );

  static ThemeData dark({String font = ImdFonts.defaultFamily}) => _base(
        font: font,
        brightness: Brightness.dark,
        primary: accentDark,
        background: bgDark,
        surface: surfaceDark,
        outline: lineDark,
        onSurface: textDark,
        muted: const Color(0xFFA1A1AA),
      );

  static ThemeData _base({
    required String font,
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color outline,
    required Color onSurface,
    required Color muted,
  }) {
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
      extensions: [brightness == Brightness.dark ? ImdColors.dark : ImdColors.light],
      visualDensity: VisualDensity.standard,
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
          foregroundColor: brightness == Brightness.dark ? const Color(0xFF0B1F1C) : Colors.white,
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark ? const Color(0xFF171717) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
