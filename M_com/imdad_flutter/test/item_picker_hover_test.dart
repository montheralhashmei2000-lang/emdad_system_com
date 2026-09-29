import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/inventory/doc_kit.dart';

/// مرور الفأرة فوق اقتراحات المنتقي.
///
/// `MouseRegion.onEnter` يُطلق في مرحلة تتبّع الفأرة — **داخل الإطار بعد
/// التخطيط** لا من إيماءةٍ مستقلة. فأيّ `setState` منه يُعلّم عناصر الشجرة
/// محتاجةً للبناء أثناء التخطيط، وهو ما يرمي تأكيد
/// `scheduleLayoutCallback` إن كان في الشجرة `LayoutBuilder`.
void main() {
  late AppDatabase db;
  late List<Item> items;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final catalog = CatalogRepo(db);
    for (final (code, name) in [('R1', 'أرز'), ('R2', 'أرز بسمتي'), ('R3', 'أرز مصري')]) {
      await catalog.saveItem(
        code: code,
        name: name,
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
    }
    items = await catalog.items();
  });

  tearDown(() => db.close());

  /// `LayoutBuilder` فوق المنتقي — كما في الشاشات الحقيقية (ImdTable وقشرة
  /// الصفحة كلتاهما تضعان واحدًا فوق صفوف الإدخال).
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LayoutBuilder(
              builder: (context, _) => Align(alignment: Alignment.topRight, child: child),
            ),
          ),
        ),
      );

  testWidgets('المرور بالفأرة فوق الاقتراحات لا يرمي استثناء تخطيط', (tester) async {
    await tester.pumpWidget(host(
      SizedBox(width: 420, child: ImdItemPicker(items: items, value: '', onChanged: (_) {})),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'أرز');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('أرز بسمتي'), findsOneWidget);

    // فأرةٌ حقيقية تمرّ فوق الاقتراحات واحدًا بعد آخر.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    // «أرز» وحدها تطابق نصّ الحقل أيضًا، فيُمرّ على الاسمين المميَّزين.
    for (final name in ['أرز بسمتي', 'أرز مصري', 'أرز بسمتي']) {
      await mouse.moveTo(tester.getCenter(find.text(name)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('المرور ثم النقر لاختيار صنف لا يرمي استثناء', (tester) async {
    var picked = '';
    await tester.pumpWidget(host(
      SizedBox(width: 420, child: ImdItemPicker(items: items, value: '', onChanged: (v) => picked = v)),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'أرز');
    await tester.pump(const Duration(milliseconds: 100));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('أرز بسمتي')));
    await tester.pump();
    await tester.tap(find.text('أرز بسمتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(picked, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
