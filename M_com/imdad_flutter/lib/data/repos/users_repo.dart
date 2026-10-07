import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../core/security/device_activation.dart';
import '../../core/security/owner_signature.dart';
import '../../core/security/password_hash.dart';
import '../../core/security/warehouse_scope.dart';
import '../../domain/access_control.dart';
import '../../domain/section_block.dart';
import 'audit_repo.dart';
import '../../core/error_log.dart';

/// إدارة المستخدمين والأدوار ونطاق المستودعات.
/// كل عمليات هذه الفئة مقصورة على من يملك صلاحية إدارة المستخدمين —
/// الشاشة هي التي تفرض ذلك قبل استدعائها، ولا تُعرض لغيرهم أصلًا.
class UsersRepo {
  UsersRepo(this.db);

  final AppDatabase db;

  /// كل الحسابات بلا فرز — لشاشات التحليل.
  Future<List<User>> allUsers() => db.select(db.users).get();

  Future<User?> byId(String id) => (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// يعتمد حسابًا معلَّقًا (التوقيع/التدقيق على المستدعي كما كان في الشاشة).
  Future<void> markApproved(String id) =>
      (db.update(db.users)..where((t) => t.id.equals(id))).write(const UsersCompanion(approved: Value(true)));

  Future<List<User>> users() async {
    final rows = await db.select(db.users).get();
    rows.sort((a, b) => a.username.compareTo(b.username));
    return rows;
  }

  static List<String> rolesOf(User user) {
    try {
      final v = jsonDecode(user.roles);
      if (v is List) return v.map((e) => e.toString()).toList();
    } catch (err, stack) {
      ErrorLogger.log('users.rolesJson', err, stack);
    }
    return const [];
  }

  /// نطاق المستودعات: `null` ⇒ كل المستودعات. التالف يُرجع قائمةً فارغة
  /// (فشل مغلق) — انظر [parseWarehouseScope].
  static List<String>? scopeOf(User user) =>
      parseWarehouseScope(user.warehouseScope, source: 'users.scopeJson');

  static String scopeLabel(User user) {
    final scope = scopeOf(user);
    if (UserRole.isAdmin(user.role)) return 'كل المستودعات (${UserRole.label(user.role)})';
    if (scope == null) return 'كل المستودعات';
    return scope.isEmpty ? 'بدون مستودعات' : scope.join('، ');
  }

  /// صلاحيات مشتقة من قوالب الأدوار المختارة.
  static PermissionMap permissionsForRoles(List<String> roleIds) => AccessControl.merge([
        for (final id in roleIds)
          if (AccessControl.roles[id] != null) AccessControl.roles[id]!.permissions,
      ]);

  /// قواعد من يفعل ماذا في إدارة الحسابات — تُطبَّق حين يُمرَّر [actorRole].
  ///
  /// • **المالك:** كل شيء (ما عدا المساس بحساب مالكٍ — يحميه الفحص أدناه).
  /// • **المدير:** ينشئ مستخدمين بدور `user` بقالبٍ جاهز فقط، ويعدّل بياناتهم
  ///   العادية ويفعّلهم. **لا** يمنح دور مدير، **ولا** يعدّل مصفوفة صلاحيات أحد
  ///   ولا نطاقه، **ولا** يعطّل حسابًا، **ولا** يمسّ حساب مديرٍ أو مالك.
  /// • غيرهما: لا شيء.
  ///
  /// `actorRole == null` ⇒ استدعاءٌ داخليٌّ موثوق (تهيئة، ترحيل، اختبارات) لا
  /// يخضع للقواعد. الشاشات تمرّر دور المستخدم الحالي دائمًا.
  static void _requireActor(String? actorRole, {bool owner = false, String why = ''}) {
    if (actorRole == null) return;
    final ok = owner ? UserRole.isOwner(actorRole) : UserRole.isAdmin(actorRole);
    if (!ok) {
      throw ArgumentError(owner ? '✖ هذا الإجراء للمالك وحده${why.isEmpty ? '' : ' — $why'}' : '✖ لا تملك صلاحية إدارة الحسابات');
    }
  }

  Future<String> createUser({
    required String username,
    required String password,
    required String name,
    List<String> roleIds = const [],
    PermissionMap? permissions,
    List<String>? warehouseScope,
    bool isAdmin = false,
    String actorEmail = '',
    String? actorRole,
  }) async {
    _requireActor(actorRole);
    if (actorRole != null && !UserRole.isOwner(actorRole)) {
      // المدير: مستخدمٌ عاديٌّ بقالبٍ جاهز — لا مدير، ولا مصفوفة صلاحياتٍ مخصَّصة، ولا نطاق.
      if (isAdmin) _requireActor(actorRole, owner: true, why: 'منح دور مدير النظام');
      if (permissions != null) _requireActor(actorRole, owner: true, why: 'تخصيص الصلاحيات');
      if (warehouseScope != null) _requireActor(actorRole, owner: true, why: 'تحديد نطاق المستودعات');
      if (roleIds.any((r) => !AccessControl.roles.containsKey(r))) {
        throw ArgumentError('✖ قالب صلاحيات غير معروف');
      }
    }
    final u = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,40}$').hasMatch(u)) {
      throw ArgumentError('اسم المستخدم بالإنجليزية أو الأرقام أو النقاط، 3 أحرف فأكثر');
    }
    if (password.length < 8) {
      throw ArgumentError('كلمة المرور 8 أحرف فأكثر');
    }
    final exists = await (db.select(db.users)..where((t) => t.username.equals(u))).get();
    if (exists.isNotEmpty) throw ArgumentError('اسم المستخدم مستخدم بالفعل');

