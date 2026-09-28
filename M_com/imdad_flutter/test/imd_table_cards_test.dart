import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// `ImdTable(cards: true)` — لا تُختبر إلا حين تُفعَّل صراحةً، ولا تُفعَّل بعد
/// في أيّ شاشة من الـ٣٦ التي تستخدم `ImdTable`.
void main() {
  Widget host(Widget child, {double width = 400}) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  // عمودان: واحدٌ بعنوان (يُكدَّس في البطاقة)، وآخر بعنوانٍ فارغ (زرّ إجراء
  // يُجمَع أسفل البطاقة) — نمط كل شاشةٍ قائمةٍ فعليًّا (`opening_screen` مثلًا).
  List<ImdCol> cols() => const [ImdCol('الاسم'), ImdCol('')];
  List<List<Widget>> rowsOf(int n) => [
        for (var i = 0; i < n; i++) [Text('عنصر $i'), ElevatedButton(onPressed: () {}, child: Text('حذف $i'))],
      ];

  testWidgets('cards: false ⇒ جدولٌ كما هو دومًا، حتى على شاشةٍ ضيّقة', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(3)), width: 400));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('عنصر 0'), findsOneWidget);
  });

  testWidgets('cards: true وعرضٌ ضيّق ⇒ بطاقاتٌ بدل الجدول', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(3), cards: true), width: 400));
    expect(find.byType(Table), findsNothing);
    expect(find.text('عنصر 0'), findsOneWidget);
    expect(find.text('عنصر 1'), findsOneWidget);
    expect(find.text('عنصر 2'), findsOneWidget);
  });

  testWidgets('cards: true لكن عرضٌ واسع (≥900) ⇒ يبقى جدولًا', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(3), cards: true), width: 1200));
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('عمود العنوان الفارغ يظهر في صفّ إجراءات لا معنوَنًا', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(2), cards: true), width: 400));
    // العنوان الحقيقي («الاسم») ظاهر، والعمود الفارغ العنوان لا يُطبع نصًّا فارغًا مستقلًّا له —
    // فقط زرّ الإجراء نفسه.
    expect(find.text('الاسم'), findsNWidgets(2)); // مرّةً لكل بطاقة
    expect(find.text('حذف 0'), findsOneWidget);
    expect(find.text('حذف 1'), findsOneWidget);
  });

  testWidgets('onRowTap يلفّ البطاقة كاملةً', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(host(
      ImdTable(columns: cols(), rows: rowsOf(3), cards: true, onRowTap: tapped.add),
      width: 400,
    ));
    await tester.tap(find.text('عنصر 1')); // النقر على أي جزءٍ من البطاقة، لا الزرّ نفسه
    expect(tapped, [1]);
  });

  testWidgets('صف الإجماليات يظهر كبطاقة إجماليات منفصلة مع cards: true', (tester) async {
    await tester.pumpWidget(host(
      ImdTable(
        columns: cols(),
        rows: rowsOf(2),
        cards: true,
        footer: const [Text('الإجمالي: ٢'), SizedBox.shrink()],
      ),
      width: 400,
    ));
    expect(find.text('الإجمالي: ٢'), findsOneWidget);
  });

  testWidgets('cards مع pageSize معًا: البطاقات تُقتصر على الصفحة، وشريط الترقيم يظهر', (tester) async {
    final rows = [for (var i = 0; i < 25; i++) [Text('عنصر $i'), const SizedBox.shrink()]];
    await tester.pumpWidget(host(
      ImdTable(columns: cols(), rows: rows, cards: true, pageSize: 10),
      width: 400,
    ));
    expect(find.text('عنصر 0'), findsOneWidget);
    expect(find.text('عنصر 9'), findsOneWidget);
    expect(find.text('عنصر 10'), findsNothing);
    expect(find.text('صفحة ١ من ٣'), findsOneWidget);
  });

  testWidgets('rowColor يُستخدم خلفيةً للبطاقة ويبقى بلا انهيار', (tester) async {
    await tester.pumpWidget(host(
      ImdTable(
        columns: cols(),
        rows: rowsOf(3),
        cards: true,
        rowColor: (i) => i == 1 ? Colors.red.withValues(alpha: .1) : null,
      ),
      width: 400,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('عنصر 1'), findsOneWidget);
  });
}
