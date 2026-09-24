import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/export/excel_export.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_files.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';

/// ضبط الاستحقاقات والمقررات — نقل `renderRatios()`:
/// إدخال شبكي مباشر لكل صنف (المقرر الشهري للفرد + وحدة القياس + ملاحظات)،
/// مع معدل يومي محسوب، ورقائق تصفية (الكل / لها مقرر / بدون مقرر)،
/// وحفظ جماعي للسطور المعدَّلة فقط، وتصدير إكسل وطباعة لائحة رسمية.
class RatiosScreen extends StatefulWidget {
  const RatiosScreen({super.key});

  @override
  State<RatiosScreen> createState() => _RatiosScreenState();
}

/// حالة سطر واحد في الشبكة مع قيمه الأصلية لكشف التعديل (`data-q0/u0/n0`).
class _RatRow {
  _RatRow({required this.item, required this.qty0, required this.unit0, required this.notes0})
      : qty = TextEditingController(text: qty0),
        notes = TextEditingController(text: notes0),
        unit = unit0;

  final Item item;
  final String qty0;
  final String unit0;
  final String notes0;
  final TextEditingController qty;
  final TextEditingController notes;
  String unit;

  bool get hasEnt => (double.tryParse(qty.text.trim()) ?? 0) > 0;

  /// القيمة مكتوبة لكنها ليست رقمًا موجبًا (`ratBad`).
  bool get bad {
    final t = qty.text.trim();
    if (t.isEmpty) return false;
    final v = double.tryParse(t);
    return v == null || v < 0;
  }

  bool get dirty =>
      _norm(qty.text) != qty0 || unit != unit0 || notes.text.trim() != notes0;

  static String _norm(String v) {
    final t = v.trim();
    if (t.isEmpty) return '';
    final n = double.tryParse(t);
    if (n == null) return t;
    final r = (n * 1000).round() / 1000;
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }

  void dispose() {
    qty.dispose();
    notes.dispose();
  }
}

