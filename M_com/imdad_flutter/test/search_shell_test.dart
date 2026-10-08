import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_screen_actions.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// دمج البحث العام في الإطار: زرُّ الشريط العلوي يفتح اللوحة، والإجراء نفسه
/// هو ما يستدعيه Ctrl+K في `main.dart` ([ImdScreenActions.onSearch])، وزرُّ
/// الرجوع على أندرويد يغلق اللوحة لا الشاشة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late AutoSyncService autoSync;
  late ImdTheme imdTheme;
  late ImdScreenActions actions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    autoSync = AutoSyncService(db);
    imdTheme = ImdTheme(ThemeMode.light);
    actions = ImdScreenActions();
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    SharedPreferences.setMockInitialValues({
      'imdad.space.${auth.currentUser!.id}': AppSpace.supply,
    });
    await db.into(db.items).insert(ItemsCompanion.insert(id: 'i1', name: 'طحين فاخر'));
  });

  tearDown(() => db.close());

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          // كما في `main.dart`: سجلّ الإجراءات فوق القشرة، وهو قناة Ctrl+K.
          Provider<ImdScreenActions>.value(value: actions),
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

  /// سطح المكتب (>1150) هو حيث يعمل Ctrl+K؛ وعرضٌ محدَّدٌ صراحةً حتى لا
  /// يتعلّق الاختبار بحجم النافذة الافتراضي.
  Future<void> pump(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  testWidgets('القشرة تسجّل إجراء البحث العام، وهو ما يربطه Ctrl+K', (tester) async {
    await pump(tester);
    expect(actions.onSearch, isNotNull, reason: 'بلا تسجيلٍ لا يفعل Ctrl+K شيئًا');

    // الشاشات تسجّل إجراءاتها عند فتحها؛ البحث إجراءُ الإطار فلا يُمسح معها.
    actions.register(onSave: () {});
    expect(actions.onSearch, isNotNull);
    actions.clear();
    expect(actions.onSearch, isNotNull);
  });

  testWidgets('زرّ 🔍 في شريط سطح المكتب يفتح اللوحة', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('البحث العام (Ctrl+K)'));
    await tester.pumpAndSettle();
    expect(find.text('البحث العام'), findsWidgets, reason: 'عنوان الحوار');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('زرّ 🔍 موجودٌ أيضًا في شريط الجوال (لا Ctrl+K هناك)', (tester) async {
    await pump(tester, size: const Size(400, 800));
    expect(find.byTooltip('البحث العام (Ctrl+K)'), findsOneWidget);
    await tester.tap(find.byTooltip('البحث العام (Ctrl+K)'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('اللوحة تبحث في بيانات القاعدة وتفتح شاشة النتيجة', (tester) async {
    await pump(tester);
    actions.onSearch!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'طحين');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // النصّ نفسه قد يظهر خلف الحوار (لوحة القيادة)، فيُقصَد سطرُ اللوحة.
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('طحين فاخر')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing, reason: 'اللوحة أُغلقت بالاختيار');
    // تبويبة الأصناف فُتحت في القشرة (شاشة النتيجة).
    expect(find.text('الأصناف'), findsWidgets);
  });

  testWidgets('زرّ الرجوع (أندرويد) يغلق اللوحة ويُبقي القشرة', (tester) async {
    await pump(tester);
    actions.onSearch!();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'اللوحة أُغلقت');
    expect(find.byType(HomeShell), findsOneWidget, reason: 'القشرة باقية');
  });

  testWidgets('بعد الإغلاق يرجع التركيز، فتُفتح اللوحة من جديد', (tester) async {
    await pump(tester);
    final before = FocusManager.instance.primaryFocus;

    actions.onSearch!();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(before), reason: 'حقل البحث أخذ التركيز');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, before, reason: 'التركيز عاد لما كان قبل الفتح');

    actions.onSearch!();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
