import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/home_shell.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
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
    expect(find.text('نظام الإمداد والتموين'), findsWidgets);
  });

  testWidgets('الشريط يُبنى بأبوابه بعد اختيار القسم', (tester) async {
    wideWindow(tester);

    await enterSupply(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('العمليات المخزنية'), findsWidgets);
    expect(find.text('التقارير والرقابة'), findsWidgets);
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
      // والاسم يبقى في التلميح لمن يبحث.
      expect(
          find.byWidgetPredicate(
              (w) => w is Tooltip && w.message == 'حركة المخزون'),
          findsWidgets);
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

  testWidgets('كل صلاحية معرَّفة لها تسمية', (tester) async {
    // تسميةٌ ناقصة تعني بندًا لا يظهر إلا للمدير بلا قصد.
    for (final key in Perm.labels.keys) {
      expect(Perm.labels[key]!.trim(), isNotEmpty, reason: key);
    }
  });
}
