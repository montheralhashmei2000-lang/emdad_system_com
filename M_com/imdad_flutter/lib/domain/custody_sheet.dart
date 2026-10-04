/// حسابات «مسير العهدة» — تطابق صيغ ملف Excel المعتمد:
///
/// * المنصرف بالسعودي = المنصرف باليمني ÷ سعر الصرف إن أُدخل اليمني، وإلا
///   فالمبلغ السعودي المكتوب (`=F13/410` في الملف).
/// * الإجماليات: العهدة، المنصرف، المرتجع، والمتبقي = العهدة − المنصرف − المرتجع
///   (المرتجع يُطرح من المتبقي بطلب المستخدم؛ ملف Excel الأصلي لا يطرحه).
/// * تكرار رقم الفاتورة يُلوَّن بالأحمر الفاتح في الإدخال والطباعة.
library;

/// سعر الصرف الافتراضي (ريال يمني مقابل ريال سعودي) كما في الملف.
const double kDefaultYerPerSar = 410;

/// سطر من مسير العهدة بمدخلاته الخام.
class CustodyRowValues {
  const CustodyRowValues({
    this.grantSar = 0,
    this.grantYer = 0,
    this.returnSar = 0,
    this.returnYer = 0,
    this.spentSar = 0,
    this.spentYer = 0,
    this.rate = kDefaultYerPerSar,
  });

  final double grantSar;

  /// مبلغ العهدة اليمني (للمسيرات بعهدة يمنية).
  final double grantYer;
  final double returnSar;
  final double returnYer;
  final double spentSar;
  final double spentYer;
  final double rate;

  static double _toSar(double sar, double yer, double rate) =>
      yer > 0 && rate > 0 ? yer / rate : sar;

  /// المنصرف الفعلي بالسعودي.
  double get spentInSar => _toSar(spentSar, spentYer, rate);

  /// المرتجع الفعلي بالسعودي.
  double get returnedInSar => _toSar(returnSar, returnYer, rate);

  static const String _yer = 'yer';

  /// مبلغ العهدة بعملة المسير [cur] (`sar` أو `yer`) — بلا تحويل: لكل عملةٍ عمودها.
  double grantIn(String cur) => cur == _yer ? grantYer : grantSar;

  /// المنصرف بعملة [cur]: ما أُدخل بها كما هو، وإلا حُوِّل بسعر السطر.
  /// سعرٌ غير صالح لا يُخمَّن فيه: يبقى ما أُدخل بعملةٍ أخرى خارج الحساب.
  double spentIn(String cur) => _in(cur, spentSar, spentYer);

  /// المرتجع بعملة [cur].
  double returnedIn(String cur) => _in(cur, returnSar, returnYer);

  double _in(String cur, double sar, double yer) {
    if (cur == _yer) {
      if (yer > 0) return yer;
      return rate > 0 ? sar * rate : 0;
    }
    return _toSar(sar, yer, rate);
  }
}

/// إجماليات المسير.
class CustodyTotals {
  const CustodyTotals({required this.granted, required this.spent, required this.returned});

  final double granted;
  final double spent;
  final double returned;

  /// المتبقي = العهدة − المنصرف − المرتجع.
  double get remaining => granted - spent - returned;
}

CustodyTotals custodyTotals(Iterable<CustodyRowValues> rows) {
  var g = 0.0, s = 0.0, r = 0.0;
  for (final x in rows) {
    g += x.grantSar;
    s += x.spentInSar;
    r += x.returnedInSar;
  }
  return CustodyTotals(granted: g, spent: s, returned: r);
}

/// تطبيع رقم الفاتورة للمقارنة: بلا فراغات طرفية، وبلا فرق حالة أحرف.
String normalizeInvoiceNo(String v) => v.trim().toLowerCase();

/// قيم رقم الفاتورة المكررة (الفارغ لا يُعدّ تكرارًا).
Set<String> duplicateInvoiceNos(Iterable<String> invoiceNos) {
  final seen = <String>{};
  final dup = <String>{};
  for (final raw in invoiceNos) {
    final v = normalizeInvoiceNo(raw);
    if (v.isEmpty) continue;
    if (!seen.add(v)) dup.add(v);
  }
  return dup;
}

/// إجماليات المسير بعملته [cur]: العهدة والمنصرف والمرتجع، والمتبقي = العهدة − المنصرف − المرتجع.
CustodyTotals custodyTotalsIn(Iterable<CustodyRowValues> rows, String cur) {
  var g = 0.0, s = 0.0, r = 0.0;
  for (final x in rows) {
    g += x.grantIn(cur);
    s += x.spentIn(cur);
    r += x.returnedIn(cur);
  }
  return CustodyTotals(granted: g, spent: s, returned: r);
}
