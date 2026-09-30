import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/features/inventory/doc_kit.dart';

/// منتقي الوحدة: يُكتب فيه أو يُختار — بديل القائمة المنسدلة.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(alignment: Alignment.topRight, child: SizedBox(width: 200, child: child)),
          ),
        ),
      );

  const units = ['كجم', 'كيس', 'كرتون'];

  testWidgets('الكتابة تُصفّي الخيارات', (tester) async {
    await tester.pumpWidget(host(
      ImdUnitPicker(units: units, value: '', onChanged: (_) {}),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('كيس'), findsOneWidget);
    expect(find.text('كرتون'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'كي');
    await tester.pump();
    expect(find.text('كيس'), findsOneWidget);
    expect(find.text('كرتون'), findsNothing);
  });

  testWidgets('النقر على خيارٍ يُبلّغ به', (tester) async {
    var picked = '';
    await tester.pumpWidget(host(
      ImdUnitPicker(units: units, value: '', onChanged: (v) => picked = v),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.text('كرتون'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(picked, 'كرتون');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter يختار أول نتيجةٍ مطابقة', (tester) async {
    var picked = '';
    await tester.pumpWidget(host(
      ImdUnitPicker(units: units, value: '', onChanged: (v) => picked = v),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'كرت');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(picked, 'كرتون');
  });

  testWidgets('المرور بالفأرة لا يرمي استثناء تخطيط', (tester) async {
    await tester.pumpWidget(host(
      // `LayoutBuilder` فوقه كما في الشاشات الحقيقية.
      LayoutBuilder(
        builder: (_, __) => ImdUnitPicker(units: units, value: '', onChanged: (_) {}),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final u in units) {
      await mouse.moveTo(tester.getCenter(find.text(u)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('قيمةٌ مُمرَّرة تظهر في الحقل', (tester) async {
    await tester.pumpWidget(host(
      ImdUnitPicker(units: units, value: 'كيس', onChanged: (_) {}),
    ));
    expect(find.widgetWithText(TextField, 'كيس'), findsOneWidget);
  });
}
