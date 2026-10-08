import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/error_log.dart';
import 'core/print/print_preview.dart';
import 'core/security/auth_service.dart';
import 'core/security/idle_lock.dart';
import 'core/security/owner_key.dart';
import 'core/ui/imd_density.dart';
import 'core/ui/imd_section_theme.dart';
import 'core/ui/imd_fonts.dart';
import 'core/ui/imd_layout.dart';
import 'core/ui/imd_screen_actions.dart';
import 'core/ui/imd_style.dart';
import 'core/ui/imd_widgets.dart';
import 'core/ui/imd_window.dart';
import 'core/theme/app_theme.dart';
import 'data/backup/backup_scheduler.dart';
import 'data/db/app_database.dart';
import 'data/db/db_cipher.dart';
import 'data/repos/audit_repo.dart';
import 'data/repos/camp_ledger_repo.dart';
import 'data/repos/settings_repo.dart';
import 'data/sync/auto_sync.dart';
import 'features/auth/idle_lock_host.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'core/security/device_activation.dart';
import 'features/settings/device_activation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // نسخة التوزيع بلا مفتاح مالك تعمل بلا تفعيل على أي جهاز — لا تُشغَّل أبدًا.
  // (الفحص المبكر قبل البناء: `dart run tool/check_release.dart`.)
  if (kReleaseMode && !OwnerKey.isConfigured) {
    throw StateError(
      'نسخة الإصدار بُنيت بلا مفتاح مالك (OwnerKey.publicKey فارغ). '
      'ولّد مفتاحًا بـ tool/make_owner_key.dart وأعد البناء.',
    );
  }

  final db = AppDatabase();
  _wireErrorLogger(db);
  ErrorLogger.installGlobalHandlers();
  final auth = AuthService(db, isBranchDevice: () => DeviceActivation(db).isBranch());
  final restored = await auth.restoreSession();
  await _cleanupPlainBackups(db);
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
        title: 'Emdad System',
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
    await ImdWindow.syncMica(ImdTheme.parse(identity.themePref));
  }

  runApp(ImdadApp(
    db: db,
    auth: auth,
    signedIn: restored != null,
    themeMode: ImdTheme.parse(identity.themePref),
    fontFamily: identity.fontFamily,
  ));
}

/// يربط [ErrorLogger] بسجل التدقيق (للحرجة) وبإشعار المستخدم (SnackBar).
void _wireErrorLogger(AppDatabase db) {
  ErrorLogger.sink = (e) => AuditRepo(db).log(
        action: 'error.critical',
        entityType: 'نظام',
        summary: '${e.source}: ${e.message.length > 160 ? '${e.message.substring(0, 160)}…' : e.message}',
        details: {'source': e.source, 'type': e.type},
      );
  ErrorLogger.userNotifier = (message) {
    final ctx = imdNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) showImdToast(ctx, '⚠ $message', error: false);
  };
}

/// تنظيف الإقلاع: نسخ `*.plain.bak` غير المشفّرة التي تركها الترحيل القديم تُحذف
/// متى سلمت القاعدة المشفّرة، ويُسجَّل ذلك في سجل التدقيق. لا يمنع الإقلاع أبدًا.
Future<void> _cleanupPlainBackups(AppDatabase db) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, DbCipher.fileName));
    final removed = DbCipher.removeStalePlainBackups(file, await DbCipher.loadKey());
    if (removed.isEmpty) return;
    await AuditRepo(db).log(
      action: 'db.cleanup_plain_backup',
      entityType: 'قاعدة البيانات',
      summary: 'حُذفت ${removed.length} نسخة غير مشفّرة قديمة (plain.bak) بعد التأكد من سلامة القاعدة المشفّرة',
      details: {'files': [for (final f in removed) p.basename(f)]},
      risk: AuditRepo.riskHigh,
    );
  } catch (e) {
    debugPrint('تعذّر تنظيف النسخ غير المشفّرة: $e');
  }
}

