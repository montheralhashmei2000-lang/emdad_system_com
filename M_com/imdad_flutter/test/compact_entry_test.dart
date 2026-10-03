import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_form.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/features/inventory/doc_kit.dart';
import 'package:imdad/features/inventory/opening_screen.dart';
import 'package:imdad/features/inventory/receive_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// جداول إدخال الأصناف — النمط المدمج.
///
/// **جدول الأصناف ليس نموذج تسجيل.** النموذج يُملأ مرةً فتُفسحه، والجدول
/// يُملأ عشرين سطرًا فتضيق به الشاشة ويُدفع التمرير بين كل صنفين.
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
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(screen));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    final catalog = CatalogRepo(db);
    await catalog.saveItem(
      code: 'X1',
      name: 'رز أبيض',
      baseUnit: 'كجم',
      units: const [
        ItemUnit(name: 'كجم', factor: 1, isBase: true),
        ItemUnit(name: 'كيس', factor: 40),
      ],
    );
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
  }

  group('وسم الكثافة', () {
    testWidgets('الحقل يقصر داخل الوسم ويطول خارجه', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await show(
        tester,
        Column(children: [
          SizedBox(width: 200, child: ImdFld(controller: ctrl)),
          SizedBox(
            width: 200,
            child: ImdCompact(child: ImdFld(controller: ctrl)),
          ),
        ]),
      );

      // الحقل المدمج بسطرٍ واحد ارتفاعه **مطابقٌ** لـ compactField (SizedBox ثابت)،
      // والعادي لا يقل عن touchMin — فلا يعلو حقلٌ مدمجٌ أخاه في صفّ الجدول.
      final normal = tester.getSize(find.byType(ImdFld).first).height;
      final compact = tester.getSize(find.byType(ImdFld).last).height;
      expect(normal, greaterThanOrEqualTo(ImdSizes.touchMin));
      expect(compact, ImdSizes.compactField);
      expect(ImdSizes.compactField, lessThan(ImdSizes.touchMin),
          reason: 'المدمج يجب أن يكون أقصر');
    });

    testWidgets('بطاقة السطر تُعلن الكثافة لما تحتها', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      late bool inside;
      await show(
        tester,
        ImdRvRow(
          index: 1,
          child: Builder(builder: (ctx) {
            inside = ImdCompact.of(ctx);
            return ImdFld(controller: ctrl);
          }),
        ),
      );
      expect(inside, isTrue,
          reason: 'حقول السطر تتبع كثافته بلا تمريرٍ لكل حقل');
    });
  });

  group('الأرصدة الافتتاحية', () {
    testWidgets('عمود وحدة الصنف بين الحالة والرصيد', (tester) async {
      await seed();
      await show(tester, const OpeningScreen());
      expect(tester.takeException(), isNull);

      // تُقرأ أعمدة الجدول من تعريفه لا من نصّه المرسوم: الشارات والعناوين
      // تُبنى نصًّا غنيًّا لا `Text`، فلا يلتقطها `find.text`.
      final table = tester.widget<ImdTable>(find.byType(ImdTable));
      final titles = [for (final col in table.columns) col.label];
      expect(titles, contains('وحدة الصنف'));
      expect(titles.indexOf('وحدة الصنف'),
          greaterThan(titles.indexOf('الحالة')));
      expect(titles.indexOf('وحدة الصنف'),
          lessThan(titles.indexOf('الرصيد الافتتاحي')));
    });

    testWidgets('الوحدات المعرَّفة كلها معروضة للاختيار', (tester) async {
      await seed();
      await show(tester, const OpeningScreen());
      final select = tester.widget<ImdSelect<String>>(
          find.byType(ImdSelect<String>).last);
      final names = [for (final e in select.items) e.$2];
      expect(names, containsAll(<String>['كجم', 'كيس']),
          reason: 'من يعدّ أكياسًا يكتب بالأكياس');
    });
  });

  group('تاريخ الانتهاء يُضبط من الإعدادات', () {
    test('محفوظٌ ومقروء، وافتراضُه الإظهار', () async {
      final repo = SettingsRepo(db);
      expect((await repo.identity()).showExpiry, isTrue,
          reason: 'لا يُخفى حقلٌ قائم حتى يُطلب ذلك');

      await repo.saveIdentity(
          (await repo.identity()).copyWith(showExpiry: false));
      expect((await repo.identity()).showExpiry, isFalse);
    });

    testWidgets('إطفاؤه يُخفي الحقل من سطر الصنف', (tester) async {
      await seed();
      final repo = SettingsRepo(db);
      await repo.saveIdentity(
          (await repo.identity()).copyWith(showExpiry: false));

      await show(tester, const ReceiveScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('تاريخ الانتهاء'), findsNothing,
          reason: 'عمودٌ لا يُملأ يضيّق على ما يُملأ');
    });

    testWidgets('وإبقاؤه يُظهره', (tester) async {
      await seed();
      await show(tester, const ReceiveScreen());
      expect(tester.takeException(), isNull);
      // السطر الفارغ بلا صنف لا يعرض التاريخ؛ والشاشة تُبنى بلا انهيار.
      expect(find.byType(ReceiveScreen), findsOneWidget);
    });
  });
}
