import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/ration_repo.dart';
import 'package:imdad/features/catalog/authorities_screen.dart';
import 'package:imdad/features/inventory/transfer_screen.dart';
import 'package:imdad/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «سحب من طلبية» في شاشة التحويل.
///
/// هذا هو المفصل الذي يجعل الطلبية طلبًا لا حركة: ركن الإمداد يأذن، ثم يُنشئ
/// أمين المخزن سندَ التحويل من الطلبية — فيقع أثرُ المخزون مرةً واحدة، في
/// المستند الذي يملك فحوصه.
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

  /// طلبية فرعية معتمدة بـ٦٠ من أصل ١٠٠، ورصيدٌ كافٍ في المخزن الرئيسي.
  Future<String> approvedOrder() async {
    await CatalogRepo(db).saveItem(
      code: 'X1',
      name: 'دقيق',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    final item = (await CatalogRepo(db).items()).single;
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرع'));
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: item.id,
          itemName: Value(item.name),
          warehouse: const Value('الرئيسي'),
          qty: const Value(500),
          date: const Value('2026-01-01'),
        ));

    final repo = RationRepo(db);
    await repo.save(
      requestingWarehouse: 'الفرع',
      date: '2026-01-01',
      lines: [
        RationLineInput(
          itemId: item.id,
          itemCode: item.code,
          itemName: item.name,
          unitName: 'كجم',
          factor: 1,
          requestedQty: 100,
        ),
      ],
    );
    final id = (await repo.orders()).single.id;
    await repo.submit(id);
    final lineId = (await repo.byId(id))!.lines.single.id;
    await repo.approve(id, approved: {lineId: 60});
    return id;
  }

  testWidgets('بطاقة السحب لا تظهر إن لم تكن هناك طلبية معتمدة',
      (tester) async {
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرع'));
    await show(tester, const TransferScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('سحب من طلبية معتمدة'), findsNothing);
  });

  testWidgets('الطلبية المعتمدة تظهر للسحب من المخزن الرئيسي', (tester) async {
    await approvedOrder();
    await show(tester, const TransferScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('سحب من طلبية معتمدة'), findsOneWidget);
    expect(find.textContaining('ط-'), findsWidgets,
        reason: 'مرجع الطلبية الجاهزة يجب أن يُعرض للسحب');
  });

  testWidgets('السحب يملأ الأصناف بالكمية المعتمدة لا المطلوبة',
      (tester) async {
    await approvedOrder();
    await show(tester, const TransferScreen());

    final pull = find.textContaining('ط-').first;
    await tester.ensureVisible(pull);
    await tester.pumpAndSettle();
    await tester.tap(pull, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // ٦٠ هي المعتمدة؛ ١٠٠ هي المطلوبة ولا يجوز تحويلها.
    expect(find.widgetWithText(TextField, '60'), findsWidgets,
        reason: 'ما يُحوَّل هو ما أذن به ركن الإمداد');
    expect(find.textContaining('مبنيّ على الطلبية'), findsWidgets);
  });

  testWidgets('مطابقة خطة الاستحقاق تُعلّم الصنف خارج المقرر ولا تمنعه',
      (tester) async {
    await approvedOrder();
    await show(tester, const TransferScreen());

    final pull = find.textContaining('ط-').first;
    await tester.ensureVisible(pull);
    await tester.pumpAndSettle();
    await tester.tap(pull, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();

    final toggle = find.textContaining('مطابقة الأصناف بخطة الاستحقاق');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // لا مقرر لهذا الصنف في هذه القاعدة، فيُعلَّم «خارج المقرر» ويبقى.
    expect(find.text('خارج المقرر'), findsWidgets);
    expect(find.widgetWithText(TextField, '60'), findsWidgets,
        reason: 'المطابقة عرضٌ لا منع — السطر يبقى بكميته');
  });

  testWidgets('جهات الاعتمادات تُفتح من قسمها في الإعدادات', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // موضعها الحقيقي: قسمٌ داخل الإعدادات لا شاشةٌ في قائمة العمليات.
    await show(tester, const SettingsScreen());
    expect(tester.takeException(), isNull);

    final section = find.text('جهات الاعتمادات');
    expect(section, findsWidgets, reason: 'القسم غائب عن قائمة الإعدادات');
    await tester.ensureVisible(section.first);
    await tester.pumpAndSettle();
    await tester.tap(section.first, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('إضافة جهة'), findsWidgets);
  });

  testWidgets('جهات الاعتمادات تُبنى مضمَّنةً وتحفظ جهة', (tester) async {
    // مضمَّنةً كما تظهر في الإعدادات: داخل صفحة تُمرَّر، بلا عنوان خاص بها.
    await show(
      tester,
      const SingleChildScrollView(child: AuthoritiesScreen(embedded: true)),
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, 'ركن إمداد الفرقة');
    await tester.pumpAndSettle();
    final add = find.text('إضافة');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();

    expect((await RationRepo(db).authorities()).single.name, 'ركن إمداد الفرقة');
  });
}
