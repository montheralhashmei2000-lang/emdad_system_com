import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';

/// إعدادات قسم المحروقات.
///
/// كانت حدود التنبيه والتواقيع والكميات الافتراضية مدفونةً في الكود، فتغييرُ
/// نسبةٍ يحتاج بناءً جديدًا ونشرًا على كل جهاز.
///
/// وهي إعدادات **القسم** لا إعدادات النظام: توقيع مسؤول المحروقات غير توقيع
/// أمين المستودع، وحدُّ نفاد الوقود غير حدّ نفاد الأصناف.
class FuelSettingsScreen extends StatefulWidget {
  const FuelSettingsScreen({super.key});

  @override
  State<FuelSettingsScreen> createState() => _FuelSettingsScreenState();
}

class _FuelSettingsScreenState extends State<FuelSettingsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  final _low = TextEditingController();
  final _daily = TextEditingController();
  final _weekly = TextEditingController();
  final _monthly = TextEditingController();
  final _officer = TextEditingController();
  final _supply = TextEditingController();
  final _chief = TextEditingController();
  final _notes = TextEditingController();

  bool _requireChassis = false;
  bool _allowExceptional = true;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _low,
      _daily,
      _weekly,
      _monthly,
      _officer,
      _supply,
      _chief,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _load() async {
    final s = await _repo.settings();
    if (!mounted) return;
    imdSetText(_low, _num(s.lowStockPercent));
    imdSetText(_daily, _num(s.defaultDailyLiters));
    imdSetText(_weekly, _num(s.defaultWeeklyLiters));
    imdSetText(_monthly, _num(s.defaultMonthlyLiters));
    imdSetText(_officer, s.signOfficer);
    imdSetText(_supply, s.signSupply);
    imdSetText(_chief, s.signChief);
    imdSetText(_notes, s.notes);
    setState(() {
      _requireChassis = s.requireChassis;
      _allowExceptional = s.allowExceptional;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!Perm.of(context).guard(context, 'fuelSettings', PermAction.edit)) {
      return;
    }
    setState(() => _busy = true);
    final res = await _repo.saveSettings(
      lowStockPercent: double.tryParse(_low.text.trim()) ?? 20,
      defaultDailyLiters: double.tryParse(_daily.text.trim()) ?? 0,
      defaultWeeklyLiters: double.tryParse(_weekly.text.trim()) ?? 0,
      defaultMonthlyLiters: double.tryParse(_monthly.text.trim()) ?? 0,
      signOfficer: _officer.text,
      signSupply: _supply.text,
      signChief: _chief.text,
      requireChassis: _requireChassis,
      allowExceptional: _allowExceptional,
      notes: _notes.text,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ حُفظت الإعدادات' : res.error,
        error: !res.ok);
    if (res.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'إعدادات المحروقات', icon: 'settings'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelSettings');

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'إعدادات المحروقات',
        icon: 'settings',
        subtitle: 'حدود التنبيه والكميات الافتراضية وتواقيع أوراق القسم',
      ),
      ImdPanel(
        title: 'التنبيهات',
        icon: 'alert',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled(
              'حد التنبيه على الانخفاض (٪ من السعة)',
              ImdFld(controller: _low, number: true, enabled: can),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          const ImdNote(
            'التنبيه **بالنسبة لا بالكمية**: خمسمئة لتر في خزّان سعته عشرون '
            'ألفًا نفادٌ وشيك، وفي خزّان سعته ألف رصيدٌ مريح. '
            'ومستودعٌ بلا سعة معلومة لا تنبيه نسبة له.',
          ),
        ]),
      ),
      ImdPanel(
        title: 'الكميات الافتراضية للتفريدة',
        icon: 'sliders',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled('يومي (${Fuel.unit})',
                ImdFld(controller: _daily, number: true, enabled: can),
                size: 11),
            ImdLabeled('أسبوعي (${Fuel.unit})',
                ImdFld(controller: _weekly, number: true, enabled: can),
                size: 11),
            ImdLabeled('شهري (${Fuel.unit})',
                ImdFld(controller: _monthly, number: true, enabled: can),
                size: 11),
          ]),
          const SizedBox(height: 10),
          const ImdLdText(
              'تُقترح عند إنشاء تفريدة جديدة، ويمكن تغييرها لكل وحدة.'),
        ]),
      ),
      ImdPanel(
        title: 'قواعد الصرف',
        icon: 'shield',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdCheckbox(
            value: _requireChassis,
            label: 'اشتراط رقم الشاصي في كل صرف',
            onChanged: can ? (v) => setState(() => _requireChassis = v) : null,
          ),
          const SizedBox(height: 6),
          const ImdLdText(
              'الشاصي هو ما يُحاسب عليه: بدونه لا يُعرف ما شربته المركبة، '
              'ولا يُكشف صرفٌ متكرر لمركبة واحدة بأسماء سائقين مختلفين.'),
          const SizedBox(height: 14),
          ImdCheckbox(
            value: _allowExceptional,
            label: 'السماح بالصرف الاستثنائي خارج التفريدة',
            onChanged: can ? (v) => setState(() => _allowExceptional = v) : null,
          ),
          const SizedBox(height: 6),
          const ImdLdText(
              'إن عُطّل، لم يُصرف وقود إلا من تفريدة معتمدة. '
              'وإن بقي مفعَّلًا فالاستثنائي يلزمه مبرر وجهة أمر، ويُسجَّل في '
              'التدقيق عالي الخطورة.'),
        ]),
      ),
      ImdPanel(
        title: 'تواقيع أوراق المحروقات',
        icon: 'edit',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled('مسؤول المحروقات',
                ImdFld(controller: _officer, enabled: can), size: 11),
            ImdLabeled('ركن الإمداد',
                ImdFld(controller: _supply, enabled: can), size: 11),
            ImdLabeled('رئيس الشعبة',
                ImdFld(controller: _chief, enabled: can), size: 11),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات',
              ImdFld(controller: _notes, maxLines: 2, enabled: can)),
        ]),
      ),
      if (can)
        ImdPanel(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
                label: 'حفظ الإعدادات',
                icon: 'check',
                busy: _busy,
                onPressed: _save),
          ),
        ),
    ]);
  }
}
