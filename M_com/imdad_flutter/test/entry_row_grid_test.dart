import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/features/inventory/doc_kit.dart';

/// سطر الصنف على الجوال: الوحدة والكمية لا تفترقان.
///
/// كان التخطيط في شاشات السندات الأربع يضع «الصنف والوحدة» في صفّ و«الكمية»
/// وحدها في صفٍّ تحته — فتنفصل الكميةُ عن وحدتها. المطلوب: الثلاثة في صفٍّ
/// واحد ما اتّسع العرض، وإلّا نزل الصنفُ وحده وبقيت الوحدة بجوار الكمية.
void main() {
  Widget host(double width, Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  Widget grid({(String, Widget)? leading, List<(String, Widget)> extras = const []}) =>
      ImdEntryRowGrid(
        item: const TextField(key: Key('item')),
        meta: 'رصيد ١٠٠ كجم',
        unit: const TextField(key: Key('unit')),
        qty: const TextField(key: Key('qty')),
        leading: leading,
        extras: extras,
        actions: const [SizedBox(key: Key('del'), width: 32, height: 32)],
      );

  /// مركز الحقل رأسيًّا — صفّان مختلفان ⇒ مركزان مختلفان.
  double midY(WidgetTester tester, String key) =>
      tester.getCenter(find.byKey(Key(key))).dy;

  testWidgets('عرضٌ واسع: الصنف والوحدة والكمية في صفٍّ واحد', (tester) async {
    await tester.pumpWidget(host(520, grid()));
    expect(midY(tester, 'unit'), closeTo(midY(tester, 'qty'), 1),
        reason: 'الوحدة والكمية في صفٍّ واحد');
    expect(midY(tester, 'item'), closeTo(midY(tester, 'qty'), 1),
        reason: 'والصنف معهما — لا صفَّ ثانٍ بلا داعٍ');
  });

  testWidgets('عرضٌ ضيّق: الصنف وحده، والوحدة بجوار الكمية', (tester) async {
    await tester.pumpWidget(host(260, grid()));
    expect(midY(tester, 'unit'), closeTo(midY(tester, 'qty'), 1),
        reason: 'الكمية لا تُترك وحدها في صفّ دون وحدتها');
    expect(midY(tester, 'item'), lessThan(midY(tester, 'qty')),
        reason: 'الصنف ينزل إلى صفّه وهو أحوج الحقول إلى العرض');
  });

  testWidgets('حقلٌ رابع (الوحدة المستفيدة) يُنزل الصنف ويبقي الثلاثة معًا', (tester) async {
    await tester.pumpWidget(host(
      520,
      grid(leading: ('الوحدة المستفيدة', const TextField(key: Key('ben')))),
    ));
    expect(midY(tester, 'ben'), closeTo(midY(tester, 'unit'), 1));
    expect(midY(tester, 'qty'), closeTo(midY(tester, 'unit'), 1));
    expect(midY(tester, 'item'), lessThan(midY(tester, 'unit')));
  });

  testWidgets('الحقول الثانوية في صفٍّ تحت الأساسية لا تزاحمها', (tester) async {
    await tester.pumpWidget(host(
      520,
      grid(extras: [('نوع العملية', const TextField(key: Key('cy')))]),
    ));
    expect(midY(tester, 'cy'), greaterThan(midY(tester, 'qty')));
    expect(midY(tester, 'unit'), closeTo(midY(tester, 'qty'), 1));
  });

  testWidgets('زرُّ الحذف يحاذي الحقول لا عناوينها', (tester) async {
    await tester.pumpWidget(host(520, grid()));
    // الزرُّ تحت عنوانٍ شفّاف يحجز ارتفاع العنوان، فمركزه قرب مركز الحقل.
    expect(midY(tester, 'del'), closeTo(midY(tester, 'qty'), 12));
  });

  testWidgets('لا فيض في أيٍّ من العرضين', (tester) async {
    for (final w in [240.0, 300.0, 360.0, 420.0, 520.0]) {
      await tester.pumpWidget(host(w, grid(
        extras: [('نوع العملية', const TextField(key: Key('cy')))],
      )));
      expect(tester.takeException(), isNull, reason: 'فيض عند عرض $w');
    }
  });
}
