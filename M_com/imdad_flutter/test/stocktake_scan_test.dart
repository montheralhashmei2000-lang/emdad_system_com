import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/stocktake_scan.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/stocktake/stocktake_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const items = [
    (id: 'milk', code: 'M1', barcode: '6281000000011'),
    (id: 'rice', code: 'R1', barcode: ''),
    (id: 'oil', code: 'O1', barcode: '6281000000028'),
  ];
  const lines = {'milk': 'line-milk', 'rice': 'line-rice'};

  group('المطابقة', () {
    test('بالباركود ثم بكود الصنف (بلا حساسية لحالة الأحرف)', () {
      final a = StocktakeScan.resolve(' 6281000000011 ', items, lines) as ScanCounted;
      expect((a.itemId, a.lineId), ('milk', 'line-milk'));
      expect((StocktakeScan.resolve('r1', items, lines) as ScanCounted).lineId, 'line-rice');
    });

    test('صنف غير مدرج في الأمر، وباركود مجهول', () {
      expect((StocktakeScan.resolve('6281000000028', items, lines) as ScanNotInOrder).itemId, 'oil');
      expect(StocktakeScan.resolve('999', items, lines), isA<ScanUnknown>());
    });

    test('المسحة تزيد أصغر وحدة وحدها', () {
      expect(StocktakeScan.increment({'كرتون': 2}, 'علبة'), {'كرتون': 2, 'علبة': 1});
      expect(StocktakeScan.increment({'كرتون': 2, 'علبة': 5}, 'علبة'), {'كرتون': 2, 'علبة': 6});
    });
  });

  group('منع العدّ المزدوج', () {
    test('القراءة المتكررة والباركود أمام الكاميرا لا تُحتسب، وبعد إبعاده تُحتسب', () {
      var now = DateTime(2026, 9, 20, 10);
      final d = ScanDebouncer(clock: () => now);
      expect(d.accept('A'), isTrue);
      now = now.add(const Duration(milliseconds: 300));
      expect(d.accept('A'), isFalse);
      now = now.add(const Duration(milliseconds: 1000)); // ما زال أمامها: المهلة امتدت
      expect(d.accept('A'), isFalse);
      now = now.add(const Duration(milliseconds: 1500)); // أُبعد ثم أُعيد
      expect(d.accept('A'), isTrue);
    });

    test('باركود مختلف يُحتسب فورًا', () {
      final d = ScanDebouncer(clock: () => DateTime(2026));
      expect(d.accept('A'), isTrue);
      expect(d.accept('B'), isTrue);
      expect(d.accept('A'), isTrue);
    });
  });

  group('شاشة الجرد', () {
    late AppDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    testWidgets('مسح بقارئ USB يعدّ الصنف ويحفظه فورًا، ويضيف الصنف غير المدرج', (tester) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = AuthService(db);
      await tester.runAsync(() async {
        await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
        final catalog = CatalogRepo(db);
        await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
        final milk = await catalog.saveItem(
          code: 'M1',
          name: 'حليب',
          baseUnit: 'علبة',
          units: const [ItemUnit(name: 'علبة', factor: 1, isBase: true), ItemUnit(name: 'كرتون', factor: 12)],
        );
        await (db.update(db.items)..where((t) => t.id.equals(milk)))
            .write(const ItemsCompanion(barcode: Value('6281000000011')));
        await MovementsRepo(db).saveReceipt(
          warehouse: 'الرئيسي',
          supplier: 'م',
          date: '2026-09-01',
          lines: [DocLineInput(itemId: milk, itemCode: 'M1', itemName: 'حليب', unitName: 'علبة', factor: 1, qty: 30)],
        );
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'stocktake')),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: StocktakeScreen())),
        ),
      ));
      await settle(tester);

      await tester.tap(find.text('إنشاء أمر الجرد وسحب الأرصدة الدفترية'));
      await settle(tester);

      // صنف عُرِّف بعد فتح الأمر فليس فيه: وُجد على الرف أثناء العد.
      await tester.runAsync(() => CatalogRepo(db).saveItem(
            code: 'O1',
            name: 'زيت',
            baseUnit: 'علبة',
            units: const [ItemUnit(name: 'علبة', factor: 1, isBase: true)],
          ));
      // الشاشة تقرأ الأصناف عند فتحها؛ تبديل التبويب لا يعيد قراءتها، فالمسح نفسه يجب أن يجدها.

      final input = find.widgetWithText(TextField, 'امسح بقارئ USB أو اكتب كود الصنف ثم Enter…');
      expect(input, findsOneWidget);
      for (final code in ['6281000000011', '6281000000011', 'o1']) {
        await tester.enterText(input, code);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
      }

      final saved = await tester.runAsync(() => db.select(db.stocktakeLines).get());
      final milkLine = saved!.firstWhere((l) => l.itemCode == 'M1');
      expect(milkLine.countedQty, 2, reason: 'مسحتان = علبتان، محفوظتان دون ضغط «حفظ العد»');
      final oilLine = saved.firstWhere((l) => l.itemCode == 'O1');
      expect(oilLine.discovered, isTrue);
      expect(oilLine.countedQty, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
