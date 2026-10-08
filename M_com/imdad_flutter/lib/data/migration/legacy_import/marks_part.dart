part of '../legacy_import.dart';

/// الأرصدة السالبة وشواهد الحذف (tombstones) وتثبيت العلامات بعد الدمج.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyMarks on _LegacyBase {
  /// مفاتيح الأرصدة السالبة الآن (مستودع|صنف)، أو `null` إن تعذّر الحساب.
  Future<Set<String>?> _negativeKeys() async {
    try {
      return {for (final n in await MovementsRepo(db).negativeBalances()) n.key};
    } catch (err, stack) {
      ErrorLogger.log('import.negativeSnapshot', err, stack);
      return null;
    }
  }

  /// بعد الدمج: كل رصيدٍ **انتقل** من غير سالب إلى سالب يُسجَّل حدثًا عالي الخطورة.
  ///
  /// المقارنة بلقطة ما قبل الدمج هي ما يمنع التكرار: مزامنة لم تغيّر شيئًا، أو رصيدٌ
  /// سالب قائم من قبل، لا يكتبان سطرًا جديدًا. كشفٌ فقط — لا يمنع الدمج ولا يُسوّي
  /// شيئًا (التسوية قرار إداري)، وإخفاقه لا يُفشل الاستيراد.
  Future<void> _auditNewNegatives(Set<String>? before, String source) async {
    if (before == null) return;
    try {
      final fresh = [
        for (final n in await MovementsRepo(db).negativeBalances())
          if (!before.contains(n.key)) n,
      ];
      if (fresh.isEmpty) return;
      final items = {for (final i in await db.select(db.items).get()) i.id: i};
      final audit = AuditRepo(db);
      final at = DateTime.now().toIso8601String();
      for (final n in fresh) {
        final item = items[n.itemId];
        await audit.log(
          action: 'sync.negative_stock',
          entityType: 'مزامنة',
          summary: 'رصيد سالب بعد الدمج: ${item?.name ?? n.itemId} في ${n.warehouse} (${n.qty})',
          risk: AuditRepo.riskHigh,
          details: {
            'warehouse': n.warehouse,
            'itemId': n.itemId,
            'itemCode': item?.code ?? '',
            'itemName': item?.name ?? '',
            'balance': n.qty,
            'source': source,
            'at': at,
          },
        );
      }
    } catch (err, stack) {
      ErrorLogger.log('import.negativeAudit', err, stack);
    }
  }

  /// ما حُذف في الجهاز الآخر يُحذف هنا أيضًا — ما لم يُعدَّل عندنا بعد حذفه.
  Future<void> _applyTombstones(SyncMarks marks, LegacyImportResult res) async {
    var removed = 0;
    for (final mark in _incoming.values) {
      if (!mark.isDeleted) continue;
      if (!SyncMarks.entities.containsKey(mark.entity)) continue;
      final local = _local[mark.key];
      if (local != null && local.stamp > mark.stamp) continue;
      try {
        await marks.applyTombstone(mark);
      } on Exception catch (err, stack) {
        // صنفٌ حُذف في الجهاز الآخر وله حركات هنا: يمنعه مشغّل القاعدة، ويبقى الصنف
        // مكانه بدل أن تُجهض المزامنة كلها.
        ErrorLogger.log('sync.tombstone', err, stack);
        res.warnings.add('تعذّر تطبيق حذف منقول (${mark.entity}/${mark.rowId}) — له سجلات مرتبطة');
        continue;
      }
      removed++;
    }
    if (removed > 0) res.inserted['محذوفات منقولة'] = removed;
  }

  /// تثبيت الختم الفائز لكل سجل بدل الختم الذي كتبته المحفِّزات لحظة الاستيراد،
  /// حتى يصل الجهازان إلى العلامات نفسها ولا تتأرجح المزامنة التالية.
  Future<void> _settleMarks(SyncMarks marks) async {
    for (final entry in _incoming.entries) {
      final incoming = entry.value;
      final local = _local[entry.key];
      final winner =
          (local == null || incoming.stamp >= local.stamp) ? incoming : local;
      await marks.put(winner);
    }
  }

  /// أوامر الجرد وسطورها — بيانات تشغيلية كانت خارج المزامنة، فكانت جلسة جرد
  /// تتم في فرع ولا تبلغ الإدارة أبدًا.
}
