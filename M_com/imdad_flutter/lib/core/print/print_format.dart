/// تنسيق الأرقام والتواريخ في النماذج المطبوعة.
///
/// الصورة تُقرأ من [ImdNumbers] («الأرقام والعملات» في الإعدادات): لاتينيةٌ
/// افتراضًا كما تظهر في ملفات Excel/Word المعتمدة (`15/05/2026` و`30,000.00`)،
/// لا الهندية التي تستعملها الشاشات — ومن أراد طباعتها هنديةً بدّل الإعداد.
///
/// كانت هنا `NumberFormat` بنمطٍ مثبَّت لا يعرف إعدادات النظام، فخاناتُ المبالغ
/// وفاصلُ الآلاف في المطبوعات لا تتبع ما يُختار للشاشات ولا يملك أحدٌ تغييرها.
library;

import '../ui/imd_numbers.dart';

/// `2026-05-15` ⇒ `15-05-2026 م`؛ ما لا يُفهم يُعاد كما هو.
String printDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final out =
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  return '${ImdNumbers.toDigits(out, ImdNumbers.current.printDigits)} م';
}

/// مبلغٌ بخاناته العشرية الثابتة: `30,000.00`.
String printMoney(num v) => ImdNumbers.format(v, money: true, forPrint: true);

/// رقمٌ بلا أصفار زائدة: `2200` و`12.5`.
String printNum(num v) => ImdNumbers.format(v, forPrint: true);
