import 'package:flutter/material.dart';

import '../../core/ui/imd_tabs_shell.dart';
import '../alerts/stock_alerts_screen.dart';
import '../catalog/assets_screen.dart';
import '../catalog/items_screen.dart';
import '../catalog/kitchens_screen.dart';
import '../catalog/suppliers_screen.dart';
import '../catalog/units_screen.dart';
import '../catalog/warehouses_screen.dart';
import '../daily/daily_operations_screen.dart';
import '../daily/ratios_screen.dart';
import '../daily/strength_screen.dart';
import '../insights/activity_intel_screen.dart';
import '../insights/executive_cmd_screen.dart';
import '../insights/health_ops_screen.dart';
import '../insights/sensitive_ops_screen.dart';
import '../inventory/issue_screen.dart';
import '../inventory/opening_screen.dart';
import '../inventory/pending_screen.dart';
import '../inventory/ration_order_screen.dart';
import '../inventory/receive_screen.dart';
import '../inventory/returns_screen.dart';
import '../inventory/transfer_screen.dart';
import '../reports/balances_screen.dart';
import '../reports/reports_center_screen.dart';
import '../settings/audit_screen.dart';

/// أبواب قسم الإمداد والتموين.
///
/// **الشريط فهرسٌ لا سجل.** ستّة وعشرون بندًا في خمسة أقسام تُقرأ بالبحث لا
/// بالنظر. والمتقارب فيها ظاهر: سندات الحركة الخمسة يحرّرها أمينُ مستودعٍ
/// واحد في جلسةٍ واحدة، والأدلّة الستة تُعرَّف مرةً وتُقرأ دائمًا، والرقابة
/// خمسُ نظراتٍ على السجل نفسه.
///
/// وكلُّ بابٍ يُخفي تبويبةً لا يملك المستخدم صلاحيتها: الجمع تنظيمٌ للقائمة
/// لا توسيعٌ للأذونات.

