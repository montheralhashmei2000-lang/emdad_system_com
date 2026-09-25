import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// رموز الألوان والمقاسات — منقولة حرفيًا من متغيرات `ui-theme.css` في نسخة الويب
/// (الوضع الفاتح `:root` والداكن `[data-theme=dark]`).
@immutable
class ImdColors extends ThemeExtension<ImdColors> {
  const ImdColors({
    required this.bg,
    required this.surface,
    required this.subtle,
    required this.hover,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.text2,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.ring,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.info,
    required this.infoSoft,
    required this.side,
    required this.side2,
    required this.sideHover,
    required this.sideActive,
    required this.sideText,
    required this.sideMuted,
    required this.sideBorder,
    required this.sideLine,
    required this.tableHead,
    required this.tableRowLine,
    required this.noteBg,
    required this.noteBorder,
    required this.noteText,
    required this.isDark,
  });

  final Color bg, surface, subtle, hover, line, lineStrong;
  final Color text, text2, muted, faint;
  final Color accent, accentHover, accentSoft, ring, onAccent;
  final Color success, successSoft, danger, dangerSoft, warn, warnSoft, info, infoSoft;
  final Color side, side2, sideHover, sideActive, sideText, sideMuted, sideBorder, sideLine;
  final Color tableHead, tableRowLine;
  final Color noteBg, noteBorder, noteText;
  final bool isDark;

  static const light = ImdColors(
    bg: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    subtle: Color(0xFFECECF1),
    hover: Color(0xFFF2F2F5),
    line: Color(0xFFE3E3E8),
    lineStrong: Color(0xFFD1D1DB),
    text: Color(0xFF202123),
    text2: Color(0xFF343541),
    muted: Color(0xFF5B5E6B),
    faint: Color(0xFF8E8EA0),
    accent: Color(0xFF0F766E),
    accentHover: Color(0xFF115E59),
    accentSoft: Color(0xFFE6F4F2),
    ring: Color(0x380F766E),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF067647),
    successSoft: Color(0xFFDCFAE6),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFEE4E2),
    warn: Color(0xFFB54708),
    warnSoft: Color(0xFFFEF0C7),
    info: Color(0xFF175CD3),
    infoSoft: Color(0xFFEFF4FF),
    // الشريط الجانبي في السمة الفاتحة: أخضر مزرق داكن من عائلة لون التمييز
    // (0F766E) بدل الأسود — يبقى النص الأبيض مقروءًا ويتّسق مع أزرار النظام.
    side: Color(0xFF0B3D3A),
    side2: Color(0xFF104A46),
    sideHover: Color(0xFF155A55),
    sideActive: Color(0xFF1A6A63),
    sideText: Color(0xFFF0FDFA),
    sideMuted: Color(0xFF9CCFC7),
    sideBorder: Color(0xFF1F665F),
    sideLine: Color(0xFF17524D),
    tableHead: Color(0xFFFAFAFB),
    tableRowLine: Color(0xFFEFEFF3),
    noteBg: Color(0xFFFFFAEB),
    noteBorder: Color(0xFFFEDF89),
    noteText: Color(0xFF7A2E0E),
    isDark: false,
  );

  static const dark = ImdColors(
    bg: Color(0xFF171717),
    surface: Color(0xFF212121),
    subtle: Color(0xFF2F2F33),
    hover: Color(0xFF2A2A2E),
    line: Color(0xFF303036),
    lineStrong: Color(0xFF3F3F46),
    text: Color(0xFFECECF1),
    text2: Color(0xFFD4D4D8),
    muted: Color(0xFFA1A1AA),
    faint: Color(0xFF8B8B96),
    accent: Color(0xFF2DD4BF),
    accentHover: Color(0xFF5EEAD4),
    accentSoft: Color(0x242DD4BF),
    ring: Color(0x522DD4BF),
    onAccent: Color(0xFF0B1F1C),
    success: Color(0xFF4ADE80),
    successSoft: Color(0x244ADE80),
    danger: Color(0xFFF97066),
    dangerSoft: Color(0x26F97066),
    warn: Color(0xFFFDB022),
    warnSoft: Color(0x26FDB022),
    info: Color(0xFF84ADFF),
    infoSoft: Color(0x2684ADFF),
    side: Color(0xFF0F0F10),
    side2: Color(0xFF1A1A1C),
    sideHover: Color(0xFF26262A),
    sideActive: Color(0xFF303036),
    sideText: Color(0xFFECECF1),
    sideMuted: Color(0xFFA1A1AA),
    sideBorder: Color(0xFF2F3036),
    sideLine: Color(0xFF2A2B32),
    tableHead: Color(0xFF1C1C1F),
    tableRowLine: Color(0xFF2A2A2E),
    noteBg: Color(0x1AFDB022),
    noteBorder: Color(0x59FDB022),
    noteText: Color(0xFFFEC84B),
    isDark: true,
  );

  @override
  ImdColors copyWith() => this;

  @override
  ImdColors lerp(ThemeExtension<ImdColors>? other, double t) =>
      (other is ImdColors && t >= .5) ? other : this;
}

extension ImdThemeX on BuildContext {
  ImdColors get imd => Theme.of(this).extension<ImdColors>() ?? ImdColors.light;
}

/// المقاسات الثابتة في `ui-theme.css`.
class ImdSizes {
  static const double radius = 12; // --ui-radius
  static const double sideWidth = 290; // .side
  static const double topbarHeight = 59; // .topbar
  static const EdgeInsets mainPadding = EdgeInsets.symmetric(horizontal: 36, vertical: 28); // ≥1200px
  static const EdgeInsets mainPaddingMid = EdgeInsets.symmetric(horizontal: 28, vertical: 24);
  static const EdgeInsets mainPaddingTablet = EdgeInsets.symmetric(horizontal: 14, vertical: 16); // ≤920
  static const EdgeInsets mainPaddingMobile = EdgeInsets.symmetric(horizontal: 10, vertical: 12); // ≤680
  static double get touchMin => ImdBp.touch ? 46 : 44; // --touch-min
  static const String font = 'IBMPlexSansArabic';
}

/// نقاط التكيّف في CSS الويب: ≥1200 واسع، 921–1199 متوسط، ≤920 لوحي، ≤680 جوال، ≤420 جوال صغير.
class ImdBp {
  ImdBp(this.width);
  factory ImdBp.of(BuildContext context) => ImdBp(MediaQuery.sizeOf(context).width);

  final double width;
  bool get wide => width >= 1200;
  bool get tablet => width <= 920;
  bool get mobile => width <= 680;
  bool get tiny => width <= 420;

  /// `@media (hover:none) and (pointer:coarse)` ⇒ أهداف لمس 46.
  static bool get touch =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

/// ظل البطاقات `--ui-shadow`.
List<BoxShadow> imdShadow(ImdColors c) => [
      BoxShadow(
        color: c.isDark ? const Color(0x66000000) : const Color(0x0D101828),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
