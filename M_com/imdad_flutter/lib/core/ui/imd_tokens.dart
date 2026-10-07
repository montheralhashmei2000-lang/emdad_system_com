import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'imd_density.dart';
import 'imd_style.dart';

/// رموز ألوان النظام — المصدر الوحيد لكل لونٍ في الواجهة. تُقرأ من
/// `context.imd`، ولا يُكتب لونٌ صريح في شاشةٍ ولا في مكوّن.
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
    accent: Color(0xFF047857),
    accentHover: Color(0xFF065F46),
    accentSoft: Color(0xFFECFDF5),
    ring: Color(0x38047857),
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
    // (047857) بدل الأسود — يبقى النص الأبيض مقروءًا ويتّسق مع أزرار النظام.
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
    accent: Color(0xFF10B981),
    accentHover: Color(0xFF34D399),
    accentSoft: Color(0x2410B981),
    ring: Color(0x5210B981),
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

  /// لوحة قسم المحروقات — داكنة بلمسة زيتونية.
  ///
  /// القسم له هويّته البصرية: من يعمل فيه يعرف من أول نظرة أنه ليس في شاشات
  /// الإعاشة، فلا يكتب سند وقود في مكان سند إعاشة. والخضرة الباهتة (لا
  /// الفيروزي المؤسسي) تميّزه بلا أن تخرج عن لغة النظام.
  static const fuel = ImdColors(
    bg: Color(0xFF0E100D),
    surface: Color(0xFF151814),
    subtle: Color(0xFF1C201A),
    hover: Color(0xFF212519),
    line: Color(0xFF262B24),
    lineStrong: Color(0xFF343A31),
    text: Color(0xFFE9ECE5),
    text2: Color(0xFFD2D7CB),
    muted: Color(0xFF8C9386),
    faint: Color(0xFF6E7568),
    accent: Color(0xFFBFD8A4),
    accentHover: Color(0xFFD3E6BD),
    accentSoft: Color(0x22BFD8A4),
    ring: Color(0x55BFD8A4),
    onAccent: Color(0xFF13210C),
    success: Color(0xFF8FD694),
    successSoft: Color(0x248FD694),
    danger: Color(0xFFE5806A),
    dangerSoft: Color(0x26E5806A),
    warn: Color(0xFFE3B872),
    warnSoft: Color(0x26E3B872),
    info: Color(0xFF9DC7D8),
    infoSoft: Color(0x269DC7D8),
    side: Color(0xFF111410),
    side2: Color(0xFF0E110D),
    sideHover: Color(0xFF1D2119),
    sideActive: Color(0xFF242A20),
    sideText: Color(0xFFE9ECE5),
    sideMuted: Color(0xFF8C9386),
    sideBorder: Color(0xFF272C24),
    sideLine: Color(0xFF232821),
    tableHead: Color(0xFF191D17),
    tableRowLine: Color(0xFF232821),
    noteBg: Color(0x1AE3B872),
    noteBorder: Color(0x59E3B872),
    noteText: Color(0xFFE8C88A),
    isDark: true,
  );

  /// النمط الكلاسيكي (فاتح): خلفية رمادية `#F3F4F6` وحدود رمادية رفيعة، وألوانٌ
  /// دلالية بدرجات باهتة، وأخضر الإمداد `#047857` للتمييز. شريطه الجانبي كالفاتح.
  static const classicLight = ImdColors(
    bg: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    subtle: Color(0xFFE5E7EB),
    hover: Color(0xFFF3F4F6),
    line: Color(0xFFD1D5DB),
    lineStrong: Color(0xFF9CA3AF),
    text: Color(0xFF1F2937),
    text2: Color(0xFF374151),
    muted: Color(0xFF4B5563),
    faint: Color(0xFF6B7280),
    accent: Color(0xFF047857),
    accentHover: Color(0xFF065F46),
    accentSoft: Color(0xFFECFDF5),
    ring: Color(0x38047857),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
    successSoft: Color(0xFFD1FAE5),
    danger: Color(0xFFEF4444),
    dangerSoft: Color(0xFFFEE2E2),
    warn: Color(0xFFF59E0B),
    warnSoft: Color(0xFFFEF3C7),
    info: Color(0xFF3B82F6),
    infoSoft: Color(0xFFDBEAFE),
    side: Color(0xFF0B3D3A),
    side2: Color(0xFF104A46),
    sideHover: Color(0xFF155A55),
    sideActive: Color(0xFF1A6A63),
    sideText: Color(0xFFF0FDFA),
    sideMuted: Color(0xFF9CCFC7),
    sideBorder: Color(0xFF1F665F),
    sideLine: Color(0xFF17524D),
    tableHead: Color(0xFFE5E7EB),
    tableRowLine: Color(0xFFE5E7EB),
    noteBg: Color(0xFFFFFAEB),
    noteBorder: Color(0xFFFEDF89),
    noteText: Color(0xFF7A2E0E),
    isDark: false,
  );

  /// هوية قسم المحروقات (فاتح): برتقالي محروق مع شريط جانبي بنّي داكن — لوحةٌ
  /// مستقلةٌ عن أخضر الإمداد بنفس البنية، فمن يعمل فيه يعرف قسمه من أول نظرة.
  /// الألوان الدلالية (نجاح/خطر/تحذير) تبقى كما هي: معناها لا يتغيّر بالقسم.
  static const fuelLight = ImdColors(
    bg: Color(0xFFF7F6F4),
    surface: Color(0xFFFFFFFF),
    subtle: Color(0xFFEFEDEA),
    hover: Color(0xFFF4F2EF),
    line: Color(0xFFE6E2DC),
    lineStrong: Color(0xFFD4CEC5),
    text: Color(0xFF211D19),
    text2: Color(0xFF3A342E),
    muted: Color(0xFF625A51),
    faint: Color(0xFF948B80),
    accent: Color(0xFFC2410C),
    accentHover: Color(0xFF9A3412),
    accentSoft: Color(0xFFFFF1E8),
    ring: Color(0x38C2410C),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF067647),
    successSoft: Color(0xFFDCFAE6),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFEE4E2),
    warn: Color(0xFFB54708),
    warnSoft: Color(0xFFFEF0C7),
    info: Color(0xFF175CD3),
    infoSoft: Color(0xFFEFF4FF),
    side: Color(0xFF3B1D0E),
    side2: Color(0xFF4A2512),
    sideHover: Color(0xFF5C2F18),
    sideActive: Color(0xFF6E3A1E),
    sideText: Color(0xFFFFF4EC),
    sideMuted: Color(0xFFD9AE91),
    sideBorder: Color(0xFF6A3A20),
    sideLine: Color(0xFF522B16),
    tableHead: Color(0xFFFAF9F7),
    tableRowLine: Color(0xFFF0EDE8),
    noteBg: Color(0xFFFFFAEB),
    noteBorder: Color(0xFFFEDF89),
    noteText: Color(0xFF7A2E0E),
    isDark: false,
  );

  /// هوية قسم المحروقات (داكن): برتقالي دافئ على رمادي فحمي بحرارةٍ خفيفة.
  static const fuelDark = ImdColors(
    bg: Color(0xFF171513),
    surface: Color(0xFF211E1B),
    subtle: Color(0xFF2F2B27),
    hover: Color(0xFF2A2623),
    line: Color(0xFF34302B),
    lineStrong: Color(0xFF433E38),
    text: Color(0xFFEFEBE6),
    text2: Color(0xFFD8D2CB),
    muted: Color(0xFFA8A097),
    faint: Color(0xFF8E867C),
    accent: Color(0xFFFB923C),
    accentHover: Color(0xFFFDBA74),
    accentSoft: Color(0x24FB923C),
    ring: Color(0x52FB923C),
    onAccent: Color(0xFF2B1204),
    success: Color(0xFF4ADE80),
    successSoft: Color(0x244ADE80),
    danger: Color(0xFFF97066),
    dangerSoft: Color(0x26F97066),
    warn: Color(0xFFFDB022),
    warnSoft: Color(0x26FDB022),
    info: Color(0xFF84ADFF),
    infoSoft: Color(0x2684ADFF),
    side: Color(0xFF120F0C),
    side2: Color(0xFF1C1814),
    sideHover: Color(0xFF29231D),
    sideActive: Color(0xFF3A2F25),
    sideText: Color(0xFFEFEBE6),
    sideMuted: Color(0xFFA8A097),
    sideBorder: Color(0xFF332C25),
    sideLine: Color(0xFF2B251F),
    tableHead: Color(0xFF1C1A17),
    tableRowLine: Color(0xFF2B2824),
    noteBg: Color(0x1AFDB022),
    noteBorder: Color(0x59FDB022),
    noteText: Color(0xFFFEC84B),
    isDark: true,
  );

  /// شبكة الرسوم ونصوص محاورها في الوضع الفاتح (الداكن يشتقّها من `line`/`muted`).
  static const chartGridLight = Color(0xFFE7EEE9);
  static const chartTickLight = Color(0xFF66756C);

  @override
  ImdColors copyWith() => this;

  @override
  ImdColors lerp(ThemeExtension<ImdColors>? other, double t) =>
      (other is ImdColors && t >= .5) ? other : this;
}

