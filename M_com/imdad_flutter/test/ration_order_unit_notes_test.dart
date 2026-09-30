import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/ration_repo.dart';
import 'package:imdad/features/inventory/ration_order_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// عمودا الوحدة والملاحظة في طلبية الإعاشة.
///
/// كانا معطَّلين أصلًا: الوحدة تُشتقّ دومًا من وحدة الأساس (factor: 1
/// ثابتًا)، والملاحظة حقلٌ في طبقة البيانات بلا واجهةٍ تملؤه.
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
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرع'));
    await CatalogRepo(db).saveItem(
      code: 'X1',
      name: 'دقيق',
      baseUnit: 'كجم',
      units: const [
        ItemUnit(name: 'كجم', factor: 1, isBase: true),
        ItemUnit(name: 'كيس', factor: 40),
      ],
    );
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
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
        ),
      );

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const RationOrderScreen()));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  /// يضيف سطرًا ويختار فيه الصنف — لا حاجة لاختيار مستودعٍ ولا مورِّد:
  /// جدول الأسطر يُبنى بلا شرطٍ عليهما.
  Future<void> addLineWithItem(WidgetTester tester) async {
    await tester.tap(find.text('إضافة صنف').first);
    await tester.pumpAndSettle();

    final itemField = find.byType(TextField).first;
    await tester.tap(itemField);
    await tester.pump();
    await tester.enterText(itemField, 'دقيق');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('دقيق').last);
    await tester.pump();
  }

  testWidgets('اختيار صنفٍ يملأ وحدة الأساس تلقائيًّا في حقل الوحدة', (tester) async {
    await show(tester);
    await addLineWithItem(tester);

    // حقل الوحدة (الثاني) يعرض «كجم» فور اختيار الصنف — وحدة الأساس.
    expect(find.widgetWithText(TextField, 'كجم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('التبديل إلى وحدةٍ بمعاملٍ مختلف يحوّل الكمية المكتوبة', (tester) async {
    await show(tester);
    await addLineWithItem(tester);

    final qtyField = find.byType(TextField).at(2);
    await tester.enterText(qtyField, '80');
    await tester.pump();

    // التبديل إلى «كيس» (معاملها ٤٠ مقابل ١ لكجم): ٨٠ كجم ⇒ ٢ كيس.
    final unitField = find.byType(TextField).at(1);
    await tester.tap(unitField);
    await tester.pump();
    await tester.tap(find.text('كيس'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('حقل الملاحظة موجودٌ لكل سطر ويقبل الكتابة', (tester) async {
    await show(tester);
    await addLineWithItem(tester);

    final notesField = find.byType(TextField).at(3);
    await tester.enterText(notesField, 'يُفضَّل التسليم صباحًا');
    // المنتقي يؤجّل إغلاق قائمته 150ms بعد فقد التركيز (هنا: تركيز حقل
    // الملاحظة يسحبه من حقل الصنف)، فيُستنزف مؤقّته وإلا انتهى الاختبار
    // ومؤقّتٌ معلّق.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('يُفضَّل التسليم صباحًا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('الوحدة والمعامل والملاحظة تُحفظ وتُقرأ كما أُدخلت (طبقة البيانات)',
      () async {
    final repo = RationRepo(db);
    final item = (await CatalogRepo(db).items()).single;
    await repo.save(
      requestingWarehouse: 'الفرع',
      supplyingWarehouse: 'الرئيسي',
      date: '2026-01-01',
      lines: [
        RationLineInput(
          itemId: item.id,
          itemCode: item.code,
          itemName: item.name,
          unitName: 'كيس',
          factor: 40,
          requestedQty: 2,
          notes: 'يُفضَّل التسليم صباحًا',
        ),
      ],
    );
    final saved = (await repo.orders()).single;
    final full = await repo.byId(saved.id);
    final line = full!.lines.single;

    expect(line.unitName, 'كيس');
    expect(line.factor, 40);
    expect(line.requestedQty, 2);
    expect(line.notes, 'يُفضَّل التسليم صباحًا');
  });
}
