import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// جدول الإدخال الكثيف في سند الصرف — الأسلوب نفسه الموحَّد مع الاستلام،
/// وأعمدته الخاصة (الوحدة المستفيدة، الملاحظة).
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
    await catalog.saveUnit(code: 'U1', name: 'السرية الأولى');
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'issue')),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: IssueScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  ImdTable table(WidgetTester tester) => tester.widget<ImdTable>(find.byType(ImdTable));

  testWidgets('أعمدة الصرف بترتيبها، بلا الوحدة المستفيدة في التوجيه المفرد',
      (tester) async {
    await pump(tester);
    final titles = [for (final c in table(tester).columns) c.label];
    expect(titles, ['الصنف', 'الرصيد', 'الوحدة', 'الكمية', 'ملاحظة', '']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الأسلوب موحَّدٌ مع الاستلام: رأسٌ بالتمييز، شبكة، خطّ ١٢',
      (tester) async {
    await pump(tester);
    final t = table(tester);
    final c = tester.element(find.byType(ImdTable)).imd;
    expect(t.headerBackground, c.accent);
    expect(t.headerForeground, c.onAccent);
    expect(t.gridLines, isTrue);
    expect(t.cellFontSize, 12);
    expect(t.cards, isFalse);
    expect(t.maxHeight, isNotNull);
  });
}
