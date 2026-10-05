/// تنسيق الأرقام والتواريخ في النماذج المطبوعة المطابقة لملفات Excel/Word
/// المعتمدة — **بالأرقام اللاتينية** كما تظهر في تلك الملفات (`15/05/2026`
/// و`30,000.00`) لا الهندية التي تستعملها بقية شاشات النظام.
library;

import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _plain = NumberFormat('#,##0.##', 'en');

/// `2026-05-15` ⇒ `15-05-2026 م`؛ ما لا يُفهم يُعاد كما هو.
String printDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} م';
}

/// مبلغٌ بخانتين عشريتين: `30,000.00`.
String printMoney(num v) => _money.format(v);

/// رقمٌ بلا أصفار زائدة: `2200` و`12.5`.
String printNum(num v) => _plain.format(v);
