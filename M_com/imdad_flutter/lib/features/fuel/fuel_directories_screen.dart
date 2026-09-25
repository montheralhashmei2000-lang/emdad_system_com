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
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';

/// دليل مستودعات المحروقات — مستقلٌّ عن مخازن الإعاشة.
///
/// **خزّان الوقود ليس مخزنًا للإعاشة.** له سعةٌ باللتر وموقعٌ يُشترط فيه البعد
/// عن السكن، ويمسكه أمينٌ غير أمين المستودع. وجمعُ الاثنين في دليلٍ واحد
/// يُدخل مخزن الطحين في قائمة «من أين نصرف الديزل؟».
class FuelWarehousesScreen extends StatefulWidget {
  const FuelWarehousesScreen({super.key});

  @override
  State<FuelWarehousesScreen> createState() => _FuelWarehousesScreenState();
}

class _FuelWarehousesScreenState extends State<FuelWarehousesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _items = const [];
  List<FuelStock> _stocks = const [];

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _location = TextEditingController();
  final _capacity = TextEditingController();
  final _notes = TextEditingController();

  String? _editId;
  bool _active = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _manager, _location, _capacity, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _repo.warehouses();
    final stocks = await _repo.stocks();
    if (!mounted) return;
    setState(() {
      _items = items;
      _stocks = stocks;
      _loading = false;
    });
  }

  void _reset() {
    for (final c in [_code, _name, _manager, _location, _capacity, _notes]) {
      imdSetText(c, '');
    }
    setState(() {
      _editId = null;
      _active = true;
    });
  }

  void _edit(FuelWarehouse w) {
    imdSetText(_code, w.code);
    imdSetText(_name, w.name);
    imdSetText(_manager, w.manager);
    imdSetText(_location, w.location);
    imdSetText(_capacity, w.capacityLiters == 0 ? '' : _num(w.capacityLiters));
    imdSetText(_notes, w.notes);
    setState(() {
      _editId = w.id;
      _active = w.active;
    });
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelWarehouses',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    final res = await _repo.saveWarehouse(
      id: _editId,
      name: _name.text,
      code: _code.text,
      manager: _manager.text,
      location: _location.text,
      capacityLiters: double.tryParse(_capacity.text.trim()) ?? 0,
      active: _active,
      notes: _notes.text,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُفظ المستودع' : res.error,
        error: !res.ok);
    if (res.ok) {
      _reset();
      await _load();
    }
  }

  Future<void> _delete(FuelWarehouse w) async {
    if (!Perm.of(context).guard(context, 'fuelWarehouses', PermAction.delete)) {
      return;
    }
    if (!await imdConfirm(context, 'حذف مستودع «${w.name}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.deleteWarehouse(w.id,
        actor: context.read<AuthService>().currentUser?.email ?? '');
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذف المستودع' : res.error,
        error: !res.ok);
    if (res.ok) {
      if (_editId == w.id) _reset();
      await _load();
    }
  }

  double _stockOf(String name) => _stocks
      .where((s) => s.warehouse == name)
      .fold<double>(0, (sum, s) => sum + s.stock);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'مستودعات المحروقات', icon: 'warehouse'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelWarehouses');
    final active = _items.where((w) => w.active).length;
    final capacity =
        _items.fold<double>(0, (sum, w) => sum + w.capacityLiters);

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'مستودعات المحروقات',
        icon: 'warehouse',
        subtitle: 'خزّانات الوقود وسعاتها — دليلٌ مستقل عن مخازن الإعاشة',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'المستودعات', value: nf(_items.length)),
        ImdKpi(label: 'مفعَّلة', value: nf(active)),
        ImdKpi(
            label: 'إجمالي السعة',
            value: '${nf(capacity)} ${Fuel.unit}'),
        ImdKpi(
            label: 'الرصيد الكلي',
            value:
                '${nf(_stocks.fold<double>(0, (s, x) => s + x.stock))} ${Fuel.unit}'),
      ]),
      if (can)
        ImdPanel(
          title: _editId == null ? 'إضافة مستودع' : 'تعديل مستودع',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled('الكود', ImdFld(controller: _code), size: 11),
              ImdLabeled('اسم المستودع *', ImdFld(controller: _name), size: 11),
              ImdLabeled('المسؤول', ImdFld(controller: _manager), size: 11),
              ImdLabeled('الموقع', ImdFld(controller: _location), size: 11),
              ImdLabeled(
                'السعة (${Fuel.unit})',
                ImdFld(controller: _capacity, number: true, hint: 'اتركها فارغة إن لم تُعرف'),
                size: 11,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
            const SizedBox(height: 10),
            ImdCheckbox(
              value: _active,
              label: 'مفعَّل — يظهر في شاشات الحركة',
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 10),
            const ImdNote(
              'السعة هي ما تُحسب منه نسبة الإشغال وتنبيهات النفاد والامتلاء. '
              'وبدونها يعمل المستودع، لكن لا تنبيه له.',
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              ImdButton(
                  label: _editId == null ? 'إضافة' : 'حفظ التعديل',
                  icon: 'check',
                  onPressed: _save),
              if (_editId != null)
                ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: _reset),
            ]),
          ]),
        ),
      ImdPanel(title: 'المستودعات', icon: 'list', child: _table(can)),
    ]);
  }

  Widget _table(bool can) {
    final c = context.imd;
    return ImdTable(
      empty: 'لا مستودعات محروقات — أضف أول خزّان',
      minWidth: 880,
      columns: const [
        ImdCol('الكود'),
        ImdCol('المستودع'),
        ImdCol('المسؤول'),
        ImdCol('الموقع'),
        ImdCol('السعة', numeric: true),
        ImdCol('الرصيد', numeric: true),
        ImdCol('الحالة'),
        ImdCol('', center: true),
      ],
      rows: [
        for (final w in _items)
          [
            Text(w.code.isEmpty ? '—' : w.code,
                style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(w.manager.isEmpty ? '—' : w.manager),
            Text(w.location.isEmpty ? '—' : w.location),
            Text(w.capacityLiters == 0 ? '—' : nf(w.capacityLiters)),
            Text('${nf(_stockOf(w.name))} ${Fuel.unit}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            w.active
                ? const ImdChip('مفعَّل', tone: ImdTone.ok)
                : const ImdChip('معطَّل', tone: ImdTone.off),
            if (can)
              Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                ImdIconButton(
                    icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(w)),
                ImdIconButton(
                    icon: 'trash', tooltip: 'حذف', onPressed: () => _delete(w)),
              ])
            else
              const SizedBox.shrink(),
          ],
      ],
    );
  }
}

