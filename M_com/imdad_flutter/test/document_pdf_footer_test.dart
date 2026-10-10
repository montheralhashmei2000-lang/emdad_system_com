import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/document_pdf.dart';
import 'package:imdad/domain/print_layout.dart';

/// تذييل `DocumentPdf`: التوقيعات وسطر الطباعة في **كل** صفحة.
///
/// كانت خانات التوقيع تُرسم مرةً في آخر المحتوى، فلا تحملها إلا الصفحة
/// الأخيرة من تقريرٍ متعدد الصفحات. نصوص PDF العربية رموزُ خطٍّ لا تُبحث في
/// البايتات، فيُعرف موضع التوقيعات بـ[DocumentPdf.debugOnSignatures].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int pages(List<int> pdf) => RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(pdf)).length;

  PrintDoc doc(int rows, {List<String> signatureLines = const []}) => PrintDoc(
        title: 'تقرير اختبار',
        headers: const ['م', 'الصنف', 'الكمية'],
        rows: [
          for (var i = 1; i <= rows; i++) ['$i', 'صنف رقم $i', '${i * 10}'],
        ],
        signatureLines: signatureLines,
      );

  /// يبني المستند ويعيد (عدد الصفحات، الصفحات التي رُسمت فيها التوقيعات).
  Future<(int, Set<int>)> render(PrintDoc d, {PrintLayout layout = PrintLayout.defaults}) async {
    final signed = <int>{};
    DocumentPdf.debugOnSignatures = signed.add;
    // محاولةٌ أولى فشلت ثم أُعيد البناء: ما رُسم فيها لا يُحتسب.
    DocumentPdf.debugOnFallback = signed.clear;
    addTearDown(() {
      DocumentPdf.debugOnSignatures = null;
      DocumentPdf.debugOnFallback = null;
    });
    final bytes = await DocumentPdf.build(doc: d, layout: layout, printedBy: 'المختبِر');
    return (pages(bytes), signed);
  }

  test('تقرير صفحة واحدة: التوقيعات أسفلها', () async {
    final (n, signed) = await render(doc(5));
    expect(n, 1);
    expect(signed, {1});
  });

  test('تقرير ثلاث صفحات: التوقيعات في كل صفحة، لا في الأخيرة وحدها', () async {
    final (n, signed) = await render(doc(60));
    expect(n, 3, reason: 'عدد الصفوف يجب أن يملأ ثلاث صفحات');
    expect(signed, {1, 2, 3});
  });

  test('تواقيع المستند (signatureLines) تُرسم في كل صفحة ولو أُخفيت تواقيع التخطيط', () async {
    final hidden = PrintLayout.defaults.copyWith(
      signatures: [for (final s in PrintLayout.defaults.signatures) s.copyWith(show: false)],
    );
    final (n, signed) = await render(doc(60, signatureLines: const ['أمين المحروقات\nفلان']), layout: hidden);
    expect(n, greaterThan(1));
    expect(signed, {for (var p = 1; p <= n; p++) p});
  });

  test('تخطيط بلا تواقيع ظاهرة ولا تواقيع مستند: لا صف توقيعات', () async {
    final none = PrintLayout.defaults.copyWith(signatures: const []);
    final (_, signed) = await render(doc(60), layout: none);
    expect(signed, isEmpty);
  });

  test('صفٌّ أطول من مساحة الصفحة: الطباعة لا تفشل، والتواقيع تعود إلى آخر المحتوى', () async {
    // خليةٌ بآلاف الأحرف: صفٌّ لا تقسمه مكتبة pdf. التذييل الموقَّع يقتطع من
    // مساحة الصفحة، فكان هذا المستند (الذي يُطبع قبل التغيير) يرمي
    // TooManyPagesException. 240 تكرارًا بين الحدّين المقيسين (~215 و~260).
    final long = 'نص طويل جدًا ' * 240;
    final d = PrintDoc(
      title: 'إخلاء عهدة',
      headers: const ['البيان', 'القيمة'],
      columnFlex: const [2, 5],
      rows: [for (var i = 0; i < 4; i++) ['حقل $i', long]],
      signatureLines: const ['صاحب العهدة\n....', 'المُخلِّي\n....'],
    );
    final (n, signed) = await render(d);
    expect(n, greaterThan(0));
    expect(signed, isEmpty, reason: 'البديل يضع التواقيع في آخر المحتوى لا في التذييل');
  });

  group('سطر الطباعة', () {
    final at = DateTime(2026, 10, 10, 14, 5);

    test('التاريخ والوقت والمستخدم ورقم الصفحة بالترتيب', () {
      expect(
        DocumentPdf.footerLine(at: at, by: 'أحمد', page: 2, pages: 3),
        'تاريخ الطباعة: 10-10-2026 م 14:05 · طُبع بواسطة: أحمد · صفحة 2 من 3',
      );
    });

    test('بلا مستخدم معروف يُحذف مقطعه ولا يُكتب «طُبع بواسطة:» فارغًا', () {
      expect(
        DocumentPdf.footerLine(at: at, by: '  ', page: 1, pages: 1),
        'تاريخ الطباعة: 10-10-2026 م 14:05 · صفحة 1 من 1',
      );
    });
  });
}
