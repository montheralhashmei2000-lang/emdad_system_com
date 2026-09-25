import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../domain/access_control.dart';
import '../ui/imd_widgets.dart';
import 'auth_service.dart';

/// مساعدات الصلاحيات في الشاشات — نفس `can()` و`hasPerm()` و`pageManage()` و`guardPerm()` في الويب.
class Perm {
  Perm(this._auth);
  final AuthService _auth;

  /// `PERM_CATALOG` — أسماء الصفحات كما تظهر في رسائل الصلاحية.
  static const labels = <String, String>{
    'dashboard': 'الرئيسية',
    'items': 'الأصناف',
    'suppliers': 'الموردون',
    'units': 'الوحدات المستفيدة',
    'stores': 'المستودعات',
    'kitchens': 'المطابخ والأفران',
    'assets': 'الأصول الثابتة',
    'rationOrders': 'طلبيات الإعاشة',
    'supplyAuthorities': 'جهات الإمداد',
    'receive': 'الاستلام',
    'issue': 'الصرف',
    'transfer': 'التحويل المخزني',
    'returns': 'المرتجعات',
    'pendingOrders': 'أوامر التوريد المعلقة',
    'documents': 'سجل المستندات (السندات المحفوظة)',
    'feeding': 'التغذية / القوة',
    'kitchenLog': 'سجل التشغيل والطهي',
    'mealPlans': 'خطط الوجبات',
    'ratios': 'نسب الاستهلاك والاستحقاقات',
    'balances': 'الأرصدة الحالية',
    'stocktake': 'الجرد',
    'reports': 'التقارير',
    'actualEntitlement': 'حساب الاستحقاق الفعلي',
    'campLedger': 'سجل حساب المعسكر',
    'campSettlement': 'تصفية الشهر',
    'campDashboard': 'لوحة المعسكرات',
    'auditTrail': 'سجل التدقيق',
    'activityIntel': 'ذكاء النشاط',
    'executiveCmd': 'القيادة التنفيذية',
    'sensitiveOps': 'المراجعة الحساسة',
    'opening': 'الأرصدة الافتتاحية',
    'settings': 'الإعدادات والهوية',
    'usersAccess': 'المستخدمون والصلاحيات',
  };

  static Perm of(BuildContext context) => Perm(context.read<AuthService>());

  /// `can()` — مدير النظام.
  bool get admin => _auth.currentUser?.role == 'admin';

  String get email => _auth.currentUser?.email ?? '';

  bool has(String page, [String action = PermAction.view]) {
    final u = _auth.currentUser;
    if (u == null) return false;
    if (admin) return true;
    final p = _auth.permissionsOf(u)[page];
    return p is Map && p[action] == true;
  }

  /// `pageManage(page)`
  bool manage(String page) =>
      has(page, PermAction.create) || has(page, PermAction.edit) || has(page, PermAction.delete) || has(page, PermAction.approve);

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
  static String scopeBlock(String warehouse) => '✖ المستودع «$warehouse» خارج نطاق صلاحياتك — تواصل مع مدير النظام';

  /// `guardPerm(page, action)`
  bool guard(BuildContext context, String page, [String action = PermAction.edit]) {
    if (has(page, action)) return true;
    showImdToast(context, '✖ لا تملك صلاحية: ${labels[page] ?? page} — $action');
    return false;
  }
}
