import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';
import '../../core/ui/imd_widgets.dart';
import '../../domain/access_control.dart';
import '../../domain/app_space.dart';
import '../../domain/menu_doors.dart';
import 'space_chooser_screen.dart';
import '../fuel/fuel_allocations_screen.dart';
import '../fuel/fuel_groups.dart';
import 'supply_groups.dart';
import '../fuel/fuel_settings_screen.dart';
import '../fuel/fuel_dashboard_screen.dart';
import '../fuel/fuel_moves_screen.dart';
import '../fuel/fuel_stocktake_screen.dart';
import '../daily/meal_plan_screen.dart';
import '../daily/kitchen_log_screen.dart';
import 'notification_bell.dart';
import '../reports/camp_ledger_screen.dart';
import '../reports/camp_settlement_screen.dart';
import '../reports/actual_entitlement_screen.dart';
import '../settings/branding_screen.dart';
import '../settings/forms_designer_screen.dart';
import '../settings/device_activation_screen.dart';
import '../settings/verify_sign_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/users_screen.dart';
import '../stocktake/stocktake_screen.dart';
import '../sync/sync_screen.dart';
import 'dashboard_screen.dart';

/// التنقل بين الشاشات من داخل أي شاشة (`curPage='x';renderPage()` في الويب).
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
  // قسم الإمداد: تسعةُ أبوابٍ لا ستةٌ وعشرون بندًا.
  //
  // **الشريط فهرسٌ لا سجل.** سندات الحركة الخمسة يحرّرها أمينُ مستودعٍ واحد
  // في جلسةٍ واحدة، والأدلّة الستة تُعرَّف مرةً وتُقرأ دائمًا، والرقابة خمسُ
  // نظراتٍ على السجل نفسه — فكلُّ مجموعةٍ بابٌ بتبويباته.
  _MenuSection('stock', 'package', 'العمليات المخزنية', [
    _MenuItem('supplyMoves', 'swap', 'حركة المخزون'),
    _MenuItem('supplyOrders', 'clipboard', 'الطلبيات'),
    _MenuItem('stocktake', 'clipboard', 'جرد المخزون'),
  ]),
  _MenuSection('basic', 'database', 'البيانات الأساسية', [
    _MenuItem('supplyData', 'database', 'الأدلّة الأساسية'),
  ]),
  // قسم المحروقات: ستّة أبوابٍ لا ثلاثة عشر بندًا.
  //
  // **الشريط فهرسٌ لا سجل.** الصرف والتوريد والتحويل والافتتاحي حركةٌ واحدة
  // يديرها رجلٌ واحد، والمستودعات والوحدات والمركبات أدلّةٌ تُعرَّف مرةً،
  // والتقارير نظراتٌ على البيانات نفسها — فكلُّ ثلاثةٍ بابٌ بتبويباته.
  _MenuSection('fuel', 'zap', 'المحروقات', [
    _MenuItem('fuelDashboard', 'home', 'الرئيسية', space: AppSpace.fuel),
    _MenuItem('fuelMoves', 'swap', 'حركة المحروقات', space: AppSpace.fuel),
    _MenuItem('fuelAllocations', 'clipboard', 'التفريدة', space: AppSpace.fuel),
    _MenuItem('fuelData', 'database', 'البيانات الأساسية',
        space: AppSpace.fuel),
    _MenuItem('fuelReports', 'chart', 'التقارير', space: AppSpace.fuel),
    _MenuItem('fuelStocktake', 'clipboard', 'الجرد المخزني',
        space: AppSpace.fuel),
    _MenuItem('fuelSettings', 'settings', 'الإعدادات', space: AppSpace.fuel),
  ]),
  _MenuSection('daily', 'chart', 'التشغيل اليومي', [
    _MenuItem('supplyDaily', 'calendar', 'التشغيل اليومي'),
  ]),
  _MenuSection('reports', 'trending', 'التقارير والرقابة', [
    _MenuItem('supplyReports', 'chart', 'التقارير'),
    _MenuItem('supplyAudit', 'scan', 'الرقابة والتدقيق'),
  ]),
  _MenuSection('settings', 'wrench', 'الإعدادات', [
    _MenuItem('settings', 'settings', 'الإعدادات'),
  ]),
];

