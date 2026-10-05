/// كتالوج الصلاحيات — **المصدر الوحيد** لمعرّفات الصلاحيات وأسمائها وإجراءاتها.
///
/// تقرؤه شاشة المستخدمين (لرسم مصفوفة الصلاحيات)، و`Perm.labels` (لرسائل
/// الرفض)، واختبار الاكتمال (يتأكد أن كل مفتاحٍ يُفحص في الكود له مدخلٌ هنا،
/// فلا تعود صلاحيةٌ «مستخدمة ولا تُمنح»).
///
/// **القسم** (`section`) يُشتقّ من الشاشات لا من مفتاحٍ مستقل: من يملك شاشاتٍ
/// في قسمٍ يراه، وهو ما تقرؤه `AppSpace.availableFor`. وقيم القسم هي نفسها
/// `AppSpace.supply` و`AppSpace.fuel` مضافًا إليها [PermSection.admin].
library;

import 'access_control.dart' show PermAction;

/// أقسام الكتالوج.
class PermSection {
  const PermSection._();

  static const String supply = 'supply';
  static const String fuel = 'fuel';

  /// الإدارة: الإعدادات والمستخدمون (ليست «مساحة عمل» في القائمة).
  static const String admin = 'admin';

  static const List<String> all = [supply, fuel, admin];

  static const Map<String, String> labels = {
    supply: 'الإمداد والتموين',
    fuel: 'المحروقات',
    admin: 'الإدارة',
  };
}

/// مدخلٌ في الكتالوج: صفحةٌ بإجراءاتها المتاحة.
class PermEntry {
  const PermEntry(this.key, this.label, this.section, this.group, this.actions);

  final String key;
  final String label;
  final String section;

  /// مجموعة العرض داخل القسم (عنوانٌ في مصفوفة الصلاحيات).
  final String group;
  final List<String> actions;
}

class PermCatalog {
  const PermCatalog._();

  // مجموعات إجراءاتٍ متكررة.
  static const _v = [PermAction.view];
  static const _crud = [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete];
  static const _doc = [..._crud, PermAction.approve, PermAction.print];