/// ألوانٌ مشتقة تتبّع الوضع (فاتح/داكن) — تحفظ ما كان يُكتب صريحًا في الشاشات
/// (`c.isDark ? Color(0x…) : Color(0x…)`) فتبقى القيم الصريحة هنا وحدها.
///
/// تُقرأ كبقية الرموز من `context.imd`. إضافة لونٍ جديد تكون هنا لا في شاشة.
extension ImdColorsDerived on ImdColors {
  // ───── حالات المرور والتحديد
  /// خلفية رأس عمودٍ قابلٍ للفرز عند المرور.
  Color get headerHover => isDark ? const Color(0xFF26262A) : hover;

  /// خلفية صفّ/بطاقة عند المرور.
  Color get rowHover => isDark ? const Color(0xFF26262A) : tableHead;

  /// حدّ زرٍّ ثانويٍّ عند المرور.
  Color get lineHover => isDark ? const Color(0xFF52525B) : const Color(0xFFB9B9C6);

  /// خلفية زرٍّ هدّامٍ ناعمٍ عند المرور.
  Color get dangerHover => isDark ? const Color(0x40F97066) : const Color(0xFFFDD5D1);

  // ───── أسطحٌ معكوسة (داكنةٌ في الفاتح، رماديةٌ داكنةٌ في الداكن)
  Color get inverse => isDark ? const Color(0xFF303036) : text;
  Color get inverseLine => isDark ? const Color(0xFF3F3F46) : text;
  Color get onInverse => const Color(0xFFFFFFFF);
  Color get onInverseSoft => const Color(0x1AFFFFFF);
  Color get onInverseSoft2 => const Color(0x1FFFFFFF);
  Color get onInverseText => const Color(0xFFE4E4E7);
  Color get onInverseMuted => const Color(0xFF9DB3A6);

