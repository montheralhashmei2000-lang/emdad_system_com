import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/cylinders.dart';
import 'package:imdad/features/catalog/assets_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يملأ قاعدة بدورة أسطوانات: شراء، عهدة لوحدة، إرسال للتعبئة.
Future<void> seedCylinders(AppDatabase db) async {
  final catalog = CatalogRepo(db);
  final mv = MovementsRepo(db);
  await catalog.saveWarehouse(code: 'W1', name: 'المستودع الرئيسي');
  final gas = await catalog.saveItem(
    code: 'G1',
    name: 'أسطوانة غاز',
    baseUnit: 'أسطوانة',
    units: const [ItemUnit(name: 'أسطوانة', factor: 1, isBase: true)],
    isRefillable: true,
  );
  await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'السرية الأولى'));
  DocLineInput l(double q, String a) => DocLineInput(
      itemId: gas, itemCode: 'G1', itemName: 'أسطوانة غاز', unitName: 'أسطوانة', factor: 1, qty: q, cylinderAction: a);
  await mv.saveReceipt(
      warehouse: 'المستودع الرئيسي',
      supplier: 'شركة الغاز',
      date: '2026-09-01',
      lines: [l(20, CylAction.receiveFull), l(10, CylAction.receiveEmpty)]);
  await mv.saveIssue(
      warehouse: 'المستودع الرئيسي',
      recipientDisplay: 'السرية الأولى',
      unitId: 'u1',
      date: '2026-09-02',
      lines: [l(6, CylAction.issueFull)]);
  await mv.saveIssue(
      warehouse: 'المستودع الرئيسي',
      recipientDisplay: 'شركة الغاز',
      targetType: 2,
      date: '2026-09-03',
      lines: [l(4, CylAction.sendRefill)]);
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('تبويب الأسطوانات يعرض الموقف بحالاته والعهد', (tester) async {
    tester.view.physicalSize = const Size(1500, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthService(db);
    await tester.runAsync(() async {
      await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
      await seedCylinders(db);
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'assets')),
      ],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: AssetsScreen())),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    await settle();
    await tester.tap(find.text('الأسطوانات'));
    await settle();

    expect(tester.takeException(), isNull);
    expect(find.text('السرية الأولى'), findsOneWidget);
    expect(find.text('المستودع الرئيسي'), findsOneWidget);
    // ٢٠ − ٦ ممتلئة، و١٠ − ٤ فارغة، و٤ عند المورد، و٦ عهدة، و٣٠ إجمالًا.
    for (final v in ['14', '6', '4', '30']) {
      expect(find.text(v).evaluate().isNotEmpty || find.text(_ar(v)).evaluate().isNotEmpty, isTrue, reason: v);
    }
  });
}

String _ar(String v) => v.split('').map((c) => '٠١٢٣٤٥٦٧٨٩'[int.parse(c)]).join();
