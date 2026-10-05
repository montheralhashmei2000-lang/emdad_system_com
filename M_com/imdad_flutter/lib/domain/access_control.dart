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

  /// استيراد بياناتٍ من ملف (Excel وغيره) — إجراءٌ مستقل عن «إضافة».
  static const String import = 'import';
}

/// أدوار الحساب (عمود `users.role`).
///
/// • [owner]: المالك — كل الصلاحيات ومعها `sys.*`، ولا يُعدَّل من أحد.
/// • [admin]: مدير النظام — كل صلاحيات الصفحات، **بلا** `sys.*`.
/// • [user]: مستخدم عادي — بحسب صلاحياته المخزَّنة.
///
/// القيمة القديمة `admin` تبقى كما هي، فلا ترحيل لها: المالك أضيف فوقها.
class UserRole {
  const UserRole._();

  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String user = 'user';

  /// يملك كل صلاحيات الصفحات (مالك أو مدير).
  static bool isAdmin(String? role) => role == admin || role == owner;

  static bool isOwner(String? role) => role == owner;

  static String label(String? role) => switch (role) {
        owner => 'المالك',
        admin => 'مدير النظام',
        _ => 'مستخدم',
      };
}

/// الصلاحيات الخاصة بالنظام (`sys.*`) — **للمالك وحده**.
///
/// ليست في كتالوج الصلاحيات ولا في القوالب ولا في مصفوفة الصلاحيات، ولا تُقرأ
/// من `users.permissions` إطلاقًا: فمفتاحٌ `sys.backup: true` يصل بمزامنةٍ أو
/// بملف استعادة أو بتعديلٍ يدوي للقاعدة **لا أثر له** (فشلٌ مغلق). الفحص دور
/// الحساب [UserRole.owner] لا غير.
class SysPerm {
  const SysPerm._();

  static const String prefix = 'sys.';

  /// تعديل صلاحيات الآخرين وأدوارهم وحجب الأقسام.
  static const String permissions = 'sys.permissions';

  /// منح دور مدير النظام، وحذف المستخدمين وتعطيلهم، وإعادة كلمة مرور مدير.
  static const String users = 'sys.users';

  /// النسخ الاحتياطي الكامل (تصدير واستعادة وجدولة) والإعادة المحلية واستيراد
  /// حسابات المستخدمين بالجملة.
  static const String backup = 'sys.backup';

  /// تفعيل الأجهزة: إصدار الرموز والإلغاء والمفتاح الخاص.
  static const String devices = 'sys.devices';

  /// المزامنة: الاقتران والمفاتيح الدائمة واستقبال الحسابات.
  static const String sync = 'sys.sync';

  /// الإعدادات الحساسة: قواعد المحرك ومفتاح التوقيع والأرشفة التلقائية.
  static const String settingsSensitive = 'sys.settingsSensitive';

  static const Map<String, String> labels = {
    permissions: 'تعديل الصلاحيات والأدوار وحجب الأقسام',
    users: 'منح دور المدير وحذف المستخدمين وتعطيلهم',
    backup: 'النسخ الاحتياطي الكامل واستيراد المستخدمين',
    devices: 'تفعيل الأجهزة',
    sync: 'المزامنة والاقتران',
    settingsSensitive: 'الإعدادات الحساسة (القواعد والتوقيع والأرشفة)',
  };

  static List<String> get all => labels.keys.toList();