/// الهيكل الرئيسي بعد الدخول — مطابق لإطار نسخة الويب:
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
      _openSec = space == AppSpace.fuel ? 'fuel' : 'basic';
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
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
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
    // والتقارير الخمسة تحت صلاحية التقارير، عدا الاستهلاك فله صلاحيته.
    'fuelDaily': 'fuelReports',
    'fuelStocks': 'fuelReports',
    'fuelLedger': 'fuelReports',
    'fuelPlanVsIssued': 'fuelReports',
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
        return const SupplyDataScreen(initialTab: 'items');
      case 'suppliers':
        return const SupplyDataScreen(initialTab: 'suppliers');
      case 'kitchens':
        return const SupplyDataScreen(initialTab: 'kitchens');
      case 'units':
        return const SupplyDataScreen(initialTab: 'units');
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
        return const SupplyDataScreen(initialTab: 'assets');
      case 'fuelDashboard':
        return const FuelDashboardScreen();
      case 'fuelIssue':
        return const FuelMovesScreen(initialTab: 'issue');
      case 'fuelSupply':
        return const FuelMovesScreen(initialTab: 'supply');
      case 'fuelTransfer':
        return const FuelMovesScreen(initialTab: 'transfer');
      case 'fuelOpening':
        return const FuelMovesScreen(initialTab: 'opening');
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
        return const FuelDataScreen(initialTab: 'warehouses');
      case 'fuelUnits':
        return const FuelDataScreen(initialTab: 'units');
      case 'fuelVehicles':
        return const FuelDataScreen(initialTab: 'vehicles');
      case 'fuelConsumption':
        return const FuelReportsHubScreen(initialTab: 'consumption');
      case 'fuelDaily':
        return const FuelReportsHubScreen(initialTab: 'daily');
      case 'fuelStocks':
        return const FuelReportsHubScreen(initialTab: 'stocks');
      case 'fuelLedger':
        return const FuelReportsHubScreen(initialTab: 'ledger');
      case 'fuelPlanVsIssued':
        return const FuelReportsHubScreen(initialTab: 'plan');
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
        return const SupplyOrdersScreen(initialTab: 'rationOrders');
      case 'stores':
        return const SupplyDataScreen(initialTab: 'stores');
      case 'pendingOrders':
        return const SupplyOrdersScreen(initialTab: 'pendingOrders');
      case 'receive':
        return const SupplyMovesScreen(initialTab: 'receive');
      case 'issue':
        return const SupplyMovesScreen(initialTab: 'issue');
      case 'transfer':
        return const SupplyMovesScreen(initialTab: 'transfer');
      case 'returns':
        return const SupplyMovesScreen(initialTab: 'returns');
      case 'opening':
        return const SupplyMovesScreen(initialTab: 'opening');
      case 'feeding':
        return const SupplyDailyScreen(initialTab: 'feeding');
      case 'kitchenLog':
        return const KitchenLogScreen();
      case 'ratios':
        return const SupplyDailyScreen(initialTab: 'ratios');
      case 'balances':
        return const SupplyReportsScreen(initialTab: 'balances');
      case 'stockAlerts':
        return const SupplyReportsScreen(initialTab: 'stockAlerts');
      case 'stocktake':
        return const StocktakeScreen();
      case 'reports':
        return const SupplyReportsScreen();
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
      case 'formsDesigner':
        return const FormsDesignerScreen();
      case 'deviceActivation':
        return const DeviceActivationScreen();
      case 'verifySign':
        return const VerifySignScreen();
      case 'branding':
        return const BrandingScreen();
      case 'usersAccess':
        return const UsersScreen();
      case 'lanSync':
        return const SyncScreen();
    }
    // نفس رسالة الويب للشاشات غير المبنية بعد.
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
    // سمة القسم تُلفّ القشرة كلها: كل شاشة داخله تأخذ لوحته بلا تعديل فيها،
    // لأن ألوانها كلها تمرّ بـ`context.imd`.
    final fuelSpace = space == AppSpace.fuel;

    final allowed = _page == 'dash' || _hasPerm(auth, _page);
    final body = allowed ? _pageBody(_page) : const _NoAccess();

    final side = _Sidebar(
      page: _page,
      space: space,
      rail: rail,
      canSwitch: available.length > 1,
      onSwitchSpace: _switchSpace,
      openSec: _openSec,
      isAdmin: _isAdmin(auth),
      hasPerm: (p) => _hasPerm(auth, p),
      userName: auth.currentUser?.name.isNotEmpty == true
          ? auth.currentUser!.name
          : (auth.currentUser?.username ?? ''),
      onGo: _go,
      onToggle: (sec) =>
          setState(() => _openSec = _openSec == sec ? null : sec),
      onLogout: widget.onSignOut,
    );

    final shell = Provider<ImdNav>.value(
      value: _nav,
      child: PopScope(
        // زر الرجوع كان يُنهي التطبيق بضغطة واحدة من أي شاشة. الآن يعود إلى
        // الرئيسية أولًا، ولا يخرج من الرئيسية إلا بتأكيد صريح.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (_page != 'dash') {
            _go('dash');
            return;
          }
          if (await imdConfirm(context, 'إغلاق النظام؟', ok: 'خروج')) {
            // `SystemNavigator.pop` تُنهي تطبيق أندرويد، أما على ويندوز
            // فتُطلب ولا يستجيب لها أحد: يظلّ المستخدم ينقر ويظنّ التطبيق
            // معلّقًا. وهدمُ النافذة هو إنهاؤه هناك.
            if (ImdWindow.supported) {
              await ImdWindow.exit();
            } else {
              await SystemNavigator.pop();
            }
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
                    page: _page,
                    space: space,
                    canSwitch: available.length > 1,
                    onSwitchSpace: _switchSpace,
                    openSec: _openSec,
                    isAdmin: _isAdmin(auth),
                    hasPerm: (p) => _hasPerm(auth, p),
                    userName: side.userName,
                    onGo: (id) {
                      Navigator.of(context).maybePop();
                      _go(id);
                    },
                    onToggle: (sec) => setState(
                        () => _openSec = _openSec == sec ? null : sec),
                    onLogout: widget.onSignOut,
                  ),
                )
              : null,
          bottomNavigationBar: handheld
              ? _BottomNav(
                  space: space,
                  page: _page,
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
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!handheld) side,
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

    // سمة القسم تُلفّ كل شيء: الشريط والمحتوى والحوارات تأخذ لوحته، فلا
    // تُعدَّل شاشة واحدة من شاشاته — ألوانها كلها تمرّ بـ`context.imd`.
    return fuelSpace
        ? Theme(
            data: AppTheme.fuel(
              // الخط يتبع اختيار المستخدم في السمة العامة.
              font: Theme.of(context).textTheme.bodyMedium?.fontFamily ??
                  ImdFonts.defaultFamily,
            ),
            child: shell,
          )
        : shell;
  }
}

