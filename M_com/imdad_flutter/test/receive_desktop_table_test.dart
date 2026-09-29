import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/receive_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// جدول الإدخال الكثيف في سند الوارد على سطح المكتب: رأسٌ ثابتٌ بلون
/// التمييز، وعمودا «نوع العملية»/«تاريخ الانتهاء» شرطيّان على مستوى
/// الجدول كله — يظهر العمود إن احتاجه أيّ صفٍّ، لا صفٍّ بعينه.
void main() {
  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
    await auth.login('admin', 'Test@12345');
    final catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await catalog.saveItem(
      code: 'G1',
      name: 'أسطوانة غاز',
      baseUnit: 'أسطوانة',
      units: const [ItemUnit(name: 'أسطوانة', factor: 1, isBase: true)],
      isRefillable: true,
    );
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  Finder deskTable() => find.byType(ImdTable);

  Future<void> pickItem(WidgetTester tester, String name, int fieldIndex) async {
    final field = find.descendant(of: deskTable(), matching: find.byType(TextField)).at(fieldIndex);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, name);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  testWidgets('بلا صنفٍ مختار: عمودا نوع العملية وتاريخ الانتهاء غائبان',
      (tester) async {
    await pump(tester);
    final table = tester.widget<ImdTable>(deskTable());
    final titles = [for (final c in table.columns) c.label];
    expect(titles, ['الصنف', 'الوحدة', 'الكمية', '']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('رأس الجدول بلون التمييز ونصٍّ يتبع onAccent', (tester) async {
    await pump(tester);
    final table = tester.widget<ImdTable>(deskTable());
    final ctx = tester.element(deskTable());
    final c = ctx.imd;
    expect(table.headerBackground, c.accent);
    expect(table.headerForeground, c.onAccent);
  });

  testWidgets('اختيار صنفٍ عادي: عمود تاريخ الانتهاء يظهر، ونوع العملية يبقى غائبًا',
      (tester) async {
    await pump(tester);
    await pickItem(tester, 'أرز', 0);

    final table = tester.widget<ImdTable>(deskTable());
    final titles = [for (final c in table.columns) c.label];
    expect(titles, contains('تاريخ الانتهاء'));
    expect(titles, isNot(contains('نوع العملية')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'اختيار صنفٍ قابل للتعبئة: عمود نوع العملية يظهر بلا طفح تخطيط (الحارس ضد الخلل المُصلَح)',
      (tester) async {
    await pump(tester);
    await pickItem(tester, 'أسطوانة غاز', 0);

    final table = tester.widget<ImdTable>(deskTable());
    final titles = [for (final c in table.columns) c.label];
    expect(titles, contains('نوع العملية'));
    expect(titles, isNot(contains('تاريخ الانتهاء')));
    // زرّا النسخ والحذف معًا في عمود الإجراء الضيّق أطفحا القياس ١٤px عند
    // أول تنفيذ — هذا الحارس المباشر ضد رجوعه.
    expect(tester.takeException(), isNull);
  });
}
