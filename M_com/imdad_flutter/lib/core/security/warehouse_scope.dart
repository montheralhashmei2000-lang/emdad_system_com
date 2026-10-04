import 'dart:convert';

import '../error_log.dart';

/// يقرأ نطاق المستودعات المخزَّن لمستخدم (`users.warehouse_scope`).
///
/// القيم الصحيحة: `ALL` (كل المستودعات ⇒ `null`) أو JSON بقائمة أسماء.
///
/// **فشلٌ مغلق:** أي قيمة أخرى — نصٌّ تالف، JSON ليس قائمة، فراغ — تُعدّ تالفة،
/// فتُرجع قائمةً **فارغة** (لا مستودعات) وتُسجَّل خطأً حرجًا. كان التلف يُرجع
/// `null` أي «كل المستودعات»، فيرى المستخدم المقيَّد كل شيء بسبب تلف قيمته.
/// يصلح المدير النطاق من «المستخدمون والصلاحيات».
List<String>? parseWarehouseScope(String raw, {required String source}) {
  if (raw.trim().toUpperCase() == 'ALL') return null;
  try {
    final v = jsonDecode(raw);
    if (v is List) return [for (final e in v) e.toString()];
    throw FormatException('نطاق المستودعات ليس قائمة: «$raw»');
  } catch (err, stack) {
    ErrorLogger.critical(source, err, stack: stack);
    return const <String>[];
  }
}