/// `.topbar`
class _Topbar extends StatelessWidget {
  const _Topbar({
    required this.userName,
    required this.showBurger,
    required this.onBurger,
    required this.onOpenPage,
    required this.space,
  });

  final String userName;
  final bool showBurger;
  final VoidCallback onBurger;
  final ValueChanged<String> onOpenPage;

  /// القسم الذي يقف فيه المستخدم — الجرس يخصّ ما بين يديه.
  final String space;

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

      return Container(
        height: ImdSizes.topbarHeight,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: c.isDark ? const Color(0xEB171717) : const Color(0xEBFFFFFF),
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
            const Spacer(),
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
                    const _StatusPill(label: 'متصل — متزامن'),
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

/// `.device-sync`
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
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
          decoration: const BoxDecoration(
              color: Color(0xFF35C978), shape: BoxShape.circle),
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
  }
}

/// `.avatar`
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
            color: c.isDark ? const Color(0xFF0B1F1C) : Colors.white),
      ),
    );
  }
}

/// `.side` — القائمة الجانبية الداكنة.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.space,
    required this.canSwitch,
    required this.onSwitchSpace,
    required this.openSec,
    required this.isAdmin,
    required this.hasPerm,
    required this.userName,
    required this.onGo,
    required this.onToggle,
    required this.onLogout,
    this.rail = false,
  });

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

  /// زر التبديل لا يظهر لمن يملك مساحةً واحدة: تبديلٌ إلى لا شيء.
  final bool canSwitch;
  final VoidCallback onSwitchSpace;
  final String? openSec;
  final bool isAdmin;
  final bool Function(String page) hasPerm;
  final String userName;
  final ValueChanged<String> onGo;
  final ValueChanged<String> onToggle;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    if (rail) return _rail(context);
    final c = context.imd;
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Container(
      width: ImdSizes.sideWidth,
      decoration: BoxDecoration(
        // تدرّج خفيف من لون الشريط إلى أغمق منه أسفلًا.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.side, Color.lerp(c.side, Colors.black, .22)!],
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
                  Container(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.sideLine))),
                    child: Column(children: [
                      Text('نظام الإمداد والتموين',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .2,
                              color: c.sideMuted)),
                      const SizedBox(height: 4),
                      Text(AppSpace.label(space),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: c.sideText)),
                      const SizedBox(height: 10),
                      // القسم الحالي معروضٌ دائمًا: من يعمل في قسمين يحتاج أن
                      // يعرف في أيّهما هو قبل أن يكتب سندًا في الخطأ.
                      MouseRegion(
                        cursor: canSwitch
                            ? SystemMouseCursors.click
                            : MouseCursor.defer,
                        child: GestureDetector(
                          onTap: canSwitch ? onSwitchSpace : null,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: c.sideHover,
                              border: Border.all(color: c.sideBorder),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              ImdIcon(
                                  canSwitch
                                      ? 'swap'
                                      : (AppSpace.icons[space] ?? 'package'),
                                  size: 12,
                                  color: c.sideMuted),
                              const SizedBox(width: 6),
                              Text(canSwitch ? 'تبديل القسم' : 'قسم واحد',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.sideMuted)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  // زر الرئيسية العام لا يظهر في المحروقات: قائمته تبدأ به
                  // أصلًا، فزرّان لشاشةٍ واحدة يربكان لا يُيسّران.
                  if (space != AppSpace.fuel)
                    _SideTile(
                      icon: 'home',
                      label: 'الرئيسية',
                      kind: _SideKind.home,
                      on: page == 'dash',
                      onTap: () => onGo('dash'),
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
                        on: page == i.id ||
                            (i.id == 'fuelDashboard' && page == 'dash'),
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
                  // مركز الصلاحيات شأنُ النظام كله، وبابه قسم الإمداد:
                  // إظهاره في المحروقات يخلط قسمًا بقسم بعد أن فُصلا.
                  if (isAdmin && space != AppSpace.fuel) ...[
                    const SizedBox(height: 12),
                    _SideTile(
                      icon: 'users',
                      label: 'مركز الصلاحيات والوصول',
                      kind: _SideKind.item,
                      on: page == 'usersAccess',
                      onTap: () => onGo('usersAccess'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: c.side2,
                            border: Border.all(color: c.sideBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            _Avatar(name: userName, size: 40, fontSize: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                  Row(children: [
                                    ImdIcon(mobile ? 'phone' : 'monitor',
                                        size: 12, color: c.sideMuted),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '${mobile ? 'جوال' : 'كمبيوتر'} • ${isAdmin ? 'مدير النظام' : 'مستخدم'}',
                                        style: TextStyle(
                                            fontSize: 11, color: c.sideMuted),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        _SideTile(
                            icon: 'lock',
                            label: 'تسجيل خروج',
                            kind: _SideKind.logout,
                            onTap: onLogout),
                      ],
                    ),
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
          colors: [c.side, Color.lerp(c.side, Colors.black, .22)!],
        ),
        border: BorderDirectional(start: BorderSide(color: c.sideLine)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        if (space != AppSpace.fuel)
          _RailTile(
            icon: 'home',
            label: 'الرئيسية',
            on: page == 'dash',
            onTap: () => onGo('dash'),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              for (final i in items)
                _RailTile(
                  icon: i.icon,
                  label: i.name,
                  on: page == i.id ||
                      (i.id == 'fuelDashboard' && page == 'dash'),
                  onTap: () => onGo(i.id),
                ),
            ]),
          ),
        ),
        if (isAdmin && space != AppSpace.fuel)
          _RailTile(
            icon: 'users',
            label: 'مركز الصلاحيات والوصول',
            on: page == 'usersAccess',
            onTap: () => onGo('usersAccess'),
          ),
        if (canSwitch)
          _RailTile(
            icon: 'swap',
            label: 'تبديل القسم',
            on: false,
            onTap: onSwitchSpace,
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
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 300),
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
  static const Map<String, List<String>> _main = {
    AppSpace.supply: ['supplyMoves', 'supplyOrders', 'supplyReports'],
    AppSpace.fuel: ['fuelMoves', 'fuelAllocations', 'fuelReports'],
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
        fg = Colors.white;
        border = Border.all(color: c.sideBorder);
        pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 13);
        margin = const EdgeInsets.only(bottom: 10);
        fs = 14;
        fw = FontWeight.w600;
        radius = 10;
      case _SideKind.header:
        bg = _hover ? c.sideHover : Colors.transparent;
        fg = (_hover || widget.open) ? Colors.white : c.sideMuted;
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
            ? Colors.white
            : c.sideText.withValues(alpha: .86);
        iconColor = widget.on ? ImdColors.dark.accentHover : null;
        pad = const EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11)
            .resolve(TextDirection.rtl);
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
      cursor: SystemMouseCursors.click,
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

/// نفس رسالة الويب: «صلاحية غير متاحة 🔒».
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
