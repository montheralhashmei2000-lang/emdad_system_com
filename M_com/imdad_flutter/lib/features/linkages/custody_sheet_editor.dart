import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/custody_sheet_print.dart';
import '../../core/print/print_format.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/migration/custody_sheet_import.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/arabic_words.dart';
import '../../domain/custody_sheet.dart';
import '../inventory/doc_kit.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

String _fmt(double v) {
  if (v == 0) return '';
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// سطر مسير قيد التحرير — أعمدته بترتيب ملف Excel.
class _SRow {
  _SRow({double rate = kDefaultYerPerSar, LinkCustodySheetRow? r})
      : grant = TextEditingController(text: _fmt(r?.grantSar ?? 0)),
        retSar = TextEditingController(text: _fmt(r?.returnSar ?? 0)),
        retYer = TextEditingController(text: _fmt(r?.returnYer ?? 0)),
        spentSar = TextEditingController(text: _fmt(r?.spentSar ?? 0)),
        spentYer = TextEditingController(text: _fmt(r?.spentYer ?? 0)),
        rate = TextEditingController(text: _fmt(r?.rate ?? rate)),
        person = TextEditingController(text: r?.person ?? ''),
        statement = TextEditingController(text: r?.statement ?? ''),
        category = TextEditingController(text: r?.category.trim() ?? ''),
        entryNo = TextEditingController(text: r?.entryNo ?? ''),
        invoiceNo = TextEditingController(text: r?.invoiceNo ?? ''),
        shop = TextEditingController(text: r?.shop ?? ''),
        notes = TextEditingController(text: r?.notes ?? ''),
        date = r?.date ?? '' {
    sync();
  }

  /// سطر مقروء من ملف Excel.
  factory _SRow.imported(ImportedCustodyRow r) {
    final row = _SRow(rate: r.rate);
    row.date = r.date;
    row.grant.text = _fmt(r.grantSar);
    row.retSar.text = _fmt(r.returnSar);
    row.retYer.text = _fmt(r.returnYer);
    row.spentSar.text = _fmt(r.spentSar);
    row.spentYer.text = _fmt(r.spentYer);
    row.rate.text = _fmt(r.rate);
    row.person.text = r.person;
    row.statement.text = r.statement;
    row.category.text = r.category;
    row.entryNo.text = r.entryNo;
    row.invoiceNo.text = r.invoiceNo;
    row.shop.text = r.shop;
    row.notes.text = r.notes;
    row.sync();
    return row;
  }

  final key = UniqueKey();
  String date;
  final TextEditingController grant, retSar, retYer, spentSar, spentYer, rate;
  final TextEditingController person, statement, category, entryNo, invoiceNo, shop, notes;

  /// كما في Excel (`=F13/410`): إدخال اليمني يحسب السعودي = اليمني ÷ سعر الصرف
  /// ويقفل خليته؛ ومسح اليمني يعيد خلية السعودي للإدخال اليدوي.
  void sync() {
    final r = _num(rate.text);
    if (_num(spentYer.text) > 0 && r > 0) spentSar.text = _fmt(_num(spentYer.text) / r);
    if (_num(retYer.text) > 0 && r > 0) retSar.text = _fmt(_num(retYer.text) / r);
  }

  bool get spentLocked => _num(spentYer.text) > 0 && _num(rate.text) > 0;
  bool get retLocked => _num(retYer.text) > 0 && _num(rate.text) > 0;

  CustodyRowValues get values => CustodyRowValues(
        grantSar: _num(grant.text),
        returnSar: _num(retSar.text),
        returnYer: _num(retYer.text),
        spentSar: _num(spentSar.text),
        spentYer: _num(spentYer.text),
        rate: _num(rate.text),
      );

  bool get isEmpty =>
      date.isEmpty &&
      [grant, retSar, retYer, spentSar, spentYer, person, statement, category, entryNo, invoiceNo, shop, notes]
          .every((c) => c.text.trim().isEmpty);

  void dispose() {
    for (final c in [grant, retSar, retYer, spentSar, spentYer, rate, person, statement, category, entryNo, invoiceNo, shop, notes]) {
      c.dispose();
    }
  }
}

/// فتح محرر مسير العهدة. يعيد true عند الحفظ.
Future<bool> openCustodySheetEditor(BuildContext context,
    {LinkCustodySheet? initial, CustodySheetImport? imported, required String actor, required bool canPrint}) async {
  final repo = LinkageRepo(context.read<AppDatabase>());
  final rows = initial == null ? const <LinkCustodySheetRow>[] : await repo.sheetRows(initial.id);
  if (!context.mounted) return false;
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: SafeArea(child: CustodySheetEditor(initial: initial, initialRows: rows, actor: actor, canPrint: canPrint)),
    ),
  ));
  return saved == true;
}

