import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/print/contract_print.dart';
import '../../core/print/print_format.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/ocr/invoice_models.dart';
import '../../data/ocr/invoice_scanner.dart';
import '../../data/ocr/ocr_engine.dart';
import '../../data/repos/linkage_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/arabic_words.dart';
import '../../domain/finance.dart';
import '../../domain/invoice_merge.dart';
import '../inventory/doc_kit.dart';
import 'invoice_scan_ui.dart';

double _num(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

String _fmt(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());

/// سطر أصناف قيد التحرير. الأصناف نصٌّ حر: لا منتقي أصناف ولا ربط بالمخزون،
/// فمسميات الفواتير عند التجار تختلف عن مسميات النظام.
class _ItemRow {
  _ItemRow([ContractItem? i])
      : name = TextEditingController(text: i?.name ?? ''),
        unit = TextEditingController(text: i?.unit ?? ''),
        qty = TextEditingController(text: _fmt(i?.qty ?? 0)),
        price = TextEditingController(text: _fmt(i?.price ?? 0)),
        total = TextEditingController(text: _fmt(i?.total ?? 0)),
        invoiceNo = TextEditingController(text: i?.invoiceNo ?? ''),
        note = TextEditingController(text: i?.note ?? ''),
        date = i?.date ?? '',
        // إجماليٌّ محفوظ يخالف (الكمية × السعر) عُدِّل يدويًّا فلا يُكتب فوقه.
        totalTouched = i != null && i.total != 0 && i.total != ContractItem.autoTotal(i.qty, i.price);

  final key = UniqueKey();
  final TextEditingController name, unit, qty, price, total, invoiceNo, note;
  String date;
  bool totalTouched;

  void dispose() {
    for (final c in [name, unit, qty, price, total, invoiceNo, note]) {
      c.dispose();
    }
  }

  ContractItem get value => ContractItem(
        name: name.text.trim(),
        unit: unit.text.trim(),
        qty: _num(qty.text),
        price: _num(price.text),
        total: _num(total.text),
        invoiceNo: invoiceNo.text.trim(),
        date: date,
        note: note.text.trim(),
      );
}

/// فتح محرر عقد الشراء. يعيد true عند الحفظ.
Future<bool> openContractEditor(BuildContext context,
    {LinkPurchaseContract? initial, required String actor, required bool canPrint, bool readOnly = false}) async {
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: SafeArea(child: ContractEditor(initial: initial, actor: actor, canPrint: canPrint, readOnly: readOnly)),
    ),
  ));
  return saved == true;
}

/// محرر «عقد الشراء» بحسب النموذج المعتمد: رأس (التصنيف، التاجر، العملة، سعر
/// الصرف، تاريخ القائمة) ثم أسطر الأصناف النصية الحرة ثم الإجمالي والتفقيط.
/// سطر المقابل بالسعودي لا يظهر إلا مع العملة اليمنية.
class ContractEditor extends StatefulWidget {
  const ContractEditor({super.key, required this.initial, required this.actor, required this.canPrint, this.readOnly = false});

  final LinkPurchaseContract? initial;
  final String actor;
  final bool canPrint;

  /// عرضٌ بلا حفظ لمن لا يملك صلاحية التعديل.
  final bool readOnly;

