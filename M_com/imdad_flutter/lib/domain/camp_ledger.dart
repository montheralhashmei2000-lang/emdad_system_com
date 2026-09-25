/// حساب سجل المعسكر — رصيدان مستقلان لكل معسكر وصنف في كل شهر.
///
/// ## المعادلتان
///
/// ```
/// رصيد الاستحقاق = المُرحَّل + المستحق − المُسلَّم
/// رصيد المخزون   = المُرحَّل عينًا + المُسلَّم − المستهلك في المطبخ
/// ```
///
/// **وخلطهما هو الغلط الشائع.** معسكرٌ أخذ كامل حقه ولم يطبخه: رصيد استحقاقه
/// صفر (لا له ولا عليه) ومخزونه ممتلئ. ومعسكرٌ طبخ أكثر مما أخذ: مخزونه سالب
/// (خطأ إدخال) واستحقاقه له. من يقيس الاستحقاق بالاستهلاك في المطبخ يخلط
/// حساب الجهة بحساب المطبخ، فيطالب وحدةً استلمت حقها كاملًا بأن تستلمه ثانيةً.
library;

/// حالة الرصيد.
enum LedgerStatus {
  /// موجب — للمعسكر عندنا.
  credit,

  /// سالب — استلم أكثر من حقه.
  debit,

  /// ضمن هامش التقريب.
  balanced,
}

extension LedgerStatusX on LedgerStatus {
  String get label => switch (this) {
        LedgerStatus.credit => 'متبقٍ له',
        LedgerStatus.debit => 'متبقٍ عليه',
        LedgerStatus.balanced => 'مطابق',
      };
}

/// مكوّنات سجل شهر واحد — بلا ارتباط بجدول، فتُختبر وحدها.
class LedgerAmounts {
  const LedgerAmounts({
    this.openingEntitled = 0,
    this.openingStock = 0,
    this.entitlementTotal = 0,
    this.transferredIn = 0,
    this.issuedDirect = 0,
    this.returnedQty = 0,
    this.consumedKitchen = 0,
  });

  final double openingEntitled;
  final double openingStock;
  final double entitlementTotal;
  final double transferredIn;
  final double issuedDirect;
  final double returnedQty;
  final double consumedKitchen;

  /// ما وصل المعسكر فعلًا: المحوَّل والمصروف مباشرةً، مطروحًا منه ما ردّه.
  double get delivered =>
      CampLedgerCalc.round(transferredIn + issuedDirect - returnedQty);

  /// هل أخذ حقه؟ موجب ⇒ له، سالب ⇒ أخذ أكثر.
  double get entitlementBalance =>
      CampLedgerCalc.round(openingEntitled + entitlementTotal - delivered);

  /// كم بقي في مخزنه؟
  double get stockBalance =>
      CampLedgerCalc.round(openingStock + delivered - consumedKitchen);

  LedgerStatus get entitlementStatus => CampLedgerCalc.statusOf(entitlementBalance);

  /// مخزون سالب مستحيل ماديًا — استهلاكٌ سُجّل بلا استلام، أو استلام لم يُسجَّل.
  bool get stockImpossible => stockBalance < -0.001;
}

class CampLedgerCalc {
  const CampLedgerCalc._();

  /// هامش التقريب: أقل من غرام لا يُغيّر حكمًا، وحملُه يجعل كل سطر «غير مطابق».
  static const double epsilon = 0.001;

  /// المستحق على مدى: **المعدل اليومي** للفرد × مجموع القوى اليومية.
  ///
  /// [monthlyQtyPerPerson] الكمية الشهرية للفرد بوحدة القياس المختارة،
  /// و[measureFactor] يحوّلها إلى وحدة الأساس (كيس ٤٠ كجم ⇒ ٤٠).
  ///
  /// **القسمة على ٣٠ ليست تفصيلًا.** نسب المقرر في هذا النظام شهرية
  /// (`Entitlements.qtyPerPerson`)، فضربها في مجموع القوى اليومية مباشرةً —
  /// كما يُكتب أحيانًا — يضخّم الاستحقاق ثلاثين ضعفًا، فيصير كل معسكر دائنًا
  /// بأرقام خيالية وتفقد التصفية معناها.
  static double entitlementOf({
    required double monthlyQtyPerPerson,
    required double measureFactor,
    required double strengthSum,
  }) {
    final factor = measureFactor <= 0 ? 1.0 : measureFactor;
    final dailyRate = monthlyQtyPerPerson * factor / 30.0;
    return round(dailyRate * strengthSum);
  }

  /// متوسط القوة اليومية على الأيام **المسجّلة** وحدها.
  ///
  /// يومٌ بلا تفريدة ليس يومًا بقوة صفر، بل يوم لم يُسجَّل — وإقحامه في
  /// القسمة يخفض المتوسط بسبب إهمال إداري لا بسبب نقص في القوة.
  static int averageStrength(Iterable<double> dailyTotals) {
    final recorded = dailyTotals.where((v) => v > 0).toList();
    if (recorded.isEmpty) return 0;
    return (recorded.reduce((a, b) => a + b) / recorded.length).round();
  }

  static LedgerStatus statusOf(double balance) {
    if (balance > epsilon) return LedgerStatus.credit;
    if (balance < -epsilon) return LedgerStatus.debit;
    return LedgerStatus.balanced;
  }

  static double round(double v) => (v * 1000).round() / 1000;

  /// إجماليات مجموعة سجلات.
  static ({double credit, double debit, double net, double stock}) totals(
    Iterable<LedgerAmounts> rows,
  ) {
    var credit = 0.0;
    var debit = 0.0;
    var stock = 0.0;
    for (final r in rows) {
      final b = r.entitlementBalance;
      if (b > epsilon) {
        credit += b;
      } else if (b < -epsilon) {
        debit += -b;
      }
      stock += r.stockBalance;
    }
    return (
      credit: round(credit),
      debit: round(debit),
      net: round(credit - debit),
      stock: round(stock),
    );
  }
}
