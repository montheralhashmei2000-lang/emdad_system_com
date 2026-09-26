import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/export/excel_export.dart';
import 'package:imdad/core/ui/imd_format.dart';

/// تصدير Excel.
///
/// **ملفٌ لا تُجمع أعمدته ليس تصديرًا.** الأرقام تصل إلى المصدِّر منسَّقةً
/// للعرض — هندية بفاصلة آلاف — فإن خرجت نصًّا لم تُجمع ولم تُفرز ولم تُرسم،
/// ويصير الزرّ صورةً من الجدول لا بياناتٍ منه.
void main() {
  /// يقرأ الملف المصدَّر ويعيد خلاياه.
  List<List<CellValue?>> read(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first]!;
    return [
      for (final row in sheet.rows) [for (final c in row) c?.value],
    ];
  }

  test('الرقم المعروض يخرج رقمًا لا نصًّا', () {
    // ٧٬٧٠٠ كما تكتبها `nf` — أرقامٌ هندية وفاصلة آلاف.
    final shown = nf(7700);
    expect(double.tryParse(shown), isNull,
        reason: 'هذه هي العلّة: النص المعروض لا يُحلَّل رقمًا');

    final cells = read(ExcelExport.build(
      sheetName: 'الأرصدة',
      headers: const ['م', 'الصنف', 'الرصيد'],
      rows: [
        ['1', 'أرز', shown]
      ],
      numericColumns: const {2},
    ));
    expect(cells[1][2], isA<IntCellValue>());
    expect((cells[1][2]! as IntCellValue).value, 7700);
  });

  test('الكسر يخرج عشريًّا بقيمته', () {
    final cells = read(ExcelExport.build(
      sheetName: 'نسب',
      headers: const ['الصنف', 'النسبة'],
      rows: [
        ['أرز', nf(27.5)]
      ],
      numericColumns: const {1},
    ));
    expect(cells[1][1], isA<DoubleCellValue>());
    expect((cells[1][1]! as DoubleCellValue).value, closeTo(27.5, 1e-9));
  });

  test('السالب يخرج سالبًا رغم علامة الاتجاه', () {
    // `nf` تسبق السالب بعلامة اتجاهٍ غير مرئية كي لا تنقلب الإشارة.
    final cells = read(ExcelExport.build(
      sheetName: 'فروق',
      headers: const ['الصنف', 'الفرق'],
      rows: [
        ['ديزل', nf(-1250)]
      ],
      numericColumns: const {1},
    ));
    expect((cells[1][1]! as IntCellValue).value, -1250);
  });

  test('إشارة الطرح الرياضية «−» تُقرأ سالبًا', () {
    final cells = read(ExcelExport.build(
      sheetName: 'فروق',
      headers: const ['الصنف', 'الفرق'],
      rows: [
        ['بترول', '−٢٬٠٠٠']
      ],
      numericColumns: const {1},
    ));
    expect((cells[1][1]! as IntCellValue).value, -2000);
  });

  group('ما لا يُقرأ رقمًا', () {
    test('عمودٌ غير معلَّم يبقى نصًّا', () {
      final cells = read(ExcelExport.build(
        sheetName: 'أدلّة',
        headers: const ['الكود', 'الصنف'],
        rows: [
          ['000073', 'أرز']
        ],
      ));
      // **الأصفار الأمامية تُحمى**: رقم السند والهاتف نصّان لا كمّيتان.
      expect(cells[1][0], isA<TextCellValue>());
    });

    test('نصٌّ في عمودٍ رقميّ لا يُكسر الملف', () {
      final cells = read(ExcelExport.build(
        sheetName: 'أرصدة',
        headers: const ['الصنف', 'الرصيد'],
        rows: [
          ['أرز', '—']
        ],
        numericColumns: const {1},
      ));
      expect(cells[1][1], isA<TextCellValue>());
    });

    test('الخلية الفارغة تبقى فارغة', () {
      final cells = read(ExcelExport.build(
        sheetName: 'أرصدة',
        headers: const ['الصنف', 'الرصيد'],
        rows: [
          ['أرز', '']
        ],
        numericColumns: const {1},
      ));
      expect(cells[1][1], isA<TextCellValue>());
    });

    test('التاريخ لا ينقلب رقمًا', () {
      final cells = read(ExcelExport.build(
        sheetName: 'حركة',
        headers: const ['التاريخ', 'الكمية'],
        rows: [
          ['٢٠٢٦-٠٦-٢١', nf(100)]
        ],
        numericColumns: const {1},
      ));
      expect(cells[1][0], isA<TextCellValue>());
      expect((cells[1][1]! as IntCellValue).value, 100);
    });
  });

  test('العناوين نصٌّ دائمًا', () {
    final cells = read(ExcelExport.build(
      sheetName: 'أرصدة',
      headers: const ['م', '2026'],
      rows: const [],
    ));
    expect(cells.first.every((c) => c is TextCellValue), isTrue);
  });
}
