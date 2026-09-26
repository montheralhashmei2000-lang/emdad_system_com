import 'dart:io';

import 'package:excel/excel.dart';

/// تصدير جداول التقارير إلى ملف Excel — الأرقام تُكتب أرقامًا لا نصًا
/// حتى تصلح للجمع والفرز في الملف الناتج.
class ExcelExport {
  static List<int> build({
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
    Set<int> numericColumns = const {},
  }) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    final name = _safeSheetName(sheetName);
    final sheet = book[name];

    sheet.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow([
        for (final (i, v) in row.indexed)
          _cell(v, numeric: numericColumns.contains(i)),
      ]);
    }

    if (defaultSheet != null && defaultSheet != name) book.delete(defaultSheet);
    return book.encode() ?? const [];
  }

  static Future<String> writeToFile({
    required String path,
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
    Set<int> numericColumns = const {},
  }) async {
    final bytes = build(
      sheetName: sheetName,
      headers: headers,
      rows: rows,
      numericColumns: numericColumns,
    );
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// خليةٌ رقمية أو نصية.
  ///
  /// **الرقم يصل هنا منسَّقًا للعرض** — أرقامٌ هندية وفاصلةُ آلاف — فـ
  /// `double.tryParse` يفشل فيه ويخرج نصًّا، فلا يُجمع في Excel ولا يُفرز
  /// ولا يُرسم. والتحويلُ يسبق التحليل.
  ///
  /// ولا يقع إلا على عمودٍ [numeric] تعلنه الشاشة.
  static CellValue _cell(String value, {bool numeric = false}) {
    final trimmed = value.trim();
    // **العمود غير المعلَّم نصٌّ ولو بدا رقمًا.** «٠٠٠٠٧٣» رقمُ سندٍ لا
    // كمّية، وقراءتُه رقمًا تبتلع أصفاره؛ والشاشة وحدها تعرف أي أعمدتها
    // كمّيات — فلا يُخمِّن المصدِّر.
    if (!numeric || trimmed.isEmpty) return TextCellValue(value);
    final number = double.tryParse(_latin(trimmed));
    if (number != null) {
      return number == number.roundToDouble()
          ? IntCellValue(number.toInt())
          : DoubleCellValue(number);
    }
    return TextCellValue(value);
  }

  /// يُعيد الرقم المعروض إلى صيغةٍ يقرؤها `double.tryParse`.
  static String _latin(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        // ٠-٩ الهندية
        b.writeCharCode(0x30 + (r - 0x0660));
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        // ۰-۹ الفارسية، تَرِد من لصقٍ خارجي
        b.writeCharCode(0x30 + (r - 0x06F0));
      } else if (r == 0x066B || r == 0x002E) {
        // الفاصلة العشرية بصيغتيها
        b.write('.');
      } else if (r == 0x066C || r == 0x002C || r == 0x2019 || r == 0x0020) {
        // فواصل الآلاف تُحذف
        continue;
      } else if (r == 0x061C || r == 0x200F || r == 0x200E) {
        // علامات الاتجاه لا تُطبع ولا تُحلَّل
        continue;
      } else if (r == 0x2212) {
        // إشارة الطرح الرياضية «−» غير الشرطة
        b.write('-');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// أسماء أوراق Excel لا تقبل هذه المحارف ولا تتجاوز 31 محرفًا.
  static String _safeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    final short = cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
    return short.isEmpty ? 'تقرير' : short;
  }
}
