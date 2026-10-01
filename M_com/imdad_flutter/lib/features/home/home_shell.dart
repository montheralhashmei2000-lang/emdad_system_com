import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../core/security/auth_service.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/reports_repo.dart' show ReportId;
import '../../data/repos/settings_repo.dart';
import '../../main.dart' show ImdTheme;
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_menu_bar.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';
import '../../core/ui/imd_widgets.dart';
import '../../domain/access_control.dart';
import '../../domain/app_space.dart';
import '../../domain/menu_doors.dart';
import '../../data/sync/auto_sync.dart';
import 'space_chooser_screen.dart';
import '../fuel/fuel_allocations_screen.dart';
import '../fuel/fuel_consumption_screen.dart';
import '../fuel/fuel_daily_report_screen.dart';
import '../fuel/fuel_directories_screen.dart';
import '../fuel/fuel_groups.dart';
import '../fuel/fuel_ledger_screen.dart';
import '../fuel/fuel_official_report_screen.dart';
import '../fuel/fuel_vehicles_screen.dart';
import 'supply_groups.dart';
import '../fuel/fuel_settings_screen.dart';
import '../fuel/fuel_dashboard_screen.dart';
import '../fuel/fuel_moves_screen.dart';
import '../fuel/fuel_stocktake_screen.dart';
import '../daily/meal_plan_screen.dart';
import '../daily/kitchen_log_screen.dart';
import '../daily/ratios_screen.dart';
import '../daily/strength_screen.dart';
import 'notification_bell.dart';
import '../alerts/stock_alerts_screen.dart';
import '../catalog/assets_screen.dart';
import '../catalog/items_screen.dart';
import '../catalog/kitchens_screen.dart';
import '../catalog/suppliers_screen.dart';
import '../catalog/units_screen.dart';
import '../catalog/warehouses_screen.dart';
import '../inventory/issue_screen.dart';
import '../inventory/opening_screen.dart';
import '../inventory/pending_screen.dart';
import '../inventory/ration_order_screen.dart';
import '../inventory/receive_screen.dart';
import '../inventory/returns_screen.dart';
import '../inventory/transfer_screen.dart';
import '../reports/balances_screen.dart';
import '../reports/camp_ledger_screen.dart';
import '../reports/camp_settlement_screen.dart';
import '../reports/actual_entitlement_screen.dart';
import '../reports/reports_center_screen.dart';
import '../settings/settings_screen.dart';
import '../stocktake/stocktake_screen.dart';
import 'dashboard_screen.dart';

/// التنقل بين الشاشات من داخل أي شاشة.
class ImdNav {
  ImdNav(this._go, this._current);
  final void Function(String page) _go;
  final String Function() _current;

  void go(String page) => _go(page);
  String get current => _current();

  static ImdNav of(BuildContext context) => context.read<ImdNav>();
}

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

/// معرّفات الصفحات التي صارت أقسامًا داخل الإعدادات ← القسم الذي تُفتح عليه.
const kSettingsSections = <String, String>{
  'branding': 'company',
  'formsDesigner': 'forms',
  'deviceActivation': 'devices',
  'verifySign': 'verify',
  'lanSync': 'sync',
  'usersAccess': 'users',
};

/// الصفحة التي يُضيئها بندُها في القائمة: الأقسام المضمَّنة تُضيء «الإعدادات».
String _menuPageOf(String page) => kSettingsSections.containsKey(page) ? 'settings' : page;

class _MenuSection {
  const _MenuSection(this.sec, this.icon, this.name, this.items);
  final String sec;
  final String icon;
  final String name;
  final List<_MenuItem> items;
}

/// عتبات القشرة الثلاث.
///
/// **الشاشة الواحدة تعمل على شاشتين مختلفتين تمامًا**: حاسبُ الشعبة وجهازُ
/// أمين المستودع في يده. والفرق ليس في الحجم وحده — على الحاسب فأرةٌ ووقت،
/// وفي اليد إبهامٌ وعجلة.
class _Shell {
  const _Shell._();

  /// فوقها شريطٌ جانبيّ كامل بأقسامه وأسمائه.
  static const double wide = 1150;

  /// بينها و[wide] شريطٌ ضيّق بالأيقونات وحدها: ٢٩٠ بكسل تأكل ثلث لوحيّ
  /// عرضه ألف، وسبعون منها تكفي للتنقّل.
  static const double rail = 900;
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

/// الهيكل الرئيسي بعد الدخول:
/// شريط علوي، قائمة جانبية داكنة بأقسام قابلة للطي (قسم واحد مفتوح)، ومنطقة المحتوى.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  String _page = 'dash';
  String? _openSec = 'basic';

  static const double _sideMin = 220;
  static const double _sideMax = 420;
  static const String _sideKey = 'imdad.sideWidth';
  double _sideWidth = ImdSizes.sideWidth;

