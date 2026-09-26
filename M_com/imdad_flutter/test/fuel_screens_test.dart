import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel.dart';
import 'package:imdad/features/fuel/fuel_allocations_screen.dart';
import 'package:imdad/features/fuel/fuel_consumption_screen.dart';
import 'package:imdad/features/fuel/fuel_dashboard_screen.dart';
import 'package:imdad/features/fuel/fuel_directories_screen.dart';
import 'package:imdad/features/fuel/fuel_daily_report_screen.dart';
import 'package:imdad/features/fuel/fuel_groups.dart';
import 'package:imdad/features/fuel/fuel_ledger_screen.dart';
import 'package:imdad/features/fuel/fuel_official_report_screen.dart';
import 'package:imdad/features/fuel/fuel_vehicles_screen.dart';
import 'package:imdad/features/fuel/fuel_settings_screen.dart';
import 'package:imdad/features/fuel/fuel_moves_screen.dart';
import 'package:imdad/features/fuel/fuel_stocktake_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشات قسم المحروقات.
///
/// كلٌّ منها تُبنى بقاعدة فارغة وبقاعدة فيها بيانات — وأكثر ما ينكسر في شاشة
/// إدخال يقع في أول إطار: قائمة فارغة تُقرأ بـ`.first`، أو قسمة على سعةٍ صفر.
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
  });

  tearDown(() => db.close());

  /// شاشات القسم تُعرض بسمته الداكنة، فتُختبر بها لا بالسمة الفاتحة.
  Widget host(Widget child) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.fuel(),
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: child),
          ),
        ),
      );

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(host(screen));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    final repo = FuelRepo(db);
    await repo.saveWarehouse(name: 'مستودع الوقود', capacityLiters: 20000);
    await repo.saveWarehouse(name: 'الفرعي');
    final unitId = (await repo.saveUnit(name: 'الكتيبة الأولى')).refNo;
    await repo.saveSupply(
      date: '2026-01-01',
      fuelType: FuelType.diesel,
      warehouse: 'مستودع الوقود',
      quantityLiters: 8000,
      supplierName: 'مورّد الوقود',
    );
    await repo.saveAllocation(
      unitId: unitId,
      unitName: 'الكتيبة الأولى',
      fuelType: FuelType.diesel,
      periodType: FuelPeriod.monthly,
      quantityPerPeriod: 2000,
      startDate: '2026-01-01',
    );
    final id = (await repo.allocations()).single.allocation.id;
    // السند بتاريخ اليوم: تقرير الاستهلاك يفتح على الشهر الحالي، فسندٌ قديم
    // يُرشَّح خارجه بحق.
    await repo.saveIssue(
      date: DateTime.now().toIso8601String().substring(0, 10),
      fuelType: FuelType.diesel,
      warehouse: 'مستودع الوقود',
      quantityLiters: 300,
      allocationId: id,
      driverName: 'أحمد',
      vehicleType: 'شاص',
      chassisNo: 'SH-77',
    );
  }

  final screens = <String, Widget Function()>{
    'قسم المحروقات': () => const FuelDashboardScreen(),
    'تفريدة المحروقات': () => const FuelAllocationsScreen(),
    'حركة المحروقات': () => const FuelMovesScreen(),
    'جرد المحروقات': () => const FuelStocktakeScreen(),
    'مستودعات المحروقات': () => const FuelWarehousesScreen(),
    'وحدات المحروقات': () => const FuelUnitsScreen(),
    'سجل المركبات': () => const FuelVehiclesScreen(),
    'التقارير الرسمية': () => const FuelOfficialReportScreen(),
    'تقرير الاستهلاك': () => const FuelConsumptionScreen(),
    'إعدادات المحروقات': () => const FuelSettingsScreen(),
    'تقرير الحركة اليومية للمحروقات': () => const FuelDailyReportScreen(),
    'أرصدة المستودعات': () => const FuelStocksReportScreen(),
    'كشف حركة المستودع': () => const FuelLedgerScreen(),
    'الاستحقاق مقابل الصرف': () => const FuelPlanVsIssuedScreen(),
  };

  group('كل شاشة تُبنى بقاعدة فارغة', () {
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        await show(tester, e.value());
        expect(tester.takeException(), isNull);
        expect(find.text(e.key), findsWidgets);
      });
    }
  });

  group('كل شاشة تُبنى ببيانات', () {
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        await seed();
        await show(tester, e.value());
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('اللوحة تعرض الرصيد والمركبة التي صُرف لها', (tester) async {
    await seed();
    await show(tester, const FuelDashboardScreen());
    expect(tester.takeException(), isNull);
    // ٨٠٠٠ وارد − ٣٠٠ مصروف = ٧٧٠٠
    expect(find.textContaining('٧٬٧٠٠'), findsWidgets);
    // البترول لم يُورَّد، فينبّه على نفاده.
    expect(find.textContaining('نفاد بترول'), findsWidgets);
  });

  testWidgets('سجل المركبات يجمع صرف الشاصي ويفتح سنداته', (tester) async {
    await seed();
    await show(tester, const FuelVehiclesScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('SH-77'), findsWidgets);

    await tester.tap(find.text('SH-77').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('سندات المركبة'), findsWidgets);
  });

  testWidgets('تقرير الاستهلاك يجمّع ويبدّل محوره', (tester) async {
    await seed();
    await show(tester, const FuelConsumptionScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('الكتيبة الأولى'), findsWidgets);

    final axis = find.text('المركبة (الشاصي)').first;
    await tester.ensureVisible(axis);
    await tester.pumpAndSettle();
    await tester.tap(axis, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('SH-77'), findsWidgets,
        reason: 'التبديل إلى محور المركبة لم يُغيّر التجميع');
  });

  testWidgets('باب البيانات الأساسية يفتح على تبويبته ويتنقّل', (tester) async {
    await seed();
    await show(tester, const FuelDataScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('مستودعات المحروقات'), findsWidgets);

    final units = find.text('الوحدات المستفيدة').first;
    await tester.ensureVisible(units);
    await tester.pumpAndSettle();
    await tester.tap(units, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('وحدات المحروقات'), findsWidgets);
  });

  testWidgets('باب البيانات يُفتح على التبويبة المطلوبة', (tester) async {
    await seed();
    await show(tester, const FuelDataScreen(initialTab: 'vehicles'));
    expect(tester.takeException(), isNull);
    expect(find.text('سجل المركبات'), findsWidgets);
  });

  testWidgets('الحركة اليومية تسرد المعسكر بجداوله الثلاثة', (tester) async {
    await seed();
    await show(tester, const FuelDailyReportScreen());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('ملخّص الحركة اليومية'), findsWidgets);
    expect(find.textContaining('الحركة اليومية بـ'), findsWidgets);
    expect(find.text('الوارد'), findsWidgets);
    expect(find.text('المنصرف'), findsWidgets);
    expect(find.textContaining('إجمالي المنصرف'), findsWidgets);
  });

  testWidgets('باب التقارير يحمل تقاريره الستة', (tester) async {
    await seed();
    await show(tester, const FuelReportsHubScreen());
    expect(tester.takeException(), isNull);
    for (final t in const [
      'الحركة اليومية',
      'التقرير الرسمي',
      'الاستهلاك',
      'أرصدة المستودعات',
      'كشف حركة المستودع',
      'الاستحقاق مقابل الصرف',
    ]) {
      expect(find.text(t), findsWidgets, reason: 'تبويبة «$t» غائبة');
    }
  });

  testWidgets('كشف الحركة يمشي بالرصيد مع السطور', (tester) async {
    await seed();
    await show(tester, const FuelReportsHubScreen(initialTab: 'ledger'));
    expect(tester.takeException(), isNull);
    expect(find.text('رصيد مُرحَّل'), findsWidgets,
        reason: 'الكشف يبدأ بما استقرّ قبل المدى');
  });

  testWidgets('البرقية الرسمية تُبنى بترويستها وجداولها', (tester) async {
    await seed();
    await show(tester, const FuelOfficialReportScreen());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('محطة الوقود في'), findsWidgets);
    expect(find.textContaining('الصادر من مادة البترول'), findsWidgets);
    expect(find.textContaining('الصادر من مادة الديزل'), findsWidgets);
    // الترويسة صارت شأنَ الورقة المطبوعة، وتُذكر في الشاشة سطرًا.
    expect(find.textContaining('إعدادات المحروقات'), findsWidgets);
  });

  testWidgets('شاشة الحركة تُظهر المتاح وتتنقّل بين تبويباتها', (tester) async {
    await seed();
    await show(tester, const FuelMovesScreen());
    expect(find.textContaining('المتاح في'), findsWidgets,
        reason: 'من يصرف يجب أن يرى رصيده قبل أن يكتب الكمية');

    for (final name in ['توريد', 'تحويل', 'رصيد افتتاحي']) {
      final tab = find.text(name);
      await tester.ensureVisible(tab.first);
      await tester.pumpAndSettle();
      await tester.tap(tab.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'عند فتح «$name»');
    }
  });

  testWidgets('شاشات القسم تأخذ لوحته الداكنة', (tester) async {
    await seed();
    await show(tester, const FuelDashboardScreen());
    final ctx = tester.element(find.byType(FuelDashboardScreen));
    final colors = Theme.of(ctx).extension<ImdColors>()!;
    expect(colors.isDark, isTrue);
    expect(colors.accent, ImdColors.fuel.accent,
        reason: 'القسم يجب أن يُعرف من أول نظرة أنه ليس شاشات الإعاشة');
  });

  testWidgets('مرشّح نوع الوقود يعمل في التفريدة', (tester) async {
    await seed();
    await show(tester, const FuelAllocationsScreen());
    expect(find.textContaining('وحدة ·'), findsWidgets,
        reason: 'سطر الملخّص يُجمل الخطة قبل قراءة سطورها');

    // التفريدة المزروعة ديزل، فترشيح البترول يُفرغ الجدول.
    await tester.tap(find.text('بترول').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('الكتيبة الأولى'), findsNothing);

    await tester.tap(find.text('ديزل').first);
    await tester.pumpAndSettle();
    expect(find.text('الكتيبة الأولى'), findsWidgets);
  });

  testWidgets('التفريدة تعرض المستحق والمتبقي', (tester) async {
    await seed();
    await show(tester, const FuelAllocationsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('الكتيبة الأولى'), findsWidgets);
    expect(find.text('المتبقي'), findsWidgets);
  });

  testWidgets('الجرد يُفتح فيلتقط الرصيد الدفتري', (tester) async {
    await seed();
    await show(tester, const FuelStocktakeScreen());

    final btn = find.text('فتح أمر الجرد');
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final repo = FuelRepo(db);
    final take = (await repo.stocktakes()).single;
    final lines = await repo.stocktakeLines(take.id);
    final diesel = lines.firstWhere((l) => l.fuelType == FuelType.diesel);
    // الشاشة تفتح على أول مستودع في الدليل (مرتَّبًا أبجديًّا)، فيُقارَن
    // الدفتري برصيد ذلك المستودع بعينه لا برصيدٍ مفترض.
    final expected = (await repo.stocks(warehouse: take.warehouse))
        .firstWhere((x) => x.fuelType == FuelType.diesel)
        .stock;
    expect(diesel.bookLiters, expected,
        reason: 'الرصيد الدفتري لم يُلتقط وقت الفتح');
  });
}
