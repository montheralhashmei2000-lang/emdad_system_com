import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// خليةٌ مقروءة من xlsx.
class XCell {
  const XCell({this.text, this.number, this.isFormula = false, this.isDate = false});

  /// النص (للخلايا النصية).
  final String? text;

  /// الرقم الخام (للخلايا الرقمية والتواريخ — التاريخ رقمٌ تسلسلي).
  final double? number;

  /// في الخلية معادلة (قيمتها المحفوظة قد تكون موجودة في [number]).
  final bool isFormula;

  /// تنسيق الخلية تاريخ.
  final bool isDate;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && number == null;
}

/// ورقة: شبكة خلايا (الصفوف × الأعمدة) بفهارس تبدأ من الصفر.
class XSheet {
  XSheet(this.name, this.rows);
  final String name;
  final List<List<XCell?>> rows;
}

/// قارئ xlsx مبسّط: النصوص والأرقام والتواريخ والمعادلات (مع قيمتها المحفوظة).
///
/// كُتب لأن حزمة `excel` ترمي على ملفات Excel الواقعية (تنسيقات أرقام مخصصة بمعرّف
/// أقل من ١٦٤) — وهي حالة ملفات المسيرات العربية نفسها. هنا لا يُقرأ التنسيق إلا
/// لمعرفة هل الخلية تاريخ.
class XlsxReader {
  XlsxReader._();

  static final _builtinDates = <int>{14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 45, 46, 47, 50, 51, 52, 53, 54, 55, 56, 57, 58};

  static String _fileText(Archive a, String name) {
    final f = a.findFile(name);
    if (f == null) return '';
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  /// يقرأ كل أوراق الملف. يرمي [FormatException] إن لم يكن xlsx صالحًا.
  static List<XSheet> read(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('الملف ليس xlsx صالحًا');
    }
    final wb = _fileText(zip, 'xl/workbook.xml');
    if (wb.isEmpty) throw const FormatException('الملف ليس xlsx صالحًا');

    final shared = _sharedStrings(_fileText(zip, 'xl/sharedStrings.xml'));
    final dateStyles = _dateStyles(_fileText(zip, 'xl/styles.xml'));

    final rels = <String, String>{};
    for (final r in XmlDocument.parse(_fileText(zip, 'xl/_rels/workbook.xml.rels')).findAllElements('Relationship')) {
      rels[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
    final out = <XSheet>[];
    for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
      final rid = s.attributes.firstWhere((a) => a.name.local == 'id', orElse: () => XmlAttribute(XmlName('id'), '')).value;
      var target = rels[rid] ?? '';
      if (target.isEmpty) continue;
      target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final xml = _fileText(zip, target);
      if (xml.isEmpty) continue;
      out.add(XSheet(s.getAttribute('name') ?? '', _sheetRows(xml, shared, dateStyles)));
    }
    return out;
  }

  static List<String> _sharedStrings(String xml) {
    if (xml.isEmpty) return const [];
    return [
      for (final si in XmlDocument.parse(xml).findAllElements('si')) si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  }

  /// فهارس أنماط الخلايا (`cellXfs`) التي تنسيقها تاريخ.
  static Set<int> _dateStyles(String xml) {
    if (xml.isEmpty) return {};
    final doc = XmlDocument.parse(xml);
    final customDate = <int>{};
    for (final n in doc.findAllElements('numFmt')) {
      final id = int.tryParse(n.getAttribute('numFmtId') ?? '');
      final code = (n.getAttribute('formatCode') ?? '').replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '');
      if (id != null && RegExp('[dmyDMY]').hasMatch(code) && !code.contains('0') && !code.contains('#')) customDate.add(id);
    }
    final styles = <int>{};
    final xfs = doc.findAllElements('cellXfs').firstOrNull;
    if (xfs == null) return styles;
    var i = 0;
    for (final xf in xfs.findElements('xf')) {
      final id = int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0;
      if (_builtinDates.contains(id) || customDate.contains(id)) styles.add(i);
      i++;
    }
    return styles;
  }

  /// `B12` ← (صف 11، عمود 1).
  static (int, int)? _ref(String? ref) {
    if (ref == null) return null;
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref);
    if (m == null) return null;
    var c = 0;
    for (final ch in m[1]!.codeUnits) {
      c = c * 26 + (ch - 64);
    }
    return (int.parse(m[2]!) - 1, c - 1);
  }

  static List<List<XCell?>> _sheetRows(String xml, List<String> shared, Set<int> dateStyles) {
    final grid = <int, Map<int, XCell>>{};
    var maxRow = -1;
    var autoRow = -1;
    for (final row in XmlDocument.parse(xml).findAllElements('row')) {
      autoRow = (int.tryParse(row.getAttribute('r') ?? '') ?? autoRow + 2) - 1;
      var autoCol = -1;
      for (final c in row.findElements('c')) {
        final pos = _ref(c.getAttribute('r'));
        final r = pos?.$1 ?? autoRow;
        final col = pos?.$2 ?? autoCol + 1;
        autoCol = col;
        final t = c.getAttribute('t');
        final v = c.getElement('v')?.innerText;
        final isF = c.getElement('f') != null;
        final style = int.tryParse(c.getAttribute('s') ?? '');
        XCell? cell;
        if (t == 's') {
          final idx = int.tryParse(v ?? '');
          cell = XCell(text: idx != null && idx < shared.length ? shared[idx] : '', isFormula: isF);
        } else if (t == 'inlineStr') {
          cell = XCell(text: c.findAllElements('t').map((e) => e.innerText).join(), isFormula: isF);
        } else if (t == 'str') {
          cell = XCell(text: v ?? '', isFormula: isF);
        } else if (t == 'b') {
          cell = XCell(number: v == '1' ? 1 : 0, isFormula: isF);
        } else if (v != null && v.isNotEmpty) {
          cell = XCell(number: double.tryParse(v), isFormula: isF, isDate: style != null && dateStyles.contains(style));
        } else if (isF) {
          cell = const XCell(isFormula: true);
        }
        if (cell == null) continue;
        (grid[r] ??= {})[col] = cell;
        if (r > maxRow) maxRow = r;
      }
    }
    final out = <List<XCell?>>[];
    for (var r = 0; r <= maxRow; r++) {
      final m = grid[r];
      if (m == null) {
        out.add(const []);
        continue;
      }
      final width = m.keys.reduce((a, b) => a > b ? a : b) + 1;
      out.add([for (var c = 0; c < width; c++) m[c]]);
    }
    return out;
  }
}
