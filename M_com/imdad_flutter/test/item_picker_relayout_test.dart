import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/inventory/doc_kit.dart';

/// محاولة إعادة إنتاج «الوميض الأحمر»: القائمة المنسدلة تُبنى عبر
/// OverlayPortal، وتخطيطها مؤجَّلٌ يقوده حقلُها نفسه (layout surrogate).
/// فإن أُعيد تخطيط الحقل والقائمة مفتوحة، قد يُطلب تخطيط الطبقة المؤجَّلة
/// مرتين في الإطار الواحد — وهناك يقع التأكيد.
void main() {
  late AppDatabase db;
  late List<Item> items;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final catalog = CatalogRepo(db);
    await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await catalog.saveItem(
      code: 'S1',
      name: 'سكر',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    items = await catalog.items();
  });

  tearDown(() => db.close());

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Align(alignment: Alignment.topRight, child: child)),
        ),
      );

  Widget picker() => ImdItemPicker(items: items, value: '', onChanged: (_) {});

  Future<void> openList(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'أ');
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('تغيّر عرض الحقل والقائمة مفتوحة', (tester) async {
    await tester.pumpWidget(host(SizedBox(width: 420, child: picker())));
    await openList(tester);
    expect(find.text('أرز'), findsOneWidget);

    // العرض يتغيّر بينما القائمة مفتوحة — كما يحدث حين يظهر عمودٌ جديد في
    // جدول الإدخال فيضيق عمود الصنف.
    await tester.pumpWidget(host(SizedBox(width: 260, child: picker())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('إزالة الحقل من الشجرة والقائمة مفتوحة', (tester) async {
    await tester.pumpWidget(host(SizedBox(width: 420, child: picker())));
    await openList(tester);

    await tester.pumpWidget(host(const SizedBox(width: 420)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('تمرير الصفحة والقائمة مفتوحة', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(host(SizedBox(
      width: 420,
      height: 300,
      child: SingleChildScrollView(
        controller: scroll,
        child: Column(children: [
          const SizedBox(height: 120),
          picker(),
          const SizedBox(height: 900),
        ]),
      ),
    )));
    await openList(tester);

    scroll.jumpTo(80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