  Future<void> _loadSideWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_sideKey);
    if (w != null && mounted) setState(() => _sideWidth = w.clamp(_sideMin, _sideMax));
  }

  Future<void> _saveSideWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sideKey, _sideWidth);
  }

  /// مساحة العمل الحالية — `null` تعني أن المستخدم يملك الاثنتين ولم يختر.
  String? _space;
  bool _spaceReady = false;
  Timer? _sessionTimer;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ImdNav _nav = ImdNav(_go, () => _page);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // فحص دوري: الجلسة 12 ساعة، ووقف الحساب يُنهي الجلسة فورًا.
    _sessionTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _checkSession());
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSpace());
    _loadSideWidth();
  }

  /// مفتاح الاختيار لكل مستخدم على حدة: جهازٌ يتشاركه أمين المستودع وأمين
  /// المحروقات لا يفرض اختيار أحدهما على الآخر.
  String _spaceKey(AuthService auth) =>
      'imdad.space.${auth.currentUser?.id ?? ''}';

  Future<void> _restoreSpace() async {
    final auth = context.read<AuthService>();
    final available = AppSpace.availableFor((p) => _hasPerm(auth, p));
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_spaceKey(auth));
    if (!mounted) return;
    setState(() {
      _space = AppSpace.resolve(available: available, saved: saved);
      _spaceReady = true;
    });
  }

  Future<void> _pickSpace(String space) async {
    final auth = context.read<AuthService>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spaceKey(auth), space);
    if (!mounted) return;
    setState(() {
      _space = space;
      _page = 'dash';
      _openSec = space == AppSpace.fuel ? 'fuelMoves' : 'basic';
    });
  }

  /// العودة إلى الاختيار — لا يُمسح المحفوظ حتى لا يُنسى تفضيله إن تراجع.
  void _switchSpace() => setState(() => _space = null);

  @override
  void dispose() {
    _sessionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSession();
  }

  Future<void> _checkSession() async {
    final auth = context.read<AuthService>();
    if (!await auth.sessionExpired()) return;
    if (!mounted) return;
    showImdToast(context, 'انتهت مدة الجلسة — سجّل الدخول من جديد');
    await widget.onSignOut();
  }

  void _go(String page) {
    setState(() => _page = page);
    // يُغلق الدرج نفسه لا «أعلى مسار»: `Navigator.pop` كانت تغلق أي حوارٍ
    // مفتوح فوق الشاشة بدل الدرج.
    _scaffoldKey.currentState?.closeEndDrawer();
  }

  bool _isAdmin(AuthService auth) => auth.currentUser?.role == 'admin';

  /// صفحات بلا صلاحية خاصة بها تتبع صلاحية صفحة أخرى، فلا يلزم تعديل الأدوار.
  static const _permPage = {
    'lanSync': 'settings',
    'stockAlerts': 'balances',
    // بنود الحركة الأربعة شاشةٌ واحدة بتبويبات، فصلاحيتها واحدة.
    'fuelIssue': 'fuelMoves',
    'fuelSupply': 'fuelMoves',
    'fuelTransfer': 'fuelMoves',
    'fuelOpening': 'fuelMoves',
    // والتقارير الستة تحت صلاحية التقارير، عدا الاستهلاك فله صلاحيته.
    'fuelDaily': 'fuelReports',
    'fuelOfficial': 'fuelReports',
    'fuelStocks': 'fuelReports',
    'fuelLedger': 'fuelReports',
    'fuelPlanVsIssued': 'fuelReports',
    // بنود إدارة الجرد الخمسة شاشةٌ واحدة بتبويبات داخلية، فصلاحيتها واحدة.
    'stocktakeCreate': 'stocktake',
    'stocktakeCount': 'stocktake',
    'stocktakeAnalysis': 'stocktake',
    'stocktakeSettle': 'stocktake',
    'stocktakeHistory': 'stocktake',
    // أربعة من تقارير «مركز التقارير» فُكِّكت إلى بنودٍ مباشرة؛ صلاحيتها صلاحية
    // المركز نفسه — الفلترة بين التقارير تنظيمٌ للقائمة لا توسيعٌ للأذونات.
    'reportMoves': 'reports',
    'reportUnitAccount': 'reports',
    'reportStock': 'reports',
    'reportConsumption': 'reports',
    'reportStrength': 'reports',
    'reportKitchen': 'reports',
    'reportSupplier': 'reports',
    'reportReturns': 'reports',
    'reportDaily': 'reports',
  };

  bool _hasPerm(AuthService auth, String page,
      [String action = PermAction.view]) {
    page = _permPage[page] ?? page;
    // بابٌ بتبويبات يُفتح لمن ملك إحداها، والتبويبات تُخفي ما لا يملك —
    // فالجمع تنظيمٌ للقائمة لا توسيعٌ للأذونات.
    if (kMenuDoors.containsKey(page)) {
      return menuDoorAllows(page, (p) => _hasPerm(auth, p, action));
    }
    final user = auth.currentUser;
    if (user == null) return false;
    final perms = auth.permissionsOf(user).map(
          (k, v) => MapEntry(
              k, (v as Map).map((a, b) => MapEntry(a.toString(), b == true))),
        );
    return AccessControl.can(
        isAdmin: _isAdmin(auth),
        permissions: perms,
        page: page,
        action: action);
  }

  Widget _pageBody(String page) {
    switch (page) {
      case 'dash':
        // «الرئيسية» تتبع القسم: لوحة الإمداد في مكانها، ولوحة المحروقات في
        // مكانها — ولا يرى صاحب قسمٍ لوحةَ القسم الآخر.
        return _space == AppSpace.fuel
            ? const FuelDashboardScreen()
            : const DashboardScreen();
      case 'items':
        return const ItemsScreen();
      case 'suppliers':
        return const SuppliersScreen();
      case 'kitchens':
        return const KitchensScreen();
      case 'units':
        return const UnitsScreen();
      case 'campLedger':
        return const CampLedgerScreen();
      case 'campSettlement':
        return const CampSettlementScreen();
      case 'actualEntitlement':
        return const ActualEntitlementScreen();
      case 'mealPlans':
        return const MealPlanScreen();
      case 'dailyOperations':
        return const SupplyDailyScreen(initialTab: 'dailyOperations');
      case 'assets':
        return const AssetsScreen();
      case 'fuelDashboard':
        return const FuelDashboardScreen();
      // حركة المحروقات: كل بندٍ يفتح نفس الشاشة، لكن مقفلةً على تبويبته —
      // `standalone: true` يُخفي شريط التبويبات (انظر fuel_moves_screen.dart).
      case 'fuelIssue':
        return const FuelMovesScreen(initialTab: 'issue', standalone: true);
      case 'fuelSupply':
        return const FuelMovesScreen(initialTab: 'supply', standalone: true);
      case 'fuelTransfer':
        return const FuelMovesScreen(initialTab: 'transfer', standalone: true);
      case 'fuelOpening':
        return const FuelMovesScreen(initialTab: 'opening', standalone: true);
      case 'fuelAllocations':
        return const FuelAllocationsScreen();
      case 'fuelMoves':
        return const FuelMovesScreen();
      case 'fuelStocktake':
        return const FuelStocktakeScreen();
      // الأدلّة والتقارير أبوابٌ بتبويبات، والمعرّفات القديمة تفتحها على
      // تبويبتها — فاختصارٌ أو رابطٌ قديم لا ينكسر.
      case 'fuelData':
        return const FuelDataScreen();
      case 'fuelWarehouses':
        return const FuelWarehousesScreen();
      case 'fuelUnits':
        return const FuelUnitsScreen();
      case 'fuelVehicles':
        return const FuelVehiclesScreen();
      case 'fuelConsumption':
        return const FuelConsumptionScreen();
      case 'fuelDaily':
        return const FuelDailyReportScreen();
      case 'fuelOfficial':
        return const FuelOfficialReportScreen();
      case 'fuelStocks':
        return const FuelStocksReportScreen();
      case 'fuelLedger':
        return const FuelLedgerScreen();
      case 'fuelPlanVsIssued':
        return const FuelPlanVsIssuedScreen();
      case 'fuelReports':
        return const FuelReportsHubScreen();
      case 'fuelSettings':
        return const FuelSettingsScreen();
      // أبواب الإمداد — والمعرّفات القديمة تفتحها على تبويبتها، فلا ينكسر
      // اختصارٌ في اللوحة ولا رابطٌ من تنبيه.
      case 'supplyMoves':
        return const SupplyMovesScreen();
      case 'supplyOrders':
        return const SupplyOrdersScreen();
      case 'supplyData':
        return const SupplyDataScreen();
      case 'supplyDaily':
        return const SupplyDailyScreen();
      case 'supplyReports':
        return const SupplyReportsScreen();
      case 'supplyAudit':
        return const SupplyAuditScreen();
      case 'rationOrders':
        return const RationOrderScreen();
      case 'stores':
        return const WarehousesScreen();
      case 'pendingOrders':
        return const PendingScreen();
      case 'receive':
        return const ReceiveScreen();
      case 'issue':
        return const IssueScreen();
      case 'transfer':
        return const TransferScreen();
      case 'returns':
        return const ReturnsScreen();
      case 'opening':
        return const OpeningScreen();
      case 'feeding':
        return const StrengthScreen();
      case 'kitchenLog':
        return const KitchenLogScreen();
      case 'ratios':
        return const RatiosScreen();
      case 'balances':
        return const BalancesScreen();
      case 'stockAlerts':
        return const StockAlertsScreen();
      // إدارة الجرد: نفس معالجة حركة المحروقات — `standalone: true` يُخفي
      // شريط تبويبات الشاشة الداخلي عند الفتح من بندٍ مباشر.
      case 'stocktakeCreate':
        return const StocktakeScreen(initialTab: 'create', standalone: true);
      case 'stocktakeCount':
        return const StocktakeScreen(initialTab: 'count', standalone: true);
      case 'stocktakeAnalysis':
        return const StocktakeScreen(initialTab: 'analysis', standalone: true);
      case 'stocktakeSettle':
        return const StocktakeScreen(initialTab: 'approve', standalone: true);
      case 'stocktakeHistory':
        return const StocktakeScreen(initialTab: 'history', standalone: true);
      case 'stocktake':
        return const StocktakeScreen();
      case 'reports':
        return const ReportsCenterScreen();
      // أربعة تقارير من التسعة القائمة داخل «مركز التقارير» فُكِّكت إلى بنودٍ
      // مباشرة — `standalone: true` يُخفي قائمة التنقّل الجانبية للمركز،
      // والتقرير الواحد يصير الشاشة كلها (نفس معالجة حركة المحروقات).
      case 'reportMoves':
        return const ReportsCenterScreen(initialReport: ReportId.moves, standalone: true);
      case 'reportUnitAccount':
        return const ReportsCenterScreen(
            initialReport: ReportId.unitAccount, standalone: true);
      case 'reportStock':
        return const ReportsCenterScreen(initialReport: ReportId.stock, standalone: true);
      case 'reportConsumption':
        return const ReportsCenterScreen(
            initialReport: ReportId.consumption, standalone: true);
      case 'reportStrength':
        return const ReportsCenterScreen(initialReport: ReportId.strength, standalone: true);
      case 'reportKitchen':
        return const ReportsCenterScreen(initialReport: ReportId.kitchen, standalone: true);
      case 'reportSupplier':
        return const ReportsCenterScreen(initialReport: ReportId.supplier, standalone: true);
      case 'reportReturns':
        return const ReportsCenterScreen(initialReport: ReportId.returns, standalone: true);
      case 'reportDaily':
        return const ReportsCenterScreen(initialReport: ReportId.daily, standalone: true);
      case 'auditTrail':
        return const SupplyAuditScreen(initialTab: 'auditTrail');
      case 'activityIntel':
        return const SupplyAuditScreen(initialTab: 'activityIntel');
      case 'executiveCmd':
        return const SupplyAuditScreen(initialTab: 'executiveCmd');
      case 'sensitiveOps':
        return const SupplyAuditScreen(initialTab: 'sensitiveOps');
      case 'healthOps':
        return const SupplyAuditScreen(initialTab: 'healthOps');
      case 'settings':
        return const SettingsScreen();
      // أقسامٌ داخل الإعدادات: الروابط القديمة تفتح الإعدادات على القسم نفسه.
      case 'formsDesigner':
      case 'deviceActivation':
      case 'verifySign':
      case 'branding':
      case 'usersAccess':
      case 'lanSync':
        return SettingsScreen(initialSection: kSettingsSections[page]!);
    }
    // رسالة الشاشات غير المبنية بعد.
    return const _Soon();
  }

  @override
  Widget build(BuildContext context) =>
      // **القياس على المساحة المتاحة لا على النافذة**: القشرة قد تُعرض داخل
      // لوحٍ مقسوم أو نافذةٍ فرعية، وقياسُ النافذة يعدها عريضةً وهي ضيقة.
      LayoutBuilder(builder: (context, cons) => _build(context, cons.maxWidth));

  Widget _build(BuildContext context, double width) {
    final auth = context.read<AuthService>();
    final c = context.imd;
    final wide = width > _Shell.wide;
    final rail = !wide && width > _Shell.rail;
    final handheld = width <= _Shell.rail;

    // قبل أن تُقرأ المساحة المحفوظة لا تُرسم قائمةٌ قد تتبدّل بعد لحظة.
    if (!_spaceReady) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final available = AppSpace.availableFor((p) => _hasPerm(auth, p));
    if (_space == null && available.length > 1) {
      return SpaceChooserScreen(
        spaces: available,
        userName: auth.currentUser?.name.isNotEmpty == true
            ? auth.currentUser!.name
            : (auth.currentUser?.username ?? ''),
        onPick: _pickSpace,
      );
    }
    final space = _space ?? AppSpace.supply;

    final allowed = _page == 'dash' || _hasPerm(auth, _page);
    final body = allowed ? _pageBody(_page) : const _NoAccess();

    final side = _Sidebar(
      page: _menuPageOf(_page),
      space: space,
      rail: rail,
      openSec: _openSec,
      hasPerm: (p) => _hasPerm(auth, p),
      userName: auth.currentUser?.name.isNotEmpty == true
          ? auth.currentUser!.name
          : (auth.currentUser?.username ?? ''),
      onGo: _go,
      onToggle: (sec) =>
          setState(() => _openSec = _openSec == sec ? null : sec),
      onLogout: widget.onSignOut,
      width: _sideWidth,
    );

    final shell = Provider<ImdNav>.value(
      value: _nav,
      child: PopScope(
        // زر الرجوع كان يُنهي التطبيق بضغطة واحدة من أي شاشة. الآن يعود إلى
        // الرئيسية أولًا، ولا يخرج من الرئيسية إلا بتأكيد صريح.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          // الرجوع والدرج مفتوح يغلق الدرج أولًا.
          if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
            _scaffoldKey.currentState?.closeEndDrawer();
            return;
          }
          final home = _space == AppSpace.fuel ? 'fuelDashboard' : 'dash';
          if (_page != home && _page != 'dash') {
            _go(home);
            return;
          }
          if (await imdConfirm(context, 'إغلاق النظام؟', ok: 'خروج')) {
            // `SystemNavigator.pop` تُنهي تطبيق أندرويد، أما على ويندوز
            // فتُطلب ولا يستجيب لها أحد: يظلّ المستخدم ينقر ويظنّ التطبيق
            // معلّقًا. وهدمُ النافذة هو إنهاؤه هناك.
            // `exit()` يمسح الجلسة ويُغلق المنافذ على كل المنصات، ويُنهي العملية
            // على ويندوز؛ على أندرويد يُنهي النظام التطبيق بعد `pop`.
            await ImdWindow.exit();
            if (!ImdWindow.supported) await SystemNavigator.pop();
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: c.bg,
          // الدرج يحمل القائمة كاملةً في اليد: الشريط السفليّ لأشهر الأبواب،
          // وما وراءها يُفتح منه.
          endDrawer: handheld
              ? Drawer(
                  width: ImdSizes.sideWidth,
                  backgroundColor: c.side,
                  child: _Sidebar(
                    page: _menuPageOf(_page),
                    space: space,
                    openSec: _openSec,
                    hasPerm: (p) => _hasPerm(auth, p),
                    userName: side.userName,
                    // `_go` يغلق الدرج. كان هنا `maybePop` أيضًا فتعترضها `PopScope`
                    // أدناه وتُعيد المستخدم إلى الرئيسية (أو تسأله عن الإغلاق)،
                    // فلا تفتح أي شاشةٍ من الدرج على أندرويد إلا «الرئيسية».
                    onGo: _go,
                    onToggle: (sec) => setState(
                        () => _openSec = _openSec == sec ? null : sec),
                    onLogout: widget.onSignOut,
                  ),
                )
              : null,
          bottomNavigationBar: handheld
              ? _BottomNav(
                  space: space,
                  page: _menuPageOf(_page),
                  hasPerm: (p) => _hasPerm(auth, p),
                  onGo: _go,
                  onMore: () => _scaffoldKey.currentState?.openEndDrawer(),
                )
              : null,
          body: Column(
            children: [
              _Topbar(
                userName: side.userName,
                showBurger: handheld,
                onBurger: () => _scaffoldKey.currentState?.openEndDrawer(),
                onOpenPage: _go,
                space: _space ?? '',
                canSwitch: available.length > 1,
                onSwitchSpace: _switchSpace,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!handheld) side,
                    if (!handheld && !rail)
                      _SideSplitter(
                        onDrag: (dx) => setState(() {
                          // القائمة على الطرف البدئي: السحب نحو المحتوى يوسّعها.
                          final rtl = Directionality.of(context) == ui.TextDirection.rtl;
                          _sideWidth = (_sideWidth + (rtl ? -dx : dx)).clamp(_sideMin, _sideMax);
                        }),
                        onEnd: _saveSideWidth,
                      ),
                    Expanded(
                      child: KeyedSubtree(key: ValueKey(_page), child: body),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // قسم المحروقات يأخذ السمة العامة نفسها التي يأخذها الإمداد — لا سمةً
    // داكنةً خاصة به (`AppTheme.fuel` أُزيلت من هنا عمدًا).
    return shell;
  }
}

/// الشريط العلوي: عنوان الشاشة، وتبديل القسم، وتبديل السمة، وحالة
/// المزامنة، وحساب المستخدم.
///
/// تبديل القسم انتقل إليه من الشريط الجانبي: هو إجراءٌ نادر (مرةً في بداية
/// الجلسة غالبًا) لا يستحقّ ارتفاعًا دائمًا في القائمة، وهنا يبقى في متناول
/// اليد بلا أن يزاحم أبوابها.
class _Topbar extends StatelessWidget {
  const _Topbar({
    required this.userName,
    required this.showBurger,
    required this.onBurger,
    required this.onOpenPage,
    required this.space,
    required this.canSwitch,
    required this.onSwitchSpace,
  });

  final String userName;
  final bool showBurger;
  final VoidCallback onBurger;
  final ValueChanged<String> onOpenPage;

  /// القسم الذي يقف فيه المستخدم — الجرس يخصّ ما بين يديه.
  final String space;

  /// زر التبديل لا يظهر تفاعليًّا لمن يملك مساحةً واحدة: تبديلٌ إلى لا شيء،
  /// لكن اسم القسم يبقى معروضًا فيعرف من فتحه أين هو.
  final bool canSwitch;
  final VoidCallback onSwitchSpace;

  /// يبدّل السمة صراحةً بين فاتحٍ وداكن (لا «تلقائي»): زرٌّ سريعٌ يفترض
  /// نيّة المستخدم من السطوع الحالي الفعلي — ويحفظها فتبقى بعد إعادة
  /// التشغيل، بنفس مسار حفظ السمة من شاشة الهوية.
  Future<void> _toggleTheme(BuildContext context) async {
    final next = Theme.of(context).brightness == Brightness.dark ? 'light' : 'dark';
    final settings = SettingsRepo(context.read<AppDatabase>());
    final id = await settings.identity();
    await settings.saveIdentity(id.copyWith(themePref: next));
    if (context.mounted) context.read<ImdTheme>().apply(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // **الشريط العلويّ نظيفٌ على الجهازين.** ما يُزاح أولًا شاراتُ الحالة،
    // ثم اسم المستخدم، ثم اسم النظام — وتبقى الصورة والجرس والقائمة، وهي
    // ما يُنقر. وبلا هذا التدرّج يفيض الصف ويُرسم شريطًا أصفر.
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final showSync = w > 900;
      final showIam = w > 720;
      final showName = w > 560;
      final showTitle = w > 430;
      final sync = context.watch<AutoSyncService>();
      final failed = !sync.isRunning &&
          (sync.status.contains('تعذّر') || sync.status.contains('تعثّرت') || sync.status.contains('فشل'));
      final syncLabel = sync.isRunning
          ? 'جارٍ التزامن'
          : !sync.enabled
              ? 'المزامنة متوقفة'
              : failed
                  ? 'تعذّرت آخر مزامنة'
                  : sync.lastAt == null
                      ? 'بانتظار أول مزامنة'
                      : 'آخر مزامنة ${DateFormat('HH:mm').format(sync.lastAt!)}';

      // أندرويد ١٥+ يرسم التطبيق خلف شريط الحالة: بلا هذا الإزاحة يطلع الشريط
      // العلوي (الاسم والمزامنة) تحت الساعة والبطارية. على ويندوز الإزاحة صفر.
      final inset = MediaQuery.paddingOf(context).top;
      return Container(
        height: ImdSizes.topbarHeight + inset,
        padding: EdgeInsets.fromLTRB(12, 8 + inset, 12, 10),
        decoration: BoxDecoration(
          color: c.topbar(mica: ImdWindow.micaActive.value),
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            if (showBurger) ...[
              ImdIconButton(icon: 'menu', onPressed: onBurger),
              const SizedBox(width: 8),
            ],
            if (showTitle)
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'نظام '),
                    TextSpan(
                        text: 'الإمداد والتموين',
                        style: TextStyle(
                            color: c.accent, fontWeight: FontWeight.w700)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.text2),
                ),
              ),
            if (showTitle) ...[
              const SizedBox(width: 10),
              const ImdMenuBar(),
            ],
            const SizedBox(width: 10),
            // تبديل القسم: أيقونةٌ دائمًا، واسمه معها ما اتّسع الشريط. من
            // يملك مساحةً واحدة يبقى الاسم معروضًا له لكن بلا تفاعل — لا
            // تبديل إلى لا شيء.
            MouseRegion(
              cursor: canSwitch ? ImdCursor.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: canSwitch ? onSwitchSpace : null,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: canSwitch ? 'تبديل القسم' : AppSpace.label(space),
                  child: Container(
                    height: 36,
                    padding: EdgeInsetsDirectional.fromSTEB(
                        10, 6, showTitle ? 12 : 10, 6),
                    decoration: BoxDecoration(
                      color: c.subtle,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ImdIcon(
                          canSwitch
                              ? 'swap'
                              : (AppSpace.icons[space] ?? 'package'),
                          size: 13,
                          color: c.muted),
                      if (showTitle) ...[
                        const SizedBox(width: 6),
                        Text(AppSpace.label(space),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.text2)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
            const Spacer(),
            ImdIconButton(
              icon: c.isDark ? 'sun' : 'moon',
              tooltip: c.isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
              onPressed: () => _toggleTheme(context),
            ),
            const SizedBox(width: 8),
            NotificationBell(onOpenPage: onOpenPage, space: space),
            const SizedBox(width: 8),
            Container(
              height: 40,
              padding: EdgeInsetsDirectional.fromSTEB(6, 4, showName ? 10 : 6, 4),
              decoration: BoxDecoration(
                  color: c.subtle, borderRadius: BorderRadius.circular(99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(name: userName, size: 32, fontSize: 14),
                  if (showName) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.text)),
                    ),
                  ],
                  if (showIam) ...[
                    const SizedBox(width: 10),
                    const _StatusPill(label: 'IAM محمي'),
                  ],
                  if (showSync) ...[
                    const SizedBox(width: 10),
                    _StatusPill(
                      label: syncLabel,
                      tone: failed ? ImdTone.err : (sync.isRunning ? ImdTone.info : (sync.enabled ? ImdTone.ok : ImdTone.off)),
                      tooltip: sync.status.isEmpty ? null : sync.status,
                      onTap: () => onOpenPage('lanSync'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// كبسولة حالةٍ بنقطةٍ ملوّنة — تُستعمل لحالة المزامنة في الشريط العلوي.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.tone = ImdTone.ok, this.tooltip, this.onTap});
  final String label;
  final ImdTone tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final (_, foreground) = ImdChip.colors(c, tone);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.text2,
                height: 1.6)),
      ]),
    );
    final tappable = onTap == null ? pill : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(999), child: pill);
    return tooltip == null || tooltip!.isEmpty ? tappable : Semantics(label: tooltip!, child: tappable);
  }
}

/// دائرة الحرف الأول من اسم المستخدم.
class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.name, required this.size, required this.fontSize});
  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
        style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: c.onAccent),
      ),
    );
  }
}

