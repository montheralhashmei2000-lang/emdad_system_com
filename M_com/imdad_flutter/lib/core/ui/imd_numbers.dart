import 'package:flutter/foundation.dart';

/// صورةُ الأرقام: هنديةٌ (٠١٢٣) أو لاتينية (0123).
enum ImdDigits {
  arabic('arabic', 'عربية (٠١٢٣٤٥٦٧٨٩)'),
  latin('latin', 'لاتينية (0123456789)');

  const ImdDigits(this.id, this.label);
  final String id;
  final String label;

  static ImdDigits of(Object? v) =>
      values.firstWhere((d) => d.id == v, orElse: () => arabic);
}

/// تفضيلات تنسيق الأرقام — تُحفظ في القاعدة فتُزامَن: صورةُ الرقم في المطبوعات
/// معيارٌ للجهة كلها لا تفضيلُ جهاز، فلا يصدر سندان بصيغتين.
@immutable
class ImdNumberPrefs {
  const ImdNumberPrefs({
    this.uiDigits = ImdDigits.arabic,
    this.printDigits = ImdDigits.latin,
    this.thousands = ',',
    this.decimal = '.',
    this.qtyDecimals = 3,
    this.moneyDecimals = 2,
  });

  /// أرقام الشاشات.
  final ImdDigits uiDigits;

  /// أرقام المطبوعات — لاتينيةٌ افتراضًا لتطابق ملفات Excel/Word المعتمدة.
  final ImdDigits printDigits;

  /// فاصل الآلاف: `,` أو `٬` أو مسافةٌ رفيعة أو لا شيء.
  final String thousands;

  /// الفاصل العشري: `.` أو `٫`.
  final String decimal;

  /// أقصى خاناتٍ عشرية للكميات — تُحذف أصفارُها الزائدة (٢٫٥٠٠ ⇒ ٢٫٥).
  final int qtyDecimals;

  /// خانات المبالغ — **ثابتةٌ لا تُقصّ**: ٣٠٠٠٠٫٠٠ لا ٣٠٠٠٠.
  final int moneyDecimals;

  /// خياراتُ الفواصل المعروضة في الإعدادات.
  static const thousandsOptions = <(String, String)>[
    (',', 'فاصلة  ١٢٣,٤٥٦'),
    ('٬', 'فاصلة عربية  ١٢٣٬٤٥٦'),
    (' ', 'مسافة  ١٢٣ ٤٥٦'),
    ('', 'بلا فاصل  ١٢٣٤٥٦'),
  ];

  static const decimalOptions = <(String, String)>[
    ('.', 'نقطة  ١٢٫٥ ⇠ 12.5'),
    ('٫', 'فاصلة عربية  ١٢٫٥'),
  ];

  ImdNumberPrefs copyWith({
    ImdDigits? uiDigits,
    ImdDigits? printDigits,
    String? thousands,
    String? decimal,
    int? qtyDecimals,
    int? moneyDecimals,
  }) =>
      ImdNumberPrefs(
        uiDigits: uiDigits ?? this.uiDigits,
        printDigits: printDigits ?? this.printDigits,
        thousands: thousands ?? this.thousands,
        decimal: decimal ?? this.decimal,
        qtyDecimals: qtyDecimals ?? this.qtyDecimals,
        moneyDecimals: moneyDecimals ?? this.moneyDecimals,
      );

  Map<String, dynamic> toMap() => {
        'uiDigits': uiDigits.id,
        'printDigits': printDigits.id,
        'thousands': thousands,
        'decimal': decimal,
        'qtyDecimals': qtyDecimals,
        'moneyDecimals': moneyDecimals,
      };