  /// نصٌّ فوق زرٍّ خلفيّته [text] نفسه (أبيض في الفاتح، داكنٌ في الداكن).
  Color get onText => isDark ? const Color(0xFF171717) : const Color(0xFFFFFFFF);

  /// أبيض ثابت للنص فوق شارةٍ ملوّنة (عدّاد التنبيهات).
  Color get onBadge => const Color(0xFFFFFFFF);

  // ───── حقولٌ ولوحات
  Color get fieldFill => isDark ? bg : const Color(0xFFEEF1EE);
  Color get panelFill => isDark ? bg : const Color(0xFFF7FAF8);
  Color get toolbarFill => isDark ? surface : const Color(0xFFF2F7F5);
  Color get toolbarLine => isDark ? line : const Color(0xFFDFE9E4);
  Color get popupLine => isDark ? const Color(0xFF2C3B35) : const Color(0xFFCFDCD6);

  /// بطاقة معلوماتٍ زرقاء (حدٌّ ونصّ).
  Color get infoLine => isDark ? const Color(0x5984ADFF) : const Color(0xFFB2CCFF);
  Color get infoStrong => isDark ? const Color(0xFFB2CCFF) : const Color(0xFF1849A9);

  // ───── ظلال وحجب
  Color get shadowXs => isDark ? const Color(0x66000000) : const Color(0x0A101828);
  Color get shadowSm => isDark ? const Color(0x80000000) : const Color(0x14101828);
  Color get shadowMd => isDark ? const Color(0x99000000) : const Color(0x26101828);
  Color get shadowHairline => const Color(0x1A101828);
  Color get shadowPopup => const Color(0x2E0F281E);
  Color get shadowBase => isDark ? const Color(0xFF000000) : const Color(0xFF101828);
  Color get scrim => const Color(0x73111111);

