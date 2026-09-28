import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// `ImdTable(pageSize: …)` — لا تُختبر إلا حين تُفعَّل صراحةً، فلا شاشةٍ من
/// الـ٣٦ التي تستخدم `ImdTable` اليوم تُفعِّلها بعد.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  List<ImdCol> cols() => const [ImdCol('الرقم')];
  List<List<Widget>> rowsOf(int n) => [for (var i = 0; i < n; i++) [Text('صف $i')]];

  /// ٥٠ صفًّا داخل `SingleChildScrollView` تدفع شريط الترقيم خارج نافذة
  /// الاختبار الافتراضية (٦٠٠ ارتفاعًا)، فيُمرَّر إليه أولًا قبل نقره.
  Future<void> tapPager(WidgetTester tester, String tooltip) async {
    await tester.ensureVisible(find.byTooltip(tooltip));
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  testWidgets('pageSize null ⇒ كل الصفوف كما كانت، بلا شريط ترقيم', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(120))));
    expect(find.text('صف 0'), findsOneWidget);
    expect(find.text('صف 119'), findsOneWidget);
    expect(find.textContaining('صفحة'), findsNothing);
  });

  testWidgets('pageSize مفعَّل ⇒ صفحة واحدة فقط تُعرض، وشريطٌ يصف الإجمالي', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(120), pageSize: 50)));
    expect(find.text('صف 0'), findsOneWidget);
    expect(find.text('صف 49'), findsOneWidget);
    expect(find.text('صف 50'), findsNothing);
    expect(find.textContaining('١'), findsWidgets); // أرقام عربية
    expect(find.text('صفحة ١ من ٣'), findsOneWidget);
    // «السابق» معطَّل في الصفحة الأولى: نقره لا يُغيِّر شيئًا.
    await tapPager(tester, 'الصفحة السابقة');
    expect(find.text('صفحة ١ من ٣'), findsOneWidget);
  });

  testWidgets('«التالي» ينتقل للصفحة التالية بفهرسٍ مطلق لا محلي', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(120), pageSize: 50)));
    await tapPager(tester, 'الصفحة التالية');
    expect(find.text('صف 50'), findsOneWidget);
    expect(find.text('صف 99'), findsOneWidget);
    expect(find.text('صف 0'), findsNothing);
    expect(find.text('صفحة ٢ من ٣'), findsOneWidget);

    await tapPager(tester, 'الصفحة التالية');
    // الصفحة الأخيرة فيها ٢٠ صفًّا فقط (١٢٠ - ١٠٠)، و«التالي» يصير معطَّلًا.
    expect(find.text('صف 100'), findsOneWidget);
    expect(find.text('صف 119'), findsOneWidget);
    expect(find.text('صفحة ٣ من ٣'), findsOneWidget);
  });

  testWidgets('onRowTap يبلَّغ بالفهرس المطلق حتى في صفحاتٍ لاحقة', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(host(ImdTable(
      columns: cols(),
      rows: rowsOf(120),
      pageSize: 50,
      onRowTap: tapped.add,
    )));
    await tapPager(tester, 'الصفحة التالية');
    await tester.ensureVisible(find.text('صف 55'));
    await tester.tap(find.text('صف 55'));
    expect(tapped, [55]);
  });

  testWidgets('صف الإجماليات يظهر مرةً واحدة بصرف النظر عن الصفحة', (tester) async {
    await tester.pumpWidget(host(ImdTable(
      columns: cols(),
      rows: rowsOf(120),
      pageSize: 50,
      footer: const [Text('الإجمالي: ١٢٠')],
    )));
    expect(find.text('الإجمالي: ١٢٠'), findsOneWidget);
    await tapPager(tester, 'الصفحة التالية');
    expect(find.text('الإجمالي: ١٢٠'), findsOneWidget);
  });

  testWidgets('قائمة فارغة مع pageSize: تبقى رسالة الفراغ، بلا شريط ترقيم', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: const [], pageSize: 50)));
    expect(find.text('لا توجد بيانات'), findsOneWidget);
    expect(find.textContaining('صفحة'), findsNothing);
  });

  testWidgets('عدد الصفوف أقل من حجم الصفحة: صفحة واحدة، والزرّان معطَّلان',
      (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(5), pageSize: 50)));
    expect(find.text('صفحة ١ من ١'), findsOneWidget);
    expect(find.text('صف 4'), findsOneWidget);
  });
}
