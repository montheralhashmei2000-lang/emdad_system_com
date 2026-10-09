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

  /// لماذا يُرفض شاهد الحذف هذا؟ `null` ⇒ يُطبَّق.
  ///
  /// الشاهد كان لا يمرّ بأي حارس: ختمه بيد المرسِل، فجهازٌ مقترن يحذف ما يشاء.
  ///  • **حساب مميَّز محليًّا** (مدير/مالك): كان يُحذف المالك والمديرون بشاهدٍ
  ///    واحد — والواجهة نفسها لا تحذف المالك. حذفُ مديرٍ شرعيًّا يمرّ بتقاعدٍ موقَّع
  ///    أولًا (`UsersRepo.deleteUser`) فيصل هنا حسابًا عاديًّا يُحذف شاهدُه.
  ///  • **مفتاح إعدادات محلي** (`localOnlyKeys`): كان يمحو سجلّ الثقة (`sync`) أو
  ///    هوية الجهاز ومفتاح المالك الخاص (`device`) — مع أن الصفّ نفسه لا يُستورد.
  /// أما سجل التدقيق فله [_ignoresTombstone].
  Future<String?> _tombstoneRejection(SyncMark mark) async {
    if (mark.entity == 'app_settings' && SettingsRepo.localOnlyKeys.contains(mark.rowId)) {
      return 'مفتاح إعدادات خاص بهذا الجهاز';
    }
    if (mark.entity == 'users') {
      final row = await (db.select(db.users)..where((t) => t.id.equals(mark.rowId))).getSingleOrNull();
      if (row != null && OwnerSignature.rank(row.role) > 0) return 'حساب ${row.role == 'owner' ? 'المالك' : 'مدير'} «${row.username}»';
    }
    return null;
  }

  /// سجل التدقيق لا يُحذف بشاهدٍ وارد — صامتًا بلا شاهد رفض: كل جهازٍ يقلّم
  /// سجلَّه العادي بنفسه (`AuditRepo.prune`) فتسافر شواهدُ ذلك التقليم شرعيًّا في
  /// كل دورة، وتسجيلُ رفضها يملأ السجل الذي جاء الحارس ليحفظه. والمحمي منه
  /// (high/sensitive/critical) لا يُقلَّم أصلًا، فلا يمحوه جهازٌ آخر.
  static bool _ignoresTombstone(SyncMark mark) => mark.entity == 'audit_logs';

  /// ما حُذف في الجهاز الآخر يُحذف هنا أيضًا — ما لم يُعدَّل عندنا بعد حذفه.
  Future<void> _applyTombstones(SyncMarks marks, LegacyImportResult res) async {
    var removed = 0;
    final rejected = <String, String>{};
    for (final mark in _incoming.values) {
      if (!mark.isDeleted) continue;
      if (!SyncMarks.entities.containsKey(mark.entity)) continue;
      final local = _local[mark.key];
      if (local != null && local.stamp > mark.stamp) continue;
      if (_ignoresTombstone(mark)) {
        _rejectedMarks.add(mark.key);
        continue;
      }
      final why = await _tombstoneRejection(mark);
      if (why != null) {
        _rejectedMarks.add(mark.key);
        rejected[mark.key] = why;
        continue;
      }
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
    if (rejected.isNotEmpty) {
      // صفٌّ واحد للحمولة كلها لا صفٌّ لكل شاهد: حمولةٌ بآلاف الشواهد لا تنفخ
      // السجلَّ المحمي (عالي الخطورة لا يُقلَّم).
      res.warnings.add('رُفض ${rejected.length} حذفًا منقولًا يمسّ حسابًا مميَّزًا أو إعدادًا خاصًّا بالجهاز');
      await AuditRepo(db).log(
        action: 'sync.tombstone_rejected',
        entityType: 'مزامنة',
        summary: 'رُفض ${rejected.length} حذفًا منقولًا: ${rejected.values.take(5).join('، ')}'
            '${rejected.length > 5 ? '…' : ''}',
        details: {'count': rejected.length, 'rows': rejected.keys.take(50).toList()},
        risk: AuditRepo.riskHigh,
        actorEmail: 'sync',
      );
    }
  }

  /// تثبيت الختم الفائز لكل سجل بدل الختم الذي كتبته المحفِّزات لحظة الاستيراد،
  /// حتى يصل الجهازان إلى العلامات نفسها ولا تتأرجح المزامنة التالية.
  Future<void> _settleMarks(SyncMarks marks) async {
    for (final entry in _incoming.entries) {
      // المرفوض يبقى بختمه المحلي، ومفتاح الإعدادات المحلي لا يأخذ ختمَ ما لم
      // يُكتب (صفُّه لا يُستورد أصلًا).
      if (_rejectedMarks.contains(entry.key)) continue;
      if (entry.value.entity == 'app_settings' && SettingsRepo.localOnlyKeys.contains(entry.value.rowId)) continue;
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
