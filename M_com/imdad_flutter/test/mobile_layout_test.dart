import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_layout.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// كل شاشات النظام على مقاس هاتف أندرويد: لا فيض في التخطيط ولا استثناء.
///
/// RenderFlex overflow يظهر في نسخة التطوير شريطًا أصفر وأسود، وفي الإصدار
/// يُقصّ المحتوى بصمت — فيُكتشف على الهاتف فقط. هذا الاختبار يكشفه قبل ذلك.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late AutoSyncService autoSync;

  const supplyPages = [
    'dash', 'items', 'stores', 'units', 'suppliers', 'kitchens', 'assets',
    'receive', 'issue', 'transfer', 'returns', 'opening', 'rationOrders', 'pendingOrders',
    'feeding', 'mealPlans', 'kitchenLog', 'ratios',
    'balances', 'reportMoves', 'reportUnitAccount', 'reportStock', 'reportConsumption',
    'reportStrength', 'reportKitchen', 'reportSupplier', 'reportReturns', 'reportDaily',
    'campLedger', 'campSettlement', 'actualEntitlement', 'stockAlerts', 'supplyAudit',
    'stocktakeCreate', 'stocktakeCount', 'stocktakeAnalysis', 'stocktakeSettle', 'stocktakeHistory',
    'settings', 'branding', 'formsDesigner', 'deviceActivation', 'verifySign', 'lanSync', 'usersAccess',
  ];

  /// خط التطبيق الحقيقي: اختبارات Flutter ترسم كل نصٍّ بخط Ahem (كل حرفٍ مربعٌ
  /// بعرض حجم الخط)، فتُبالغ في عرض النص الفعلي بنحو الضعف وتُظهر فيضًا لا يقع على
  /// الجهاز. بالخط الحقيقي تكون أعراض النصوص هي ما يراه المستخدم.
  setUpAll(() async {
    for (final family in ['IBMPlexSansArabic']) {
      final loader = FontLoader(family);
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    autoSync = AutoSyncService(db);
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    SharedPreferences.setMockInitialValues({
      'imdad.space.${auth.currentUser!.id}': AppSpace.supply,
    });
  });

  tearDown(() => db.close());

  Widget host({double textScale = 1}) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<AutoSyncService>.value(value: autoSync),
          ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HomeShell(onSignOut: () async {}),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
    await tester.pump();
  }

  Future<List<String>> sweep(WidgetTester tester, Size size, {double textScale = 1}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // تُجمع الأخطاء بتفاصيلها (سلسلة الودجات) لا بعنوانها وحده، فيُعرف أي سطرٍ
    // من أي ملفٍّ يفيض.
    final captured = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = captured.add;

    await tester.pumpWidget(host(textScale: textScale));
    await settle(tester);
    captured.clear();

    final nav = ImdNav.of(tester.element(find.byType(Scaffold).first));
    final bad = <String>[];
    for (final page in supplyPages) {
      nav.go(page);
      await settle(tester);
      for (final d in captured) {
        final text = d.toDiagnosticsNode().toStringDeep();
        final first = text.split('\n').firstWhere((l) => l.contains('Exception') || l.contains('overflowed') || l.contains('Error'), orElse: () => text.split('\n').first);
        final where = RegExp(r'lib/[\w/]+\.dart:\d+').allMatches(text).map((m) => m.group(0)).toSet().take(2).join(' ');
        bad.add('$page: ${first.trim()} @ $where');
        File('/tmp/claude-0/-home-user-emdad-system-com/2b639e3e-f260-5e7f-8b9e-58b676793e53/scratchpad/overflow_${page}_${bad.length}.txt').writeAsStringSync(text);
      }
      captured.clear();
    }
    FlutterError.onError = previous;
    // قبل نهاية الاختبار: الإطار يرفض متغيّراتٍ مُغيَّرةً تُترك لما بعده.
    debugDefaultTargetPlatformOverride = null;
    return bad;
  }

  testWidgets('هاتف ٣٦٠×٧٤٠: لا فيض في أي شاشة', (tester) async {
    final bad = await sweep(tester, const Size(360, 740));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  testWidgets('هاتف ٣٦٠×٧٤٠ بخطٍّ أكبر ١٫٣: لا فيض في أي شاشة', (tester) async {
    final bad = await sweep(tester, const Size(360, 740), textScale: 1.3);
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  testWidgets('هاتف صغير ٣٢٠×٥٦٨: لا فيض في أي شاشة', (tester) async {
    final bad = await sweep(tester, const Size(320, 568));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  testWidgets('هاتف أفقيّ ٧٤٠×٣٦٠: لا فيض في أي شاشة', (tester) async {
    final bad = await sweep(tester, const Size(740, 360));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  testWidgets('لوحي ٨٠٠×١٢٨٠: لا فيض في أي شاشة', (tester) async {
    final bad = await sweep(tester, const Size(800, 1280));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  group('تكبير الخط', () {
    test('يُقصّ فوق السقف ويُترك ما دونه', () {
      MediaQueryData at(double f) =>
          imdClampedMediaQuery(MediaQueryData(textScaler: TextScaler.linear(f)));
      expect(at(2.0).textScaler.scale(10), closeTo(10 * kImdMaxTextScale, .001));
      expect(at(1.0).textScaler.scale(10), closeTo(10, .001));
      expect(at(0.85).textScaler.scale(10), closeTo(8.5, .001),
          reason: 'تصغير المستخدم للخط يُحترم');
    });
  });

  testWidgets('الشريط العلوي لا يدخل تحت شريط حالة أندرويد', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 30);
    tester.view.viewPadding = const FakeViewPadding(top: 30);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await settle(tester);

    // الشريط العلوي يطول بقدر إزاحة شريط الحالة، وحشوته العلوية تزيد بها —
    // فمحتواه يبدأ تحت الساعة والبطارية لا خلفها.
    final bar = find.byWidgetPredicate((w) =>
        w is Container && w.constraints?.maxHeight == ImdSizes.topbarHeight + 30);
    expect(bar, findsOneWidget, reason: 'الشريط لم يأخذ إزاحة شريط الحالة');
    final container = tester.widget<Container>(bar);
    expect((container.padding as EdgeInsets).top, 8 + 30);
    debugDefaultTargetPlatformOverride = null;
  });
}
