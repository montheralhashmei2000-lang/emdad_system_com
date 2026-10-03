/// تفقيط المبالغ: «ألفان ومئتان ريال يمني فقط لا غير».
///
/// المعدود (ريال) مذكّر فتُستعمل الأعداد بصيغة المذكر. تدعم حتى المليارات،
/// والكسر يُكتب بوحدته الصغرى (هللة / فلس) إن وُجد.
library;

const _units = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', //
  'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر',
  'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = [
  '', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة',
];

/// عددٌ من 1 إلى 999 بالحروف.
String _below1000(int n) {
  final parts = <String>[];
  final h = n ~/ 100;
  final r = n % 100;
  if (h > 0) parts.add(_hundreds[h]);
  if (r > 0) {
    if (r < 20) {
      parts.add(_units[r]);
    } else {
      final u = r % 10;
      parts.add(u == 0 ? _tens[r ~/ 10] : '${_units[u]} و${_tens[r ~/ 10]}');
    }
  }
  return parts.join(' و');
}

/// (المفرد، المثنى، الجمع للـ3-10، التمييز لـ11 فما فوق)
const _scales = <(String, String, String, String)>[
  ('ألف', 'ألفان', 'آلاف', 'ألف'),
  ('مليون', 'مليونان', 'ملايين', 'مليون'),
  ('مليار', 'ملياران', 'مليارات', 'مليار'),
];

/// عددٌ صحيحٌ غير سالب بالحروف. الصفر ⇒ «صفر».
String arabicNumberWords(int n) {
  if (n == 0) return 'صفر';
  final groups = <int>[];
  var rest = n;
  while (rest > 0) {
    groups.add(rest % 1000);
    rest ~/= 1000;
  }
  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    final g = groups[i];
    if (g == 0) continue;
    if (i == 0) {
      parts.add(_below1000(g));
      continue;
    }
    final s = _scales[(i - 1).clamp(0, _scales.length - 1)];
    if (g == 1) {
      parts.add(s.$1);
    } else if (g == 2) {
      parts.add(s.$2);
    } else if (g <= 10) {
      parts.add('${_below1000(g)} ${s.$3}');
    } else {
      parts.add('${_below1000(g)} ${s.$4}');
    }
  }
  return parts.join(' و');
}

/// مبلغٌ مالي بالحروف: `amountInWords(2200, major: 'ريال يمني')` ⇒
/// «ألفان ومئتان ريال يمني فقط لا غير».
String amountInWords(double amount, {required String major, String minor = 'هللة'}) {
  final v = amount.abs();
  // التقريب إلى أقرب جزء من مئة قبل الفصل، فلا يظهر «تسعة وتسعون هللة وتسعمئة…».
  final total = (v * 100).round();
  final whole = total ~/ 100;
  final frac = total % 100;
  final b = StringBuffer(arabicNumberWords(whole))..write(' $major');
  if (frac > 0) b.write(' و${arabicNumberWords(frac)} $minor');
  b.write(' فقط لا غير');
  return b.toString();
}
