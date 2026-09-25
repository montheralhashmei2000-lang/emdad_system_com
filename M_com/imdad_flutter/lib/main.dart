import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/print/print_preview.dart';
import 'core/security/auth_service.dart';
import 'core/ui/imd_fonts.dart';
import 'core/ui/imd_widgets.dart';
import 'core/ui/imd_window.dart';
import 'core/theme/app_theme.dart';
import 'data/db/app_database.dart';
import 'data/repos/camp_ledger_repo.dart';
import 'data/repos/settings_repo.dart';
import 'data/sync/auto_sync.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/settings/device_activation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final auth = AuthService(db);
  final restored = await auth.restoreSession();
  final identity = await SettingsRepo(db).identity();

  if (ImdWindow.supported) {
    // تظهر النافذة من البداية بوضعها الصحيح: بطاقة الدخول وحدها، أو الرئيسية
    // مكبّرة بشريط عنوانها. (الجهاز الجديد يعرض بوابة التفعيل، وهي شاشة كاملة.)
    final compact = restored == null && await auth.hasAnyUser();
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: compact ? ImdWindow.loginSize : const Size(1280, 820),
        minimumSize: compact ? ImdWindow.loginSize : const Size(360, 600),
        title: 'نظام الإمداد والتموين',
        center: true,
        titleBarStyle: compact ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: !compact,
      ),
      () async {
        if (compact) {
          await ImdWindow.login();
        } else {
          await ImdWindow.main();
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(ImdadApp(
    db: db,
    auth: auth,
    signedIn: restored != null,
    themeMode: ImdTheme.parse(identity.themePref),
    fontFamily: identity.fontFamily,
  ));
}

/// تفضيل السمة المحفوظ في شاشة الهوية (`APP_CFG.themePref`) — يطبَّق على التطبيق كله.
/// الويب يطبّقه عبر `applyBranding()`، وهنا عبر `MaterialApp.themeMode`.
class ImdTheme extends ChangeNotifier {
  ImdTheme(this._mode, [String font = ImdFonts.defaultFamily])
      : _font = ImdFonts.normalize(font);

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  String _font;

  /// خط الواجهة المختار — يسري على التطبيق كله فور حفظه، بلا إعادة تشغيل.
  String get font => _font;

  void applyFont(String family) {
    final next = ImdFonts.normalize(family);
    if (next == _font) return;
    _font = next;
    notifyListeners();
  }

  static ThemeMode parse(String pref) => switch (pref) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  void apply(String pref) {
    final next = parse(pref);
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
  }
}

class ImdadApp extends StatefulWidget {
  const ImdadApp({
    super.key,
    required this.db,
    required this.auth,
    required this.signedIn,
    this.themeMode = ThemeMode.system,
    this.fontFamily = ImdFonts.defaultFamily,
  });

  final AppDatabase db;
  final AuthService auth;
  final bool signedIn;
  final ThemeMode themeMode;
  final String fontFamily;

  @override
  State<ImdadApp> createState() => _ImdadAppState();
}

class _ImdadAppState extends State<ImdadApp> with WindowListener {
  late bool _signedIn = widget.signedIn;
  late final ImdTheme _theme = ImdTheme(widget.themeMode, widget.fontFamily);

  /// المزامنة التلقائية تبدأ مع التطبيق لا مع شاشة المزامنة: جهاز الفرع قد لا
  /// يفتح تلك الشاشة شهرًا كاملًا، والمقصود أن يزامن بلا أن يفتحها أحد.
  late final AutoSyncService _autoSync = AutoSyncService(widget.db);

  @override
  void initState() {
    super.initState();
    // بعد أول إطار: الإقلاع لا ينتظر الشبكة، وفشلها لا يمنع ظهور الواجهة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSync.refresh();
      // تصفية الشهر المنقضي إن أُذن بها — تتحقق بنفسها من الإذن وانقضاء الشهر.
      CampLedgerRepo(widget.db).autoSettleIfDue().catchError(
            (_) => const SettlementResult(ok: false, error: ''),
          );
    });
    // زر إغلاق النافذة لا يمرّ بـ `PopScope`، فيُعترض هنا ليُسأل عن التأكيد
    // كما يُسأل زر الرجوع على الهاتف.
    if (!kIsWeb && Platform.isWindows) {
      windowManager.addListener(this);
      // الإضافة غير مُهيّأة في بيئة الاختبار، فالفشل هنا لا يمنع التطبيق.
      windowManager.setPreventClose(true).catchError((_) {});
      // ما يُنهى قبل الإغلاق: مؤقّت المزامنة وخادمها ومقبس اكتشافها.
      ImdWindow.onBeforeExit = _shutdown;
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) windowManager.removeListener(this);
    _autoSync.dispose();
    super.dispose();
  }

  /// إنهاء ما يُبقي العملية حيّةً بعد إغلاق النافذة.
  ///
  /// خادم المزامنة يستمع على منفذ، ومقبس الاكتشاف على آخر، ومؤقّتها يدور.
  /// هدمُ النافذة وحده يترك هذه قائمةً فتتأخّر نهاية العملية ثوانيَ تبدو
  /// تعليقًا. وكلٌّ منها يُنهى على حدة فلا يمنع تعثّرُ واحدٍ إنهاءَ الباقي.
  Future<void> _shutdown() async {
    try {
      await _autoSync.shutdown();
    } catch (_) {}
  }

  @override
  void onWindowClose() async {
    if (!await windowManager.isPreventClose()) return;
    final context = imdNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await ImdWindow.exit();
      return;
    }
    if (await imdConfirm(context, 'إغلاق النظام؟', ok: 'خروج')) {
      await ImdWindow.exit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: widget.db),
        Provider<AuthService>.value(value: widget.auth),
        ChangeNotifierProvider<ImdTheme>.value(value: _theme),
        ChangeNotifierProvider<AutoSyncService>.value(value: _autoSync),
      ],
      child: Consumer<ImdTheme>(
        builder: (context, theme, _) => MaterialApp(
        // تحتاجه نافذة معاينة الطباعة (تُفتح من طبقة الطباعة بلا سياق).
        navigatorKey: imdNavigatorKey,
        title: 'نظام الإمداد والتموين',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(font: theme.font),
        darkTheme: AppTheme.dark(font: theme.font),
        themeMode: theme.mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _signedIn
            ? HomeShell(onSignOut: () async {
                await widget.auth.logout();
                if (mounted) setState(() => _signedIn = false);
                await ImdWindow.login();
              })
            : _DeviceGate(
                db: widget.db,
                auth: widget.auth,
                onSignedIn: () async {
                  await ImdWindow.main();
                  if (mounted) setState(() => _signedIn = true);
                },
              ),
        ),
      ),
    );
  }
}

