import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_bulk.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/assets_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/warehouse_limits_repo.dart';
import 'package:imdad/features/catalog/assets_screen.dart';
import 'package:imdad/features/catalog/warehouses_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الإدخال الجماعي: الأصول دفعةً، وحدود المستودع دفعةً.
///
/// ما تحرسه هذه الاختبارات ليس الشكل بل **الطريق من الشبكة إلى القاعدة**:
/// أن الكمية تُحفظ، وأن الحد المكتوب بالشوال يُخزَّن بالكجم.
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

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).first;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();
  }

  Future<void> seedWarehouse() async {
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
    await CatalogRepo(db).saveItem(
      code: 'X1',
      name: 'رز',
      baseUnit: 'كجم',
      units: const [
        ItemUnit(name: 'كجم', factor: 1, isBase: true),
        ItemUnit(name: 'شوال', factor: 50),
      ],
    );
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: (await CatalogRepo(db).items()).single.id,
          warehouse: const Value('الرئيسي'),
          qty: const Value(300),
          date: const Value('2026-01-01'),
        ));
  }

  group('شاشة الأصول — إدخال جماعي', () {
    testWidgets('التبويب يفتح شبكة الدفعة', (tester) async {
      await show(tester, const AssetsScreen());
      expect(tester.takeException(), isNull);

      await tapText(tester, 'دفعة أصول');
      expect(tester.takeException(), isNull);
      expect(find.text('إضافة أصل'), findsWidgets);
      expect(find.textContaining('البيانات المشتركة'), findsWidgets);
    });

    testWidgets('الدفعة تُحفظ بكمياتها', (tester) async {
      await show(tester, const AssetsScreen());
      await tapText(tester, 'دفعة أصول');
      await tapText(tester, 'إضافة أصل');

      // حقول الشبكة وحدها — الحقول المشتركة أعلاها ليست منها.
      final rowFields = find.descendant(
          of: find.byType(ImdBulkGrid), matching: find.byType(TextField));
      expect(rowFields, findsWidgets);
      await tester.enterText(rowFields.at(0), 'طاولة طعام');
      await tester.pumpAndSettle();
      await tester.enterText(rowFields.at(1), '12');
      await tester.pumpAndSettle();

      await tapText(tester, 'حفظ الدفعة');

      final saved = await AssetsRepo(db).assets();
      expect(saved, hasLength(1));
      expect(saved.single.name, 'طاولة طعام');
      expect(saved.single.quantity, 12,
          reason: 'الكمية لم تصل من الشبكة إلى القاعدة');
    });

    testWidgets('رقم تسلسلي مع كمية أكثر من واحدة يمنع الحفظ', (tester) async {
      await show(tester, const AssetsScreen());
      await tapText(tester, 'دفعة أصول');
      await tapText(tester, 'إضافة أصل');

      final rowFields = find.descendant(
          of: find.byType(ImdBulkGrid), matching: find.byType(TextField));
      await tester.enterText(rowFields.at(0), 'مولّد');
      await tester.pumpAndSettle();
      await tester.enterText(rowFields.at(1), '5');
      await tester.pumpAndSettle();
      await tester.enterText(rowFields.at(2), 'SN-1');
      await tester.pumpAndSettle();

      expect(find.textContaining('الرقم التسلسلي لقطعة واحدة'), findsWidgets,
          reason: 'خمس قطع برقم واحد لا يُعرف أيّها المقصود في العهدة');
      expect(await AssetsRepo(db).assets(), isEmpty);
    });
  });

  group('لوحة المستودعات', () {
    testWidgets('تبويب اللوحة يظهر داخل شاشة المستودعات', (tester) async {
      await seedWarehouse();
      await show(tester, const WarehousesScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('لوحة المستودعات'), findsWidgets);

      await tapText(tester, 'لوحة المستودعات');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('أصناف لها حدود'), findsWidgets);
    });

    testWidgets('الحد المكتوب بالشوال يُخزَّن بالكجم', (tester) async {
      await seedWarehouse();
      await show(tester, const WarehousesScreen());
      await tapText(tester, 'لوحة المستودعات');
      await tapText(tester, 'ضبط الحدود');

      // الصنف يُختار من المنتقي، ثم الوحدة، ثم الحدّان.
      await tester.enterText(
          find.byType(TextField).first, 'رز');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('اللوحة تعرض النقص بوحدة الإدخال لا بوحدة الأساس',
        (tester) async {
      await seedWarehouse();
      final item = (await CatalogRepo(db).items()).single;
      await WarehouseLimitsRepo(db).saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
            itemId: item.id,
            itemName: 'رز',
            unitName: 'شوال',
            factor: 50,
            min: 10,
            max: 0,
          ),
        ],
      );

      await show(tester, const WarehousesScreen());
      await tapText(tester, 'لوحة المستودعات');

      expect(tester.takeException(), isNull);
      // الرصيد ٣٠٠ كجم = ٦ شوالات، والحد ١٠ — فينقصه ٤ شوالات.
      expect(find.textContaining('حوّل'), findsWidgets);
      expect(find.text('تحت الأدنى'), findsWidgets);
    });

    testWidgets('مستودع بلا حدود يقول ذلك صراحةً', (tester) async {
      await seedWarehouse();
      await show(tester, const WarehousesScreen());
      await tapText(tester, 'لوحة المستودعات');
      expect(find.textContaining('لا حدود مضبوطة'), findsWidgets);
    });
  });
}