/// القائمة الجانبية الداكنة.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.space,
    required this.openSec,
    required this.hasPerm,
    required this.userName,
    required this.onGo,
    required this.onToggle,
    required this.onLogout,
    this.rail = false,
    this.width = ImdSizes.sideWidth,
  });

  /// عرض القائمة الكاملة — يسحبه المستخدم بفاصلٍ قابلٍ للسحب.
  final double width;

  /// أيقوناتٌ بلا أسماء — لشاشةٍ لا تتسع لـ٢٩٠ بكسل من قائمة.
  final bool rail;

  /// بنود المساحة التي يملكها المستخدم، مسطَّحةً — وهي ما يُرسم في القضيب.
  List<_MenuItem> _items() => [
        for (final sec in _menu)
          for (final i in sec.items)
            if (AppSpace.shows(i.space, space) && hasPerm(i.id)) i,
      ];

  /// هل للمساحة قسمٌ واحد فيُعرض مسطّحًا بلا رأس؟
  static bool _flat(String space, bool Function(String) hasPerm) =>
      _menu
          .where((s) => s.items
              .any((i) => AppSpace.shows(i.space, space) && hasPerm(i.id)))
          .length <=
      1;

  final String page;

  /// مساحة العمل الحالية — تُرشَّح بها بنود القائمة.
  final String space;

  final String? openSec;
  final bool Function(String page) hasPerm;
  final String userName;
  final ValueChanged<String> onGo;
  final ValueChanged<String> onToggle;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    if (rail) return _rail(context);
    final c = context.imd;
    return Container(
      width: width,
      decoration: BoxDecoration(
        // تدرّج خفيف من لون الشريط إلى أغمق منه أسفلًا.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.side.withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
            c.sideDeep
                .withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
          ],
        ),
        border: BorderDirectional(start: BorderSide(color: c.sideLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      // الرأس والتذييل ثابتان، والقائمة بينهما تتمرّر. لا `IntrinsicHeight` هنا:
      // `AnimatedSize` تُرجع ارتفاع الطفل الهدف لا المتحرّك، فيفيض العمود
      // مؤقتًا عند طيّ قسمٍ أو التبديل بين قسمين.
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  // الرئيسية بندٌ مستقلٌّ دائمًا في القسمين — لا قائمة فرعية
                  // تحته؛ وجهتها تتبع القسم النشط (`dash` أو `fuelDashboard`).
                  _SideTile(
                    icon: 'home',
                    label: 'الرئيسية',
                    kind: _SideKind.home,
                    on: page == (space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
                    onTap: () =>
                        onGo(space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
                  ),
                  // قسمٌ بقائمةٍ واحدة يُعرض مسطّحًا: رأسُ قسمٍ يُطوى على كل
                  // ما في الشاشة ليس تصنيفًا، بل نقرةٌ تُدفع قبل كل شيء.
                  if (_flat(space, hasPerm))
                    for (final i in _menu.expand((x) => x.items).where(
                        (i) => AppSpace.shows(i.space, space) && hasPerm(i.id)))
                      _SideTile(
                        icon: i.icon,
                        label: i.name,
                        kind: _SideKind.item,
                        on: page == i.id,
                        onTap: () => onGo(i.id),
                      )
                  else
                    for (final s in _menu)
                      if (s.items.any((i) =>
                          AppSpace.shows(i.space, space) && hasPerm(i.id))) ...[
                        _SideTile(
                          icon: s.icon,
                          label: s.name,
                          kind: _SideKind.header,
                          open: openSec == s.sec,
                          onTap: () => onToggle(s.sec),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.ease,
                          alignment: Alignment.topCenter,
                          child: openSec == s.sec
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final i in s.items.where((i) =>
                                        AppSpace.shows(i.space, space) &&
                                        hasPerm(i.id)))
                                      _SideTile(
                                        icon: i.icon,
                                        label: i.name,
                                        kind: _SideKind.item,
                                        on: page == i.id,
                                        onTap: () => onGo(i.id),
                                      ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.sideLine))),
                    // بلا بطاقة مستخدمٍ هنا: الاسم والصلاحية معروضان في
                    // الشريط العلوي، وهذا الشريط لا يحمل غير الخروج فيقصر
                    // ارتفاعه لصالح القائمة.
                    child: _SideTile(
                        icon: 'lock',
                        label: 'تسجيل خروج',
                        kind: _SideKind.logout,
                        onTap: onLogout),
                  ),
                ],
      ),
    );
  }
  /// شريطٌ ضيّق: أيقونةٌ لكل باب واسمُه في تلميحها.
  ///
  /// **الأيقونة تكفي لمن يعرف طريقه.** من يفتح الشاشة كل يوم لا يقرأ اسم
  /// البند، بل يقصد موضعه؛ والاسم يبقى في التلميح لمن يبحث.
  Widget _rail(BuildContext context) {
    final c = context.imd;
    final items = _items();
    return Container(
      width: 68,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.side.withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
            c.sideDeep
                .withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
          ],
        ),
        border: BorderDirectional(start: BorderSide(color: c.sideLine)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        _RailTile(
          icon: 'home',
          label: 'الرئيسية',
          on: page == (space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
          onTap: () => onGo(space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              for (final i in items)
                _RailTile(
                  icon: i.icon,
                  label: i.name,
                  on: page == i.id,
                  onTap: () => onGo(i.id),
                ),
            ]),
          ),
        ),
        _RailTile(
          icon: 'log-out',
          label: 'تسجيل الخروج',
          on: false,
          danger: true,
          onTap: onLogout,
        ),
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// أيقونةُ بابٍ في الشريط الضيّق، واسمُه في تلميحها.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = danger ? c.danger : (on ? c.sideText : c.sideMuted);
    return Semantics(
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 48,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.sideActive : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ImdIcon(icon, size: 19, color: fg),
        ),
      ),
    );
  }
}