/// دليل الوحدات المستفيدة من المحروقات.
///
/// **مستفيد الوقود ليس مستفيد الإعاشة**: تلك وحداتٌ لها قوةٌ تُطعَم، وهذه
/// جهاتٌ لها مركباتٌ تُزوَّد — وقد تكون ورشةً أو مولّدًا أو رتلًا عابرًا لا
/// قوة له أصلًا.
class FuelUnitsScreen extends StatefulWidget {
  const FuelUnitsScreen({super.key});

  @override
  State<FuelUnitsScreen> createState() => _FuelUnitsScreenState();
}

class _FuelUnitsScreenState extends State<FuelUnitsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelUnit> _items = const [];
  List<FuelAllocationRow> _allocations = const [];

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _commander = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  String? _editId;
  bool _active = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _commander, _phone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _repo.units();
    final allocations = await _repo.allocations();
    if (!mounted) return;
    setState(() {
      _items = items;
      _allocations = allocations;
      _loading = false;
    });
  }

  void _reset() {
    for (final c in [_code, _name, _commander, _phone, _notes]) {
      imdSetText(c, '');
    }
    setState(() {
      _editId = null;
      _active = true;
    });
  }

  void _edit(FuelUnit u) {
    imdSetText(_code, u.code);
    imdSetText(_name, u.name);
    imdSetText(_commander, u.commander);
    imdSetText(_phone, u.phone);
    imdSetText(_notes, u.notes);
    setState(() {
      _editId = u.id;
      _active = u.active;
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelUnits',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    final res = await _repo.saveUnit(
      id: _editId,
      name: _name.text,
      code: _code.text,
      commander: _commander.text,
      phone: _phone.text,
      active: _active,
      notes: _notes.text,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُفظت الوحدة' : res.error, error: !res.ok);
    if (res.ok) {
      _reset();
      await _load();
    }
  }

  Future<void> _delete(FuelUnit u) async {
    if (!Perm.of(context).guard(context, 'fuelUnits', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف وحدة «${u.name}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.deleteUnit(u.id,
        actor: context.read<AuthService>().currentUser?.email ?? '');
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذفت الوحدة' : res.error, error: !res.ok);
    if (res.ok) {
      if (_editId == u.id) _reset();
      await _load();
    }
  }

  int _allocationsOf(String id) =>
      _allocations.where((a) => a.allocation.unitId == id).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'وحدات المحروقات', icon: 'users'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelUnits');
    final active = _items.where((u) => u.active).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'وحدات المحروقات',
        icon: 'users',
        subtitle: 'الجهات التي يُصرف لها الوقود — دليلٌ مستقل عن وحدات الإعاشة',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'الوحدات', value: nf(_items.length)),
        ImdKpi(label: 'مفعَّلة', value: nf(active)),
        ImdKpi(label: 'لها تفريدة', value: nf(_allocations.length)),
      ]),
      if (can)
        ImdPanel(
          title: _editId == null ? 'إضافة وحدة' : 'تعديل وحدة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled('الكود', ImdFld(controller: _code), size: 11),
              ImdLabeled('اسم الوحدة *', ImdFld(controller: _name), size: 11),
              ImdLabeled('القائد / المسؤول',
                  ImdFld(controller: _commander), size: 11),
              ImdLabeled('الهاتف', ImdFld(controller: _phone), size: 11),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
            const SizedBox(height: 10),
            ImdCheckbox(
              value: _active,
              label: 'مفعَّلة — تظهر عند إنشاء التفريدة',
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              ImdButton(
                  label: _editId == null ? 'إضافة' : 'حفظ التعديل',
                  icon: 'check',
                  onPressed: _save),
              if (_editId != null)
                ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: _reset),
            ]),
          ]),
        ),
      ImdPanel(
        title: 'الوحدات',
        icon: 'list',
        child: ImdTable(
          empty: 'لا وحدات — أضف أول جهة تُزوَّد بالوقود',
          minWidth: 780,
          columns: const [
            ImdCol('الكود'),
            ImdCol('الوحدة'),
            ImdCol('القائد'),
            ImdCol('الهاتف'),
            ImdCol('تفريداتها', numeric: true),
            ImdCol('الحالة'),
            ImdCol('', center: true),
          ],
          rows: [
            for (final u in _items)
              [
                Text(u.code.isEmpty ? '—' : u.code,
                    style: TextStyle(color: context.imd.muted, fontSize: 12.5)),
                Text(u.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(u.commander.isEmpty ? '—' : u.commander),
                Text(u.phone.isEmpty ? '—' : u.phone),
                Text(nf(_allocationsOf(u.id))),
                u.active
                    ? const ImdChip('مفعَّلة', tone: ImdTone.ok)
                    : const ImdChip('معطَّلة', tone: ImdTone.off),
                if (can)
                  Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                    ImdIconButton(
                        icon: 'edit',
                        tooltip: 'تعديل',
                        onPressed: () => _edit(u)),
                    ImdIconButton(
                        icon: 'trash',
                        tooltip: 'حذف',
                        onPressed: () => _delete(u)),
                  ])
                else
                  const SizedBox.shrink(),
              ],
          ],
        ),
      ),
    ]);
  }
}
