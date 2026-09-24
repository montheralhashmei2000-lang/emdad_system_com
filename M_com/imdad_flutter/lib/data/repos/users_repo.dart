import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../core/security/pbkdf2.dart';
import '../../domain/access_control.dart';
import 'audit_repo.dart';

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
    } catch (_) {}
    return const [];
  }

  static List<String>? scopeOf(User user) {
    if (user.warehouseScope == 'ALL') return null;
    try {
      final v = jsonDecode(user.warehouseScope);
      if (v is List) return v.map((e) => e.toString()).toList();
    } catch (_) {}
    return null;
  }

  static String scopeLabel(User user) {
    final scope = scopeOf(user);
    if (user.role == 'admin') return 'كل المستودعات (مدير النظام)';
    if (scope == null) return 'كل المستودعات';
    return scope.isEmpty ? 'بدون مستودعات' : scope.join('، ');
  }

  /// صلاحيات مشتقة من قوالب الأدوار المختارة.
  static PermissionMap permissionsForRoles(List<String> roleIds) => AccessControl.merge([
        for (final id in roleIds)
          if (AccessControl.roles[id] != null) AccessControl.roles[id]!.permissions,
      ]);

  Future<String> createUser({
    required String username,
    required String password,
    required String name,
    List<String> roleIds = const [],
    PermissionMap? permissions,
    List<String>? warehouseScope,
    bool isAdmin = false,
    String actorEmail = '',
  }) async {
    final u = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,40}$').hasMatch(u)) {
      throw ArgumentError('اسم المستخدم بالإنجليزية أو الأرقام أو النقاط، 3 أحرف فأكثر');
    }
    if (password.length < 8) {
      throw ArgumentError('كلمة المرور 8 أحرف فأكثر');
    }
    final exists = await (db.select(db.users)..where((t) => t.username.equals(u))).get();
    if (exists.isNotEmpty) throw ArgumentError('اسم المستخدم مستخدم بالفعل');

    final salt = Pbkdf2.newSaltHex();
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
          saltHex: Value(salt),
          hashHex: Value(Pbkdf2.deriveHex(password, salt)),
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
  }) async {
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
    final salt = Pbkdf2.newSaltHex();
    await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(
      saltHex: Value(salt),
      hashHex: Value(Pbkdf2.deriveHex(password, salt)),
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
  Future<bool> deleteUser(String id) async {
    final rows = await db.select(db.users).get();
    final target = rows.where((u) => u.id == id).toList();
    if (target.isEmpty) return false;
    if (target.first.role == 'admin' && rows.where((u) => u.role == 'admin').length <= 1) {
      return false;
    }
    await (db.delete(db.users)..where((t) => t.id.equals(id))).go();
    return true;
  }
}