/// شريطٌ سفليّ لأشهر أبواب القسم — وما وراءها في الدرج.
///
/// **الإبهام لا يبلغ أعلى الشاشة.** الدرج وحده يكلّف نقرتين لكل تنقّل، وأمينُ
/// المستودع ينتقل بين الصرف والاستلام عشرات المرات في الساعة.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.space,
    required this.page,
    required this.hasPerm,
    required this.onGo,
    required this.onMore,
  });

  final String space;
  final String page;
  final bool Function(String) hasPerm;
  final ValueChanged<String> onGo;
  final VoidCallback onMore;

  /// أبوابٌ ثلاثة بعد الرئيسية — والرابع «المزيد» يفتح القائمة كاملة.
  // أُشير بها إلى معرّفات أبوابٍ حذفناها من الشجرة عند تفكيكها إلى بنودٍ
  // مباشرة؛ استُبدلت ببنودٍ فرديةٍ ما زالت في `_menu` تمثّل نفس الغرض
  // (أشهر ما يُفتح) بدل أن تختفي صفوف المفضّلة في الشريط السفليّ صامتة.
  static const Map<String, List<String>> _main = {
    AppSpace.supply: ['issue', 'receive', 'balances'],
    AppSpace.fuel: ['fuelIssue', 'fuelAllocations', 'fuelDaily'],
  };

  static _MenuItem? _itemOf(String id) {
    for (final sec in _menu) {
      for (final i in sec.items) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final ids = [
      for (final id in _main[space] ?? const <String>[])
        if (hasPerm(id)) id,
    ];
    final items = [
      for (final id in ids)
        if (_itemOf(id) != null) _itemOf(id)!,
    ];
    final home = space == AppSpace.fuel ? 'fuelDashboard' : 'dash';

    return Container(
      decoration: BoxDecoration(
        color: c.side,
        border: Border(top: BorderSide(color: c.sideLine)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            _BottomTile(
              icon: 'home',
              label: 'الرئيسية',
              on: page == 'dash' || page == home,
              onTap: () => onGo(home),
            ),
            for (final i in items)
              _BottomTile(
                icon: i.icon,
                label: i.name,
                on: page == i.id,
                onTap: () => onGo(i.id),
              ),
            _BottomTile(
              icon: 'menu',
              label: 'المزيد',
              on: false,
              onTap: onMore,
            ),
          ]),
        ),
      ),
    );
  }
}

