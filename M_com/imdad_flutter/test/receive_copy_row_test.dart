import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/doc_kit.dart';
import 'package:imdad/features/inventory/receive_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «دفعة أخرى من هذا الصنف» في سند الوارد.
///
/// الخطر الحقيقي هنا ليس الزرّ بل الدمج التلقائي: الشاشة تدمج السطور
/// المتطابقة في (صنف|أسطوانة|صلاحية) وتجمع كمياتها. فنسخةٌ تحمل كمية أصلها
/// كانت ستُبتلع فورًا وتُضاعف الكمية بدل أن تفتح سطرًا — وهذا ما يحرسه
/// الاختبار الأخير.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthService(db);
    await tester.runAsync(() async {
      await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
      final catalog = CatalogRepo(db);
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await catalog.saveItem(
        code: 'R1',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'receive')),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: ReceiveScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  Finder copyBtn() => find.byTooltip('دفعة أخرى من هذا الصنف');
  Finder rows() => find.byType(ImdItemPicker);

  /// حقول السطر الأول نصًّا: الأول حقل المنتقي والثاني الكمية (الوحدة قائمة
  /// منسدلة لا حقل نص). مُقيَّدٌ بجدول سطح المكتب لا الشجرة كلها — حقول رأس
  /// النموذج (لجنة الفحص، الملاحظات…) تستخدم TextField أيضًا، وهذا الاختبار
  /// يعمل بعرض سطح مكتب دومًا (١٥٠٠) فجدول الأصناف هو ImdTable الوحيد.
  Finder fieldInFirstRow(int i) => find
      .descendant(of: find.byType(ImdTable), matching: find.byType(TextField))
      .at(i);

  /// المنتقي يفتح قائمته بالكتابة، وEnter يختار أول نتيجة.
  Future<void> pickFirstItem(WidgetTester tester) async {
    final field = fieldInFirstRow(0);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'أرز');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  testWidgets('الزر لا يظهر لسطرٍ بلا صنف', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(copyBtn(), findsNothing);
  });

  testWidgets('بعد اختيار صنف يظهر الزر، ونقره يفتح سطرًا ثانيًا بالصنف نفسه',
      (tester) async {
    await pump(tester);
    await pickFirstItem(tester);
    expect(copyBtn(), findsWidgets);

    final before = tester.widgetList(rows()).length;
    await tester.tap(copyBtn().first);
    await tester.pump();

    // سطرٌ إضافي ظهر مباشرةً تحت أصله.
    expect(tester.widgetList(rows()).length, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('النسخة تنجو من الدمج التلقائي: كميتها فارغة فلا تُبتلع في أصلها',
      (tester) async {
    await pump(tester);
    await pickFirstItem(tester);

    await tester.enterText(fieldInFirstRow(1), '5');
    await tester.pump();
    final before = tester.widgetList(rows()).length;

    await tester.tap(copyBtn().first);
    await tester.pump();
    expect(tester.widgetList(rows()).length, before + 1);

    // الدمج لا يعمل إلا عند فتح سطرٍ جديد، فيُستدعى صراحةً هنا: هذه هي
    // اللحظة التي كانت ستُبتلع فيها النسخة لو حملت كمية أصلها.
    await tester.tap(find.widgetWithText(ImdButton, '+ سطر جديد'));
    // المنتقي يؤجّل إغلاق قائمته 150ms بعد فقد التركيز، فيُستنزف مؤقّته هنا
    // وإلا انتهى الاختبار ومؤقّتٌ معلّق.
    await tester.pump(const Duration(milliseconds: 300));

    // الأصل ما يزال بكميته لا بضعفها، والنسخة لم تختفِ.
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '10'), findsNothing);
    expect(tester.widgetList(rows()).length, greaterThan(before));
    expect(tester.takeException(), isNull);
  });
}
