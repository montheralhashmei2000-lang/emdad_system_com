import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel.dart';
import 'package:imdad/features/fuel/fuel_allocations_screen.dart';
import 'package:imdad/features/fuel/fuel_dashboard_screen.dart';
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

  Widget host(Widget child) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
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
    await repo.saveIssue(
      date: '2026-01-05',
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
    'لوحة المحروقات': () => const FuelDashboardScreen(),
    'تفريدة المحروقات': () => const FuelAllocationsScreen(),
    'حركة المحروقات': () => const FuelMovesScreen(),
    'جرد المحروقات': () => const FuelStocktakeScreen(),
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

  testWidgets('اللوحة تنتقل إلى سجل المركبات', (tester) async {
    await seed();
    await show(tester, const FuelDashboardScreen());
    final tab = find.text('سجل المركبات');
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SH-77'), findsWidgets);
  });

  testWidgets('شاشة الحركة تُظهر المتاح وتتنقّل بين تبويباتها',
      (tester) async {
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
