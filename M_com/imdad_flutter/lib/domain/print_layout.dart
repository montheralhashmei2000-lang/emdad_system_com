/// تخطيط المستندات المطبوعة — نقل لإعدادات print-layout.js.
///
/// القواعد المحفوظة كما هي في نسخة الويب:
/// • أعلى الصفحة يمينًا: أسطر الجهة (الجمهورية اليمنية، وزارة الدفاع، …).
/// • أعلى الصفحة يسارًا: حقول السند (التاريخ، رقم القيد، رقم السند، …).
/// • كل حقل عربي: **العنوان من اليمين والقيمة من اليسار**.
/// • لكل عنصر تحكّم في الإظهار والخط والحجم والمحاذاة والعريض.
library;

import 'dart:convert';

import '../core/ui/imd_fonts.dart';

enum PrintAlign { right, center, left }

PrintAlign alignFrom(String? v) => switch (v) {
      'left' => PrintAlign.left,
      'center' => PrintAlign.center,
      _ => PrintAlign.right,
    };

String alignName(PrintAlign a) => a.name;

class PrintLine {
  const PrintLine({
    required this.text,
    this.show = true,
    this.bold = false,
    this.size = 11,
    this.align = PrintAlign.right,
  });

  final String text;
  final bool show;
  final bool bold;
  final double size;
  final PrintAlign align;

  PrintLine copyWith({String? text, bool? show, bool? bold, double? size, PrintAlign? align}) =>
      PrintLine(
        text: text ?? this.text,
        show: show ?? this.show,
        bold: bold ?? this.bold,
        size: size ?? this.size,
        align: align ?? this.align,
      );

  Map<String, dynamic> toMap() => {
        'text': text,
        'show': show,
        'bold': bold,
        'size': size,
        'align': alignName(align),
      };

  factory PrintLine.fromMap(Map<String, dynamic> m) => PrintLine(
        text: (m['text'] ?? '').toString(),
        show: m['show'] != false,
        bold: m['bold'] == true,
        size: (m['size'] as num?)?.toDouble() ?? 11,
        align: alignFrom(m['align'] as String?),
      );
}

/// حقل «عنوان: قيمة» — العنوان يمينًا والقيمة يسارًا افتراضيًا.
class PrintField {
  const PrintField({
    required this.key,
    required this.label,
    this.show = true,
    this.bold = false,
    this.size = 10.5,
    this.labelAlign = PrintAlign.right,
    this.valueAlign = PrintAlign.left,
  });

  final String key;
  final String label;
  final bool show;
  final bool bold;
  final double size;
  final PrintAlign labelAlign;
  final PrintAlign valueAlign;

