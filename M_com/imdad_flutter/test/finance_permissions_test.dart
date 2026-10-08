import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart' show ImdIconButton;
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/features/linkages/link_finances.dart';
import 'package:imdad/features/linkages/linkages_screen.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مصفوفة الصلاحيات على شاشة المالية: ما يظهر لكل مستخدم بحسب إجراءاته على
/// صفحة `linkages`. من لا يملك العرض لا يرى شيئًا، ومن يملكه وحده لا يرى زرَّ
/// إنشاءٍ ولا تصديرٍ ولا طباعةٍ ولا حذفٍ ولا اعتماد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seed(AppDatabase db) async {
    final repo = LinkageRepo(db);
    await repo.insertCustody(const LinkFinCustodiesCompanion(
      id: Value('a'), title: Value('عهدة'), amount: Value(1000), receiverName: Value('سالم'), custodyDate: Value('2026-10-01')));
    await repo.insertContract(const LinkPurchaseContractsCompanion(id: Value('k'), title: Value('بهارات'), amount: Value(300), custodyId: Value('a')));
    await repo.saveCustodySheet(
        sheetNo: 'S1', title: 't', defaultRate: 400, notes: '', custodyId: 'a', currency: 'sar',
        rows: const [LinkCustodySheetRowsCompanion(spentSar: Value(300))]);
    await repo.saveCustodyClearance(custodyId: 'a', clearanceDate: '2026-10-05', workflow: LinkageRepo.wfDraft);
    // إخلاء مُعتمد لعهدةٍ أخرى.
    await repo.insertCustody(const LinkFinCustodiesCompanion(id: Value('c'), title: Value('مُعتمدة'), amount: Value(50), receiverName: Value('خالد')));
    await repo.saveCustodyClearance(custodyId: 'c', clearanceDate: '2026-10-06');
  }

  /// يبني الشاشة بمستخدمٍ صلاحياته [actions] على `linkages` (null = بلا صلاحية للصفحة).
  Future<void> pumpAs(WidgetTester tester, List<String>? actions, {bool screen = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = AuthService(db);
    await tester.runAsync(() async {
      await UsersRepo(db).createUser(
        username: 'limited',
        password: 'Test@12345',
        name: 'محدود',
        permissions: {if (actions != null) 'linkages': {for (final a in actions) a: true}},
      );
      await auth.login('limited', 'Test@12345');
      await seed(db);
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: screen ? const LinkFinancesScreen() : LinkFinancesTab(repo: LinkageRepo(db), perm: Perm(auth)),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
  }

  /// يُبحث بخاصية `tooltip` على الودجة نفسها لا بنصٍّ في الشجرة: التلميحة
  /// تُرسَم في الطبقة العائمة عند الوقوف بالمؤشّر وحده، فلا يجدها `find.text`.
  Finder tip(String t) => find.byWidgetPredicate((w) => w is ImdIconButton && w.tooltip == t);

  testWidgets('بلا صلاحية الصفحة: لا يرى شيئًا', (tester) async {
    await pumpAs(tester, null, screen: true);
    expect(find.text('لا تملك صلاحية العرض'), findsOneWidget);
    expect(find.text('تسجيل عهدة'), findsNothing);
    expect(find.text('كشف حساب مالية'), findsNothing);
  });

  testWidgets('العرض وحده: لا إنشاء ولا تعديل ولا حذف ولا تصدير ولا طباعة ولا اعتماد', (tester) async {
    await pumpAs(tester, ['view']);
    // العهد
    expect(find.text('عهدة'), findsWidgets);
    expect(find.text('تسجيل عهدة'), findsNothing);
    expect(find.text('تصدير Excel'), findsNothing);
    expect(tip('تعديل'), findsNothing);
    expect(tip('حذف'), findsNothing);
    expect(tip('إخلاء العهدة'), findsNothing);
    expect(tip('تفاصيل العهدة والعقود المرتبطة'), findsWidgets, reason: 'العرض متاح');
    expect(find.text('كشف حساب مالية'), findsOneWidget);

    await openTab(tester, 'الإخلاءات');
    expect(find.text('تسجيل إخلاء'), findsNothing);
    expect(find.text('تصدير Excel'), findsNothing);
    expect(tip('طباعة الإخلاء'), findsNothing);
    expect(tip('حذف'), findsNothing);
    expect(tip('عرض'), findsWidgets, reason: 'عرض الإخلاء متاح للقراءة');
    expect(tip('فتح وتعديل'), findsNothing);

    await openTab(tester, 'عقود الشراء');
    expect(find.text('عقد جديد'), findsNothing);
    expect(find.text('تصدير Excel'), findsNothing);
    expect(tip('طباعة العقد'), findsNothing);
    expect(tip('حذف'), findsNothing);
    expect(tip('تسجيل إخلاء'), findsNothing);
    expect(tip('عرض'), findsWidgets);

    await openTab(tester, 'مسير العهدة');
    expect(find.text('مسير عهدة جديد'), findsNothing);
    expect(find.text('استيراد من Excel'), findsNothing);
    expect(find.text('تصدير Excel'), findsNothing);
    expect(tip('طباعة المسير'), findsNothing);
    expect(tip('حذف'), findsNothing);
    expect(tip('عرض'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('عرض + طباعة + تصدير: يظهران، دون إنشاء أو حذف', (tester) async {
    await pumpAs(tester, ['view', 'print', 'export']);
    expect(find.text('تصدير Excel'), findsOneWidget);
    expect(find.text('تسجيل عهدة'), findsNothing);

    await openTab(tester, 'الإخلاءات');
    expect(find.text('تصدير Excel'), findsOneWidget);
    expect(tip('طباعة الإخلاء'), findsWidgets);
    expect(find.text('تسجيل إخلاء'), findsNothing);

    await openTab(tester, 'عقود الشراء');
    expect(tip('طباعة العقد'), findsWidgets);
    expect(find.text('تصدير Excel'), findsOneWidget);

    await openTab(tester, 'مسير العهدة');
    expect(tip('طباعة المسير'), findsWidgets);
    expect(find.text('تصدير Excel'), findsOneWidget, reason: 'تصدير المسيرات');
    expect(find.text('مسير عهدة جديد'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الإنشاء والتعديل والحذف بلا اعتماد: حذف الإخلاء المُعتمد ممنوع', (tester) async {
    await pumpAs(tester, ['view', 'create', 'edit', 'delete']);
    expect(find.text('تسجيل عهدة'), findsOneWidget);
    expect(tip('تعديل'), findsWidgets);
    expect(tip('حذف'), findsWidgets);
    expect(tip('إخلاء العهدة'), findsWidgets);
    expect(find.text('تصدير Excel'), findsNothing);

    await openTab(tester, 'الإخلاءات');
    expect(find.text('تسجيل إخلاء'), findsOneWidget);
    expect(tip('فتح وتعديل'), findsWidgets);
    expect(tip('طباعة الإخلاء'), findsNothing);
  });

  testWidgets('حذف الإخلاء: المسودة بـdelete، والمُعتمد يلزمه approve', (tester) async {
    await pumpAs(tester, ['view', 'delete']);
    await openTab(tester, 'الإخلاءات');
    expect(tip('حذف'), findsNWidgets(1), reason: 'المسودة وحدها');
  });

  testWidgets('مع approve يظهر حذف المُعتمد أيضًا، وزر الاعتماد في النموذج', (tester) async {
    await pumpAs(tester, ['view', 'delete', 'approve']);
    await openTab(tester, 'الإخلاءات');
    expect(tip('حذف'), findsNWidgets(2));
  });

  testWidgets('approve بلا delete: حذف المُعتمد فقط', (tester) async {
    await pumpAs(tester, ['view', 'approve']);
    await openTab(tester, 'الإخلاءات');
    expect(tip('حذف'), findsNWidgets(1), reason: 'المُعتمد وحده');
  });
}