  static bool isSys(String page) => page.startsWith(prefix);
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
    'dashboard', 'items', 'suppliers', 'units', 'stores', 'kitchens', 'assets',
    'supplyAuthorities',
  ];

  /// طلبيات الإعاشة ضمن العمليات: من يستلم ويصرف هو من يطلب، ومن يعتمد سندًا
  /// هو من يعتمد طلبية.
  /// صفحات المحروقات — قسمٌ مستقل عن مخزون الإعاشة: أمين المحروقات ليس
  /// بالضرورة أمين المستودع، وصلاحية أحدهما لا تُعطى للآخر ضمنًا.
  static const List<String> fuelPages = [
    'fuelDashboard', 'fuelAllocations', 'fuelMoves', 'fuelStocktake',
    'fuelWarehouses', 'fuelUnits', 'fuelSettings',
    'fuelVehicles', 'fuelReports', 'fuelConsumption',
  ];

  static const List<String> opsPages = [
    'receive', 'issue', 'transfer', 'returns', 'rationOrders',
  ];

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
      description: 'إضافة سندات وتفريدات وسجلات جديدة فقط في مستودعات نطاقه — دون تعديل ما سُجّل أو حذفه أو اعتماده',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        grant(opsPages, [PermAction.view, PermAction.create]),
        // إضافةٌ فقط: التفريدة تُحفظ لليوم الجديد بـ«إضافة» (انظر strength_screen)،
        // وتصحيح ما سُجّل لمن يملك «تعديل».
        grant(['feeding', 'kitchenLog', 'mealPlans'], [PermAction.view, PermAction.create]),
        grant(['balances', 'pendingOrders'], [PermAction.view]),
        grant(['documents'], [PermAction.view]),
        // العدّ إضافة: سطرٌ لم يُعدّ بعد يكفيه «إضافة» (انظر _canCountLine في
        // شاشة الجرد)، وتصحيح عدٍّ مسجَّل يتطلب «تعديل».
        grant(['stocktake'], [PermAction.view, PermAction.create]),
      ]),
    ),
    'storekeeper': RoleTemplate(
      id: 'storekeeper',
      label: 'أمين مخزن',
      description: 'الاستلام والصرف والتحويل والمرتجعات والجرد واعتمادها وطباعتها، وإدارة الكتالوج (الأصناف والموردون والوحدات…) والأرصدة والتقارير، في مستودعات نطاقه',
      permissions: merge([
        grant(basicPages, [PermAction.view]),
        // الكتالوج: يضيف ويعدّل ويستورد ويصدّر ويطبع — بلا حذف، وبلا إدارة المستودعات نفسها.
        grant(['items'], [
          PermAction.view, PermAction.create, PermAction.edit,
          PermAction.print, PermAction.export, PermAction.import,
        ]),
        grant(['suppliers'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.export,
        ]),
        grant(['kitchens', 'assets'], [
          PermAction.view, PermAction.create, PermAction.edit,
        ]),
        grant(['units'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.print, PermAction.export,
        ]),
        grant(opsPages, [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.approve, PermAction.print,
        ]),
        grant(['pendingOrders'], [PermAction.view, PermAction.approve, PermAction.print]),
        // ركن الإمداد يضع تفريدة المحروقات ويعتمد جردها — وهو من يوازن بين
        // الوحدات، فبيده توزيع الاستحقاق لا بيد من يصرفه.
        grant(fuelPages, [PermAction.view, PermAction.print, PermAction.export]),
        grant(['fuelAllocations', 'fuelWarehouses', 'fuelUnits'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.delete,
        ]),
        grant(['fuelSettings'], [PermAction.view, PermAction.edit]),
        grant(['fuelStocktake'], [PermAction.view, PermAction.approve]),
        // ركن الإمداد هو من تُرفع إليه طلبيات الإعاشة وبه تُجاز: لا تتحرك
        // إعاشةٌ بين مستودعين ولا تُطلب من جهةٍ إلا بإذنه.
        grant(['rationOrders'], [
          PermAction.view, PermAction.approve, PermAction.print, PermAction.export,
        ]),
        // ودليل الجهات يديره من يطلب منها.
        grant(['supplyAuthorities'], [
          PermAction.view, PermAction.create, PermAction.edit,
        ]),
        grant(['opening'], [PermAction.view, PermAction.create, PermAction.print]),
        grant(['balances'], [PermAction.view, PermAction.print, PermAction.export]),
        grant(['campDashboard'], [PermAction.view]),
        grant(['stocktake'], [PermAction.view, PermAction.create, PermAction.edit, PermAction.print]),
        grant(['reports'], [PermAction.view, PermAction.print, PermAction.export]),
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
        // ركن الإمداد هو من يضع قائمة الطعام ويعتمدها — ولذلك وحده التنشيط.
        grant(['mealPlans'], [
          PermAction.view, PermAction.create, PermAction.edit,
          PermAction.approve, PermAction.print, PermAction.export,
        ]),
        // سجل المعسكرات يبنيه ركن الإمداد ويصفّيه — وهو من يوازن بين الوحدات.
        grant(['campLedger', 'campDashboard'], [
          PermAction.view, PermAction.create, PermAction.edit,
          PermAction.print, PermAction.export,
        ]),
        grant(['campSettlement'], [PermAction.view, PermAction.approve]),
        grant(['balances', 'reports', 'actualEntitlement'], [PermAction.view, PermAction.print, PermAction.export]),
        grant(['stocktake'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['documents'], [PermAction.view, PermAction.print]),
      ]),
    ),
    'fuel_keeper': RoleTemplate(
      id: 'fuel_keeper',
      label: 'أمين المحروقات',
      description: 'قسم المحروقات وحده: التفريدة والصرف والتوريد والتحويل والجرد والتقارير — بلا أي صلاحية على الإمداد',
      permissions: merge([
        grant(['fuelDashboard', 'fuelVehicles'], [PermAction.view]),
        grant(['fuelMoves', 'fuelAllocations'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.print,
        ]),
        grant(['fuelWarehouses', 'fuelUnits'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.delete,
        ]),
        grant(['fuelReports', 'fuelConsumption'], [PermAction.view, PermAction.print]),
        grant(['fuelStocktake'], [PermAction.view, PermAction.approve, PermAction.print]),
        grant(['fuelSettings'], [PermAction.view, PermAction.edit]),
      ]),
    ),
    'finance': RoleTemplate(
      id: 'finance',
      label: 'المالية',
      description: 'الارتباطات: القوة البشرية والمالية (السندات والعهد والعقود والمسيرات والإخلاء) وطباعتها وتصديرها واستيرادها',
      permissions: merge([
        grant(['personnel'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.delete,
          PermAction.print, PermAction.export,
        ]),
        grant(['linkages'], [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.approve,
          PermAction.print, PermAction.export, PermAction.import,
        ]),
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
        grant(['feeding', 'kitchenLog', 'ratios', 'mealPlans'], [
          PermAction.view, PermAction.print, PermAction.export,
        ]),
        grant(['balances', 'reports', 'actualEntitlement', 'campLedger', 'campDashboard', 'auditTrail', 'executiveCmd'], [
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
        grant(['balances', 'reports', 'actualEntitlement', 'documents', 'stocktake', 'mealPlans'], [PermAction.view]),
      ]),
    ),
  };

  /// صلاحيات مجموعة أدوار مجتمعة.
  static PermissionMap permissionsForRoles(List<String> roleIds) => merge([
        for (final id in roleIds)
          if (roles.containsKey(id)) roles[id]!.permissions,
      ]);

  /// هل تسمح خريطة إجراءات صفحةٍ ([pageActions]) بـ[action]؟
  ///
  /// **توافقٌ مع ما قبل «import»:** الاستيراد كان يُحرس بـ«إضافة»، فمن لم
  /// يُذكر له مفتاح `import` صراحةً (لا `true` ولا `false`) يرث صلاحية
  /// «إضافة» كما كانت — فلا يفقد أحدٌ قدرةً كانت له. وإن حدّد المالك
  /// `import` صراحةً (تفعيلًا أو إلغاءً) فهو الحكم.
  static bool allows(Map? pageActions, String action) {
    if (pageActions == null) return false;
    if (action == PermAction.import && !pageActions.containsKey(PermAction.import)) {
      return pageActions[PermAction.create] == true;
    }
    return pageActions[action] == true;
  }

  /// فحص صلاحية صفحة/إجراء.
  static bool can({
    required bool isAdmin,
    required PermissionMap permissions,
    required String page,
    String action = PermAction.view,
    bool isOwner = false,
  }) {
    // `sys.*` للمالك وحده، ولا يُقرأ من الصلاحيات المخزَّنة أبدًا.
    if (SysPerm.isSys(page)) return isOwner;
    if (isAdmin) return true;
    return allows(permissions[page], action);
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
