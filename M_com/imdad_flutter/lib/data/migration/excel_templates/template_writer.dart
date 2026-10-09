import 'package:excel/excel.dart';

import 'template_kind.dart';

/// معادلة Excel تُكتب كما هي (`=B2+C2`) ويحسبها Excel عند الفتح.
///
/// في ملف xlsx تُحفظ المعادلة في `<f>` **بلا** علامة «=» (يعرضها Excel `=B2+C2`)؛
/// فالبادئة تُزال هنا إن كُتبت.
class TFormula {
  const TFormula(this.formula);
  final String formula;

  String get stored => formula.startsWith('=') ? formula.substring(1) : formula;
}

/// كاتب ملفات القوالب: ورقتان — «البيانات» (أرقام لاتينية) و«التعليمات»
/// (أرقام عربية). لا يستعمل `ExcelExport` الذي يكتب ورقةً واحدة بلا معادلات.
class TemplateWriter {
  TemplateWriter._();

  /// [rows]: `String` نصّ، `num` رقم (يبقى رقمًا قابلًا للجمع)، [TFormula] معادلة،
  /// `null` خلية فارغة.
  static List<int> build(TemplateSpec spec, List<List<Object?>> rows) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();

    final data = book[TemplateSpec.dataSheet];
    data.isRTL = true;
    data.appendRow([
      for (final h in spec.headers) TextCellValue(h),
    ]);
    for (var c = 0; c < spec.headers.length; c++) {
      data.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle =
          CellStyle(bold: true);
      data.setColumnWidth(c, 20);
    }
    for (final row in rows) {
      data.appendRow([for (final v in row) _cell(v)]);
    }

    final help = book[TemplateSpec.instructionsSheet];
    help.isRTL = true;
    help.setColumnWidth(0, 100);
    for (final line in spec.instructions) {
      help.appendRow([TextCellValue(arabicDigits(line))]);
    }

    if (defaultSheet != null) book.delete(defaultSheet);
    return book.encode() ?? const [];
  }

  static CellValue? _cell(Object? v) {
    if (v == null) return null;
    if (v is TFormula) return FormulaCellValue(v.stored);
    if (v is int) return IntCellValue(v);
    if (v is double) {
      return v == v.roundToDouble() ? IntCellValue(v.toInt()) : DoubleCellValue(v);
    }
    return TextCellValue('$v');
  }
}