class _BottomTile extends StatelessWidget {
  const _BottomTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = on ? c.accent : c.sideMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImdIcon(icon, size: 19, color: fg),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SideKind { home, header, item, logout }

class _SideTile extends StatefulWidget {
  const _SideTile({
    required this.icon,
    required this.label,
    required this.kind,
    required this.onTap,
    this.on = false,
    this.open = false,
  });

  final String icon;
  final String label;
  final _SideKind kind;
  final VoidCallback onTap;
  final bool on;
  final bool open;

  @override
  State<_SideTile> createState() => _SideTileState();
}

class _SideTileState extends State<_SideTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    late final Color bg;
    late final Color fg;
    Border? border;
    late final EdgeInsets pad;
    late final EdgeInsets margin;
    late final double fs;
    late final FontWeight fw;
    late final double radius;
    Color? iconColor;
    switch (widget.kind) {
      case _SideKind.home:
        bg = _hover ? c.sideHover : c.side2;
        fg = c.sideBright;
        border = Border.all(color: c.sideBorder);
        pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 13);
        margin = const EdgeInsets.only(bottom: 10);
        fs = 14;
        fw = FontWeight.w600;
        radius = 10;
      case _SideKind.header:
        bg = _hover ? c.sideHover : Colors.transparent;
        fg = (_hover || widget.open) ? c.sideBright : c.sideMuted;
        pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 11);
        margin = const EdgeInsets.only(top: 6, bottom: 4);
        fs = 12.5;
        fw = FontWeight.w600;
        radius = 8;
      case _SideKind.item:
        bg = widget.on
            ? c.sideActive
            : (_hover ? c.sideHover : Colors.transparent);
        fg = (widget.on || _hover)
            ? c.sideBright
            : c.sideText.withValues(alpha: .86);
        iconColor = widget.on ? ImdColors.dark.accentHover : null;
        pad = const EdgeInsets.only(left: 10, top: 11, right: 14, bottom: 11);
        margin = const EdgeInsets.only(left: 4, top: 1, bottom: 1);
        fs = 13.5;
        fw = FontWeight.w500;
        radius = 8;
      case _SideKind.logout:
        bg = _hover ? c.sideHover : Colors.transparent;
        fg = c.sideText;
        border = Border.all(color: _hover ? c.sideMuted : c.sideBorder);
        pad = const EdgeInsets.all(13);
        margin = EdgeInsets.zero;
        fs = 14;
        fw = FontWeight.w600;
        radius = 10;
    }
    final isItem = widget.kind == _SideKind.item;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: margin,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: isItem ? null : border,
          ),
          foregroundDecoration: isItem && widget.on
              ? BoxDecoration(
                  border: Border(
                      right: BorderSide(color: ImdColors.dark.accentHover, width: 2)),
                )
              : null,
          padding: pad,
          child: Row(
            mainAxisAlignment: widget.kind == _SideKind.logout
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              ImdIcon(widget.icon, size: fs * 1.1, color: iconColor ?? fg),
              SizedBox(
                  width: widget.kind == _SideKind.header
                      ? 8
                      : (widget.kind == _SideKind.logout ? 6 : 10)),
              if (widget.kind == _SideKind.logout)
                Text(widget.label,
                    style: TextStyle(
                        fontSize: fs, fontWeight: fw, color: fg, height: 1.6))
              else
                Expanded(
                  child: Text(widget.label,
                      style: TextStyle(
                          fontSize: fs, fontWeight: fw, color: fg, height: 1.6),
                      overflow: TextOverflow.ellipsis),
                ),
              if (widget.kind == _SideKind.header) ...[
                ImdIcon(widget.open ? 'chevron-down' : 'chevron-left',
                    size: 12, color: c.sideMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// رسالة «صلاحية غير متاحة 🔒».
class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return const ImdPage(
      children: [
        ImdPageTitle(title: 'صلاحية غير متاحة', icon: 'lock'),
        ImdEmptyState.noPermission(
          message: 'لا تملك صلاحية الوصول إلى هذه الشاشة. اطلب من مدير النظام منحك الصلاحية المناسبة.',
        ),
      ],
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon();

  @override
  Widget build(BuildContext context) {
    return const ImdPage(
      children: [
        ImdPageTitle(
            title: 'قريبًا',
            icon: 'alert',
            subtitle: 'هذه الشاشة ستُبنى في خطوة قادمة'),
      ],
    );
  }
}


/// فاصلٌ رأسيّ رفيع بين القائمة الجانبية والمحتوى يُسحب لتغيير عرضها —
/// مؤشّر تغيير الحجم وخطٌّ بلون العلامة عند المرور، كنوافذ سطح المكتب.
class _SideSplitter extends StatefulWidget {
  const _SideSplitter({required this.onDrag, required this.onEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  State<_SideSplitter> createState() => _SideSplitterState();
}

class _SideSplitterState extends State<_SideSplitter> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = _hover || _drag;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _drag = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _drag = false);
          widget.onEnd();
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: on ? 3 : 1,
              color: on ? c.accent : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
