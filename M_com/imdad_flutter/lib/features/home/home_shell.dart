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
import '../../core/theme/app_theme.dart';
import '../../core/ui/imd_density.dart';
import '../../core/ui/imd_section_theme.dart';
import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_menu_bar.dart';
import '../../core/ui/imd_page_tabs.dart';
import '../../core/ui/imd_screen_actions.dart';
import '../../core/ui/imd_status_bar.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';
import '../../core/ui/imd_context_menu.dart';
import '../../core/ui/imd_widgets.dart';
import '../../domain/access_control.dart';
import '../../domain/app_space.dart';
import '../../domain/menu_doors.dart';
import '../../domain/section_block.dart';
import '../../data/sync/auto_sync.dart';
import '../search/search_modal.dart';
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
import '../linkages/linkages_screen.dart';
import '../cables/cables_screen.dart';
import '../linkages/personnel_screen.dart';
import '../archive/electronic_archive_screen.dart';
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

part 'shell/home_shell_menu.dart';
part 'shell/home_shell_topbar.dart';
part 'shell/home_shell_sidebar.dart';
part 'shell/home_shell_bottom_nav.dart';
part 'shell/home_shell_placeholders.dart';


/// التنقل بين الشاشات من داخل أي شاشة.
class ImdNav {
  ImdNav(this._go, this._current);
  final void Function(String page) _go;
  final String Function() _current;

  void go(String page) => _go(page);
  String get current => _current();

  static ImdNav of(BuildContext context) => context.read<ImdNav>();
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

/// حالة تبويبات قسمٍ واحد — انظر [_HomeShellState._spaces].
class _SpaceState {
  _SpaceState(String space) : openSec = space == AppSpace.fuel ? 'fuelMoves' : 'basic';

  String page = 'dash';
  final List<String> open = ['dash'];
  final Map<String, int> gen = {};
  final Map<String, ImdRecordSink> sinks = {};
  final Set<String> stale = {};
  String? openSec;
}

/// الهيكل الرئيسي بعد الدخول:
/// شريط علوي، قائمة جانبية داكنة بأقسام قابلة للطي (قسم واحد مفتوح)، ومنطقة المحتوى.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// حالة كل قسم (الإمداد/المحروقات) على حدة: تبويباته المفتوحة وصفحته الظاهرة
  /// وأرقام تحديثه وتنبيهات تقادمه. **القسمان يحيَيان معًا**: التبديل بينهما
  /// يُخفي أحدهما ولا يهدمه، فيعود كل قسمٍ بتبويباته وما في صفحاته من إدخال.
  final Map<String, _SpaceState> _spaces = {};

  _SpaceState _stateOf(String space) => _spaces.putIfAbsent(space, () => _SpaceState(space));

  /// حالة القسم الظاهر.
  _SpaceState get _st => _stateOf(_space ?? AppSpace.supply);

  /// الصفحة الظاهرة في القسم الظاهر.
  String get _page => _st.page;
  set _page(String v) => _st.page = v;

  /// الصفحات المفتوحة بحالتها (تبويبات سطح المكتب) في القسم الظاهر.
  ///
  /// **لماذا تبقى حيّةً:** التنقّل بين الشاشات كان يهدم السابقة (`ValueKey(_page)`)
  /// فيضيع سندٌ نصف مملوء بمجرد نظرةٍ إلى الأرصدة. الآن تبقى مبنيّةً مخفيّة
  /// ([ImdPageHost]) وتعود كما تُركت.
  List<String> get _open => _st.open;

  /// أقصى صفحاتٍ مفتوحة في كل قسم: كل واحدةٍ تحمل حالتها وبياناتها في الذاكرة.
  static const int _maxOpen = 8;

  /// رقم إعادة بناء كل صفحة — زيادته تُنشئ الصفحة من جديد (تحديث).
  Map<String, int> get _gen => _st.gen;