/// محرر «مسير العهدة» بتنسيق ملف Excel المعتمد.
///
/// نفس الأعمدة والترتيب، والمنصرف اليمني يُحوَّل بسعر الصرف، وتكرار أي قيمة في
/// «رقم الفاتورة» يُلوَّن بالأحمر الفاتح، وأسفل الجدول إجمالي العهدة (برتقالي)
/// والمنصرف (ذهبي) والمتبقي (أحمر) وجملة المتبقي بالحروف.
class CustodySheetEditor extends StatefulWidget {
  const CustodySheetEditor(
      {super.key, required this.initial, required this.initialRows, this.imported, required this.actor, required this.canPrint});

  final LinkCustodySheet? initial;
  final List<LinkCustodySheetRow> initialRows;

  /// أسطر مستوردة من Excel تُعرض للمراجعة قبل الحفظ.
  final CustodySheetImport? imported;
  final String actor;
  final bool canPrint;

  @override
  State<CustodySheetEditor> createState() => _CustodySheetEditorState();
}

class _CustodySheetEditorState extends State<CustodySheetEditor> {
  late final _no = TextEditingController(text: widget.initial?.sheetNo ?? widget.imported?.sheetNo ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _rate = TextEditingController(text: _fmt(widget.initial?.defaultRate ?? widget.imported?.defaultRate ?? kDefaultYerPerSar));
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late final List<_SRow> _rows = [
    for (final r in widget.initialRows) _SRow(r: r),
    for (final r in widget.imported?.rows ?? const <ImportedCustodyRow>[]) _SRow.imported(r),
    if (widget.initialRows.isEmpty && (widget.imported?.rows.isEmpty ?? true)) _SRow(rate: kDefaultYerPerSar),
  ];
  List<String> _persons = const [], _statements = const [], _categories = const [], _shops = const [];
  bool _busy = false;

  double get _defaultRate => _num(_rate.text) > 0 ? _num(_rate.text) : kDefaultYerPerSar;

  @override
  void initState() {
    super.initState();
    _loadHints();
  }

  /// اقتراحات من مسيرات سابقة: الأسماء والبيانات والفئات والمحلات.
  Future<void> _loadHints() async {
    final db = context.read<AppDatabase>();
    final all = await db.select(db.linkCustodySheetRows).get();
    Set<String> pick(String Function(LinkCustodySheetRow) f) => {for (final r in all) if (f(r).trim().isNotEmpty) f(r).trim()};
    if (!mounted) return;
    setState(() {
      _persons = pick((r) => r.person).toList()..sort();
      _statements = pick((r) => r.statement).toList()..sort();
      _categories = pick((r) => r.category).toList()..sort();
      _shops = pick((r) => r.shop).toList()..sort();
    });
  }

  @override
  void dispose() {
    for (final c in [_no, _title, _rate, _notes]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<_SRow> get _filled => [for (final r in _rows) if (!r.isEmpty) r];

  void _changed(_SRow r) {
    r.sync();
    setState(() {});
  }

  LinkCustodySheetRowsCompanion _companion(_SRow r) => LinkCustodySheetRowsCompanion(
        date: Value(r.date),
        grantSar: Value(_num(r.grant.text)),
        returnSar: Value(_num(r.retSar.text)),
        returnYer: Value(_num(r.retYer.text)),
        spentSar: Value(_num(r.spentSar.text)),
        spentYer: Value(_num(r.spentYer.text)),
        rate: Value(_num(r.rate.text) > 0 ? _num(r.rate.text) : _defaultRate),
        person: Value(r.person.text.trim()),
        statement: Value(r.statement.text.trim()),
        category: Value(r.category.text.trim()),
        entryNo: Value(r.entryNo.text.trim()),
        invoiceNo: Value(r.invoiceNo.text.trim()),
        shop: Value(r.shop.text.trim()),
        notes: Value(r.notes.text.trim()),
      );

  Future<String?> _save({bool closeAfter = true}) async {
    if (_filled.isEmpty) {
      showImdToast(context, '✖ أضف سطرًا واحدًا على الأقل', error: true);
      return null;
    }
    setState(() => _busy = true);
    try {
      final id = await LinkageRepo(context.read<AppDatabase>()).saveCustodySheet(
        id: widget.initial?.id,
        sheetNo: _no.text.trim(),
        title: _title.text.trim(),
        defaultRate: _defaultRate,
        notes: _notes.text.trim(),
        rows: [for (final r in _filled) _companion(r)],
        actor: widget.actor,
      );
      if (!mounted) return id;
      setState(() => _busy = false);
      if (closeAfter) Navigator.of(context).pop(true);
      return id;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showImdToast(context, '✖ $e', error: true);
      }
      return null;
    }
  }

  /// يطبع الحالة الحالية للمحرر (محفوظةً كانت أم لا) ثم يغلق.
  Future<void> _saveAndPrint() async {
    final db = context.read<AppDatabase>();
    final id = await _save(closeAfter: false);
    if (id == null || !mounted) return;
    final repo = LinkageRepo(db);
    final sheet = (await repo.custodySheets()).firstWhere((s) => s.id == id);
    await CustodySheetPrint.print(db, sheet, await repo.sheetRows(id));
    if (mounted) Navigator.of(context).pop(true);
  }

  /// يضيف أسطر ملف Excel (بتنسيق المسير المعتمد) إلى المحرر للمراجعة قبل الحفظ.
  Future<void> _importExcel() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
      final bytes = res?.files.firstOrNull?.bytes;
      if (res == null || bytes == null) return;
      final parsed = CustodySheetImporter.parse(bytes);
      if (!mounted) return;
      setState(() {
        // السطر الفارغ الوحيد يُستبدل بالمستورد.
        if (_rows.length == 1 && _rows.first.isEmpty) _rows.removeAt(0).dispose();
        for (final r in parsed.rows) {
          _rows.add(_SRow.imported(r));
        }
        if (_no.text.trim().isEmpty && parsed.sheetNo.isNotEmpty) _no.text = parsed.sheetNo;
      });
      showImdToast(context, '✔ استُوردت ${parsed.rows.length} سطرًا — راجعها ثم اضغط حفظ${parsed.warnings.isEmpty ? '' : ' · ${parsed.warnings.join('، ')}'}');
    } on FormatException catch (e) {
      if (mounted) showImdToast(context, '✖ ${e.message}', error: true);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّر الاستيراد: $e', error: true);
    }
  }

