/// الأدوار ونطاق المستودعات — نقل مطابق لـ access-control.js.
/// • قوالب أدوار جاهزة تُجمع لمستخدم واحد (مدخل بيانات، أمين مخزن، ركن إمداد، مدير مكتب، مطّلع).
/// • نطاق المستودعات: كل المستودعات أو قائمة محددة، ويُطبَّق على الإدخال والسجلات والتقارير والأرصدة.
/// • مدير النظام (role = admin) يملك كل الصلاحيات ولا يخضع للنطاق.
library;

class PermAction {
  static const String view = 'view';
  static const String create = 'create';
  static const String edit = 'edit';
  static const String delete = 'delete';
  static const String approve = 'approve';
  static const String print = 'print';
  static const String export = 'export';
}

/// صلاحيات على شكل: { 'receive': {'view': true, 'create': true}, ... }
typedef PermissionMap = Map<String, Map<String, bool>>;

class RoleTemplate {
  const RoleTemplate({
    required this.id,
    required this.label,
    required this.description,
    required this.permissions,
  });

  final String id;
  final String label;
  final String description;
  final PermissionMap permissions;
}

class AccessControl {
  static const List<String> basicPages = [
    'dashboard', 'items', 'suppliers', 'units', 'stores', 'kitchens',
  ];
  static const List<String> opsPages = ['receive', 'issue', 'transfer', 'returns'];

  static PermissionMap grant(List<String> pages, List<String> actions) {
    final out = <String, Map<String, bool>>{};
    for (final p in pages) {
      out[p] = {for (final a in actions) a: true};
    }
    return out;
  }

  static PermissionMap merge(List<PermissionMap> maps) {
    final out = <String, Map<String, bool>>{};
    for (final m in maps) {
      m.forEach((page, actions) {
        final target = out.putIfAbsent(page, () => <String, bool>{});
        actions.forEach((action, allowed) {
          if (allowed) target[action] = true;
        });
      });
    }
    return out;
  }

  static final Map<String, RoleTemplate> roles = {
    'data_entry': RoleTemplate(
      id: 'data_entry',
      label: 'مدخل بيانات',
      description: 'إدخال السندات والتغذية وسجل التشغيل في مستودعات نطاقه، دون اعتماد أو حذف',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(opsPages, [PermAction.view, PermAction.create]),
        grant(['feeding', 'kitchenLog'], [PermAction.view, PermAction.create, PermAction.edit]),
        grant(['balances', 'pendingOrders'], [PermAction.view]),
        grant(['documents'], [PermAction.view]),
        grant(['stocktake'], [PermAction.view, PermAction.edit]),
      ]),
    ),
    'storekeeper': RoleTemplate(
      id: 'storekeeper',
      label: 'أمين مخزن',
      description: 'الاستلام والصرف والتحويل والمرتجعات والجرد واعتمادها وطباعتها في مستودعات نطاقه',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(opsPages, [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.approve, PermAction.print,
        ]),
        grant(['pendingOrders'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['opening'], [PermAction.view, PermAction.create, PermAction.print]),
        grant(['balances'], [PermAction.view, PermAction.print, PermAction.export]),
        grant(['stocktake'], [PermAction.view, PermAction.create, PermAction.edit, PermAction.print]),
        grant(['reports'], [PermAction.view, PermAction.print]),
        grant(['documents'], [PermAction.view, PermAction.print, PermAction.edit]),
      ]),
    ),
    'supply_officer': RoleTemplate(
      id: 'supply_officer',
      label: 'ركن إمداد',
      description: 'التخطيط والتغذية والاستحقاقات وأوامر الصرف ومتابعة الأرصدة والتقارير',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(['units', 'kitchens'], [PermAction.view, PermAction.create, PermAction.edit]),
        grant(opsPages, [PermAction.view, PermAction.print]),
        grant(['issue'], [PermAction.view, PermAction.create, PermAction.approve, PermAction.print]),
        grant(['pendingOrders'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['feeding', 'kitchenLog'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.print, PermAction.export,
        ]),
        grant(['ratios'], [PermAction.view, PermAction.edit, PermAction.print, PermAction.export]),
        grant(['balances', 'reports'], [PermAction.view, PermAction.print, PermAction.export]),
        grant(['stocktake'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['documents'], [PermAction.view, PermAction.print]),
      ]),
    ),
    'office_manager': RoleTemplate(
      id: 'office_manager',
      label: 'مدير مكتب',
      description: 'اطلاع شامل وطباعة وتصدير واعتماد، دون إدخال أو تعديل أو حذف',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(opsPages, [PermAction.view, PermAction.print]),
        grant(['pendingOrders'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['feeding', 'kitchenLog', 'ratios'], [
          PermAction.view, PermAction.print, PermAction.export,
        ]),
        grant(['balances', 'reports', 'auditTrail', 'executiveCmd'], [
          PermAction.view, PermAction.print, PermAction.export,
        ]),
        grant(['stocktake'], [
          PermAction.view, PermAction.approve, PermAction.print, PermAction.export,
        ]),
        grant(['sensitiveOps'], [PermAction.view]),
        grant(['documents'], [PermAction.view, PermAction.print]),
      ]),
    ),
    'viewer': RoleTemplate(
      id: 'viewer',
      label: 'مطّلع',
      description: 'مشاهدة البيانات والأرصدة والتقارير فقط',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(opsPages, [PermAction.view]),
        grant(['balances', 'reports', 'documents', 'stocktake'], [PermAction.view]),
      ]),
    ),
  };

  /// صلاحيات مجموعة أدوار مجتمعة.
  static PermissionMap permissionsForRoles(List<String> roleIds) => merge([
        for (final id in roleIds)
          if (roles.containsKey(id)) roles[id]!.permissions,
      ]);

  /// فحص صلاحية صفحة/إجراء.
  static bool can({
    required bool isAdmin,
    required PermissionMap permissions,
    required String page,
    String action = PermAction.view,
  }) {
    if (isAdmin) return true;
    return permissions[page]?[action] == true;
  }

  /// هل يملك المستخدم أي صلاحية إدارة على الصفحة (إضافة/تعديل/حذف/اعتماد)؟
  static bool canManage({
    required bool isAdmin,
    required PermissionMap permissions,
    required String page,
  }) =>
      isAdmin ||
      [PermAction.create, PermAction.edit, PermAction.delete, PermAction.approve]
          .any((a) => permissions[page]?[a] == true);

  /// نطاق المستودعات: null ⇒ كل المستودعات.
  static bool canUseWarehouse({
    required bool isAdmin,
    required List<String>? scope,
    required String warehouse,
  }) {
    if (isAdmin || scope == null) return true;
    if (warehouse.isEmpty) return true;
    return scope.contains(warehouse);
  }

  static List<String> filterWarehouses({
    required bool isAdmin,
    required List<String>? scope,
    required List<String> all,
  }) {
    if (isAdmin || scope == null) return all;
    return all.where(scope.contains).toList();
  }
}
