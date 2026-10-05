import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../core/security/password_hash.dart';
import '../../core/security/warehouse_scope.dart';
import '../../domain/access_control.dart';
import 'audit_repo.dart';
import '../../core/error_log.dart';

/// إدارة المستخدمين والأدوار ونطاق المستودعات.
/// كل عمليات هذه الفئة مقصورة على من يملك صلاحية إدارة المستخدمين —
/// الشاشة هي التي تفرض ذلك قبل استدعائها، ولا تُعرض لغيرهم أصلًا.
class UsersRepo {
  UsersRepo(this.db);

  final AppDatabase db;

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
        ));

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
