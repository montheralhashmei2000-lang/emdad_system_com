/// فهرس النماذج المطبوعة في النظام — سندات القسمين وتقاريرهما وكشوفهما.
///
/// **لماذا فهرسٌ مستقل:** كان تخطيطُ الطباعة واحدًا للنظام كله (مفتاح
/// `printLayout`)، فمن أراد ترويسةً للبرقيات تخالف ترويسة سندات المخزن، أو
/// خانات توقيعٍ للعهد تخالف خانات أمر الصرف، لم يكن له إلى ذلك سبيل. ومع
/// الفهرس صار لكل نموذجٍ تخطيطٌ خاصٌّ إن أُفرد، وإلا تبع الافتراضي العام.
///
/// وهو كذلك **قائمة الحضور**: كل مطبوعةٍ في النظام مذكورةٌ هنا بمفتاحها،
/// فاختبار `print_forms_test` يُسقط أي مفتاح يُستعمل في الطباعة ولا يُعرَّف
/// هنا — لئلا تعود مطبوعةٌ لا يملك أحدٌ تنسيقها (كما كان سجلّ البرقيات وكشف
/// القوة البشرية والكشوف المالية تُطبع بالافتراضي المثبَّت في الكود).
library;

/// القسم الذي تنتمي إليه المطبوعة — مطابقٌ لـ`AppSpace`.
enum PrintFormSpace { supply, fuel, common }

/// مطبوعةٌ واحدة في الفهرس.
class PrintForm {
  const PrintForm(this.key, this.label, this.screen, this.space, this.group);

  /// مفتاح التخزين — لا يُغيَّر بعد إصداره وإلا ضاع تخطيطٌ حفظه مستخدم.
  final String key;

  /// اسم المطبوعة كما يُعرض في منتقي المصمم.
  final String label;

  /// الشاشة التي تُطبع منها — ليعرف المستخدم أين يراها.
  final String screen;

  final PrintFormSpace space;

  /// مجموعة المنتقي: سندات / تقارير وكشوف / محروقات / ارتباطات / برقيات.
  final String group;
}

/// فهرس المطبوعات كله.
class PrintForms {
  const PrintForms._();

  // ───────────────────────── سندات المخزن
  static const String receipt = 'receipt';
  static const String issue = 'issue';
  static const String transfer = 'transfer';
  static const String returnFromUnit = 'returnFromUnit';
  static const String returnToSupplier = 'returnToSupplier';
  static const String opening = 'opening';
  static const String rationOrder = 'rationOrder';

  // ───────────────────────── تقارير الإمداد وكشوفه
  static const String balances = 'balances';
  static const String issueLog = 'issueLog';
  static const String stocktakeSheet = 'stocktakeSheet';
  static const String stocktakeDiff = 'stocktakeDiff';
  static const String reportsCenter = 'reportsCenter';
  static const String campLedger = 'campLedger';
  static const String actualEntitlement = 'actualEntitlement';
  static const String ratios = 'ratios';
  static const String strength = 'strength';

  // ───────────────────────── المحروقات
  static const String fuelIssue = 'fuelIssue';
  static const String fuelSupply = 'fuelSupply';
  static const String fuelTransfer = 'fuelTransfer';
  static const String fuelStocktake = 'fuelStocktake';
  static const String fuelIssuesReport = 'fuelIssuesReport';
  static const String fuelStocksReport = 'fuelStocksReport';
  static const String fuelOfficial = 'fuelOfficial';
  static const String fuelDaily = 'fuelDaily';
  static const String fuelPlan = 'fuelPlan';
  static const String fuelConsumption = 'fuelConsumption';

  // ───────────────────────── الارتباطات والمالية
  static const String roster = 'roster';
  static const String custodyClearance = 'custodyClearance';
  static const String financeStatement = 'financeStatement';
  static const String purchaseContract = 'purchaseContract';
  static const String custodySheet = 'custodySheet';
  static const String moneyReceipt = 'moneyReceipt';

  // ───────────────────────── البرقيات
  static const String cableForm = 'cableForm';
  static const String cableLog = 'cableLog';

  static const String groupVouchers = 'سندات المخزن';
  static const String groupReports = 'تقارير وكشوف';
  static const String groupFuel = 'المحروقات';
  static const String groupLinks = 'الارتباطات والمالية';
  static const String groupCables = 'البرقيات والوثائق';

