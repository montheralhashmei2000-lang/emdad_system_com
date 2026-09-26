import 'package:flutter/material.dart';

import 'fuel_consumption_screen.dart';
import 'fuel_daily_report_screen.dart';
import 'fuel_directories_screen.dart';
import 'fuel_ledger_screen.dart';
import 'fuel_official_report_screen.dart';
import 'fuel_tabs_shell.dart';
import 'fuel_vehicles_screen.dart';

/// البيانات الأساسية — أدلّة القسم التي تُعرَّف مرةً ويُبنى عليها كل سند.
///
/// **تُفتح نادرًا وتُقرأ كثيرًا.** المستودعات والوحدات والمركبات ليست عملًا
/// يوميًّا كالصرف، فجمعُها في بندٍ واحد يُخلي القائمة لما يُفتح كل يوم.
class FuelDataScreen extends StatelessWidget {
  const FuelDataScreen({super.key, this.initialTab = 'warehouses'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => FuelTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لأي من أدلّة المحروقات',
        tabs: [
          FuelTab(
            id: 'warehouses',
            label: 'المستودعات',
            icon: 'warehouse',
            perm: 'fuelWarehouses',
            builder: (_) => const FuelWarehousesScreen(),
          ),
          FuelTab(
            id: 'units',
            label: 'الوحدات المستفيدة',
            icon: 'building',
            perm: 'fuelUnits',
            builder: (_) => const FuelUnitsScreen(),
          ),
          FuelTab(
            id: 'vehicles',
            label: 'سجل المركبات',
            icon: 'truck',
            perm: 'fuelVehicles',
            builder: (_) => const FuelVehiclesScreen(),
          ),
        ],
      );
}

/// التقارير — خمسُ نظراتٍ على البيانات نفسها.
///
/// البرقية ورقةٌ تُرفع، والاستهلاك يقول من يشرب، والأرصدة تقول ما بقي،
/// والكشف يقول متى وبأي سند، والاستحقاق يقول من أخذ حقّه. وجمعُها في بندٍ
/// واحد يجعل السؤال «أي تقرير؟» لا «أين التقارير؟».
class FuelReportsHubScreen extends StatelessWidget {
  const FuelReportsHubScreen({super.key, this.initialTab = 'daily'});

  final String initialTab;

  @override
  Widget build(BuildContext context) => FuelTabsShell(
        initial: initialTab,
        emptyMessage: 'لا صلاحية لأي من تقارير المحروقات',
        tabs: [
          FuelTab(
            id: 'daily',
            label: 'الحركة اليومية',
            icon: 'calendar',
            perm: 'fuelReports',
            builder: (_) => const FuelDailyReportScreen(),
          ),
          FuelTab(
            id: 'official',
            label: 'التقرير الرسمي',
            icon: 'file',
            perm: 'fuelReports',
            builder: (_) => const FuelOfficialReportScreen(),
          ),
          FuelTab(
            id: 'consumption',
            label: 'الاستهلاك',
            icon: 'trending',
            perm: 'fuelConsumption',
            builder: (_) => const FuelConsumptionScreen(),
          ),
          FuelTab(
            id: 'stocks',
            label: 'أرصدة المستودعات',
            icon: 'package',
            perm: 'fuelReports',
            builder: (_) => const FuelStocksReportScreen(),
          ),
          FuelTab(
            id: 'ledger',
            label: 'كشف حركة المستودع',
            icon: 'list',
            perm: 'fuelReports',
            builder: (_) => const FuelLedgerScreen(),
          ),
          FuelTab(
            id: 'plan',
            label: 'الاستحقاق مقابل الصرف',
            icon: 'scale',
            perm: 'fuelReports',
            builder: (_) => const FuelPlanVsIssuedScreen(),
          ),
        ],
      );
}
