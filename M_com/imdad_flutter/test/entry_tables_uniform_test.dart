import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_form.dart';
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
    // خلايا ملتصقة (CLAUDE.md §5): بلا حشو للخلية، وخط الشبكة وحده يفصل.
    expect(t.flushCells, isTrue, reason: 'خلايا ملتصقة على سطح المكتب');
    expect(t.cellPadding, isNull, reason: 'لا حشو للخلية');
    expect(t.cards, isFalse, reason: 'جدولٌ دومًا على سطح المكتب');
    expect(t.maxHeight, isNotNull, reason: 'سقفٌ يُثبّت الرأس ويُمرّر الجسم');
  });

  testWidgets('ارتفاع الصفّ ثابتٌ (= ارتفاع الحقل المدمج) مهما اختلف محتوى الخلية', (tester) async {
    // محتوياتٌ مختلفة الارتفاع جدًّا: نصٌّ قصير، وصندوقٌ ضئيل، وآخر أطول من
    // الصفّ نفسه — والخلية تفرض ارتفاعها على الثلاثة.
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
    expect(ImdSizes.compactPadH, 8);
    expect(ImdSizes.compactPadV, 6);
    expect(ImdSizes.compactGap, 4, reason: 'بين الأعمدة');
    expect(ImdSizes.compactRowGap, 2, reason: 'بين الصفوف');
  });

  group('صفوفٌ ملتصقة وخلايا بارتفاع الحقل', () {
    final fieldH = ImdSizes.compactField;
    final controllers = <TextEditingController>[];

    Widget realTable(int rows) {
      controllers.clear();
      return ImdEntryTable(
        columns: const [
          ImdCol('الصنف', flex: 3),
          ImdCol('الرصيد', width: 96),
          ImdCol('الكمية', width: 88),
          ImdCol('', width: 96),
        ],
        rowKeys: [for (var i = 0; i < rows; i++) ValueKey('r$i')],
        rows: [
          for (var i = 0; i < rows; i++)
            [
              ImdEntryTable.cell(ImdFld(controller: TextEditingController(text: 'صنف $i'))),
              ImdEntryTable.cell(ImdEntryBalanceCell('${i + 1}٠ كيس')),
              ImdEntryTable.cell(ImdFld(controller: TextEditingController(text: '5'))),
              ImdEntryTable.actions([
                ImdIconButton(icon: 'plus-square', onPressed: () {}),
                ImdIconButton(icon: 'x', kind: ImdBtnKind.danger, onPressed: () {}),
              ]),
            ],
        ],
      );
    }

    testWidgets('كل خلايا الصفّ بارتفاع الحقل نفسه: الرصيد والأزرار والحقول', (tester) async {
      await tester.pumpWidget(host(realTable(2)));

      for (final f in tester.widgetList<ImdFld>(find.byType(ImdFld))) {
        expect(tester.getSize(find.byWidget(f)).height, fieldH, reason: 'حقل');
      }
      expect(tester.getSize(find.byType(ImdEntryBalanceCell).first).height, fieldH,
          reason: 'الرصيد أطول أو أقصر من الحقول');
      for (final b in tester.widgetList<ImdIconButton>(find.byType(ImdIconButton))) {
        expect(tester.getSize(find.byWidget(b)).height, fieldH, reason: 'زرّ الإجراءات');
      }
    });

    testWidgets('الصفّ الثاني ملتصقٌ بالأول: لا فراغ بينهما إلا خطّ الشبكة', (tester) async {
      await tester.pumpWidget(host(realTable(3)));

      final tops = [
        for (final f in tester.widgetList<ImdFld>(find.byType(ImdFld)).where(
            (f) => (f.controller.text).startsWith('صنف')))
          tester.getTopLeft(find.byWidget(f)).dy,
      ];
      expect(tops.length, 3);
      // المسافة بين بدايتَي صفّين متتاليين = ارتفاع الصفّ + سُمك خطّ الشبكة فقط.
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i] - tops[i - 1], inInclusiveRange(fieldH, fieldH + 2),
            reason: 'فراغٌ زائد بين الصفّين $i');
      }
    });

    testWidgets('الزرّ خارج الجداول المدمجة يبقى بمقاسه المعتاد', (tester) async {
      await tester.pumpWidget(host(Center(child: ImdIconButton(icon: 'plus', onPressed: () {}))));
      expect(tester.getSize(find.byType(ImdIconButton)).height, greaterThanOrEqualTo(ImdSizes.touchMin));
    });

    testWidgets('زرّ «+» بجوار قائمةٍ في نموذجٍ مدمج بارتفاع القائمة نفسه', (tester) async {
      await tester.pumpWidget(host(ImdCompact(
        child: Row(children: [
          Expanded(
            child: ImdSelect<String>(
              value: 'أ',
              items: const [('أ', 'مستودع')],
              onChanged: (_) {},
            ),
          ),
          const SizedBox(width: 6),
          ImdIconButton(icon: 'plus', onPressed: () {}),
        ]),
      )));
      final select = tester.getSize(find.byType(ImdSelect<String>)).height;
      final button = tester.getSize(find.byType(ImdIconButton)).height;
      expect(button, select, reason: 'الزرّ أعلى من القائمة أو أقصر منها');
    });
  });
}