/// حركة المخزون — السندات التي تحرّك الرصيد.
class SupplyMovesScreen extends StatelessWidget {
  const SupplyMovesScreen({super.key, this.initialTab = 'receive'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لأي من سندات الحركة',
        tabs: [
          ImdShellTab(
            id: 'receive',
            label: 'الاستلام',
            icon: 'download',
            perm: 'receive',
            builder: (_) => const ReceiveScreen(),
          ),
          ImdShellTab(
            id: 'issue',
            label: 'الصرف',
            icon: 'upload',
            perm: 'issue',
            builder: (_) => const IssueScreen(),
          ),
          ImdShellTab(
            id: 'transfer',
            label: 'التحويل',
            icon: 'refresh',
            perm: 'transfer',
            builder: (_) => const TransferScreen(),
          ),
          ImdShellTab(
            id: 'returns',
            label: 'المرتجعات',
            icon: 'undo',
            perm: 'returns',
            builder: (_) => const ReturnsScreen(),
          ),
          ImdShellTab(
            id: 'opening',
            label: 'الأرصدة الافتتاحية',
            icon: 'clipboard',
            perm: 'opening',
            builder: (_) => const OpeningScreen(),
          ),
        ],
      );
}

/// الطلبيات — ما يُطلب قبل أن يُستلم.
///
/// وهي غير الحركة: الطلبية **لا تمسّ الرصيد** حتى تُعتمد ويُحرَّر سندها.
class SupplyOrdersScreen extends StatelessWidget {
  const SupplyOrdersScreen({super.key, this.initialTab = 'rationOrders'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية للطلبيات',
        tabs: [
          ImdShellTab(
            id: 'rationOrders',
            label: 'طلبيات الإعاشة',
            icon: 'clipboard',
            perm: 'rationOrders',
            builder: (_) => const RationOrderScreen(),
          ),
          ImdShellTab(
            id: 'pendingOrders',
            label: 'أوامر التوريد المعلقة',
            icon: 'bell',
            perm: 'pendingOrders',
            builder: (_) => const PendingScreen(),
          ),
        ],
      );
}

/// البيانات الأساسية — أدلّة القسم التي يُبنى عليها كل سند.
class SupplyDataScreen extends StatelessWidget {
  const SupplyDataScreen({super.key, this.initialTab = 'items'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لأي من الأدلّة',
        tabs: [
          ImdShellTab(
            id: 'items',
            label: 'الأصناف',
            icon: 'package',
            perm: 'items',
            builder: (_) => const ItemsScreen(),
          ),
          ImdShellTab(
            id: 'stores',
            label: 'المستودعات',
            icon: 'warehouse',
            perm: 'stores',
            builder: (_) => const WarehousesScreen(),
          ),
          ImdShellTab(
            id: 'units',
            label: 'الوحدات المستفيدة',
            icon: 'users',
            perm: 'units',
            builder: (_) => const UnitsScreen(),
          ),
          ImdShellTab(
            id: 'suppliers',
            label: 'الموردون',
            icon: 'truck',
            perm: 'suppliers',
            builder: (_) => const SuppliersScreen(),
          ),
          ImdShellTab(
            id: 'kitchens',
            label: 'المطابخ والأفران',
            icon: 'utensils',
            perm: 'kitchens',
            builder: (_) => const KitchensScreen(),
          ),
          ImdShellTab(
            id: 'assets',
            label: 'الأصول الثابتة',
            icon: 'package',
            perm: 'assets',
            builder: (_) => const AssetsScreen(),
          ),
        ],
      );
}

/// التشغيل اليومي — ما يُفتح كل صباح.
class SupplyDailyScreen extends StatelessWidget {
  const SupplyDailyScreen({super.key, this.initialTab = 'feeding'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لشاشات التشغيل اليومي',
        tabs: [
          ImdShellTab(
            id: 'feeding',
            label: 'التغذية اليومية',
            icon: 'calendar',
            perm: 'feeding',
            builder: (_) => const StrengthScreen(),
          ),
          ImdShellTab(
            id: 'dailyOperations',
            label: 'التخطيط والتشغيل',
            icon: 'calendar',
            perm: 'dailyOperations',
            builder: (_) => const DailyOperationsScreen(),
          ),
          ImdShellTab(
            id: 'ratios',
            label: 'نسب الاستهلاك',
            icon: 'scale',
            perm: 'ratios',
            builder: (_) => const RatiosScreen(),
          ),
        ],
      );
}

/// التقارير — نظراتٌ على البيانات نفسها.
class SupplyReportsScreen extends StatelessWidget {
  const SupplyReportsScreen({super.key, this.initialTab = 'reports'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لأي من التقارير',
        tabs: [
          ImdShellTab(
            id: 'reports',
            label: 'مركز التقارير',
            icon: 'chart',
            perm: 'reports',
            builder: (_) => const ReportsCenterScreen(),
          ),
          ImdShellTab(
            id: 'balances',
            label: 'الأرصدة الحالية',
            icon: 'calculator',
            perm: 'balances',
            builder: (_) => const BalancesScreen(),
          ),
          ImdShellTab(
            id: 'stockAlerts',
            label: 'تنبيهات المخزون',
            icon: 'alert',
            perm: 'balances',
            builder: (_) => const StockAlertsScreen(),
          ),
        ],
      );
}

/// الرقابة والتدقيق — خمسُ نظراتٍ على السجل نفسه.
///
/// السجل يُقرأ سطرًا سطرًا للتحقيق، ويُقرأ مجمَّعًا لكشف الانحراف، ويُقرأ
/// مرشَّحًا على الحسّاس وحده. وثلاثتها بابٌ واحد.
class SupplyAuditScreen extends StatelessWidget {
  const SupplyAuditScreen({super.key, this.initialTab = 'auditTrail'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => ImdTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية للرقابة والتدقيق',
        tabs: [
          ImdShellTab(
            id: 'auditTrail',
            label: 'سجل النشاط',
            icon: 'scan',
            perm: 'auditTrail',
            builder: (_) => const AuditScreen(),
          ),
          ImdShellTab(
            id: 'activityIntel',
            label: 'ذكاء النشاط',
            icon: 'bulb',
            perm: 'activityIntel',
            builder: (_) => const ActivityIntelScreen(),
          ),
          ImdShellTab(
            id: 'sensitiveOps',
            label: 'التغييرات الحساسة',
            icon: 'alert',
            perm: 'sensitiveOps',
            builder: (_) => const SensitiveOpsScreen(),
          ),
          ImdShellTab(
            id: 'executiveCmd',
            label: 'مركز القيادة',
            icon: 'target',
            perm: 'executiveCmd',
            builder: (_) => const ExecutiveCmdScreen(),
          ),
          ImdShellTab(
            id: 'healthOps',
            label: 'صحة النظام',
            icon: 'shield',
            perm: 'healthOps',
            builder: (_) => const HealthOpsScreen(),
          ),
        ],
      );
}
