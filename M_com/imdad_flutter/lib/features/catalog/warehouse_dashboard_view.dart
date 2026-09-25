import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_bulk.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/warehouse_limits_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/warehouse_limits.dart';
import '../inventory/doc_kit.dart';

/// لوحة المستودع: ما تحت حدّه الأدنى وما فوق أعلاه، ومنها تُضبط الحدود دفعةً.
///
/// كانت لوحةَ معسكرات، والمعسكر جهةٌ مستفيدة لا مكان تخزين: الرصيد الذي
/// يُقارَن بالحد يقع في مستودع، ومن المستودع يُطلب التعويض. فصارت اللوحة
/// حيث يقع الرصيد، تبويبًا داخل شاشة المستودعات لا شاشةً منفصلة يُبحث عنها.
class WarehouseDashboardView extends StatefulWidget {
  const WarehouseDashboardView({super.key, required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  State<WarehouseDashboardView> createState() => _WarehouseDashboardViewState();
}

/// سطر حدود قيد الإدخال.
class _LimitDraft {
  _LimitDraft({this.itemId = '', this.unit = '', double? min, double? max})
      : min = TextEditingController(text: _num(min)),
        max = TextEditingController(text: _num(max));

  String itemId;

  /// وحدة الإدخال — فارغة تعني وحدة الأساس.
  String unit;
  final TextEditingController min;
  final TextEditingController max;

  static String _num(double? v) =>
      v == null || v == 0 ? '' : (v == v.roundToDouble() ? '${v.toInt()}' : '$v');

  double get minV => double.tryParse(min.text.trim()) ?? 0;
  double get maxV => double.tryParse(max.text.trim()) ?? 0;

  void dispose() {
    min.dispose();
    max.dispose();
  }
}

class _WarehouseDashboardViewState extends State<WarehouseDashboardView> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final WarehouseLimitsRepo _repo = WarehouseLimitsRepo(_db);

  List<Item> _items = const [];
  List<WarehouseLimitRow> _rows = const [];
  final List<_LimitDraft> _drafts = [];

  String _warehouse = '';
  String _statusFilter = '';
  bool _loading = true;
  bool _busy = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final items = await CatalogRepo(_db).items();
    if (!mounted) return;
    final main = widget.warehouses.where((w) => w.isMain).firstOrNull;
    setState(() {
      _items = items;
      _warehouse = main?.name ?? (widget.warehouses.firstOrNull?.name ?? '');
      _loading = false;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_warehouse.isEmpty) {
      setState(() => _rows = const []);
      return;
    }
    setState(() => _busy = true);
    final rows = await _repo.dashboard(_warehouse);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _busy = false;
    });
  }

  Item? _item(String id) => _items.where((i) => i.id == id).firstOrNull;

  /// وحدات الصنف: وحدة الأساس أولًا ثم بقية وحدات التعامل.
  List<ItemUnit> _unitsOf(String itemId) {
    final it = _item(itemId);
    if (it == null) return const [];
    final units = unitsOfItem(it);
    if (units.isEmpty) {
      return [ItemUnit(name: it.baseUnit, factor: 1, isBase: true)];
    }
    return units;
  }

  double _factorOf(String itemId, String unit) {
    final units = _unitsOf(itemId);
    final match = units.where((u) => u.name == unit).firstOrNull;
    return match?.factor ?? 1;
  }

  // ───────────────────────── الإدخال الجماعي

  void _startEditing() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts.clear();
    // الحدود القائمة تُفتح للتعديل بالوحدة التي أُدخلت بها، لا بوحدة الأساس:
    // من ضبط «٤ شوالات» يراها أربعة لا مئتين.
    for (final r in _rows) {
      _drafts.add(_LimitDraft(
        itemId: r.limit.itemId,
        unit: r.unitName,
        min: r.min,
        max: r.max,
      ));
    }
    if (_drafts.isEmpty) _drafts.add(_LimitDraft());
    setState(() => _editing = true);
  }

  void _cancelEditing() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts.clear();
    setState(() => _editing = false);
  }

  void _addRow() => setState(() => _drafts.add(_LimitDraft()));

  void _removeRow(int i) => setState(() => _drafts.removeAt(i).dispose());

  void _duplicateRow(int i) {
    final src = _drafts[i];
    setState(() => _drafts.insert(
          i + 1,
          _LimitDraft(unit: src.unit, min: src.minV, max: src.maxV),
        ));
  }

  /// خطأ كل سطر على حدة — يُعرض تحته لا في رسالة واحدة أعلى الشاشة.
  Map<int, String> get _rowErrors {
    final out = <int, String>{};
    final seen = <String, int>{};
    for (var i = 0; i < _drafts.length; i++) {
      final d = _drafts[i];
      final error = WarehouseLimits.validate(
          itemId: d.itemId, min: d.minV, max: d.maxV);
      if (error != null) {
        out[i] = error;
        continue;
      }
      final first = seen[d.itemId];
      if (first != null) {
        out[i] = 'مكرر مع السطر ${first + 1} — ادمجهما';
      } else {
        seen[d.itemId] = i;
      }
    }
    return out;
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'stores', PermAction.edit)) return;
    final errors = _rowErrors;
    if (errors.isNotEmpty) {
      showImdToast(context, '✖ راجع ${nf(errors.length)} سطرًا فيه خطأ',
          error: true);
      return;
    }
    final wh = widget.warehouses.where((w) => w.name == _warehouse).firstOrNull;
    if (wh == null) return;

    setState(() => _busy = true);
    final res = await _repo.saveBatch(
      warehouseId: wh.id,
      warehouseName: wh.name,
      rows: [
        for (final d in _drafts)
          LimitInput(
            itemId: d.itemId,
            itemName: _item(d.itemId)?.name ?? '',
            unitName: d.unit.isEmpty ? (_item(d.itemId)?.baseUnit ?? '') : d.unit,
            factor: _factorOf(d.itemId, d.unit),
            min: d.minV,
            max: d.maxV,
          ),
      ],
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ حُفظ ${nf(res.saved)} حدًّا' : res.error,
        error: !res.ok);
    if (res.ok) {
      _cancelEditing();
      await _load();
    }
  }

  Future<void> _delete(WarehouseLimitRow row) async {
    if (!Perm.of(context).guard(context, 'stores', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف حد «${row.limit.itemName}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.delete(row.limit.id,
        actor: context.read<AuthService>().currentUser?.email ?? '');
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذف الحد' : res.error, error: !res.ok);
    if (res.ok) await _load();
  }

  // ───────────────────────── العرض

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ImdLd('⏳ جارٍ التحميل…');
    if (widget.warehouses.isEmpty) {
      return const ImdEmptyBox('عرّف مستودعًا أولًا لتضبط حدوده');
    }
    final can = Perm.of(context).writable('stores');
    final low = _rows.where((r) => r.status == LimitStatus.low).length;
    final over = _rows.where((r) => r.status == LimitStatus.over).length;
    final ok = _rows.where((r) => r.status == LimitStatus.ok).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdKpis(children: [
        ImdKpi(label: 'أصناف لها حدود', value: nf(_rows.length)),
        ImdKpi(
          label: 'تحت الأدنى',
          value: nf(low),
          extra: low == 0
              ? null
              : const ImdChip('يحتاج تعويضًا', tone: ImdTone.err),
        ),
        ImdKpi(
          label: 'فوق الأعلى',
          value: nf(over),
          extra: over == 0
              ? null
              : const ImdChip('مخزون راكد', tone: ImdTone.pend),
        ),
        ImdKpi(label: 'ضمن الحدود', value: nf(ok)),
      ]),
      ImdICard(
        child: ImdF2(children: [
          ImdLabeled(
            'المستودع',
            ImdSelect<String>(
              items: [
                for (final w in widget.warehouses)
                  (w.name, w.isMain ? '${w.name} — رئيسي' : w.name),
              ],
              value: _warehouse,
              onChanged: (v) {
                setState(() => _warehouse = v ?? '');
                _cancelEditing();
                _load();
              },
            ),
            size: 11,
          ),
          ImdLabeled(
            'الحالة',
            ImdSelect<String>(
              items: const [
                ('', 'الكل'),
                ('low', 'تحت الأدنى'),
                ('over', 'فوق الأعلى'),
                ('ok', 'ضمن الحدود'),
              ],
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled(
            ' ',
            Wrap(spacing: 10, runSpacing: 8, children: [
              ImdButton.outline(
                  label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
              if (can && !_editing)
                ImdButton.outline(
                  label: _rows.isEmpty ? 'ضبط الحدود' : 'تعديل الحدود دفعةً',
                  icon: 'sliders',
                  small: true,
                  onPressed: _startEditing,
                ),
            ]),
            size: 11,
          ),
        ]),
      ),
      if (_editing) _editor(),
      ImdPanel(
        title: 'حدود مخزون «$_warehouse»',
        icon: 'package',
        child: _busy ? const ImdLd('⏳ جارٍ الحساب…') : _table(can),
      ),
    ]);
  }

  Widget _editor() {
    final errors = _rowErrors;
    final ready = _drafts.length - errors.length;
    return ImdPanel(
      title: 'ضبط الحدود دفعةً — «$_warehouse»',
      icon: 'sliders',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdPrintTip(
            'الحدّان يُكتبان بالوحدة التي تختارها لكل صنف — شوالًا أو كرتونًا '
            'أو حبة — ويُحوّلان لوحدة الأساس عند الحفظ. فتضبط الحد كما تتعامل '
            'به، وتُقارن الأرصدة بلغة واحدة. واترك حدًّا فارغًا إن لم ترد ضبطه.'),
        const SizedBox(height: 12),
        ImdBulkGrid(
          columns: const [
            ImdBulkCol('الصنف', flex: 5, hint: 'ابحث بالكود أو الاسم'),
            ImdBulkCol('وحدة الإدخال', flex: 2),
            ImdBulkCol('الحد الأدنى', flex: 2, hint: 'دونه يُنبَّه'),
            ImdBulkCol('الحد الأعلى', flex: 2, hint: 'فوقه مخزون راكد'),
            ImdBulkCol('الرصيد الآن', flex: 2),
          ],
          rows: [
            for (var i = 0; i < _drafts.length; i++)
              _draftRow(i, errors[i] ?? ''),
          ],
          onAdd: _addRow,
          onRemove: _removeRow,
          onDuplicate: _duplicateRow,
          addLabel: 'إضافة صنف',
          empty: 'أضف صنفًا لتضبط حدوده',
          summary: [
            ImdChip('السطور: ${nf(_drafts.length)}', tone: ImdTone.code),
            if (errors.isEmpty)
              ImdChip('جاهز للحفظ: ${nf(ready)}', tone: ImdTone.ok)
            else
              ImdChip('أخطاء: ${nf(errors.length)}', tone: ImdTone.err),
          ],
          actions: [
            ImdButton(
              label: 'حفظ الحدود',
              icon: 'check',
              small: true,
              busy: _busy,
              onPressed: errors.isEmpty && _drafts.isNotEmpty ? _save : null,
            ),
            ImdButton.outline(
                label: 'إلغاء', icon: 'x', small: true, onPressed: _cancelEditing),
          ],
        ),
      ]),
    );
  }

  ImdBulkRow _draftRow(int i, String error) {
    final d = _drafts[i];
    final units = _unitsOf(d.itemId);
    final current = _rows.where((r) => r.limit.itemId == d.itemId).firstOrNull;
    final factor = _factorOf(d.itemId, d.unit);
    final balance = current == null
        ? null
        : WarehouseLimits.fromBase(current.balanceBase, factor);

    return ImdBulkRow(
      error: error,
      badge: d.itemId.isEmpty
          ? null
          : ImdChip(_item(d.itemId)?.code ?? '', tone: ImdTone.code),
      cells: [
        ImdItemPicker(
          items: _items,
          value: d.itemId,
          labelOf: (it) => '${it.code} — ${it.name} (${it.baseUnit})',
          onChanged: (v) => setState(() {
            d.itemId = v;
            // الوحدة تعود للأساس عند تبديل الصنف: وحدة صنفٍ آخر لا تعنيه.
            d.unit = '';
          }),
        ),
        ImdSelect<String>(
          items: [
            for (final u in units)
              (u.name, u.isBase ? '${u.name} (أساس)' : '${u.name} ×${nf(u.factor)}'),
          ],
          value: units.any((u) => u.name == d.unit)
              ? d.unit
              : (units.firstOrNull?.name ?? ''),
          onChanged: (v) => setState(() => d.unit = v ?? ''),
        ),
        ImdFld(
            controller: d.min,
            number: true,
            hint: '—',
            onChanged: (_) => setState(() {})),
        ImdFld(
            controller: d.max,
            number: true,
            hint: '—',
            onChanged: (_) => setState(() {})),
        ImdReadonlyField(
          text: balance == null ? '—' : '${nf(balance)} ${d.unit.isEmpty ? (_item(d.itemId)?.baseUnit ?? '') : d.unit}',
        ),
      ],
    );
  }

  Widget _table(bool can) {
    final c = context.imd;
    final rows = _rows.where((r) {
      return switch (_statusFilter) {
        'low' => r.status == LimitStatus.low,
        'over' => r.status == LimitStatus.over,
        'ok' => r.status == LimitStatus.ok,
        _ => true,
      };
    }).toList();

    return ImdTable(
      empty: _rows.isEmpty
          ? 'لا حدود مضبوطة في هذا المستودع — اضغط «ضبط الحدود»'
          : 'لا صنف بهذه الحالة',
      minWidth: 880,
      columns: const [
        ImdCol('الكود'),
        ImdCol('الصنف'),
        ImdCol('الوحدة'),
        ImdCol('الأدنى', numeric: true),
        ImdCol('الرصيد', numeric: true),
        ImdCol('الأعلى', numeric: true),
        ImdCol('الامتلاء'),
        ImdCol('الحالة'),
        ImdCol('الإجراء المطلوب'),
        ImdCol('', center: true),
      ],
      rows: [
        for (final r in rows)
          [
            Text(r.item?.code ?? '—',
                style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text(r.limit.itemName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(r.unitName),
            Text(r.limit.minStock > 0 ? nf(r.min) : '—'),
            Text(nf(r.balance),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: switch (r.status) {
                    LimitStatus.low => c.danger,
                    LimitStatus.over => c.warn,
                    _ => c.text,
                  },
                )),
            Text(r.limit.maxStock > 0 ? nf(r.max) : '—'),
            _fillBar(r),
            ImdChip(r.status.label, tone: _tone(r.status)),
            // الرقم وحده لا يقول ماذا أفعل: «ينقصه ٨ شوالات» يقوله.
            Text(
              switch (r.status) {
                LimitStatus.low => 'حوّل ${nf(r.shortfall)} ${r.unitName}',
                LimitStatus.over => 'فائض ${nf(r.surplus)} ${r.unitName}',
                _ => '—',
              },
              style: TextStyle(
                  fontSize: 12.5,
                  color: r.status == LimitStatus.low ? c.danger : c.muted),
            ),
            if (can)
              ImdIconButton(
                  icon: 'trash',
                  tooltip: 'حذف الحد',
                  onPressed: () => _delete(r))
            else
              const SizedBox.shrink(),
          ],
      ],
    );
  }

  /// شريط الامتلاء: الفرق بين «قارب الامتلاء» و«تجاوز» لا يظهر في رقم.
  Widget _fillBar(WarehouseLimitRow r) {
    final c = context.imd;
    final ratio = r.fillRatio;
    if (ratio == null) {
      return Text('—', style: TextStyle(color: c.muted));
    }
    final clamped = ratio.clamp(0.0, 1.0);
    final color = switch (r.status) {
      LimitStatus.low => c.danger,
      LimitStatus.over => c.warn,
      _ => c.success,
    };
    return SizedBox(
      width: 96,
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 7,
              backgroundColor: c.subtle,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${(ratio * 100).round()}%',
            style: TextStyle(fontSize: 11, color: c.muted)),
      ]),
    );
  }

  static ImdTone _tone(LimitStatus s) => switch (s) {
        LimitStatus.low => ImdTone.err,
        LimitStatus.over => ImdTone.pend,
        LimitStatus.ok => ImdTone.ok,
        LimitStatus.none => ImdTone.off,
      };
}
