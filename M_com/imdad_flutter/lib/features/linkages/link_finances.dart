import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/print/document_pdf.dart';

import '../../core/print/contract_print.dart';
import '../../core/print/custody_sheet_print.dart';
import '../../core/print/print_format.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import '../../domain/access_control.dart';
import '../../data/migration/custody_sheet_import.dart';
import '../../domain/custody_sheet.dart';
import '../../domain/finance.dart';
import 'contract_editor.dart';
import 'clearance_form.dart';
import 'custody_detail.dart';
import 'finance_statement.dart';
import 'custody_form.dart';
import 'custody_sheet_editor.dart';
import 'link_export.dart';
import 'money_receipts_tab.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/print_forms.dart';

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

/// تبويب «مالية الإمداد» — ثلاثة فروع مترابطة، **بلا ارتباطٍ بالأفراد**:
///
/// * **العهد**: عهدةٌ تخصّ جهةً مسؤولة (مستودع/مطبخ/مكتب…) وتُفتح بالتسليح،
///   مع تنبيهٍ للمتأخرة عن آخر أجل.
/// * **الإخلاءات**: إغلاقٌ ماليٌّ لعهدةٍ أو عقد؛ تسجيله يغلق مرجعه،
///   وحذفه يعيد فتحه.
/// * **العقود**: عقود المشتريات مع المورد والقيمة ومدّة التنفيذ.
class LinkFinancesTab extends StatefulWidget {
  const LinkFinancesTab({super.key, required this.repo, required this.perm, });

  final LinkageRepo repo;
  final Perm perm;

  @override
  State<LinkFinancesTab> createState() => _LinkFinancesTabState();
}

class _LinkFinancesTabState extends State<LinkFinancesTab> {
  String _sub = 'custody'; // custody | clearances | contracts | sheets | receipts
  final _q = TextEditingController();
  String _view = ''; // عامل تصفية الفرع الحالي
  List<LinkFinCustody>? _custodies;
  List<LinkClearance>? _clearances;
  List<LinkPurchaseContract>? _contracts;
  List<LinkCustodySheet>? _sheets;
  Map<String, CustodyTotals> _sheetTotals = const {};
  Map<String, int> _sheetRowCount = const {};
  List<String> _holders = const [];
  List<String> _names = const [];
  Map<String, CustodyUsage> _usage = const {};
  Map<String, Map<String, double>> _balances = const {};
  Map<String, List<LinkClearance>> _dupClearances = const {};

  // فلاتر العهد: الافتراضي «قيد الإخلاء» فتختفي المُخلَّاة حتى يُطلب عرضها.
  String _cStatus = CustodyStatus.open;
  String _cKind = '';
  String _cPerson = '';
  String _cFrom = '';
  String _cTo = '';

