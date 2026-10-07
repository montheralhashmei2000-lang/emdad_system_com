import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_density.dart';
import 'package:imdad/core/ui/imd_layout.dart';
import 'package:imdad/core/ui/imd_style.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_page_tabs.dart';
import 'package:imdad/core/ui/imd_status_bar.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تصفية الأعمدة والتجميع والكثافة العالية وعدّاد السجلات في [ImdTable].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const names = ['أرز', 'سكر', 'زيت', 'دقيق', 'ملح'];
  const cats = ['حبوب', 'حلويات', 'زيوت', 'حبوب', ''];

  Widget host(Widget child, {Size size = const Size(1200, 800)}) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  ImdTable table({
    List<int>? tapped,
    ImdRecordSink? sink,
    bool withValues = true,
  }) =>
      ImdTable(
        columns: const [ImdCol('الصنف'), ImdCol('الفئة')],
        rows: [
          for (var i = 0; i < names.length; i++) [Text(names[i]), Text(cats[i])],
        ],
        values: withValues
            ? [
                for (var i = 0; i < names.length; i++) [names[i], cats[i]],
              ]
            : null,
        onRowTap: tapped?.add,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ImdDensity.notifier.value = false;
    ImdStyle.notifier.value = false;
  });

  testWidgets('بلا values لا شريط أدوات ولا أيقونات تصفية', (tester) async {
    await tester.pumpWidget(host(table(withValues: false)));
    expect(find.text('تصفية'), findsNothing);
    expect(find.text('تجميع حسب'), findsNothing);
    expect(find.byTooltip('تصفية العمود'), findsNothing);
  });

  testWidgets('مع values: شريط أدوات وأيقونة تصفية لكل عمود', (tester) async {
    await tester.pumpWidget(host(table()));
    expect(find.text('بحث فوري…'), findsOneWidget);
    expect(find.text('اسحب رأس العمود هنا للتجميع'), findsOneWidget);
    expect(find.byTooltip('تصفية العمود'), findsNWidgets(2));
    // قائمتا «تصفية»/«تجميع حسب» للجوال وحده (لا سحب ولا أيقونات رؤوس هناك).
    expect(find.text('تصفية'), findsNothing);
    expect(find.text('تجميع حسب'), findsNothing);
  });

  testWidgets('تصفية عمودٍ تُخفي الصفوف غير المختارة وتُبقي الفهرس المطلق', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(host(table(tapped: tapped)));

    await tester.tap(find.byTooltip('تصفية العمود').last); // عمود الفئة
    await tester.pumpAndSettle();
    expect(find.text('(فارغ)'), findsOneWidget, reason: 'القيمة الفارغة تُعرض باسمها');

    // إلغاء الكل ثم اختيار «حبوب» وحدها.
    await tester.tap(find.text('إلغاء الكل'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, 'حبوب').last);
    await tester.pump();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    expect(find.text('أرز'), findsOneWidget);
    expect(find.text('دقيق'), findsOneWidget);
    expect(find.text('سكر'), findsNothing);
    expect(find.text('ملح'), findsNothing);

    await tester.tap(find.text('دقيق'));
    expect(tapped, [3], reason: 'onRowTap يتلقى فهرس الصف في القائمة الأصلية لا بعد التصفية');

    await tester.tap(find.text('مسح الفلاتر'));
    await tester.pump();
    expect(find.text('سكر'), findsOneWidget);
  });

  testWidgets('التجميع (قائمة الجوال) يضع رأسًا لكل قيمة ويطوي المجموعة بالنقر', (tester) async {
    await tester.pumpWidget(host(table(), size: const Size(400, 800)));

    await tester.tap(find.text('تجميع حسب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفئة').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'رأس المجموعة فاض أو كسر تخطيط الجدول');
    expect(find.textContaining('الفئة: حبوب'), findsOneWidget);
    expect(find.textContaining('الفئة: (فارغ)'), findsOneWidget);
    expect(find.text('أرز'), findsOneWidget);

    await tester.tap(find.textContaining('الفئة: حبوب'));
    await tester.pumpAndSettle();
    expect(find.text('أرز'), findsNothing, reason: 'المجموعة المطويّة تخفي صفوفها');
    expect(find.text('سكر'), findsOneWidget);
  });

  testWidgets('الجدول يُبلّغ عدّاد السجلات بالمعروض والإجمالي', (tester) async {
    final sink = ImdRecordSink();
    await tester.pumpWidget(host(ImdRecordScope(sink: sink, child: table())));
    await tester.pump();
    expect(sink.current, (shown: 5, total: 5));

    await tester.tap(find.byTooltip('تصفية العمود').first); // الصنف
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء الكل'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, 'أرز').last);
    await tester.pump();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect(sink.current, (shown: 1, total: 5));
  });

  test('العدّاد يعرض أكبر جدولٍ في الصفحة ويتخلّى عن المُزال', () {
    final sink = ImdRecordSink();
    final a = Object(), b = Object();
    sink.report(a, shown: 3, total: 3);
    sink.report(b, shown: 40, total: 120);
    expect(sink.current, (shown: 40, total: 120));
    sink.remove(b);
    expect(sink.current, (shown: 3, total: 3));
  });

  testWidgets('الكثافة العالية تُنقص ارتفاع الصفوف', (tester) async {
    await tester.pumpWidget(host(table(withValues: false)));
    final normal = tester.getSize(find.byType(ImdTable)).height;

    ImdDensity.notifier.value = true;
    await tester.pumpWidget(host(table(withValues: false)));
    await tester.pump();
    final dense = tester.getSize(find.byType(ImdTable)).height;
    expect(dense, lessThan(normal));
  });

  testWidgets('الكثافة العالية لا تُضيّق أهداف اللمس على الجوال', (tester) async {
    ImdDensity.notifier.value = true;
    // بيئة الاختبار تحاكي أندرويد افتراضيًّا، فنُحدّد المنصة صراحةً.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ImdDensity.compactTargets, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(ImdDensity.compactTargets, isFalse);
    // يجب تصفيره قبل نهاية الاختبار: الإطار يفحص المتغيّرات التشخيصية عندها.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('البحث الفوري يفلتر الصفوف فورًا ويبلّغ العدّاد', (tester) async {
    final sink = ImdRecordSink();
    await tester.pumpWidget(host(ImdRecordScope(sink: sink, child: table())));
    await tester.enterText(find.byType(TextField), 'سك');
    await tester.pump();
    expect(find.text('سكر'), findsOneWidget);
    expect(find.text('أرز'), findsNothing);
    expect(sink.current, (shown: 1, total: 5));

    // البحث يشمل كل الأعمدة (الفئة أيضًا).
    await tester.enterText(find.byType(TextField), 'زيوت');
    await tester.pump();
    expect(find.text('زيت'), findsOneWidget);
    expect(find.text('سكر'), findsNothing);
  });

  testWidgets('لوحة التجميع: نصّ إرشادي وإسقاط رأس العمود عليها يجمّع', (tester) async {
    await tester.pumpWidget(host(table()));
    expect(find.text('اسحب رأس العمود هنا للتجميع'), findsOneWidget);

    final from = tester.getCenter(find.text('الفئة').first);
    final to = tester.getCenter(find.text('اسحب رأس العمود هنا للتجميع'));
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(0, -10));
    await g.moveTo(to);
    await g.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('الفئة: حبوب'), findsOneWidget, reason: 'السحب إلى اللوحة لم يجمّع');
    expect(find.text('اسحب رأس العمود هنا للتجميع'), findsNothing);
  });

  testWidgets('الجدول الفارغ يُبقي رأسه ويعرض سطحًا رماديًّا صغيرًا', (tester) async {
    await tester.pumpWidget(host(const ImdTable(
      columns: [ImdCol('الصنف'), ImdCol('الفئة')],
      rows: [],
      empty: 'لا توجد بيانات',
    )));
    expect(find.text('الصنف'), findsOneWidget, reason: 'الرأس يبقى مع الفراغ');
    expect(find.text('لا توجد بيانات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الجوال: جدول بتمرير أفقي لا بطاقات، والعمود الأول مثبَّت', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      ImdTable(
        freezeFirst: true,
        columns: const [
          ImdCol('الكود', width: 90),
          ImdCol('الصنف', width: 200),
          ImdCol('الفئة', width: 200),
          ImdCol('الرصيد', width: 200),
        ],
        rows: [
          for (var i = 0; i < 3; i++) [Text('ك$i'), Text('صنف $i'), const Text('فئة'), Text('${i * 10}')],
        ],
      ),
      size: const Size(400, 800),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'فيض على عرض 400');
    // عند الإزاحة صفر العمود الأول ظاهرٌ في الأصل: جدولٌ واحد بلا نسخة مثبَّتة (لا بطاقات).
    expect(find.byType(Table), findsNWidgets(1));

    final before = tester.getTopLeft(find.text('ك0').first).dx;
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(150, 0));
    await tester.pumpAndSettle();
    // بعد التمرير تُبنى النسخة المثبَّتة (الأصل + العمود الأول).
    expect(find.byType(Table), findsNWidgets(2));
    // عمود الكود المثبَّت ما زال ظاهرًا في موضعه.
    final visibleCodes = find.text('ك0').evaluate().length;
    expect(visibleCodes, greaterThanOrEqualTo(1));
    expect(tester.getTopLeft(find.text('ك0').last).dx, closeTo(before, 1.0), reason: 'العمود الأول تحرّك مع التمرير');
  });

  testWidgets('ترقيم تلقائي بعد 300 صفٍّ حين لا يُمرَّر pageSize', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      ImdTable(
        columns: const [ImdCol('م')],
        rows: [for (var i = 0; i < 350; i++) [Text('صف$i')]],
      ),
      size: const Size(1200, 900),
    ));
    await tester.pumpAndSettle();
    expect(find.text('صف0'), findsOneWidget);
    expect(find.text('صف99'), findsOneWidget);
    expect(find.text('صف100'), findsNothing, reason: 'الصفحة الأولى 100 صف فقط');
    expect(find.textContaining('من ٣٥٠'), findsWidgets, reason: 'شريط الترقيم يعرض الإجمالي');
  });

  testWidgets('جدولٌ بـ300 صفٍّ فأقل لا يُرقَّم تلقائيًّا', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      ImdTable(
        columns: const [ImdCol('م')],
        rows: [for (var i = 0; i < 300; i++) [Text('صف$i')]],
      ),
      size: const Size(1200, 900),
    ));
    await tester.pumpAndSettle();
    expect(find.text('صف299'), findsOneWidget);
    expect(find.textContaining('الصفحة التالية'), findsNothing);
  });

  testWidgets('ImdSelect يفتح نافذةً كبيرة ببحثٍ ويختار منها', (tester) async {
    String? picked = 'b';
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, set) => ImdSelect<String>(
        hint: 'الصنف',
        items: [for (final e in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) (e, 'خيار $e')],
        value: picked,
        onChanged: (v) => set(() => picked = v),
      ),
    )));
    expect(find.text('خيار b'), findsOneWidget, reason: 'القيمة المختارة تظهر في الحقل');

    await tester.tap(find.text('خيار b'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'تُفتح نافذةٌ لا قائمةٌ صغيرة');
    expect(find.text('خيار h'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'خيار h');
    await tester.pump();
    expect(find.text('خيار a'), findsNothing, reason: 'البحث يضيّق الخيارات');
    await tester.tap(find.descendant(of: find.byType(ListView), matching: find.text('خيار h')));
    await tester.pumpAndSettle();
    expect(picked, 'h');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('ImdSelect معطَّل بلا onChanged لا يفتح شيئًا', (tester) async {
    await tester.pumpWidget(host(const ImdSelect<String>(items: [('a', 'أ')], value: 'a', onChanged: null)));
    await tester.tap(find.text('أ'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('ImdKpi: sparkline اختياريّ — يُرسم بنقطتين فأكثر ولا يغيّر البطاقة بدونه', (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      ImdKpi(label: 'أ', value: '١'),
      ImdKpi(label: 'ب', value: '٢', spark: [1, 4, 2, 8]),
      ImdKpi(label: 'ج', value: '٣', spark: [5]),
    ])));
    expect(find.byType(ImdSparkPainter, skipOffstage: false), findsNothing); // painter ليس ودجت
    final paints = find.descendant(of: find.byType(ImdKpi), matching: find.byType(CustomPaint));
    final withSpark = paints.evaluate().where((e) => (e.widget as CustomPaint).painter is ImdSparkPainter).length;
    expect(withSpark, 1, reason: 'الثانية وحدها (الثالثة بنقطة واحدة لا تُرسم)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('النمط الكلاسيكي: زوايا 2 وبلا ظلال وخط 12، ويعود الحديث بإيقافه', (tester) async {
    expect(ImdSizes.radius, 12);
    expect(imdShadow(ImdColors.light), isNotEmpty);

    ImdStyle.notifier.value = true;
    expect(ImdSizes.radius, 2);
    expect(ImdSizes.compactRadius, 2);
    expect(imdShadow(ImdColors.light), isEmpty, reason: 'مسطّح بلا ظلال');
    expect(imdShadowOverlay(ImdColors.light), isEmpty);
    expect(ImdDensity.cellFont, 12);

    final theme = AppTheme.classic();
    expect(theme.extension<ImdColors>()!.bg, const Color(0xFFF3F4F6));
    expect(theme.extension<ImdColors>()!.accent, const Color(0xFF047857), reason: 'أخضر الإمداد يبقى للتمييز');

    ImdStyle.notifier.value = false;
    expect(ImdSizes.radius, 12);
    expect(ImdDensity.cellFont, 13.5);
  });

  testWidgets('إزالة جدولٍ من الشجرة لا تُعيد بناء شريط الحالة أثناء التفكيك', (tester) async {
    // عطلٌ حقيقي: `dispose()` للجدول كان يُشعِر المستمعين فورًا والشجرة مقفلة
    // فينهار التطبيق عند أول تنقّلٍ بين صفحتين («widget tree was locked»).
    final sink = ImdRecordSink();
    Widget app({required bool withTable}) => host(
          ImdRecordScope(
            sink: sink,
            child: Column(children: [
              ListenableBuilder(
                listenable: sink,
                builder: (_, __) => Text('عدد: ${sink.current?.total ?? 0}'),
              ),
              if (withTable) table(),
            ]),
          ),
        );

    await tester.pumpWidget(app(withTable: true));
    await tester.pump();
    expect(find.text('عدد: 5'), findsOneWidget);

    await tester.pumpWidget(app(withTable: false));
    expect(tester.takeException(), isNull, reason: 'الإشعار أثناء قفل الشجرة');
    await tester.pump();
    expect(find.text('عدد: 0'), findsOneWidget, reason: 'الشريط يتحدّث بعد الإطار');
  });

  testWidgets('عدّاد مُتخلَّص منه لا يرمي عند إبلاغٍ متأخر', (tester) async {
    final sink = ImdRecordSink()..dispose();
    sink.report(Object(), shown: 1, total: 1);
    sink.remove(Object());
    expect(tester.takeException(), isNull);
  });

  testWidgets('الصفحة المخفيّة تحتفظ بحالتها', (tester) async {
    final sinkA = ImdRecordSink(), sinkB = ImdRecordSink();
    Widget pages(String active) => MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Stack(fit: StackFit.expand, children: [
                ImdPageHost(key: const ValueKey('a'), active: active == 'a', sink: sinkA, child: const _Counter()),
                ImdPageHost(key: const ValueKey('b'), active: active == 'b', sink: sinkB, child: const Text('صفحة ب')),
              ]),
            ),
          ),
        );

    await tester.pumpWidget(pages('a'));
    await tester.tap(find.byKey(const ValueKey('inc')));
    await tester.pump();
    expect(find.text('العدّ: 1'), findsOneWidget);

    await tester.pumpWidget(pages('b'));
    expect(find.text('العدّ: 1'), findsNothing, reason: 'المخفيّة لا تُرى (offstage)');
    expect(find.text('صفحة ب'), findsOneWidget);

    await tester.pumpWidget(pages('a'));
    expect(find.text('العدّ: 1'), findsOneWidget, reason: 'عادت الصفحة بحالتها لا من الصفر');
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('العدّ: $n'),
        TextButton(key: const ValueKey('inc'), onPressed: () => setState(() => n++), child: const Text('+')),
      ]);
}
