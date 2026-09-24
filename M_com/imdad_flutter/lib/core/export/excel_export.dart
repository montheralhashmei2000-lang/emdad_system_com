import 'dart:io';

import 'package:excel/excel.dart';

/// تصدير جداول التقارير إلى ملف Excel — الأرقام تُكتب أرقامًا لا نصًا
/// حتى تصلح للجمع والفرز في الملف الناتج.
class ExcelExport {
  static List<int> build({
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    final name = _safeSheetName(sheetName);
    final sheet = book[name];

    sheet.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map<CellValue?>(_cell).toList());
    }

    if (defaultSheet != null && defaultSheet != name) book.delete(defaultSheet);
    return book.encode() ?? const [];
  }

  static Future<String> writeToFile({
    required String path,
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final bytes = build(sheetName: sheetName, headers: headers, rows: rows);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static CellValue _cell(String value) {
    final trimmed = value.trim();
    final number = double.tryParse(trimmed);
    if (number != null && trimmed.isNotEmpty) {
      return number == number.roundToDouble()
          ? IntCellValue(number.toInt())
          : DoubleCellValue(number);
    }
    return TextCellValue(value);
  }

  /// أسماء أوراق Excel لا تقبل هذه المحارف ولا تتجاوز 31 محرفًا.
  static String _safeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    final short = cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
    return short.isEmpty ? 'تقرير' : short;
  }
}
