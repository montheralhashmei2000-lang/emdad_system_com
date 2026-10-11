part of '../legacy_import.dart';

/// سجلاتٌ لها **مفتاحٌ طبيعيٌّ فريد** غير المعرّف (البند H-1 في تدقيق 2026-10-10).
///
/// جهازان يُنشئان السجلَّ «نفسه» قبل أن يتزامنا — سجلُّ معسكرٍ لشهرٍ واحد،
/// تصفيةُ الشهر نفسه، وحدةُ محروقاتٍ بالاسم نفسه، رصيدٌ افتتاحيٌّ لصنفٍ في
/// مستودع — فيحمل كلٌّ منهما معرّفًا مختلفًا. كان الدمج يكتب بالمعرّف، فيصطدم
/// الفهرس الفريد ويُجهض معاملة الاستيراد **كلها** في كل دورة إلى الأبد: توقّفت
/// المزامنة بين الجهازين لكل البيانات، والرسالة «تعذّر الاتصال».
///
/// والرصيد الافتتاحي (H-7) أسوأ لأنه بلا فهرس: الصفّان يبقيان فيُجمعان، فيُحتسب
/// الرصيد مرتين بصمت.
///
/// **القاعدة (حتمية على الجهازين):** يبقى الأحدث ختمًا، وعند التساوي الأصغر
/// معرّفًا. فإن فاز الوارد حُذف المحلي (فيسافر شاهد حذفه) وحُوّلت إليه المراجع؛
/// وإن خسر لم يُكتب ولم تُثبَّت علامته. وكلا الجهازين يحكمان على الزوج نفسه
/// بالقاعدة نفسها، فيلتقيان على صفٍّ واحد.
mixin _LegacyNaturalKeys on _LegacyBase {
  /// الجدول ← أعمدة مفتاحه الطبيعي.
  static const Map<String, List<String>> naturalKeys = {
    'opening_balances': ['item_id', 'warehouse'],
    'camp_ledgers': ['camp_id', 'item_id', 'year', 'month'],
    'camp_stock_limits': ['camp_id', 'item_id'],
    'monthly_settlements': ['year', 'month'],
    'warehouse_stock_limits': ['warehouse_id', 'item_id'],
    'fuel_units': ['name'],
    'fuel_warehouses': ['name'],
  };

  /// مراجعُ بالمعرّف تُحوَّل إلى الفائز حين يُحذف الخاسر. (مستودعات المحروقات
  /// يُشار إليها بالاسم، والاسم واحد، فلا مراجع تُحوَّل.)
  static const Map<String, List<(String, String)>> _references = {
    'fuel_units': [('fuel_allocations', 'unit_id'), ('fuel_issues', 'beneficiary_unit_id')],
  };

  /// هل يُكتب الصفّ الوارد [incomingId] من [entity] بمفتاحه الطبيعي [values]؟
  ///
  /// يحسم كل صفٍّ محليٍّ بالمفتاح نفسه ومعرّفٍ آخر: الوارد يفوز ⇒ يُحذف المحلي
  /// وتُحوَّل مراجعه؛ المحلي يفوز ⇒ لا يُكتب الوارد ولا تُثبَّت علامته.
  Future<bool> _claimNaturalKey(
    String entity,
    String incomingId,
    List<Object> values,
    LegacyImportResult res,
  ) async {
    final cols = naturalKeys[entity]!;
    final where = cols.map((c) => '"$c" = ?').join(' AND ');
    Variable<Object> v(Object x) => x is int ? Variable<int>(x) : Variable<String>('$x');
    final rows = await db.customSelect(
      'SELECT id FROM "$entity" WHERE $where AND id <> ?',
      variables: [for (final x in values) v(x), Variable<String>(incomingId)],
    ).get();
    if (rows.isEmpty) return true;

    final inStamp = _incoming['$entity/$incomingId']?.stamp ?? 0;
    final losers = <String>[];
    for (final r in rows) {
      final localId = r.read<String>('id');
      final localStamp = _local['$entity/$localId']?.stamp ?? 0;
      final incomingWins =
          inStamp > localStamp || (inStamp == localStamp && incomingId.compareTo(localId) < 0);
      if (!incomingWins) {
        _rejectedMarks.add('$entity/$incomingId');
        (_replacedIds[entity] ??= {})[incomingId] = localId;
        _count(res, 'تعارضات محسومة', 1);
        return false;
      }
      losers.add(localId);
    }
    for (final localId in losers) {
      (_replacedIds[entity] ??= {})[localId] = incomingId;
      for (final (table, column) in _references[entity] ?? const <(String, String)>[]) {
        await db.customStatement('UPDATE "$table" SET "$column" = ? WHERE "$column" = ?', [incomingId, localId]);
      }
      await db.customStatement('DELETE FROM "$entity" WHERE id = ?', [localId]);
    }
    _count(res, 'تعارضات محسومة', losers.length);
    return true;
  }

  /// كتابة صفٍّ في نقطة حفظٍ مستقلة: صفٌّ يخالف قيدًا لم يُتوقَّع لا يُسقط
  /// معاملة الاستيراد كلها — يُتجاوز، ولا تُثبَّت علامته، ويُعدّ خطأً فلا تتقدّم
  /// علامة الماء (فيُعاد طلبه في الدورة القادمة).
  Future<bool> _guardedRow(String entity, String id, LegacyImportResult res, Future<void> Function() write) async {
    try {
      await db.transaction(write);
      return true;
    } catch (err, stack) {
      ErrorLogger.log('import.row.$entity', err, stack);
      _rejectedMarks.add('$entity/$id');
      res.failedRows++;
      res.warnings.add('تعذّر دمج سجلٍّ في $entity ($id): $err');
      return false;
    }
  }
}