/// تفضيل السمة المحفوظ في شاشة الهوية — يطبَّق على التطبيق كله
/// عبر `MaterialApp.themeMode`.
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

  /// القفل التلقائي بعد الخمول — يعمل ما دام المستخدم مسجَّلًا.
  late final IdleLock _idle = IdleLock(widget.db);

  /// النسخ الاحتياطي المشفّر المجدول — يعمل في الخلفية ما دام التطبيق مفتوحًا.
  late final BackupScheduler _backup = BackupScheduler(widget.db);

  /// المزامنة التلقائية تبدأ مع التطبيق لا مع شاشة المزامنة: جهاز الفرع قد لا
  /// يفتح تلك الشاشة شهرًا كاملًا، والمقصود أن يزامن بلا أن يفتحها أحد.
  late final AutoSyncService _autoSync = AutoSyncService(widget.db);

  /// سجلّ إجراءات الشاشة النشطة لاختصارات لوحة المفاتيح — انظر
  /// [ImdScreenActions].
  final _screenActions = ImdScreenActions();

  @override
  void initState() {
    super.initState();
    // تفضيلات الشكل (نمط كلاسيكي/كثافة) قبل أول إطار ما أمكن حتى لا يومض الشكل الآخر.
    ImdStyle.load();
    ImdDensity.load();
    ImdSectionTheme.load();
    // تنسيق الأرقام من القاعدة: معيارُ الجهة لا تفضيلُ جهاز، فيسبق أول رقمٍ
    // يُرسم. وفشلُه يُبقي الافتراضات ولا يمنع الإقلاع.
    SettingsRepo(widget.db).loadNumbers().catchError((_) {});
    // الإعداد يُقرأ من القاعدة ثم تبدأ المراقبة إن كانت الجلسة مستعادة.
    _idle.load().then((_) {
      if (mounted && _signedIn) _idle.activate();
    });
    // بعد أول إطار: الإقلاع لا ينتظر الشبكة، وفشلها لا يمنع ظهور الواجهة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSync.refresh();
      _backup.start();
      // تصفية الشهر المنقضي إن أُذن بها — تتحقق بنفسها من الإذن وانقضاء الشهر.
      CampLedgerRepo(widget.db).autoSettleIfDue().catchError(
            (_) => const SettlementResult(ok: false, error: ''),
          );
    });
    // زر إغلاق النافذة لا يمرّ بـ `PopScope`، فيُعترض هنا ليُسأل عن التأكيد
    // كما يُسأل زر الرجوع على الهاتف.
    // ما يُنهى قبل الإغلاق: الجلسة، ومؤقّت المزامنة وخادمها ومقبس اكتشافها —
    // على كل المنصات، فالخروج من أندرويد بزر الرجوع يمسح الجلسة أيضًا.
    ImdWindow.onBeforeExit = _shutdown;
    if (Platform.isWindows) {
      windowManager.addListener(this);
      // الإضافة غير مُهيّأة في بيئة الاختبار، فالفشل هنا لا يمنع التطبيق.
      windowManager.setPreventClose(true).catchError((_) {});
      // لون Mica يتبع السمة: فاتحٌ أو داكن.
      _theme.addListener(_syncMica);
    }
  }

  void _syncMica() => ImdWindow.syncMica(_theme.mode);

  /// تسجيل الخروج: من الشريط الرئيسي أو من غطاء القفل.
  Future<void> _signOut() async {
    _idle.deactivate();
    await widget.auth.logout();
    if (mounted) setState(() => _signedIn = false);
    await ImdWindow.login();
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      _theme.removeListener(_syncMica);
    }
    _autoSync.dispose();
    _idle.dispose();
    _backup.dispose();
    super.dispose();
  }

  /// إنهاء ما يُبقي العملية حيّةً بعد إغلاق النافذة.
  ///
  /// خادم المزامنة يستمع على منفذ، ومقبس الاكتشاف على آخر، ومؤقّتها يدور.
  /// هدمُ النافذة وحده يترك هذه قائمةً فتتأخّر نهاية العملية ثوانيَ تبدو
  /// تعليقًا. وكلٌّ منها يُنهى على حدة فلا يمنع تعثّرُ واحدٍ إنهاءَ الباقي.
  ///
  /// والجلسة تُمسح كذلك: الخروج الصريح (زر الإغلاق أو «خروج») ينهي الجلسة،
  /// فيُطلب الدخول عند فتح التطبيق من جديد. كانت الجلسة تبقى 12 ساعة فيدخل
  /// التطبيق بلا كلمة مرور بعد الإغلاق.
  Future<void> _shutdown() async {
    await Future.wait([
      _autoSync.shutdown().catchError((_) {}),
      widget.auth.logout().catchError((_) {}),
    ]);
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
        Provider<ImdScreenActions>.value(value: _screenActions),
        ChangeNotifierProvider<ImdTheme>.value(value: _theme),
        ChangeNotifierProvider<AutoSyncService>.value(value: _autoSync),
        ChangeNotifierProvider<IdleLock>.value(value: _idle),
        ChangeNotifierProvider<BackupScheduler>.value(value: _backup),
      ],
      child: Consumer<ImdTheme>(
        builder: (context, theme, _) => MaterialApp(
        // تحتاجه نافذة معاينة الطباعة (تُفتح من طبقة الطباعة بلا سياق).
        navigatorKey: imdNavigatorKey,
        title: 'Emdad System',
        debugShowCheckedModeBanner: false,
        theme: ImdStyle.classic ? AppTheme.classic(font: ImdStyle.classicFont) : AppTheme.light(font: theme.font),
        darkTheme: AppTheme.dark(font: theme.font),
        themeMode: theme.mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final content = child ?? const SizedBox.shrink();
          // بعد تسجيل الدخول: رصد الخمول وغطاء القفل فوق كل شيء (حتى الحوارات).
          final body = _signedIn
              ? IdleLockHost(lock: _idle, auth: widget.auth, onSignOut: _signOut, child: content)
              : content;
          return MediaQuery(
            data: imdClampedMediaQuery(MediaQuery.of(context)),
            child: Directionality(
            textDirection: TextDirection.rtl,
            child: ImdShortcuts.supported
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                          context.read<ImdScreenActions>().onSave?.call(),
                      const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
                          context.read<ImdScreenActions>().onPrint?.call(),
                      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                          context.read<ImdScreenActions>().onNewDoc?.call(),
                      const SingleActivator(LogicalKeyboardKey.f5): () =>
                          context.read<ImdScreenActions>().onRefresh?.call(),
                      // البحث العام: يسجّله الإطار لا الشاشة، فلا يعمل قبل الدخول.
                      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                          context.read<ImdScreenActions>().onSearch?.call(),
                    },
                    child: Focus(autofocus: true, child: body),
                  )
                : body,
          ));
        },
        home: _signedIn
            ? HomeShell(onSignOut: _signOut)
            : _DeviceGate(
                db: widget.db,
                auth: widget.auth,
                onSignedIn: () async {
                  await ImdWindow.main();
                  _idle.activate();
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
