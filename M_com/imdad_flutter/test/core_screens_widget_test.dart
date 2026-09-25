import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/catalog/items_screen.dart';
import 'package:imdad/features/catalog/kitchens_screen.dart';
import 'package:imdad/features/catalog/suppliers_screen.dart';
import 'package:imdad/features/catalog/units_screen.dart';
import 'package:imdad/features/catalog/warehouses_screen.dart';
import 'package:imdad/features/daily/daily_operations_screen.dart';
import 'package:imdad/features/daily/kitchen_log_screen.dart';
import 'package:imdad/features/daily/ratios_screen.dart';
import 'package:imdad/features/daily/strength_screen.dart';
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:imdad/features/inventory/opening_screen.dart';
import 'package:imdad/features/inventory/pending_screen.dart';
import 'package:imdad/features/inventory/receive_screen.dart';
import 'package:imdad/features/inventory/returns_screen.dart';
import 'package:imdad/features/inventory/transfer_screen.dart';
import 'package:imdad/features/reports/balances_screen.dart';
import 'package:imdad/features/reports/reports_center_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اختبارات واجهة لشاشات الاستعمال اليومي — الصرف والاستلام والتحويل والجرد
/// والتقارير والأدلة.
///
/// هذه أكثر شاشات النظام استعمالًا وأكثرها تعديلًا، وكانت بلا اختبار واجهة
/// واحد. الغرض ليس التقاط البكسل بل التأكد من أن كلًّا منها **تُبنى وتُرسَم**
/// بقاعدة فارغة وبقاعدة فيها بيانات، بلا شاشة حمراء. أكثر ما ينكسر في شاشة
/// إدخال يقع في أول إطار: قائمة فارغة تُقرأ بـ`.first`، أو قيمة منسدلة لا
/// تطابق أي خيار، أو رصيد يُقسم على صفر.
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
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  /// بيانات صغيرة لكنها كاملة الأركان: صنف ووحدته، ومستودعان (التحويل يلزمه
  /// طرفان)، ومعسكر ومنشأة ومورّد، ورصيد افتتاحي وحركات فعلية.
  Future<void> seed() async {
    final catalog = CatalogRepo(db);
    await catalog.saveItem(
      code: 'X1',
      name: 'رز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    final item = (await catalog.items()).single;

    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرعي'));
    await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(id: 'sup1', name: 'مورّد الإعاشة'));
    await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
          id: 'camp1',
          name: 'المعسكر الأول',
          type: const Value('camp'),
          isCamp: const Value(true),
        ));
    await db.into(db.facilities).insert(FacilitiesCompanion.insert(
        id: 'fac1', name: 'مطبخ المعسكر', warehouse: const Value('الرئيسي')));
    await db.into(db.entitlements).insert(EntitlementsCompanion.insert(
          itemId: item.id,
          itemName: Value(item.name),
          qtyPerPerson: const Value(30),
        ));
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: item.id,
          itemName: Value(item.name),
          warehouse: const Value('الرئيسي'),
          qty: const Value(1000),
          date: const Value('2026-01-01'),
        ));
    await db.into(db.strengths).insert(StrengthsCompanion.insert(
          id: Ids.next('st'),
          unitId: 'camp1',
          campId: const Value('camp1'),
          campName: const Value('المعسكر الأول'),
          strengthDate: '2026-06-01',
          total: const Value(500),
        ));
    await db.into(db.issues).insert(IssuesCompanion.insert(
          id: Ids.next('is'),
          refNo: const Value('ص-1'),
          date: const Value('2026-06-02'),
          warehouse: const Value('الرئيسي'),
          itemId: Value(item.id),
          itemName: Value(item.name),
          qty: const Value(50),
          baseQty: const Value(50),
          beneficiaryUnitId: const Value('camp1'),
          beneficiaryUnitName: const Value('المعسكر الأول'),
        ));
    await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          id: Ids.next('rc'),
          refNo: const Value('و-1'),
          date: const Value('2026-06-01'),
          warehouse: const Value('الرئيسي'),
          itemId: Value(item.id),
          itemName: Value(item.name),
          qty: const Value(200),
          baseQty: const Value(200),
          supplier: const Value('مورّد الإعاشة'),
        ));
    await db.into(db.kitchenLogs).insert(KitchenLogsCompanion.insert(
          id: Ids.next('kl'),
          date: '2026-06-02',
          facilityId: 'fac1',
          facilityName: const Value('مطبخ المعسكر'),
          mealType: const Value('LUNCH'),
          itemId: Value(item.id),
          baseQty: const Value(40),
          strength: const Value(500),
        ));
  }

  final screens = <String, Widget Function()>{
    'الأصناف': () => const ItemsScreen(),
    'المستودعات': () => const WarehousesScreen(),
    'الوحدات المستفيدة': () => const UnitsScreen(),
    'الموردون': () => const SuppliersScreen(),
    'المطابخ والأفران': () => const KitchensScreen(),
    'الاستلام': () => const ReceiveScreen(),
    'الصرف': () => const IssueScreen(),
    'التحويل': () => const TransferScreen(),
    'المرتجعات': () => const ReturnsScreen(),
    'الأرصدة الافتتاحية': () => const OpeningScreen(),
    'السندات المعلّقة': () => const PendingScreen(),
    'حصر القوة': () => const StrengthScreen(),
    'نسب المقرر': () => const RatiosScreen(),
    'سجل الطهي': () => const KitchenLogScreen(),
    'التخطيط والتشغيل اليومي': () => const DailyOperationsScreen(),
    'الأرصدة': () => const BalancesScreen(),
    'مركز التقارير': () => const ReportsCenterScreen(),
  };

  group('كل شاشة تُبنى بقاعدة فارغة', () {
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        await show(tester, e.value());
        expect(tester.takeException(), isNull);
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

  testWidgets('مركز التقارير يتنقّل بين تقاريره بلا انهيار', (tester) async {
    await seed();
    await show(tester, const ReportsCenterScreen());
    // التنقّل بين التقارير يغيّر نافذة البيانات المحمَّلة: تقرير الأرصدة يلزمه
    // التاريخ كاملًا، وتقرير الحركات شهرٌ واحد. الانتقال بينهما يعيد التحميل،
    // وهنا يظهر أي خلل في اتساع النافذة أو في إعادة البناء بعدها.
    for (final name in const [
      'تقرير أرصدة المخزون',
      'تحليل الاستهلاك',
      'حركة المخزون اليومية',
    ]) {
      final tile = find.text(name);
      if (tile.evaluate().isEmpty) continue;
      await tester.ensureVisible(tile.first);
      await tester.pumpAndSettle();
      await tester.tap(tile.first, warnIfMissed: false);
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'عند فتح «$name»');
    }
  });

  testWidgets('شاشة الأرصدة تعرض الصنف بعد حركاته', (tester) async {
    await seed();
    await show(tester, const BalancesScreen());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('رز'), findsWidgets);
  });
}
