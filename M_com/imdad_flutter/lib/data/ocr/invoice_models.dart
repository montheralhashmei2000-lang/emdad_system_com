/// صنفٌ مقروء من فاتورة — كما طُبع فيها (المسميات عند التجار قد تخالف مسميات النظام).
class ScannedItem {
  const ScannedItem({this.name = '', this.unit = '', this.qty = 0, this.unitPrice = 0, this.lineTotal = 0});

  final String name;
  final String unit;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  bool get isEmpty => name.trim().isEmpty && qty == 0 && unitPrice == 0 && lineTotal == 0;
}

/// فاتورة مقروءة. الحقل الذي لم يُعثر عليه يبقى فارغًا (نصًّا) أو صفرًا (رقمًا) —
/// لا يُخمَّن شيء لم يُقرأ.
class ScannedInvoice {
  const ScannedInvoice({
    this.merchant = '',
    this.invoiceNo = '',
    this.date = '',
    this.currency = '',
    this.exchangeRate = 0,
    this.printedTotal = 0,
    this.notes = '',
    this.items = const [],
  });

  final String merchant;
  final String invoiceNo;

  /// تاريخ الفاتورة `YYYY-MM-DD` أو فارغ.
  final String date;

  /// `sar` | `yer` | فارغ إن لم تذكر الفاتورة عملتها.
  final String currency;
  final double exchangeRate;

  /// الإجمالي المطبوع على الفاتورة (للمطابقة فقط؛ إجمالي العقد يُحسب من الأصناف).
  final double printedTotal;
  final String notes;
  final List<ScannedItem> items;
}

/// خطأ مسح بمعنًى يُعرض للمستخدم.
class InvoiceScanException implements Exception {
  InvoiceScanException(this.message);
  final String message;
  @override
  String toString() => message;
}
