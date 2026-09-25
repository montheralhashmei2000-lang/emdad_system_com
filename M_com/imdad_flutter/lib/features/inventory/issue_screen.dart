import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/print/voucher_print.dart';
import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/repos/documents_repo.dart';
import '../documents/doc_log_view.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/line_consolidation.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/strength.dart';
import 'doc_kit.dart';

/// صرف بضاعة — نقل مطابق لـ `renderIssue()`: سند صرف جديد (أربعة أنواع توجيه، القوة والاستحقاق،
/// موعد الصرف القادم)، المسودات والأوامر، وسجل الصادرات مع تعديل القوة/الأيام والطباعة المجمّعة.
class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key});

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _Row {
  _Row({this.itemId = '', this.unit = '', double? qty, String notes = '', this.benUnit = '', this.noAuto = false})
      : cy = 'EXCHANGE', qty = TextEditingController(text: qty == null ? '' : _num(qty)),
        notes = TextEditingController(text: notes);
  String itemId;
  String unit;
  final TextEditingController qty;
  final TextEditingController notes;
  String cy;
  String benUnit;
  bool noAuto;
  final key = UniqueKey();

  void dispose() {
    qty.dispose();
    notes.dispose();
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _IssueScreenState extends State<IssueScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);

  String _tab = 'form';

  // ISS
  int _type = 0;
  List<Item> _items = const [];
  List<BeneficiaryUnit> _units = const [];
  List<Warehouse> _whs = const [];
  List<Facility> _facs = const [];
  Map<String, Entitlement> _ents = const {};
  StrengthCalculator? _calc;
  Map<String, double> _whBal = const {};
  double _strength = 0;
  bool _ready = false;
  bool _busy = false;

  // النموذج
  String _wh = '';
  String _date = imdToday();
  String _ref = '';
  String _nextDue = '—';
  Color? _nextDueColor;
  String _parent = '';
  String _ben = '';
  String _fac = '';
  final _custom = TextEditingController();
  String _strDate = imdToday();
  final _days = TextEditingController(text: '1');
  final _notes = TextEditingController();
  final List<_Row> _rows = [];

  // المسودات والسجل
  List<Issue>? _drafts;

  @override
  void initState() {
    super.initState();
    _form();
  }

  @override
  void dispose() {
    for (final c in [_custom, _days, _notes]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _switch(String t) {
    setState(() => _tab = t);
    if (t == 'form') _form();
    if (t == 'drafts') _loadDrafts();
  }

  // ───────────────────────── النموذج ─────────────────────────
  /// `issFetchAll()` + `issRenderForm()`
  Future<void> _form() async {
    final perm = Perm.of(context);
    final items = await _catalog.items();
    final units = await _catalog.units();
    final whs = (await _db.select(_db.warehouses).get()..sort((a, b) => a.name.compareTo(b.name)))
        .where((w) => perm.canWh(w.name))
        .toList();
    final facs = await _db.select(_db.facilities).get();
    final ents = {for (final e in await _db.select(_db.entitlements).get()) e.itemId: e};
    final calc = await DailyRepo(_db).calculator();
    final ref = await _moves.nextRef('issues', 'ص-');
    if (!mounted) return;
    setState(() {
      _items = items;
      _units = units;
      _whs = whs;
      _facs = facs;
      _ents = ents;
      _calc = calc;
      _date = imdToday();
      _strDate = imdToday();
      _ref = ref;
      _parent = '';
      _ben = '';
      _fac = '';
      _custom.clear();
      imdSetText(_days, '1');
      _notes.clear();
      _strength = 0;
      _nextDue = '—';
      _nextDueColor = null;
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..add(_Row());
      _wh = _whsForCamp('').isNotEmpty ? _whsForCamp('').first.name : '';
      if (_type == 2 || _type == 3) _strength = 0;
      _ready = true;
    });
    await _refreshBal();
  }

  Future<void> _refreshBal() async {
    if (_wh.isEmpty) return;
    final b = await _moves.balances(warehouse: _wh);
    if (mounted) setState(() => _whBal = b);
  }

  /// `issWhOptionsFor(campId)` — المستودعات التي تغذي المعسكر، وإلا الكل.
  List<Warehouse> _whsForCamp(String campId) {
    if (campId.isEmpty) return _whs;
    final f = _whs.where((w) => _feeds(w, campId)).toList();
    return f.isNotEmpty ? f : _whs;
  }

  bool _feeds(Warehouse w, String campId) => w.feedsAllCamps || _catalog.campsOf(w).contains(campId);

  Item? _item(String id) => _items.where((x) => x.id == id).firstOrNull;

  void _setType(int t) {
    setState(() {
      _type = t;
      if (t == 2 || t == 3) {
        _strength = 0;
        _nextDue = '—';
        _nextDueColor = null;
      }
    });
    _fetchStrength();
  }

  void _onParent(String pid) {
    setState(() {
      _parent = pid;
      final opts = _whsForCamp(pid);
      if (!opts.any((w) => w.name == _wh)) _wh = opts.isNotEmpty ? opts.first.name : '';
      _ben = '';
      _strength = 0;
      _nextDue = '—';
      _nextDueColor = null;
    });
    _refreshBal();
  }

  Future<void> _onBen(String uid) async {
    setState(() => _ben = uid);
    if (_type != 0) return;
    if (uid.isEmpty) {
      setState(() {
        _strength = 0;
        _nextDue = '—';
        _nextDueColor = null;
      });
      return;
    }
    await _fetchStrength();
    await _checkNextDue(uid);
  }

  /// `issFetchStrength()` (نسخة strength-fix.js)
  Future<void> _fetchStrength() async {
    if (_type != 0 && _type != 1) return;
    final calc = _calc;
    if (calc == null) return;
    final date = _strDate.isNotEmpty ? _strDate : _date;
    double total;
    if (_type == 0) {
      if (_ben.isEmpty) return;
      total = calc.unitStrengthOn(_ben, date);
    } else {
      if (_fac.isEmpty) return;
      total = calc.facilityStrengthOn(_fac, date);
    }
    setState(() => _strength = total);
    _recalcAll();
  }

  /// `issCheckNextDue(unitId)`
  Future<void> _checkNextDue(String unitId) async {
    final rows = await (_db.select(_db.issues)
          ..where((t) => t.unitId.equals(unitId))
          ..where((t) => t.status.equals('COMPLETED')))
        .get();
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    if (rows.isEmpty) {
      setState(() {
        _nextDue = 'لا يوجد صرف سابق';
        _nextDueColor = const Color(0xFF155724);
      });
      return;
    }
    DateTime? maxNext;
    for (final v in rows.take(10)) {
      final dt = v.date.isNotEmpty ? v.date : isoDay(v.createdAt);
      final d = DateTime.tryParse(dt);
      if (d == null) continue;
      final next = d.add(Duration(days: v.durationDays <= 0 ? 1 : v.durationDays));
      if (maxNext == null || next.isAfter(maxNext)) maxNext = next;
    }
    if (maxNext == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = (maxNext.difference(today).inHours / 24).round();
    final str = isoDay(maxNext);
    setState(() {
      if (diff < 0) {
        _nextDue = '⚠️ متأخر! كان يجب الصرف في $str';
        _nextDueColor = context.imd.danger;
      } else if (diff == 0) {
        _nextDue = '📢 اليوم! موعد الصرف $str';
        _nextDueColor = const Color(0xFFB78103);
      } else {
        _nextDue = '📅 $str (بعد $diff يوم)';
        _nextDueColor = const Color(0xFF155724);
      }
    });
  }

  /// `issCalculateRowEntitlement(row)` — (المقرر الشهري بوحدة الأساس ÷ 30) × القوة × الأيام ÷ معامل وحدة السطر.
  /// يعيد `true` إن ضبط الكمية من الاستحقاق، و`false` إن لم ينطبق الاحتساب
  /// (فيتولّى نداءُ التحويل بالمعامل ضبطَها بدل تركها على حالها).
  bool _calcRow(_Row r) {
    if (r.itemId.isEmpty || _strength <= 0) return false;
    final ent = _ents[r.itemId];
    final it = _item(r.itemId);
    if (ent == null || ent.qtyPerPerson == 0 || it == null) return false;
    final days = int.tryParse(_days.text.trim()) ?? 1;
    final measureFactor = _catalog.factorOf(it, ent.measureUnitName);
    final perDay = ent.qtyPerPerson * measureFactor / 30.0;
    final total = perDay * _strength * (days <= 0 ? 1 : days);
    final factor = _catalog.factorOf(it, r.unit);
    r.qty.text = _num(((total / factor) * 1000).round() / 1000);
    return true;
  }


  /// يملأ جدول الصرف بكل الأصناف المستحقة دفعة واحدة، بدل إضافتها يدويًا صنفًا
  /// صنفًا. المنطق نفسه الموجود في `_calcRow` لكن على كل المقررات:
  /// الكمية = الاستحقاق اليومي للفرد × إجمالي القوة × مدة الإعاشة.
  void _autoFillFromEntitlements() {
    if (_strength <= 0) {
      showImdToast(
        context,
        '✖ لا توجد قوة محسوبة — حدد الجهة المستفيدة وتاريخ حصر القوة أولًا، '
        'أو أدخل إجمالي القوة يدويًا',
        error: true,
      );
      return;
    }
    final days = int.tryParse(_days.text.trim()) ?? 1;
    final entries = _ents.values.where((e) => e.qtyPerPerson > 0).toList();
    if (entries.isEmpty) {
      showImdToast(
        context,
        '✖ لا توجد استحقاقات مقررة بعد — اضبطها من شاشة «الاستحقاقات والمقررات»',
        error: true,
      );
      return;
    }

    final ben = _units.isNotEmpty ? _units.first.id : '';
    var added = 0;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      for (final e in entries) {
        final it = _item(e.itemId);
        if (it == null) continue;
        final uName = e.measureUnitName.isNotEmpty ? e.measureUnitName : it.baseUnit;
        // المقرر شهري، فيُقسم على ٣٠ ليصير يوميًا كما في `_calcRow`.
        final qty = ((e.qtyPerPerson / 30.0) * _strength * (days <= 0 ? 1 : days) * 1000)
                .round() /
            1000;
        if (qty <= 0) continue;
        _rows.add(_Row(itemId: it.id, unit: uName, qty: qty, benUnit: ben, noAuto: true));
        added++;
      }
      if (_rows.isEmpty) _rows.add(_Row(benUnit: ben));
    });
    showImdToast(context, '✔ احتُسب $added صنفًا تلقائيًا — راجع الكميات قبل التنفيذ');
  }

  void _recalcAll() {
    setState(() {
      for (final r in _rows) {
        _calcRow(r);
      }
    });
  }

  void _onItem(_Row r, String id) {
    final it = _item(id);
    setState(() {
      r.itemId = id;
      final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
      r.unit = units.where((u) => u.isBase).firstOrNull?.name ?? (units.isNotEmpty ? units.first.name : '');
      if (r.benUnit.isEmpty && _units.isNotEmpty) r.benUnit = _units.first.id;
      _calcRow(r);
      if (it != null && !r.noAuto && identical(_rows.last, r)) _rows.add(_Row(benUnit: _units.isNotEmpty ? _units.first.id : ''));
    });
  }

  /// `issCollect()`
  ({List<DocLineInput> rows, String err}) _collect() {
    final rows = <DocLineInput>[];
    for (final r in _rows) {
      if (r.itemId.isEmpty) continue;
      final it = _item(r.itemId);
      if (it == null) continue;
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (qty <= 0) return (rows: rows, err: '✖ أدخل كمية صالحة للصنف ${it.name}');
      final factor = _catalog.factorOf(it, r.unit);
      final base = qty * factor;
      final have = _whBal[it.id] ?? 0;
      if (_wh.isNotEmpty && base > have + 1e-9) {
        return (rows: rows, err: '✖ رصيد «${it.name}» في مستودع «$_wh» لا يكفي (${nf(have)} متاح)');
      }
      final ben = _type == 3 ? _units.where((u) => u.id == r.benUnit).firstOrNull : null;
      rows.add(DocLineInput(
        itemId: it.id,
        itemCode: it.code,
        itemName: it.name,
        unitName: r.unit,
        factor: factor,
        qty: qty,
        notes: r.notes.text.trim(),
        cylinderAction: it.isRefillable ? r.cy : '',
        beneficiaryUnitId: ben?.id ?? '',
        beneficiaryUnitName: ben == null ? '' : '${ben.code} — ${ben.name}',
      ));
    }
    return (rows: rows, err: '');
  }

  /// مجموع الخصم لكل صنف مقابل رصيد المستودع (`stockErrorFromMap`).
  String _balError(List<DocLineInput> rows) {
    final sum = <String, double>{};
    for (final r in rows) {
      sum[r.itemId] = (sum[r.itemId] ?? 0) + r.baseQty;
    }
    for (final e in sum.entries) {
      final have = _whBal[e.key] ?? 0;
      if (e.value > have + 1e-9) {
        return MovementsRepo.stockError(_item(e.key), _wh, have, e.value);
      }
    }
    return '';
  }

  /// التجميع التلقائي وإعادة التوزيع على الوحدات — يحل محل زر «دمج التكرار».
  ///
  /// يُستدعى عند مغادرة حقل الكمية وعند إضافة سطر جديد. الصنف الواحد للجهة
  /// الواحدة يُجمع ولو اختلفت وحداته، ثم يُعاد توزيعه من الأكبر إلى الأصغر.
  void _autoConsolidate() {
    final complete = <_Row>[];
    final pending = <_Row>[];
    for (final r in _rows) {
      final it = _item(r.itemId);
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      if (it == null || r.unit.isEmpty || qty <= 0) {
        pending.add(r);
      } else {
        complete.add(r);
      }
    }
    if (complete.length < 2) return;

    // الجهة المستفيدة وعملية الأسطوانة لا يصح خلطها، فتدخل في مفتاح المجموعة.
    String keyOf(_Row r) {
      final it = _item(r.itemId)!;
      return '${r.itemId}|${r.benUnit}|${it.isRefillable ? r.cy : ''}';
    }

    final notesOf = <String, String>{};
    for (final r in complete) {
      final k = keyOf(r);
      if ((notesOf[k] ?? '').isEmpty) notesOf[k] = r.notes.text;
    }

    final consolidated = consolidateLines([
      for (final r in complete)
        LineQty(
          groupKey: keyOf(r),
          unitName: r.unit,
          factor: _catalog.factorOf(_item(r.itemId)!, r.unit),
          qty: double.parse(r.qty.text.trim()),
        ),
    ]);

    final before = [for (final r in complete) '${keyOf(r)}|${r.unit}|${r.qty.text.trim()}'];
    final after = [for (final l in consolidated) '${l.groupKey}|${l.unitName}|${_num(l.qty)}'];
    if (before.join('§') == after.join('§')) return;

    setState(() {
      for (final r in complete) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final l in consolidated)
            _Row(
              itemId: l.groupKey.split('|')[0],
              unit: l.unitName,
              qty: l.qty,
              notes: notesOf[l.groupKey] ?? '',
              benUnit: l.groupKey.split('|')[1],
              noAuto: true,
            )..cy = l.groupKey.split('|')[2].isEmpty ? 'EXCHANGE' : l.groupKey.split('|')[2],
          ...pending,
        ]);
      if (_rows.isEmpty) _rows.add(_Row());
    });
  }

  /// `issScanGo()`
  void _scan(String code) {
    final it = _items.where((x) => x.barcode == code || x.code == code).firstOrNull;
    if (it == null) return showImdToast(context, '✖ الباركود/الكود غير معرّف');
    for (final r in _rows) {
      if (r.itemId == it.id) {
        r.qty.text = _num((double.tryParse(r.qty.text) ?? 0) + 1);
        _autoConsolidate();
        return;
      }
    }
    final row = _Row(qty: 1);
    setState(() => _rows.add(row));
    _onItem(row, it.id);
    showImdToast(context, '➕ أُضيف: ${it.name}');
  }

  /// `issValidateLive()`
  List<ImdCheck> _validate() {
    final items = <ImdCheck>[];
    if (_wh.isEmpty) items.add(const ImdCheck('warn', 'المستودع غير محدد', 'اختَر المستودع المصروف منه قبل التنفيذ.'));
    if (imdIsFuture(_date)) items.add(const ImdCheck('err', 'تاريخ غير صالح', 'تاريخ الصرف لا يمكن أن يكون في المستقبل.'));
    if (_type == 0 && _ben.isEmpty) items.add(const ImdCheck('warn', 'الوحدة المستفيدة غير محددة', 'اختَر الوحدة التابعة قبل الاعتماد.'));
    if (_type == 1 && _fac.isEmpty) items.add(const ImdCheck('warn', 'المطبخ/الفرن غير محدد', 'اختَر الجهة التشغيلية قبل الاعتماد.'));
    if (_type == 2 && _custom.text.trim().isEmpty) items.add(const ImdCheck('warn', 'اسم المستلم ناقص', 'اكتب اسم المستلم أو الجهة الاستثنائية.'));
    final c = _collect();
    if (c.err.isNotEmpty) items.add(ImdCheck('err', 'مشكلة في السطور', c.err.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isEmpty) items.add(const ImdCheck('warn', 'لا توجد أصناف بعد', 'أضف صنفًا واحدًا على الأقل قبل التنفيذ.'));
    if (imdDuplicateCount(c.rows, (r) => '${r.itemId}|${r.unitName}|${r.beneficiaryUnitId}') > 0) {
    }
    final bal = _balError(c.rows);
    if (bal.isNotEmpty) items.add(ImdCheck('err', 'الرصيد لا يكفي', bal.replaceFirst(RegExp(r'^✖\s*'), '')));
    if (c.rows.isNotEmpty) {
      items.add(ImdCheck('ok', 'ملخص سريع',
          'عدد السطور: ${nf(c.rows.length)} — إجمالي الخصم المتوقع: ${nf(c.rows.fold<double>(0, (a, b) => a + b.baseQty))}'));
    }
    return items;
  }

  String get _benName {
    final u = _units.where((x) => x.id == _ben).firstOrNull;
    return u?.name ?? '';
  }

  String get _facLabel {
    final f = _facs.where((x) => x.id == _fac).firstOrNull;
    return f == null ? '' : '${f.name} (${f.fType.toUpperCase() == 'KITCHEN' ? 'مطبخ' : 'فرن'})';
  }

  /// `issSubmit(moveStatus)`
  Future<void> _submit(String status) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'issue', status == 'DRAFT' ? 'create' : 'approve')) return;
    if (_wh.isNotEmpty && !perm.canWh(_wh)) return showImdToast(context, Perm.scopeBlock(_wh));
    final frozen = await _moves.frozenMessage(_wh);
    if (!mounted) return;
    if (frozen != null) return showImdToast(context, frozen);
    if (_wh.isEmpty) return showImdToast(context, '✖ اختر المستودع');
    if (_date.isEmpty) return showImdToast(context, '✖ اختر تاريخ الصرف');
    if (imdIsFuture(_date)) return showImdToast(context, '✖ تاريخ الصرف لا يمكن أن يكون في المستقبل');
    if (_ref.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    String target;
    switch (_type) {
      case 0:
        if (_ben.isEmpty) return showImdToast(context, '✖ اختر الوحدة المستفيدة');
        target = _benName;
      case 1:
        if (_fac.isEmpty) return showImdToast(context, '✖ اختر المطبخ أو الفرن');
        target = _facLabel;
      case 2:
        target = _custom.text.trim();
        if (target.isEmpty) return showImdToast(context, '✖ اكتب اسم المستلم');
      default:
        target = 'صرف لوحدات متعددة';
    }
    final c = _collect();
    if (c.err.isNotEmpty) return showImdToast(context, c.err);
    if (c.rows.isEmpty) return showImdToast(context, '✖ أضف صنفًا واحدًا على الأقل');
    final bal = _balError(c.rows);
    if (status == 'COMPLETED' && bal.isNotEmpty) return showImdToast(context, bal);
    setState(() => _busy = true);
    try {
      if (await _moves.hasRefConflict('issues', _ref, 'REJECTED')) {
        if (mounted) showImdToast(context, '✖ يوجد سند صرف سابق بنفس المرجع — استخدم مرجعًا مختلفًا');
        return;
      }
      if (!mounted) return;
      if (status == 'COMPLETED' && !await imdConfirm(context, 'اعتماد سند الصرف النهائي؟\nسيتم خصم الكميات من المستودع مباشرة.')) {
        return;
      }
      if (!mounted) return;
      final actor = context.read<AuthService>().currentUser;
      final res = await _moves.saveIssue(
        warehouse: _wh,
        recipientDisplay: target,
        date: _date,
        lines: c.rows,
        targetType: _type,
        unitId: _type == 0 ? _ben : '',
        facilityId: _type == 1 ? _fac : '',
        soldierCount: _strength,
        durationDays: int.tryParse(_days.text.trim()) ?? 1,
        refNo: _ref,
        notes: _notes.text.trim(),
        status: status,
        createdBy: actor?.email ?? '',
        actor: actor,
      );
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      if (!mounted) return;
      showImdToast(
          context,
          status == 'COMPLETED'
              ? '🎉 تم تنفيذ أمر الصرف وخصم الرصيد بنجاح'
              : (status == 'ORDER' ? '📤 أُرسل أمر التوجيه للمستودع' : '💾 حُفظت المسودة'));
      await _form();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _print(bool both) {
    final c = _collect();
    if (c.rows.isEmpty) return showImdToast(context, '✖ لا توجد أصناف للطباعة');
    final recipient = switch (_type) {
      0 => _units.where((x) => x.id == _ben).map((u) => '${u.code} — ${u.name}').firstOrNull ?? '—',
      1 => _facLabel.isEmpty ? '—' : _facLabel,
      2 => _custom.text.trim().isEmpty ? '—' : _custom.text.trim(),
      _ => '—',
    };
    // الصرف متعدد الجهات يطبع عمود «الوحدة المستفيدة» بدل دمجه في اسم الصنف.
    final multi = _type == 3;
    final lines = [
      for (final l in c.rows)
        VoucherLine(
          itemName: l.itemName,
          unitName: l.unitName,
          qty: l.qty,
          itemCode: l.itemCode,
          notes: l.notes,
          beneficiary: l.beneficiaryUnitName,
        ),
    ];
    final days = int.tryParse(_days.text.trim()) ?? 1;
    final end = (DateTime.tryParse(_date) ?? DateTime.now()).add(Duration(days: days - 1));
    VoucherPrint.print(
      db: _db,
      title: 'أمر صرف مخزني',
      kind: VoucherKind.issue,
      refNo: _ref,
      date: _date,
      endDate: isoDay(end),
      warehouse: _wh,
      party: recipient,
      notes: _notes.text.trim(),
      strength: nf(_strength),
      days: nf(days),
      multiUnit: multi,
      lines: lines,
      withReceipt: both,
    );
  }

  // ───────────────────────── العرض ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      const ImdPageTitle(
        title: 'صرف بضاعة',
        icon: 'upload',
        subtitle: 'سندات الصرف للوحدات والمطابخ والجهات المستفيدة والتحقق الآلي من الاستحقاق والمخزون',
      ),
      ImdItabs(
        value: _tab,
        onChanged: _switch,
        tabs: const [
          ImdTab('form', 'سند صرف جديد', icon: 'file'),
          ImdTab('drafts', 'المسودات والأوامر', icon: 'save'),
          ImdTab('hist', 'سجل الصادرات', icon: 'file'),
        ],
      ),
    ];
    if (_tab != 'form') {
      return ImdPage(children: [
        ...head,
        if (_tab == 'drafts')
          _draftsView(context)
        else ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ImdButton.outline(
                label: 'تقرير مجمّع للكميات',
                icon: 'printer',
                small: true,
                onPressed: _printAggregated,
              ),
            ),
          ),
          DocLogView(
            kinds: const {DocKind.issue},
            embedded: true,
            // «تعديل القوة» خاص بأوامر الصرف ولا يغطيه نموذج التعديل العام.
            extraActions: (doc, reload) => [
              ImdButton.outline(
                label: 'القوة',
                icon: 'users',
                small: true,
                onPressed: () => _editEntByRef(doc.refNo, reload),
              ),
            ],
          ),
        ],
      ]);
    }
    if (!_ready) return ImdPage(children: [...head, const ImdLd('جارٍ التهيئة…')]);
    final w = Perm.of(context).writable('issue');
    return ImdStickyPage(
      sticky: ImdStickyActions(
        caption: 'تنبيه: التنفيذ النهائي يخصم الرصيد فورًا',
        children: [
          ImdButton.outline(
            label: '+ سطر صنف جديد',
            small: true,
            // التجميع قبل فتح سطر جديد: أحد موضعي الاستدعاء التلقائي.
            onPressed: _busy
                ? null
                : () {
                    _autoConsolidate();
                    setState(() => _rows.add(_Row()));
                  },
          ),
          ImdButton.outline(label: 'طباعة أمر الصرف', icon: 'printer', small: true, onPressed: _busy ? null : () => _print(false)),
          ImdButton.outline(label: 'طباعة صرف واستلام', icon: 'printer', small: true, onPressed: _busy ? null : () => _print(true)),
          if (w) ...[
            ImdButton(label: 'تنفيذ أمر الصرف وخصم الرصيد', icon: 'check', busy: _busy, onPressed: () => _submit('COMPLETED')),
            ImdButton(label: 'إرسال إشعار للمستودع', icon: 'upload', kind: ImdBtnKind.blue, busy: _busy, onPressed: () => _submit('ORDER')),
            ImdButton(label: 'حفظ كمسودة', icon: 'save', kind: ImdBtnKind.warn, busy: _busy, onPressed: () => _submit('DRAFT')),
          ] else
            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: ImdLdText('👁 عرض فقط — الصرف والاعتماد متاح لمدير النظام')),
        ],
      ),
      children: [...head, ..._formBody(context)],
    );
  }

  List<Widget> _formBody(BuildContext context) {
    final c = context.imd;
    final camps = _units.where((u) => u.parentId.isEmpty).toList();
    final whOpts = _whsForCamp(_parent);
    final campFiltered = _parent.isEmpty ? <Warehouse>[] : _whs.where((w) => _feeds(w, _parent)).toList();
    final whNote = _parent.isEmpty
        ? ''
        : (campFiltered.isNotEmpty
            ? '🏕️ تمت التصفية تلقائيًا: ${nf(campFiltered.length)} مستودع يغذي هذا المعسكر'
            : '⚠ لا يوجد مستودع مرتبط بهذا المعسكر بعد — تُعرض كل المستودعات');
    final subs = _units.where((u) => _parent.isEmpty || u.parentId == _parent).toList();
    final strDateLabel = _strDate.isNotEmpty ? _strDate : _date;
    final noStrength = ((_type == 0 && _ben.isNotEmpty) || (_type == 1 && _fac.isNotEmpty)) && _strength == 0;
    Widget lab(String l, Widget f) => ImdLabeled(l, f, size: 11);

    return [
      ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdWorkflowSteps(['حدد الجهة المستفيدة', 'اختر الأصناف', 'راجع الاستحقاق', 'اطبع أو نفّذ أو احفظ مسودة']),
          ImdQuickGrid([
            ('الأصناف', nf(_items.length)),
            ('الوحدات', nf(_units.length)),
            ('المستودعات', nf(_whs.length)),
            ('المطابخ/الأفران', nf(_facs.length)),
          ]),
          const ImdPrintTip('لو محتاج موافقة تشغيلية قبل الخصم الفعلي، استخدم «إشعار للمستودع» أو «مسودة» بدل التنفيذ المباشر.'),
        ]),
      ),
      const SizedBox(height: 12),
      ImdICard(
        title: 'نوع التوجيه والجهة المستفيدة',
        icon: 'target',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdTargetPills<int>(
            value: _type,
            onChanged: _setType,
            tabs: const [
              ImdTab(0, 'وحدة مستفيدة', icon: 'users'),
              ImdTab(1, 'مطبخ / فرن', icon: 'utensils'),
              ImdTab(2, 'استثنائي / مخصص', icon: 'star'),
              ImdTab(3, 'وحدات متعددة', icon: 'file'),
            ],
          ),
          // .f4 auto-fit minmax(180px,1fr)
          ImdAutoGrid(minItem: 180, gap: 12, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              lab(
                'المستودع المصروف منه *',
                ImdSelect<String>(
                  value: _wh,
                  items: whOpts.isEmpty
                      ? [('', Perm.of(context).scope == null ? '— لا مستودعات —' : '— لا توجد مستودعات ضمن نطاقك —')]
                      : [for (final w in whOpts) (w.name, '${w.code.isNotEmpty ? '${w.code} — ' : ''}${w.name}')],
                  onChanged: (v) {
                    setState(() => _wh = v ?? '');
                    _refreshBal();
                  },
                ),
              ),
              if (whNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: ImdEmojiText(whNote, iconSize: 11, style: TextStyle(fontSize: 11, color: c.muted)),
                ),
            ]),
            lab('تاريخ الصرف', ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v))),
            lab('رقم السند/المرجع', ImdReadonlyField(text: _ref)),
            lab(
              'موعد الصرف القادم',
              ImdReadonlyField(
                text: _nextDue,
                weight: FontWeight.w800,
                bg: c.isDark ? const Color(0x26FDB022) : const Color(0xFFFFF8E1),
                color: _nextDueColor ?? const Color(0xFFB78103),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ImdF2(cols: 3, children: [
            if (_type == 0) ...[
              lab(
                'المعسكر / الوحدة الرئيسية',
                ImdSelect<String>(
                  value: _parent,
                  items: [('', 'الكل / لا يوجد'), for (final cp in camps) (cp.id, '${cp.code} — ${cp.name}')],
                  onChanged: (v) => _onParent(v ?? ''),
                ),
              ),
              lab(
                'الوحدة التابعة المستفيدة *',
                ImdSelect<String>(
                  value: _ben,
                  items: [('', '— اختر الوحدة —'), for (final u in subs) (u.id, '${u.code} — ${u.name}')],
                  onChanged: (v) => _onBen(v ?? ''),
                ),
              ),
            ],
            if (_type == 1)
              lab(
                'المطبخ أو الفرن المستلم *',
                ImdSelect<String>(
                  value: _fac,
                  items: [
                    ('', '— اختر المطبخ/الفرن —'),
                    for (final f in _facs) (f.id, '${f.name} (${f.fType.toUpperCase() == 'KITCHEN' ? 'مطبخ' : 'فرن'})'),
                  ],
                  onChanged: (v) {
                    setState(() => _fac = v ?? '');
                    _fetchStrength();
                  },
                ),
              ),
            if (_type == 2)
              lab('اسم المستلم (للاستثناءات) *', ImdFld(controller: _custom, hint: 'اكتب اسم المستلم / الجهة...', onChanged: (_) => setState(() {}))),
          ]),
          if (_type == 0 || _type == 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ImdDashedBox(
                child: ImdF2(cols: 3, children: [
                  lab('تاريخ إلحاق القوة (حصر القوة)', ImdDateField(value: _strDate, onChanged: (v) {
                    setState(() => _strDate = v);
                    _fetchStrength();
                  })),
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    lab('إجمالي القوة (أفراد/ضباط)', ImdReadonlyField(text: _num(_strength), bg: c.surface, color: c.accent)),
                    if (noStrength)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('لا توجد تفريدة بتاريخ $strDateLabel — القوة صفر', style: TextStyle(fontSize: 11, color: c.warn)),
                      ),
                  ]),
                  lab('مدة الإعاشة (أيام)', ImdFld(controller: _days, number: true, onChanged: (_) => _recalcAll())),
                ]),
              ),
            ),
          const SizedBox(height: 10),
          lab('ملاحظات السند / الغرض من الصرف', ImdFld(controller: _notes, hint: 'ملاحظات توثيقية حول أمر الصرف...')),
        ]),
      ),
      // نفس أداة «الاحتساب التلقائي» في شاشة التحويل المخزني: المنطق كان
      // موجودًا هنا (يُحدّث الأسطر المضافة يدويًا) وينقصه ملء الجدول دفعة واحدة.
      if (_strength > 0)
        ImdICard(
          title: 'احتساب تلقائي بالاستحقاقات (بدل إدخال كل صنف يدويًا)',
          icon: 'calculator',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdPrintTip(
                'تُحسب الكمية = الاستحقاق اليومي للفرد × إجمالي القوة × مدة الإعاشة. '
                'القوة تُجلب من تفريدة الجهة المستفيدة أعلاه، والمقرر من شاشة الاستحقاقات.'),
            const SizedBox(height: 10),
            ImdRbar(bottom: 0, children: [
              ImdChip('القوة: ${nf(_strength)}', tone: ImdTone.ok),
              ImdChip('المدة: ${_days.text.trim().isEmpty ? '1' : _days.text.trim()} يوم',
                  tone: ImdTone.code),
              ImdButton(
                label: 'احتساب الأصناف تلقائيًا',
                icon: 'calculator',
                onPressed: _busy ? null : _autoFillFromEntitlements,
              ),
            ]),
          ]),
        ),
      ImdICard(
        title: 'ماسح الباركود / الإضافة السريعة',
        icon: 'tag',
        child: ImdBarcodeInput(hint: 'مرّر قارئ الباركود أو اكتب الكود واضغط Enter…', onSubmit: _scan),
      ),
      for (final (i, r) in _rows.indexed) KeyedSubtree(key: r.key, child: _rowView(context, i + 1, r)),
      ImdValidationBox(title: 'فحص سريع قبل تنفيذ أمر الصرف', items: _validate()),
    ];
  }


  /// مكافئ الكمية بالوحدة الأساسية — يجعل التجميع التلقائي وإعادة التوزيع
  /// مرئيَّين للمستخدم بدل أن يتغيّر الرقم أمامه بلا تفسير.
  Widget? _baseHint(_Row r) {
    final it = _item(r.itemId);
    if (it == null || r.unit.isEmpty) return null;
    final qty = double.tryParse(r.qty.text.trim()) ?? 0;
    final f = _catalog.factorOf(it, r.unit);
    if (qty <= 0 || f == 1) return null;
    return ImdRowMeta('= ${nf((qty * f * 1000).round() / 1000)} ${it.baseUnit}');
  }

  Widget _rowView(BuildContext context, int index, _Row r) {
    final c = context.imd;
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final multi = _type == 3;
    final narrow = MediaQuery.sizeOf(context).width <= 768;
    // الرصيد يُعرض بوحدة العرض المختارة في بطاقة الصنف لا بالأساسية دائمًا.
    final shown = it == null
        ? null
        : displayBalance(it, _wh.isNotEmpty ? (_whBal[it.id] ?? 0) : it.qty);
    final meta = it == null
        ? ''
        : (_wh.isNotEmpty
            ? 'رصيد «$_wh»: ${nf(shown!.qty)} ${shown.unit}'
            : 'المتاح: ${nf(shown!.qty)} ${shown.unit}');
    final picker = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الصنف'),
      ImdItemPicker(
        items: _items,
        value: r.itemId,
        labelOf: (i) => '${i.code} — ${i.name} (رصيد: ${nf(_whBal[i.id] ?? i.qty)})',
        onChanged: (v) => _onItem(r, v),
      ),
      ImdRowMeta(meta),
    ]);
    final ben = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الوحدة المستفيدة'),
      ImdSelect<String>(
        value: r.benUnit.isEmpty && _units.isNotEmpty ? _units.first.id : r.benUnit,
        items: [for (final u in _units) (u.id, '${u.code} — ${u.name}')],
        onChanged: (v) => setState(() => r.benUnit = v ?? ''),
      ),
    ]);
    final unit = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الوحدة'),
      ImdSelect<String>(
        value: r.unit,
        items: units.isEmpty ? const [('', '—')] : [for (final u in units) (u.name, u.name)],
        onChanged: (v) => setState(() {
          final next = v ?? '';
          final previous = r.unit;
          final qty = double.tryParse(r.qty.text.trim()) ?? 0;
          r.unit = next;
          // الاستحقاق أولى إن انطبق؛ وإلا تُحوَّل الكمية بمعامل الوحدتين
          // (١١٠٠ كجم ⇒ ٢٧٫٥ كيسًا) بدل بقاء الرقم على حاله.
          if (_calcRow(r)) return;
          final item = _item(r.itemId);
          if (item != null && qty > 0 && previous.isNotEmpty && next.isNotEmpty && next != previous) {
            imdSetText(
              r.qty,
              _num(convertQty(
                qty,
                _catalog.factorOf(item, previous),
                _catalog.factorOf(item, next),
              )),
            );
          }
        }),
      ),
    ]);
    final qty = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الكمية'),
      // مغادرة الحقل تجمع الأصناف المكررة تلقائيًا وتعيد توزيع الوحدات.
      Focus(
        onFocusChange: (has) {
          if (!has) _autoConsolidate();
        },
        child: ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
      ),
    ]);
    final del = Padding(
      padding: const EdgeInsets.only(top: 19),
      child: ImdIconButton(
        icon: 'x',
        kind: ImdBtnKind.danger,
        onPressed: () => setState(() {
          _rows.remove(r);
          r.dispose();
          if (_rows.isEmpty) _rows.add(_Row());
        }),
      ),
    );
    Widget grid;
    if (narrow) {
      grid = Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: picker), const SizedBox(width: 10), Expanded(child: multi ? ben : unit)]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (multi) ...[Expanded(child: unit), const SizedBox(width: 10)],
          Expanded(child: qty),
          const SizedBox(width: 10),
          del,
        ]),
      ]);
    } else if (multi) {
      // .rgrid-multi: 1fr 1fr 120px 90px auto
      grid = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: picker),
        const SizedBox(width: 10),
        Expanded(child: ben),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: unit),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: qty),
        const SizedBox(width: 10),
        del,
      ]);
    } else {
      grid = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: picker),
        const SizedBox(width: 10),
        SizedBox(width: 150, child: unit),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: qty),
        const SizedBox(width: 10),
        del,
      ]);
    }
    return ImdRvRow(
      index: index,
      trailing: _baseHint(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        grid,
        if (it != null && it.isRefillable)
          ImdCyBox(
            label: '🛢️ صنف قابل للتعبئة/الاستبدال — العملية:',
            value: r.cy,
            options: const [('EXCHANGE', 'استبدال أسطوانات'), ('ISSUE_FULL', 'صرف ممتلئ'), ('ISSUE_EMPTY', 'صرف فارغ'), ('CONSUME', 'استهلاك داخلي')],
            onChanged: (v) => setState(() => r.cy = v),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextField(
            controller: r.notes,
            style: TextStyle(fontSize: 12, color: c.text),
            decoration: imdFieldDecoration(context, hint: 'ملاحظات على هذا الصنف...', dense: true)
                .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          ),
        ),
      ]),
    );
  }

  // ───────────────────────── المسودات والأوامر ─────────────────────────
  Future<void> _loadDrafts() async {
    setState(() => _drafts = null);
    final rows = await (_db.select(_db.issues)..where((t) => t.status.isIn(const ['DRAFT', 'ORDER']))).get();
    if (mounted) setState(() => _drafts = rows);
  }

  Map<String, List<Issue>> _group(List<Issue> docs) {
    final g = <String, List<Issue>>{};
    for (final d in docs) {
      g.putIfAbsent(d.refNo.isNotEmpty ? d.refNo : '_${d.id}', () => []).add(d);
    }
    return g;
  }

  Widget _draftsView(BuildContext context) {
    final docs = _drafts;
    if (docs == null) return const ImdLd('جارٍ تحميل المسودات…');
    final groups = _group(docs);
    if (groups.isEmpty) return const ImdICard(child: ImdLdText('لا توجد مسودات أو أوامر معلقة 👌'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdChipsRow(children: [ImdChip('أوامر ومسودات: ${nf(groups.length)}', tone: ImdTone.code)]),
      for (final e in groups.entries)
        () {
          final f = e.value.first;
          final isOrder = f.status == 'ORDER';
          return ImdDocCard(
            head: [
              ImdChip(isOrder ? '📤 أمر توجيه' : '💾 مسودة', tone: isOrder ? ImdTone.ok : ImdTone.pend),
              ImdChip(e.key, tone: ImdTone.code),
              Text(f.recipientDisplay.isEmpty ? '—' : f.recipientDisplay, style: const TextStyle(fontWeight: FontWeight.w700)),
              ImdChip(f.date.isEmpty ? '—' : f.date, tone: ImdTone.off),
              ImdChip('${nf(e.value.length)} صنف', tone: ImdTone.ok),
              ImdDocWarehouse(f.warehouse),
            ],
            actions: [
              ImdButton(label: 'اعتماد وصرف الرصيد', icon: 'check', small: true, onPressed: () => _approveDraft(e.key, e.value)),
              ImdButton(label: 'حذف', icon: 'trash', small: true, kind: ImdBtnKind.danger, onPressed: () => _deleteDraft(e.key, e.value)),
            ],
          );
        }(),
    ]);
  }

  Future<void> _approveDraft(String k, List<Issue> g) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'issue', 'approve')) return;
    if (!perm.canWh(g.first.warehouse)) return showImdToast(context, Perm.scopeBlock(g.first.warehouse));
    if (!await imdConfirm(context, 'اعتماد أمر الصرف وخصم الرصيد المخزني لجميع الأصناف؟')) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      // فحص الرصيد والتجميد والاعتماد في مكان واحد: رصيد مستودع السند لا الإجمالي.
      final res = await _moves.approveIssues(g, actor: actor);
      if (!mounted) return;
      if (!res.ok) return showImdToast(context, res.error);
      showImdToast(context, '✔ اعتُمد السند وتم خصم الرصيد');
      await _loadDrafts();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _deleteDraft(String k, List<Issue> g) async {
    if (!Perm.of(context).canWh(g.first.warehouse)) return showImdToast(context, Perm.scopeBlock(g.first.warehouse));
    if (!await imdConfirm(context, 'حذف هذه المسودة نهائياً؟', ok: 'حذف', danger: true)) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _db.transaction(() async {
        for (final d in g) {
          await (_db.delete(_db.issues)..where((t) => t.id.equals(d.id))).go();
        }
      });
      await AuditRepo(_db).write('ISSUE_DRAFT_DELETED', 'issue', 'حذف مسودة صرف',
          details: {
            'refNo': k,
            'warehouse': g.first.warehouse,
            'target': g.first.recipientDisplay,
            'status': 'DELETED',
            'itemCount': g.length,
            'risk': 'sensitive',
          },
          actor: actor);
      if (mounted) showImdToast(context, '✔ حُذفت المسودة');
      await _loadDrafts();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  // ───────────────────────── السجل ─────────────────────────

  /// أسطر الصرف المعتمدة ضمن نطاق المستخدم — يجلبها التقرير المجمّع بنفسه
  /// بعد أن صار السجل مكوّنًا مشتركًا لا يملك هذه الشاشة حالته.
  Future<List<Issue>> _issuedLines() async {
    final perm = Perm.of(context);
    final rows = await (_db.select(_db.issues)
          ..where((t) => t.status.equals('COMPLETED')))
        .get();
    return rows.where((r) => perm.canWh(r.warehouse)).toList();
  }


  /// زر «تعديل القوة» داخل سجل الصادرات — قدرة لا يغطيها نموذج التعديل العام
  /// (يحافظ على القوة والأيام ولا يسمح بتغييرهما).
  Future<void> _editEntByRef(String refNo, Future<void> Function() reload) async {
    final group = await (_db.select(_db.issues)..where((t) => t.refNo.equals(refNo))).get();
    if (group.isEmpty) return;
    await _editEnt(group);
    await reload();
  }

  /// نافذة «تعديل بيانات السند والقوة» (`editEntOvl`).
  Future<void> _editEnt(List<Issue> group) async {
    final f = group.first;
    final soldiers = TextEditingController(text: _num(f.soldierCount));
    final officers = TextEditingController(text: _num(f.officerCount));
    final days = TextEditingController(text: '${f.durationDays}');
    final ok = await showImdModal<bool>(
      context,
      title: 'تعديل بيانات السند والقوة',
      icon: 'edit',
      maxWidth: 420,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdField(label: 'عدد القوة (أفراد)', controller: soldiers, keyboardType: TextInputType.number),
        ImdField(label: 'عدد الضباط', controller: officers, keyboardType: TextInputType.number),
        ImdField(label: 'مدة الإعاشة (أيام)', controller: days, keyboardType: TextInputType.number),
      ]),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'حفظ التعديل', icon: 'save', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    final s = double.tryParse(soldiers.text) ?? 0, o = double.tryParse(officers.text) ?? 0;
    final dd = int.tryParse(days.text) ?? 1;
    soldiers.dispose();
    officers.dispose();
    days.dispose();
    if (ok != true) return;
    try {
      await _db.transaction(() async {
        for (final d in group) {
          await (_db.update(_db.issues)..where((t) => t.id.equals(d.id))).write(IssuesCompanion(
            soldierCount: Value(s),
            officerCount: Value(o),
            durationDays: Value(dd <= 0 ? 1 : dd),
          ));
        }
      });
      if (!mounted) return;
      showImdToast(context, '✔ تم تحديث بيانات السند والقوة بنجاح');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  /// `issPrintAggregated()` — مجموع الكميات لكل (صنف|وحدة) ضمن نتائج البحث.
  Future<void> _printAggregated() async {
    final rows = await _issuedLines();
    if (!mounted) return;
    if (rows.isEmpty) return showImdToast(context, '✖ لا توجد بيانات للطباعة');
    final agg = <String, double>{};
    for (final r in rows) {
      final k = '${r.itemName}|${r.unitName}';
      agg[k] = (agg[k] ?? 0) + r.qty;
    }
    var i = 1;
    final layout = await SettingsRepo(_db).printLayout();
    await DocumentPdf.printDoc(
      layout: layout,
      doc: PrintDoc(
        title: 'تقرير مجمّع كميات أوامر الصرف',
        headers: const ['م', 'اسم الصنف', 'إجمالي الكمية المصروفة', 'الوحدة'],
        columnFlex: const [1, 6, 3, 2],
        rows: [
          for (final e in agg.entries) ['${i++}', e.key.split('|').first, nf(e.value), e.key.split('|').last],
        ],
        leftValues: {'date': imdToday(), 'refNo': 'مجمّع'},
        fieldValues: const {'warehouse': 'المستودع العام', 'party': 'كافة الوحدات'},
      ),
    );
  }
}