  /// الفهرس مرتَّبًا كما يُعرض: سندات، ثم تقارير، ثم المحروقات، ثم الارتباطات،
  /// ثم البرقيات.
  static const List<PrintForm> all = [
    PrintForm(receipt, 'سند استلام (توريد)', 'الوارد', PrintFormSpace.supply, groupVouchers),
    PrintForm(issue, 'أمر صرف', 'الصرف', PrintFormSpace.supply, groupVouchers),
    PrintForm(transfer, 'إذن تحويل مخزني', 'التحويل', PrintFormSpace.supply, groupVouchers),
    PrintForm(returnFromUnit, 'مرتجع من وحدة', 'المرتجعات', PrintFormSpace.supply, groupVouchers),
    PrintForm(returnToSupplier, 'مرتجع إلى مورّد', 'المرتجعات', PrintFormSpace.supply, groupVouchers),
    PrintForm(opening, 'سند أرصدة افتتاحية', 'الأرصدة الافتتاحية', PrintFormSpace.supply, groupVouchers),
    PrintForm(rationOrder, 'طلبية إعاشة', 'طلبيات الإعاشة', PrintFormSpace.supply, groupVouchers),
    PrintForm(balances, 'تقرير الأرصدة', 'الأرصدة', PrintFormSpace.supply, groupReports),
    PrintForm(issueLog, 'سجل الصرف', 'الصرف — السجل', PrintFormSpace.supply, groupReports),
    PrintForm(stocktakeSheet, 'كشف جرد', 'الجرد', PrintFormSpace.supply, groupReports),
    PrintForm(stocktakeDiff, 'محضر فروق الجرد', 'الجرد', PrintFormSpace.supply, groupReports),
    PrintForm(reportsCenter, 'تقارير مركز التقارير', 'مركز التقارير', PrintFormSpace.supply, groupReports),
    PrintForm(campLedger, 'دفتر المعسكر', 'دفتر المعسكر', PrintFormSpace.supply, groupReports),
    PrintForm(actualEntitlement, 'كشف الاستحقاق الفعلي', 'الاستحقاق الفعلي', PrintFormSpace.supply, groupReports),
    PrintForm(ratios, 'كشف المعدلات', 'المعدلات', PrintFormSpace.supply, groupReports),
    PrintForm(strength, 'كشف القوة اليومية', 'القوة اليومية', PrintFormSpace.supply, groupReports),
    PrintForm(fuelSupply, 'سند توريد محروقات', 'حركات المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelIssue, 'سند صرف محروقات', 'حركات المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelTransfer, 'سند تحويل محروقات', 'حركات المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelStocktake, 'محضر جرد محروقات', 'جرد المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelIssuesReport, 'كشف صرف المحروقات', 'حركات المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelStocksReport, 'كشف أرصدة المحروقات', 'أرصدة المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelOfficial, 'التقرير الرسمي للمحروقات', 'تقارير المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelDaily, 'ملخّص الحركة اليومية', 'تقارير المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelPlan, 'مقترح خطة التوزيع', 'تقارير المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(fuelConsumption, 'تقرير الاستهلاك', 'استهلاك المحروقات', PrintFormSpace.fuel, groupFuel),
    PrintForm(roster, 'كشف القوة البشرية', 'الارتباطات — الأفراد', PrintFormSpace.supply, groupLinks),
    PrintForm(custodyClearance, 'إخلاء عهدة', 'الارتباطات — المالية', PrintFormSpace.supply, groupLinks),
    PrintForm(financeStatement, 'كشف حساب مالي', 'الارتباطات — المالية', PrintFormSpace.supply, groupLinks),
    PrintForm(purchaseContract, 'عقد شراء', 'الارتباطات — العقود', PrintFormSpace.supply, groupLinks),
    PrintForm(custodySheet, 'كشف عهدة', 'الارتباطات — العهد', PrintFormSpace.supply, groupLinks),
    PrintForm(moneyReceipt, 'سند قبض/صرف نقدي', 'الارتباطات — المالية', PrintFormSpace.supply, groupLinks),
    PrintForm(cableForm, 'نموذج برقية', 'البرقيات', PrintFormSpace.common, groupCables),
    PrintForm(cableLog, 'سجل البرقيات', 'البرقيات', PrintFormSpace.common, groupCables),
  ];

  /// المجموعات بترتيب ظهورها في الفهرس.
  static List<String> get groups {
    final out = <String>[];
    for (final f in all) {
      if (!out.contains(f.group)) out.add(f.group);
    }
    return out;
  }

  static PrintForm? find(String key) {
    for (final f in all) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// اسم المطبوعة أو المفتاح نفسه إن كان مجهولًا (تخطيطٌ قديمٌ لمفتاح حُذف).
  static String labelOf(String key) => find(key)?.label ?? key;

  static bool has(String key) => find(key) != null;
}
