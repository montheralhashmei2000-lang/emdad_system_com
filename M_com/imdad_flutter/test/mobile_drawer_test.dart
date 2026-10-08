import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// درج الجوال يلتزم بالشاشة.
///
/// كان عرضه ثابتًا على [ImdSizes.sideWidth] — وهو مقاس **سطح المكتب** (٢٩٠):
/// يبتلع ٨٠٪ من هاتفٍ عرضه ٣٦٠ و٩٠٪ من هاتفٍ عرضه ٣٢٠، فلا يبقى خلفه ما
/// يُذكّر بالصفحة المفتوحة. وكانت القائمة داخله تفرض العرض نفسه على نفسها،
/// فلو ضاق الدرج فاضت. ولا حشوة لشريط الحالة، فيبدأ أولُ بندٍ تحت ساعة النظام.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late AutoSyncService autoSync;

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

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          ChangeNotifierProvider<AutoSyncService>.value(value: autoSync),
          ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HomeShell(onSignOut: () async {}),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
    await tester.pump();
  }

  Future<double> openDrawer(WidgetTester tester, Size size, {double statusBar = 0}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    if (statusBar > 0) {
      tester.view.padding = FakeViewPadding(top: statusBar);
      tester.view.viewPadding = FakeViewPadding(top: statusBar);
    }
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await settle(tester);
    final state = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    state.openEndDrawer();
    await settle(tester);
    debugDefaultTargetPlatformOverride = null;
    return tester.getSize(find.byType(Drawer)).width;
  }

  group('عرض الدرج يتبع عرض الشاشة', () {
    testWidgets('هاتف ٣٦٠: الدرج لا يبتلع الشاشة ويبقى خلفه أثرٌ منها', (tester) async {
      final w = await openDrawer(tester, const Size(360, 740));
      expect(w, lessThan(360 * .9), reason: 'يبقى من الشاشة ما يُذكّر بالصفحة');
      expect(w, closeTo(360 * .76, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('هاتف صغير ٣٢٠: يضيق معه ولا يفيض', (tester) async {
      final w = await openDrawer(tester, const Size(320, 568));
      expect(w, closeTo(320 * .76, 1));
      expect(tester.takeException(), isNull, reason: 'القائمة فاضت عن درجها');
    });

    testWidgets('لوحيّ ٨٠٠: يقف عند مقاس سطح المكتب ولا يتمدّد', (tester) async {
      final w = await openDrawer(tester, const Size(800, 1280));
      expect(w, ImdSizes.sideWidth, reason: '٧٦٪ من ٨٠٠ أعرض من اللازم');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('حشوةٌ لشريط الحالة: أوّل بندٍ لا يقع تحت ساعة النظام', (tester) async {
    await openDrawer(tester, const Size(360, 740), statusBar: 36);
    final home = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('الرئيسية'),
    );
    expect(home, findsOneWidget);
    expect(tester.getTopLeft(home).dy, greaterThanOrEqualTo(36),
        reason: 'البند بدأ داخل شريط الحالة');
    expect(tester.takeException(), isNull);
  });
}
