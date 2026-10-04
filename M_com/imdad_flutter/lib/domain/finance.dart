/// قواعد «المالية»: العهدة والمسير والإخلاء. نقيّة بلا قاعدة بيانات ولا واجهة.
///
/// **القاعدة العامة:** كل حسابٍ بعملة العهدة. ما صُرف بالعملة الأخرى يُحوَّل
/// بسعر صرفه (يمني لكل سعودي)، ولا يُجمع يمنيٌّ وسعوديٌّ في رقمٍ واحد بغير تحويل.
library;

/// نوع العهدة.
class CustodyKind {
  /// مستلمة: استلمتُها من المالية فهي عليّ.
  static const String received = 'received';

  /// مسلَّمة: صرفتُها لشخصٍ فهي عليه لي.
  static const String delivered = 'delivered';

  static const Map<String, String> labels = {received: 'مستلمة', delivered: 'مسلَّمة'};

  static String label(String k) => labels[k] ?? k;
}

/// حالة العهدة.
class CustodyStatus {
  static const String open = 'open';
  static const String cleared = 'cleared';
  static const String canceled = 'canceled';

  static const Map<String, String> labels = {open: 'قيد الإخلاء', cleared: 'تم الإخلاء', canceled: 'ملغاة'};

  static String label(String s) => labels[s] ?? s;
}

/// نتيجة الإخلاء.
class CustodyOutcome {
  static const String matched = 'matched';
  static const String surplus = 'surplus';
  static const String deficit = 'deficit';

  static const Map<String, String> labels = {matched: 'مطابق', surplus: 'فائض', deficit: 'عجز'};

  static String label(String s) => labels[s] ?? '';
}

/// عملة المبالغ.
class FinCurrency {
  static const String sar = 'sar';
  static const String yer = 'yer';

  static const Map<String, String> labels = {sar: 'سعودي', yer: 'يمني'};

  static String label(String c) => labels[c] ?? c;

  /// رمزٌ مختصر بجوار المبلغ.
  static String short(String c) => c == yer ? 'ر.ي' : 'ر.س';
}

/// تحويل مبلغٍ بين العملتين بسعر الصرف (ريال يمني لكل سعودي).
///
/// يعيد `null` إن لزم التحويل ولا سعر صرفٍ صالح — فلا يُخمَّن سعر.
double? convertAmount(double amount, {required String from, required String to, required double rate}) {
  if (from == to) return amount;
  if (rate <= 0) return null;
  // يمني → سعودي: قسمة؛ سعودي → يمني: ضرب.
  return from == FinCurrency.yer ? amount / rate : amount * rate;
}

/// فرق العهدة عن المصروف: العهدة − المصروف، بعملة العهدة.
class CustodyDiff {
  const CustodyDiff({required this.type, required this.amount});

  /// `matched` | `surplus` (المصروف أقل) | `deficit` (المصروف أكثر).
  final String type;

  /// قيمة مطلقة.
  final double amount;

  /// الفروق دون نصف هللة تُعدّ مطابقة، فلا يظهر «عجز 0.0000001» من التقريب.
  static CustodyDiff of({required double granted, required double spent}) {
    final d = double.parse((granted - spent).toStringAsFixed(2));
    if (d == 0) return const CustodyDiff(type: CustodyOutcome.matched, amount: 0);
    return CustodyDiff(type: d > 0 ? CustodyOutcome.surplus : CustodyOutcome.deficit, amount: d.abs());
  }

  /// صياغة الفرق بحسب نوع العهدة والطرف المقابل ([counterparty]: المستلم في المسلَّمة).
  ///
  /// مستلمة: «متبقٍّ لك عند المالية» / «متبقٍّ عليك للمالية».
  /// مسلَّمة: «متبقٍّ لي عند X» / «متبقٍّ على X لي».
  String phrase({required String custodyKind, String counterparty = ''}) {
    if (type == CustodyOutcome.matched) return 'مطابق';
    final who = counterparty.trim().isEmpty ? 'المستلم' : counterparty.trim();
    if (custodyKind == CustodyKind.received) {
      return type == CustodyOutcome.surplus ? 'متبقٍّ لك عند المالية' : 'متبقٍّ عليك للمالية';
    }
    return type == CustodyOutcome.surplus ? 'متبقٍّ لي عند $who' : 'متبقٍّ على $who لي';
  }
}