  PrintField copyWith({
    String? label,
    bool? show,
    bool? bold,
    double? size,
    PrintAlign? labelAlign,
    PrintAlign? valueAlign,
  }) =>
      PrintField(
        key: key,
        label: label ?? this.label,
        show: show ?? this.show,
        bold: bold ?? this.bold,
        size: size ?? this.size,
        labelAlign: labelAlign ?? this.labelAlign,
        valueAlign: valueAlign ?? this.valueAlign,
      );

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'show': show,
        'bold': bold,
        'size': size,
        'labelAlign': alignName(labelAlign),
        'valueAlign': alignName(valueAlign),
      };

  factory PrintField.fromMap(Map<String, dynamic> m) => PrintField(
        key: (m['key'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        show: m['show'] != false,
        bold: m['bold'] == true,
        size: (m['size'] as num?)?.toDouble() ?? 10.5,
        labelAlign: alignFrom(m['labelAlign'] as String?),
        valueAlign: alignFrom(m['valueAlign'] as String? ?? 'left'),
      );
}

class TableStyle {
  const TableStyle({
    this.headAlign = PrintAlign.center,
    this.cellAlign = PrintAlign.right,
    this.firstColAlign = PrintAlign.center,
    this.numAlign = PrintAlign.center,
    this.size = 10,
    this.headBold = true,
  });

  final PrintAlign headAlign;
  final PrintAlign cellAlign;

  /// عمود التسلسل.
  final PrintAlign firstColAlign;

  /// الأعمدة الرقمية (الكمية، المعامل، الرصيد…).
  final PrintAlign numAlign;
  final double size;
  final bool headBold;

  /// محاذاة خلية حسب موضعها ومحتواها — نفس قاعدة نسخة الويب.
  PrintAlign alignFor(int columnIndex, String content) {
    if (columnIndex == 0) return firstColAlign;
    return isNumeric(content) ? numAlign : cellAlign;
  }

  static final RegExp _numeric = RegExp(r'^[0-9٠-٩.,٬\s+-]+$');

  static bool isNumeric(String s) => s.trim().isNotEmpty && _numeric.hasMatch(s.trim());

  Map<String, dynamic> toMap() => {
        'headAlign': alignName(headAlign),
        'cellAlign': alignName(cellAlign),
        'firstColAlign': alignName(firstColAlign),
        'numAlign': alignName(numAlign),
        'size': size,
        'headBold': headBold,
      };

  factory TableStyle.fromMap(Map<String, dynamic> m) => TableStyle(
        headAlign: alignFrom(m['headAlign'] as String? ?? 'center'),
        cellAlign: alignFrom(m['cellAlign'] as String?),
        firstColAlign: alignFrom(m['firstColAlign'] as String? ?? 'center'),
        numAlign: alignFrom(m['numAlign'] as String? ?? 'center'),
        size: (m['size'] as num?)?.toDouble() ?? 10,
        headBold: m['headBold'] != false,
      );
}

class PrintLayout {
  const PrintLayout({
    this.fontFamily = 'Amiri',
    this.baseSize = 11,
    this.showLogo = true,
    this.right = const [],
    this.left = const [],
    this.info = const [],
    this.signatures = const [],
    this.footer = const [],
    this.table = const TableStyle(),
    this.titleSize = 15,
    this.titleAlign = PrintAlign.center,
    this.approval = const PrintLine(text: 'مصادقة رئيس شعبة الإمداد والتموين', size: 9, bold: true),
  });

  final String fontFamily;
  final double baseSize;
  final bool showLogo;

  /// أسطر الجهة أعلى اليمين.
  final List<PrintLine> right;

  /// حقول أعلى اليسار.
  final List<PrintField> left;

  /// حقول بيانات السند.
  final List<PrintField> info;

  /// خانات التوقيع.
  final List<PrintLine> signatures;
  final List<PrintLine> footer;
  final TableStyle table;
  final double titleSize;
  final PrintAlign titleAlign;

  /// مربع المصادقة أعلى يسار سندات التوريد والعمل اليومي.
  /// كان مثبّتًا في الكود بلا أي خيار لإخفائه أو تعديل نصه.
  final PrintLine approval;

  static const PrintLayout defaults = PrintLayout(
    right: [
      PrintLine(text: 'الجمهورية اليمنية', bold: true, size: 12),
      PrintLine(text: 'وزارة الدفاع'),
      PrintLine(text: 'قيادة المنطقة'),
      PrintLine(text: 'دائرة الإمداد والتموين'),
    ],
    left: [
      PrintField(key: 'date', label: 'التاريخ'),
      PrintField(key: 'entryNo', label: 'رقم القيد'),
      PrintField(key: 'refNo', label: 'رقم السند'),
    ],
    info: [
      PrintField(key: 'warehouse', label: 'المستودع'),
      PrintField(key: 'party', label: 'الجهة'),
      PrintField(key: 'notes', label: 'ملاحظات'),
    ],
    signatures: [
      PrintLine(text: 'أمين المستودع', align: PrintAlign.right),
      PrintLine(text: 'المستلم', align: PrintAlign.center),
      PrintLine(text: 'ركن الإمداد', align: PrintAlign.left),
    ],
    footer: [
      PrintLine(text: 'نظام الإمداد والتموين', size: 9, align: PrintAlign.center),
    ],
  );

  PrintLayout copyWith({
    String? fontFamily,
    double? baseSize,
    bool? showLogo,
    List<PrintLine>? right,
    List<PrintField>? left,
    List<PrintField>? info,
    List<PrintLine>? signatures,
    List<PrintLine>? footer,
    TableStyle? table,
    double? titleSize,
    PrintAlign? titleAlign,
    PrintLine? approval,
  }) =>
      PrintLayout(
        fontFamily: fontFamily ?? this.fontFamily,
        baseSize: baseSize ?? this.baseSize,
        showLogo: showLogo ?? this.showLogo,
        right: right ?? this.right,
        left: left ?? this.left,
        info: info ?? this.info,
        signatures: signatures ?? this.signatures,
        footer: footer ?? this.footer,
        table: table ?? this.table,
        titleSize: titleSize ?? this.titleSize,
        titleAlign: titleAlign ?? this.titleAlign,
        approval: approval ?? this.approval,
      );

  Map<String, dynamic> toMap() => {
        'fontFamily': fontFamily,
        'baseSize': baseSize,
        'showLogo': showLogo,
        'right': right.map((e) => e.toMap()).toList(),
        'left': left.map((e) => e.toMap()).toList(),
        'info': info.map((e) => e.toMap()).toList(),
        'signatures': signatures.map((e) => e.toMap()).toList(),
        'footer': footer.map((e) => e.toMap()).toList(),
        'table': table.toMap(),
        'titleSize': titleSize,
        'titleAlign': alignName(titleAlign),
        'approval': approval.toMap(),
      };

  String toJson() => jsonEncode(toMap());

  factory PrintLayout.fromMap(Map<String, dynamic> m) => PrintLayout(
        fontFamily: ImdPrintFonts.normalize('${m['fontFamily'] ?? ''}'),
        baseSize: (m['baseSize'] as num?)?.toDouble() ?? 11,
        showLogo: m['showLogo'] != false,
        right: _lines(m['right']) ?? defaults.right,
        left: _fields(m['left']) ?? defaults.left,
        info: _fields(m['info']) ?? defaults.info,
        signatures: _lines(m['signatures']) ?? defaults.signatures,
        footer: _lines(m['footer']) ?? defaults.footer,
        table: m['table'] is Map
            ? TableStyle.fromMap(Map<String, dynamic>.from(m['table'] as Map))
            : const TableStyle(),
        titleSize: (m['titleSize'] as num?)?.toDouble() ?? 15,
        titleAlign: alignFrom(m['titleAlign'] as String? ?? 'center'),
        approval: m['approval'] is Map
            ? PrintLine.fromMap(Map<String, dynamic>.from(m['approval'] as Map))
            : defaults.approval,
      );

  factory PrintLayout.fromJson(String source) {
    if (source.trim().isEmpty) return defaults;
    final decoded = jsonDecode(source);
    if (decoded is! Map) return defaults;
    return PrintLayout.fromMap(Map<String, dynamic>.from(decoded));
  }

  static List<PrintLine>? _lines(dynamic v) => v is List
      ? v.map((e) => PrintLine.fromMap(Map<String, dynamic>.from(e as Map))).toList()
      : null;

  static List<PrintField>? _fields(dynamic v) => v is List
      ? v.map((e) => PrintField.fromMap(Map<String, dynamic>.from(e as Map))).toList()
      : null;
}
