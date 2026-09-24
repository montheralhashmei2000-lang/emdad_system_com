/// تنسيق الأرقام والتواريخ كما في نسخة الويب:
/// `nf = n => (n||0).toLocaleString('ar-EG')` ⇒ أرقام هندية، فاصل آلاف «٬»، فاصلة عشرية «٫»،
/// وثلاث خانات عشرية كحد أقصى.
library;

const _arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// يحوّل الأرقام اللاتينية داخل نص إلى أرقام هندية.
String arDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.write(_arDigits[r - 0x30]);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// `nf()` في الويب.
String nf(num? n) {
  final v = (n == null || (n is double && (n.isNaN || n.isInfinite))) ? 0 : n;
  final neg = v < 0;
  final abs = v.abs();
  // toLocaleString يقرّب إلى ثلاث خانات عشرية ويحذف الأصفار الزائدة.
  final fixed = abs.toStringAsFixed(3);
  final intPart = fixed.split('.')[0];
  final frac = fixed.split('.')[1].replaceFirst(RegExp(r'0+$'), '');
  final grouped = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write('٬');
    grouped.write(intPart[i]);
  }
  var out = grouped.toString();
  if (frac.isNotEmpty) out = '$out٫$frac';
  if (neg && out != '0') out = '؜-$out';
  return arDigits(out);
}

/// `toLocaleDateString('ar-EG')` ⇒ يوم/شهر/سنة بأرقام هندية.
String arDate(DateTime d) => arDigits('${d.day}/${d.month}/${d.year}');

/// صيغة التاريخ المخزَّنة في الويب (YYYY-MM-DD).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