  static const entries = <PermEntry>[
    // ───────── الإمداد والتموين ─────────
    PermEntry('dashboard', 'الرئيسية', PermSection.supply, 'الرئيسية', _v),

    PermEntry('items', 'الأصناف', PermSection.supply, 'البيانات الأساسية',
        [..._crud, PermAction.print, PermAction.export, PermAction.import]),
    PermEntry('suppliers', 'الموردون', PermSection.supply, 'البيانات الأساسية', [..._crud, PermAction.export]),
    PermEntry('units', 'الوحدات المستفيدة', PermSection.supply, 'البيانات الأساسية',
        [..._crud, PermAction.print, PermAction.export]),
    PermEntry('stores', 'المستودعات', PermSection.supply, 'البيانات الأساسية', [..._crud, PermAction.export]),
    PermEntry('kitchens', 'المطابخ والأفران', PermSection.supply, 'البيانات الأساسية', _crud),
    PermEntry('assets', 'الأصول الثابتة', PermSection.supply, 'البيانات الأساسية', _crud),
    PermEntry('supplyAuthorities', 'جهات الاعتمادات', PermSection.supply, 'البيانات الأساسية', _crud),

    PermEntry('receive', 'الاستلام', PermSection.supply, 'العمليات المخزنية', _doc),
    PermEntry('issue', 'الصرف', PermSection.supply, 'العمليات المخزنية', _doc),
    PermEntry('transfer', 'التحويل المخزني', PermSection.supply, 'العمليات المخزنية', _doc),
    PermEntry('returns', 'المرتجعات', PermSection.supply, 'العمليات المخزنية', _doc),
    PermEntry('opening', 'الأرصدة الافتتاحية', PermSection.supply, 'العمليات المخزنية',
        [PermAction.view, PermAction.create, PermAction.edit, PermAction.approve, PermAction.print]),
    PermEntry('rationOrders', 'طلبيات الإعاشة', PermSection.supply, 'العمليات المخزنية', _doc),
    PermEntry('pendingOrders', 'أوامر التوريد المعلقة', PermSection.supply, 'العمليات المخزنية',
        [PermAction.view, PermAction.approve, PermAction.delete, PermAction.print]),
    PermEntry('documents', 'سجل المستندات (السندات المحفوظة)', PermSection.supply, 'العمليات المخزنية',
        [PermAction.view, PermAction.print, PermAction.edit, PermAction.delete]),

    PermEntry('feeding', 'التفريدة اليومية (التغذية / القوة)', PermSection.supply, 'التشغيل اليومي',
        [..._crud, PermAction.print, PermAction.export]),
    PermEntry('mealPlans', 'خطط الوجبات', PermSection.supply, 'التشغيل اليومي',
        [..._crud, PermAction.approve, PermAction.print, PermAction.export]),
    PermEntry('kitchenLog', 'سجل التشغيل والطهي', PermSection.supply, 'التشغيل اليومي',
        [..._crud, PermAction.print, PermAction.export]),
    PermEntry('ratios', 'نسب الاستحقاق', PermSection.supply, 'التشغيل اليومي',
        [PermAction.view, PermAction.edit, PermAction.print, PermAction.export]),

    PermEntry('balances', 'الأرصدة الحالية', PermSection.supply, 'الأرصدة والتقارير',
        [PermAction.view, PermAction.export, PermAction.print]),
    PermEntry('reports', 'مركز التقارير', PermSection.supply, 'الأرصدة والتقارير',
        [PermAction.view, PermAction.export, PermAction.print]),
    PermEntry('actualEntitlement', 'حساب الاستحقاق الفعلي', PermSection.supply, 'الأرصدة والتقارير',
        [PermAction.view, PermAction.print, PermAction.export]),
    PermEntry('campLedger', 'سجل حساب المعسكر', PermSection.supply, 'الأرصدة والتقارير',
        [PermAction.view, PermAction.create, PermAction.edit, PermAction.print, PermAction.export]),
    PermEntry('campSettlement', 'تصفية الشهر', PermSection.supply, 'الأرصدة والتقارير',
        [PermAction.view, PermAction.approve]),
    PermEntry('campDashboard', 'لوحة المعسكرات', PermSection.supply, 'الأرصدة والتقارير', _v),

    PermEntry('stocktake', 'الجرد', PermSection.supply, 'الجرد', [..._doc, PermAction.export]),

    PermEntry('cables', 'البرقيات', PermSection.supply, 'البرقيات والأرشيف', [..._crud, PermAction.print]),
    PermEntry('archive', 'الأرشيف الإلكتروني', PermSection.supply, 'البرقيات والأرشيف', [..._crud, PermAction.print]),

    PermEntry('personnel', 'القوة البشرية للإمداد والتموين', PermSection.supply, 'الارتباطات',
        [..._crud, PermAction.print, PermAction.export]),
    // «approve»: اعتماد الإخلاء المالي وحذف المُعتمد منه. «import»: استيراد مسيرات العهد.
    PermEntry('linkages', 'الارتباطات (المالية والتسليح)', PermSection.supply, 'الارتباطات',
        [..._doc, PermAction.export, PermAction.import]),

    PermEntry('auditTrail', 'سجل التدقيق', PermSection.supply, 'الرقابة',
        [PermAction.view, PermAction.export, PermAction.print]),
    PermEntry('activityIntel', 'ذكاء النشاط', PermSection.supply, 'الرقابة', [PermAction.view, PermAction.export]),
    PermEntry('executiveCmd', 'القيادة التنفيذية', PermSection.supply, 'الرقابة',
        [PermAction.view, PermAction.export, PermAction.print]),
    PermEntry('sensitiveOps', 'المراجعة الحساسة', PermSection.supply, 'الرقابة', [PermAction.view, PermAction.approve]),
    PermEntry('healthOps', 'صحة النظام والعمليات', PermSection.supply, 'الرقابة', _v),

    // ───────── المحروقات ─────────
    PermEntry('fuelDashboard', 'لوحة المحروقات', PermSection.fuel, 'الرئيسية', _v),
    PermEntry('fuelMoves', 'حركة المحروقات (صرف/توريد/تحويل/افتتاحي)', PermSection.fuel, 'الحركة',
        [..._crud, PermAction.print]),
    PermEntry('fuelAllocations', 'تفريدة المحروقات', PermSection.fuel, 'الحركة', [..._crud, PermAction.print]),
    PermEntry('fuelWarehouses', 'مستودعات المحروقات', PermSection.fuel, 'البيانات الأساسية', _crud),
    PermEntry('fuelUnits', 'وحدات المحروقات', PermSection.fuel, 'البيانات الأساسية', _crud),
    PermEntry('fuelVehicles', 'سجل المركبات', PermSection.fuel, 'البيانات الأساسية', _v),
    PermEntry('fuelReports', 'تقارير المحروقات (الرسمي والأرصدة والكشف)', PermSection.fuel, 'التقارير',
        [PermAction.view, PermAction.print]),
    PermEntry('fuelConsumption', 'تقرير استهلاك المحروقات', PermSection.fuel, 'التقارير',
        [PermAction.view, PermAction.print]),
    PermEntry('fuelStocktake', 'جرد المحروقات', PermSection.fuel, 'الجرد',
        [PermAction.view, PermAction.approve, PermAction.print]),
    PermEntry('fuelSettings', 'إعدادات المحروقات', PermSection.fuel, 'الإعدادات', [PermAction.view, PermAction.edit]),

    // ───────── الإدارة ─────────
    PermEntry('settings', 'الإعدادات والهوية', PermSection.admin, 'الإدارة', [PermAction.view, PermAction.edit]),
    PermEntry('usersAccess', 'المستخدمون والصلاحيات', PermSection.admin, 'الإدارة',
        [PermAction.view, PermAction.edit, PermAction.approve]),
  ];

  static final Map<String, PermEntry> byKey = {for (final e in entries) e.key: e};

  static final Map<String, String> labels = {for (final e in entries) e.key: e.label};

  /// أسماء بنود القائمة التي لا صلاحية خاصة بها: تتبع صلاحية صفحةٍ أخرى أو
  /// باب (انظر `_permPage` في الصفحة الرئيسية و`kMenuDoors`). تبقى لها أسماءٌ
  /// تُقرأ في رسائل الرفض والاختبارات.
  static const Map<String, String> aliasLabels = {
    'fuelData': 'البيانات الأساسية للمحروقات',
    'fuelIssue': 'صرف المحروقات',
    'fuelSupply': 'توريد المحروقات',
    'fuelTransfer': 'تحويل المحروقات',
    'fuelOpening': 'الرصيد الافتتاحي للمحروقات',
  };

  /// مدخلات قسمٍ مجمَّعةً بحسب مجموعة العرض، بترتيب الظهور.
  static Map<String, List<PermEntry>> groupsOf(String section) {
    final out = <String, List<PermEntry>>{};
    for (final e in entries) {
      if (e.section == section) (out[e.group] ??= []).add(e);
    }
    return out;
  }
}
