import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/catalog/assets_screen.dart';
import 'package:imdad/features/daily/camp_dashboard_screen.dart';
import 'package:imdad/features/daily/meal_plan_screen.dart';
import 'package:imdad/features/inventory/ration_order_screen.dart';
import 'package:imdad/features/reports/actual_entitlement_screen.dart';
import 'package:imdad/features/reports/camp_ledger_screen.dart';
import 'package:imdad/features/reports/camp_settlement_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اختبارات واجهة للشاشات الجديدة.
///
/// الغرض ليس التقاط البكسل بل التأكد من أن كل شاشة **تُبنى وتُرسَم** بقاعدة
/// فارغة وبقاعدة فيها بيانات، بلا استثناء ولا شاشة حمراء. أكثر ما ينكسر في
/// هذه الشاشات يقع في أول إطار: قائمة فارغة تُقرأ بـ`.first`، أو قيمة منسدلة
/// لا تطابق أي خيار.

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

  /// يبني الشاشة ويُمهلها لإنهاء قراءاتها غير المتزامنة.
  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(host(screen));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    final catalog = CatalogRepo(db);
    await catalog.saveItem(
      code: 'X1',
      name: 'رز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(id: 'wh1', name: 'الرئيسي', isMain: const Value(true)),
        );
    await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
          id: 'camp1',
          name: 'المعسكر الأول',
          type: const Value('camp'),
          isCamp: const Value(true),
        ));
    final item = (await catalog.items()).single;
    await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
          itemId: item.id,
          itemName: Value(item.name),
          qtyPerPerson: const Value(30),
        ));
  }

  final screens = <String, Widget Function()>{
    'الأصول الثابتة': () => const AssetsScreen(),
    'طلبيات الإعاشة': () => const RationOrderScreen(),
    'خطط الوجبات': () => const MealPlanScreen(),
    'لوحة المعسكرات': () => const CampDashboardScreen(),
    'حساب الاستحقاق الفعلي': () => const ActualEntitlementScreen(),
    'سجل حساب المعسكر': () => const CampLedgerScreen(),
    'تصفية الشهر': () => const CampSettlementScreen(),
  };

  group('كل شاشة تُبنى بقاعدة فارغة', () {
    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        await show(tester, entry.value());
        expect(tester.takeException(), isNull);
        expect(find.text(entry.key), findsWidgets);
      });
    }
  });

  group('كل شاشة تُبنى ببيانات', () {
    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        await seed();
        await show(tester, entry.value());
        expect(tester.takeException(), isNull);
        expect(find.text(entry.key), findsWidgets);
      });
    }
  });

  testWidgets('تبويبات خطط الوجبات تتبدّل بلا انهيار', (tester) async {
    await seed();
    await show(tester, const MealPlanScreen());

    await tester.tap(find.text('قائمة الطعام').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('اختر خطة'), findsWidgets);

    await tester.tap(find.text('مقارنة خطتين').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('لوحة المعسكرات تُظهر حالة كل معسكر', (tester) async {
    await seed();
    await show(tester, const CampDashboardScreen());
    expect(find.text('المعسكر الأول'), findsWidgets);
    expect(find.text('بلا حدود'), findsWidgets,
        reason: 'معسكر بلا حدود مخزون يجب أن يُقال ذلك صراحةً');
  });

  testWidgets('تصفية شهر لم ينتهِ معطَّلة', (tester) async {
    await seed();
    await show(tester, const CampSettlementScreen());
    expect(find.textContaining('لا يُصفّى شهر لم ينتهِ'), findsNothing,
        reason: 'الافتراضي هو الشهر المنقضي لا الجاري');
    expect(tester.takeException(), isNull);
  });
}
