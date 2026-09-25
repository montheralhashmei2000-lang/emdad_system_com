import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../domain/access_control.dart';
import '../inventory/doc_kit.dart';

/// سجل التشغيل والطهي اليومي — نقل `renderKitchenLog()`:
/// تبويب تسجيل استهلاك وجبة (بيانات الوجبة + سطور الأصناف مع مقارنة فورية بالمقرر)،
/// وتبويب السجل والمقارنات (بطاقات مجمّعة بالمطبخ + التاريخ + الوجبة).
/// القوة المستفيدة تُحسب للمطبخ بتاريخ اليوم المحدد وحده.
class KitchenLogScreen extends StatefulWidget {
  const KitchenLogScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<KitchenLogScreen> createState() => _KitchenLogScreenState();
}

/// أسماء الوجبات — بلا رموز تعبيرية لأن القوائم المنسدلة تعرض نصًا عاديًا.
const Map<String, String> _meals = {
  'BREAKFAST': 'فطور',
  'LUNCH': 'غداء',
  'DINNER': 'عشاء',
};

class _Row {
  _Row();
  String itemId = '';
  String unitName = '';
  final qty = TextEditingController();

  void dispose() => qty.dispose();
}

class _KitchenLogScreenState extends State<KitchenLogScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final DailyRepo _daily = DailyRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _notes = TextEditingController();
  final _histQ = TextEditingController();
  final List<_Row> _rows = [_Row()];

  List<Item> _items = const [];
  List<Facility> _facilities = const [];
  List<Entitlement> _entitlements = const [];
  List<KitchenLog> _hist = const [];

  String _tab = 'form';
  String _date = imdToday();
  String _facilityId = '';
  String _meal = 'LUNCH';
  double _strength = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    _histQ.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _writable => _perm.admin || _perm.manage('kitchenLog');

  /// `klogFetchAll()`
  Future<void> _load() async {
    final items = await _catalog.items();
    final facilities = await _catalog.facilities();
    final ents = await _daily.entitlements();
    final hist = await _daily.kitchenLogs();
    if (!mounted) return;
    setState(() {
      _items = items;
      _facilities = facilities;
      _entitlements = ents;
      _hist = hist;
      _loading = false;
    });
    await _refreshStrength();
  }

  /// `klogRefreshStrength()`
  Future<void> _refreshStrength() async {
    if (_facilityId.isEmpty || _date.isEmpty) {
      setState(() => _strength = 0);
      return;
    }
    final calc = await _daily.calculator();
    if (!mounted) return;
    setState(() => _strength = calc.facilityStrengthOn(_facilityId, _date));
  }

  Item? _itemById(String id) {
    for (final it in _items) {
      if (it.id == id) return it;
    }
    return null;
  }

  Entitlement? _entOf(String itemId) {
    for (final e in _entitlements) {
      if (e.itemId == itemId) return e;
    }
    return null;
  }

  List<ItemUnit> _unitsOf(Item? it) =>
      it == null ? const [ItemUnit(name: '—', factor: 1)] : _catalog.unitsOf(it);

  double _factorOf(Item? it, String unitName) {
    for (final u in _unitsOf(it)) {
      if (u.name == unitName) return u.factor <= 0 ? 1 : u.factor;
    }
    return 1;
  }

  /// المقرر اليومي بوحدة الأساس = (المقرر الشهري ÷ 30) × القوة — `entBaseQty(ent,it)/30*strength`.
  double _expectedBase(Entitlement e) =>
      (e.qtyPerPerson * (e.measureFactor <= 0 ? 1 : e.measureFactor)) / 30.0 * _strength;

  /// `klogCalcRow(rowEl)` — نص المقارنة تحت اختيار الصنف.
  (String text, Color? color) _rowMeta(_Row r) {
    final it = _itemById(r.itemId);
    if (it == null) return ('', null);
    final factor = _factorOf(it, r.unitName);
    final actualBase = (double.tryParse(r.qty.text.trim()) ?? 0) * factor;
    final ent = _entOf(r.itemId);
    if (ent == null || ent.qtyPerPerson == 0 || _strength == 0) {
      return ('المستهلك: ${nf(actualBase)} ${it.baseUnit} (لا يوجد مقرر/قوة لمقارنته)', null);
    }
    final expected = _expectedBase(ent);
    final diff = actualBase - expected;
    final pct = expected == 0 ? 0.0 : (diff / expected * 1000).round() / 10;
    final c = context.imd;
    return (
      'المقرر: ${nf((expected * 100).round() / 100)} ${it.baseUnit} — '
          'الفرق: ${diff > 0 ? '+' : ''}${nf((diff * 100).round() / 100)} (${nf(pct)}%)',
      diff > 0 ? c.danger : (diff < 0 ? c.accent : null),
    );
  }

  /// `klogSave()`
  Future<void> _save() async {
    if (!_perm.guard(context, 'kitchenLog', PermAction.create)) return;
    if (_facilityId.isEmpty) {
      showImdToast(context, '✖ اختر المطبخ/الفرن', error: true);
      return;
    }
    if (_date.isEmpty) {
      showImdToast(context, '✖ اختر التاريخ', error: true);
      return;
    }
    final fac = _facilities.where((f) => f.id == _facilityId).firstOrNull;
    final out = <(_Row, Item, double, double)>[];
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _itemById(r.itemId)!;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) {
        showImdToast(context, '✖ أدخل كمية مستهلكة صالحة للصنف ${it.name}', error: true);
        return;
      }
      final factor = _factorOf(it, r.unitName);
      out.add((r, it, qty, qty * factor));
    }
    if (out.isEmpty) {
      showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل', error: true);
      return;
    }

    setState(() => _saving = true);
    await _db.transaction(() async {
      for (final (r, it, qty, baseQty) in out) {
        final ent = _entOf(it.id);
        await _daily.saveKitchenLog(
          facilityId: _facilityId,
          facilityName: fac?.name ?? '',
          date: _date,
          mealType: _meal,
          strength: _strength,
          itemId: it.id,
          itemName: it.name,
          unitName: r.unitName,
          qty: qty,
          baseQty: baseQty,
          expectedBase: (ent == null || ent.qtyPerPerson == 0 || _strength == 0) ? 0 : _expectedBase(ent),
          notes: _notes.text.trim(),
        );
      }
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..add(_Row());
      _notes.clear();
    });
    showImdToast(context, '✔ حُفظ سجل استهلاك الوجبة');
    await _load();
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      if (!widget.embedded)
        const ImdPageTitle(
          title: 'سجل التشغيل والطهي اليومي',
          icon: 'utensils',
          subtitle:
              'تسجيل الكميات المستهلكة فعليًا لكل وجبة ومقارنتها بنسب الاستحقاق المعتمدة '
              'لكشف الهدر أو التوفير',
        ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('form', 'تسجيل استهلاك وجبة', icon: 'file'),
          ImdTab('hist', 'السجل والمقارنات', icon: 'clipboard'),
        ],
      ),
      const SizedBox(height: 12),
      if (_loading)
        const ImdLd('⏳ جارٍ التحميل…')
      else if (_tab == 'form')
        _form()
      else
        _history(),
    ];
    return widget.embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          )
        : ImdPage(children: content);
  }

  Widget _form() {
    if (!_writable) {
      return const ImdICard(
        title: 'عرض فقط',
        icon: 'eye',
        child: ImdLd('تسجيل الاستهلاك متاح لمدير النظام'),
      );
    }
    if (_facilities.isEmpty) {
      return const ImdICard(
        child: ImdLd('لا مطابخ/أفران مسجلة — أضفها من شاشة «المطابخ والأفران»'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdICard(
        title: 'بيانات الوجبة',
        icon: 'clipboard',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdF2(cols: 4, children: [
            ImdLabeled(
              'المطبخ/الفرن *',
              ImdSelect<String>(
                hint: '— اختر المطبخ/الفرن —',
                items: [for (final f in _facilities) (f.id, f.name)],
                value: _facilityId,
                onChanged: (v) async {
                  setState(() => _facilityId = v ?? '');
                  await _refreshStrength();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'التاريخ',
              ImdDateField(
                value: _date,
                onChanged: (v) async {
                  setState(() => _date = v);
                  await _refreshStrength();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'الوجبة',
              ImdSelect<String>(
                items: [for (final e in _meals.entries) (e.key, e.value)],
                value: _meal,
                onChanged: (v) => setState(() => _meal = v ?? _meal),
              ),
              size: 11,
            ),
            ImdLabeled(
              'القوة المستفيدة (تلقائي)',
              ImdReadonlyField(text: nf(_strength), color: context.imd.accent),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes), size: 11),
        ]),
      ),
      for (final r in _rows) _lineRow(r),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
          label: 'سطر صنف جديد',
          icon: 'plus',
          small: true,
          onPressed: () => setState(() => _rows.add(_Row())),
        ),
      ),
      const SizedBox(height: 10),
      ImdButton(
        label: 'حفظ سجل الاستهلاك',
        icon: 'check',
        expand: true,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    ]);
  }

  /// `.rvrow` + `.rgrid` — الصنف (ومعه سطر المقارنة)، الوحدة، الكمية، زر الحذف.
  Widget _lineRow(_Row r) {
    final it = _itemById(r.itemId);
    final units = _unitsOf(it);
    if (r.unitName.isEmpty && it != null) {
      r.unitName = units.firstWhere((u) => u.isBase, orElse: () => units.first).name;
    }
    final (meta, metaColor) = _rowMeta(r);

    return ImdRvRow(
      child: LayoutBuilder(builder: (context, cons) {
        final narrow = cons.maxWidth < 680;
        const delW = 46.0;
        final w = narrow ? cons.maxWidth : (cons.maxWidth - delW - 8 * 3) / 3;
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.start, children: [
          SizedBox(
            width: narrow ? cons.maxWidth : w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const ImdRowLabel('الصنف'),
              ImdItemPicker(
                items: _items,
                value: r.itemId,
                onChanged: (id) => setState(() {
                  r.itemId = id;
                  final us = _unitsOf(_itemById(id));
                  r.unitName = us.firstWhere((u) => u.isBase, orElse: () => us.first).name;
                  // سطر جديد تلقائيًا عند اختيار الصنف في آخر سطر (كما في `onSel`).
                  if (_rows.last == r) _rows.add(_Row());
                }),
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    meta,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: metaColor == null ? FontWeight.w500 : FontWeight.w900,
                      color: metaColor ?? context.imd.muted,
                    ),
                  ),
                ),
            ]),
          ),
          SizedBox(
            width: narrow ? (cons.maxWidth - delW - 8) / 2 : w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const ImdRowLabel('الوحدة'),
              ImdSelect<String>(
                items: [for (final u in units) (u.name, u.name)],
                value: r.unitName,
                onChanged: (v) => setState(() => r.unitName = v ?? r.unitName),
              ),
            ]),
          ),
          SizedBox(
            width: narrow ? (cons.maxWidth - delW - 8) / 2 : w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const ImdRowLabel('الكمية المستهلكة فعليًا'),
              ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: ImdIconButton(
              icon: 'x',
              kind: ImdBtnKind.danger,
              tooltip: 'حذف السطر',
              onPressed: () => setState(() {
                _rows.remove(r);
                r.dispose();
                if (_rows.isEmpty) _rows.add(_Row());
              }),
            ),
          ),
        ]);
      }),
    );
  }

  /// `klogHist()` — بطاقات مجمّعة بـ (المطبخ + التاريخ + الوجبة).
  Widget _history() {
    final q = _histQ.text.trim().toLowerCase();
    final groups = <String, List<KitchenLog>>{};
    for (final r in _hist) {
      if (q.isNotEmpty &&
          !r.facilityName.toLowerCase().contains(q) &&
          !r.itemName.toLowerCase().contains(q)) {
        continue;
      }
      groups.putIfAbsent('${r.facilityId}|${r.date}|${r.mealType}', () => []).add(r);
    }

    return ImdICard(
      title: 'سجل الاستهلاك اليومي ومقارنته بالمقرر',
      icon: 'clipboard',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdFld(controller: _histQ, hint: 'المطبخ أو الصنف…', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const ImdLd('لا سجلات مطابقة')
        else
          for (final g in groups.values) _histCard(g),
      ]),
    );
  }

  Widget _histCard(List<KitchenLog> g) {
    final c = context.imd;
    final f = g.first;
    final totVar = g.fold<double>(0, (a, x) => a + x.varianceBase);
    return ImdDocCard(
      head: [
        Text(f.facilityName.isEmpty ? '—' : f.facilityName,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        ImdChip(f.date, tone: ImdTone.off),
        ImdChip(_meals[f.mealType] ?? f.mealType, tone: ImdTone.code),
        ImdChip('قوة: ${nf(f.strength)}', tone: ImdTone.ok),
        ImdChip(
          'إجمالي الفرق: ${totVar > 0 ? '+' : ''}${nf((totVar * 100).round() / 100)}',
          tone: totVar > 0 ? ImdTone.err : (totVar < 0 ? ImdTone.ok : ImdTone.off),
        ),
      ],
      body: Text.rich(
        TextSpan(children: [
          for (final (i, x) in g.indexed) ...[
            if (i > 0) const TextSpan(text: ' · '),
            TextSpan(text: '${x.itemName} فعلي: '),
            TextSpan(text: nf(x.qty), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' ${x.unitName} '),
            TextSpan(
              text: '(${x.varianceBase > 0 ? '+' : ''}${nf((x.varianceBase * 100).round() / 100)})',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: x.varianceBase > 0 ? c.danger : (x.varianceBase < 0 ? c.accent : c.text),
              ),
            ),
          ],
        ]),
        style: TextStyle(fontSize: 13, height: 1.9, color: c.text),
      ),
    );
  }
}