  /// يقرأ ما حُفظ، ويتجاهل أي قيمةٍ خارج المدى — صفٌّ تالفٌ لا يكسر كل رقمٍ
  /// في النظام، بل يعود بالافتراضات.
  factory ImdNumberPrefs.fromMap(Map<String, dynamic> m) {
    int clampInt(Object? v, int fallback) {
      final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      if (n == null || n < 0 || n > 3) return fallback;
      return n;
    }

    String pick(Object? v, List<(String, String)> options, String fallback) {
      final s = v is String ? v : null;
      if (s == null) return fallback;
      return options.any((o) => o.$1 == s) ? s : fallback;
    }

    const d = ImdNumberPrefs();
    return ImdNumberPrefs(
      uiDigits: ImdDigits.of(m['uiDigits']),
      printDigits: m['printDigits'] == null
          ? d.printDigits
          : ImdDigits.of(m['printDigits']),
      thousands: pick(m['thousands'], thousandsOptions, d.thousands),
      decimal: pick(m['decimal'], decimalOptions, d.decimal),
      qtyDecimals: clampInt(m['qtyDecimals'], d.qtyDecimals),
      moneyDecimals: clampInt(m['moneyDecimals'], d.moneyDecimals),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImdNumberPrefs &&
      other.uiDigits == uiDigits &&
      other.printDigits == printDigits &&
      other.thousands == thousands &&
      other.decimal == decimal &&
      other.qtyDecimals == qtyDecimals &&
      other.moneyDecimals == moneyDecimals;

  @override
  int get hashCode => Object.hash(
      uiDigits, printDigits, thousands, decimal, qtyDecimals, moneyDecimals);
}

/// مصدرُ تنسيق الأرقام الوحيد في النظام — الشاشات والمطبوعات والتصدير.
///
/// صورةُ الرقم كانت مُثبَّتةً في الشِّفرة في موضعين لا يعرف أحدهما الآخر:
/// `nf()` تكتب هنديًّا بفاصلةٍ ونقطة، و`printNum()/printMoney()` تكتبان
/// لاتينيًّا بـ`intl`. فمن أراد تغيير خانات المبالغ أو فاصل الآلاف لم يجد
/// مكانًا يغيّره منه. وهذه الحالة ساكنةٌ كـ`ImdDensity`: `nf()` دالّةٌ
/// عامّةٌ تُستدعى من ثمانمئة موضع، فلا سبيل إلى تمرير `context` إليها.
class ImdNumbers {
  const ImdNumbers._();

  /// مفتاح الصفّ في `app_settings` — يُزامَن مع بقية الإعدادات.
  static const String key = 'numbers';

  static final ValueNotifier<ImdNumberPrefs> notifier =
      ValueNotifier<ImdNumberPrefs>(const ImdNumberPrefs());

  static ImdNumberPrefs get current => notifier.value;

  /// يُستبدل التفضيل ويُعلَن للمستمعين. الحفظ في القاعدة مسؤولية المُنادي
  /// (`core/ui` لا يعرف طبقة البيانات).
  static void apply(ImdNumberPrefs p) {
    if (notifier.value != p) notifier.value = p;
  }

  static const _arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  /// يحوّل أرقام [s] إلى الصورة [d] — ويعيدها كما هي إن كانت لاتينية.
  static String toDigits(String s, ImdDigits d) {
    if (d == ImdDigits.latin) return s;
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x30 && r <= 0x39) {
        b.write(_arabic[r - 0x30]);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// صياغةُ رقمٍ بالفواصل والخانات المختارة.
  ///
  /// [money] يُثبّت الخانات العشرية ولا يقصّ أصفارها؛ وغيره يقصّها.
  /// [forPrint] يختار صورةَ أرقام المطبوعات بدل أرقام الشاشات.
  static String format(num? n, {bool money = false, bool forPrint = false}) {
    final p = current;
    final v = (n == null || (n is double && (n.isNaN || n.isInfinite))) ? 0 : n;
    final neg = v < 0;
    final abs = v.abs();
    final places = money ? p.moneyDecimals : p.qtyDecimals;
    final fixed = abs.toStringAsFixed(places);
    final dot = fixed.indexOf('.');
    final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
    var frac = dot < 0 ? '' : fixed.substring(dot + 1);
    // الكميات تُقصّ أصفارها الزائدة؛ والمبالغ تبقى بخاناتها كما تُدقَّق.
    if (!money) frac = frac.replaceFirst(RegExp(r'0+$'), '');

    final grouped = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write(p.thousands);
      grouped.write(intPart[i]);
    }
    var out = grouped.toString();
    if (frac.isNotEmpty) out = '$out${p.decimal}$frac';
    // علامةُ الاتجاه قبل السالب: وإلا قفزت الشرطة إلى آخر الرقم في سطرٍ عربي.
    if (neg && abs != 0) out = '؜-$out';
    return toDigits(out, forPrint ? p.printDigits : p.uiDigits);
  }
}