class _RatiosScreenState extends State<RatiosScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final DailyRepo _daily = DailyRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();
  final List<_RatRow> _rows = [];

  /// all | set | zero
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _writable => _perm.admin || _perm.has('ratios', PermAction.edit);

  /// `ratLoadData()` + `ratPaintRows()`
  Future<void> _load() async {
    final items = await _catalog.items();
    final ents = {for (final e in await _daily.entitlements()) e.itemId: e};
    if (!mounted) return;
    for (final r in _rows) {
      r.dispose();
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(items.map((it) {
          final units = _catalog.unitsOf(it);
          final ex = ents[it.id];
          final saved = ex?.measureUnitName ?? '';
          final sel = units.any((u) => u.name == saved)
              ? saved
              : units.firstWhere((u) => u.isBase, orElse: () => units.first).name;
          // `entMeasureQty`: المقرر يُعرض بوحدة القياس المختارة، فيُحوَّل من وحدة الأساس إليها.
          var qty = '';
          if (ex != null && ex.qtyPerPerson != 0) {
            final savedFactor = ex.measureFactor <= 0 ? 1.0 : ex.measureFactor;
            final baseQty = ex.qtyPerPerson * savedFactor;
            qty = _RatRow._norm('${baseQty / _factorOf(it, sel)}');
          }
          return _RatRow(item: it, qty0: qty, unit0: sel, notes0: ex?.notes ?? '');
        }));
      _loading = false;
    });
  }

  double _factorOf(Item it, String unitName) {
    for (final u in _catalog.unitsOf(it)) {
      if (u.name == unitName) return u.factor <= 0 ? 1 : u.factor;
    }
    return 1;
  }

  List<_RatRow> _visible() {
    final q = _q.text.trim().toLowerCase();
    return _rows.where((r) {
      if (q.isNotEmpty && !'${r.item.code} ${r.item.name}'.toLowerCase().contains(q)) return false;
      if (_filter == 'set') return r.hasEnt;
      if (_filter == 'zero') return !r.hasEnt;
      return true;
    }).toList();
  }

  int get _dirtyCount => _rows.where((r) => r.dirty).length;
  int get _setCount => _rows.where((r) => r.hasEnt).length;

  /// `ratSaveAll()` — تُحفظ السطور المعدَّلة فقط بعد التحقق من كل القيم.
  Future<void> _saveAll() async {
    if (!_perm.guard(context, 'ratios', PermAction.edit)) return;
    if (_rows.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات لحفظها', error: true);
      return;
    }
    for (final (i, r) in _rows.indexed) {
      if (r.bad) {
        showImdToast(
            context, '✖ قيمة الاستحقاق غير صحيحة للصنف «${r.item.name}» بالسطر ${nf(i + 1)}',
            error: true);
        return;
      }
    }
    final dirty = _rows.where((r) => r.dirty).toList();
    if (dirty.isEmpty) {
      showImdToast(context, 'ℹ لا توجد تعديلات لحفظها');
      return;
    }

    var saved = 0;
    for (final r in dirty) {
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      final notes = r.notes.text.trim();
      // سطر فارغ بلا مقرر سابق: لا يُنشأ له سجل.
      if (qty == 0 && notes.isEmpty && r.qty0.isEmpty && r.notes0.isEmpty) continue;
      await _daily.saveEntitlement(
        itemId: r.item.id,
        itemName: r.item.name,
        qtyPerPerson: qty,
        measureUnitName: r.unit,
        measureFactor: _factorOf(r.item, r.unit),
        notes: notes,
      );
      saved++;
    }
    if (!mounted) return;
    if (saved == 0) {
      showImdToast(context, 'ℹ لا توجد مقررات جديدة لحفظها');
      await _load();
      return;
    }
    showImdToast(context, '✔ تم حفظ وتحديث مقررات ${nf(saved)} صنف بنجاح');
    await _load();
  }

  /// `ratExportExcel()`
  Future<void> _export() async {
    final rows = <List<String>>[];
    for (final (i, r) in _rows.indexed) {
      final q = double.tryParse(r.qty.text.trim()) ?? 0;
      rows.add([
        nf(i + 1),
        r.item.code,
        r.item.name,
        _RatRow._norm(q.toString()),
        r.unit,
        q == 0 ? '0' : _RatRow._norm((q / 30).toString()),
        r.notes.text.trim(),
      ]);
    }
    final bytes = ExcelExport.build(
      sheetName: 'المقررات',
      headers: const [
        'م',
        'كود الصنف',
        'اسم الصنف',
        'الاستحقاق الشهري للفرد',
        'وحدة القياس للمقرر',
        'المعدل اليومي للفرد',
        'ملاحظات',
      ],
      rows: rows,
    );
    if (!mounted) return;
    final path = await ImdFiles.saveBytes(context, 'المقررات.xlsx', bytes);
    if (path != null && mounted) showImdToast(context, '✔ صُدِّر الملف');
  }

  /// `ratPrintMilitary()` — لائحة المقررات الرسمية.
  Future<void> _print() async {
    final visible = _visible();
    if (visible.isEmpty) {
      showImdToast(context, '✖ لا توجد بيانات للطباعة', error: true);
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    var i = 0;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'لائحة الاستحقاقات والمقررات المعتمدة',
        headers: const ['م', 'الكود', 'الصنف', 'المقرر الشهري للفرد', 'الوحدة', 'المعدل اليومي', 'ملاحظات'],
        columnFlex: const [1, 2, 5, 3, 2, 3, 4],
        rows: [
          for (final r in visible)
            [
              nf(++i),
              r.item.code,
              r.item.name,
              _RatRow._norm(r.qty.text),
              r.unit,
              r.hasEnt ? nf(((double.parse(r.qty.text.trim()) / 30) * 1000).round() / 1000) : '—',
              r.notes.text.trim(),
            ],
        ],
        leftValues: {'date': imdTodayIso()},
        fieldValues: {'notes': 'عدد الأصناف: ${nf(visible.length)}'},
      ),
      layout: layout,
    );
  }

  static String imdTodayIso() => isoDay(DateTime.now());

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    final w = _writable;
    final dirty = _dirtyCount;
    final visible = _visible();

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'ضبط الاستحقاقات والمقررات (إدخال شبكي مباشر)',
        icon: 'scale',
        subtitle: 'المقرر الشهري للفرد لكل صنف بوحدة القياس المختارة — '
            'يُحتسب تلقائيًا في الصرف والتحويل: (المقرر ÷ ٣٠) × القوة × الأيام',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث باسم أو كود الصنف...',
            onChanged: (_) => setState(() {}),
            actions: [
              if (w) ...[
                ImdButton(
                  label: dirty > 0 ? 'حفظ جميع المقررات (${nf(dirty)})' : 'حفظ جميع المقررات',
                  icon: 'save',
                  onPressed: _saveAll,
                ),
                ImdButton.outline(
                  label: 'تراجع عن التعديلات',
                  icon: 'rotate-ccw',
                  small: true,
                  onPressed: dirty == 0
                      ? null
                      : () async {
                          if (await imdConfirm(context, 'تجاهل كل التعديلات غير المحفوظة؟')) {
                            await _load();
                          }
                        },
                ),
              ],
              ImdButton.outline(label: 'تصدير للإكسيل', icon: 'download', small: true, onPressed: _export),
              ImdButton.outline(label: 'طباعة اللائحة الرسمية', icon: 'printer', small: true, onPressed: _print),
            ],
          ),
          const SizedBox(height: 4),
          ImdChipsRow(bottom: 0, children: [
            _filterChip('all', 'الأصناف: ${nf(_rows.length)}', ImdTone.ok),
            _filterChip('set', 'لها مقرر: ${nf(_setCount)}', ImdTone.code),
            _filterChip('zero', 'بدون مقرر: ${nf(_rows.length - _setCount)}', ImdTone.pend),
            if (dirty > 0) ImdChip('✏️ تعديلات غير محفوظة: ${nf(dirty)}', tone: ImdTone.off),
          ]),
        ]),
      ),
      if (_loading)
        const ImdLd('⏳ جارٍ تحميل الأصناف ونسب الاستحقاق…')
      else
        ImdTable(
          minWidth: 760,
          columns: const [
            ImdCol('م', numeric: true),
            ImdCol('الصنف (الكود والاسم)'),
            ImdCol('الاستحقاق الشهري للفرد', auto: false, width: 170),
            ImdCol('وحدة القياس للمقرر', auto: false, width: 160),
            ImdCol('المعدل اليومي للفرد', auto: false, width: 140),
            ImdCol('ملاحظات', auto: false, width: 200),
          ],
          empty: 'لا توجد أصناف بعد — أضفها من شاشة «إدارة الأصناف»',
          rowColor: (i) => i < visible.length && visible[i].dirty
              ? context.imd.warnSoft.withValues(alpha: .5)
              : null,
          rows: [
            for (final (i, r) in visible.indexed) _row(i, r, w),
          ],
        ),
    ]);
  }

  Widget _filterChip(String value, String label, ImdTone tone) {
    final on = _filter == value;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? context.imd.accent : Colors.transparent, width: 2),
      ),
      child: ImdChip(label, tone: tone, onTap: () => setState(() => _filter = value)),
    );
  }

  List<Widget> _row(int index, _RatRow r, bool w) {
    final c = context.imd;
    final units = _catalog.unitsOf(r.item);
    final qv = double.tryParse(r.qty.text.trim()) ?? 0;
    final daily = r.bad ? 'قيمة غير صحيحة' : (qv > 0 ? '${nf((qv / 30 * 1000).round() / 1000)} ${r.unit}' : '—');

    return [
      Text(nf(index + 1)),
      Text.rich(TextSpan(children: [
        TextSpan(text: r.item.code, style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' — ${r.item.name}'),
      ])),
      ImdFld(
        controller: r.qty,
        number: true,
        dense: true,
        enabled: w,
        hint: 'صفر = لا استحقاق',
        onChanged: (_) => setState(() {}),
      ),
      ImdSelect<String>(
        dense: true,
        items: [for (final u in units) (u.name, u.name)],
        value: r.unit,
        onChanged: w ? (v) => setState(() => r.unit = v ?? r.unit) : null,
      ),
      Text(
        daily,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900, color: r.bad ? c.danger : c.accent),
      ),
      ImdFld(
        controller: r.notes,
        dense: true,
        enabled: w,
        hint: 'ملاحظة أو شرط...',
        onChanged: (_) => setState(() {}),
      ),
    ];
  }
}