  bool get _canCreate => widget.perm.has('linkages', PermAction.create);
  bool get _canImport => widget.perm.has('linkages', PermAction.import);
  bool get _canEdit => widget.perm.has('linkages', PermAction.edit);
  bool get _canDelete => widget.perm.has('linkages', PermAction.delete);
  bool get _canExport => widget.perm.has('linkages', PermAction.export);
  bool get _canPrint => widget.perm.has('linkages', PermAction.print);
  bool get _canApprove => widget.perm.has('linkages', PermAction.approve);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final custodies = await widget.repo.custodies();
    final clearances = await widget.repo.clearances();
    final contracts = await widget.repo.contracts();
    final holders = await widget.repo.terms('holder');
    final sheets = await widget.repo.custodySheets();
    final usage = await widget.repo.custodyUsage();
    final balances = await widget.repo.partyBalances();
    final dups = await widget.repo.duplicateClearances();
    final persons = await widget.repo.persons();
    final allRows = await widget.repo.allSheetRows();
    final byId = <String, List<CustodyRowValues>>{};
    for (final r in allRows) {
      (byId[r.sheetId] ??= []).add(CustodyRowValues(
          grantSar: r.grantSar, grantYer: r.grantYer, returnSar: r.returnSar, returnYer: r.returnYer, spentSar: r.spentSar, spentYer: r.spentYer, rate: r.rate));
    }
    if (!mounted) return;
    setState(() {
      _sheets = sheets;
      // إجماليات كل مسير بعملته (يمني أو سعودي) لا بالسعودي دائمًا.
      _sheetTotals = {
        for (final e in byId.entries) e.key: custodyTotalsIn(e.value, sheets.where((x) => x.id == e.key).firstOrNull?.currency ?? FinCurrency.sar),
      };
      _sheetRowCount = {for (final e in byId.entries) e.key: e.value.length};
      _custodies = custodies;
      _clearances = clearances;
      _contracts = contracts;
      _holders = [for (final t in holders) t.name];
      _usage = usage;
      _balances = balances;
      _dupClearances = dups;
      _names = ({for (final p in persons) p.fullName.trim(), ..._holders}..remove('')).toList()..sort();
    });
  }

  void _switch(String v) => setState(() {
        _sub = v;
        _view = '';
        _q.clear();
      });

  // ───────────────── العهد ─────────────────

  /// عهدةٌ قائمةٌ تجاوزت آخر أجلها.
  bool _overdue(LinkFinCustody e) =>
      e.status == CustodyStatus.open &&
      e.dueDate.isNotEmpty &&
      (DateTime.tryParse(e.dueDate)?.isBefore(DateTime.now()) ?? false);

  /// الطرف الذي يخصّ الفلتر «الشخص»: المُسلِّم أو المستلم أو الجهة القديمة.
  bool _hasParty(LinkFinCustody c, String name) => [c.giverName, c.receiverName, c.holder].contains(name);

  List<LinkFinCustody> get _custodyRows {
    final q = _q.text.trim().toLowerCase();
    return (_custodies ?? const <LinkFinCustody>[]).where((c) {
      if (_cStatus.isNotEmpty && c.status != _cStatus) return false;
      if (_cKind.isNotEmpty && c.kind != _cKind) return false;
      if (_cPerson.isNotEmpty && !_hasParty(c, _cPerson)) return false;
      if (_cFrom.isNotEmpty && c.custodyDate.compareTo(_cFrom) < 0) return false;
      if (_cTo.isNotEmpty && c.custodyDate.compareTo(_cTo) > 0) return false;
      if (q.isEmpty) return true;
      return [c.custodyNo, c.holder, c.giverName, c.receiverName, c.title, c.serialNo, c.sourceDocNo, c.costCenter]
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  Future<void> _addOrEditCustody([LinkFinCustody? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    if (initial != null && !_canEdit) return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    final saved = await showImdModal<bool>(
      context,
      title: initial == null ? 'تسجيل عهدة' : 'تعديل العهدة: ${initial.custodyNo}',
      icon: 'shield',
      maxWidth: 820,
      builder: (ctx) => CustodyForm(names: _names, initial: initial, actor: widget.perm.email, userName: widget.perm.displayName),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظت العهدة');
    }
  }

  Future<void> _openCustody(LinkFinCustody e) async {
    await showImdModal<void>(
      context,
      title: 'العهدة ${e.custodyNo}',
      icon: 'shield',
      maxWidth: 980,
      builder: (ctx) => CustodyDetail(repo: widget.repo, custodyId: e.id),
    );
  }

  Future<void> _deleteCustody(LinkFinCustody e) async {
    if (!_canDelete) return showImdToast(context, '✖ لا تملك صلاحية الحذف', error: true);
    if (!await imdConfirm(context, 'حذف العهدة ${e.custodyNo} «${e.title}» نهائيًّا؟', ok: 'حذف', danger: true)) return;
    try {
      await widget.repo.deleteCustody(e, actor: widget.perm.email);
      await _load();
    } on LinkBlocked catch (x) {
      if (mounted) showImdToast(context, '✖ ${x.message}', error: true);
    }
  }

  Future<void> _exportCustodies() async {
    final rows = _custodyRows;
    await linkExportExcel(
      context,
      sheetName: 'العهد',
      fileName: 'العهد-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الرقم', 'النوع', 'الغرض', 'المُسلِّم', 'المستلم', 'المبلغ', 'العملة', 'المستهلك', 'المتبقي', 'التاريخ', 'آخر أجل', 'الحالة', 'النتيجة'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].custodyNo,
            CustodyKind.label(rows[i].kind),
            rows[i].title,
            rows[i].giverName.isEmpty ? rows[i].holder : rows[i].giverName,
            rows[i].receiverName,
            nf(rows[i].amount),
            FinCurrency.label(rows[i].currency),
            nf(_usage[rows[i].id]?.consumed ?? 0),
            nf(rows[i].amount - (_usage[rows[i].id]?.consumed ?? 0)),
            _d(rows[i].custodyDate),
            _d(rows[i].dueDate),
            CustodyStatus.label(rows[i].status),
            CustodyOutcome.label(rows[i].outcome),
          ],
      ],
      numericColumns: const {0, 6, 8, 9},
    );
  }

  // ───────────────── الإخلاءات ─────────────────

  List<LinkClearance> get _clearanceRows {
    final q = _q.text.trim().toLowerCase();
    return (_clearances ?? const <LinkClearance>[]).where((c) {
      if (_view.isNotEmpty && c.kind != _view) return false;
      if (q.isEmpty) return true;
      return [c.clearanceNo, c.refTitle, c.partyName, c.notes].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  /// إخلاءٌ جديد أو تعديل إخلاء عهدة. العهد المعروضة: قيد الإخلاء وليس لها إخلاء.
  Future<void> _addClearance({String kind = LinkClearanceKind.custody, String refId = '', LinkClearance? initial}) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    final hasClearance = {for (final c in _clearances ?? const <LinkClearance>[]) if (c.kind == LinkClearanceKind.custody) c.refId};
    final saved = await showImdModal<bool>(
      context,
      title: initial == null ? 'إخلاء جديد' : '${_canEdit ? 'تعديل' : 'عرض'} الإخلاء ${initial.clearanceNo}',
      icon: 'check-circle',
      maxWidth: 900,
      builder: (ctx) => ClearanceForm(
        openCustodies: [for (final c in _custodies ?? const <LinkFinCustody>[]) if (c.status == CustodyStatus.open && !hasClearance.contains(c.id)) c],
        openContracts: [for (final c in _contracts ?? const <LinkPurchaseContract>[]) if (c.status == LinkContractStatus.open) c],
        kind: kind,
        refId: refId,
        initial: initial,
        readOnly: initial != null && !_canEdit,
        canApprove: _canApprove,
        actor: widget.perm.email,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ الإخلاء');
    }
  }

  Future<void> _openStatement([String party = '']) async {
    await showImdModal<void>(
      context,
      title: 'كشف حساب مالية',
      icon: 'file',
      maxWidth: 900,
      builder: (ctx) => FinanceStatement(repo: widget.repo, names: _names, party: party, canExport: _canExport, canPrint: _canPrint),
    );
  }

  Future<void> _deleteClearance(LinkClearance e) async {
    // الإخلاء المُعتمد يمسّ الحسابات: حذفه يتطلب صلاحية الاعتماد.
    final needsApprove = e.kind == LinkClearanceKind.custody && e.workflow == LinkageRepo.wfApproved;
    if (needsApprove ? !_canApprove : !_canDelete) {
      return showImdToast(context, '✖ ${needsApprove ? 'حذف إخلاء مُعتمد يتطلب صلاحية الاعتماد' : 'لا تملك صلاحية الحذف'}', error: true);
    }
    if (!await imdConfirm(
      context,
      'حذف الإخلاء «${e.refTitle.isEmpty ? e.clearanceNo : e.refTitle}»؟ ستعود العهدة/العقد المرتبط إلى حالته القائمة.',
      ok: 'حذف',
      danger: true,
    )) {
      return;
    }
    try {
      await widget.repo.deleteClearance(e, actor: widget.perm.email);
      await _load();
      if (mounted) showImdToast(context, '✔ حُذف الإخلاء');
    } catch (x) {
      if (mounted) showImdToast(context, '✖ $x', error: true);
    }
  }

  Future<void> _exportClearances() async {
    final rows = _clearanceRows;
    String kindOf(LinkClearance e) {
      if (e.kind != LinkClearanceKind.custody) return '';
      final c = (_custodies ?? const <LinkFinCustody>[]).where((x) => x.id == e.refId).firstOrNull;
      return CustodyKind.label(c?.kind ?? CustodyKind.received);
    }

    String phrase(LinkClearance e) {
      if (e.kind != LinkClearanceKind.custody || e.diffType.isEmpty) return '';
      final c = (_custodies ?? const <LinkFinCustody>[]).where((x) => x.id == e.refId).firstOrNull;
      final amount = e.diffType == CustodyOutcome.surplus ? e.surplusAmount : e.deficitAmount;
      return CustodyDiff(type: e.diffType, amount: amount).phrase(custodyKind: c?.kind ?? CustodyKind.received, counterparty: e.counterpartyName);
    }

    await linkExportExcel(
      context,
      sheetName: 'الإخلاءات',
      fileName: 'الإخلاءات-${isoDay(DateTime.now())}.xlsx',
      headers: const [
        'م', 'الرقم', 'النوع', 'نوع العهدة', 'رقم العهدة', 'المرجع', 'الجهة', 'العملة', 'المخصص', 'المصروف', 'الفرق', 'نتيجة الإخلاء',
        'الصياغة', 'حالة الإخلاء', 'رقم الصك', 'المُخلِّي', 'التاريخ', 'ملاحظات'
      ],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].clearanceNo,
            LinkClearanceKind.label(rows[i].kind),
            kindOf(rows[i]),
            rows[i].custodyNo,
            rows[i].refTitle,
            rows[i].partyName,
            rows[i].kind == LinkClearanceKind.custody ? FinCurrency.label(rows[i].currency) : '',
            rows[i].kind == LinkClearanceKind.custody ? printNum(rows[i].grantedAmount) : '',
            printNum(rows[i].amount),
            rows[i].diffType == CustodyOutcome.surplus
                ? printNum(rows[i].surplusAmount)
                : rows[i].diffType == CustodyOutcome.deficit
                    ? printNum(-rows[i].deficitAmount)
                    : '',
            CustodyOutcome.label(rows[i].diffType),
            phrase(rows[i]),
            rows[i].kind == LinkClearanceKind.custody ? (LinkageRepo.workflowLabels[rows[i].workflow] ?? rows[i].workflow) : '',
            rows[i].docNo,
            rows[i].clearerName,
            _d(rows[i].clearanceDate),
            rows[i].notes,
          ],
      ],
      numericColumns: const {0, 8, 9, 10},
    );
  }

  /// طباعة إخلاء عهدة كوثيقة: بياناته وفرقه وصياغته وخانات التوقيع.
  Future<void> _printClearance(LinkClearance e) async {
    if (!_canPrint) return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    final c = (_custodies ?? const <LinkFinCustody>[]).where((x) => x.id == e.refId).firstOrNull;
    final cur = FinCurrency.label(e.currency);
    final diffAmount = e.diffType == CustodyOutcome.surplus ? e.surplusAmount : e.deficitAmount;
    final phrase = e.diffType.isEmpty
        ? ''
        : CustodyDiff(type: e.diffType, amount: diffAmount).phrase(custodyKind: c?.kind ?? CustodyKind.received, counterparty: e.counterpartyName);
    try {
      await DocumentPdf.printDoc(
        // كان يُطبع بـ`PrintLayout.defaults`: بلا ترويسة الجهة ولا تذييلها.
        layout: await SettingsRepo(widget.repo.db).printLayoutFor(PrintForms.custodyClearance),
        doc: PrintDoc(
          title: 'إخلاء عهدة',
          headers: const ['البيان', 'القيمة'],
          columnFlex: const [2, 5],
          rows: [
            ['رقم الإخلاء', e.clearanceNo],
            ['تاريخ الإخلاء', _d(e.clearanceDate)],
            ['حالة الإخلاء', LinkageRepo.workflowLabels[e.workflow] ?? e.workflow],
            ['رقم العهدة', e.custodyNo],
            ['الغرض من العهدة', e.refTitle],
            ['نوع العهدة', c == null ? '' : CustodyKind.label(c.kind)],
            ['صاحب العهدة', e.partyName],
            ['المبلغ المخصص للعهدة', '${printNum(e.grantedAmount)} $cur'],
            ['مجموع المسير (المصروف)', '${printNum(e.spentAmount)} $cur'],
            ['الفرق', e.diffType.isEmpty ? '' : '${CustodyOutcome.label(e.diffType)}${diffAmount == 0 ? '' : ' ${printNum(diffAmount)} $cur'}'],
            ['صياغة الفرق', phrase],
            ['رقم صك / مستند الإخلاء المالي', e.docNo],
            ['اسم المُخلِّي', e.clearerName],
            ['تاريخ المراجعة', e.reviewDate.isEmpty ? '' : _d(e.reviewDate)],
            ['ملاحظات إدارية', e.adminNotes],
            ['ملاحظات', e.notes],
          ],
          signatureLines: const ['صاحب العهدة\n....................', 'المُخلِّي (المالية)\n....................', 'المراجع\n....................'],
        ),
      );
    } catch (x) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $x', error: true);
    }
  }

  // ───────────────── عقود المشتريات ─────────────────

  List<LinkPurchaseContract> get _contractRows {
    final q = _q.text.trim().toLowerCase();
    return (_contracts ?? const <LinkPurchaseContract>[]).where((c) {
      if (_view.isNotEmpty && c.status != _view) return false;
      if (q.isEmpty) return true;
      return [c.contractNo, c.invoiceNo, c.title, c.supplier, _custodyNoOf(c.custodyId)].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _addOrEditContract([LinkPurchaseContract? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    // بلا صلاحية التعديل يُفتح العقد للعرض فقط.
    final saved = await openContractEditor(context, initial: initial, actor: widget.perm.email, canPrint: _canPrint, readOnly: initial != null && !_canEdit);
    if (saved) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ العقد');
    }
  }

  Future<void> _printContract(LinkPurchaseContract c) async {
    if (!_canPrint) return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    try {
      await ContractPrint.print(widget.repo.db, c);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  // ───────────────── مسير العهدة ─────────────────

  List<LinkCustodySheet> get _sheetRows {
    final q = _q.text.trim().toLowerCase();
    return (_sheets ?? const <LinkCustodySheet>[])
        .where((s) => q.isEmpty || [s.sheetNo, s.title, s.notes].join(' ').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _addOrEditSheet([LinkCustodySheet? initial]) async {
    if (initial == null && !_canCreate) return showImdToast(context, '✖ لا تملك صلاحية التسجيل', error: true);
    final saved = await openCustodySheetEditor(context, initial: initial, actor: widget.perm.email, canPrint: _canPrint, readOnly: initial != null && !_canEdit);
    if (saved) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظ مسير العهدة');
    }
  }

  /// يقرأ ملف Excel لمسير ويفتحه في المحرر للمراجعة قبل أول حفظ.
  Future<void> _importSheet() async {
    if (!_canImport) return showImdToast(context, '✖ لا تملك صلاحية الاستيراد', error: true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
      final bytes = res?.files.firstOrNull?.bytes;
      if (res == null || bytes == null) return;
      final parsed = CustodySheetImporter.parse(bytes);
      if (!mounted) return;
      if (parsed.warnings.isNotEmpty) showImdToast(context, '⚠ ${parsed.warnings.join('، ')}');
      final saved = await openCustodySheetEditor(context, imported: parsed, actor: widget.perm.email, canPrint: _canPrint);
      if (saved) {
        await _load();
        if (mounted) showImdToast(context, '✔ حُفظ المسير المستورد');
      }
    } on FormatException catch (e) {
      if (mounted) showImdToast(context, '✖ ${e.message}', error: true);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّر الاستيراد: $e', error: true);
    }
  }

  Future<void> _printSheet(LinkCustodySheet s) async {
    if (!_canPrint) return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    try {
      await CustodySheetPrint.print(widget.repo.db, s, await widget.repo.sheetRows(s.id));
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  Future<void> _exportSheets() async {
    final rows = _sheetRows;
    await linkExportExcel(
      context,
      sheetName: 'مسيرات العهدة',
      fileName: 'مسيرات-العهدة-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'رقم العهدة', 'صاحب العهدة', 'العملة', 'الأسطر', 'إجمالي العهدة', 'المنصرف', 'المرتجع', 'المتبقي', 'ملاحظات'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].sheetNo,
            rows[i].holderName.isNotEmpty ? rows[i].holderName : rows[i].title,
            FinCurrency.label(rows[i].currency),
            nf(_sheetRowCount[rows[i].id] ?? 0),
            printNum(_sheetTotals[rows[i].id]?.granted ?? 0),
            printNum(_sheetTotals[rows[i].id]?.spent ?? 0),
            printNum(_sheetTotals[rows[i].id]?.returned ?? 0),
            printNum(_sheetTotals[rows[i].id]?.remaining ?? 0),
            rows[i].notes,
          ],
      ],
      numericColumns: const {0, 4, 5, 6, 7, 8},
    );
  }

  Future<void> _exportContracts() async {
    final rows = _contractRows;
    await linkExportExcel(
      context,
      sheetName: 'عقود المشتريات',
      fileName: 'عقود-المشتريات-${isoDay(DateTime.now())}.xlsx',
      headers: const ['م', 'الرقم', 'التصنيف', 'المحل / التاجر', 'العملة', 'الإجمالي', 'التاريخ', 'رقم الفاتورة', 'العهدة', 'الحالة'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].contractNo,
            rows[i].title,
            rows[i].supplier,
            LinkCurrency.label(rows[i].currency),
            printNum(rows[i].amount),
            _d(rows[i].listDate),
            rows[i].displayInvoiceNo,
            _custodyNoOf(rows[i].custodyId) == '—' ? '' : _custodyNoOf(rows[i].custodyId),
            LinkContractStatus.label(rows[i].status),
          ],
      ],
      numericColumns: const {0, 5},
    );
  }

  // ───────────────── الواجهة ─────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdSegmented<String>(
        tabs: const [
          ImdTab('custody', 'العهد', icon: 'shield'),
          ImdTab('clearances', 'الإخلاءات', icon: 'check-circle'),
          ImdTab('contracts', 'عقود الشراء', icon: 'clipboard'),
          ImdTab('sheets', 'مسير العهدة', icon: 'dollar'),
          ImdTab('receipts', 'استلام مبلغ مالي', icon: 'file'),
        ],
        value: _sub,
        onChanged: _switch,
      ),
      const SizedBox(height: 14),
      if (_sub == 'custody')
        ..._custodyView(c)
      else if (_sub == 'clearances')
        ..._clearanceView(c)
      else if (_sub == 'sheets')
        ..._sheetView(c)
      else if (_sub == 'receipts')
        MoneyReceiptsTab(repo: widget.repo, perm: widget.perm)
      else
        ..._contractView(c),
    ]);
  }

  List<Widget> _custodyView(ImdColors c) {
    final all = _custodies ?? const <LinkFinCustody>[];
    final open = all.where((e) => e.status == CustodyStatus.open);
    final overdueCount = all.where(_overdue).length;
    double sum(Iterable<LinkFinCustody> xs, String cur) => xs.where((e) => e.currency == cur).fold<double>(0, (s, e) => s + e.amount);
    String money(double v, String cur) => '${nf(v)} ${FinCurrency.short(cur)}';
    final parties = <String>{for (final e in all) ...[e.giverName, e.receiverName, e.holder].where((x) => x.trim().isNotEmpty)}.toList()..sort();
    return [
      ImdKpis(children: [
        ImdKpi(label: 'قيد الإخلاء', value: nf(open.length), icon: 'shield', color: c.accent),
        ImdKpi(label: 'تم الإخلاء', value: nf(all.where((e) => e.status == CustodyStatus.cleared).length), icon: 'check-circle', color: c.success),
        ImdKpi(label: 'متأخرة عن الإخلاء', value: nf(overdueCount), icon: 'hourglass', color: overdueCount > 0 ? c.danger : c.muted),
        ImdKpi(label: 'قائمة بالسعودي', value: money(sum(open, FinCurrency.sar), FinCurrency.sar), icon: 'dollar', color: c.info),
        ImdKpi(label: 'قائمة باليمني', value: money(sum(open, FinCurrency.yer), FinCurrency.yer), icon: 'dollar', color: c.warn),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو الغرض أو الاسم أو مركز التكلفة…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdButton.outline(label: 'كشف حساب مالية', icon: 'file', small: true, onPressed: _openStatement),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportCustodies),
          if (_canCreate) ImdButton(label: 'تسجيل عهدة', icon: 'plus', onPressed: _addOrEditCustody),
        ],
      ),
      const SizedBox(height: 8),
      ImdGrid(columns: 5, minItemWidth: 170, gap: 10, children: [
        ImdLabeled(
          'الحالة',
          ImdSelect<String>(
            items: [('', 'الكل'), for (final e in CustodyStatus.labels.entries) (e.key, e.key == CustodyStatus.cleared ? 'عرض المُخلَّاة' : e.value)],
            value: _cStatus,
            onChanged: (v) => setState(() => _cStatus = v ?? ''),
          ),
        ),
        ImdLabeled(
          'النوع',
          ImdSelect<String>(
            items: [('', 'الكل'), for (final e in CustodyKind.labels.entries) (e.key, e.value)],
            value: _cKind,
            onChanged: (v) => setState(() => _cKind = v ?? ''),
          ),
        ),
        ImdLabeled(
          'الشخص',
          ImdSelect<String>(
            items: [('', 'الكل'), for (final p in {...parties, if (_cPerson.isNotEmpty) _cPerson}) (p, p)],
            value: _cPerson,
            onChanged: (v) => setState(() => _cPerson = v ?? ''),
          ),
        ),
        ImdLabeled('من تاريخ', ImdDateField(value: _cFrom, onChanged: (v) => setState(() => _cFrom = v))),
        ImdLabeled('إلى تاريخ', ImdDateField(value: _cTo, onChanged: (v) => setState(() => _cTo = v))),
      ]),
      const SizedBox(height: 12),
      if (_custodies == null)
        const ImdLd('جارٍ تحميل العهد…')
      else if (_custodyRows.isEmpty)
        const ImdEmptyBox('لا عهدٍ مطابقة')
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('الرقم'),
            ImdCol('النوع'),
            ImdCol('الغرض', flex: 2),
            ImdCol('المُسلِّم ← المستلم', flex: 2),
            ImdCol('المبلغ', numeric: true),
            ImdCol('المستهلك', numeric: true),
            ImdCol('المتبقي', numeric: true),
            ImdCol('العقود'),
            ImdCol('رصيد المالية'),
            ImdCol('التاريخ'),
            ImdCol('الحالة', flex: 2),
            ImdCol(''),
          ],
          rows: [for (final e in _custodyRows) _custodyRow(c, e)],
          empty: 'لا عهدٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _custodyRow(ImdColors c, LinkFinCustody e) {
    final overdue = _overdue(e);
    final u = _usage[e.id];
    final consumed = u?.consumed ?? 0;
    final remaining = e.amount - consumed;
    final cur = FinCurrency.short(e.currency);
    final giver = e.giverName.isEmpty ? e.holder : e.giverName;
    return [
      Text(e.custodyNo.isEmpty ? '—' : e.custodyNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      ImdChip(CustodyKind.label(e.kind), tone: e.kind == CustodyKind.received ? ImdTone.info : ImdTone.pend),
      Text(e.title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text('${giver.isEmpty ? '—' : giver} ← ${e.receiverName.isEmpty ? '—' : e.receiverName}'),
      Text('${nf(e.amount)} $cur', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text(consumed == 0 ? '—' : '${nf(consumed)} $cur'),
      Text(e.status == CustodyStatus.open || consumed > 0 ? '${nf(remaining)} $cur' : '—',
          style: TextStyle(fontWeight: FontWeight.w700, color: remaining < 0 ? c.danger : c.text)),
      Text((u?.contracts ?? 0) == 0 ? '—' : nf(u!.contracts)),
      InkWell(
        onTap: () => _openStatement(LinkageRepo.partyOf(e)),
        child: Text(financeBalanceText(_balances[LinkageRepo.partyOf(e)]), style: TextStyle(fontWeight: FontWeight.w600, color: c.info)),
      ),
      Text(_d(e.custodyDate)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ImdChip(
          e.status == CustodyStatus.cleared
              ? 'تم الإخلاء${e.outcome.isEmpty ? '' : ' + ${CustodyOutcome.label(e.outcome)}'} ${_d(e.clearedDate)}'
              : e.status == CustodyStatus.canceled
                  ? 'ملغاة'
                  : overdue
                      ? 'متأخرة ${nf(linkDaysBetween(e.dueDate, isoDay(DateTime.now())))} يوم'
                      : 'قيد الإخلاء',
          tone: e.status == CustodyStatus.cleared
              ? ImdTone.ok
              : e.status == CustodyStatus.canceled
                  ? ImdTone.off
                  : overdue
                      ? ImdTone.err
                      : ImdTone.pend,
          icon: e.status == CustodyStatus.cleared ? 'check-circle' : overdue ? 'alert' : 'hourglass',
        ),
        if (e.status == CustodyStatus.open && e.dueDate.isNotEmpty)
          Text('آخر أجل ${_d(e.dueDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: overdue ? c.danger : c.muted)),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ImdIconButton(icon: 'eye', tooltip: 'تفاصيل العهدة والعقود المرتبطة', onPressed: () => _openCustody(e)),
        if (e.status == CustodyStatus.open && _canCreate)
          ImdIconButton(icon: 'check-circle', tooltip: 'إخلاء العهدة', onPressed: () => _addClearance(refId: e.id)),
        if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _addOrEditCustody(e)),
        if (_canDelete) ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _deleteCustody(e)),
      ]),
    ];
  }

  List<Widget> _clearanceView(ImdColors c) {
    final all = _clearances ?? const <LinkClearance>[];
    return [
      ImdKpis(children: [
        ImdKpi(label: 'الإخلاءات', value: nf(all.length), icon: 'check-circle', color: c.accent),
        ImdKpi(label: 'إخلاء عهد', value: nf(all.where((e) => e.kind == LinkClearanceKind.custody).length), icon: 'shield', color: c.info),
        ImdKpi(label: 'إخلاء عقود', value: nf(all.where((e) => e.kind == LinkClearanceKind.contract).length), icon: 'clipboard', color: c.warn),
        ImdKpi(label: 'إجمالي المبالغ المسوّاة', value: nf(all.fold<double>(0, (s, e) => s + e.amount)), icon: 'dollar', color: c.success),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو المرجع أو الجهة…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [
              ImdTab('', 'الكل'),
              ImdTab(LinkClearanceKind.custody, 'عهد'),
              ImdTab(LinkClearanceKind.contract, 'عقود'),
              ImdTab(LinkClearanceKind.other, 'حر'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportClearances),
          if (_canCreate) ImdButton(label: 'تسجيل إخلاء', icon: 'plus', onPressed: _addClearance),
        ],
      ),
      for (final e in _dupClearances.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ImdNote('⚠ تعارض: العهدة ${_custodyNoOf(e.key)} لها ${nf(e.value.length)} إخلاءات (${e.value.map((x) => x.clearanceNo).join('، ')}) — غالبًا من مزامنة جهازين. احذف الزائد ليبقى إخلاءٌ واحد.'),
        ),
      if (_clearances == null)
        const ImdLd('جارٍ تحميل الإخلاءات…')
      else if (_clearanceRows.isEmpty)
        const ImdEmptyBox('لا إخلاءاتٍ مطابقة')
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('الرقم'),
            ImdCol('النوع'),
            ImdCol('المرجع', flex: 2),
            ImdCol('الجهة', flex: 2),
            ImdCol('المخصص', numeric: true),
            ImdCol('المصروف', numeric: true),
            ImdCol('الفرق', flex: 2),
            ImdCol('الحالة'),
            ImdCol('التاريخ'),
            ImdCol(''),
          ],
          rows: [for (final e in _clearanceRows) _clearanceRow(c, e)],
          empty: 'لا إخلاءاتٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _clearanceRow(ImdColors c, LinkClearance e) {
    final isCustody = e.kind == LinkClearanceKind.custody;
    final cur = FinCurrency.short(e.currency);
    final diffAmount = e.diffType == CustodyOutcome.surplus ? e.surplusAmount : e.deficitAmount;
    final custody = isCustody ? (_custodies ?? const <LinkFinCustody>[]).where((x) => x.id == e.refId).firstOrNull : null;
    final phrase = isCustody && e.diffType.isNotEmpty
        ? CustodyDiff(type: e.diffType, amount: diffAmount).phrase(custodyKind: custody?.kind ?? CustodyKind.received, counterparty: e.counterpartyName)
        : '';
    return [
      Text(e.clearanceNo.isEmpty ? '—' : e.clearanceNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      ImdChip(LinkClearanceKind.label(e.kind), tone: LinkClearanceKind.tone(e.kind)),
      Text(e.refTitle.isEmpty ? '—' : e.refTitle, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(e.partyName.isEmpty ? '—' : e.partyName),
      Text(isCustody ? '${nf(e.grantedAmount)} $cur' : '—'),
      Text(e.amount == 0 ? '—' : '${nf(e.amount)}${isCustody ? ' $cur' : ''}'),
      isCustody && e.diffType.isNotEmpty
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              ImdChip('${CustodyOutcome.label(e.diffType)}${diffAmount == 0 ? '' : ' ${nf(diffAmount)} $cur'}',
                  tone: e.diffType == CustodyOutcome.matched ? ImdTone.ok : e.diffType == CustodyOutcome.surplus ? ImdTone.info : ImdTone.err),
              Text(phrase, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ])
          : const Text('—'),
      isCustody
          ? ImdChip(LinkageRepo.workflowLabels[e.workflow] ?? e.workflow,
              tone: e.workflow == LinkageRepo.wfApproved ? ImdTone.ok : e.workflow == LinkageRepo.wfSent ? ImdTone.info : ImdTone.pend)
          : const Text('—'),
      Text(_d(e.clearanceDate)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (isCustody) ImdIconButton(icon: _canEdit ? 'edit' : 'eye', tooltip: _canEdit ? 'فتح وتعديل' : 'عرض', onPressed: () => _addClearance(initial: e)),
        if (isCustody && _canPrint) ImdIconButton(icon: 'printer', tooltip: 'طباعة الإخلاء', onPressed: () => _printClearance(e)),
        // حذف الإخلاء المُعتمد يلزمه الاعتماد (لا يكفي الحذف)، وما سواه بصلاحية الحذف.
        if (isCustody && e.workflow == LinkageRepo.wfApproved ? _canApprove : _canDelete)
          ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _deleteClearance(e)),
      ]),
    ];
  }

  List<Widget> _sheetView(ImdColors c) {
    final all = _sheets ?? const <LinkCustodySheet>[];
    double sum(String cur, double Function(CustodyTotals) f) =>
        all.where((e) => e.currency == cur).fold<double>(0, (s, e) => s + (_sheetTotals[e.id] == null ? 0 : f(_sheetTotals[e.id]!)));
    String m(double v, String cur) => '${nf(v)} ${FinCurrency.short(cur)}';
    return [
      ImdKpis(children: [
        ImdKpi(label: 'المسيرات', value: nf(all.length), icon: 'dollar', color: c.accent),
        ImdKpi(label: 'منصرف (سعودي)', value: m(sum(FinCurrency.sar, (t) => t.spent), FinCurrency.sar), icon: 'upload', color: c.info),
        ImdKpi(label: 'منصرف (يمني)', value: m(sum(FinCurrency.yer, (t) => t.spent), FinCurrency.yer), icon: 'upload', color: c.warn),
        ImdKpi(label: 'متبقي (سعودي)', value: m(sum(FinCurrency.sar, (t) => t.remaining), FinCurrency.sar), icon: 'check-circle', color: c.success),
        ImdKpi(label: 'متبقي (يمني)', value: m(sum(FinCurrency.yer, (t) => t.remaining), FinCurrency.yer), icon: 'check-circle', color: c.success),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث برقم العهدة أو عنوان المسير…',
        onChanged: (_) => setState(() {}),
        actions: [
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportSheets),
          if (_canImport) ImdButton.outline(label: 'استيراد من Excel', icon: 'upload', small: true, onPressed: _importSheet),
          if (_canCreate) ImdButton(label: 'مسير عهدة جديد', icon: 'plus', onPressed: _addOrEditSheet),
        ],
      ),
      if (_sheets == null)
        const ImdLd('جارٍ تحميل المسيرات…')
      else if (_sheetRows.isEmpty)
        const ImdEmptyBox('لا مسيراتٍ مطابقة')
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('رقم العهدة'),
            ImdCol('صاحب العهدة', flex: 2),
            ImdCol('الأسطر', numeric: true),
            ImdCol('إجمالي العهدة', numeric: true),
            ImdCol('المنصرف', numeric: true),
            ImdCol('المتبقي', numeric: true),
            ImdCol(''),
          ],
          rows: [
            for (final s in _sheetRows)
              [
                Text(s.sheetNo.isEmpty ? '—' : s.sheetNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                Text(s.holderName.isNotEmpty ? s.holderName : (s.title.isEmpty ? '—' : s.title), style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                Text(nf(_sheetRowCount[s.id] ?? 0)),
                Text('${printMoney(_sheetTotals[s.id]?.granted ?? 0)} ${FinCurrency.short(s.currency)}'),
                Text('${printMoney(_sheetTotals[s.id]?.spent ?? 0)} ${FinCurrency.short(s.currency)}'),
                Text('${printMoney(_sheetTotals[s.id]?.remaining ?? 0)} ${FinCurrency.short(s.currency)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: (_sheetTotals[s.id]?.remaining ?? 0) < 0 ? c.danger : c.text)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (_canPrint) ImdIconButton(icon: 'printer', tooltip: 'طباعة المسير', onPressed: () => _printSheet(s)),
                  ImdIconButton(icon: _canEdit ? 'edit' : 'eye', tooltip: _canEdit ? 'فتح وتعديل' : 'عرض', onPressed: () => _addOrEditSheet(s)),
                  if (_canDelete)
                    ImdIconButton(
                        icon: 'trash',
                        tooltip: 'حذف',
                        kind: ImdBtnKind.danger,
                        onPressed: () async {
                          if (!await imdConfirm(context, 'حذف مسير العهدة رقم ${s.sheetNo} وكل أسطره نهائيًّا؟', ok: 'حذف', danger: true)) return;
                          try {
                            await widget.repo.deleteCustodySheet(s, actor: widget.perm.email);
                            await _load();
                          } on LinkBlocked catch (x) {
                            if (mounted) showImdToast(context, '✖ ${x.message}', error: true);
                          }
                        }),
                ]),
              ],
          ],
          empty: 'لا مسيراتٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  List<Widget> _contractView(ImdColors c) {
    final all = _contracts ?? const <LinkPurchaseContract>[];
    return [
      ImdKpis(children: [
        ImdKpi(label: 'العقود', value: nf(all.length), icon: 'clipboard', color: c.accent),
        ImdKpi(label: 'إجمالي بالسعودي', value: nf(all.where((e) => e.currency == LinkCurrency.sar).fold<double>(0, (s, e) => s + e.amount)), icon: 'dollar', color: c.info),
        ImdKpi(label: 'إجمالي باليمني', value: nf(all.where((e) => e.currency == LinkCurrency.yer).fold<double>(0, (s, e) => s + e.amount)), icon: 'dollar', color: c.warn),
        ImdKpi(label: 'قيد التنفيذ', value: nf(all.where((e) => e.status == LinkContractStatus.open).length), icon: 'hourglass', color: c.warn),
      ]),
      ImdSearchBar(
        controller: _q,
        hint: 'بحث بالرقم أو التصنيف أو التاجر أو الأصناف…',
        onChanged: (_) => setState(() {}),
        actions: [
          ImdSegmented<String>(
            tabs: const [
              ImdTab('', 'الكل'),
              ImdTab(LinkContractStatus.open, 'قيد التنفيذ'),
              ImdTab(LinkContractStatus.done, 'منفَّذ'),
              ImdTab(LinkContractStatus.canceled, 'ملغى'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canExport) ImdButton.outline(label: 'تصدير Excel', icon: 'download', small: true, onPressed: _exportContracts),
          if (_canCreate) ImdButton(label: 'عقد جديد', icon: 'plus', onPressed: _addOrEditContract),
        ],
      ),
      if (_contracts == null)
        const ImdLd('جارٍ تحميل العقود…')
      else if (_contractRows.isEmpty)
        const ImdEmptyBox('لا عقودٍ مطابقة')
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('الرقم'),
            ImdCol('التصنيف', flex: 2),
            ImdCol('المحل / التاجر', flex: 2),
            ImdCol('العملة'),
            ImdCol('الإجمالي', numeric: true),
            ImdCol('التاريخ'),
            ImdCol('رقم الفاتورة'),
            ImdCol('العهدة'),
            ImdCol('الحالة'),
            ImdCol(''),
          ],
          rows: [for (final e in _contractRows) _contractRow(c, e)],
          empty: 'لا عقودٍ مطابقة',
          onRowTap: null,
        ),
    ];
  }

  String _custodyNoOf(String id) {
    if (id.isEmpty) return '—';
    final c = (_custodies ?? const <LinkFinCustody>[]).where((x) => x.id == id).firstOrNull;
    return c == null || c.custodyNo.isEmpty ? '—' : c.custodyNo;
  }

  List<Widget> _contractRow(ImdColors c, LinkPurchaseContract e) {
    return [
      Text(e.contractNo.isEmpty ? '—' : e.contractNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
      Text(e.title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(e.supplier.isEmpty ? '—' : e.supplier),
      ImdChip(LinkCurrency.label(e.currency), tone: e.currency == LinkCurrency.yer ? ImdTone.pend : ImdTone.info),
      Text(printNum(e.amount)),
      Text(_d(e.listDate)),
      Text(e.displayInvoiceNo.isEmpty ? '—' : e.displayInvoiceNo, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      Text(_custodyNoOf(e.custodyId)),
      ImdChip(LinkContractStatus.label(e.status), tone: LinkContractStatus.tone(e.status)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (_canPrint) ImdIconButton(icon: 'printer', tooltip: 'طباعة العقد', onPressed: () => _printContract(e)),
        if (e.status == LinkContractStatus.open && _canCreate)
          ImdIconButton(
              icon: 'check-circle',
              tooltip: 'تسجيل إخلاء',
              onPressed: () => _addClearance(kind: LinkClearanceKind.contract, refId: e.id)),
        ImdIconButton(icon: _canEdit ? 'edit' : 'eye', tooltip: _canEdit ? 'تعديل' : 'عرض', onPressed: () => _addOrEditContract(e)),
        if (_canDelete)
          ImdIconButton(
              icon: 'trash',
              tooltip: 'حذف',
              kind: ImdBtnKind.danger,
              onPressed: () async {
                if (!await imdConfirm(context, 'حذف العقد «${e.title}» نهائيًّا؟', ok: 'حذف', danger: true)) return;
                try {
                  await widget.repo.deleteContract(e, actor: widget.perm.email);
                  await _load();
                } on LinkBlocked catch (x) {
                  if (mounted) showImdToast(context, '✖ ${x.message}', error: true);
                }
              }),
      ]),
    ];
  }
}

// ═══════════════ نماذج العهدة والإخلاء والعقد ═══════════════

/// منتقي الفرد المشترك — القوائم المالية والتسليحية كلها تربط سجلها بفردٍ
/// من القوة البشرية بهذه القائمة نفسها.
class LinkPersonPicker extends StatelessWidget {
  const LinkPersonPicker({super.key, required this.persons, required this.value, required this.onChanged, this.optional = false});

  final List<LinkPerson> persons;
  final String value;
  final ValueChanged<String> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return ImdSelect<String>(
      items: [
        if (optional) ('', 'بلا ارتباط'),
        for (final p in persons) (p.id, p.militaryNo.isEmpty ? p.fullName : '${p.fullName} — ${p.militaryNo}'),
      ],
      value: value,
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}
