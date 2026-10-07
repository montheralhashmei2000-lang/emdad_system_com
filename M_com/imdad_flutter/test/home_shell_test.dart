import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_page_tabs.dart';
import 'package:imdad/core/ui/imd_status_bar.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/features/home/notification_bell.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// القشرة الرئيسية.
///
/// **لم تكن مختبَرة، فمرّ فيها عطلٌ أسقط الشريط كلّه**: بابٌ في القائمة يشير
/// إلى صلاحيةٍ تحمل اسمه، ففحصُ الصلاحية استدعى نفسه بلا نهاية وفاض المكدّس.
/// وفي نسخة الإصدار لا تظهر رسالة — مستطيلٌ رماديٌّ مكان الشريط وحسب.
///
/// وهذه الاختبارات تبني القشرة فعلًا: بناؤها وحده كان يكفي لكشفه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  // الشريط العلوي يقرأ حالة المزامنة، فلا تُبنى القشرة بلا هذه الخدمة.
  // تُنشأ ولا تُشغَّل: بلا `refresh()` لا مؤقّت ولا منفذ، وحالتها الابتدائية
  // (متوقفة، بلا آخر مزامنة) هي ما يعرضه الشريط.
  late AutoSyncService autoSync;
  late ImdTheme imdTheme;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    autoSync = AutoSyncService(db);
    imdTheme = ImdTheme(ThemeMode.light);
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    // المدير يملك القسمين، فتُعرض عليه شاشة الاختيار أولًا. وحفظُ تفضيله
    // يدخلنا القشرة مباشرةً — وهي موضع الاختبار.
    SharedPreferences.setMockInitialValues({
      'imdad.space.${auth.currentUser!.id}': AppSpace.supply,
    });
  });

  tearDown(() => db.close());

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<AutoSyncService>.value(value: autoSync),
          ChangeNotifierProvider<ImdTheme>.value(value: imdTheme),
        ],
        // Consumer لا MaterialApp مباشرةً: زر تبديل السمة يستدعي
        // ImdTheme.apply، وبلا هذا لا يتبع themeMode تغيّرها فيبقى الفاتح
        // ظاهرًا مهما تبدّلت — كما في main.dart تمامًا.
        child: Consumer<ImdTheme>(
          builder: (context, theme, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: theme.mode,
            locale: const Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: HomeShell(onSignOut: () async {}),
            ),
          ),
        ),
      );

  /// القشرة تحمل مؤقّتًا دوريًّا لفحص الجلسة، فلا تسكن أبدًا ولا يصحّ فيها
  /// `pumpAndSettle`. والضخّ المعدود يكفي: العطل يقع في أول بناء.
  /// الشريط الجانبي لا يُرسم تحت عتبته، وحجم الاختبار الافتراضي دونها —
  /// فتُضبط النافذة قبل البناء وإلا اختُبر الدرج لا الشريط.
  void window(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void wideWindow(WidgetTester tester) => window(tester, 1600);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(host());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  /// المدير يملك القسمين فتُعرض عليه شاشة الاختيار؛ والدخول منها هو
  /// الطريق الذي يُبنى فيه الشريط — وفيه وقع العطل.
  Future<void> enterSupply(WidgetTester tester) async {
    await pump(tester);
    final enter = find.text('ادخل');
    if (enter.evaluate().isNotEmpty) {
      await tester.tap(enter.first, warnIfMissed: false);
      await pump(tester);
    }
  }

  testWidgets('تُبنى بلا انهيار', (tester) async {
    wideWindow(tester);

    await pump(tester);
    expect(tester.takeException(), isNull);
    // الشريط الواحد: لا اسم نظامٍ مكرَّر ولا شارة «IAM محمي» على سطح المكتب.
    expect(find.text('نظام الإمداد والتموين'), findsNothing);
    expect(find.text('IAM محمي'), findsNothing);
  });

  testWidgets('سطح المكتب: شريطٌ علويٌّ واحد يضم التبويبات والأدوات', (tester) async {
    wideWindow(tester);
    await enterSupply(tester);

    // الرئيسية تُفتح من الشريط الجانبي: لا تبويبة لها في الشريط العلوي.
    expect(find.descendant(of: find.byType(ImdPageTabs), matching: find.text('الرئيسية')), findsNothing);
    // زرّ الطيّ والأدوات (القسم، السمة، الجرس) في الصفّ نفسه.
    final tabsTop = tester.getTopLeft(find.byTooltip('طيّ القائمة')).dy;
    final bellTop = tester.getTopLeft(find.byType(NotificationBell)).dy;
    expect((tabsTop - bellTop).abs(), lessThan(ImdSizes.desktopBarHeight),
        reason: 'التبويبات والجرس في صفّين مختلفين');
    // ولا شريط تبويباتٍ مستقلّ تحت الشريط العلوي.
    final bars = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 38);
    expect(bars, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('زرّ الطيّ يحوّل القائمة الكاملة إلى أيقوناتٍ ويعيدها', (tester) async {
    window(tester, 1600);
    await enterSupply(tester);
    expect(find.text('العمليات المخزنية'), findsWidgets, reason: 'القائمة كاملةٌ في البدء');

    await tester.tap(find.byTooltip('طيّ القائمة'));
    await pump(tester);
    expect(find.text('العمليات المخزنية'), findsNothing, reason: 'بعد الطيّ أيقوناتٌ بلا أسماء');
    expect(find.byTooltip('توسيع القائمة'), findsOneWidget);

    await tester.tap(find.byTooltip('توسيع القائمة'));
    await pump(tester);
    expect(find.text('العمليات المخزنية'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الشريط يُبنى بأبوابه بعد اختيار القسم', (tester) async {
    wideWindow(tester);

    await enterSupply(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('العمليات المخزنية'), findsWidgets);
    expect(find.text('التقارير'), findsWidgets);
  });

  testWidgets('فحص الصلاحية لا يتكرر إلى ما لا نهاية', (tester) async {
    wideWindow(tester);

    // المدير يملك كل شيء، فيمرّ الفحص على كل بندٍ في القائمة — وهو الطريق
    // الذي فاض عنده المكدّس.
    await enterSupply(tester);
    final error = tester.takeException();
    expect(error, isNull, reason: '$error');
    expect(find.byType(HomeShell), findsOneWidget);
  });

  group('القشرة تتبع عرضها', () {
    testWidgets('العريضة: شريطٌ كامل بأسماء أقسامه', (tester) async {
      window(tester, 1600);
      await enterSupply(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('العمليات المخزنية'), findsWidgets);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('المتوسطة: قضيبٌ بالأيقونات بلا أسماء', (tester) async {
      // ٢٩٠ بكسل من قائمة تأكل ثلث لوحيّ عرضه ألف.
      window(tester, 1000);
      await enterSupply(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('العمليات المخزنية'), findsNothing,
          reason: 'القضيب أيقوناتٌ لا أسماء');
      // الأقسام الرئيسية وحدها تظهر أيقوناتٍ (اسمها في Semantics والتلميح)، وأبوابها
      // الفرعية لا تُرسم حتى تُفتح قائمة القسم.
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'العمليات المخزنية'),
          findsWidgets);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'استلام'),
          findsNothing);

      // نقرة أيقونة القسم تفتح قائمةً بأبوابه، واختيار بابٍ يفتح شاشته.
      await tester.tap(find.byTooltip('العمليات المخزنية').first);
      await pump(tester);
      expect(find.text('استلام'), findsWidgets);
      await tester.tap(find.text('استلام').last);
      await pump(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('اليدوية: شريطٌ سفليّ ودرج', (tester) async {
      window(tester, 700);
      await enterSupply(tester);
      expect(tester.takeException(), isNull);
      // الإبهام لا يبلغ أعلى الشاشة، فأشهر الأبواب أسفلها.
      expect(find.text('المزيد'), findsWidgets);
      expect(find.text('الرئيسية'), findsWidgets);
    });
  });

  /// عطلٌ على أندرويد: كل بندٍ في الدرج غير «الرئيسية» لا يفتح شاشته. كان `onGo`
  /// يستدعي `Navigator.maybePop()` فتعترضها `PopScope(canPop: false)` وتُعيد
  /// المستخدم إلى الرئيسية أو تسأله «إغلاق النظام؟».
  testWidgets('الدرج على الجوال يفتح شاشة البند المختار ويُغلق بلا سؤال خروج',
      (tester) async {
    window(tester, 700);
    await enterSupply(tester);

    await tester.tap(find.text('المزيد').first);
    await pump(tester);
    // قسم «البيانات الأساسية» مفتوحٌ افتراضيًّا في الدرج.
    expect(find.text('الأصناف'), findsWidgets);

    await tester.tap(find.text('الأصناف').last);
    await pump(tester);

    expect(find.text('إدارة الأصناف'), findsOneWidget, reason: 'الشاشة لم تُفتح');
    expect(find.text('إغلاق النظام؟'), findsNothing, reason: 'سؤال الخروج ظهر خطأً');
    expect(find.byType(Drawer), findsNothing, reason: 'الدرج لم يُغلق');
    expect(tester.takeException(), isNull);
  });

  testWidgets('زرّ الرجوع والدرج مفتوح يغلق الدرج ولا يغادر الشاشة', (tester) async {
    window(tester, 700);
    await enterSupply(tester);

    await tester.tap(find.text('المزيد').first);
    await pump(tester);
    expect(find.byType(Drawer), findsOneWidget);

    await tester.binding.handlePopRoute();
    await pump(tester);

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('إغلاق النظام؟'), findsNothing);
  });

  group('الإعدادات بندٌ واحد في القائمة', () {
    testWidgets('لا بنود مستقلة للهوية والتفعيل والمزامنة والمستخدمين', (tester) async {
      wideWindow(tester);
      await enterSupply(tester);

      // القسم مفتوحٌ في الشريط ليظهر ما تحته.
      await tester.tap(find.text('الإعدادات').first);
      await pump(tester);

      expect(find.text('الإعدادات العامة'), findsWidgets);
      for (final gone in [
        'هوية النظام والشعار',
        'رأس وتذييل النماذج',
        'تفعيل الأجهزة',
        'التحقق من التوقيع',
        'مزامنة الأجهزة',
        'مركز الصلاحيات والوصول',
      ]) {
        expect(find.text(gone), findsNothing, reason: '«$gone» ما زال في القائمة');
      }
    });

    testWidgets('المعرّفات القديمة تفتح الإعدادات على القسم نفسه', (tester) async {
      wideWindow(tester);
      await enterSupply(tester);

      final ctx = tester.element(find.byType(Scaffold).first);
      ImdNav.of(ctx).go('deviceActivation');
      await pump(tester);

      expect(find.text('الإعدادات'), findsWidgets);
      expect(find.textContaining('معرّف هذا الجهاز'), findsWidgets,
          reason: 'قسم التفعيل لم يُفتح داخل الإعدادات');
      expect(tester.takeException(), isNull);
    });
  });

  /// عطلٌ ظهر في نافذة ويندوز ارتفاعها ٦٩٧: `AnimatedSize` تُرجع ارتفاع الطفل
  /// الهدف لا المتحرّك، فيفيض العمود مؤقتًا (٩٢ بكسلًا) عند طيّ قسمٍ أو التبديل
  /// بين قسمين. وهو لا يظهر إلا أثناء الحركة، فيُضخّ الوقت خطوةً خطوة.
  testWidgets('الشريط الجانبي لا يفيض أثناء طيّ الأقسام وفتحها', (tester) async {
    tester.view.physicalSize = const Size(1600, 697);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await enterSupply(tester);
    expect(tester.takeException(), isNull);

    Future<void> tapSection(String name) async {
      await tester.tap(find.text(name).first, warnIfMissed: false);
      // الحركة ٢٥٠ مللي: نلتقط الفيض في أي إطارٍ منها.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        final error = tester.takeException();
        expect(error, isNull, reason: 'بعد نقر «$name»: $error');
      }
    }

    await tapSection('العمليات المخزنية');
    await tapSection('التقارير'); // تبديلٌ: أحدهما يُطوى والآخر يُفتح.
    await tapSection('العمليات المخزنية');
    await tapSection('العمليات المخزنية'); // طيٌّ بلا فتح.
  });

  /// تبديل القسم (كانت تمرّ بشاشة اختيار القسم: `Row` بـ`stretch` داخل تمريرٍ يُعطي
  /// ارتفاعًا لا نهائيًا فيفشل التخطيط. وبعدها تفشل كل حركة فأرة في
  /// `MouseTracker` (`!_debugDuringDeviceUpdate`) فيتجمّد التطبيق في وضع التطوير.
  /// لا يظهر إلا بمؤشر فأرة حقيقي، ولا يظهر بنقر اللمس الذي تستعمله بقية الاختبارات.
  testWidgets('تبديل القسم بالفأرة لا ينهار في نافذة عريضة',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await enterSupply(tester);
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> click(Finder target) async {
      final at = tester.getCenter(target.first);
      await mouse.moveTo(at);
      await tester.pump();
      await mouse.down(at);
      await mouse.up();
      await pump(tester);
    }

    // تبديل القسم انتقل إلى الشريط العلوي؛ يُعرض اسم القسم لا نصّ «تبديل
    // القسم» (ذاك في تلميح الزر وحده، كما تطلب المواصفة: اسم القسم المفتوح
    // ظاهرٌ دومًا، والتبديل فعلٌ لا عنوان).
    await click(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'تبديل القسم'));
    final error = tester.takeException();
    expect(error, isNull, reason: '$error');
    // التبديل مباشرٌ إلى القسم الآخر (المحروقات) دون المرور بشاشة الاختيار.
    expect(find.text('ادخل'), findsNothing);

    // والعودة إلى الإمداد بنقرةٍ ثانية بلا خطأ في تخطيط ولا في تتبّع الفأرة.
    await click(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'تبديل القسم'));
    final error2 = tester.takeException();
    expect(error2, isNull, reason: '$error2');
    expect(find.text('ادخل'), findsNothing);
  });

  testWidgets('كل صلاحية معرَّفة لها تسمية', (tester) async {
    // تسميةٌ ناقصة تعني بندًا لا يظهر إلا للمدير بلا قصد.
    for (final key in Perm.labels.keys) {
      expect(Perm.labels[key]!.trim(), isNotEmpty, reason: key);
    }
  });

  testWidgets('بطاقة المستخدم أسفل الشريط الجانبي: خروجٌ فقط، بلا صورة ولا اسم ولا دور',
      (tester) async {
    wideWindow(tester);
    await enterSupply(tester);
    expect(tester.takeException(), isNull);

    // الخروج باقٍ في الشريط الجانبي. والاسم يبقى ظاهرًا مرةً واحدة فقط —
    // في كبسولة الشريط العلوي التي لم تُمَسّ — لا مكرَّرًا في بطاقةٍ أسفل
    // القائمة أيضًا. أمّا الجهاز والدور («كمبيوتر»/«مدير النظام») فكانا
    // حصرًا في تلك البطاقة المحذوفة، فيغيبان كليًّا.
    expect(find.text('تسجيل خروج'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
    expect(find.textContaining('مدير النظام'), findsNothing);
    expect(find.textContaining('كمبيوتر'), findsNothing);
    expect(find.textContaining('جوال'), findsNothing);
  });

  testWidgets('الشريط العلوي: اسم القسم ظاهرٌ، وزرّ تبديل السمة موجود',
      (tester) async {
    wideWindow(tester);
    await enterSupply(tester);
    expect(tester.takeException(), isNull);

    expect(find.text(AppSpace.label(AppSpace.supply)), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is ImdIconButton && w.tooltip == 'الوضع الداكن'),
        findsOneWidget);
  });

  testWidgets('زرّ تبديل السمة يبدّل السطوع الفعلي ويحفظه', (tester) async {
    wideWindow(tester);
    await enterSupply(tester);
    expect(Theme.of(tester.element(find.byType(HomeShell))).brightness,
        Brightness.light);

    await tester.tap(find.byWidgetPredicate(
        (w) => w is ImdIconButton && w.tooltip == 'الوضع الداكن'));
    await pump(tester);

    expect(Theme.of(tester.element(find.byType(HomeShell))).brightness,
        Brightness.dark);
    expect(imdTheme.mode, ThemeMode.dark);
    expect((await SettingsRepo(db).identity()).themePref, 'dark');
    expect(tester.takeException(), isNull);
  });

  group('الصفحات المفتوحة وشريط الحالة', () {
    testWidgets('سطح المكتب: شريط تبويبات وشريط حالة بالوقت والاتصال والكثافة', (tester) async {
      wideWindow(tester);
      await enterSupply(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(ImdPageTabs), findsOneWidget);
      expect(find.byType(ImdStatusBar), findsOneWidget);
      expect(find.textContaining('المزامنة متوقفة'), findsWidgets);
      expect(find.text('كثافة عالية'), findsOneWidget);
    });

    testWidgets('فتح شاشةٍ يضيف تبويبة، والعودة تُبقي حالة الأولى', (tester) async {
      wideWindow(tester);
      await enterSupply(tester);

      // القسم الأول مفتوح: «الأصناف».
      await tester.tap(find.text('الأصناف').first);
      await pump(tester);
      final tabsAfterItems = tester.widgetList<ImdPageHost>(find.byType(ImdPageHost, skipOffstage: false)).length;
      expect(tabsAfterItems, 2, reason: 'الرئيسية + الأصناف');

      await tester.tap(find.text('الرئيسية').first);
      await pump(tester);
      expect(tester.widgetList(find.byType(ImdPageHost, skipOffstage: false)).length, 2,
          reason: 'الصفحة السابقة بقيت مفتوحة لا هُدمت');
      expect(tester.takeException(), isNull);
    });

    testWidgets('إغلاق تبويبة يُسقط صفحتها ولا تُغلق الأخيرة', (tester) async {
      wideWindow(tester);
      await enterSupply(tester);
      await tester.tap(find.text('الأصناف').first);
      await pump(tester);
      expect(tester.widgetList(find.byType(ImdPageHost, skipOffstage: false)).length, 2);

      // زر × للتبويبة الظاهرة.
      await tester.tap(find.descendant(of: find.byType(ImdPageTabs), matching: find.byType(InkWell)).last);
      await pump(tester);
      expect(tester.widgetList(find.byType(ImdPageHost, skipOffstage: false)).length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الجوال: لا شريط تبويبات ولا شريط حالة وصفحةٌ واحدة', (tester) async {
      window(tester, 700);
      await enterSupply(tester);
      expect(find.byType(ImdPageTabs), findsNothing);
      expect(find.byType(ImdStatusBar), findsNothing);
      expect(tester.widgetList(find.byType(ImdPageHost, skipOffstage: false)).length, 1);
    });
  });
}
