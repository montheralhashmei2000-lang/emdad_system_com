import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';
import '../../core/ui/imd_widgets.dart';
import '../../domain/access_control.dart';
import '../catalog/assets_screen.dart';
import '../catalog/kitchens_screen.dart';
import '../catalog/items_screen.dart';
import '../catalog/suppliers_screen.dart';
import '../catalog/units_screen.dart';
import '../catalog/warehouses_screen.dart';
import '../daily/daily_operations_screen.dart';
import '../daily/meal_plan_screen.dart';
import '../daily/kitchen_log_screen.dart';
import '../daily/ratios_screen.dart';
import '../daily/strength_screen.dart';
import '../insights/activity_intel_screen.dart';
import '../insights/executive_cmd_screen.dart';
import '../insights/health_ops_screen.dart';
import '../insights/sensitive_ops_screen.dart';
import '../inventory/ration_order_screen.dart';
import '../inventory/issue_screen.dart';
import '../inventory/opening_screen.dart';
import '../inventory/pending_screen.dart';
import '../inventory/receive_screen.dart';
import '../inventory/returns_screen.dart';
import '../inventory/transfer_screen.dart';
import '../alerts/stock_alerts_screen.dart';
import 'notification_bell.dart';
import '../reports/camp_ledger_screen.dart';
import '../reports/camp_settlement_screen.dart';
import '../reports/actual_entitlement_screen.dart';
import '../reports/balances_screen.dart';
import '../reports/reports_center_screen.dart';
import '../settings/audit_screen.dart';
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
  const _MenuItem(this.id, this.icon, this.name);
  final String id;
  final String icon;
  final String name;
}

class _MenuSection {
  const _MenuSection(this.sec, this.icon, this.name, this.items);
  final String sec;
  final String icon;
  final String name;
  final List<_MenuItem> items;
}