  // ───── الشريط العلوي والجانبي
  /// خلفية الشريط العلوي: شفّافةٌ أكثر مع Mica.
  Color topbar({required bool mica}) {
    if (isDark) return mica ? const Color(0x99171717) : const Color(0xEB171717);
    return mica ? const Color(0x99FFFFFF) : const Color(0xEBFFFFFF);
  }

  /// نصٌّ ناصعٌ على الشريط الجانبي (الشريط داكنٌ في كل السمات).
  Color get sideBright => const Color(0xFFFFFFFF);

  /// أسفل تدرّج الشريط الجانبي: أغمق من [side].
  Color get sideDeep => Color.lerp(side, const Color(0xFF000000), .22)!;

  /// نسخةٌ من السمة بلون تمييزٍ آخر (يُستعمل لتلوين زر حفظٍ بلونٍ مختلف).
  ImdColors withAccent({required Color accent, required Color accentHover, required Color onAccent}) =>
      ImdColors(
        bg: bg,
        surface: surface,
        subtle: subtle,
        hover: hover,
        line: line,
        lineStrong: lineStrong,
        text: text,
        text2: text2,
        muted: muted,
        faint: faint,
        accent: accent,
        accentHover: accentHover,
        accentSoft: accentSoft,
        ring: ring,
        onAccent: onAccent,
        success: success,
        successSoft: successSoft,
        danger: danger,
        dangerSoft: dangerSoft,
        warn: warn,
        warnSoft: warnSoft,
        info: info,
        infoSoft: infoSoft,
        side: side,
        side2: side2,
        sideHover: sideHover,
        sideActive: sideActive,
        sideText: sideText,
        sideMuted: sideMuted,
        sideBorder: sideBorder,
        sideLine: sideLine,
        tableHead: tableHead,
        tableRowLine: tableRowLine,
        noteBg: noteBg,
        noteBorder: noteBorder,
        noteText: noteText,
        isDark: isDark,
      );

  /// لون التمييز البرتقالي لأزرار الاستلام.
  ImdColors get orangeAccent => withAccent(
        accent: const Color(0xFFF39C12),
        accentHover: const Color(0xFFE08E0B),
        onAccent: const Color(0xFFFFFFFF),
      );
}

extension ImdThemeX on BuildContext {
  ImdColors get imd => Theme.of(this).extension<ImdColors>() ?? ImdColors.light;
}

