import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// زرُّ الأيقونة يحمل اسمًا منطوقًا ومرئيًّا.
///
/// `ImdIconButton` يُرسَم بـ`label: ''` — فالأيقونة وحدها، و[tooltip] اسمُه
/// الوحيد. وكان الوسيط يُستقبَل ويُهمَل في البناء: لا تلميحةَ على سطح المكتب،
/// ولا شيءَ ينطقه قارئُ الشاشة، في ١١٤ موضعًا من الشاشات.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('التلميحة تصل إلى الشجرة فتُنطق وتُعرض', (tester) async {
    // تُفعَّل الدلالات **قبل** البناء: شجرتُها لا تُبنى بأثرٍ رجعي.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(
      ImdIconButton(icon: 'printer', tooltip: 'طباعة', onPressed: () {}),
    ));

    final tip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, 'طباعة');

    // ودلالةُ الاسم: ما يجده قارئ الشاشة. `Tooltip` وحده لا يكفي — الرسالة
    // تلحق بالطبقة العائمة حين تظهر، فلزم `Semantics` صريحًا على الزر.
    expect(find.bySemanticsLabel('طباعة'), findsOneWidget,
        reason: 'قارئ الشاشة لا يجد اسمًا لزرٍّ بأيقونةٍ وحدها');
    handle.dispose();
  });

  testWidgets('تلميحةٌ غائبة أو فارغة لا تُضيف عقدةً فارغة', (tester) async {
    await tester.pumpWidget(wrap(ImdIconButton(icon: 'printer', onPressed: () {})));
    expect(find.byType(Tooltip), findsNothing);

    await tester.pumpWidget(wrap(
      ImdIconButton(icon: 'printer', tooltip: '   ', onPressed: () {}),
    ));
    expect(find.byType(Tooltip), findsNothing, reason: 'مسافاتٌ ليست اسمًا');
  });

  testWidgets('الزر يبقى عاملًا مع التلميحة', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      ImdIconButton(icon: 'printer', tooltip: 'طباعة', onPressed: () => taps++),
    ));
    await tester.tap(find.byType(ImdIconButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('التلميحة تظهر عند الوقوف بالمؤشّر', (tester) async {
    await tester.pumpWidget(wrap(
      ImdIconButton(icon: 'printer', tooltip: 'طباعة', onPressed: () {}),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(ImdIconButton)));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('طباعة'), findsOneWidget);
  });
}
