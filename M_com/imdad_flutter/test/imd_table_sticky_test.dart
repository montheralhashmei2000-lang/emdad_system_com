import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// `ImdTable(maxHeight: …)` — الرأس الثابت.
///
/// الرأس والجسم جدولان منفصلان، فالاختبار هنا يحرس أمرين: أن الرأس يبقى
/// ظاهرًا بعد تمرير الجسم، وأن الجدولين يظلّان بعرض أعمدةٍ واحد. الثاني هو
/// موضع الانكسار الصامت: لو عاد عمودٌ إلى القياس من المحتوى لانزاح الرأس عن
/// جسمه بلا خطأ ولا تحذير — تراه العين ولا يراه المترجم.
void main() {
  Widget host(Widget child, {double width = 900}) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 600)),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  List<ImdCol> cols() => const [ImdCol('الكود'), ImdCol('الصنف')];
  List<List<Widget>> rowsOf(int n) =>
      [for (var i = 0; i < n; i++) [Text('كود $i'), Text('صنف $i')]];

  testWidgets('بلا maxHeight: جدولٌ واحد كما كان', (tester) async {
    await tester.pumpWidget(host(ImdTable(columns: cols(), rows: rowsOf(40), cards: false)));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('الكود'), findsOneWidget);
  });

  testWidgets('مع maxHeight: جدولان — رأسٌ وجسم', (tester) async {
    await tester.pumpWidget(
        host(ImdTable(columns: cols(), rows: rowsOf(40), cards: false, maxHeight: 300)));
    expect(find.byType(Table), findsNWidgets(2));
    expect(find.text('الكود'), findsOneWidget);
  });

  testWidgets('الرأس يبقى ظاهرًا بعد تمرير الجسم', (tester) async {
    await tester.pumpWidget(
        host(ImdTable(columns: cols(), rows: rowsOf(60), cards: false, maxHeight: 300)));

    final headerBefore = tester.getTopLeft(find.text('الكود'));
    final firstRowBefore = tester.getTopLeft(find.text('كود 0')).dy;

    // تمرير جسم الجدول وحده لا الصفحة.
    await tester.drag(find.text('كود 1'), const Offset(0, -400));
    await tester.pump();

    final firstRowAfter = tester.getTopLeft(find.text('كود 0')).dy;

    // `SingleChildScrollView` يبني كل صفوفه، فوجودُ الصف في الشجرة لا يعني
    // ظهوره — الموضع وحده يشهد بالتمرير.
    expect(firstRowAfter, lessThan(firstRowBefore - 300),
        reason: 'لم يُمرَّر جسم الجدول: $firstRowBefore ← $firstRowAfter');
    expect(tester.getTopLeft(find.text('الكود')), headerBefore,
        reason: 'الرأس تحرّك مع الجسم بدل أن يثبت');
    // وقد خرج الصف الأول فعلًا من فوق حدّ الرأس.
    expect(firstRowAfter, lessThan(headerBefore.dy));
  });

  testWidgets('أعمدة الرأس تحاذي أعمدة الجسم تمامًا', (tester) async {
    await tester.pumpWidget(
        host(ImdTable(columns: cols(), rows: rowsOf(30), cards: false, maxHeight: 300)));

    final tables = find.byType(Table);
    final headerBox = tester.renderObject<RenderBox>(tables.at(0));
    final bodyBox = tester.renderObject<RenderBox>(tables.at(1));
    expect(headerBox.size.width, bodyBox.size.width);

    // حدود الخلية لا حدود نصّها: في RTL يبدأ النص من اليمين فيتبع طوله، وحشو
    // الرأس غير حشو الصف — فالخلية وحدها هي العمود.
    Rect cellOf(String text) {
      final cell = find.ancestor(of: find.text(text), matching: find.byType(TableCell)).first;
      final box = tester.renderObject<RenderBox>(cell);
      final origin = box.localToGlobal(Offset.zero);
      return origin & box.size;
    }

    for (final (head, body) in [('الكود', 'كود 0'), ('الصنف', 'صنف 0')]) {
      final h = cellOf(head);
      final b = cellOf(body);
      expect((h.left - b.left).abs() < 0.5 && (h.width - b.width).abs() < 0.5, isTrue,
          reason: 'انزاح عمود «$head»: الرأس $h والجسم $b');
    }
  });

  testWidgets('maxHeight مع pageSize: الترقيم تحت الإطار لا داخل تمريره', (tester) async {
    await tester.pumpWidget(host(
        ImdTable(columns: cols(), rows: rowsOf(120), cards: false, maxHeight: 300, pageSize: 50)));
    expect(find.text('صفحة ١ من ٣'), findsOneWidget);
    expect(find.text('كود 50'), findsNothing);
  });

  testWidgets('جدول فارغ مع maxHeight: الرأس يبقى مع سطح «لا بيانات» بلا جسمٍ يُمرَّر', (tester) async {
    await tester.pumpWidget(host(
        ImdTable(columns: cols(), rows: const [], cards: false, maxHeight: 300, empty: 'لا بيانات')));
    expect(find.text('لا بيانات'), findsOneWidget);
    // رأسٌ وحده (جدولٌ واحد بصفٍّ واحد) — لا جسم ولا تمرير.
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget); // تمرير المضيف وحده لا جسم الجدول
  });

  testWidgets('headerBackground/headerForeground: يُطليان صفّ الرأس ونصّه معًا',
      (tester) async {
    await tester.pumpWidget(host(ImdTable(
      columns: cols(),
      rows: rowsOf(5),
      cards: false,
      headerBackground: const Color(0xFF047857),
      headerForeground: Colors.white,
    )));

    // `TableRow.decoration` يُرسم داخليًّا في RenderTable لا عبر Container
    // مستقل، فيُقرأ من صف الرأس (الأول) في شجرة الودجات مباشرة.
    final table = tester.widget<Table>(find.byType(Table));
    final headerRow = table.children.first;
    final decoration = headerRow.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF047857));

    final label = tester.widget<Text>(find.text('الكود'));
    expect(label.style?.color, Colors.white);
  });

  testWidgets('rowKeys يحافظ على هوية عنصر الصفّ عند إدراج صفٍّ قبله',
      (tester) async {
    // Table.children (TableRow) يعتمد على المفتاح لموازنة الصفوف بين
    // الإعادتين — تمامًا كما توثّقه Flutter لهذا الغرض بالذات.
    var initCount = 0;
    final probeKey = UniqueKey();

    Widget probe() => _InitProbe(onInit: () => initCount++);
    Widget build(List<List<Widget>> rows, List<LocalKey> keys) =>
        host(ImdTable(columns: cols(), rows: rows, rowKeys: keys, cards: false));

    await tester.pumpWidget(build(
      [
        [const Text('كود 0'), probe()],
      ],
      [probeKey],
    ));
    expect(initCount, 1);

    // إدراج صفٍّ جديد قبله: العنصر القديم ينتقل من الفهرس ٠ إلى ١، لكن
    // مفتاحه الثابت يمنع إعادة بنائه من الصفر.
    await tester.pumpWidget(build(
      [
        [const Text('كود جديد'), const SizedBox.shrink()],
        [const Text('كود 0'), probe()],
      ],
      [UniqueKey(), probeKey],
    ));

    expect(initCount, 1, reason: 'rowKeys يحافظ على العنصر فلا يُعاد initState');
  });

  testWidgets('cellPadding مُخصَّصة تُستبدل بها حشوة الجسم الافتراضية',
      (tester) async {
    await tester.pumpWidget(host(ImdTable(
      columns: cols(),
      rows: rowsOf(2),
      cards: false,
      cellPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    )));
    final pad = tester.widget<Padding>(find
        .ancestor(of: find.text('صنف 0'), matching: find.byType(Padding))
        .first);
    expect(pad.padding, const EdgeInsets.symmetric(horizontal: 6, vertical: 4));
  });
}

/// يُبلغ [onInit] كل ما بُنيت حالتُه من جديد — يكشف إعادة الإنشاء عبر عدد
/// النداءات، بدل مراقبة شكلٍ بصري.
class _InitProbe extends StatefulWidget {
  const _InitProbe({required this.onInit});
  final VoidCallback onInit;

  @override
  State<_InitProbe> createState() => _InitProbeState();
}

class _InitProbeState extends State<_InitProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
