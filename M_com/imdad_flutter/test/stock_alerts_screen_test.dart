import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/features/alerts/stock_alerts_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('شاشة التنبيهات تعرض الصنف تحت الحد والدفعة القريبة من الانتهاء', (tester) async {
    tester.view.physicalSize = const Size(1500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthService(db);
    await tester.runAsync(() async {
      await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
      final catalog = CatalogRepo(db);
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      final milk = await catalog.saveItem(
        code: 'M1',
        name: 'حليب طويل الأجل',
        baseUnit: 'علبة',
        units: const [ItemUnit(name: 'علبة', factor: 1, isBase: true)],
        minQty: 50,
      );
      final soon = DateTime.now().add(const Duration(days: 5));
      final iso = '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
      await MovementsRepo(db).saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'المورد',
        date: '2026-01-01',
        lines: [
          DocLineInput(
              itemId: milk, itemCode: 'M1', itemName: 'حليب', unitName: 'علبة', factor: 1, qty: 12, expiryDate: iso),
        ],
      );
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'stockAlerts')),
      ],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: StockAlertsScreen())),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('حليب طويل الأجل'), findsOneWidget);
    expect(find.text('تحت الحد'), findsOneWidget);

    await tester.tap(find.text('قرب انتهاء الصلاحية'));
    await tester.pump();
    expect(find.text('بعد ٥ يوم').evaluate().isNotEmpty || find.text('بعد 5 يوم').evaluate().isNotEmpty, isTrue);
  });
}
