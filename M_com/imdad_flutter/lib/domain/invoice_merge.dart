import '../data/ocr/invoice_models.dart';
import '../data/repos/linkage_repo.dart';

/// ناتج دمج فواتير مسحوبة في عقد شراء قيد التحرير.
class ContractScanMerge {
  ContractScanMerge({
    required this.items,
    required this.supplier,
    required this.listDate,
    required this.currency,
    required this.exchangeRate,
    required this.warnings,
    required this.currencyConflict,
  });

  /// الأصناف الجديدة المضافة بعد الأصناف الحالية.
  final List<ContractItem> items;

  /// القيم الناتجة للرأس (تساوي الحالية إن لم تتغير).
  final String supplier;
  final String listDate;
  final String currency;
  final double exchangeRate;

  /// ما يستحق انتباه المستخدم قبل الاعتماد.
  final List<String> warnings;

  /// عملة الفاتورة تخالف عملة عقدٍ فيه أصناف — لا تحويل تلقائي بين العملتين.
  final bool currencyConflict;
}

/// يوزّع بيانات الفواتير المسحوبة على أماكنها من العقد:
/// * كل صنف ← سطر أصناف يحمل رقم فاتورته وتاريخها (لكل فاتورة تاريخها).
/// * التاجر والتاريخ العلوي والعملة وسعر الصرف ← تُملأ **إن كانت فارغة** فقط ولا
///   تُكتب فوق ما أدخله المستخدم.
/// * الإجمالي النهائي لا يُمسّ: يبقى مجموع إجماليات الأصناف تلقائيًّا.
///
/// ما لا يتسق (كمية × سعر ≠ إجمالي، أو إجمالي مطبوع ≠ مجموع الأصناف، أو عملة
/// مختلفة) يُرفع تحذيرًا ولا يُصحَّح بصمت.
ContractScanMerge mergeScansIntoContract({
  required String supplier,
  required String listDate,
  required String currency,
  required double exchangeRate,
  required bool hasExistingItems,
  required List<ScannedInvoice> invoices,
}) {
  final warnings = <String>[];
  final items = <ContractItem>[];
  var newSupplier = supplier;
  var newDate = listDate;
  var newCurrency = currency;
  var newRate = exchangeRate;
  var conflict = false;

  final currencies = {for (final i in invoices) if (i.currency.isNotEmpty) i.currency};
  if (currencies.length > 1) {
    warnings.add('الفواتير بعملتين مختلفتين (سعودي ويمني) — أدخل كل عملة في عقد مستقل');
  } else if (currencies.length == 1) {
    final c = currencies.first;
    if (c != currency) {
      if (hasExistingItems) {
        conflict = true;
        warnings.add('عملة الفاتورة (${LinkCurrency.label(c)}) تخالف عملة العقد (${LinkCurrency.label(currency)}) ولا يوجد تحويل تلقائي');
      } else {
        newCurrency = c;
      }
    }
  }

  for (final inv in invoices) {
    if (newSupplier.trim().isEmpty && inv.merchant.isNotEmpty) newSupplier = inv.merchant;
    if (supplier.trim().isNotEmpty && inv.merchant.isNotEmpty && inv.merchant != supplier.trim()) {
      warnings.add('اسم التاجر في الفاتورة «${inv.merchant}» يخالف المُدخل «${supplier.trim()}»');
    }
    if (newDate.isEmpty && inv.date.isNotEmpty) newDate = inv.date;
    if (newCurrency == LinkCurrency.yer && newRate <= 0 && inv.exchangeRate > 0) newRate = inv.exchangeRate;

    var sum = 0.0;
    for (final it in inv.items) {
      var price = it.unitPrice;
      var total = it.lineTotal;
      // سعر الوحدة الغائب يُشتق من الإجمالي والكمية؛ والإجمالي الغائب من الكمية × السعر.
      if (price == 0 && total > 0 && it.qty > 0) price = total / it.qty;
      if (total == 0 && price > 0) total = ContractItem.autoTotal(it.qty, price);
      final expected = ContractItem.autoTotal(it.qty, price);
      if (it.lineTotal > 0 && it.unitPrice > 0 && (expected - total).abs() > 0.01 * (total < 1 ? 1 : total)) {
        warnings.add('«${it.name}»: الكمية × السعر (${_n(expected)}) لا تساوي الإجمالي (${_n(total)}) — راجع السطر');
      }
      sum += total;
      items.add(ContractItem(
        name: it.name,
        unit: it.unit,
        qty: it.qty,
        price: price,
        total: total,
        invoiceNo: inv.invoiceNo,
        date: inv.date,
      ));
    }
    if (inv.printedTotal > 0 && inv.items.isNotEmpty && (inv.printedTotal - sum).abs() > 0.005 * inv.printedTotal + 0.01) {
      warnings.add(
          'فاتورة ${inv.invoiceNo.isEmpty ? '' : '${inv.invoiceNo} '}: إجماليها المطبوع (${_n(inv.printedTotal)}) يخالف مجموع أصنافها (${_n(sum)}) — قد يكون صنف فات المسح أو ضريبة/خصم لم يُدرج');
    }
    if (inv.notes.isNotEmpty) warnings.add('ملاحظة من القراءة: ${inv.notes}');
  }
  if (items.isEmpty) warnings.add('لم يُستخرج أي صنف من الملف — جرّب صورة أوضح');
  return ContractScanMerge(
    items: items,
    supplier: newSupplier,
    listDate: newDate,
    currency: newCurrency,
    exchangeRate: newRate,
    warnings: warnings,
    currencyConflict: conflict,
  );
}

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
