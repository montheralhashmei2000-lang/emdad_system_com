import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_layout.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// المؤشرات: شريطٌ رفيعٌ واحد افتراضًا، والبطاقات الكبيرة للّوحات وحدها.
///
/// كانت كل شاشةٍ تبدأ بشبكة بطاقاتٍ كبيرة (نحو ٢٣٠ بكسل لستّة مؤشرات) قبل
/// جدولها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // خط التطبيق الحقيقي: خط Ahem في الاختبارات يرسم كل حرفٍ مربعًا بعرض حجم
  // الخط فيضاعف عرض النص العربي ويلفّ الشريط على سطرٍ لا يلتفّ على الجهاز.
  setUpAll(() async {
    final loader = FontLoader('IBMPlexSansArabic');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$w.ttf'));
    }
    await loader.load();
  });

  Widget host(Widget child, {double width = 1400}) => MaterialApp(
        theme: AppTheme.light(),
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

  const six = [
    ImdKpi(label: 'إجمالي الطلبيات', value: '١٢'),
    ImdKpi(label: 'مسودات', value: '٣', icon: 'file'),
    ImdKpi(label: 'بانتظار الاعتماد', value: '٢', extra: ImdChip('يحتاج إجراء', tone: ImdTone.pend)),
    ImdKpi(label: 'معتمدة', value: '٤'),
    ImdKpi(label: 'عاجلة مفتوحة', value: '١', spark: [1, 3, 2, 5]),
    ImdKpi(label: 'منفَّذة', value: '٩'),
  ];

  bool hasSpark(WidgetTester tester) => find
      .byType(CustomPaint)
      .evaluate()
      .any((e) => (e.widget as CustomPaint).painter is ImdSparkPainter);

  testWidgets('الافتراضي شريطٌ واحدٌ رفيع: ستة مؤشرات في سطرٍ واحد', (tester) async {
    await tester.pumpWidget(host(const ImdKpis(children: six)));
    expect(tester.takeException(), isNull);
    final h = tester.getSize(find.byType(ImdKpis)).height;
    // ~٤٠ بكسل + هامش ١٢ أسفله؛ الشبكة القديمة كانت نحو ٢٣٠.
    expect(h, lessThanOrEqualTo(60), reason: 'ارتفاع الشريط $h');
    expect(find.text('يحتاج إجراء'), findsOneWidget, reason: 'الشارة بجانب القيمة لا تُسقط');
    expect(hasSpark(tester), isFalse, reason: 'خط الاتجاه للبطاقة الكبيرة وحدها');
  });

  testWidgets('large: true ⇒ البطاقات الكبيرة القديمة بخط الاتجاه', (tester) async {
    await tester.pumpWidget(host(const ImdKpis(large: true, children: six)));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ImdKpis)).height, greaterThan(150));
    expect(hasSpark(tester), isTrue);
  });

  testWidgets('ImdKpi خارج ImdKpis يبقى بطاقةً كبيرة كما كان', (tester) async {
    await tester.pumpWidget(host(const ImdKpi(label: 'المستخدم', value: 'admin', spark: [1, 2])));
    expect(tester.getSize(find.byType(ImdKpi)).height, greaterThan(70));
    expect(hasSpark(tester), isTrue);
  });

  testWidgets('على هاتف ٣٢٠: الشريط يلتفّ ولا يفيض', (tester) async {
    await tester.pumpWidget(host(const ImdKpis(children: six), width: 320));
    expect(tester.takeException(), isNull);
  });
}