    final ph = await PasswordHash.create(password);
    final id = 'local-$u';
    await db.into(db.users).insert(UsersCompanion.insert(
          id: id,
          username: u,
          name: Value(name.trim().isEmpty ? u : name.trim()),
          email: Value('$u@imdad.local'),
          role: Value(isAdmin ? 'admin' : 'user'),
          roles: Value(jsonEncode(roleIds)),
          permissions: Value(jsonEncode(permissions ?? permissionsForRoles(roleIds))),
          warehouseScope: Value(warehouseScope == null ? 'ALL' : jsonEncode(warehouseScope)),
          saltHex: Value(ph.saltHex),
          hashHex: Value(ph.hashHex),
          iterations: Value(ph.iterations),
          // مديرٌ جديد يُختم بثوانٍ كاملة ليُوقَّع دورُه (بصمة التوقيع تضمّ `updatedAt`).
          updatedAt: isAdmin
              ? Value(DateTime.fromMillisecondsSinceEpoch(OwnerSignature.seconds(DateTime.now()) * 1000))
              : const Value.absent(),
        ));
    if (isAdmin) await resign(id, actorEmail: actorEmail);

    await AuditRepo(db).log(
      action: 'user.create',
      entityType: 'مستخدم',
      summary: 'إنشاء حساب «$u»${isAdmin ? ' بصلاحيات مدير نظام' : ''}',
      details: {'username': u, 'roles': roleIds, 'admin': isAdmin, 'scope': warehouseScope},
      risk: isAdmin ? AuditRepo.riskHigh : AuditRepo.riskNormal,
      actorEmail: actorEmail,
    );
    return id;
  }

  Future<void> updateUser({
    required String id,
    String? name,
    List<String>? roleIds,
    PermissionMap? permissions,
    List<String>? warehouseScope,
    bool? allWarehouses,
    bool? isAdmin,
    bool? active,
    String actorEmail = '',
    String? actorRole,
  }) async {
    _requireActor(actorRole);
    // حساب المالك محميّ: لا يتغيّر دوره ولا يُعطَّل من هذا المسار.
    final target = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (target != null && UserRole.isOwner(target.role)) {
      if (isAdmin != null) throw ArgumentError('✖ حساب المالك لا يتغيّر دوره');
      if (active == false) throw ArgumentError('✖ حساب المالك لا يُعطَّل');
    }
    if (actorRole != null && !UserRole.isOwner(actorRole)) {
      // المدير لا يمسّ حساب مديرٍ أو مالك، ولا يرفع ولا يعدّل صلاحيات ولا يعطّل.
      if (target != null && UserRole.isAdmin(target.role)) {
        throw ArgumentError('✖ لا يعدّل حسابَ مديرٍ أو مالكٍ إلا المالك');
      }
      if (isAdmin != null) _requireActor(actorRole, owner: true, why: 'تغيير دور الحساب');
      if (permissions != null) _requireActor(actorRole, owner: true, why: 'تعديل مصفوفة الصلاحيات');
      if (allWarehouses != null || warehouseScope != null) {
        _requireActor(actorRole, owner: true, why: 'تعديل نطاق المستودعات');
      }
      if (active == false) _requireActor(actorRole, owner: true, why: 'تعطيل الحسابات');
    }
    await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(
      name: name == null ? const Value.absent() : Value(name),
      roles: roleIds == null ? const Value.absent() : Value(jsonEncode(roleIds)),
      permissions: permissions == null ? const Value.absent() : Value(jsonEncode(permissions)),
      warehouseScope: allWarehouses == true
          ? const Value('ALL')
          : warehouseScope == null
              ? const Value.absent()
              : Value(jsonEncode(warehouseScope)),
      role: isAdmin == null ? const Value.absent() : Value(isAdmin ? 'admin' : 'user'),
      active: active == null ? const Value.absent() : Value(active),
      updatedAt: Value(DateTime.now()),
    ));

    // `updatedAt` تغيّر: توقيعات هذا الحساب (إن وُجدت ومفتاح المالك هنا) تُجدَّد، وإلا
    // سقطت بأول تعديل فلم يقبله جهازٌ جديد بالمزامنة.
    await resign(id, actorEmail: actorEmail);

    await AuditRepo(db).log(
      action: 'user.update',
      entityType: 'مستخدم',
      summary: 'تعديل صلاحيات أو نطاق الحساب $id',
      details: {
        'roles': roleIds,
        'admin': isAdmin,
        'allWarehouses': allWarehouses,
        'scope': warehouseScope,
        'active': active,
      },
      risk: isAdmin == true ? AuditRepo.riskHigh : AuditRepo.riskNormal,
      actorEmail: actorEmail,
    );
  }

  Future<void> resetPassword({required String id, required String password}) async {
    if (password.length < 8) throw ArgumentError('كلمة المرور 8 أحرف فأكثر');
    // الأعمدة الثلاثة معًا: لو بقي `iterations` القديم (حساب مُرحَّل بعدد مختلف)
    // لما طابقت البصمة الجديدة أبدًا وأُغلق الحساب بعد إعادة التعيين.
    final ph = await PasswordHash.create(password);
    await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(
      saltHex: Value(ph.saltHex),
      hashHex: Value(ph.hashHex),
      iterations: Value(ph.iterations),
      failedAttempts: const Value(0),
      lockedUntil: const Value(null),
      updatedAt: Value(DateTime.now()),
    ));
    await resign(id);
  }

  /// يجدّد توقيعات المالك على حسابٍ بعد أن تغيّر `updatedAt` (وهو جزءٌ من بصمة كل
  /// توقيع): توقيع الدور `r` إن كان الحساب مديرًا/مالكًا، وتوقيع الأقسام `s` إن كان
  /// عليه توقيعٌ سابق. **لا يمسّ `updatedAt`** (تغييره يُبطل ما وُقِّع للتوّ).
  ///
  /// لا يفعل شيئًا بلا مفتاح المالك الخاص على هذا الجهاز. يعيد `true` إن وُقِّع شيء.
  Future<bool> resign(String id, {DeviceActivation? activation, String actorEmail = ''}) async {
    final act = activation ?? DeviceActivation(db);
    if (!await act.canIssue()) return false;
    final row = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
    final stamp = row?.updatedAt;
    if (row == null || stamp == null) return false;

    final sec = OwnerSignature.seconds(stamp);
    final sigs = OwnerSignature.parse(row.ownerSig);
    final purposes = <String>[];

    if (OwnerSignature.rank(row.role) > 0) {
      final r = await OwnerSignature.signRole(act, userId: id, role: row.role, updatedAtSec: sec);
      if (r != null) {
        sigs[OwnerSignature.roleKey] = r;
        purposes.add('role');
      }
    }
    if (OwnerSignature.rank(row.role) > 0) {
      final c = await OwnerSignature.signCreds(
        act,
        userId: id,
        role: row.role,
        saltHex: row.saltHex,
        hashHex: row.hashHex,
        permissions: row.permissions,
        warehouseScope: row.warehouseScope,
        active: row.active,
        approved: row.approved,
        updatedAtSec: sec,
      );
      if (c != null) {
        sigs[OwnerSignature.credsKey] = c;
        purposes.add('creds');
      }
    }
    // توقيع الدور `r` لا يُسحب من أي صف أبدًا (حتى لو نزل الدور): السحب يفقد الأثر.
    if (sigs.containsKey(OwnerSignature.sectionsKey)) {
      final s = await OwnerSignature.signSections(act, userId: id, blockedJson: row.sectionBlocked, updatedAtSec: sec);
      if (s != null) {
        sigs[OwnerSignature.sectionsKey] = s;
        purposes.add('sections');
      }
    }
    final encoded = OwnerSignature.encode(sigs);
    if (encoded == row.ownerSig) return false;

    await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(ownerSig: Value(encoded)));
    if (purposes.isNotEmpty) {
      await AuditRepo(db).log(
        action: 'sys.sign.used',
        entityType: 'مستخدم',
        summary: 'استُعمل مفتاح المالك الخاص لتجديد توقيع «${row.username}» (${purposes.join('، ')})',
        details: {'purpose': purposes, 'userId': id},
        risk: AuditRepo.riskHigh,
        actorEmail: actorEmail,
      );
    }
    return true;
  }

  /// يوقّع كل المديرين والمالكين الحاليين بمفتاح المالك (لمرةٍ بعد الترقية إلى v25:
  /// حساباتهم قبلها بلا توقيع فلا يقبلها جهازٌ جديد بالمزامنة). يعيد عدد من وُقِّع.
  Future<int> signPrivilegedUsers({String? actorRole, String actorEmail = '', DeviceActivation? activation}) async {
    _requireActor(actorRole, owner: true, why: 'توقيع المديرين');
    var n = 0;
    for (final u in await db.select(db.users).get()) {
      if (OwnerSignature.rank(u.role) == 0) continue;
      // `updatedAt` الفارغ (حسابٌ قديم) يُختم الآن: لا توقيع على لا شيء.
      if (u.updatedAt == null) {
        await (db.update(db.users)..where((t) => t.id.equals(u.id))).write(UsersCompanion(
          updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(OwnerSignature.seconds(DateTime.now()) * 1000)),
        ));
      }
      if (await resign(u.id, activation: activation, actorEmail: actorEmail)) n++;
    }
    return n;
  }

  /// يضبط الأقسام المحجوبة عن مستخدم — **للمالك وحده**، ولا يُحجب عن المالك شيء.
  ///
  /// • **الإضافة** (حجبُ قسمٍ جديد) بلا توقيع: تضييقٌ لا يضرّ لو أُسيء استعماله.
  /// • **الإلغاء** (فكُّ قسم) يُوقَّع بمفتاح المالك الخاص إن كان على هذا الجهاز،
  ///   فتقبله الأجهزة الأخرى بالمزامنة. بلا المفتاح يُفكّ **محليًّا** فقط
  ///   ([SectionBlockResult.unsignedUnblock]) ولا ينتشر حتى يُوقَّع من جهاز الإدارة.
  ///   التغيير المحلي على هذا الجهاز نافذٌ في الحالين.
  ///
  /// كل تغييرٍ يُسجَّل بخطورة عالية، وكل استخدامٍ للمفتاح الخاص يُسجَّل `sys.sign.used`.
  Future<SectionBlockResult> setSectionBlocked({
    required String id,
    required Set<String> blocked,
    String? actorRole,
    String actorEmail = '',
    DeviceActivation? activation,
  }) async {
    _requireActor(actorRole, owner: true, why: 'حجب الأقسام');
    final target = await (db.select(db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (target == null) throw ArgumentError('✖ المستخدم غير موجود');
    if (UserRole.isOwner(target.role)) throw ArgumentError('✖ لا يُحجب عن المالك أي قسم');

    final before = SectionBlock.parse(target.sectionBlocked);
    final next = {for (final s in blocked) if (SectionBlock.all.contains(s)) s};
    final added = next.difference(before);
    final removed = before.difference(next);
    if (added.isEmpty && removed.isEmpty) return const SectionBlockResult();

    final nextJson = SectionBlock.encode(next);
    // بثوانٍ كاملة: هي دقة تخزين `updatedAt`، فيتطابق ما وُقِّع عليه مع ما يُقرأ.
    final stamp = DateTime.fromMillisecondsSinceEpoch(OwnerSignature.seconds(DateTime.now()) * 1000);

    // التوقيع القديم غطّى محتوىً قديمًا: يسقط. توقيع الدور (`r`) لا علاقة له.
    final sigs = OwnerSignature.parse(target.ownerSig)..remove(OwnerSignature.sectionsKey);
    var signed = false;
    if (removed.isNotEmpty) {
      final sig = await OwnerSignature.signSections(
        activation ?? DeviceActivation(db),
        userId: id,
        blockedJson: nextJson,
        updatedAtSec: OwnerSignature.seconds(stamp),
      );
      if (sig != null) {
        sigs[OwnerSignature.sectionsKey] = sig;
        signed = true;
      }
    }

    await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(
      sectionBlocked: Value(nextJson),
      ownerSig: Value(OwnerSignature.encode(sigs)),
      updatedAt: Value(stamp),
    ));

    final audit = AuditRepo(db);
    if (signed) {
      await audit.log(
        action: 'sys.sign.used',
        entityType: 'مستخدم',
        summary: 'استُعمل مفتاح المالك الخاص لتوقيع فكّ حجب أقسام «${target.username}»',
        details: {'purpose': 'sections', 'userId': id, 'removed': removed.toList()..sort()},
        risk: AuditRepo.riskHigh,
        actorEmail: actorEmail,
      );
    }
    await audit.log(
      action: 'user.section_blocked.changed',
      entityType: 'مستخدم',
      summary: 'تغيير الأقسام المحجوبة عن «${target.username}»'
          '${added.isEmpty ? '' : ' — حُجب: ${added.map((s) => SectionBlock.labels[s] ?? s).join('، ')}'}'
          '${removed.isEmpty ? '' : ' — فُكّ: ${removed.map((s) => SectionBlock.labels[s] ?? s).join('، ')}'}',
      details: {
        'userId': id,
        'added': added.toList()..sort(),
        'removed': removed.toList()..sort(),
        'signed': signed,
        'unsignedUnblock': removed.isNotEmpty && !signed,
      },
      risk: AuditRepo.riskHigh,
      actorEmail: actorEmail,
    );
    // الدور تغيّر ختمه الزمني مع هذه الكتابة: يُجدَّد توقيعه (إلا إن وُقِّع للتوّ).
    if (!signed) await resign(id, activation: activation, actorEmail: actorEmail);
    return SectionBlockResult(
      changed: true,
      added: added,
      removed: removed,
      signed: signed,
      unsignedUnblock: removed.isNotEmpty && !signed,
    );
  }

  /// فك القفل بعد تجاوز محاولات الدخول.
  Future<void> unlock(String id) =>
      (db.update(db.users)..where((t) => t.id.equals(id))).write(const UsersCompanion(
        failedAttempts: Value(0),
        lockedUntil: Value(null),
      ));

  /// لا يجوز حذف آخر مدير نظام حتى لا يُغلق النظام على نفسه.
  Future<bool> deleteUser(String id, {String? actorRole}) async {
    _requireActor(actorRole, owner: true, why: 'حذف المستخدمين');
    final rows = await db.select(db.users).get();
    final target = rows.where((u) => u.id == id).toList();
    if (target.isEmpty) return false;
    // المالك لا يُحذف أبدًا، وآخر مدير (أو مالك) لا يُحذف حتى لا يُغلق النظام على نفسه.
    if (UserRole.isOwner(target.first.role)) return false;
    if (UserRole.isAdmin(target.first.role) && rows.where((u) => UserRole.isAdmin(u.role)).length <= 1) {
      return false;
    }
    await (db.delete(db.users)..where((t) => t.id.equals(id))).go();
    return true;
  }
}

/// نتيجة [UsersRepo.setSectionBlocked].
class SectionBlockResult {
  const SectionBlockResult({
    this.changed = false,
    this.added = const {},
    this.removed = const {},
    this.signed = false,
    this.unsignedUnblock = false,
  });

  final bool changed;
  final Set<String> added;
  final Set<String> removed;

  /// وُقِّع فكُّ الحجب بمفتاح المالك (فينتشر بالمزامنة).
  final bool signed;

  /// فُكّ حجبٌ **محليًّا** بلا توقيع: لن ينتشر للأجهزة الأخرى حتى يُوقَّع من جهاز الإدارة.
  final bool unsignedUnblock;
}
