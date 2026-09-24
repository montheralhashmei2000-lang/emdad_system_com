import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/meal_plan_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/meal_plan.dart';

/// خطط الوجبات: قائمة الطعام يومًا بيوم، واحتياجها من القوة المسجّلة، ومقارنة
/// خطتين.
///
/// ثلاثة تبويبات في شاشة واحدة لا ثلاث شاشات: بناء الخطة وقراءة احتياجها
/// ومقارنتها عملٌ واحد يجري في جلسة واحدة، وتفريقه على مسارات يجعل كل انتقال
/// إعادة تحميل.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final MealPlanRepo _repo = MealPlanRepo(_db);

  String _tab = 'plans';
  List<MealPlan> _plans = const [];
  List<Item> _items = const [];
  List<Facility> _facilities = const [];
  List<Warehouse> _warehouses = const [];

  MealPlanFull? _open;
  List<MealRequirement> _needs = const [];
  Map<String, int> _persons = const {};

  String _compareA = '';
  String _compareB = '';
  List<MealPlanDiff> _diffs = const [];

  final _name = TextEditingController();
  final _notes = TextEditingController();
  String _planType = MealPlanType.weekly;
  String _start = MealPlanRules.ymd(DateTime.now());
  String _customEnd = '';
  String _facilityId = '';
  String _warehouse = '';
  String? _editId;

  String _filterStatus = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateSpan get _span =>
      MealPlanRules.spanOf(_planType, _start, customEnd: _customEnd);

  Future<void> _render() async {
    final scope = Perm.of(context).scope;
    final plans = await _repo.plans(status: _filterStatus, scope: scope);
    final items = await CatalogRepo(_db).items();
    final facilities = await _db.select(_db.facilities).get();
    final warehouses = await _db.select(_db.warehouses).get();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _items = items;
      _facilities = facilities;
      _warehouses = warehouses;
      _loading = false;
    });
    if (_open != null) await _openPlan(_open!.plan.id);
  }

  Future<void> _openPlan(String id) async {
    final full = await _repo.byId(id);
    if (full == null || !mounted) return;
    final persons = await _repo.personsByDay(full.span);
    final needs = MealPlanCalc.requirements(
      entries: full.domainEntries,
      personsByDay: persons,
    );
    if (!mounted) return;
    setState(() {
      _open = full;
      _persons = persons;
      _needs = needs;
    });
  }

  void _loadForm(MealPlan? p) {
    imdSetText(_name, p?.name ?? '');
    imdSetText(_notes, p?.notes ?? '');
    setState(() {
      _editId = p?.id;
      _planType = p?.planType ?? MealPlanType.weekly;
      _start = p?.startDate ?? MealPlanRules.ymd(DateTime.now());
      _customEnd = p?.endDate ?? '';
      _facilityId = p?.facilityId ?? '';
      _warehouse = p?.warehouse ?? '';
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'mealPlans',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    setState(() => _busy = true);
    final facility = _facilities.where((f) => f.id == _facilityId).firstOrNull;
    final res = await _repo.savePlan(
      id: _editId,
      name: _name.text,
      planType: _planType,
      span: _span,
      facilityId: _facilityId,
      facilityName: facility?.name ?? '',
      warehouse: _warehouse,
      notes: _notes.text.trim(),
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ حُفظت الخطة' : res.error, error: !res.ok);
    if (res.ok) {
      _loadForm(null);
      await _render();
      await _openPlan(res.planId);
    }
  }

  Future<void> _activate(MealPlan p) async {
    if (!Perm.of(context).guard(context, 'mealPlans', PermAction.approve)) return;
    final res = await _repo.activate(
      p.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ نُشّطت الخطة' : res.error, error: !res.ok);
    await _render();
  }

  Future<void> _archive(MealPlan p) async {
    if (!Perm.of(context).guard(context, 'mealPlans', PermAction.edit)) return;
    await _repo.archive(p.id, actor: context.read<AuthService>().currentUser?.email ?? '');
    if (!mounted) return;
    showImdToast(context, '✔ أُرشفت الخطة');
    await _render();
  }

  Future<void> _delete(MealPlan p) async {
    if (!Perm.of(context).guard(context, 'mealPlans', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف خطة «${p.name}» ووجباتها؟', ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.delete(
      p.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذفت الخطة' : res.error, error: !res.ok);
    if (res.ok && _open?.plan.id == p.id) setState(() => _open = null);
    await _render();
  }

  Future<void> _duplicate(MealPlan p) async {
    final nameCtrl = TextEditingController(text: '${p.name} — نسخة');
    var start = MealPlanRules.ymd(
      DateTime.parse(p.endDate).add(const Duration(days: 1)),
    );
    final ok = await showImdModal<bool>(
      context,
      title: 'استنساخ «${p.name}»',
      icon: 'copy',
      maxWidth: 420,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
          ImdLabeled('اسم الخطة الجديدة', ImdFld(controller: nameCtrl)),
          const SizedBox(height: 10),
          ImdLabeled(
            'تاريخ البداية الجديد',
            ImdDateField(value: start, onChanged: (v) => setS(() => start = v)),
          ),
          const SizedBox(height: 10),
          const ImdNote('تُزاح تواريخ الوجبات كلها بالفارق نفسه، فتبقى قائمة '
              'الطعام على ترتيبها.'),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'استنساخ', icon: 'copy', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    final newName = nameCtrl.text;
    nameCtrl.dispose();
    if (ok != true || !mounted) return;
    final res = await _repo.duplicate(
      sourceId: p.id,
      newName: newName,
      newStart: start,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ استُنسخت الخطة' : res.error, error: !res.ok);
    await _render();
  }

  Future<void> _addEntry(String date) async {
    if (!Perm.of(context).guard(context, 'mealPlans', PermAction.edit)) return;
    var meal = MealType.lunch;
    var itemId = '';
    final qty = TextEditingController();
    final ok = await showImdModal<bool>(
      context,
      title: 'إضافة صنف — ${MealPlanRules.weekdayOf(date)} ${arDigits(date)}',
      icon: 'utensils',
      maxWidth: 460,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
          ImdLabeled(
            'الوجبة',
            ImdSelect<String>(
              items: [for (final m in MealType.all) (m, MealType.label(m))],
              value: meal,
              onChanged: (v) => setS(() => meal = v ?? MealType.lunch),
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled(
            'الصنف',
            ImdSelect<String>(
              hint: 'اختر الصنف',
              items: [for (final i in _items) (i.id, '${i.code} · ${i.name}')],
              value: itemId.isEmpty ? null : itemId,
              onChanged: (v) => setS(() => itemId = v ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled('الكمية للفرد الواحد', ImdFld(controller: qty, number: true)),
          const SizedBox(height: 10),
          const ImdNote('الكمية **للفرد الواحد** في هذه الوجبة. الإجمالي يُحسب '
              'بضربها في قوة ذلك اليوم من التفريدة.'),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'إضافة', icon: 'check', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    final value = double.tryParse(qty.text.trim()) ?? 0;
    qty.dispose();
    if (ok != true || !mounted || _open == null) return;
    final item = _items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      showImdToast(context, '✖ اختر الصنف', error: true);
      return;
    }
    final res = await _repo.addEntry(
      planId: _open!.plan.id,
      entryDate: date,
      mealType: meal,
      itemId: item.id,
      itemCode: item.code,
      itemName: item.name,
      unitName: item.baseUnit,
      factor: 1,
      qtyPerPerson: value,
    );
    if (!mounted) return;
    if (!res.ok) showImdToast(context, res.error, error: true);
    await _openPlan(_open!.plan.id);
  }

  Future<void> _copyDay(String from) async {
    if (_open == null) return;
    var to = from;
    final ok = await showImdModal<bool>(
      context,
      title: 'نسخ وجبات ${MealPlanRules.weekdayOf(from)}',
      icon: 'copy',
      maxWidth: 400,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
          ImdLabeled(
            'إلى يوم',
            ImdDateField(value: to, onChanged: (v) => setS(() => to = v)),
          ),
          const SizedBox(height: 10),
          const ImdNote('وجبات اليوم الهدف تُستبدل بالكامل.'),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'نسخ', icon: 'copy', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    if (ok != true || !mounted) return;
    final n = await _repo.copyDay(planId: _open!.plan.id, from: from, to: to);
    if (!mounted) return;
    showImdToast(context, n > 0 ? '✔ نُسخ $n صنفًا' : '✖ لا شيء لينسخ أو اليوم خارج المدى',
        error: n == 0);
    await _openPlan(_open!.plan.id);
  }

  Future<void> _compare() async {
    if (_compareA.isEmpty || _compareB.isEmpty || _compareA == _compareB) return;
    setState(() => _busy = true);
    final a = await _repo.byId(_compareA);
    final b = await _repo.byId(_compareB);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _diffs = a == null || b == null
          ? const []
          : MealPlanCalc.compare(a: a.domainEntries, b: b.domainEntries);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'خطط الوجبات', icon: 'utensils'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'خطط الوجبات',
        icon: 'utensils',
        subtitle: 'قائمة الطعام يومًا بيوم: ما يُطبخ وكم لكل فرد. الاحتياج يُحسب '
            'من قوة كل يوم المسجّلة في التفريدة',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('plans', 'الخطط', icon: 'clipboard'),
          ImdTab('menu', 'قائمة الطعام', icon: 'utensils'),
          ImdTab('compare', 'مقارنة خطتين', icon: 'scale'),
        ],
      ),
      if (_tab == 'plans') ..._plansTab(),
      if (_tab == 'menu') ..._menuTab(),
      if (_tab == 'compare') ..._compareTab(),
    ]);
  }

  // ───────────────────────── تبويب الخطط

  List<Widget> _plansTab() {
    final can = Perm.of(context).writable('mealPlans');
    return [
      ImdICard(
        child: ImdF2(children: [
          ImdLabeled(
            'تصفية بالحالة',
            ImdSelect<String>(
              items: [
                ('', 'كل الحالات'),
                for (final s in MealPlanStatus.all) (s, MealPlanStatus.label(s)),
              ],
              value: _filterStatus,
              onChanged: (v) {
                setState(() => _filterStatus = v ?? '');
                _render();
              },
            ),
            size: 11,
          ),
          ImdLabeled(
            ' ',
            Wrap(spacing: 10, children: [
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _render),
              if (can)
                ImdButton.outline(
                  label: 'خطة جديدة',
                  icon: 'plus-square',
                  small: true,
                  onPressed: () => _loadForm(null),
                ),
            ]),
            size: 11,
          ),
        ]),
      ),
      if (can)
        ImdPanel(
          title: _editId == null ? 'خطة جديدة' : 'تعديل الخطة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: _planForm(),
        ),
      ImdPanel(title: 'الخطط', icon: 'list', child: _plansTable(can)),
    ];
  }

  Widget _planForm() {
    final span = _span;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdF2(children: [
        ImdLabeled('اسم الخطة *', ImdFld(controller: _name), size: 11),
        ImdLabeled(
          'نوع الخطة *',
          ImdSelect<String>(
            items: [for (final t in MealPlanType.all) (t, MealPlanType.label(t))],
            value: _planType,
            onChanged: (v) => setState(() => _planType = v ?? MealPlanType.weekly),
          ),
          size: 11,
        ),
        ImdLabeled(
          'تاريخ البداية *',
          ImdDateField(value: _start, onChanged: (v) => setState(() => _start = v)),
          size: 11,
        ),
        ImdLabeled(
          _planType == MealPlanType.custom ? 'تاريخ النهاية *' : 'تاريخ النهاية (يُحسب)',
          ImdDateField(
            value: span.end,
            enabled: _planType == MealPlanType.custom,
            onChanged: (v) => setState(() => _customEnd = v),
          ),
          size: 11,
        ),
        ImdLabeled(
          'المطبخ / الفرن',
          ImdSelect<String>(
            items: [('', '— الوحدة كلها —'), for (final f in _facilities) (f.id, f.name)],
            value: _facilityId,
            onChanged: (v) => setState(() => _facilityId = v ?? ''),
          ),
          size: 11,
        ),
        ImdLabeled(
          'المستودع المصروف منه',
          ImdSelect<String>(
            items: [
              ('', '— بلا تحديد —'),
              for (final w in _warehouses)
                if (Perm.of(context).canWh(w.name)) (w.name, w.name),
            ],
            value: _warehouse,
            onChanged: (v) => setState(() => _warehouse = v ?? ''),
          ),
          size: 11,
        ),
      ]),
      const SizedBox(height: 10),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
      const SizedBox(height: 10),
      ImdChipsRow(children: [
        ImdChip('المدة: ${nf(span.days)} يوم', tone: ImdTone.info),
        ImdChip('${arDigits(span.start)} ← ${arDigits(span.end)}', tone: ImdTone.code),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        ImdButton(
          label: _editId == null ? 'إنشاء الخطة' : 'حفظ التعديل',
          icon: 'check',
          busy: _busy,
          onPressed: _save,
        ),
        if (_editId != null)
          ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: () => _loadForm(null)),
      ]),
    ]);
  }

  Widget _plansTable(bool can) => ImdTable(
        empty: 'لا توجد خطط وجبات',
        minWidth: 720,
        onRowTap: (i) {
          _openPlan(_plans[i].id);
          setState(() => _tab = 'menu');
        },
        columns: const [
          ImdCol('الخطة'),
          ImdCol('النوع'),
          ImdCol('المدى'),
          ImdCol('المطبخ'),
          ImdCol('الحالة'),
          ImdCol('إجراءات', center: true),
        ],
        rows: [
          for (final p in _plans)
            [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(MealPlanType.label(p.planType)),
              Text('${arDigits(p.startDate)} ← ${arDigits(p.endDate)}'),
              Text(p.facilityName.isEmpty ? 'الوحدة كلها' : p.facilityName),
              ImdChip(MealPlanStatus.label(p.status), tone: _tone(p.status)),
              Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                ImdIconButton(
                  icon: 'utensils',
                  tooltip: 'قائمة الطعام',
                  onPressed: () {
                    _openPlan(p.id);
                    setState(() => _tab = 'menu');
                  },
                ),
                if (can)
                  ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _loadForm(p)),
                if (can)
                  ImdIconButton(
                      icon: 'copy', tooltip: 'استنساخ', onPressed: () => _duplicate(p)),
                if (can && p.status != MealPlanStatus.active)
                  ImdIconButton(
                      icon: 'check', tooltip: 'تنشيط', onPressed: () => _activate(p)),
                if (can && p.status == MealPlanStatus.active)
                  ImdIconButton(
                      icon: 'archive', tooltip: 'أرشفة', onPressed: () => _archive(p)),
                if (can)
                  ImdIconButton(icon: 'trash', tooltip: 'حذف', onPressed: () => _delete(p)),
              ]),
            ],
        ],
      );

  // ───────────────────────── تبويب قائمة الطعام

  List<Widget> _menuTab() {
    final open = _open;
    if (open == null) {
      return [
        const ImdPanel(
          title: 'قائمة الطعام',
          icon: 'utensils',
          child: ImdEmptyBox('اختر خطة من تبويب «الخطط» لعرض قائمتها'),
        ),
      ];
    }
    final can = Perm.of(context).writable('mealPlans');
    final missingDays = open.span.dates.where((d) => (_persons[d] ?? 0) == 0).length;

    return [
      ImdKpis(children: [
        ImdKpi(label: 'أيام الخطة', value: nf(open.span.days)),
        ImdKpi(label: 'مدخلات الوجبات', value: nf(open.entries.length)),
        ImdKpi(label: 'الأصناف', value: nf(_needs.length)),
        ImdKpi(
          label: 'أيام بلا تفريدة',
          value: nf(missingDays),
          extra: missingDays == 0
              ? null
              : const ImdChip('الاحتياج ناقص', tone: ImdTone.pend),
        ),
      ]),
      if (missingDays > 0)
        ImdNote('يوجد ${nf(missingDays)} يومًا بلا قوة مسجّلة في التفريدة. '
            'احتياج تلك الأيام يُحسب **صفرًا** لا تقديرًا — سجّل التفريدة ليكتمل '
            'الحساب.'),
      ImdPanel(
        title: 'قائمة الطعام: ${open.plan.name}',
        icon: 'calendar',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final date in open.span.dates) _dayCard(open, date, can),
        ]),
      ),
      ImdPanel(
        title: 'احتياج الخطة من المستودع',
        icon: 'calculator',
        child: ImdTable(
          empty: 'لا احتياج محسوب بعد',
          columns: const [
            ImdCol('الصنف'),
            ImdCol('أيام الظهور', numeric: true),
            ImdCol('الإجمالي بوحدة الأساس', numeric: true),
            ImdCol('الوحدة'),
          ],
          rows: [
            for (final r in _needs)
              [
                Text(r.itemName),
                Text(nf(r.days)),
                Text(nf(r.baseQty), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(r.unitName),
              ],
          ],
        ),
      ),
    ];
  }

  Widget _dayCard(MealPlanFull open, String date, bool can) {
    final dayEntries = open.entries.where((e) => e.entryDate == date).toList();
    final persons = _persons[date] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.imd.subtle,
        border: Border.all(color: context.imd.ring),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(
                '${MealPlanRules.weekdayOf(date)} · ${arDigits(date)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              ImdChip(
                persons > 0 ? 'القوة: ${nf(persons)}' : 'لا تفريدة',
                tone: persons > 0 ? ImdTone.ok : ImdTone.pend,
              ),
            ]),
          ),
          if (can) ...[
            ImdIconButton(
              icon: 'plus-square',
              tooltip: 'إضافة صنف',
              onPressed: () => _addEntry(date),
            ),
            const SizedBox(width: 6),
            ImdIconButton(
              icon: 'copy',
              tooltip: 'نسخ وجبات هذا اليوم إلى يوم آخر',
              onPressed: dayEntries.isEmpty ? null : () => _copyDay(date),
            ),
          ],
        ]),
        if (dayEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('لا وجبات في هذا اليوم',
                style: TextStyle(fontSize: 12.5, color: context.imd.faint)),
          )
        else
          for (final meal in MealType.all)
            if (dayEntries.any((e) => e.mealType == meal))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(MealType.label(meal),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: context.imd.muted)),
                  const SizedBox(height: 4),
                  for (final e in dayEntries.where((e) => e.mealType == meal))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text('${e.itemName} — ${nf(e.qtyPerPerson)} ${e.unitName} للفرد')),
                        if (persons > 0)
                          Text('= ${nf(e.qtyPerPerson * e.factor * persons)} ${e.unitName}',
                              style: TextStyle(fontSize: 12, color: context.imd.muted)),
                        if (can)
                          ImdIconButton(
                            icon: 'trash',
                            tooltip: 'حذف',
                            onPressed: () async {
                              await _repo.deleteEntry(e.id);
                              await _openPlan(open.plan.id);
                            },
                          ),
                      ]),
                    ),
                ]),
              ),
      ]),
    );
  }

  // ───────────────────────── تبويب المقارنة

  List<Widget> _compareTab() {
    return [
      ImdPanel(
        title: 'مقارنة خطتين',
        icon: 'scale',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(children: [
            ImdLabeled(
              'الخطة (أ)',
              ImdSelect<String>(
                hint: 'اختر خطة',
                items: [for (final p in _plans) (p.id, p.name)],
                value: _compareA.isEmpty ? null : _compareA,
                onChanged: (v) => setState(() => _compareA = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'الخطة (ب)',
              ImdSelect<String>(
                hint: 'اختر خطة',
                items: [for (final p in _plans) (p.id, p.name)],
                value: _compareB.isEmpty ? null : _compareB,
                onChanged: (v) => setState(() => _compareB = v ?? ''),
              ),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          const ImdNote('المقارنة على **الكمية للفرد** لا على الإجمالي: الإجمالي '
              'يتبدّل بتبدّل القوة، فمقارنته تخلط تغيّر القائمة بتغيّر العدد.'),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
              label: 'قارن',
              icon: 'scale',
              busy: _busy,
              onPressed:
                  _compareA.isEmpty || _compareB.isEmpty || _compareA == _compareB
                      ? null
                      : _compare,
            ),
          ),
        ]),
      ),
      if (_diffs.isNotEmpty)
        ImdPanel(
          title: 'الفروق',
          icon: 'list',
          child: ImdTable(
            empty: 'لا فروق',
            minWidth: 640,
            columns: const [
              ImdCol('الصنف'),
              ImdCol('الخطة (أ)', numeric: true),
              ImdCol('الخطة (ب)', numeric: true),
              ImdCol('الفرق', numeric: true),
              ImdCol('التغير'),
            ],
            rows: [
              for (final d in _diffs)
                [
                  Text(d.itemName),
                  Text(nf(d.qtyA)),
                  Text(nf(d.qtyB)),
                  Text(
                    '${d.delta > 0 ? '+' : ''}${nf(d.delta)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: d.delta == 0
                          ? context.imd.muted
                          : (d.delta > 0 ? context.imd.danger : context.imd.success),
                    ),
                  ),
                  if (d.onlyInB)
                    const ImdChip('صنف جديد', tone: ImdTone.info)
                  else if (d.onlyInA)
                    const ImdChip('أُسقط', tone: ImdTone.err)
                  else
                    Text('${d.pct > 0 ? '+' : ''}${nf(d.pct)}٪'),
                ],
            ],
          ),
        ),
    ];
  }

  static ImdTone _tone(String status) => switch (status) {
        MealPlanStatus.active => ImdTone.ok,
        MealPlanStatus.draft => ImdTone.off,
        MealPlanStatus.archived => ImdTone.code,
        _ => ImdTone.off,
      };
}
