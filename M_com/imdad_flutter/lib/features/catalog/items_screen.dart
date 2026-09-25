import 'dart:math' as math;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/print/barcode_labels.dart';
import '../../core/print/barcode128.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_toolbar.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/stock_alerts.dart';

/// إدارة الأصناف — نقل مطابق لـ `renderItems()` في نسخة الويب بتبويباتها الست:
/// القائمة، التصنيفات، بطاقة الصنف، الأرصدة، حركة الصنف، الباركودات.
class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

/// صف وحدة قياس في النموذج (`.urow`).
class _URow {
  _URow(String name, double factor, this.base)
      : name = TextEditingController(text: name),
        factor = TextEditingController(text: _fmtNum(factor));
  final TextEditingController name;
  final TextEditingController factor;
  bool base;

  void dispose() {
    name.dispose();
    factor.dispose();
  }
}

String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _ItemsScreenState extends State<ItemsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _repo = CatalogRepo(_db);

  // حالة الشاشة `itm`
  String _tab = 'list';
  String? _editId;
  List<Item> _items = const [];
  List<Category> _cats = const [];
  Map<String, double> _ledger = const {};
  bool _loading = true;
  String _movsId = '';

  // القائمة
  final _search = TextEditingController();

  // التصنيفات
  final _cName = TextEditingController();
  final _cDesc = TextEditingController();

  // النموذج
  final _iCode = TextEditingController();
  final _iBC = TextEditingController();
  final _iName = TextEditingController();
  final _iMin = TextEditingController();
  String _iCat = '';
  bool _iRef = false;
  String _iReportUnit = '';
  List<_URow> _uRows = [];
  bool _saving = false;

  // الأرصدة والحركة
  String _balId = '';
  Widget? _balOut;
  Widget? _movOut;

  // الباركودات
  final Set<String> _bcChecked = {};
  final _bcCopies = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _fetch().then((_) => _switch('list'));
  }

  @override
  void dispose() {
    for (final c in [_search, _cName, _cDesc, _iCode, _iBC, _iName, _iMin, _bcCopies]) {
      c.dispose();
    }
    for (final r in _uRows) {
      r.dispose();
    }
    super.dispose();
  }

  /// `itmFetchData()`
  Future<void> _fetch() async {
    final items = await _repo.items();
    final cats = await _repo.categories();
    final ledger = await MovementsRepo(_db).balances();
    if (!mounted) return;
    setState(() {
      _items = items;
      _cats = cats;
      _ledger = ledger;
      _loading = false;
    });
  }

  /// رصيد الصنف من دفتر الحركات وحده (الأرصدة الافتتاحية + صافي الحركات).
  ///
  /// كان يُضاف إليه عمود `items.qty`، وهو في الويب رصيد عرضٍ يُعاد حسابه من
  /// الدفتر نفسه — فكانت البيانات المستوردة من الويب تُحسب مرتين هنا، بينما
  /// تتجاهله أرصدة المستودعات وفحوص الكفاية، فيظهر للصنف رصيدان مختلفان.
  double _qty(Item x) => _ledger[x.id] ?? 0;

  bool _w(BuildContext context) => Perm.of(context).writable('items');

  void _switch(String t) {
    setState(() => _tab = t);
    if (t == 'form') _initForm();
    if (t == 'list' || t == 'cats' || t == 'bc') _fetch();
    if (t == 'movs' && _movsId.isNotEmpty && _items.any((x) => x.id == _movsId)) _loadMovs(_movsId);
  }

  @override
  Widget build(BuildContext context) {
    return ImdPage(
      children: [
        const ImdPageTitle(
          title: 'إدارة الأصناف',
          icon: 'package',
          subtitle: 'بطاقات الأصناف والتصنيفات والوحدات والأرصدة وحركة الصنف والباركودات',
        ),
        ImdItabs(
          value: _tab,
          onChanged: _switch,
          tabs: const [
            ImdTab('list', 'القائمة', icon: 'clipboard'),
            ImdTab('cats', 'التصنيفات', icon: 'folder'),
            ImdTab('form', 'بطاقة الصنف', icon: 'package'),
            ImdTab('bals', 'الأرصدة', icon: 'chart'),
            ImdTab('movs', 'حركة الصنف', icon: 'repeat'),
            ImdTab('bc', 'الباركودات', icon: 'camera'),
          ],
        ),
        if (_loading)
          const ImdLd('جارٍ التحميل…')
        else
          switch (_tab) {
            'list' => _list(context),
            'cats' => _catsView(context),
            'form' => _form(context),
            'bals' => _bals(context),
            'movs' => _movs(context),
            _ => _bc(context),
          },
      ],
    );
  }

  // ───────────────────────── القائمة ─────────────────────────
  Widget _list(BuildContext context) {
    final w = _w(context);
    final c = context.imd;
    final lowN = _items.where((x) => StockAlerts.isLow(_qty(x), x.minQty)).length;
    final q = _search.text.trim().toLowerCase();
    final rows = _items
        .where((x) =>
            q.isEmpty ||
            x.code.toLowerCase().contains(q) ||
            x.name.toLowerCase().contains(q) ||
            x.barcode.contains(q))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // .lst-bar
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 14, color: c.text),
                decoration: imdFieldDecoration(context, hint: 'بحث بالكود أو الاسم أو الباركود…'),
              ),
            ),
            const SizedBox(width: 6),
            ImdScanButton(controller: _search, onScanned: (_) => setState(() {})),
            const SizedBox(width: 8),
            ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _fetch),
          ]),
        ),
        ImdChipsRow(children: [
          ImdChip('الأصناف: ${nf(_items.length)}', tone: ImdTone.ok),
          ImdChip('التصنيفات: ${nf(_cats.length)}', tone: ImdTone.code),
          ImdChip('تحت الحد: ${nf(lowN)}', tone: ImdTone.pend, icon: 'alert'),
          if (!w) const ImdChip('عرض فقط — التعديل للمدير', tone: ImdTone.off, icon: 'eye'),
        ]),
        ImdTableToolbar(
          page: 'items',
          onExport: () => _exportList(rows, w),
          onTemplate: _template,
          onImport: _import,
        ),
        ImdTable(
          minWidth: 720,
          empty: 'لا أصناف مطابقة — أضف أول صنف من تبويب «بطاقة الصنف»',
          columns: [
            const ImdCol('الكود'),
            const ImdCol('اسم الصنف', flex: 2),
            const ImdCol('التصنيف'),
            const ImdCol('حد ⚠'),
            const ImdCol('الرصيد'),
            const ImdCol('الوحدات', flex: 2),
            if (w) const ImdCol('إجراءات', width: 110),
          ],
          rows: [
            for (final x in rows)
              [
                Text(x.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(x.name),
                Text(x.categoryName.isEmpty ? '—' : x.categoryName),
                Text(x.minQty != 0 ? nf(x.minQty) : '—'),
                Text(nf(_qty(x)),
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: (StockAlerts.isLow(_qty(x), x.minQty)) ? c.danger : c.text)),
                _unitsStr(x),
                if (w)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ImdIconButton(
                      icon: 'edit',
                      onPressed: () {
                        _editId = x.id;
                        _switch('form');
                      },
                    ),
                    const SizedBox(width: 4),
                    ImdIconButton(icon: 'trash', kind: ImdBtnKind.danger, onPressed: () => _delete(x)),
                  ]),
              ],
          ],
        ),
      ],
    );
  }

  /// `itmUnitsStr`
  Widget _unitsStr(Item x) {
    final us = _unitsRaw(x);
    if (us.isEmpty) return const Text('—', style: TextStyle(color: Color(0xFF98A8A0)));
    return Text(us.map((u) => u.name + (u.isBase ? ' (أساسية)' : '')).join(' · '));
  }

  /// وحدات الصنف كما خُزّنت (بدون افتراض وحدة عند الخلو).
  List<ItemUnit> _unitsRaw(Item x) {
    if (x.units.trim().isEmpty || x.units.trim() == '[]') return const [];
    return _repo.unitsOf(x);
  }

  Future<void> _delete(Item x) async {
    if (!await imdConfirm(context, 'حذف هذا الصنف نهائيًا؟ لا يمكن التراجع.', ok: 'حذف', danger: true)) return;
    try {
      await _repo.deleteItem(x.id);
      if (!mounted) return;
      showImdToast(context, '✔ تم الحذف');
      await _fetch();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _exportList(List<Item> rows, bool w) async {
    await ImdExcel.save(
      context,
      'الأصناف ${ImdFiles.today()}',
      const ['الكود', 'اسم الصنف', 'التصنيف', 'حد ⚠', 'الرصيد', 'الوحدات'],
      [
        for (final x in rows)
          [
            x.code,
            x.name,
            x.categoryName.isEmpty ? '—' : x.categoryName,
            x.minQty != 0 ? nf(x.minQty) : '—',
            nf(_qty(x)),
            _unitsRaw(x).isEmpty ? '—' : _unitsRaw(x).map((u) => u.name + (u.isBase ? ' (أساسية)' : '')).join(' · '),
          ],
      ],
    );
  }

  /// `itemsTemplate()`
  Future<void> _template() => ImdExcel.save(
        context,
        'أصناف-قالب',
        const ['code', 'name', 'category', 'unit', 'min', 'qty'],
        const [
          ['', '', '', '', '', ''],
        ],
      );

  /// `importItems(rows)` — يحدّث الصنف بنفس الكود أو يُنشئه.
  Future<void> _import() async {
    final actor = Perm.of(context).email;
    final rows = await ImdExcel.pickAndRead(context);
    if (rows == null) return;
    var ok = 0, skip = 0, qtyPending = 0;
    // الرصيد لا يُحفظ على الصنف: يصير رصيدًا افتتاحيًا في مستودع، مصدر الأرصدة
    // الوحيد. مع مستودع واحد يُعرف مكانه؛ ومع أكثر يُترك لشاشة الأرصدة الافتتاحية.
    final whs = await _db.select(_db.warehouses).get();
    final soleWh = whs.length == 1 ? whs.single.name : '';
    for (final r in rows) {
      final code = (r['code'] ?? '').trim();
      final name = (r['name'] ?? '').trim();
      if (code.isEmpty || name.isEmpty) {
        skip++;
        continue;
      }
      try {
        final cat = (r['category'] ?? '').trim();
        final unit = (r['unit'] ?? '').trim();
        final qty = double.tryParse((r['qty'] ?? '').trim()) ?? 0;
        final min = double.tryParse((r['min'] ?? '').trim()) ?? 0;
        final existing = await (_db.select(_db.items)..where((t) => t.code.equals(code))).get();
        final catRow = _cats.where((x) => x.name == cat).firstOrNull;
        if (existing.isNotEmpty) {
          final it = existing.first;
          await (_db.update(_db.items)..where((t) => t.id.equals(it.id))).write(ItemsCompanion(
            name: Value(name),
            categoryName: Value(cat),
            categoryId: Value(catRow?.id ?? it.categoryId),
            baseUnit: unit.isEmpty ? const Value.absent() : Value(unit),
            units: (unit.isEmpty || _unitsRaw(it).isNotEmpty)
                ? const Value.absent()
                : Value('[{"name":${_jsonStr(unit)},"factor":1,"isBase":true}]'),
            minQty: Value(min),
          ));
        } else {
          final id = await _repo.saveItem(
            code: code,
            name: name,
            categoryId: catRow?.id ?? '',
            categoryName: cat,
            baseUnit: unit,
            units: unit.isEmpty ? const [] : [ItemUnit(name: unit, factor: 1, isBase: true)],
            minQty: min,
          );
          if (unit.isEmpty) {
            await (_db.update(_db.items)..where((t) => t.id.equals(id))).write(const ItemsCompanion(units: Value('[]')));
          }
        }
        if (qty != 0) {
          if (soleWh.isEmpty) {
            qtyPending++;
          } else {
            final item = await (_db.select(_db.items)..where((t) => t.code.equals(code))).getSingle();
            await _setOpening(item, soleWh, qty, actor);
          }
        }
        ok++;
      } catch (_) {
        skip++;
        if (mounted) showImdToast(context, '✖ خطأ لصف $code');
      }
    }
    if (!mounted) return;
    showImdToast(
      context,
      '✔ استيراد الأصناف: $ok صنفًا${skip > 0 ? ' (تجاهل $skip)' : ''}'
      '${qtyPending > 0 ? ' — لم تُسجَّل كميات $qtyPending صنفًا لتعدد المستودعات: أدخلها من «الأرصدة الافتتاحية»' : ''}',
    );
    await _fetch();
  }

  /// رصيد افتتاحي للصنف في المستودع — تثبيت يستبدل السابق كما في شاشة الأرصدة الافتتاحية.
  Future<void> _setOpening(Item item, String warehouse, double qty, String actor) async {
    await _db.transaction(() async {
      await (_db.delete(_db.openingBalances)
            ..where((t) => t.itemId.equals(item.id) & t.warehouse.equals(warehouse)))
          .go();
      await _db.into(_db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: Ids.next('opb'),
            itemId: item.id,
            itemCode: Value(item.code),
            itemName: Value(item.name),
            warehouse: Value(warehouse),
            qty: Value(qty),
            date: Value(isoDay(DateTime.now())),
            setBy: Value(actor),
          ));
    });
  }

  static String _jsonStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  // ───────────────────────── التصنيفات ─────────────────────────
  Widget _catsView(BuildContext context) {
    final w = _w(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImdICard(
          title: 'إضافة تصنيف رئيسي',
          icon: 'plus',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImdF2(children: [
                ImdFld(controller: _cName, hint: 'اسم التصنيف (مثال: مواد غذائية)'),
                ImdFld(controller: _cDesc, hint: 'وصف / ملاحظات (اختياري)'),
              ]),
              if (w)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ImdButton(label: 'إضافة التصنيف +', onPressed: _addCat),
                  ),
                )
              else
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: ImdLdText('👁 عرض فقط — الإضافة للمدير')),
            ],
          ),
        ),
        ImdICard(
          title: 'التصنيفات المسجلة',
          icon: 'folder',
          child: ImdTable(
            empty: 'لا تصنيفات بعد',
            columns: [
              const ImdCol('م', width: 60),
              const ImdCol('الاسم', flex: 2),
              const ImdCol('الوصف', flex: 3),
              if (w) const ImdCol('إجراء', width: 110),
            ],
            rows: [
              for (var i = 0; i < _cats.length; i++)
                [
                  Text(nf(i + 1)),
                  Text(_cats[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_cats[i].description.isEmpty ? '—' : _cats[i].description),
                  if (w)
                    ImdButton(
                      label: 'حذف',
                      icon: 'trash',
                      kind: ImdBtnKind.danger,
                      small: true,
                      onPressed: () => _deleteCat(_cats[i]),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addCat() async {
    final name = _cName.text.trim();
    if (name.isEmpty) {
      showImdToast(context, '✖ اكتب اسم التصنيف');
      return;
    }
    try {
      await _repo.saveCategory(name: name, description: _cDesc.text.trim());
      _cName.clear();
      _cDesc.clear();
      if (!mounted) return;
      showImdToast(context, '✔ أُضيف التصنيف');
      await _fetch();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _deleteCat(Category cat) async {
    if (!await imdConfirm(context, 'حذف التصنيف؟ الأصناف المرتبطة به تحتفظ بالاسم القديم.', ok: 'حذف', danger: true)) {
      return;
    }
    await (_db.delete(_db.categories)..where((t) => t.id.equals(cat.id))).go();
    if (!mounted) return;
    showImdToast(context, '✔ حُذف التصنيف');
    await _fetch();
  }

  // ───────────────────────── بطاقة الصنف ─────────────────────────
  Item? get _cur => _editId == null ? null : _items.where((x) => x.id == _editId).firstOrNull;

  void _initForm() {
    final cur = _cur;
    var next = 1;
    final nums = _items
        .map((x) => int.tryParse(RegExp(r'\d+').firstMatch(x.code)?.group(0) ?? '0') ?? 0)
        .where((n) => n > 0)
        .toList();
    if (nums.isNotEmpty) next = nums.reduce(math.max) + 1;
    imdSetText(_iCode, cur?.code ?? '$next');
    imdSetText(_iBC, cur?.barcode ?? '');
    imdSetText(_iName, cur?.name ?? '');
    imdSetText(_iMin, cur != null && cur.minQty != 0 ? _fmtNum(cur.minQty) : '0');
    _iCat = cur?.categoryId ?? '';
    _iRef = cur?.isRefillable ?? false;
    _iReportUnit = cur?.reportUnit ?? '';
    for (final r in _uRows) {
      r.dispose();
    }
    _uRows = [];
    if (cur != null) {
      for (final u in _unitsRaw(cur)) {
        _uRows.add(_URow(u.name, u.factor, u.isBase));
      }
    }
    if (_uRows.isEmpty) _uRows.add(_URow('قطعة', 1, true));
  }

  Widget _form(BuildContext context) {
    final cur = _cur;
    final w = _w(context);
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImdICard(
          title: cur != null ? 'وضع التعديل: ${cur.code} — ${cur.name}' : 'وضع الإضافة: تسجيل صنف جديد',
          icon: cur != null ? 'edit' : 'plus-square',
          titleColor: const Color(0xFF915E06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImdF2(children: [
                ImdLabeled('الكود (فريد) *', ImdFld(controller: _iCode, readOnly: cur != null)),
                ImdLabeled(
                  'الباركود (نظامي 104 / مصنعي)',
                  Row(children: [
                    Expanded(child: ImdFld(controller: _iBC)),
                    const SizedBox(width: 6),
                    ImdScanButton(controller: _iBC),
                    const SizedBox(width: 6),
                    ImdButton.outline(
                      label: 'توليد',
                      icon: 'settings',
                      small: true,
                      onPressed: () {
                        final ms = DateTime.now().millisecondsSinceEpoch.toString();
                        imdSetText(_iBC, '104${ms.substring(ms.length - 9)}');
                      },
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              ImdLabeled('اسم الصنف (شجرة المواد) *', ImdFld(controller: _iName)),
              const SizedBox(height: 10),
              ImdF2(children: [
                ImdLabeled(
                  'التصنيف الرئيسي',
                  ImdSelect<String>(
                    value: _iCat,
                    items: [('', '— بدون تصنيف —'), for (final cat in _cats) (cat.id, cat.name)],
                    onChanged: (v) => setState(() => _iCat = v ?? ''),
                  ),
                ),
                ImdLabeled('الحد الأدنى للتنبيه ⚠', ImdFld(controller: _iMin, number: true)),
                // الرصيد يُخزَّن بالوحدة الأساسية دائمًا؛ هذه للعرض فقط في
                // التقارير وفي رصيد شاشات الإدخال.
                ImdLabeled(
                  'وحدة العرض في التقارير',
                  ImdSelect<String>(
                    value: _iReportUnit,
                    items: [
                      ('', '— الوحدة الأساسية —'),
                      for (final r in _uRows)
                        if (r.name.text.trim().isNotEmpty)
                          (r.name.text.trim(), r.name.text.trim()),
                    ],
                    onChanged: (v) => setState(() => _iReportUnit = v ?? ''),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _iRef = !_iRef),
                child: Row(children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _iRef,
                      activeColor: c.accent,
                      onChanged: (v) => setState(() => _iRef = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('صنف قابل للتعبئة/الاستبدال (كالغاز)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                ]),
              ),
            ],
          ),
        ),
        ImdICard(
          title: 'وحدات القياس ومعاملات التحويل',
          icon: 'scale',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('المعامل = كم وحدة أساسية تساوي هذه الوحدة (كرتون ×12 = 12 قطعة)',
                    style: TextStyle(fontSize: 12, color: c.muted)),
              ),
              for (final r in _uRows) _unitRow(r),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ImdButton.outline(
                  label: '+ إضافة وحدة',
                  small: true,
                  onPressed: () => setState(() => _uRows.add(_URow('', 1, false))),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(children: [
            Expanded(
              child: ImdButton.outline(
                label: 'إلغاء / مسح',
                expand: true,
                onPressed: () => setState(() {
                  _editId = null;
                  _initForm();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: w
                  ? ImdButton(
                      label: cur != null ? 'حفظ التعديلات' : 'حفظ بطاقة الصنف',
                      icon: 'save',
                      expand: true,
                      busy: _saving,
                      onPressed: _save,
                    )
                  : const ImdButton(label: 'عرض فقط — الإضافة للمدير', icon: 'eye', expand: true),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _unitRow(_URow r) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(flex: 14, child: ImdFld(controller: r.name, hint: 'اسم الوحدة (مثال: كرتون)', dense: true)),
        const SizedBox(width: 8),
        Expanded(flex: 7, child: ImdFld(controller: r.factor, hint: 'المعامل ×', number: true, dense: true)),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => setState(() {
            for (final x in _uRows) {
              x.base = identical(x, r);
            }
          }),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<bool>(
                value: true,
                // ignore: deprecated_member_use
                groupValue: r.base,
                activeColor: c.accent,
                // ignore: deprecated_member_use
                onChanged: (_) => setState(() {
                  for (final x in _uRows) {
                    x.base = identical(x, r);
                  }
                }),
              ),
            ),
            const SizedBox(width: 4),
            Text('أساسية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.text)),
          ]),
        ),
        const SizedBox(width: 8),
        ImdIconButton(
          icon: 'x',
          kind: ImdBtnKind.danger,
          onPressed: () => setState(() {
            _uRows.remove(r);
            r.dispose();
          }),
        ),
      ]),
    );
  }

  Future<void> _save() async {
    final cur = _cur;
    if (!Perm.of(context).guard(context, 'items', cur != null ? 'edit' : 'create')) return;
    final name = _iName.text.trim(), code = _iCode.text.trim();
    if (name.isEmpty) return showImdToast(context, '✖ أدخل اسم الصنف');
    if (code.isEmpty) return showImdToast(context, '✖ أدخل كود الصنف');
    final us = <ItemUnit>[];
    for (final r in _uRows) {
      final nm = r.name.text.trim();
      final fc = double.tryParse(r.factor.text.trim());
      if (nm.isNotEmpty) us.add(ItemUnit(name: nm, factor: (fc == null || fc == 0) ? 1 : fc, isBase: r.base));
    }
    if (us.isEmpty) return showImdToast(context, '✖ أضف وحدة قياس واحدة على الأقل');
    if (!us.any((u) => u.isBase)) us[0] = ItemUnit(name: us[0].name, factor: us[0].factor, isBase: true);
    final dup = await (_db.select(_db.items)..where((t) => t.code.equals(code))).get();
    if (!mounted) return;
    if (dup.isNotEmpty && dup.first.id != _editId) return showImdToast(context, '✖ الكود مستخدم لصنف آخر');
    setState(() => _saving = true);
    try {
      final cat = _cats.where((x) => x.id == _iCat).firstOrNull;
      await _repo.saveItem(
        id: cur?.id,
        code: code,
        name: name,
        barcode: _iBC.text.trim(),
        categoryId: _iCat,
        categoryName: cat?.name ?? '',
        minQty: double.tryParse(_iMin.text.trim()) ?? 0,
        isRefillable: _iRef,
        reportUnit: _iReportUnit,
        units: us,
        baseUnit: (us.where((u) => u.isBase).firstOrNull ?? us.first).name,
      );
      if (!mounted) return;
      showImdToast(context, cur != null ? '✔ تم حفظ التعديلات' : '🎉 تم حفظ الصنف بنجاح');
      _editId = null;
      await _fetch();
      _switch('list');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────────────────────── الأرصدة ─────────────────────────
  Widget _itemSelect(String value, ValueChanged<String> onChanged) => ImdSelect<String>(
        value: value,
        items: [('', '— اختر الصنف —'), for (final x in _items) (x.id, '${x.code} — ${x.name}')],
        onChanged: (v) => onChanged(v ?? ''),
      );

  Widget _bals(BuildContext context) {
    return ImdICard(
      title: 'أرصدة الصنف (بوحدة الأساس)',
      icon: 'chart',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _itemSelect(_balId, (v) {
            setState(() => _balId = v);
            _calcBal(v);
          }),
          const SizedBox(height: 14),
          _balOut ?? ImdLd(_items.isNotEmpty ? 'اختر صنفًا لعرض رصيده' : 'لا أصناف بعد', center: true),
        ],
      ),
    );
  }

  /// `itmCalcBal(id)` — من الاستلام والصرف غير المسودة، بمعامل وحدة السطر.
  Future<void> _calcBal(String id) async {
    if (id.isEmpty) {
      setState(() => _balOut = const ImdLd('اختر صنفًا', center: true));
      return;
    }
    setState(() => _balOut = const ImdLd('جارٍ الحساب…', center: true));
    final it = _items.firstWhere((x) => x.id == id);
    final rc = (await (_db.select(_db.receipts)..where((t) => t.itemId.equals(id))).get())
        .where((r) => r.status != 'DRAFT');
    final iss = (await (_db.select(_db.issues)..where((t) => t.itemId.equals(id))).get())
        .where((r) => r.status != 'DRAFT');
    final units = _unitsRaw(it);
    double fac(String u) {
      final f = units.where((y) => y.name == u).firstOrNull;
      return f == null ? 1 : (f.factor == 0 ? 1 : f.factor);
    }

    var tin = 0.0, tout = 0.0, nin = 0, nout = 0;
    for (final r in rc) {
      tin += r.qty * fac(r.unitName);
      nin++;
    }
    for (final r in iss) {
      tout += r.qty * fac(r.unitName);
      nout++;
    }
    final bal = tin - tout, min = it.minQty;
    final base = it.baseUnit.isNotEmpty
        ? it.baseUnit
        : (units.where((u) => u.isBase).firstOrNull?.name ?? 'وحدة الأساس');
    double r2(double v) => (v * 100).round() / 100;
    if (!mounted) return;
    final c = context.imd;
    setState(() {
      _balOut = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdKpis(children: [
            ImdKpi(label: 'إجمالي الوارد (${nf(nin)} حركة)', value: nf(r2(tin)), color: c.accent),
            ImdKpi(label: 'إجمالي المنصرف (${nf(nout)} حركة)', value: nf(r2(tout)), color: c.danger),
            ImdKpi(
              label: 'الرصيد الحالي — $base',
              value: nf(r2(bal)),
              extra: bal <= 0
                  ? const ImdChip('فارغ ❌', tone: ImdTone.off)
                  : (StockAlerts.isLow(bal, min)
                      ? const ImdChip('تحت الحد ⚠️', tone: ImdTone.pend)
                      : const ImdChip('جيد ✅', tone: ImdTone.ok)),
            ),
            ImdKpi(label: 'حد التنبيه ⚠', value: min != 0 ? nf(min) : '—'),
          ]),
          if (nin == 0 && nout == 0) const ImdLd('لا حركات بعد — استخدم شاشة «استلام بضاعة» لإضافة أول رصيد'),
        ],
      );
    });
  }

  // ───────────────────────── حركة الصنف ─────────────────────────
  Widget _movs(BuildContext context) {
    return ImdICard(
      title: 'كارت الصنف (سجل الحركة الكامل)',
      icon: 'repeat',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _itemSelect(_movsId, _loadMovs),
          const SizedBox(height: 14),
          _movOut ?? const ImdLd('اختر صنفًا لعرض حركته', center: true),
        ],
      ),
    );
  }

  /// `itmLoadMovs(id)`
  Future<void> _loadMovs(String id) async {
    setState(() => _movsId = id);
    if (id.isEmpty) {
      setState(() => _movOut = const ImdLd('اختر صنفًا', center: true));
      return;
    }
    setState(() => _movOut = const ImdLd('جارٍ التحميل…', center: true));
    final rc = (await (_db.select(_db.receipts)..where((t) => t.itemId.equals(id))).get())
        .where((r) => r.status != 'DRAFT')
        .map((r) => (t: 'in', at: r.createdAt, date: r.date, side: r.supplier.isNotEmpty ? r.supplier : r.warehouse, qty: r.qty, unit: r.unitName, ref: r.refNo, notes: r.notes));
    final iss = (await (_db.select(_db.issues)..where((t) => t.itemId.equals(id))).get())
        .where((r) => r.status != 'DRAFT')
        .map((r) => (
              t: 'out',
              at: r.createdAt,
              date: r.date,
              side: r.recipientDisplay.isNotEmpty
                  ? r.recipientDisplay
                  : (r.beneficiaryUnitName.isNotEmpty ? r.beneficiaryUnitName : r.unitName),
              qty: r.qty,
              unit: r.unitName,
              ref: r.refNo,
              notes: r.notes
            ));
    final movs = [...rc, ...iss]..sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      if (movs.isEmpty) {
        _movOut = const ImdLd('لا حركات بعد لهذا الصنف', center: true);
        return;
      }
      _movOut = ImdTable(
        minWidth: 560,
        columns: const [
          ImdCol('التاريخ'),
          ImdCol('النوع'),
          ImdCol('الجهة', flex: 2),
          ImdCol('الكمية'),
          ImdCol('مرجع'),
          ImdCol('ملاحظات', flex: 2),
        ],
        rows: [
          for (final m in movs.take(100))
            [
              Text(arDate(m.at)),
              m.t == 'in'
                  ? const ImdChip('وارد 🟢', tone: ImdTone.ok)
                  : const ImdChip('صرف 🔴', tone: ImdTone.pend),
              Text(m.side.isEmpty ? '—' : m.side),
              Text.rich(TextSpan(children: [
                TextSpan(text: nf(m.qty), style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' ${m.unit}'),
              ])),
              Text(m.ref.isEmpty ? '—' : m.ref),
              Text(m.notes),
            ],
        ],
      );
    });
  }

  // ───────────────────────── الباركودات ─────────────────────────
  Widget _bc(BuildContext context) {
    final w = _w(context);
    final c = context.imd;
    final withBc = _items.where((x) => x.barcode.isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImdICard(
          title: 'محطة الباركودات',
          icon: 'camera',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImdChipsRow(children: [
                ImdChip('إجمالي: ${nf(_items.length)}', tone: ImdTone.ok),
                ImdChip('لديه باركود: ${nf(withBc)}', tone: ImdTone.code),
                ImdChip('بدون: ${nf(_items.length - withBc)}', tone: ImdTone.pend),
              ]),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (w) ImdButton(label: 'توليد للناقص', icon: 'settings', small: true, onPressed: _genMissing),
                  ImdButton.outline(
                    label: 'تحديد الكل',
                    icon: 'check-circle',
                    small: true,
                    onPressed: () => setState(() {
                      _bcChecked
                        ..clear()
                        ..addAll(_items.where((x) => x.barcode.isNotEmpty).map((x) => x.id));
                    }),
                  ),
                  ImdButton.outline(label: 'إلغاء التحديد', small: true, onPressed: () => setState(_bcChecked.clear)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('نسخ:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(width: 6),
                    SizedBox(width: 70, child: ImdFld(controller: _bcCopies, number: true, dense: true)),
                    const SizedBox(width: 6),
                    ImdScanButton(controller: _bcCopies),
                  ]),
                  ImdButton(label: 'معاينة الملصقات وطباعتها', icon: 'printer', small: true, onPressed: _printLabels),
                ],
              ),
            ],
          ),
        ),
        if (_items.isEmpty)
          const ImdLd('لا أصناف بعد — أنشئ أصنافًا أولًا', center: true)
        else
          for (final x in _items) _bcRow(x),
      ],
    );
  }

  Widget _bcRow(Item x) {
    final c = context.imd;
    final has = x.barcode.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: has && _bcChecked.contains(x.id),
            activeColor: c.accent,
            onChanged: has
                ? (v) => setState(() => v == true ? _bcChecked.add(x.id) : _bcChecked.remove(x.id))
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${x.code} — ${x.name}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 4),
              has ? Barcode128View(x.barcode) : const ImdChip('⚠️ بدون باركود', tone: ImdTone.pend),
            ],
          ),
        ),
        if (has) ...[
          const SizedBox(width: 10),
          ImdButton.outline(
            label: 'نسخ',
            icon: 'clipboard',
            small: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: x.barcode));
              if (mounted) showImdToast(context, '📋 نُسخ: ${x.barcode}');
            },
          ),
        ],
      ]),
    );
  }

  /// `itmGenMissing()`
  Future<void> _genMissing() async {
    final miss = _items.where((x) => x.barcode.isEmpty).toList();
    if (miss.isEmpty) return showImdToast(context, '✔ جميع الأصناف لديها باركود');
    if (!await imdConfirm(context, 'توليد باركود نظامي لـ ${miss.length} صنف؟')) return;
    var n = 0;
    final rnd = math.Random();
    for (final x in miss) {
      final ms = DateTime.now().millisecondsSinceEpoch.toString();
      final bc = '104${ms.substring(ms.length - 9)}${rnd.nextInt(90) + 10}';
      try {
        await (_db.update(_db.items)..where((t) => t.id.equals(x.id))).write(ItemsCompanion(barcode: Value(bc)));
        n++;
      } catch (_) {}
    }
    if (!mounted) return;
    showImdToast(context, '✔ ولّد باركود لـ $n صنف');
    await _fetch();
    // الأصناف ذات الباركود محددة افتراضيًا كما في الويب.
    setState(() => _bcChecked.addAll(_items.where((x) => x.barcode.isNotEmpty).map((x) => x.id)));
  }

  /// `itmPrintLabels()`
  Future<void> _printLabels() async {
    final sel = _items.where((x) => x.barcode.isNotEmpty && _bcChecked.contains(x.id)).toList();
    if (sel.isEmpty) return showImdToast(context, '⚠ حدد صنوفًا لها باركود');
    final copies = (int.tryParse(_bcCopies.text.trim()) ?? 1).clamp(1, 50);
    showImdToast(context, '💡 على الجوال: اختر «حفظ كملف PDF» ثم شاركه مع الطابعة');
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BarcodeLabelsSheet(
        labels: [
          for (final x in sel)
            for (var i = 0; i < copies; i++) (name: x.name, code: x.code, barcode: x.barcode),
        ],
      ),
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // الأصناف ذات الباركود محددة مبدئيًا (checked في الويب).
    if (_bcChecked.isEmpty) _bcChecked.addAll(_items.where((x) => x.barcode.isNotEmpty).map((x) => x.id));
  }
}