/// مقاسات النظام الثابتة: نصف القطر، وعرض الشريط الجانبي، وارتفاع الشريط
/// العلوي، وحشوات المحتوى حسب العرض، وأهداف اللمس.
class ImdSizes {
  static double get radius => ImdStyle.classic ? 2 : 12; // --ui-radius
  static const double sideWidth = 290; // .side
  static const double topbarHeight = 59; // .topbar (الجوال)

  /// الشريط الواحد على سطح المكتب: عنوان النافذة والتبويبات والأدوات في صفٍّ واحد.
  static const double desktopBarHeight = 40;
  static const EdgeInsets mainPadding = EdgeInsets.symmetric(horizontal: 36, vertical: 28); // ≥1200px
  static const EdgeInsets mainPaddingMid = EdgeInsets.symmetric(horizontal: 28, vertical: 24); // 901–1199px
  // `ImdBp.tablet` اسمٌ بديل لـ`mobile` (≤900)، والمنطق يفحص `mobile` أولًا
  // (`imd_page_chrome.dart`)، فلا يبلغ فرع `tablet` أبدًا: هذه القيمة محفوظةٌ للتوافق.
  static const EdgeInsets mainPaddingTablet = EdgeInsets.symmetric(horizontal: 14, vertical: 16); // لا تُستعمل فعليًّا
  static const EdgeInsets mainPaddingMobile = EdgeInsets.symmetric(horizontal: 10, vertical: 12); // ≤900px
  static double get touchMin => ImdBp.touch ? 46 : 44; // --touch-min

  /// سقفٌ مريح لجدولٍ طويل يُمرَّر تحت رأسٍ ثابت ([ImdTable.maxHeight]).
  ///
  /// نسبةٌ من ارتفاع النافذة لا رقمٌ صلب: على شاشةٍ قصيرة لا يبتلع الجدول
  /// الصفحة كلّها، وعلى شاشةٍ طويلة لا يبقى قزمًا وحولَه فراغ. والحدّان
  /// يمنعان الطرفين: أقلُّ من ٣٢٠ لا يُظهر صفوفًا كافيةً ليستحقّ التمرير.
  static double tableMaxHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * .55).clamp(320, 640);

  // ─────────── النمط المدمج (High-Density)
  //
  // **جدول الأصناف ليس نموذج تسجيل.** النموذج يُملأ مرةً فتُفسحه، والجدول
  // يُملأ عشرين سطرًا فتضيق به الشاشة ويُدفع التمرير بين كل صنفين. فحقوله
  // أقصر وفواصله أضيق — بلا مساسٍ ببقية الشاشات.

  /// ارتفاع كل عناصر أشرطة الأعلى (تبويبات الصفحة وأزرار الإجراءات بجوارها) —
  /// واحدٌ للجميع فتقع على خطٍّ أفقيٍّ واحد في كل الشاشات.
  static double get barControl => ImdDensity.compactTargets ? 36 : touchMin;

  /// ارتفاع الحقل المدمج (بدل [touchMin]). الكثافة العالية تُنزله إلى 28 على
  /// سطح المكتب وحده — أهداف اللمس لا تُضيَّق.
  static double get compactField => ImdBp.touch ? 40 : (ImdDensity.isHigh ? 28 : 34);

  /// الفاصل الأفقي بين حقلين مترابطين في السطر (بين أعمدة جدول الإدخال) —
  /// أضيق من [ImdSizes.mainPadding] وأمثاله عمدًا: يمنع التحام حقلين
  /// متجاورين بصريًّا بلا إهدار عرضٍ على خمسة أعمدةٍ في سطرٍ واحد.
  static const double compactGap = 4;

  /// الفاصل الرأسي بين سطرَي صنف (عرض البطاقات على الجوال وحده — جدول
  /// سطح المكتب يفصل صفوفه بخطوط الشبكة لا بهذه الفجوة).
  static const double compactRowGap = 2;

  /// حشو الحقل المدمج رأسيًّا — موحَّدٌ على كل حقول الجدول ونموذج السند
  /// (الصنف والوحدة والكمية والملاحظة...)، فلا يبدو حقلٌ أقصر من أخيه.
  static const double compactPadV = 6;

  /// حشو الحقل المدمج أفقيًّا.
  static const double compactPadH = 8;

  /// نصف قطر زوايا الحقل المدمج (بدل [radius] العام).
  static double get compactRadius => ImdStyle.classic ? 2 : 6;
  static const String font = 'IBMPlexSansArabic';
}

