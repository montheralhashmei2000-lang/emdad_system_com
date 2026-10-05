import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../domain/access_control.dart';
import '../../core/print/custody_sheet_print.dart';
import '../../core/print/print_format.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/migration/custody_sheet_import.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/arabic_words.dart';
import '../../domain/custody_sheet.dart';
import '../../domain/finance.dart';
import '../inventory/doc_kit.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

String _fmt(double v) {
  if (v == 0) return '';
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// سطر مسير قيد التحرير — أعمدته بترتيب ملف Excel.
class _SRow {
  _SRow({double rate = kDefaultYerPerSar, LinkCustodySheetRow? r, bool yer = false})
      : grant = TextEditingController(text: _fmt(yer ? (r?.grantYer ?? 0) : (r?.grantSar ?? 0))),
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

  /// رقم الفاتورة الذي سُحبت له بيانات عقدٍ آخر مرة.
  String pulledFor = '';
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

  /// مبلغ العهدة في الخلية يخص عملة المسير: سعوديًّا أو يمنيًّا، ولا تحويل.
  CustodyRowValues valuesFor(String cur) => CustodyRowValues(
        grantSar: cur == FinCurrency.yer ? 0 : _num(grant.text),
        grantYer: cur == FinCurrency.yer ? _num(grant.text) : 0,
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
    {LinkCustodySheet? initial, CustodySheetImport? imported, required String actor, required bool canPrint, bool readOnly = false}) async {
  final repo = LinkageRepo(context.read<AppDatabase>());
  final rows = initial == null ? const <LinkCustodySheetRow>[] : await repo.sheetRows(initial.id);
  if (!context.mounted) return false;
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: SafeArea(child: CustodySheetEditor(initial: initial, initialRows: rows, actor: actor, canPrint: canPrint, readOnly: readOnly)),
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
      {super.key, required this.initial, required this.initialRows, this.imported, required this.actor, required this.canPrint, this.readOnly = false});

  final LinkCustodySheet? initial;
  final List<LinkCustodySheetRow> initialRows;

  /// أسطر مستوردة من Excel تُعرض للمراجعة قبل الحفظ.
  final CustodySheetImport? imported;
  final String actor;
  final bool canPrint;

  /// عرضٌ بلا حفظ لمن لا يملك صلاحية التعديل.
  final bool readOnly;

  @override
  State<CustodySheetEditor> createState() => _CustodySheetEditorState();
}

class _CustodySheetEditorState extends State<CustodySheetEditor> {
  late final _no = TextEditingController(text: widget.initial?.sheetNo ?? widget.imported?.sheetNo ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _rate = TextEditingController(text: _fmt(widget.initial?.defaultRate ?? widget.imported?.defaultRate ?? kDefaultYerPerSar));
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late String _custodyId = widget.initial?.custodyId ?? '';
  late String _currency = widget.initial?.currency ?? FinCurrency.sar;
  List<LinkFinCustody> _custodies = const [];

  /// ما صُرف وأُرجع في مسيراتٍ أخرى للعهدة نفسها (بعملتها) — يُخصم من المتبقي.
  double _otherUsed = 0;

  late final List<_SRow> _rows = [
    for (final r in widget.initialRows) _SRow(r: r, yer: _currency == FinCurrency.yer),
    for (final r in widget.imported?.rows ?? const <ImportedCustodyRow>[]) _SRow.imported(r),
    if (widget.initialRows.isEmpty && (widget.imported?.rows.isEmpty ?? true)) _SRow(rate: kDefaultYerPerSar),
  ];
  List<LinkPurchaseContract> _contracts = const [];
  List<String> _persons = const [], _statements = const [], _categories = const [], _shops = const [];
  bool _busy = false;

  double get _defaultRate => _num(_rate.text) > 0 ? _num(_rate.text) : kDefaultYerPerSar;

  @override
  void initState() {
    super.initState();
    _loadHints();
    _loadCustodies();
    _autoRow();
  }

  bool get _isYer => _currency == FinCurrency.yer;
  String get _unit => '${FinCurrency.short(_currency)}.';
  LinkFinCustody? get _custody => _custodies.where((c) => c.id == _custodyId).firstOrNull;

  /// العهد التي يُفتح لها مسير: قيد الإخلاء وحدها، وعهدة هذا المسير الحالية ولو أُخليت.
  Future<void> _loadCustodies() async {
    final repo = LinkageRepo(context.read<AppDatabase>());
    final all = [
      for (final c in await repo.custodies())
        if (c.status == CustodyStatus.open || c.id == _custodyId) c,
    ];
    if (!mounted) return;
    setState(() => _custodies = all);
    await _loadOtherUsed();
  }

  Future<void> _loadOtherUsed() async {
    final c = _custody;
    if (c == null) {
      if (mounted) setState(() => _otherUsed = 0);
      return;
    }
    final db = context.read<AppDatabase>();
    final sheets = await (db.select(db.linkCustodySheets)..where((t) => t.custodyId.equals(c.id))).get();
    var used = 0.0;
    for (final s in sheets) {
      if (s.id == widget.initial?.id) continue;
      final rows = await (db.select(db.linkCustodySheetRows)..where((t) => t.sheetId.equals(s.id))).get();
      final t = custodyTotalsIn([
        for (final r in rows)
          CustodyRowValues(
              grantSar: r.grantSar, grantYer: r.grantYer, returnSar: r.returnSar, returnYer: r.returnYer, spentSar: r.spentSar, spentYer: r.spentYer, rate: r.rate)
      ], c.currency);
      used += t.spent + t.returned;
    }
    if (mounted) setState(() => _otherUsed = used);
  }

  /// اختيار العهدة يسحب: رقمها إلى «رقم العهدة التشغيلية»، واسم صاحبها إلى «اسم صاحب
  /// العهدة»، ومبلغها وعملتها إلى «مبلغ العهدة» في السطر الأول بعملتها الأصلية.
  void _pickCustody(String id) {
    final prev = _custody;
    final c = _custodies.where((x) => x.id == id).firstOrNull;
    setState(() {
      _custodyId = id;
      if (c == null) return;
      _currency = c.currency;
      _no.text = c.custodyNo;
      _title.text = c.receiverName.isNotEmpty ? c.receiverName : c.holder;
      if (c.currency == FinCurrency.yer && c.exchangeRate > 0) _rate.text = _fmt(c.exchangeRate);
      final first = _rows.first;
      final cur = _num(first.grant.text);
      // لا يُكتب فوق مبلغٍ كتبه المستخدم بيده.
      if (cur == 0 || cur == prev?.amount) first.grant.text = _fmt(c.amount);
    });
    _loadOtherUsed();
  }

  /// السطر الأخير متى امتلأ يُفتح بعده سطرٌ فارغ (بعد سحب عقدٍ أو إدخالٍ يدوي).
  void _autoRow() {
    if (_rows.isNotEmpty && !_rows.last.isEmpty) _rows.add(_SRow(rate: _defaultRate, yer: _isYer));
  }

  void _touch() => setState(_autoRow);

  /// أرقام فواتير عقود العهدة (أو كل العقود إن لم تُحدَّد عهدة) اقتراحًا لحقل رقم الفاتورة.
  List<String> get _invoiceHints => {
        for (final k in _contracts)
          if ((_custodyId.isEmpty || k.custodyId == _custodyId) && k.displayInvoiceNo.isNotEmpty) k.displayInvoiceNo,
      }.toList()
        ..sort();

  /// اقتراحات من مسيرات سابقة: الأسماء والبيانات والفئات والمحلات.
  Future<void> _loadHints() async {
    final db = context.read<AppDatabase>();
    final contracts = await LinkageRepo(db).contracts();
    final all = await db.select(db.linkCustodySheetRows).get();
    Set<String> pick(String Function(LinkCustodySheetRow) f) => {for (final r in all) if (f(r).trim().isNotEmpty) f(r).trim()};
    if (!mounted) return;
    setState(() {
      _contracts = contracts;
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
    _touch();
  }

  LinkCustodySheetRowsCompanion _companion(_SRow r) => LinkCustodySheetRowsCompanion(
        date: Value(r.date),
        grantSar: Value(_isYer ? 0 : _num(r.grant.text)),
        grantYer: Value(_isYer ? _num(r.grant.text) : 0),
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
        custodyId: _custodyId,
        currency: _currency,
        holderName: _title.text.trim(),
        rows: [for (final r in _filled) _companion(r)],
        actor: widget.actor,
      );
      if (!mounted) return id;
      setState(() => _busy = false);
      if (closeAfter) Navigator.of(context).pop(true);
      return id;
    } on LinkBlocked catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showImdToast(context, '✖ ${e.message}', error: true);
      }
      return null;
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
    if (!Perm.of(context).guard(context, 'linkages', PermAction.import)) return;
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

  /// عند كتابة رقم فاتورةٍ يطابق عقد شراء تُسحب بياناته إلى السطر: التاريخ،
  /// والمبلغ المنصرف (سعودي أو يمني بحسب عملة العقد)، وسعر الصرف، والفئة
  /// (التصنيف)، واسم المحل. كلها تبقى قابلةً للتعديل بعد السحب. السحب مرةً
  /// لكل رقمٍ مطابق، فلا يُكتب فوق تعديلٍ يدويٍّ لاحق.
  void _pullFromContract(_SRow r) {
    final no = normalizeInvoiceNo(r.invoiceNo.text);
    if (no.isEmpty || r.pulledFor == no) {
      setState(() {});
      return;
    }
    // عقدٌ واحد لعهدة واحدة: مطابقة عقدٍ مرتبطٍ بعهدةٍ أخرى مرفوضة.
    final matches = _contracts.where((c) => c.matchesInvoice(no)).toList();
    final match = matches.where((c) => _custodyId.isEmpty || c.custodyId == _custodyId).firstOrNull ??
        matches.where((c) => c.custodyId.isEmpty).firstOrNull;
    if (match == null) {
      r.pulledFor = '';
      if (matches.isNotEmpty) {
        showImdToast(context, '✖ هذا العقد مرتبط بعهدةٍ أخرى — لا يُسحب إلى مسير هذه العهدة', error: true);
      }
      setState(() {});
      return;
    }
    r.pulledFor = no;
    setState(() {
      r.date = match.listDate;
      r.category.text = match.title;
      r.shop.text = match.supplier;
      if (match.currency == LinkCurrency.yer) {
        if (match.exchangeRate > 0) r.rate.text = _fmt(match.exchangeRate);
        r.spentYer.text = _fmt(match.amount);
      } else {
        r.spentYer.text = '';
        r.spentSar.text = _fmt(match.amount);
      }
      r.sync();
      _autoRow();
    });
    showImdToast(context, '✔ سُحبت بيانات عقد «${match.title}» — راجعها وعدّل ما يلزم');
  }

  Widget _invoiceCell(BuildContext context, _SRow r, bool dup) {
    final c = context.imd;
    final field = ImdFld(controller: r.invoiceNo, suggestions: _invoiceHints, onChanged: (_) => _pullFromContract(r));
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
      minWidth: 1790,
      columns: const [
        ImdCol('التاريخ', width: 138),
        ImdCol('مبلغ العهدة', width: 124),
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
            cell(ImdFld(
                controller: r.grant,
                number: true,
                suffix: Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Text(_unit, style: TextStyle(fontSize: 11, color: context.imd.muted))),
                onChanged: (_) => _touch())),
            cell(ImdFld(controller: r.retSar, number: true, readOnly: r.retLocked, onChanged: (_) => _touch())),
            cell(ImdFld(controller: r.retYer, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.spentSar, number: true, readOnly: r.spentLocked, onChanged: (_) => _touch())),
            cell(ImdFld(controller: r.spentYer, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.rate, number: true, onChanged: (_) => _changed(r))),
            cell(ImdFld(controller: r.person, suggestions: _persons, onChanged: (_) => _touch())),
            cell(ImdFld(controller: r.statement, suggestions: _statements, onChanged: (_) => _touch())),
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

  Widget _totalLine(String label, double value, Color bg, Color fg, {String? tail, String? unit}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ImdSizes.radius)),
        child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          Text('${printMoney(value)} ${unit ?? _unit}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg)),
          if (tail != null) Text(tail, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final totals = custodyTotalsIn([for (final r in _filled) r.valuesFor(_currency)], _currency);
    final spentOther = custodyTotalsIn([for (final r in _filled) r.valuesFor(_currency)], _isYer ? FinCurrency.sar : FinCurrency.yer).spent;
    final cust = _custody;
    final custodyRemaining = cust == null ? null : cust.amount - _otherUsed - totals.spent - totals.returned;
    final no = _no.text.trim().isEmpty ? '   ' : _no.text.trim();
    final over = totals.remaining < 0;
    final sentence = '${over ? 'تجاوز المنصرف العهدة التشغيلية رقم ($no) بمبلغ وقدره' : 'متبقي لكم من العهدة التشغيلية رقم ($no) مبلغ وقدره'} '
        '${amountInWords(totals.remaining, major: _isYer ? 'ريال يمني' : 'ريال سعودي', minor: _isYer ? 'فلس' : 'هللة')}';
    return ImdStickyPage(
      sticky: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          ImdButton.outline(label: widget.readOnly ? 'رجوع' : 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
          if (widget.canPrint && !widget.readOnly) ImdButton.outline(label: 'حفظ وطباعة', icon: 'printer', busy: _busy, onPressed: _saveAndPrint),
          if (!widget.readOnly) ImdButton(label: 'حفظ المسير', icon: 'save', busy: _busy, onPressed: _save),
        ]),
      ),
      children: [
        if (widget.readOnly) const ImdNote('وضع العرض فقط — لا تملك صلاحية التعديل، فلا يظهر زر الحفظ.'),
        ImdPageTitle(
          title: widget.initial == null ? 'مسير عهدة جديد' : (widget.readOnly ? 'عرض مسير العهدة' : 'تعديل مسير العهدة'),
          icon: 'dollar',
          subtitle: 'يطابق ملف Excel المعتمد — المنصرف باليمني يُحوَّل بسعر الصرف، وتكرار رقم الفاتورة يُلوَّن',
        ),
        ImdPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdGrid(columns: 4, minItemWidth: 200, gap: 12, children: [
            ImdLabeled(
                'العهدة (قيد الإخلاء)',
                ImdSelect<String>(
                  items: [
                    ('', 'بلا عهدة (مسير حر)'),
                    for (final c in _custodies) (c.id, '${c.custodyNo} · ${c.title} — ${printNum(c.amount)} ${FinCurrency.short(c.currency)}'),
                  ],
                  value: _custodies.any((c) => c.id == _custodyId) ? _custodyId : '',
                  onChanged: (v) => _pickCustody(v ?? ''),
                )),
            ImdLabeled('رقم العهدة التشغيلية', ImdFld(controller: _no, onChanged: (_) => setState(() {}))),
            ImdLabeled('اسم صاحب العهدة', ImdFld(controller: _title)),
            ImdLabeled('سعر الصرف الافتراضي (يمني لكل سعودي)', ImdFld(controller: _rate, number: true)),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
          ]),
          const SizedBox(height: 10),
          // المتبقي من العهدة يتحدث بعد كل سطر، بعملة العهدة.
          ImdKpis(children: [
            ImdKpi(label: 'مبلغ العهدة (${FinCurrency.label(_currency)})', value: '${printMoney(cust?.amount ?? totals.granted)} $_unit', icon: 'shield', color: c.warn),
            ImdKpi(label: 'المصروف في هذا المسير', value: '${printMoney(totals.spent)} $_unit', icon: 'upload', color: c.info),
            if (cust != null && _otherUsed > 0) ImdKpi(label: 'مصروف في مسيراتٍ أخرى', value: '${printMoney(_otherUsed)} $_unit', icon: 'clipboard', color: c.muted),
            ImdKpi(
                label: 'المتبقي من العهدة',
                value: '${printMoney(custodyRemaining ?? totals.remaining)} $_unit',
                icon: 'scale',
                color: (custodyRemaining ?? totals.remaining) < 0 ? c.danger : c.success),
          ]),
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
            _totalLine('اجمالي العهدة بالريال ${FinCurrency.label(_currency)}', totals.granted, c.warnSoft, c.text),
            const SizedBox(height: 6),
            _totalLine('اجمالي المبلغ المنصرف بالريال ${FinCurrency.label(_currency)}', totals.spent, c.infoSoft, c.text),
            if (spentOther > 0) ...[
              const SizedBox(height: 6),
              _totalLine('المنصرف بالريال ${_isYer ? 'السعودي' : 'اليمني'} (بسعر صرف الأسطر)', spentOther, c.infoSoft, c.text, unit: _isYer ? 'ر.س.' : 'ر.ي.'),
            ],
            if (totals.returned > 0) ...[
              const SizedBox(height: 6),
              _totalLine('اجمالي المرتجع بالريال ${FinCurrency.label(_currency)}', totals.returned, c.successSoft, c.text),
            ],
            const SizedBox(height: 6),
            _totalLine(over ? 'العجز بالريال ${FinCurrency.label(_currency)}' : 'المتبقي بالريال ${FinCurrency.label(_currency)}', totals.remaining.abs(), c.dangerSoft, c.danger, tail: sentence),
          ]),
        ),
      ],
    );
  }
}
