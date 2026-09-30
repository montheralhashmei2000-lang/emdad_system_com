import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/features/inventory/doc_kit.dart';

/// توحيد أسلوب جداول الإدخال.
///
/// الشاشات الخمس تمرّ كلّها من [ImdEntryTable]، فالأسلوب موروثٌ لا مُتَّفقٌ
/// عليه. وهذا الاختبار يحرس الميراث نفسه: ما دام كل جدولٍ يُبنى من هنا،
/// فتبديل قيمةٍ هنا يبدّلها في الخمس معًا — ولا يمكن لشاشةٍ أن تنحرف.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1400, 900)),
            child: Scaffold(body: child),
          ),
        ),
      );

  ImdEntryTable sample() => ImdEntryTable(
        columns: const [ImdCol('الصنف', flex: 3), ImdCol('الكمية', width: 88)],
        rowKeys: [UniqueKey()],
        rows: [
          [ImdEntryTable.cell(const Text('أرز')), ImdEntryTable.cell(const Text('5'))],
        ],
      );

  testWidgets('الأسلوب: رأسٌ بالتمييز، شبكة، خطّ ١٢، بلا بطاقات، بسقفٍ للتمرير',
      (tester) async {
    await tester.pumpWidget(host(sample()));
    final t = tester.widget<ImdTable>(find.byType(ImdTable));
    final c = tester.element(find.byType(ImdTable)).imd;

    expect(t.headerBackground, c.accent, reason: 'رأسٌ بلون التمييز');
    expect(t.headerForeground, c.onAccent, reason: 'نصُّ الرأس يقابله');
    expect(t.gridLines, isTrue, reason: 'حدٌّ لكل خلية');
    expect(t.cellFontSize, 12);
    expect(t.cellPadding, const EdgeInsets.symmetric(horizontal: 4));
    expect(t.cards, isFalse, reason: 'جدولٌ دومًا على سطح المكتب');
    expect(t.maxHeight, isNotNull, reason: 'سقفٌ يُثبّت الرأس ويُمرّر الجسم');
  });

  testWidgets('ارتفاع الصفّ ثابتٌ ٤٠ مهما اختلف محتوى الخلية', (tester) async {
    // محتوياتٌ مختلفة الارتفاع جدًّا: نصٌّ قصير، وصندوقٌ ضئيل، وآخر أطول من
    // الصفّ نفسه — والخلية تفرض ٤٠ على الثلاثة.
    const keys = <Key>[Key('قصير'), Key('ضئيل'), Key('طويل')];
    await tester.pumpWidget(host(Column(children: [
      ImdEntryTable.cell(const Text('نصّ قصير', key: Key('قصير'))),
      ImdEntryTable.cell(const SizedBox(key: Key('ضئيل'), height: 4)),
      ImdEntryTable.cell(const SizedBox(key: Key('طويل'), height: 90)),
    ])));

    for (final k in keys) {
      final cellBox = find.ancestor(of: find.byKey(k), matching: find.byType(SizedBox)).last;
      expect(tester.getSize(cellBox).height, ImdEntryTable.rowHeight,
          reason: 'الخلية تفرض ارتفاعها على محتواها مهما كان');
    }
  });

  testWidgets('الحقول داخل الجدول مضغوطة (ImdCompact مُعلَنٌ فوقها)', (tester) async {
    late bool compact;
    await tester.pumpWidget(host(ImdEntryTable(
      columns: const [ImdCol('الصنف')],
      rowKeys: [UniqueKey()],
      rows: [
        [
          Builder(builder: (ctx) {
            compact = ImdCompact.of(ctx);
            return const Text('x');
          }),
        ],
      ],
    )));
    expect(compact, isTrue, reason: 'الكثافة تُعلَن مرةً فوق الجدول لا لكل حقل');
  });

  test('ارتفاع الحقل المدمج ٣٤ على سطح المكتب، و٤٠ على اللمس (حدُّ إتاحة)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ImdSizes.compactField, 34, reason: 'مطابقةً لحقل الصنف');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(ImdSizes.compactField, 40, reason: 'هدف اللمس لا يُصغَّر تحت ٤٠');
    debugDefaultTargetPlatformOverride = null;
  });

  test('مقاسات النمط المدمج تطابق المواصفة', () {
    expect(ImdSizes.compactRadius, 6);
    expect(ImdSizes.compactPadH, 4);
    expect(ImdSizes.compactPadV, 2);
    expect(ImdSizes.compactGap, 4, reason: 'بين الأعمدة');
    expect(ImdSizes.compactRowGap, 2, reason: 'بين الصفوف');
  });
}
