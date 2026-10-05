import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_page_tabs.dart';
import 'package:imdad/core/ui/imd_status_bar.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/catalog/items_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// التبديل بين قسم الإمداد وقسم المحروقات.
///
/// القسمان يشتركان في القشرة نفسها (تبويبات + شريط جانبي + شريط حالة) لكن لكلٍّ
/// هويّته البصرية وتبويباته. والشرط أن التبديل **لا يهدم** القسم الذي غادره:
/// يعود بتبويباته المفتوحة وبحالة صفحاته نفسها لا نسخةً جديدة منها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
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
    // المدير يملك القسمين؛ حفظُ اختياره يدخلنا القشرة مباشرةً على الإمداد.
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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(host());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  Future<void> enterShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    final enter = find.text('ادخل');
    if (enter.evaluate().isNotEmpty) {
      await tester.tap(enter.first, warnIfMissed: false);
      await pump(tester);
    }
  }

  Future<void> switchSection(WidgetTester tester) async {
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'تبديل القسم'));
    await pump(tester);
  }

  /// لوحة ألوان الإطار الحالية (سمة القشرة الظاهرة).
  ImdColors shellColors(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(ImdPageTabs))).extension<ImdColors>()!;

  /// عدد صفحات قسمٍ مبنيّةً (ظاهرةً ومخفيّة).
  int hostsOf(String space) => find
      .byWidgetPredicate(
        (w) => w is ImdPageHost && (w.key as ValueKey).value.toString().startsWith('host:$space:'),
        skipOffstage: false,
      )
      .evaluate()
      .length;

  testWidgets('التبديل يغيّر الهوية البصرية: أخضر الإمداد ثم برتقالي المحروقات', (tester) async {
    await enterShell(tester);
    expect(shellColors(tester).accent, ImdColors.light.accent, reason: 'الإمداد أخضر زمردي');
    expect(shellColors(tester).side, ImdColors.light.side);

    await switchSection(tester);
    expect(tester.takeException(), isNull);
    expect(shellColors(tester).accent, ImdColors.fuelLight.accent, reason: 'المحروقات بلوحتها المستقلة');
    expect(shellColors(tester).accent, isNot(ImdColors.light.accent));
    expect(shellColors(tester).side, ImdColors.fuelLight.side);

    await switchSection(tester);
    expect(shellColors(tester).accent, ImdColors.light.accent, reason: 'العودة تعيد هوية الإمداد');
  });

  testWidgets('التبديل لا يهدم تبويبات القسم الذي غادرناه ولا حالة صفحاته', (tester) async {
    await enterShell(tester);

    // الإمداد: افتح «الأصناف» فتصير تبويبتان (الرئيسية + الأصناف).
    await tester.tap(find.text('الأصناف').first);
    await pump(tester);
    expect(hostsOf(AppSpace.supply), 2);
    final itemsBefore = find.byType(ItemsScreen, skipOffstage: false).evaluate().single;

    // المحروقات: قسمٌ جديدٌ بتبويبته الرئيسية وحدها، والإمداد ما زال حيًّا مخفيًّا.
    await switchSection(tester);
    expect(tester.takeException(), isNull);
    expect(hostsOf(AppSpace.fuel), 1, reason: 'المحروقات تبدأ بالرئيسية');
    expect(hostsOf(AppSpace.supply), 2, reason: 'تبويبات الإمداد بقيت مبنيّة');
    expect(find.byType(ItemsScreen), findsNothing, reason: 'صفحة الإمداد مخفيّة لا مرئية');

    // افتح بندًا في المحروقات: تبويباتها لا تتسرّب إلى الإمداد.
    await tester.tap(find.text('توريد').first);
    await pump(tester);
    expect(hostsOf(AppSpace.fuel), 2);
    expect(hostsOf(AppSpace.supply), 2);

    // العودة إلى الإمداد: التبويبتان نفسهما، وصفحة الأصناف هي **نفس** العنصر.
    await switchSection(tester);
    expect(hostsOf(AppSpace.supply), 2);
    expect(hostsOf(AppSpace.fuel), 2, reason: 'المحروقات بقيت مفتوحة بتبويبتيها');
    final itemsAfter = find.byType(ItemsScreen, skipOffstage: false).evaluate().single;
    expect(identical(itemsAfter, itemsBefore), isTrue, reason: 'الصفحة أُعيد بناؤها من الصفر');
    expect(find.byType(ItemsScreen), findsOneWidget, reason: 'عادت صفحة الأصناف ظاهرة');
    expect(tester.takeException(), isNull);
  });

  testWidgets('شريط التبويبات وشريط الحالة يتبعان القسم الظاهر', (tester) async {
    await enterShell(tester);
    await tester.tap(find.text('الأصناف').first);
    await pump(tester);

    List<String> tabTitles() => tester
        .widget<ImdPageTabs>(find.byType(ImdPageTabs))
        .pages
        .map((p) => p.id)
        .toList();
    expect(tabTitles(), ['dash', 'items']);

    await switchSection(tester);
    expect(tabTitles(), ['dash'], reason: 'تبويبات المحروقات وحدها');
    expect(find.byType(ImdStatusBar), findsOneWidget);

    await switchSection(tester);
    expect(tabTitles(), ['dash', 'items'], reason: 'تبويبات الإمداد كما تُركت');
  });

  testWidgets('اختيار القسم يُحفظ، والتبديل المباشر لا يمرّ بشاشة الاختيار', (tester) async {
    await enterShell(tester);
    await switchSection(tester);
    expect(find.text('ادخل'), findsNothing, reason: 'التبديل مباشرٌ لا عبر شاشة الاختيار');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('imdad.space.${auth.currentUser!.id}'), AppSpace.fuel);
  });

  testWidgets('الوضع الداكن يطبّق لوحة المحروقات الداكنة', (tester) async {
    imdTheme = ImdTheme(ThemeMode.dark);
    await enterShell(tester);
    await switchSection(tester);
    expect(shellColors(tester).accent, ImdColors.fuelDark.accent);
    expect(shellColors(tester).isDark, isTrue);
  });
}