  /// عدّاد سجلات كل صفحة مفتوحة لشريط الحالة.
  Map<String, ImdRecordSink> get _sinks => _st.sinks;

  /// صفحاتٌ مخفيّة تغيّرت البيانات بعد إخفائها.
  Set<String> get _stale => _st.stale;
  StreamSubscription<Object?>? _dbSub;

  /// آخر قياسٍ للقشرة — يقرّره البناء، ويقرؤه التنقّل لتقييد عدد الصفحات.
  bool _handheld = false;

  String? get _openSec => _st.openSec;
  set _openSec(String? v) => _st.openSec = v;

  // سمة المحروقات تُبنى مرةً لكل (سطوع، خط): بناؤها في كل إطار يعيد اشتقاق
  // لوحة ألوان Material كاملة.
  ThemeData? _fuelTheme;
  bool? _fuelDark;
  String? _fuelFont;

  /// سمة القسم: الإمداد هو سمة التطبيق نفسها. والمحروقات تتبعه افتراضًا —
  /// تطبيقٌ واحدٌ بهويّةٍ واحدة — إلا أن يُطلب تمييزه بلوحته البرتقالية من
  /// الإعدادات ([ImdSectionTheme.distinctFuel]).
  ThemeData _themeFor(BuildContext context, String space) {
    final base = Theme.of(context);
    if (space != AppSpace.fuel || !ImdSectionTheme.distinctFuel) return base;
    final dark = base.brightness == Brightness.dark;
    final font = base.textTheme.bodyMedium?.fontFamily ?? ImdFonts.defaultFamily;
    if (_fuelTheme == null || _fuelDark != dark || _fuelFont != font) {
      _fuelTheme = AppTheme.fuelSection(dark: dark, font: font);
      _fuelDark = dark;
      _fuelFont = font;
    }
    return _fuelTheme!;
  }

  static const double _sideMin = 220;
  static const double _sideMax = 420;
  static const String _sideKey = 'imdad.sideWidth';
  double _sideWidth = ImdSizes.sideWidth;

