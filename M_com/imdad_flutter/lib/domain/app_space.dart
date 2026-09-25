/// مساحات العمل: الإمداد والتموين، والمحروقات.
///
/// **لماذا مساحتان لا قائمةٌ واحدة؟** القسمان يُشغّلهما شخصان مختلفان: أمين
/// المحروقات لا شأن له بخطط الوجبات ونسب الاستهلاك، وأمين المستودع لا يفتح
/// تفريدة الوقود. وقائمةٌ واحدة تضع أمام كلٍّ منهما ضعفَ ما يحتاج.
///
/// **ولماذا مبدِّل لا بوابة؟** من يملك مساحةً واحدة يدخلها مباشرة بلا شاشة
/// اختيار يضغط فيها على خياره الوحيد كل يوم. والاختيار لا يُسأل عنه إلا من
/// يملك المساحتين، ثم يُحفظ فلا يُسأل مرة أخرى.
library;

class AppSpace {
  static const String supply = 'supply';
  static const String fuel = 'fuel';

  /// بندٌ يظهر في المساحتين — الأدلة والإعدادات والتدقيق.
  static const String both = 'both';

  static const List<String> all = [supply, fuel];

  static const Map<String, String> labels = {
    supply: 'الإمداد والتموين',
    fuel: 'المحروقات',
  };

  static const Map<String, String> descriptions = {
    supply: 'الأصناف والمستودعات والصرف والاستلام والتغذية اليومية والتقارير',
    fuel: 'تفريدة الوقود وصرفه وتوريده وتحويله وجرده وسجل المركبات',
  };

  static const Map<String, String> icons = {
    supply: 'package',
    fuel: 'zap',
  };

  static String label(String v) => labels[v] ?? v;

  /// هل يظهر بندٌ مساحتُه [itemSpace] داخل المساحة [current]؟
  static bool shows(String itemSpace, String current) =>
      itemSpace == both || itemSpace == current;

  /// صفحات كل مساحة — ما يُسأل عنه لمعرفة ما يملكه المستخدم.
  ///
  /// المشتركة ليست دليلًا على امتلاك مساحة: من يملك الإعدادات وحدها لا يُقال
  /// إنه صاحب قسم محروقات، وإلا رأى مساحةً فارغة إلا من إعداداتٍ عامة.
  static const Map<String, List<String>> pages = {
    fuel: [
      'fuelDashboard',
      'fuelAllocations',
      'fuelMoves',
      'fuelStocktake',
      'fuelWarehouses',
      'fuelUnits',
    ],
    supply: [
      'items',
      'stores',
      'units',
      'suppliers',
      'kitchens',
      'assets',
      'receive',
      'issue',
      'transfer',
      'returns',
      'opening',
      'rationOrders',
      'pendingOrders',
      'feeding',
      'mealPlans',
      'kitchenLog',
      'ratios',
      'balances',
      'stocktake',
      'reports',
    ],
  };

  /// المساحات التي يملك المستخدم شيئًا فيها فعلًا.
  ///
  /// [can] تُجيب: هل له صلاحية عرض هذه الصفحة؟
  static List<String> availableFor(bool Function(String page) can) => [
        for (final space in all)
          if (pages[space]!.any(can)) space,
      ];

  /// المساحة التي يُفتح عليها التطبيق.
  ///
  /// يعود `null` حين يملك المستخدم مساحتين ولم يختر بعد — وحدها الحالة التي
  /// تستدعي سؤاله. وإن كان المحفوظ لم يعد متاحًا (تغيّرت صلاحياته) لم يُحبس
  /// في مساحةٍ لا يرى فيها شيئًا.
  static String? resolve({
    required List<String> available,
    String? saved,
  }) {
    if (available.isEmpty) return null;
    if (available.length == 1) return available.first;
    if (saved != null && available.contains(saved)) return saved;
    return null;
  }
}
