part of '../home_shell.dart';

/// عنصر في القائمة الجانبية — نفس `MENU` في `index.html`.
class _MenuItem {
  const _MenuItem(this.id, this.icon, this.name,
      {this.space = AppSpace.supply});

  final String id;
  final String icon;
  final String name;

  /// مساحة البند: `supply` أو `fuel` أو `both` لما يخدم القسمين.
  ///
  /// الأدلة المشتركة (المستودعات والوحدات) والإعدادات والتدقيق تظهر في
  /// القسمين: الوقود يُخزَّن في نفس المستودعات ويُصرف لنفس الوحدات، ومنعُ
  /// أمين المحروقات من دليلٍ يحتاجه في كل سند أغلى من تكرار بندٍ في قائمة.
  final String space;
}

class _MenuSection {
  const _MenuSection(this.sec, this.icon, this.name, this.items);
  final String sec;
  final String icon;
  final String name;
  final List<_MenuItem> items;
}

const _menu = <_MenuSection>[
  // ═════════ الإمداد: ستّة أقسامٍ قابلة للطي — «الرئيسية» مستقلةٌ خارجها.
  //
  // **شجرةٌ لا أبواب.** كل بندٍ هنا يفتح شاشته الخامّة مباشرة، بلا تبويباتٍ
  // فوقها تُخفي أخواتها — القسم في الشريط هو التصنيف الوحيد، فلا حاجة
  // لتصنيفٍ ثانٍ داخل الشاشة نفسها.
  _MenuSection('basic', 'database', 'البيانات الأساسية', [
    _MenuItem('items', 'package', 'الأصناف'),
    _MenuItem('stores', 'warehouse', 'المستودعات'),
    _MenuItem('units', 'users', 'الوحدات المستفيدة'),
    _MenuItem('suppliers', 'truck', 'الموردون'),
    _MenuItem('kitchens', 'utensils', 'المطابخ والأفران'),
    _MenuItem('assets', 'package', 'الأصول الثابتة'),
  ]),
  _MenuSection('stock', 'package', 'العمليات المخزنية', [
    _MenuItem('receive', 'download', 'استلام'),
    _MenuItem('issue', 'upload', 'صرف'),
    _MenuItem('transfer', 'refresh', 'تحويل'),
    _MenuItem('returns', 'undo', 'مرتجعات'),
    _MenuItem('opening', 'clipboard', 'الأرصدة الافتتاحية'),
    _MenuItem('rationOrders', 'clipboard', 'طلبيات الإعاشة'),
    _MenuItem('pendingOrders', 'bell', 'أوامر التوريد المعلقة'),
  ]),
  _MenuSection('daily', 'chart', 'التشغيل اليومي', [
    _MenuItem('feeding', 'calendar', 'التفريدة اليومية'),
    _MenuItem('mealPlans', 'calendar', 'خطط الوجبات'),
    _MenuItem('kitchenLog', 'utensils', 'سجل التشغيل والطهي'),
    _MenuItem('ratios', 'scale', 'نسب الاستحقاق'),
  ]),
  // «رقابة» وحدها بقيت باباً بتبويباته الخمسة (سجل النشاط، ذكاء النشاط،
  // التغييرات الحساسة، مركز القيادة، صحة النظام) — خمس نظراتٍ على سجلٍّ
  // واحد لا خمس شاشاتٍ منفصلة، فتفكيكها يُكرِّر لا يُبسِّط.
  _MenuSection('archiveGroup', 'folder', 'البرقيات والأرشيف', [
    _MenuItem('cables', 'mail', 'البرقيات'),
    _MenuItem('archive', 'folder', 'الأرشيف الإلكتروني'),
  ]),
  _MenuSection('linkagesGroup', 'link', 'الارتباطات', [
    // ثلاث شاشات؛ تبويباتها الفرعية داخل الشاشة نفسها لا في هذا الشريط.
    _MenuItem('personnel', 'users', 'القوة البشرية'),
    _MenuItem('linkFinances', 'dollar', 'المالية'),
    _MenuItem('linkArmament', 'target', 'التسليح'),
  ]),
  _MenuSection('reports', 'trending', 'التقارير', [
    _MenuItem('balances', 'calculator', 'الأرصدة الحالية'),
    // تقارير «مركز التقارير» التسعة كلها بنودٌ مباشرة الآن (بلا قائمة تنقّل
    // جانبية) — فلا حاجة لبند «مركز التقارير» نفسه في الشريط؛ الشاشة
    // (`reports_center_screen.dart`) بقيت بلا حذف، فقط بلا رابطٍ إليها هنا.
    _MenuItem('reportMoves', 'repeat', 'حركة المخزون اليومية'),
    _MenuItem('reportUnitAccount', 'file', 'كشف حساب وحدة مستفيدة'),
    _MenuItem('reportStock', 'package', 'تقرير أرصدة المخزون'),
    _MenuItem('reportConsumption', 'chart', 'تحليل الاستهلاك'),
    _MenuItem('reportStrength', 'users', 'تقرير حصر القوة'),
    _MenuItem('reportKitchen', 'utensils', 'أداء المطابخ والأفران'),
    _MenuItem('reportSupplier', 'truck', 'ملخص توريدات الموردين'),
    _MenuItem('reportReturns', 'undo', 'تقرير المرتجعات'),
    _MenuItem('reportDaily', 'clipboard', 'تقرير العمل اليومي'),
    _MenuItem('campLedger', 'list', 'سجل حساب المعسكر'),
    _MenuItem('campSettlement', 'scale', 'تصفية الشهر'),
    _MenuItem('actualEntitlement', 'calculator', 'حساب الاستحقاق الفعلي'),
    _MenuItem('stockAlerts', 'alert', 'تنبيهات المخزون'),
    _MenuItem('supplyAudit', 'scan', 'الرقابة والتدقيق'),
  ]),
  // خمسة بنودٍ لشاشةٍ واحدة (`StocktakeScreen`) بمعامل `standalone` يُخفي
  // تبويباتها الداخلية — لا خمس شاشاتٍ منفصلة فعلًا.
  _MenuSection('stocktake', 'clipboard', 'إدارة الجرد', [
    _MenuItem('stocktakeCreate', 'plus-square', 'إنشاء أمر جرد'),
    _MenuItem('stocktakeCount', 'clipboard', 'العدّ الفعلي'),
    _MenuItem('stocktakeAnalysis', 'scale', 'تحليل الفروقات'),
    _MenuItem('stocktakeSettle', 'check-circle', 'التسوية والاعتماد'),
    _MenuItem('stocktakeHistory', 'clock', 'سجل الجرد'),
  ]),
  // «مركز الصلاحيات» كان بندًا مستقلًّا خارج كل الأقسام يظهر لمدير النظام
  // فقط؛ انتقل هنا، وبقي مقصورًا على الإمداد (`space` الافتراضي) كما كان —
  // شأنُ النظام كله وبابه قسم الإمداد، لا يخلطه بالمحروقات.
  // بندٌ واحد: الهوية والنماذج والتفعيل والتوقيع والمزامنة والمستخدمون صارت
  // أقسامًا داخل شاشة الإعدادات نفسها (انظر [kSettingsSections])، وتبقى
  // معرّفاتها القديمة (`branding`، `deviceActivation`…) تفتح الإعدادات على قسمها.
  _MenuSection('settings', 'wrench', 'الإعدادات', [
    _MenuItem('settings', 'settings', 'الإعدادات العامة'),
  ]),

  // ═════════ المحروقات: نفس نمط الإمداد — خمسة أقسامٍ و«رئيسية» مستقلة.
  // «حركة المحروقات» أربعة بنودٍ لشاشةٍ واحدة (`FuelMovesScreen`) بمعامل
  // `standalone` يُخفي تبويباتها الداخلية، والتفريدة شاشةٌ مستقلة فعلًا.
  _MenuSection('fuelMoves', 'swap', 'حركة المحروقات', [
    _MenuItem('fuelIssue', 'upload', 'صرف', space: AppSpace.fuel),
    _MenuItem('fuelSupply', 'download', 'توريد', space: AppSpace.fuel),
    _MenuItem('fuelTransfer', 'refresh', 'تحويل', space: AppSpace.fuel),
    _MenuItem('fuelOpening', 'compass', 'رصيد افتتاحي', space: AppSpace.fuel),
    _MenuItem('fuelAllocations', 'clipboard', 'التفريدة', space: AppSpace.fuel),
  ]),
  _MenuSection('fuelData', 'database', 'البيانات الأساسية', [
    _MenuItem('fuelWarehouses', 'warehouse', 'المستودعات', space: AppSpace.fuel),
    _MenuItem('fuelUnits', 'building', 'الوحدات المستفيدة', space: AppSpace.fuel),
    _MenuItem('fuelVehicles', 'truck', 'سجل المركبات', space: AppSpace.fuel),
  ]),
  _MenuSection('fuelReports', 'chart', 'التقارير', [
    _MenuItem('fuelDaily', 'calendar', 'الحركة اليومية', space: AppSpace.fuel),
    _MenuItem('fuelOfficial', 'file', 'التقرير الرسمي', space: AppSpace.fuel),
    _MenuItem('fuelConsumption', 'trending', 'الاستهلاك', space: AppSpace.fuel),
    _MenuItem('fuelStocks', 'package', 'أرصدة المستودعات', space: AppSpace.fuel),
    _MenuItem('fuelLedger', 'list', 'كشف حركة المستودع', space: AppSpace.fuel),
    _MenuItem('fuelPlanVsIssued', 'scale', 'الاستحقاق مقابل الصرف',
        space: AppSpace.fuel),
  ]),
  // «جرد المحروقات» بلا تبويبات داخلية أصلًا (تدفّق قائمة ← تفاصيل لا
  // شريط تبويبات)، فبقيت بندًا واحدًا كما كانت.
  _MenuSection('fuelStocktake', 'clipboard', 'إدارة الجرد', [
    _MenuItem('fuelStocktake', 'clipboard', 'الجرد المخزني',
        space: AppSpace.fuel),
  ]),
  _MenuSection('fuelSettings', 'wrench', 'الإعدادات', [
    _MenuItem('fuelSettings', 'settings', 'الإعدادات', space: AppSpace.fuel),
  ]),
];

/// الصفحة التي يُضيئها بندُها في القائمة: الأقسام المضمَّنة تُضيء «الإعدادات».
String _menuPageOf(String page) => kSettingsSections.containsKey(page) ? 'settings' : page;
