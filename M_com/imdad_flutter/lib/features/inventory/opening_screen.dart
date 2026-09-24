import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';

/// الأرصدة الافتتاحية — نقل `renderOpening()` / `opbPaint()`:
/// بحث + طباعة كشف + جدول (الكود، الصنف، الحالة، الرصيد الافتتاحي، إجراء).
/// الفرق الوحيد عن الويب: الرصيد يُثبَّت **لمستودع محدد** لأن أرصدة النظام هنا
/// مفصولة بالمستودعات (دفتر `stock-ledger`)، فأُضيف اختيار المستودع إلى شريط البحث.
class OpeningScreen extends StatefulWidget {
  const OpeningScreen({super.key});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();
  final Map<String, TextEditingController> _inputs = {};

  List<Item> _items = const [];
  List<Warehouse> _warehouses = const [];
  Map<String, double> _balances = const {};

  /// تاريخ آخر رصيد افتتاحي مُثبَّت لكل صنف في المستودع المختار (`openingSet/openingDate`).
  Map<String, String> _openingDate = const {};
  String _warehouse = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// `opbLoad()`
  Future<void> _load() async {
    final items = await _catalog.items();
    final whs = await _catalog.warehouses(scope: _perm.scope);
    if (!mounted) return;
    setState(() {
      _items = items;
      _warehouses = whs;
      if (_warehouse.isEmpty && whs.isNotEmpty) _warehouse = whs.first.name;
      _loading = false;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_warehouse.isEmpty) return;
    final bal = await _moves.balances(warehouse: _warehouse);
    final rows = await (_db.select(_db.openingBalances)
          ..where((t) => t.warehouse.equals(_warehouse)))
        .get();
    final dates = <String, String>{};
    for (final r in rows) {
      final prev = dates[r.itemId] ?? '';
      if (r.date.compareTo(prev) > 0) dates[r.itemId] = r.date;
    }
    if (mounted) {
      setState(() {
        _balances = bal;
        _openingDate = dates;
      });
    }
  }

  bool get _writable => _perm.admin || _perm.manage('opening');

  List<Item> _rows() {
    final q = _q.text.trim().toLowerCase();
    return _items
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q) || i.code.toLowerCase().contains(q))
        .toList();
  }

  /// زر «💾 حفظ» في الجدول.
  Future<void> _save(Item item) async {
    if (!_perm.guard(context, 'opening', PermAction.create)) return;
    if (_warehouse.isEmpty) {
      showImdToast(context, '✖ اختر المستودع أولًا', error: true);
      return;
    }
    if (!_perm.canWh(_warehouse)) {
      showImdToast(context, Perm.scopeBlock(_warehouse), error: true);
      return;
    }
    final qty = double.tryParse(_inputs[item.id]?.text.trim() ?? '');
    if (qty == null || qty < 0) {
      showImdToast(context, '✖ أدخل رقمًا صحيحًا', error: true);
      return;
    }
    final ok = await imdConfirm(
      context,
      'تثبيت الرصيد الافتتاحي لـ «${item.name}» بقيمة ${nf(qty)} في مستودع «$_warehouse»؟\n'
      'سيُستبدل الرصيد الافتتاحي السابق بهذه القيمة.',
      ok: 'تثبيت',
    );
    if (!ok) return;

    final date = isoDay(DateTime.now());
    await _db.transaction(() async {
      // تثبيت لا إضافة: يُستبدل الرصيد الافتتاحي السابق لنفس الصنف في نفس المستودع.
      await (_db.delete(_db.openingBalances)
            ..where((t) => t.itemId.equals(item.id) & t.warehouse.equals(_warehouse)))
          .go();
      await _db.into(_db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: Ids.next('opb'),
            itemId: item.id,
            itemCode: Value(item.code),
            itemName: Value(item.name),
            warehouse: Value(_warehouse),
            qty: Value(qty),
            date: Value(date),
            setBy: Value(_perm.email),
          ));
    });
    await AuditRepo(_db).write(
      'OPENING_BALANCE_SET',
      'openingBalance',
      'تثبيت رصيد افتتاحي لصنف',
      details: {
        'refNo': item.code,
        'qty': qty,
        'target': item.name,
        'warehouse': _warehouse,
        'status': 'OPENING_SET',
        'risk': 'critical',
      },
    );
    _inputs[item.id]?.clear();
    if (!mounted) return;
    showImdToast(context, '✔ تم تثبيت الرصيد الافتتاحي');
    await _refresh();
  }

  /// `opbPrintReport()`
  Future<void> _print() async {
    final rows = _rows();
    if (rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للطباعة', error: true);
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    var i = 0;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'كشف الأرصدة الافتتاحية',
        headers: const ['م', 'الكود', 'الصنف', 'الرصيد الافتتاحي', 'الوحدة', 'تاريخ الضبط'],
        columnFlex: const [1, 2, 6, 3, 2, 3],
        rows: [
          for (final x in rows)
            [
              (++i).toString(),
              x.code,
              x.name,
              nf(_balances[x.id] ?? 0),
              x.baseUnit,
              _openingDate[x.id] ?? '—',
            ],
        ],
        leftValues: {'date': isoDay(DateTime.now())},
        fieldValues: {'warehouse': _warehouse, 'notes': 'عدد الأصناف: ${rows.length}'},
      ),
      layout: layout,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ImdPage(children: [ImdLd('جارٍ التحميل…')]);
    final c = context.imd;
    final w = _writable;
    final rows = _rows();

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الأرصدة الافتتاحية',
        icon: 'clipboard',
        subtitle: 'تسجيل واعتماد الأرصدة الأولية للمخازن أو الأصناف الجديدة كنقطة انطلاق دفترية',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث بالكود أو الاسم…',
            onChanged: (_) => setState(() {}),
            actions: [
              SizedBox(
                width: 220,
                child: ImdSelect<String>(
                  dense: true,
                  hint: 'المستودع',
                  items: [for (final x in _warehouses) (x.name, x.name)],
                  value: _warehouse,
                  onChanged: (v) async {
                    setState(() => _warehouse = v ?? '');
                    await _refresh();
                  },
                ),
              ),
              ImdButton(
                label: 'طباعة كشف الأرصدة الافتتاحية',
                icon: 'printer',
                kind: ImdBtnKind.purple,
                small: true,
                onPressed: _print,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ImdEmojiText(
              '⚠️ تُستخدم هذه الشاشة لتثبيت رصيد بداية التشغيل لكل صنف في المستودع المختار. '
              'تعديل الرصيد هنا يُصحح الرصيد الحالي مباشرة ويُسجَّل بتاريخه في سجل تدقيق منفصل.',
              style: TextStyle(fontSize: 12, color: c.muted, height: 1.7),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      ImdTable(
        columns: [
          const ImdCol('الكود'),
          const ImdCol('الصنف'),
          const ImdCol('الحالة'),
          const ImdCol('الرصيد الافتتاحي', auto: false, width: 150),
          if (w) const ImdCol('إجراء'),
        ],
        empty: 'لا أصناف مطابقة',
        rows: [
          for (final x in rows)
            [
              Text(x.code, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(x.name),
              _openingDate.containsKey(x.id)
                  ? ImdChip('مضبوط (${_openingDate[x.id]})', tone: ImdTone.ok)
                  : const ImdChip('لم يُضبط بعد', tone: ImdTone.pend),
              ImdFld(
                controller: _inputs.putIfAbsent(
                  x.id,
                  () => TextEditingController(text: _plainQty(_balances[x.id] ?? 0)),
                ),
                number: true,
                dense: true,
                enabled: w,
              ),
              if (w)
                ImdButton(label: 'حفظ', icon: 'save', small: true, onPressed: () => _save(x)),
            ],
        ],
      ),
    ]);
  }

  static String _plainQty(double v) {
    final r = (v * 1000).round() / 1000;
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }
}