  Widget _invoiceCell(BuildContext context, _SRow r, bool dup) {
    final c = context.imd;
    final field = ImdFld(controller: r.invoiceNo, onChanged: (_) => setState(() {}));
    if (!dup) return ImdEntryTable.cell(field);
    // التكرار: تظليل أحمر فاتح فوق الحقل دون اعتراض الكتابة (CF duplicateValues في Excel).
    return ImdEntryTable.cell(Stack(children: [
      field,
      Positioned.fill(child: IgnorePointer(child: ColoredBox(color: c.danger.withValues(alpha: 0.2)))),
    ]));
  }

  Widget _table(BuildContext context) {
    const cell = ImdEntryTable.cell;
    final dups = duplicateInvoiceNos([for (final r in _rows) r.invoiceNo.text]);
    return ImdEntryTable(
      cards: true,
      minWidth: 1790,
      columns: const [
        ImdCol('التاريخ', width: 138),
        ImdCol('مبلغ العهدة\nسعودي', width: 112),
        ImdCol('مرتجع\nسعودي', width: 96),
        ImdCol('مرتجع\nيمني', width: 96),
        ImdCol('المبلغ المنصرف\nسعودي', width: 118),
        ImdCol('المبلغ المنصرف\nيمني', width: 118),
        ImdCol('سعر\nالصرف', width: 76),
        ImdCol('الاسم', width: 150),
        ImdCol('البيان', width: 200),
        ImdCol('الفئة', width: 110),
        ImdCol('رقم القيد', width: 84),
        ImdCol('رقم الفاتورة', width: 112),
        ImdCol('اسم المحل', width: 170),
        ImdCol('ملاحظات', width: 140),
        ImdCol('', width: 48),
      ],
      rowKeys: [for (final r in _rows) r.key],
      rows: [
        for (final (i, r) in _rows.indexed)
          [
            cell(ImdDateField(value: r.date, onChanged: (v) => setState(() => r.date = v))),
            cell(ImdFld(controller: r.grant, number: true, onChanged: (_) => setState(() {}))),
            cell(ImdFld(controller: r.retSar, number: true, readOnly: r.retLocked, onChanged: (_) => setState(() {}))),
            cell(ImdFld(controller: r.retYer, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.spentSar, number: true, readOnly: r.spentLocked, onChanged: (_) => setState(() {}))),
            cell(ImdFld(controller: r.spentYer, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.rate, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.person, suggestions: _persons)),
            cell(ImdFld(controller: r.statement, suggestions: _statements)),
            cell(ImdFld(controller: r.category, suggestions: _categories)),
            cell(ImdFld(controller: r.entryNo)),
            _invoiceCell(context, r, dups.contains(normalizeInvoiceNo(r.invoiceNo.text))),
            cell(ImdFld(controller: r.shop, suggestions: _shops)),
            cell(ImdFld(controller: r.notes)),
            cell(ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف السطر',
              kind: ImdBtnKind.danger,
              onPressed: () => setState(() {
                _rows.removeAt(i).dispose();
                if (_rows.isEmpty) _rows.add(_SRow(rate: _defaultRate));
              }),
            )),
          ],
      ],
    );
  }

  Widget _totalLine(String label, double value, Color bg, Color fg, {String? tail}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ImdSizes.radius)),
        child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          Text('${printMoney(value)} ر.س.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg)),
          if (tail != null) Text(tail, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final totals = custodyTotals([for (final r in _filled) r.values]);
    final no = _no.text.trim().isEmpty ? '   ' : _no.text.trim();
    final over = totals.remaining < 0;
    final sentence = '${over ? 'تجاوز المنصرف العهدة التشغيلية رقم ($no) بمبلغ وقدره' : 'متبقي لكم من العهدة التشغيلية رقم ($no) مبلغ وقدره'} '
        '${amountInWords(totals.remaining, major: 'ريال سعودي', minor: 'هللة')}';
    return ImdStickyPage(
      sticky: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
          if (widget.canPrint) ImdButton.outline(label: 'حفظ وطباعة', icon: 'printer', busy: _busy, onPressed: _saveAndPrint),
          ImdButton(label: 'حفظ المسير', icon: 'save', busy: _busy, onPressed: _save),
        ]),
      ),
      children: [
        ImdPageTitle(
          title: widget.initial == null ? 'مسير عهدة جديد' : 'تعديل مسير العهدة',
          icon: 'dollar',
          subtitle: 'يطابق ملف Excel المعتمد — المنصرف باليمني يُحوَّل بسعر الصرف، وتكرار رقم الفاتورة يُلوَّن',
        ),
        ImdPanel(
          child: ImdGrid(columns: 4, minItemWidth: 200, gap: 12, children: [
            ImdLabeled('رقم العهدة التشغيلية', ImdFld(controller: _no, onChanged: (_) => setState(() {}))),
            ImdLabeled('عنوان المسير', ImdFld(controller: _title)),
            ImdLabeled('سعر الصرف الافتراضي (يمني لكل سعودي)', ImdFld(controller: _rate, number: true)),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
          ]),
        ),
        const SizedBox(height: 12),
        ImdPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _table(context),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton.outline(
                  label: 'إضافة سطر', icon: 'plus', small: true, onPressed: () => setState(() => _rows.add(_SRow(rate: _defaultRate)))),
              ImdButton.outline(label: 'استيراد من Excel', icon: 'upload', small: true, onPressed: _importExcel),
              ImdChip('عدد الأسطر: ${_filled.length}', tone: ImdTone.off),
              if (duplicateInvoiceNos([for (final r in _rows) r.invoiceNo.text]).isNotEmpty)
                const ImdChip('تنبيه: أرقام فواتير مكررة (مظلَّلة)', tone: ImdTone.err, icon: 'alert'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        // الإجماليات بألوان الملف: برتقالي للعهدة، ذهبي للمنصرف، أحمر للمتبقي.
        ImdPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _totalLine('اجمالي العهدة بالريال السعودي', totals.granted, c.warnSoft, c.text),
            const SizedBox(height: 6),
            _totalLine('اجمالي المبلغ المنصرف بالريال السعودي', totals.spent, c.infoSoft, c.text),
            if (totals.returned > 0) ...[
              const SizedBox(height: 6),
              _totalLine('اجمالي المرتجع بالريال السعودي', totals.returned, c.successSoft, c.text),
            ],
            const SizedBox(height: 6),
            _totalLine(over ? 'العجز بالريال السعودي' : 'المتبقي بالريال السعودي', totals.remaining.abs(), c.dangerSoft, c.danger, tail: sentence),
          ]),
        ),
      ],
    );
  }
}
