import 'dart:typed_data';

import '../xlsx_reader.dart';
import 'template_kind.dart';

/// جدول «البيانات» مقروءًا بـ[XlsxReader] — لا بحزمة `excel` التي ترفض ملفات
/// Excel العربية ذات تنسيقات الأرقام المخصصة.
class TemplateTable {
  TemplateTable._(this.sheetName, this.rows, this._columns);

  final String sheetName;

  /// كل الصفوف بما فيها صف العناوين (الفهرس 0).
  final List<List<XCell?>> rows;

  /// عنوانٌ مطبَّع ← رقم العمود.
  final Map<String, int> _columns;

  /// يقرأ الملف ويختار ورقة البيانات. يرمي [FormatException] برسالة عربية.
  factory TemplateTable.fromBytes(Uint8List bytes) {
    final List<XSheet> sheets;
    try {
      sheets = XlsxReader.read(bytes);
    } on FormatException {
      throw const FormatException('تعذّرت قراءة الملف — تأكد أنه ملف Excel بصيغة xlsx');
    }
    if (sheets.isEmpty) throw const FormatException('الملف لا يحوي أي ورقة');
    final named = sheets.where((s) => normalizeHeader(s.name) == normalizeHeader(TemplateSpec.dataSheet));
    final sheet = named.isNotEmpty
        ? named.first
        : sheets.firstWhere(
            (s) => normalizeHeader(s.name) != normalizeHeader(TemplateSpec.instructionsSheet),
            orElse: () => sheets.first,
          );
    if (sheet.rows.isEmpty) throw const FormatException('الورقة فارغة');
    final cols = <String, int>{};
    final head = sheet.rows.first;
    for (var i = 0; i < head.length; i++) {
      final key = normalizeHeader(cellText(head[i]));
      if (key.isNotEmpty) cols.putIfAbsent(key, () => i);
    }
    return TemplateTable._(sheet.name, sheet.rows, cols);
  }

  /// كل القوالب التي تطابق عناوين الملف.
  ///
  /// قالبٌ مفاتيحه مجموعةٌ جزئية صِرفة من مفاتيح قالبٍ آخر مطابق يسقط: ملف
  /// الأرصدة الافتتاحية يحوي كل عناوين الأصناف (كود، اسم، وحدة 1) وزيادة، فهو
  /// ليس ملف أصناف. وقالبا الأرصدة الافتتاحية والعد الفعلي عناوينهما واحدة
  /// فيبقيان معًا — تحسمهما الشاشة التي فُتح منها الاستيراد.
  List<TemplateKind> detectAll() {
    final hits = [
      for (final spec in TemplateSpec.all)
        if (spec.detectKeys.every((h) => _columns.containsKey(normalizeHeader(h)))) spec,
    ];
    Set<String> keys(TemplateSpec s) => {for (final h in s.detectKeys) normalizeHeader(h)};
    return [
      for (final a in hits)
        if (!hits.any((b) => !identical(a, b) && keys(b).length > keys(a).length && keys(b).containsAll(keys(a))))
          a.kind,
    ];
  }

  /// القالب إن لم يلتبس غيره به، وإلا `null` (لا قالب، أو عدّة قوالب متطابقة).
  TemplateKind? detect() {
    final all = detectAll();
    return all.length == 1 ? all.first : null;
  }

  /// رقم عمود [header]، أو `null` إن لم يوجد.
  int? col(String header) => _columns[normalizeHeader(header)];

  /// صفوف البيانات ذات المحتوى: (رقم الصف في الورقة 1‑based، الخلايا).
  Iterable<(int, List<XCell?>)> dataRows() sync* {
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => c == null || c.isEmpty)) continue;
      yield (r + 1, row);
    }
  }

  XCell? cell(List<XCell?> row, String header) {
    final i = col(header);
    return i == null || i >= row.length ? null : row[i];
  }
}

/// نصّ الخلية مشذَّبًا. الرقم الصحيح بلا «.0» (كودٌ مكتوب 1001 رقمًا).
String cellText(XCell? c) {
  if (c == null) return '';
  final t = c.text;
  if (t != null) return t.replaceAll(RegExp('[‎‏؜]'), '').trim();
  final n = c.number;
  if (n == null) return '';
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// أرقام هندية/فارسية → لاتينية وفواصل عشرية مألوفة.
String latinDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + (r - 0x0660));
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + (r - 0x06F0));
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x066C || r == 0x200E || r == 0x200F || r == 0x061C) {
      continue;
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// هل في الخلية محتوى (نصٌّ أو رقم أو معادلة)؟
bool hasContent(XCell? c) => c != null && !c.isEmpty;

/// قيمة الخلية رقمًا: الرقم الخام، وإلا النص المحلَّل. `null` إن لم يُفهم.
/// الخلية الفارغة تُعطي `null` أيضًا — يفرّق [hasContent] بين الحالتين.
double? cellNum(XCell? c) {
  if (c == null) return null;
  if (c.number != null) return c.number;
  final t = latinDigits(cellText(c)).replaceAll(',', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