  Future<void> _loadSideWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_sideKey);
    final collapsed = prefs.getBool(_collapsedKey);
    if (!mounted) return;
    setState(() {
      if (w != null) _sideWidth = w.clamp(_sideMin, _sideMax);
      _userCollapsed = collapsed;
    });
  }

  /// طيّ القائمة الجانبية يدويًّا: `null` = تلقائي (شريط أيقونات بين 900 و1150، وقائمةٌ
  /// كاملة فوقها)، و`true`/`false` = اختيار المستخدم يسري على كل العروض فوق 900.
  static const String _collapsedKey = 'imdad.sideCollapsed';
  bool? _userCollapsed;

  Future<void> _setCollapsed(bool v) async {
    setState(() => _userCollapsed = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapsedKey, v);
    } catch (_) {
      // تفضيل شكلٍ فقط: فشل حفظه لا يمنع الطيّ في هذه الجلسة.
    }
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
    ImdDensity.load();
    _watchData();
    // دور المستخدم أو حجب أقسامه تغيّر (مزامنة): تُعاد الواجهة فيسري فورًا.
    _userVersion = context.read<AuthService>().userVersion..addListener(_onUserChanged);
    // البحث العام (Ctrl+K): إجراءُ الإطار — يفتح أي شاشةٍ فلا تملكه شاشةٌ
    // واحدة. يُسجَّل هنا مرةً، فلا يعمل الاختصار قبل الدخول.
    _actions = ImdScreenActions.maybeOf(context)?..onSearch = _openSearch;
  }

  ImdScreenActions? _actions;

  void _openSearch() => showSearchModal(context, onOpenPage: _go);

  late final ValueNotifier<int> _userVersion;

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  /// أي كتابةٍ في القاعدة (من هذه الشاشات أو من المزامنة) تجعل الصفحات
  /// **المخفيّة** مشتبهةً بالتقادم؛ الظاهرة هي مصدر الكتابة فلا تُعلَّم.
  void _watchData() {
    final db = context.read<AppDatabase>();
    _dbSub = db.tableUpdates().listen((_) {
      if (!mounted) return;
      final current = _space ?? AppSpace.supply;
      var changed = false;
      for (final e in _spaces.entries) {
        for (final p in e.value.open) {
          // الظاهر هو مصدر الكتابة؛ وكل ما عداه (حتى صفحات القسم الآخر) مشتبهٌ به.
          if (e.key == current && p == e.value.page) continue;
          changed = e.value.stale.add(p) || changed;
        }
      }
      if (changed) setState(() {});
    });
  }

  ImdRecordSink _sinkOf(String page) => _sinks.putIfAbsent(page, ImdRecordSink.new);

  /// يُسقط صفحةً مفتوحة بحالتها كلّها.
  void _drop(String page) {
    _open.remove(page);
    _stale.remove(page);
    _gen.remove(page);
    // يُتخلَّص منه بعد الإطار: جداول الصفحة المهدومة ما زالت تُبلّغ عنه حتى تُفكَّك.
    final sink = _sinks.remove(page);
    if (sink != null) WidgetsBinding.instance.addPostFrameCallback((_) => sink.dispose());
  }

  void _closePage(String page) {
    if (_open.length <= 1) return;
    setState(() {
      final i = _open.indexOf(page);
      _drop(page);
      if (page == _page) _page = _open[i.clamp(0, _open.length - 1)];
    });
  }

  void _closeOthers(String keep) => setState(() {
        for (final p in List.of(_open)) {
          if (p != keep) _drop(p);
        }
        _page = keep;
      });

  void _refreshPage(String page) => setState(() {
        _gen[page] = (_gen[page] ?? 0) + 1;
        _stale.remove(page);
      });

  static String _titleOf(String page) {
    if (page == 'dash') return 'الرئيسية';
    final id = _menuPageOf(page);
    for (final sec in _menu) {
      for (final it in sec.items) {
        if (it.id == id) return it.name;
      }
    }
    return page;
  }

  static String? _iconOf(String page) {
    if (page == 'dash') return 'home';
    final id = _menuPageOf(page);
    for (final sec in _menu) {
      for (final it in sec.items) {
        if (it.id == id) return it.icon;
      }
    }
    return null;
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
    // لا تُصفَّر الحالة: العودة إلى قسمٍ زاره المستخدم تُظهر تبويباته كما تركها.
    setState(() => _space = space);
  }

  /// يبدّل إلى القسم التالي مباشرةً (دون شاشة الاختيار) ويحفظ اختياره. القسم
  /// الذي غادره يبقى حيًّا بتبويباته وبياناته.
  Future<void> _switchSpace() async {
    final auth = context.read<AuthService>();
    final available = AppSpace.availableFor((p) => _hasPerm(auth, p));
    if (available.length < 2) return;
    final current = _space ?? available.first;
    final next = available[(available.indexOf(current) + 1) % available.length];
    await _pickSpace(next);
  }

  @override
  void dispose() {
    _actions?.onSearch = null;
    _sessionTimer?.cancel();
    _dbSub?.cancel();
    // المرجع محفوظ منذ initState: القراءة من السياق أثناء dispose غير آمنة.
    _userVersion.removeListener(_onUserChanged);
    for (final st in _spaces.values) {
      for (final s in st.sinks.values) {
        s.dispose();
      }
    }
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
    setState(() {
      if (!_open.contains(page)) {
        _open.add(page);
        // الجوال صفحةٌ واحدة كما كان: لا شريط تبويبات يتيح العودة لما أُخفي.
        final cap = _handheld ? 1 : _maxOpen;
        while (_open.length > cap) {
          _drop(_open.firstWhere((p) => p != page));
        }
      }
      _page = page;
    });
    // يُغلق الدرج نفسه لا «أعلى مسار»: `Navigator.pop` كانت تغلق أي حوارٍ
    // مفتوح فوق الشاشة بدل الدرج.
    _scaffoldKey.currentState?.closeEndDrawer();
  }

  bool _isAdmin(AuthService auth) => UserRole.isAdmin(auth.currentUser?.role);

  /// صفحات بلا صلاحية خاصة بها تتبع صلاحية صفحة أخرى، فلا يلزم تعديل الأدوار.
  static const _permPage = {
    'lanSync': SysPerm.sync,
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
    // شاشتا المالية والتسليح صلاحيتهما صلاحية «الارتباطات» نفسها.
    'linkFinances': 'linkages',
    'linkArmament': 'linkages',
  };

  /// هل قسم العمل [space] (`supply`/`fuel`) محجوبٌ عن المستخدم الحالي؟
  bool _spaceBlocked(AuthService auth, String space) {
    final u = auth.currentUser;
    if (u == null) return false;
    return SectionBlock.blocksSection(role: u.role, blockedJson: u.sectionBlocked, section: space);
  }

  bool _hasPerm(AuthService auth, String page,
      [String action = PermAction.view]) {
    // الحجب أولًا وعلى **هوية الصفحة الأصلية**: التطبيع التالي قد يحوّلها إلى
    // صلاحيةٍ لا تُنبئ بقسمها (`lanSync` ← `sys.sync`).
    final blockedUser = auth.currentUser;
    if (blockedUser != null &&
        SectionBlock.blocksPage(role: blockedUser.role, blockedJson: blockedUser.sectionBlocked, page: page)) {
      return false;
    }
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
        isOwner: UserRole.isOwner(user.role),
        permissions: perms,
        page: page,
        action: action);
  }

  Widget _pageBody(String page, String space) {
    switch (page) {
      case 'dash':
        // «الرئيسية» تتبع القسم: لوحة الإمداد في مكانها، ولوحة المحروقات في
        // مكانها — ولا يرى صاحب قسمٍ لوحةَ القسم الآخر.
        return space == AppSpace.fuel
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
      case 'cables':
        return const CablesScreen();
      case 'archive':
        return const ElectronicArchiveScreen();
      case 'personnel':
        return const PersonnelStrengthScreen();
      // «linkages» معرّفٌ قديم (مركز الارتباطات) يفتح المالية.
      case 'linkages':
      case 'linkFinances':
        return const LinkFinancesScreen();
      case 'linkArmament':
        return const LinkArmamentScreen();
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
    final handheld = width <= _Shell.rail;
    final rail = !handheld && (_userCollapsed ?? !wide);

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
    // قسمٌ حُجب عن المستخدم أثناء جلسته (مزامنة/تعديل المالك) لا يبقى مفتوحًا:
    // يُنقل إلى أول قسمٍ متاح بعد هذا الإطار. وإطارٌ واحد يُبنى فيه القسم المحجوب
    // صفحاتُه كلها «لا صلاحية» (الحجب fail-closed في `_hasPerm`).
    if (_space != null && available.isNotEmpty && !available.contains(_space)) {
      final fallback = available.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _space != fallback) setState(() => _space = fallback);
      });
    }
    final space = _space ?? AppSpace.supply;

    _handheld = handheld;
    final themed = _themeFor(context, space);
    final sc = themed.extension<ImdColors>() ?? c;

    // كل قسمٍ زاره المستخدم يبقى مبنيًّا (الظاهر وحده مرئي) بسمته: التبديل بين
    // الإمداد والمحروقات لا يهدم تبويباتهما. على الجوال صفحةٌ واحدة فقط للقسم
    // الظاهر — ما أُخفي لا شريط يعيده، فلا يُبقى حيًّا بلا فائدة.
    Widget sectionStack(String sp, _SpaceState st) {
      final isActive = sp == space;
      final pages = handheld ? (isActive ? [st.page] : <String>[]) : List<String>.of(st.open);
      return Offstage(
        key: ValueKey('space:$sp'),
        offstage: !isActive,
        child: TickerMode(
          enabled: isActive,
          child: ExcludeFocus(
            excluding: !isActive,
            child: Theme(
              data: _themeFor(context, sp),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final p in pages)
                    ImdPageHost(
                      key: ValueKey('host:$sp:$p'),
                      active: isActive && p == st.page,
                      sink: st.sinks.putIfAbsent(p, ImdRecordSink.new),
                      child: KeyedSubtree(
                        key: ValueKey('$sp:$p#${st.gen[p] ?? 0}'),
                        // «الرئيسية» مفتوحةٌ لكل مستخدم، إلا أن يُحجب قسمُها نفسه.
                        child: ((p == 'dash' && !_spaceBlocked(auth, sp)) || _hasPerm(auth, p))
                            ? _pageBody(p, sp)
                            : const _NoAccess(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // الحالة تُنشأ للقسم الظاهر قبل البناء حتى يظهر في `_spaces`.
    _stateOf(space);
    final body = Stack(
      fit: StackFit.expand,
      children: [for (final e in _spaces.entries) sectionStack(e.key, e.value)],
    );
    final sync = context.watch<AutoSyncService>();
    final syncFailed = !sync.isRunning && sync.failed;

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
          backgroundColor: sc.bg,
          // الدرج يحمل القائمة كاملةً في اليد: الشريط السفليّ لأشهر الأبواب،
          // وما وراءها يُفتح منه.
          endDrawer: handheld
              ? Drawer(
                  width: ImdSizes.drawerWidth(context),
                  backgroundColor: sc.side,
                  child: _Sidebar(
                    // داخل الدرج تملأ القائمةُ عرضَه؛ ولو فرضت ٢٩٠ على درجٍ
                    // أضيق منها فاضت أفقيًّا.
                    width: null,
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
              if (handheld)
                _Topbar(
                  userName: side.userName,
                  showBurger: true,
                  onBurger: () => _scaffoldKey.currentState?.openEndDrawer(),
                  onOpenPage: _go,
                  space: _space ?? '',
                  canSwitch: available.length > 1,
                  onSwitchSpace: _switchSpace,
                )
              else
                _DesktopBar(
                  userName: side.userName,
                  collapsed: rail,
                  onToggleSide: () => _setCollapsed(!rail),
                  pages: [
                    for (final p in _open)
                      ImdOpenPage(id: p, title: _titleOf(p), icon: _iconOf(p), stale: _stale.contains(p)),
                  ],
                  activeId: _page,
                  onSelect: _go,
                  onClose: _closePage,
                  onCloseOthers: _closeOthers,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!handheld && _stale.contains(_page))
                            ImdStaleBanner(
                              onRefresh: () => _refreshPage(_page),
                              onDismiss: () => setState(() => _stale.remove(_page)),
                            ),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!handheld)
                ImdStatusBar(
                  records: _sinkOf(_page),
                  onConnectionTap: () => _go('lanSync'),
                  connection: sync.isRunning
                      ? 'جارٍ التزامن'
                      : !sync.enabled
                          ? 'العمل محلي — المزامنة متوقفة'
                          : syncFailed
                              ? 'تعذّرت آخر مزامنة'
                              : sync.lastAt == null
                                  ? 'متصل — بانتظار أول مزامنة'
                                  : 'متصل — آخر مزامنة ${DateFormat('HH:mm').format(sync.lastAt!)}',
                  connectionOk: sync.isRunning
                      ? true
                      : !sync.enabled
                          ? null
                          : !syncFailed,
                ),
            ],
          ),
        ),
      ),
    );

    // الإطار كله (الشريط الجانبي والعلوي والتبويبات) بسمة القسم الظاهر.
    return Theme(data: themed, child: shell);
  }
}