/// بوابة الجهاز قبل تسجيل الدخول.
///
/// **جهاز جديد بلا حسابات** لا يُستعمل إلا بعد تفعيله برمز موقَّع من الإدارة،
/// ثم يجلب الحسابات بالمزامنة — فلا ينشئ أحد لنفسه حسابًا في فرع.
///
/// **الأجهزة العاملة اليوم لا تُمسّ**: وجود حسابات يعني جهازًا قيد الخدمة، فلا
/// يُقفل بأثر رجعي عند التحديث. المدير يفعّله لاحقًا من الإعدادات.
/// وجهة البوابة — مستخرَجة لتُختبر بلا واجهة.
enum GateTarget { activation, login }

/// القرار: هل على الجهاز حساب واحد على الأقل؟ إن كان فشاشة الدخول، وإلا فالبوابة.
///
/// [fresh] تعني **لا حساب على الجهاز إطلاقًا** (`AuthService.hasAnyUser`)، لا
/// «لا حساب محلي». جهاز الفرع يستقبل حساباته بالمزامنة بمعرّفات ليست `local-`،
/// فلو قِيس بالحسابات المحلية وحدها لبقي «جديدًا» بعد أن صارت عنده حسابات.
///
/// ولماذا لا يخرج الجهاز الجديد إلى شاشة الدخول بمجرد قبول رمزه: لأن قبول
/// الرمز لا يُنشئ حسابًا. جهاز الإدارة ينشئ حساب مديره من لوحة «تهيئة جهاز
/// الإدارة» داخل البوابة نفسها، وجهاز الفرع ينتظر المزامنة. إخراجه قبل ذلك
/// يضعه أمام شاشة دخول لا حساب خلفها، فيرد عليه النظام «اسم المستخدم أو كلمة
/// المرور غير صحيحة» مهما كتب — وهي رسالة كاذبة، فلا حساب أصلًا ليخطئ فيه.
GateTarget gateFor({required bool fresh}) =>
    fresh ? GateTarget.activation : GateTarget.login;

class _DeviceGate extends StatefulWidget {
  const _DeviceGate({required this.db, required this.auth, required this.onSignedIn});

  final AppDatabase db;
  final AuthService auth;
  final VoidCallback onSignedIn;

  @override
  State<_DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<_DeviceGate> {
  bool _loading = true;
  bool _fresh = false; // لا حسابات على هذا الجهاز إطلاقًا

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final fresh = !await widget.auth.hasAnyUser();
    if (!mounted) return;
    setState(() {
      _fresh = fresh;
      _loading = false;
    });
    // بوابة التفعيل شاشة كاملة؛ الدخول نافذة صغيرة بمقاس بطاقته.
    if (gateFor(fresh: fresh) == GateTarget.activation) {
      await ImdWindow.main();
    } else {
      await ImdWindow.login();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (gateFor(fresh: _fresh) == GateTarget.activation) {
      return Scaffold(
        body: DeviceActivationScreen(standalone: true, onActivated: _check),
      );
    }
    return LoginScreen(onSignedIn: widget.onSignedIn);
  }
}
