import 'dart:typed_data';

import '../../domain/custody_sheet.dart';
import 'xlsx_reader.dart';

/// سطر مسير مقروء من Excel، بمدخلاته الخام (كما في الملف).
class ImportedCustodyRow {
  const ImportedCustodyRow({
    this.date = '',
    this.grantSar = 0,
    this.returnSar = 0,
    this.returnYer = 0,
    this.spentSar = 0,
    this.spentYer = 0,
    this.rate = kDefaultYerPerSar,
    this.person = '',
    this.statement = '',
    this.category = '',
    this.entryNo = '',
    this.invoiceNo = '',
    this.shop = '',
    this.notes = '',
  });

  final String date;
  final double grantSar, returnSar, returnYer, spentSar, spentYer, rate;
  final String person, statement, category, entryNo, invoiceNo, shop, notes;
}

/// نتيجة قراءة ملف مسير العهدة.
class CustodySheetImport {
  CustodySheetImport({required this.rows, required this.warnings, this.sheetNo = '', this.defaultRate = kDefaultYerPerSar});

  final List<ImportedCustodyRow> rows;
  final List<String> warnings;

  /// رقم العهدة التشغيلية إن ورد في جملة المتبقي («رقم (2)»).
  final String sheetNo;
  final double defaultRate;
}

/// يقرأ ملف Excel لمسير العهدة بتنسيق الملف المعتمد، فيطابق الأعمدة بعناوينها
/// لا بمواضعها (ترتيب الأعمدة قد يختلف)، ويتعامل مع الترويسة ذات المستويين
/// (مبلغ العهدة / مرتجع / المبلغ المنصرف ← سعودي، يمني).
///
/// خلايا المعادلات (`=F13/410`) لا تُقرأ قيمتها المحفوظة؛ يُكتفى بالمبلغ اليمني
/// وسعر الصرف فيُعاد حساب السعودي في المحرر بالمعادلة نفسها.
class CustodySheetImporter {
  CustodySheetImporter._();