const _menu = <_MenuSection>[
  _MenuSection('basic', 'settings', 'البيانات الأساسية', [
    _MenuItem('items', 'package', 'إدارة الأصناف'),
    _MenuItem('suppliers', 'truck', 'الموردون'),
    _MenuItem('units', 'users', 'الوحدات المستفيدة'),
    _MenuItem('stores', 'warehouse', 'المستودعات'),
    _MenuItem('kitchens', 'utensils', 'المطابخ والأفران'),
    _MenuItem('assets', 'package', 'الأصول الثابتة'),
  ]),
  _MenuSection('stock', 'package', 'العمليات المخزنية', [
    _MenuItem('pendingOrders', 'bell', 'أوامر التوريد المعلقة'),
    _MenuItem('receive', 'download', 'استلام بضاعة'),
    _MenuItem('issue', 'upload', 'صرف بضاعة'),
    _MenuItem('transfer', 'refresh', 'تحويل مخزني'),
    _MenuItem('returns', 'undo', 'المرتجعات'),
    _MenuItem('opening', 'clipboard', 'الأرصدة الافتتاحية'),
    _MenuItem('rationOrders', 'clipboard', 'طلبيات الإعاشة'),
  ]),
  _MenuSection('daily', 'chart', 'التشغيل اليومي', [
    _MenuItem('feeding', 'calendar', 'التغذية اليومية (حصر القوة)'),
    _MenuItem('dailyOperations', 'calendar', 'التخطيط والتشغيل اليومي'),
    _MenuItem('ratios', 'scale', 'نسب الاستهلاك'),
  ]),
  _MenuSection('reports', 'trending', 'التقارير والجرد', [
    _MenuItem('balances', 'calculator', 'الأرصدة الحالية'),
    _MenuItem('stockAlerts', 'alert', 'تنبيهات المخزون'),
    _MenuItem('stocktake', 'clipboard', 'جرد المخزون'),
    _MenuItem('reports', 'chart', 'التقارير'),
    _MenuItem('auditTrail', 'scan', 'سجل النشاط والتدقيق'),
    _MenuItem('activityIntel', 'bulb', 'ذكاء النشاط والانحرافات'),
    _MenuItem('executiveCmd', 'target', 'مركز القيادة التنفيذية'),
    _MenuItem('sensitiveOps', 'alert', 'التغييرات الحساسة والمراجعة'),
    _MenuItem('healthOps', 'shield', 'صحة النظام والعمليات'),
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
  }

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
  static const _permPage = {'lanSync': 'settings', 'stockAlerts': 'balances'};

  bool _hasPerm(AuthService auth, String page, [String action = PermAction.view]) {
    page = _permPage[page] ?? page;
    if (page == 'dailyOperations') {
      return _hasPerm(auth, 'mealPlans', action) ||
          _hasPerm(auth, 'kitchenLog', action);
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
        return const DashboardScreen();
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
        return const DailyOperationsScreen();
      case 'assets':
        return const AssetsScreen();
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
      case 'stocktake':
        return const StocktakeScreen();
      case 'reports':
        return const ReportsCenterScreen();
      case 'auditTrail':
        return const AuditScreen();
      case 'activityIntel':
        return const ActivityIntelScreen();
      case 'executiveCmd':
        return const ExecutiveCmdScreen();
      case 'sensitiveOps':
        return const SensitiveOpsScreen();
      case 'healthOps':
        return const HealthOpsScreen();
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
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final c = context.imd;
    final wide = MediaQuery.sizeOf(context).width > 920;

    final allowed = _page == 'dash' || _hasPerm(auth, _page);
    final body = allowed ? _pageBody(_page) : const _NoAccess();

    final side = _Sidebar(
      page: _page,
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

    return Provider<ImdNav>.value(
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
          endDrawer: wide
              ? null
              : Drawer(
                  width: ImdSizes.sideWidth,
                  backgroundColor: c.side,
                  child: side),
          body: Column(
            children: [
              _Topbar(
                userName: side.userName,
                showBurger: !wide,
                onBurger: () => _scaffoldKey.currentState?.openEndDrawer(),
                onOpenPage: _go,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide) side,
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
  }
}

/// `.topbar`
class _Topbar extends StatelessWidget {
  const _Topbar({
    required this.userName,
    required this.showBurger,
    required this.onBurger,
    required this.onOpenPage,
  });

  final String userName;
  final bool showBurger;
  final VoidCallback onBurger;
  final ValueChanged<String> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
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
            const SizedBox(width: 12),
          ],
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'نظام '),
              TextSpan(
                  text: 'الإمداد والتموين',
                  style:
                      TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
            ]),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: c.text2),
          ),
          const Spacer(),
          NotificationBell(onOpenPage: onOpenPage),
          const SizedBox(width: 8),
          Container(
            height: 40,
            padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 10, 4),
            decoration: BoxDecoration(
                color: c.subtle, borderRadius: BorderRadius.circular(99)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(name: userName, size: 32, fontSize: 14),
                const SizedBox(width: 10),
                Text(userName,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.text)),
                const SizedBox(width: 10),
                const _StatusPill(label: 'IAM محمي'),
                if (MediaQuery.sizeOf(context).width > 560) ...[
                  const SizedBox(width: 10),
                  const _StatusPill(label: 'متصل — متزامن'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
          color: c.isDark ? c.accent : const Color(0xFF0F766E),
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
    required this.openSec,
    required this.isAdmin,
    required this.hasPerm,
    required this.userName,
    required this.onGo,
    required this.onToggle,
    required this.onLogout,
  });

  final String page;
  final String? openSec;
  final bool isAdmin;
  final bool Function(String page) hasPerm;
  final String userName;
  final ValueChanged<String> onGo;
  final ValueChanged<String> onToggle;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
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
      child: LayoutBuilder(
        builder: (context, cons) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: cons.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.sideLine))),
                    child: const Text('نظام الإمداد والتموين',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                  _SideTile(
                    icon: 'home',
                    label: 'الرئيسية',
                    kind: _SideKind.home,
                    on: page == 'dash',
                    onTap: () => onGo('dash'),
                  ),
                  for (final s in _menu) ...[
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final i
                                    in s.items.where((i) => hasPerm(i.id)))
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
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    _SideTile(
                      icon: 'users',
                      label: 'مركز الصلاحيات والوصول',
                      kind: _SideKind.item,
                      on: page == 'usersAccess',
                      onTap: () => onGo('usersAccess'),
                    ),
                  ],
                  const Spacer(),
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
            ),
          ),
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
        bg = widget.on ? c.sideActive : (_hover ? c.sideHover : Colors.transparent);
        fg = (widget.on || _hover) ? Colors.white : c.sideText.withValues(alpha: .86);
        iconColor = widget.on ? const Color(0xFF5EEAD4) : null;
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
              ? const BoxDecoration(
                  border: Border(
                      right: BorderSide(color: Color(0xFF2DD4BF), width: 2)),
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
        ImdPanel(
          child: Text(
              'لا تملك صلاحية الوصول إلى هذه الشاشة. اطلب من مدير النظام منحك الصلاحية المناسبة.'),
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
