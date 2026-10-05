import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../domain/access_control.dart';
import '../../domain/perm_catalog.dart';
import '../ui/imd_widgets.dart';
import 'auth_service.dart';

/// مساعدات الصلاحيات في الشاشات: فحص إذنٍ واحد، وإدارة صفحة، وحراسة وصول.
class Perm {
  Perm(this._auth);
  final AuthService _auth;

  /// أسماء الصفحات كما تظهر في رسائل الصلاحية — من [PermCatalog] (المصدر الوحيد)
  /// مضافًا إليها أسماء بنود القائمة التي تتبع صلاحية غيرها.
  static final Map<String, String> labels = {
    ...PermCatalog.aliasLabels,
    ...PermCatalog.labels,
  };

  static Perm of(BuildContext context) => Perm(context.read<AuthService>());

  /// `can()` — مدير النظام.
  /// مدير أو مالك: كل صلاحيات الصفحات.
  bool get admin => UserRole.isAdmin(_auth.currentUser?.role);

  /// المالك وحده: يملك `sys.*`.
  bool get owner => UserRole.isOwner(_auth.currentUser?.role);

  /// صلاحية نظامٍ خاصة (`sys.*`) — للمالك وحده.
  bool sys(String key) => owner;

  /// حارس `sys.*`: يرفض بإشعارٍ يسمّي الصلاحية.
  bool guardSys(BuildContext context, String key) {
    if (sys(key)) return true;
    showImdToast(context, '✖ هذا الإجراء للمالك وحده — ${SysPerm.labels[key] ?? key}', error: true);
    return false;
  }

  String get email => _auth.currentUser?.email ?? '';

  /// اسم المستخدم الحالي للعرض (الاسم، وإلا اسم الدخول).
  String get displayName {
    final u = _auth.currentUser;
    if (u == null) return '';
    return u.name.trim().isNotEmpty ? u.name.trim() : u.username;
  }

  static Map? _pageMap(Object? v) => v is Map ? v : null;

  bool has(String page, [String action = PermAction.view]) {
    final u = _auth.currentUser;
    if (u == null) return false;
    if (SysPerm.isSys(page)) return owner;
    if (admin) return true;
    return AccessControl.allows(_pageMap(_auth.permissionsOf(u)[page]), action);
  }

  /// `pageManage(page)`
  bool manage(String page) =>
      has(page, PermAction.create) ||
      has(page, PermAction.edit) ||
      has(page, PermAction.delete) ||
      has(page, PermAction.approve);

  /// `can() || pageManage(page)` — الشرط المتكرر لإظهار أزرار الإدارة.
  bool writable(String page) => admin || manage(page);

  /// نطاق المستودعات: null ⇒ كل المستودعات (`scopeOf()==='ALL'`).
  List<String>? get scope {
    final u = _auth.currentUser;
    if (u == null) return const [];
    return _auth.warehouseScopeOf(u);
  }

  /// `canWh(name)`
  bool canWh(String warehouse) {
    final s = scope;
    return s == null || warehouse.isEmpty || s.contains(warehouse);
  }

  /// `blockMsg(wh)` في access-control.js
  static String scopeBlock(String warehouse) =>
      '✖ المستودع «$warehouse» خارج نطاق صلاحياتك — تواصل مع مدير النظام';

  /// `guardPerm(page, action)`
  bool guard(BuildContext context, String page,
      [String action = PermAction.edit]) {
    if (has(page, action)) return true;
    showImdToast(
        context, '✖ لا تملك صلاحية: ${labels[page] ?? page} — $action');
    return false;
  }
}
