import 'package:flutter/material.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';
import 'kitchen_log_screen.dart';
import 'meal_plan_screen.dart';

/// نقطة موحّدة للتخطيط اليومي وتسجيل التنفيذ الفعلي.
class DailyOperationsScreen extends StatefulWidget {
  const DailyOperationsScreen({super.key});

  @override
  State<DailyOperationsScreen> createState() => _DailyOperationsScreenState();
}

class _DailyOperationsScreenState extends State<DailyOperationsScreen> {
  String _tab = '';

  bool get _canPlan => Perm.of(context).has('mealPlans');
  bool get _canLog => Perm.of(context).has('kitchenLog');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tab.isEmpty) _tab = _canPlan ? 'plans' : 'actual';
    if (_tab == 'plans' && !_canPlan && _canLog) _tab = 'actual';
    if (_tab == 'actual' && !_canLog && _canPlan) _tab = 'plans';
  }

  @override
  Widget build(BuildContext context) {
    final canPlan = _canPlan;
    final canLog = _canLog;
    final tabs = <ImdTab<String>>[
      if (canPlan) const ImdTab('plans', 'خطط الوجبات', icon: 'calendar'),
      if (canLog) const ImdTab('actual', 'التسجيل اليومي والسجل', icon: 'utensils'),
    ];

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'التخطيط والتشغيل اليومي',
        icon: 'calendar',
        subtitle: 'إدارة قوائم الوجبات ومراجعة الاستهلاك الفعلي في مساحة تشغيل واحدة',
      ),
      if (tabs.length > 1) ...[
        ImdItabs(
          value: _tab,
          onChanged: (value) => setState(() => _tab = value),
          tabs: tabs,
        ),
        const SizedBox(height: 12),
      ],
      if (_tab == 'plans' && canPlan)
        const MealPlanScreen(embedded: true)
      else if (_tab == 'actual' && canLog)
        const KitchenLogScreen(embedded: true)
      else if (canPlan)
        const MealPlanScreen(embedded: true)
      else if (canLog)
        const KitchenLogScreen(embedded: true)
      else
        const ImdEmptyBox('لا تملك صلاحية عرض خطط الوجبات أو سجل التشغيل اليومي.'),
    ]);
  }
}