  static String _norm(String s) => s
      .replaceAll('ـ', '') // التطويل «الاســــم»
      .replaceAll(RegExp('[ً-ْ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _text(XCell? d) {
    if (d == null) return '';
    if (d.text != null) return d.text!;
    final n = d.number;
    if (n == null) return '';
    if (d.isDate && n > 20000 && n < 80000) {
      final dt = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
      return _iso(dt.year, dt.month, dt.day);
    }
    return _plainNum(n);
  }

  static String _plainNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  static String _iso(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  static bool _isFormula(XCell? d) => d?.isFormula ?? false;

  static double _num(XCell? d) {
    if (d == null) return 0;
    if (d.number != null) return d.number!;
    return double.tryParse(_latin(d.text ?? '').replaceAll(',', '').trim()) ?? 0;
  }

  /// الأرقام الهندية ← لاتينية، للقيم المكتوبة نصًّا.
  static String _latin(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = ar.indexOf(c);
      b.write(i >= 0 ? '$i' : c);
    }
    return b.toString();
  }

  /// تاريخ الخلية: تاريخ Excel (رقم تسلسلي بتنسيق تاريخ) أو نص `15/05/2026` / `2026-05-15`.
  static String _date(XCell? d) {
    if (d == null) return '';
    final n = d.number;
    if (n != null) {
      if (n > 20000 && n < 80000) {
        final dt = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
        return _iso(dt.year, dt.month, dt.day);
      }
      return '';
    }
    final t = _latin(d.text ?? '').trim();
    final m1 = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(t);
    if (m1 != null) return _iso(int.parse(m1[3]!), int.parse(m1[2]!), int.parse(m1[1]!));
    final m2 = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(t);
    if (m2 != null) return _iso(int.parse(m2[1]!), int.parse(m2[2]!), int.parse(m2[3]!));
    return '';
  }

  static XCell? _at(List<List<XCell?>> rows, int r, int c) => r < rows.length && c >= 0 && c < rows[r].length ? rows[r][c] : null;

  /// يقرأ أول ورقة تحمل ترويسة المسير. يرمي [FormatException] برسالة عربية إن لم يجدها.
  static CustodySheetImport parse(Uint8List bytes) {
    final List<XSheet> sheets;
    try {
      sheets = XlsxReader.read(bytes);
    } on FormatException {
      throw const FormatException('تعذّرت قراءة الملف — تأكد أنه ملف Excel بصيغة xlsx');
    }
    for (final sheet in sheets) {
      final r = _tryParseSheet(sheet.rows);
      if (r != null) return r;
    }
    throw const FormatException('لم أجد ترويسة مسير العهدة (التاريخ، المبلغ المنصرف، رقم الفاتورة…) في أي ورقة');
  }

  static CustodySheetImport? _tryParseSheet(List<List<XCell?>> rows) {
    // 1) صف الترويسة: يحوي «التاريخ» و«الفاتورة» معًا.
    int? head;
    for (var r = 0; r < rows.length && r < 15; r++) {
      final texts = [for (final c in rows[r]) _norm(_text(c))];
      if (texts.any((t) => t == 'التاريخ') && texts.any((t) => t.contains('الفاتوره'))) {
        head = r;
        break;
      }
    }
    if (head == null) return null;
    final h = [for (final c in rows[head]) _norm(_text(c))];
    final sub = head + 1 < rows.length ? [for (final c in rows[head + 1]) _norm(_text(c))] : const <String>[];
    final hasSub = sub.any((t) => t == 'سعودي' || t == 'يمني');

    int col(bool Function(String) f) => h.indexWhere(f);
    final cDate = col((t) => t == 'التاريخ');
    final cGrant = col((t) => t.contains('مبلغ العهده'));
    final cReturn = col((t) => t == 'مرتجع' || t.startsWith('مرتجع'));
    final cSpent = col((t) => t.contains('المنصرف'));
    final cRate = col((t) => t.contains('سعر الصرف'));
    final cPerson = col((t) => t == 'الاسم');
    final cStatement = col((t) => t == 'البيان');
    final cCategory = col((t) => t == 'الفئه');
    final cEntry = col((t) => t.contains('رقم القيد'));
    final cInvoice = col((t) => t.contains('رقم الفاتوره'));
    final cShop = col((t) => t.contains('اسم المحل'));
    final cNotes = col((t) => t.contains('ملاحظات'));

    /// عمودا (سعودي، يمني) تحت عنوان مجموعة، من صف العناوين الفرعية.
    (int, int) pair(int g) {
      if (g < 0) return (-1, -1);
      var sar = -1, yer = -1;
      for (var c = g; c < g + 3 && c < sub.length; c++) {
        if (sub[c] == 'سعودي' && sar < 0) sar = c;
        if (sub[c] == 'يمني' && yer < 0) yer = c;
      }
      // بلا ترويسة فرعية: العمودان المتتاليان سعودي ثم يمني.
      if (sar < 0 && yer < 0) {
        sar = g;
        yer = g + 1;
      }
      return (sar, yer);
    }

    final (retSar, retYer) = hasSub ? pair(cReturn) : (cReturn, cReturn >= 0 ? cReturn + 1 : -1);
    final (spSar, spYer) = hasSub ? pair(cSpent) : (cSpent, cSpent >= 0 ? cSpent + 1 : -1);
    final grantCol = cGrant;

    final warnings = <String>[];
    final out = <ImportedCustodyRow>[];
    var blank = 0;
    String sheetNo = '';
    final rates = <double>[];
    var formulaWithoutYer = 0;
    for (var r = head + (hasSub ? 2 : 1); r < rows.length; r++) {
      final row = rows[r];
      final all = [for (final c in row) _text(c)];
      final joined = all.join(' ');
      final nj = _norm(joined);
      // سطر الإجماليات أو الجملة الختامية ينهي البيانات.
      if (nj.contains('اجمالي') || nj.contains('المتبقي')) {
        final m = RegExp(r'رقم\s*\(([^)]+)\)').firstMatch(joined);
        if (m != null) sheetNo = _latin(m[1]!).trim();
        continue;
      }
      final m = RegExp(r'العهده التشغيليه رقم\s*\(([^)]+)\)').firstMatch(nj);
      if (m != null) {
        sheetNo = _latin(m[1]!).trim();
        continue;
      }
      if (nj.isEmpty) {
        if (++blank >= 3 && out.isNotEmpty) break;
        continue;
      }
      blank = 0;
      XCell? d(int c) => _at(rows, r, c);
      String t(int c) => c < 0 ? '' : _text(d(c)).trim();

      final yerSpent = spYer < 0 ? 0.0 : _num(d(spYer));
      final sarSpentCell = spSar < 0 ? null : d(spSar);
      final sarFormula = _isFormula(sarSpentCell);
      if (sarFormula && yerSpent == 0) formulaWithoutYer++;
      final rate = cRate < 0 ? 0.0 : _num(d(cRate));
      if (rate > 0) rates.add(rate);
      final item = ImportedCustodyRow(
        date: cDate < 0 ? '' : _date(d(cDate)),
        grantSar: grantCol < 0 ? 0 : _num(d(grantCol)),
        returnSar: retSar < 0 || _isFormula(d(retSar)) ? 0 : _num(d(retSar)),
        returnYer: retYer < 0 ? 0 : _num(d(retYer)),
        // المعادلة تُهمل: السعودي يُشتق من اليمني وسعر الصرف.
        spentSar: sarFormula ? 0 : _num(sarSpentCell),
        spentYer: yerSpent,
        rate: rate > 0 ? rate : kDefaultYerPerSar,
        person: t(cPerson),
        statement: t(cStatement),
        category: t(cCategory),
        entryNo: t(cEntry),
        invoiceNo: t(cInvoice),
        shop: t(cShop),
        notes: t(cNotes),
      );
      final empty = item.date.isEmpty &&
          item.grantSar == 0 &&
          item.spentSar == 0 &&
          item.spentYer == 0 &&
          item.returnSar == 0 &&
          item.returnYer == 0 &&
          item.person.isEmpty &&
          item.statement.isEmpty &&
          item.invoiceNo.isEmpty &&
          item.shop.isEmpty;
      if (!empty) out.add(item);
    }
    if (out.isEmpty) {
      warnings.add('لم أجد أسطرًا تحت الترويسة');
    }
    if (formulaWithoutYer > 0) {
      warnings.add('$formulaWithoutYer سطر منصرفه معادلة بلا مبلغ يمني — أدخل المنصرف يدويًّا');
    }
    final noDate = out.where((e) => e.date.isEmpty).length;
    if (noDate > 0) warnings.add('$noDate سطر بلا تاريخ مقروء');
    // سعر الصرف الأكثر شيوعًا هو الافتراضي.
    var common = kDefaultYerPerSar;
    if (rates.isNotEmpty) {
      final freq = <double, int>{};
      for (final x in rates) {
        freq[x] = (freq[x] ?? 0) + 1;
      }
      common = freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    return CustodySheetImport(rows: out, warnings: warnings, sheetNo: sheetNo, defaultRate: common);
  }
}
