/// جدولٌ حرّ: أعمدته وأسماؤها وأعراضها وصفوفه يحدّدها المستخدم بنفسه.
///
/// يُستعمل في «المرسَل إليهم» بالبرقية. يُحفظ JSON واحدًا:
/// `{"v":2,"title":"","cols":[{"t":"الاسم","w":5}],"rows":[["أحمد"]]}`
/// ويقرأ أيضًا الصيغة القديمة (قائمة `{name,unit,note}`) فلا تضيع برقيةٌ محفوظة.
library;

import 'dart:convert';

/// عمودٌ: عنوانه وعرضه النسبي (يتناسب مع بقية الأعمدة).
class FreeCol {
  const FreeCol(this.title, [this.weight = 5]);

  final String title;
  final double weight;

  FreeCol copyWith({String? title, double? weight}) => FreeCol(title ?? this.title, weight ?? this.weight);
}

class FreeTable {
  const FreeTable({this.title = '', required this.cols, required this.rows});

  /// جدول البداية: ثلاثة أعمدة وصفٌّ فارغ.
  factory FreeTable.starter() => const FreeTable(
        cols: [FreeCol('الاسم'), FreeCol('الوحدة'), FreeCol('ملاحظة')],
        rows: [
          ['', '', '']
        ],
      );

  /// عنوانٌ يُطبع فوق الجدول؛ الفراغ = بلا عنوان.
  final String title;
  final List<FreeCol> cols;
  final List<List<String>> rows;

  /// الجدول لا يُطبع إن لم يُكتب فيه شيء.
  bool get isEmpty => rows.every((r) => r.every((c) => c.trim().isEmpty));

  /// الصفوف غير الفارغة، كلٌّ منها بعدد الأعمدة بالضبط.
  List<List<String>> get filledRows => [
        for (final r in rows)
          if (r.any((c) => c.trim().isNotEmpty)) [for (var i = 0; i < cols.length; i++) i < r.length ? r[i] : ''],
      ];

  String encode() => jsonEncode({
        'v': 2,
        'title': title,
        'cols': [for (final c in cols) {'t': c.title, 'w': c.weight}],
        'rows': filledRows,
      });

  static FreeTable decode(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is List) return _legacy(raw);
      if (raw is Map) {
        final cols = [
          for (final c in (raw['cols'] as List? ?? const []))
            if (c is Map) FreeCol('${c['t'] ?? ''}', (c['w'] is num ? (c['w'] as num).toDouble() : 5).clamp(1, 100).toDouble()),
        ];
        if (cols.isEmpty) return FreeTable.starter();
        final rows = [
          for (final r in (raw['rows'] as List? ?? const []))
            if (r is List) [for (var i = 0; i < cols.length; i++) i < r.length ? '${r[i]}' : ''],
        ];
        return FreeTable(title: '${raw['title'] ?? ''}', cols: cols, rows: rows.isEmpty ? [List.filled(cols.length, '')] : rows);
      }
    } catch (_) {}
    return FreeTable.starter();
  }

  /// الصيغة القديمة: قائمة `{name, unit, note}`.
  static FreeTable _legacy(List raw) {
    final rows = [
      for (final e in raw)
        if (e is Map) ['${e['name'] ?? ''}', '${e['unit'] ?? ''}', '${e['note'] ?? ''}'],
    ];
    final base = FreeTable.starter();
    return FreeTable(cols: base.cols, rows: rows.isEmpty ? base.rows : rows);
  }
}
