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
import 'package:imdad/domain/ration_order.dart';
import 'package:imdad/features/inventory/ration_order_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة طلبيات الإعاشة — وتحديدًا طريق الاعتماد بالكميات.
///
/// [RationRepo.approve] يقبل كمياتٍ مقلَّصة منذ البداية، لكن الشاشة كانت
/// تعتمد المطلوب كلّه بضغطة، فتبقى القدرة حبيسة الطبقة. هذه الاختبارات تحرس
/// الطريق من الشاشة إلى القاعدة، لا الطبقة وحدها.
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

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(host(const RationOrderScreen()));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  /// يمرّر الأطر حتى تستقرّ القراءات غير المتزامنة.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();
  }

  /// يفتح ورقة الاعتماد. الزر في آخر الصفحة، فيُمرَّر إليه أولًا: نقرةٌ على
  /// ما هو خارج إطار الاختبار لا تصيب هدفها.
  Future<void> openApprove(WidgetTester tester) async {
    final btn = find.byTooltip('اعتماد بالكميات');
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn, warnIfMissed: false);
    await settle(tester);
  }

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(Dialog), matching: matching);

  /// طلبية مرسلة: ١٠٠ مطلوبة، و٦٠ فقط في رصيد المورِّد.
  Future<String> seedPending({double stock = 60}) async {
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
          qty: Value(stock),
          date: const Value('2026-01-01'),
        ));

    final repo = RationRepo(db);
    await repo.save(
      requestingWarehouse: 'الفرع',
      supplyingWarehouse: 'الرئيسي',
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
    return id;
  }

  testWidgets('الشاشة تُبنى بطلبية مرسلة وتعرض زر الاعتماد', (tester) async {
    await seedPending();
    await show(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('اعتماد بالكميات'), findsOneWidget);
  });

  testWidgets('ورقة الاعتماد تفتح بالمطلوب وتُظهر رصيد المورِّد',
      (tester) async {
    await seedPending();
    await show(tester);

    await openApprove(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('اعتماد الطلبية'), findsWidgets);
    expect(find.textContaining('متاح'), findsWidgets,
        reason: 'الاعتماد بلا رصيد المورِّد قرارٌ على عمياء');
    // الحقل يفتح بالمطلوب، فالإقرار الكامل يبقى ضغطةً واحدة.
    expect(inSheet(find.widgetWithText(TextField, '100.0')), findsOneWidget);
  });

  testWidgets('«تقليص إلى المتاح» يعتمد ٦٠ لا ١٠٠ ويحفظها', (tester) async {
    final id = await seedPending(stock: 60);
    await show(tester);

    await openApprove(tester);

    await tester.tap(find.text('تقليص إلى المتاح'));
    await tester.pumpAndSettle();
    expect(inSheet(find.widgetWithText(TextField, '60.0')), findsOneWidget);

    await tester.tap(find.text('اعتماد'));
    await settle(tester);

    final full = await RationRepo(db).byId(id);
    expect(full!.order.status, RationStatus.approved);
    expect(full.lines.single.approvedQty, 60,
        reason: 'التقليص من الشاشة لم يصل إلى القاعدة');
    expect(full.lines.single.requestedQty, 100,
        reason: 'المطلوب الأصلي يبقى مسجَّلًا ليُعرف حجم العجز');
  });

  testWidgets('الاعتماد بأكثر من المطلوب ممنوع', (tester) async {
    await seedPending();
    await show(tester);

    await openApprove(tester);

    await tester.enterText(inSheet(find.byType(TextField)).first, '150');
    await tester.pumpAndSettle();

    expect(find.textContaining('تتجاوز المطلوبة'), findsWidgets,
        reason: 'الاعتماد زيادةً على ما طلبه الفرع قرارٌ من طرف واحد');
  });

  testWidgets('تصفير كل السطور يمنع الاعتماد', (tester) async {
    await seedPending();
    await show(tester);

    await openApprove(tester);

    await tester.tap(find.text('تصفير الكل'));
    await tester.pumpAndSettle();

    expect(find.textContaining('لا شيء يُستلم'), findsWidgets,
        reason: 'طلبية بلا كمية تُرفض لا تُعتمد صفرًا');
  });
}