  @override
  State<ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends State<ContractEditor> {
  LinkPurchaseContract? get _i => widget.initial;

  late final _no = TextEditingController(text: _i?.contractNo ?? '');
  late final _title = TextEditingController(text: _i?.title ?? '');
  late final _supplier = TextEditingController(text: _i?.supplier ?? '');
  late final _rate = TextEditingController(text: _fmt(_i?.exchangeRate ?? 0));
  late final _invoice = TextEditingController(text: _i?.invoiceNo ?? '');
  late final _notes = TextEditingController(text: _i?.notes ?? '');
  late String _currency = _i?.currency ?? LinkCurrency.sar;
  late String _listDate = _i?.listDate ?? '';
  late String _endDate = _i?.endDate ?? '';
  late String _custodyId = _i?.custodyId ?? '';
  List<LinkFinCustody> _custodies = const [];
  bool _advanced = false;
  late String _status = _i?.status ?? LinkContractStatus.open;
  late final List<_ItemRow> _rows = [
    for (final i in ContractItem.decode(_i?.itemsJson ?? '[]')) _ItemRow(i),
    if (ContractItem.decode(_i?.itemsJson ?? '[]').isEmpty) _ItemRow()
      ..invoiceNo.text = _i?.invoiceNo ?? ''
      ..date = _i?.listDate ?? '',
  ];
  late String _prevInvoice = (_i?.invoiceNo ?? '').trim();
  List<String> _nameHints = const [];
  List<String> _unitHints = const [];
  List<String> _shopHints = const [];
  List<String> _categoryHints = const [];
  bool _busy = false;

  /// تنبيهات آخر مسح (تبقى ظاهرة حتى يُغلقها المستخدم).
  List<String> _scanNotes = const [];
  int _scannedCount = 0;

  bool get _isYer => _currency == LinkCurrency.yer;

  /// تنبيه حين يلزم تحويل مبلغ العقد إلى عملة العهدة ولا سعر صرفٍ متاح.
  String get _custodyNote {
    final c = _custodies.where((x) => x.id == _custodyId).firstOrNull;
    if (c == null || c.currency == _currency) return '';
    final rate = _isYer ? _num(_rate.text) : c.exchangeRate;
    return rate > 0 ? '' : 'عملة العقد تختلف عن عملة العهدة ${c.custodyNo} ولا يوجد سعر صرف — لن يُحتسب هذا العقد في المستهلك حتى يُدخل سعر الصرف.';
  }

  @override
  void initState() {
    super.initState();
    _advanced = _endDate.isNotEmpty;
    _loadHints();
  }

  Future<void> _loadHints() async {
    final repo = LinkageRepo(context.read<AppDatabase>());
    final all = await repo.contracts();
    // العهد التي يُربط بها عقد: القائمة (قيد الإخلاء) وحدها، وعهدة هذا العقد الحالية ولو أُخليت.
    final custodies = [
      for (final c in await repo.custodies())
        if (c.status == CustodyStatus.open || c.id == _custodyId) c,
    ];
    final names = <String>{}, units = <String>{}, shops = <String>{}, cats = <String>{};
    for (final c in all) {
      if (c.supplier.trim().isNotEmpty) shops.add(c.supplier.trim());
      if (c.title.trim().isNotEmpty) cats.add(c.title.trim());
      for (final it in ContractItem.decode(c.itemsJson)) {
        if (it.name.isNotEmpty) names.add(it.name);
        if (it.unit.isNotEmpty) units.add(it.unit);
      }
    }
    if (!mounted) return;
    setState(() {
      _custodies = custodies;
      _nameHints = names.toList()..sort();
      _unitHints = units.toList()..sort();
      _shopHints = shops.toList()..sort();
      _categoryHints = cats.toList()..sort();
    });
  }

  @override
  void dispose() {
    for (final c in [_no, _title, _supplier, _rate, _invoice, _notes]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// رقم الفاتورة وتاريخ القائمة في الرأس يُسحبان إلى أسطر الأصناف تلقائيًّا:
  /// السطر الفارغ أو الذي يطابق القيمة السابقة يتبع الجديدة، وما عدّله المستخدم
  /// بيده يبقى كما هو.
  void _followHeader({String? oldInvoice, String? oldDate}) {
    for (final r in _rows) {
      if (oldInvoice != null && (r.invoiceNo.text.trim().isEmpty || r.invoiceNo.text.trim() == oldInvoice.trim())) {
        r.invoiceNo.text = _invoice.text.trim();
      }
      if (oldDate != null && (r.date.isEmpty || r.date == oldDate)) r.date = _listDate;
    }
  }

  _ItemRow _newRow() => _ItemRow()
    ..invoiceNo.text = _invoice.text.trim()
    ..date = _listDate;

  List<ContractItem> get _items => [for (final r in _rows) r.value];
  double get _total => ContractItem.sum(_items);

  /// الإجمالي يُحسب تلقائيًّا (الكمية × السعر) ما لم يُعدَّل يدويًّا.
  void _recalc(_ItemRow r) {
    if (!r.totalTouched) {
      final p = _num(r.price.text);
      r.total.text = p == 0 && _num(r.qty.text) == 0 ? '' : _fmt(ContractItem.autoTotal(_num(r.qty.text), p));
    }
    setState(() {});
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'التصنيف مطلوب (مواد غذائية، بهارات…)';
    if (_isYer && _num(_rate.text) <= 0) return 'أدخل سعر الصرف للعملة اليمنية';
    if (_items.where((i) => !i.isEmpty).isEmpty) return 'أضف صنفًا واحدًا على الأقل';
    return null;
  }

  LinkPurchaseContractsCompanion _companion() => LinkPurchaseContractsCompanion(
        contractNo: Value(_no.text.trim()),
        title: Value(_title.text.trim()),
        supplier: Value(_supplier.text.trim()),
        invoiceNo: Value(_invoice.text.trim()),
        currency: Value(_currency),
        exchangeRate: Value(_isYer ? _num(_rate.text) : 0),
        listDate: Value(_listDate),
        itemsJson: Value(ContractItem.encode(_items)),
        amount: Value(_total),
        endDate: Value(_endDate),
        custodyId: Value(_custodyId),
        status: Value(_status),
        notes: Value(_notes.text.trim()),
        updatedAt: Value(DateTime.now()),
      );

  Future<LinkPurchaseContract?> _save({bool closeAfter = true}) async {
    final err = _validate();
    if (err != null) {
      showImdToast(context, '✖ $err', error: true);
      return null;
    }
    setState(() => _busy = true);
    final db = context.read<AppDatabase>();
    final repo = LinkageRepo(db);
    final id = _i?.id ?? Ids.next('lk');
    try {
      if (_i == null) {
        await repo.insertContract(
          _companion().copyWith(id: Value(id), createdBy: Value(widget.actor), createdAt: Value(DateTime.now())),
          actor: widget.actor,
        );
      } else {
        await repo.updateContract(_i!, _companion(), actor: widget.actor);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showImdToast(context, '✖ $e', error: true);
      }
      return null;
    }
    final saved = (await repo.contracts()).firstWhere((c) => c.id == id);
    if (!mounted) return saved;
    setState(() => _busy = false);
    if (closeAfter) Navigator.of(context).pop(true);
    return saved;
  }

  Future<void> _saveAndPrint() async {
    final db = context.read<AppDatabase>();
    final saved = await _save(closeAfter: false);
    if (saved == null || !mounted) return;
    await ContractPrint.print(db, saved);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// مسح فاتورة (كاميرا أو ملف ممسوح) وسحب بياناتها إلى أصناف العقد ورأسه.
  /// ما يُسحب يُضاف كأسطر عادية قابلة للتعديل؛ والإجمالي يبقى مجموع الأصناف.
  Future<void> _scanInvoice({InvoiceScanner? scannerForTest}) async {
    final settingsRepo = SettingsRepo(context.read<AppDatabase>());
    final source = await chooseInvoiceSource(context);
    if (source == null || !mounted) return;
    if (source == InvoiceSource.settings) {
      await showOcrSetup(context, settingsRepo);
      return;
    }
    // محرك القراءة المحلي: Tesseract المضمَّن على الهاتف، أو المثبّت على الحاسوب.
    var engine = scannerForTest == null ? await createOcrEngine(settingsRepo) : null;
    if (scannerForTest == null && engine == null) {
      if (!mounted) return;
      final ready = await showOcrSetup(context, settingsRepo);
      if (!ready || !mounted) return;
      engine = await createOcrEngine(settingsRepo);
      if (engine == null) return;
    }
    final List<PickedInvoiceFile> files;
    try {
      files = await pickInvoiceFiles(source);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّر فتح الكاميرا/الملف: $e', error: true);
      return;
    }
    if (files.isEmpty || !mounted) return;

    final scanner = scannerForTest ?? InvoiceScanner(engine!);
    final progress = ValueNotifier<String>('جارٍ قراءة الفاتورة…');
    showScanProgress(context, progress);
    final invoices = <ScannedInvoice>[];
    final errors = <String>[];
    for (final (i, f) in files.indexed) {
      progress.value = 'جارٍ قراءة ${files.length > 1 ? 'الملف ${i + 1} من ${files.length}: ' : ''}${f.name}…';
      try {
        invoices.addAll(await scanner.scan(f.bytes));
      } on InvoiceScanException catch (e) {
        errors.add('${f.name}: ${e.message}');
      } catch (e) {
        errors.add('${f.name}: $e');
      }
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (!mounted) return;
    if (invoices.isEmpty) {
      showImdToast(context, errors.isEmpty ? '✖ لم تُقرأ أي فاتورة' : '✖ ${errors.first}', error: true);
      return;
    }
    _applyScans(invoices, errors);
  }

  Future<void> _applyScans(List<ScannedInvoice> invoices, List<String> errors) async {
    final hasItems = _rows.any((r) => !r.value.isEmpty);
    final merge = mergeScansIntoContract(
      supplier: _supplier.text,
      listDate: _listDate,
      currency: _currency,
      exchangeRate: _num(_rate.text),
      hasExistingItems: hasItems,
      invoices: invoices,
    );
    if (merge.currencyConflict) {
      final go = await imdConfirm(context, '${merge.warnings.first}\nهل تُضاف الأصناف رغم ذلك (دون تحويل)؟', ok: 'إضافة');
      if (!go || !mounted) return;
    }
    setState(() {
      if (_rows.length == 1 && _rows.first.value.isEmpty) _rows.removeAt(0).dispose();
      for (final it in merge.items) {
        _rows.add(_ItemRow(it));
      }
      _supplier.text = merge.supplier;
      _listDate = merge.listDate;
      _currency = merge.currency;
      if (merge.exchangeRate > 0 && _num(_rate.text) <= 0) _rate.text = _fmt(merge.exchangeRate);
      _scannedCount += merge.items.length;
      _scanNotes = [kOcrReviewNote, ...merge.warnings, ...errors];
    });
    showImdToast(context, '✔ سُحب ${merge.items.length} صنفًا من ${invoices.length} فاتورة — راجعها وعدّل ما يلزم');
  }

  Widget _itemsTable(BuildContext context) {
    const cell = ImdEntryTable.cell;
    return ImdEntryTable(
      minWidth: 880,
      columns: const [
        ImdCol('م', width: 40),
        ImdCol('اسم الصنف', flex: 3),
        ImdCol('الوحدة', width: 96),
        ImdCol('الكمية', width: 84),
        ImdCol('سعر الوحدة', width: 104),
        ImdCol('السعر الإجمالي', width: 112),
        ImdCol('رقم الفاتورة', width: 108),
        ImdCol('تاريخ الشراء', width: 138),
        ImdCol('ملاحظة', flex: 2),
        ImdCol('', width: 48),
      ],
      rowKeys: [for (final r in _rows) r.key],
      rows: [
        for (final (i, r) in _rows.indexed)
          [
            ImdEntryTable.textCell(Text('${i + 1}')),
            cell(ImdFld(controller: r.name, suggestions: _nameHints, onChanged: (_) => setState(() {}))),
            cell(ImdFld(controller: r.unit, suggestions: _unitHints)),
            cell(ImdFld(controller: r.qty, number: true, onChanged: (_) => _recalc(r))),
            cell(ImdFld(controller: r.price, number: true, onChanged: (_) => _recalc(r))),
            cell(ImdFld(
                controller: r.total,
                number: true,
                onChanged: (_) {
                  r.totalTouched = true;
                  setState(() {});
                })),
            cell(ImdFld(controller: r.invoiceNo)),
            // تاريخ الشراء يدوي حسب تاريخ الفاتورة، لكل صنفٍ تاريخه.
            cell(ImdDateField(value: r.date, onChanged: (v) => setState(() => r.date = v))),
            cell(ImdFld(controller: r.note)),
            cell(ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف السطر',
              kind: ImdBtnKind.danger,
              onPressed: () => setState(() {
                _rows.removeAt(i).dispose();
                if (_rows.isEmpty) _rows.add(_newRow());
              }),
            )),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final total = _total;
    final cur = LinkCurrency.label(_currency);
    final rate = _num(_rate.text);
    final words = amountInWords(total, major: LinkCurrency.major(_currency), minor: LinkCurrency.minor(_currency));
    return ImdStickyPage(
      sticky: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          ImdButton.outline(label: widget.readOnly ? 'رجوع' : 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
          if (widget.canPrint && !widget.readOnly) ImdButton.outline(label: 'حفظ وطباعة', icon: 'printer', busy: _busy, onPressed: _saveAndPrint),
          if (!widget.readOnly) ImdButton(label: 'حفظ العقد', icon: 'save', busy: _busy, onPressed: _save),
        ]),
      ),
      children: [
        if (widget.readOnly) const ImdNote('وضع العرض فقط — لا تملك صلاحية التعديل، فلا يظهر زر الحفظ.'),
        ImdPageTitle(
          title: _i == null ? 'عقد شراء جديد' : (widget.readOnly ? 'عرض عقد الشراء' : 'تعديل عقد الشراء'),
          icon: 'clipboard',
          subtitle: 'الأصناف نصٌّ حر بمسميات فاتورة التاجر — لا صلة لها بأصناف النظام',
        ),
        ImdPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdGrid(columns: 4, minItemWidth: 200, gap: 12, children: [
              ImdLabeled('رقم العقد', ImdFld(controller: _no)),
              ImdLabeled('التصنيف * (مواد غذائية، بهارات…)', ImdFld(controller: _title, suggestions: _categoryHints, onChanged: (_) => setState(() {}))),
              ImdLabeled('اسم المحل / التاجر', ImdFld(controller: _supplier, suggestions: _shopHints, onChanged: (_) => setState(() {}))),
              ImdLabeled(
                  'العملة',
                  ImdSelect<String>(
                    items: [for (final e in LinkCurrency.labels.entries) (e.key, e.value)],
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v ?? LinkCurrency.sar),
                  )),
              // سعر الصرف لا يظهر إلا للعملة اليمنية.
              if (_isYer)
                ImdLabeled('سعر الصرف * (ريال يمني لكل سعودي)', ImdFld(controller: _rate, number: true, onChanged: (_) => setState(() {}))),
              ImdLabeled(
                  'قائمة الكمية المستهلكة بتاريخ',
                  ImdDateField(
                      value: _listDate,
                      onChanged: (v) => setState(() {
                            final old = _listDate;
                            _listDate = v;
                            _followHeader(oldDate: old);
                          }))),
              ImdLabeled(
                  'الحالة',
                  ImdSelect<String>(
                    items: [for (final e in LinkContractStatus.meta.entries) (e.key, e.value.$1)],
                    value: _status,
                    onChanged: (v) => setState(() => _status = v ?? LinkContractStatus.open),
                  )),
              ImdLabeled(
                  'العهدة المرتبطة (اختياري — لا تُطبع)',
                  ImdSelect<String>(
                    items: [
                      ('', 'بلا عهدة'),
                      for (final c in _custodies)
                        (c.id, '${c.custodyNo} · ${c.title} — ${printNum(c.amount)} ${FinCurrency.short(c.currency)}'),
                    ],
                    value: _custodies.any((c) => c.id == _custodyId) ? _custodyId : '',
                    onChanged: (v) => setState(() => _custodyId = v ?? ''),
                  )),
              ImdLabeled(
                  'رقم الفاتورة',
                  ImdFld(
                      controller: _invoice,
                      onChanged: (v) => setState(() {
                            // الرقم السابق = ما كان في الأسطر قبل هذا الحرف.
                            for (final r in _rows) {
                              if (r.invoiceNo.text.trim().isEmpty || r.invoiceNo.text.trim() == _prevInvoice) r.invoiceNo.text = v.trim();
                            }
                            _prevInvoice = v.trim();
                          }))),
            ]),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton.outline(
                label: _advanced ? 'إخفاء المتقدم' : 'متقدم',
                icon: 'sliders',
                small: true,
                onPressed: () => setState(() => _advanced = !_advanced),
              ),
            ),
            if (_advanced) ...[
              const SizedBox(height: 8),
              ImdGrid(columns: 4, minItemWidth: 200, gap: 12, children: [
                ImdLabeled('تاريخ الانتهاء (اختياري — للتنبيه)', ImdDateField(value: _endDate, onChanged: (v) => setState(() => _endDate = v))),
              ]),
            ],
            if (_custodyNote.isNotEmpty) ...[const SizedBox(height: 8), ImdNote(_custodyNote)],
          ]),
        ),
        const SizedBox(height: 12),
        ImdPanel(
          title: 'الأصناف',
          icon: 'package',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ImdButton(label: 'مسح فاتورة', icon: 'scan', small: true, onPressed: _scanInvoice),
              if (_scannedCount > 0) ImdChip('سُحب $_scannedCount صنفًا', tone: ImdTone.info, icon: 'check'),
            ]),
            if (_scanNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ImdNote('تنبيهات المسح — راجعها:\n• ${_scanNotes.join('\n• ')}'),
            ],
            const SizedBox(height: 8),
            _itemsTable(context),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton.outline(label: 'إضافة سطر', icon: 'plus', small: true, onPressed: () => setState(() => _rows.add(_newRow()))),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // الإجماليات كما في النموذج المطبوع.
        ImdPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _totalLine(c, 'الإجمالي بالريال $cur', printNum(total), words),
            if (_isYer && rate > 0) ...[
              const SizedBox(height: 6),
              _totalLine(c, 'ما يقابل بالريال السعودي', printMoney(total / rate), 'الإجمالي ÷ سعر الصرف: ${printNum(rate)} ريال يمني'),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _totalLine(ImdColors c, String label, String value, String words) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(ImdSizes.radius)),
        child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: c.text)),
          Text(words, style: TextStyle(color: c.text2)),
        ]),
      );
}