/// نقاط التكيّف: ≥1200 واسع، 901–1199 متوسط (لا جوال ولا واسع)، ≤900 جوال، ≤420 جوال صغير.
///
/// 900 نقطة التحوّل الوحيدة بين نمط الجوال (Drawer/بطاقات) ونمط سطح المكتب.
class ImdBp {
  ImdBp(this.width);
  factory ImdBp.of(BuildContext context) => ImdBp(MediaQuery.sizeOf(context).width);

  static const double mobileMax = 900;

  final double width;
  bool get wide => width >= 1200;
  bool get mobile => width <= mobileMax;

  /// اسمٌ بديل لـ[mobile] للتوافق الرجعي: اللوحي والجوال نمطٌ واحد.
  bool get tablet => mobile;
  bool get tiny => width <= 420;

  /// `@media (hover:none) and (pointer:coarse)` ⇒ أهداف لمس 46.
  static bool get touch =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

/// مؤشر الفأرة على العناصر القابلة للنقر.
///
/// تطبيقات سطح المكتب الأصيلة (ويندوز) تُبقي السهم على الأزرار والصفوف وتحتفظ
/// بيد الإصبع للروابط وحدها؛ يد الإصبع على كل عنصر علامةُ صفحات الويب. فيبقى
/// السهم على سطح المكتب، ولا أثر للمؤشر على الجوال أصلًا.
class ImdCursor {
  const ImdCursor._();

  /// لعنصر قابل للنقر (زر، صف، بطاقة).
  static MouseCursor get click => SystemMouseCursors.basic;

  /// لرابط نصّي حقيقي وحده.
  static MouseCursor get link => SystemMouseCursors.click;
}

/// ظل البطاقات `--ui-shadow`.
List<BoxShadow> imdShadow(ImdColors c) => ImdStyle.classic
    ? const []
    : [
      BoxShadow(
        color: c.isDark ? const Color(0x66000000) : const Color(0x0D101828),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];

/// ظل القوائم المنسدلة والنوافذ الطافية فوق الصفحة — أعمق من [imdShadow]
/// لأن ما يحمله يطفو فوق المحتوى لا يستقر عليه، فيحتاج فصلًا بصريًّا أوضح.
List<BoxShadow> imdShadowOverlay(ImdColors c) => ImdStyle.classic
    ? const []
    : [
      BoxShadow(
        color: c.isDark ? const Color(0x8A000000) : const Color(0x24101828),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    ];

/// ألوانٌ **لا تتبع السمة عمدًا**: وظيفتها التباين الثابت، لا المظهر.
///
/// ورقُ الباركود وQR أبيضٌ ووحداتُهما سوداء في الفاتح والداكن معًا، وإلا فشلت
/// قراءتها بالماسح؛ وشاشة الكاميرا سوداء خلف الصورة الحيّة دائمًا. تُقرأ من هنا
/// لا من `Colors.*` حتى يبقى كل لونٍ في التطبيق معرَّفًا في ملف الرموز.
abstract final class ImdFixedColors {
  /// خلفية الباركود/QR وورق الطباعة.
  static const Color paper = Color(0xFFFFFFFF);

  /// وحدات الباركود/QR ونصها.
  static const Color ink = Color(0xFF000000);

  /// خلفية شاشة الماسح فوق الكاميرا.
  static const Color cameraBackdrop = ink;

  /// نصوص وأيقونات الماسح فوق الكاميرا.
  static const Color cameraForeground = paper;
}
