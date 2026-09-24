/// خطوط الواجهة المتاحة للاختيار من «بيانات الجهة والمظهر».
///
/// **معايير الاختيار** (نظام محاسبي لا موقع دعائي):
/// • أوزان ثابتة متعددة — لتتمايز العناوين عن الحقول عن المجاميع.
/// • أرقام متساوية العرض — فتتراصف خانات الجداول عموديًا.
/// • بلا زخرفة — الخط المزخرف يُتعب عين المحاسب ويتداخل مع خانات الإدخال.
///
/// خط `Amiri` غير مطروح هنا عمدًا لهذا السبب، ويبقى مستعمَلًا في **الطباعة**
/// وحدها حيث يُطلب الطابع الرسمي الكلاسيكي.
library;

/// خط واجهة واحد بوصفه المعروض للمستخدم.
class ImdFont {
  const ImdFont(this.family, this.label, this.note);

  /// اسم العائلة كما هو مسجَّل في `pubspec.yaml`.
  final String family;

  /// الاسم المعروض في الإعدادات.
  final String label;

  /// وصف مختصر يعين المستخدم على الاختيار.
  final String note;
}

class ImdFonts {
  const ImdFonts._();

  static const String defaultFamily = 'IBMPlexSansArabic';

  static const List<ImdFont> all = [
    ImdFont('IBMPlexSansArabic', 'IBM Plex Sans Arabic',
        'هندسي رسمي — مريح في الجداول الطويلة والتقارير المالية'),
    ImdFont('Tajawal', 'تجوال (Tajawal)',
        'مصمَّم للواجهات — أوضحها في الأحجام الصغيرة'),
    ImdFont('Cairo', 'القاهرة (Cairo)',
        'هندسي حديث بزوايا صريحة — شائع في أنظمة ERP العربية'),
    ImdFont('NotoSansArabic', 'Noto Sans Arabic',
        'دعم شامل للشاشات والدقات — يطبع جيدًا مباشرة'),
  ];

  /// يعيد اسم عائلة صالحًا: ما لم يكن معروفًا يسقط إلى الافتراضي، فلا تنكسر
  /// الواجهة بقيمة قديمة أو ملف بيانات من إصدار آخر.
  static String normalize(String? family) {
    if (family == null || family.isEmpty) return defaultFamily;
    for (final f in all) {
      if (f.family == family) return family;
    }
    return defaultFamily;
  }

  static ImdFont of(String family) =>
      all.firstWhere((f) => f.family == normalize(family));
}

/// خط طباعة واحد: عائلته وملفّاه (عادي وعريض) ووصفه.
class ImdPrintFont {
  const ImdPrintFont(this.family, this.label, this.note, this.regular, this.bold);

  final String family;
  final String label;
  final String note;

  /// مسارا الملفين داخل الأصول — الطباعة تحمّل الملف لا اسم العائلة.
  final String regular;
  final String bold;
}

/// خطوط **الطباعة** — منفصلة عن خطوط الواجهة لأن الورق غير الشاشة.
///
/// المطروح هنا ما نملك حقّ توزيعه فعلًا (رخصة OFL). خطوط مثل
/// Traditional Arabic و Simplified Arabic و Arial ملكية لمايكروسوفت وأدوبي،
/// وتضمينها في تطبيق يُوزَّع مخالفة ترخيص — فلا تُطرح مهما كانت مألوفة.
class ImdPrintFonts {
  const ImdPrintFonts._();

  static const String defaultFamily = 'Amiri';

  static const List<ImdPrintFont> all = [
    ImdPrintFont(
      'Amiri',
      'أميري (Amiri)',
      'طابع رسمي كلاسيكي — الأقرب إلى السندات الحكومية المطبوعة',
      'assets/fonts/Amiri-Regular.ttf',
      'assets/fonts/Amiri-Bold.ttf',
    ),
    ImdPrintFont(
      'IBMPlexSansArabic',
      'IBM Plex Sans Arabic',
      'واضح في الجداول الكثيفة — مناسب للتقارير والكشوف',
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
      'assets/fonts/IBMPlexSansArabic-Bold.ttf',
    ),
    ImdPrintFont(
      'Tajawal',
      'تجوال (Tajawal)',
      'حروف بسيطة بلا حواف معقّدة — الأنسب للطابعة الحرارية',
      'assets/fonts/Tajawal-Regular.ttf',
      'assets/fonts/Tajawal-Bold.ttf',
    ),
    ImdPrintFont(
      'Cairo',
      'القاهرة (Cairo)',
      'هندسي صريح — أرقام منتظمة في جداول الجرد',
      'assets/fonts/Cairo-Regular.ttf',
      'assets/fonts/Cairo-Bold.ttf',
    ),
    ImdPrintFont(
      'NotoSansArabic',
      'Noto Sans Arabic',
      'يطبع جيدًا على مختلف الطابعات والدقات',
      'assets/fonts/NotoSansArabic-Regular.ttf',
      'assets/fonts/NotoSansArabic-Bold.ttf',
    ),
  ];

  /// يعيد خطًا صالحًا دائمًا: المجهول يسقط إلى الافتراضي فلا تفشل الطباعة.
  static ImdPrintFont of(String? family) {
    for (final f in all) {
      if (f.family == family) return f;
    }
    return all.first;
  }

  static String normalize(String? family) => of(family).family;
}
