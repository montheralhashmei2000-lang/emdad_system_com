part of '../legacy_import.dart';

/// الحسابات: حارس رفض الاستقبال (`_userRejection`) واستيراد الصفوف.
/// كلا الموضعين منقولٌ حرفيًّا بشروطه وترتيبها كما كانت.
///
/// نقلٌ حرفيّ من `LegacyImporter` — خليطٌ في المكتبة نفسها، فواجهة
/// المستورد العامة (`importJson`/`importFile`) لم تتغيّر.
mixin _LegacyUsers on _LegacyBase {
  // ───────── الجداول ─────────
  /// سبب رفض استقبال حسابٍ، أو `null` إن قُبل.
  ///
  /// **قاعدتان، كلتاهما تُقاس بالمحلي لا بالوارد وحده:**
  ///  • **رفع الدور** إلى `admin`/`owner` (حسابٌ جديد، أو رتبةٌ أعلى من المحلية) يلزمه
  ///    توقيع المالك `r` على `userId|role|updatedAt`. خفضُ الدور أو بقاؤه لا يلزمه.
  ///  • **فكّ حجبٍ** (قسمٌ محجوبٌ محليًّا غاب من الوارد) يلزمه توقيع `s` على
  ///    `userId|section_blocked|updatedAt`. إضافة حجب لا تلزمه.
  ///
  /// وبلا مفتاح مالكٍ مضبوط (وضع تطوير) لا تُفرض القاعدتان — كحال تفعيل الأجهزة.
  ({String kind, String reason})? _userRejection(Map<String, dynamic> u, User? local, Iterable<User> existing) {
    if (_ownerKey.isEmpty) return null;
    final id = _id(u);
    final role = _s(u, 'role', 'user');
    final updatedSec = u['updatedAt'] is num ? (u['updatedAt'] as num).toInt() : null;
    final sigs = OwnerSignature.parse(u['ownerSig'] is String ? u['ownerSig'] as String : null);
    final inRank = OwnerSignature.rank(role);
    final localRank = OwnerSignature.rank(local?.role);

    // **انتزاع اسم الدخول:** حسابٌ عاديٌّ وارد يحمل اسم حسابٍ مميَّز قائم بمعرّفٍ
    // آخر. `login` يطابق الاسم بلا حساسية للحالة ويفضّل `local-` ثم الأحدث تعديلًا
    // (والختم بيد المرسِل)، فيُصادَق الدخيلُ بكلمة مرورٍ يعرفها ويُردّ المدير
    // الحقيقي بـ«كلمة مرور خاطئة». المميَّز الوارد بتوقيعٍ صحيح لا يُمسّ هنا:
    // يحرسه شرط الرفع أدناه، والتكرار الشرعي (جهازٌ هيّأ مديره محليًّا) يبقى ممكنًا.
    if (inRank == 0) {
      final name = _s(u, 'username', _s(u, 'email').split('@').first).toLowerCase();
      final clash = existing.any(
          (x) => x.id != id && OwnerSignature.rank(x.role) > 0 && x.username.toLowerCase() == name);
      if (name.isNotEmpty && clash) {
        return (kind: 'username', reason: 'حسابٌ عاديٌّ باسم حسابٍ مميَّز قائم («$name») بمعرّفٍ آخر');
      }
    }

    // **صفٌّ موقَّعٌ أقدم من المحلي يُرفض (H-3 في تدقيق 2026-10-10).** التواقيع
    // تربط القيم بختم `updatedAt` الخاص بها، ولا شيء كان يشترط أن يكون الوارد
    // أحدث: فجهازٌ مقترن يعيد إرسال صفّ مديرٍ قديم (قبل خفضه أو تعطيله أو تغيير
    // كلمة مروره) بتوقيعه الأصلي الصحيح، وبعلامة دمجٍ من المستقبل (بيده)، فتعود
    // الصلاحية المسحوبة أو كلمة المرور المسرَّبة — ولا يستطيع المالك نقضها.
    // والختم المقارَن ختمُ الموقِّع نفسه (`updatedAt`)، لا علامة الدمج.
    final localSec = local?.updatedAt == null ? null : OwnerSignature.seconds(local!.updatedAt!);
    final vouched = inRank > 0 || localRank > 0 || (local != null && OwnerSignature.parse(local.ownerSig).isNotEmpty);
    if (vouched && localSec != null && (updatedSec == null || updatedSec < localSec)) {
      return (
        kind: 'rollback',
        reason: 'نسخةٌ أقدم من المحلية لحسابٍ موقَّع (${updatedSec ?? '—'} < $localSec) — إعادةُ صفٍّ قديم',
      );
    }
    // وإحياءُ حسابٍ مميَّز حُذف هنا بصفٍّ وُقِّع قبل حذفه: الصف المحلي غائب، والشاهد يحمل وقت الحذف.
    if (local == null && inRank > 0) {
      final tomb = _local['users/$id'];
      if (tomb != null && tomb.isDeleted && (updatedSec == null || updatedSec * 1000 <= tomb.deletedAt!)) {
        return (kind: 'rollback', reason: 'إحياءُ حسابٍ مميَّز محذوف بصفٍّ وُقِّع قبل حذفه');
      }
    }

    // تغيير الدور يلزمه توقيع `r` على الدور الوارد: **رفعًا** في أي حساب، و**خفضًا**
    // في حسابٍ مميَّز محليًّا. كان الخفض حرًّا، فيُخفض المالك إلى `user` ومعه تُستبدل
    // بصمته وصلاحياته في الصف نفسه بلا توقيع — لأن حارس `c` أدناه كان يشترط أن يبقى
    // الدور الوارد مميَّزًا.
    if (inRank > localRank || (localRank > 0 && inRank < localRank)) {
      final ok = updatedSec != null &&
          OwnerSignature.verifyRole(
            sigB64: sigs[OwnerSignature.roleKey] ?? '',
            userId: id,
            role: role,
            updatedAtSec: updatedSec,
            publicKey: _ownerKey,
          );
      if (!ok) {
        return inRank > localRank
            ? (kind: 'role', reason: 'رفع الدور إلى «$role» بلا توقيع مالكٍ صحيح')
            : (kind: 'role', reason: 'خفض حسابٍ مميَّز إلى «$role» بلا توقيع مالكٍ صحيح');
      }
    }

    // **حسابٌ مميَّز محليًّا** (مدير/مالك)، أيًّا كان الدور الوارد: أي تغيير في بصمة
    // كلمة المرور أو الصلاحيات أو النطاق أو التفعيل يلزمه توقيع المالك `c` على القيم
    // الواردة نفسها. وإلا استبدل جهازٌ مقترن هاش المدير بهاشٍ يعرفه فدخل باسمه.
    if (local != null && localRank > 0) {
      // بصمةٌ غائبة أو فارغة لا تُكتب (انظر `_importUsers`): تبقى القائمة محليًّا.
      final hasSecret = _s(u, 'saltHex').isNotEmpty && _s(u, 'hashHex').isNotEmpty;
      final inSalt = hasSecret ? _s(u, 'saltHex') : local.saltHex;
      final inHash = hasSecret ? _s(u, 'hashHex') : local.hashHex;
      final inPerms = u.containsKey('permissions') ? _json(u['permissions'], '{}') : local.permissions;
      final inScope = u.containsKey('warehouseScope')
          ? (u['warehouseScope'] is List ? _json(u['warehouseScope']) : _s(u, 'warehouseScope', 'ALL'))
          : local.warehouseScope;
      final inActive = u.containsKey('active') ? _b(u, 'active', true) : local.active;
      final inApproved = u.containsKey('approved') ? _b(u, 'approved', true) : local.approved;
      final changed = inSalt != local.saltHex ||
          inHash != local.hashHex ||
          inPerms != local.permissions ||
          inScope != local.warehouseScope ||
          inActive != local.active ||
          inApproved != local.approved;
      if (changed) {
        final ok = updatedSec != null &&
            OwnerSignature.verifyCreds(
              sigB64: sigs[OwnerSignature.credsKey] ?? '',
              userId: id,
              role: role,
              saltHex: inSalt,
              hashHex: inHash,
              permissions: inPerms,
              warehouseScope: inScope,
              active: inActive,
              approved: inApproved,
              updatedAtSec: updatedSec,
              publicKey: _ownerKey,
            );
        if (!ok) return (kind: 'credentials', reason: 'تغيير بيانات دخول أو صلاحيات حساب مدير/مالك بلا توقيع مالكٍ صحيح');
      }
    }

    // غياب الحقل (نظيرٌ أقدم) ليس فكًّا: لا يمسّ حجبًا قائمًا أصلًا (يُترك الحقل).
    if (u['sectionBlocked'] is String) {
      final incomingJson = u['sectionBlocked'] as String;
      final localSet = SectionBlock.parse(local?.sectionBlocked);
      final removed = localSet.difference(SectionBlock.parse(incomingJson));
      if (removed.isNotEmpty) {
        final ok = updatedSec != null &&
            OwnerSignature.verifySections(
              sigB64: sigs[OwnerSignature.sectionsKey] ?? '',
              userId: id,
              blockedJson: incomingJson,
              updatedAtSec: updatedSec,
              publicKey: _ownerKey,
            );
        if (!ok) return (kind: 'unblock', reason: 'فكّ حجب (${(removed.toList()..sort()).join('، ')}) بلا توقيع مالكٍ صحيح');
      }
    }
    return null;
  }

  Future<void> _importUsers(Object? raw, LegacyImportResult res, {required bool trusted}) async {
    final rows = _rows(raw);
    var passwordless = 0;
    final existing = {for (final x in await db.select(db.users).get()) x.id: x};
    for (final u in rows) {
      if (!_accept('users', _id(u))) {
        res.usersSkipped++;
        continue;
      }

      final local = existing[_id(u)];
      final rejection = trusted ? null : _userRejection(u, local, existing.values);
      if (rejection != null) {
        // علامة الصف المرفوض لا تُثبَّت (`_settleMarks`): لو أخذ الصفُّ المحلي ختمَ
        // الوارد لبدا أحدثَ مما هو، فيُدهس به تعديلٌ أحدث على جهازٍ ثالث.
        _rejectedMarks.add('users/${_id(u)}');
        final username = _s(u, 'username', _s(u, 'email').split('@').first);
        res.rejectedUsers.add(RejectedUser(id: _id(u), username: username, kind: rejection.kind, reason: rejection.reason));
        await AuditRepo(db).log(
          action: 'sync.role_rejected',
          entityType: 'مستخدم',
          summary: 'رُفض استقبال «$username»: ${rejection.reason}',
          details: {
            'userId': _id(u),
            'username': username,
            'kind': rejection.kind,
            'incomingRole': _s(u, 'role', 'user'),
            'localRole': local?.role,
            'reason': rejection.reason,
          },
          risk: AuditRepo.riskHigh,
          actorEmail: 'sync',
        );
        continue;
      }

      // **كلمة المرور تُنقل مع الحساب.** الملح والبصمة يخرجان في التصدير، وكان
      // الاستيراد لا يقرؤهما — فيصل الحساب إلى الفرع ببصمة فارغة، ويستحيل
      // الدخول به مديرًا كان أو غيره. الحساب بلا بصمته ليس حسابًا.
      final salt = _s(u, 'saltHex');
      final hash = _s(u, 'hashHex');
      final hasSecret = salt.isNotEmpty && hash.isNotEmpty;
      if (!hasSecret) passwordless++;

      await db.into(db.users).insertOnConflictUpdate(UsersCompanion.insert(
            id: _id(u),
            username: _s(u, 'username', _s(u, 'email').split('@').first),
            name: Value(_s(u, 'name')),
            email: Value(_s(u, 'email')),
            role: Value(_s(u, 'role', 'user')),
            roles: Value(_json(u['roles'])),
            permissions: Value(_json(u['permissions'], '{}')),
            warehouseScope: Value(u['warehouseScope'] is List
                ? _json(u['warehouseScope'])
                : _s(u, 'warehouseScope', 'ALL')),
            // حمولةٌ بلا بصمة تترك الأعمدة الثلاثة **غائبة** لا فارغة: الغياب
            // يُبقي كلمة المرور القائمة على هذا الجهاز، والفراغ يمحوها. ونسخة
            // ويب قديمة بلا بصمات كانت ستمحو كلمات المرور عند كل استيراد.
            saltHex: hasSecret ? Value(salt) : const Value.absent(),
            hashHex: hasSecret ? Value(hash) : const Value.absent(),
            iterations: hasSecret
                ? Value(_safeIterations(_i(u, 'iterations', Pbkdf2.legacyIterations)))
                : const Value.absent(),
            active: Value(_b(u, 'active', true)),
            approved: Value(_b(u, 'approved', true)),
            createdAt: Value(_created(u)),
            // الحقول الأمنية الجديدة: الغياب (نظيرٌ أقدم) يترك القائم لا يمحوه.
            sectionBlocked: u['sectionBlocked'] is String ? Value(u['sectionBlocked'] as String) : const Value.absent(),
            ownerSig: u['ownerSig'] is String && (u['ownerSig'] as String).isNotEmpty
                ? Value(u['ownerSig'] as String)
                : const Value.absent(),
            updatedAt: u['updatedAt'] is num
                ? Value(DateTime.fromMillisecondsSinceEpoch((u['updatedAt'] as num).toInt() * 1000))
                : const Value.absent(),
          ));
    }
    _count(res, 'users', rows.length);
    if (passwordless > 0) {
      res.warnings
          .add('$passwordless حسابًا وصل بلا كلمة مرور (تصدير قديم لا يحمل '
              'الملح والبصمة) — يُعيّنها مدير النظام من شاشة المستخدمين.');
    }
  }
}
