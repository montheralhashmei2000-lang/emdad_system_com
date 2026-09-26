import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/repos/reports_repo.dart';

/// سطر الإجمالي في التقارير.
///
/// **الورقة تُوقَّع بمجموعها.** كان الإجمالي يُحسب في الشاشة وحدها فيظهر
/// عليها ولا يدخل الطباعة ولا ملف Excel؛ فصار حسابًا واحدًا تُبنى منه
/// المخرجات الثلاثة — وهذه الاختبارات تحرس أن يبقى كذلك.
void main() {
  const label = 'الإجمالي';

  ReportCell cell(String text, [double? value]) =>
      ReportCell(text, value: value);

  group('متى يُجمع', () {
    const columns = [
      ReportColumn('الصنف'),
      ReportColumn('الكمية', numeric: true, sum: true),
    ];

    test('سطران فأكثر لهما إجمالي', () {
      final t = reportTotalsRow(columns, [
        [cell('أرز'), cell('١٠٠', 100)],
        [cell('سكر'), cell('٥٠', 50)],
      ]);
      expect(t, isNotNull);
      expect(t!.first, label);
      expect(t.last, '١٥٠');
    });

    test('سطرٌ وحيد لا يُجمع', () {
      // «الإجمالي ١٠٠» تحت «١٠٠» تكرارٌ لا خبر.
      final t = reportTotalsRow(columns, [
        [cell('أرز'), cell('١٠٠', 100)],
      ]);
      expect(t, isNull);
    });

    test('تقريرٌ بلا عمودٍ مجمَّع لا إجمالي له', () {
      final t = reportTotalsRow(const [
        ReportColumn('الصنف'),
        ReportColumn('الوحدة'),
      ], [
        [cell('أرز'), cell('كجم')],
        [cell('سكر'), cell('كجم')],
      ]);
      expect(t, isNull);
    });

    test('عمودٌ رقميّ بلا sum لا يدخل الجمع', () {
      final t = reportTotalsRow(const [
        ReportColumn('الصنف'),
        ReportColumn('النسبة', numeric: true),
        ReportColumn('الكمية', numeric: true, sum: true),
      ], [
        [cell('أرز'), cell('٨٠', 80), cell('١٠٠', 100)],
        [cell('سكر'), cell('٩٠', 90), cell('٥٠', 50)],
      ]);
      // النسبة لا تُجمع — مجموع النسب لا معنى له. والتسمية تشغل العمود
      // الأول، فكل عمودٍ يُزاح خانةً عنه.
      expect(t, ['الإجمالي', '', '', '١٥٠']);
    });
  });

  group('بنية السطر', () {
    const columns = [
      ReportColumn('الصنف'),
      ReportColumn('المستحق', numeric: true, sum: true),
      ReportColumn('الوحدة'),
      ReportColumn('المصروف', numeric: true, sum: true),
    ];

    final rows = [
      [cell('أرز'), cell('١٠٠', 100), cell('كجم'), cell('٤٠', 40)],
      [cell('سكر'), cell('٢٠٠', 200), cell('كجم'), cell('٦٠', 60)],
    ];

    test('طوله عمود التسمية زائدًا أعمدة التقرير', () {
      // العمود الأول في الورقة «م»، فتحته كلمة «الإجمالي».
      final t = reportTotalsRow(columns, rows)!;
      expect(t.length, columns.length + 1);
    });

    test('كل مجموعٍ تحت عموده', () {
      final t = reportTotalsRow(columns, rows)!;
      expect(t[1], '', reason: 'الصنف نصٌّ لا يُجمع');
      expect(t[2], '٣٠٠');
      expect(t[3], '', reason: 'الوحدة نصٌّ لا يُجمع');
      expect(t[4], '١٠٠');
    });

    test('القيمة الرقمية هي المجموعة لا النص المعروض', () {
      // النص قد يحمل وحدةً أو تقريبًا؛ والجمع يقع على `value`.
      final t = reportTotalsRow(columns, [
        [cell('أرز'), cell('١٠٠ كجم', 100), cell('كجم'), cell('—')],
        [cell('سكر'), cell('٢٠٠ كجم', 200), cell('كجم'), cell('—')],
      ])!;
      expect(t[2], '٣٠٠');
      expect(t[4], '٠', reason: 'خلايا بلا قيمة تُحسب صفرًا لا تُسقط السطر');
    });

    test('سطرٌ أقصر من الأعمدة لا يُسقط الحساب', () {
      final t = reportTotalsRow(columns, [
        [cell('أرز'), cell('١٠٠', 100), cell('كجم'), cell('٤٠', 40)],
        [cell('سكر'), cell('٢٠٠', 200)],
      ])!;
      expect(t[2], '٣٠٠');
      expect(t[4], '٤٠');
    });

    test('التسمية تُبدَّل عند الحاجة', () {
      final t = reportTotalsRow(columns, rows, label: 'المجموع')!;
      expect(t.first, 'المجموع');
    });
  });
}
