import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/line_consolidation.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/issue_rules.dart';
import '../../domain/strength.dart';
import '../../domain/cylinders.dart';
import 'doc_kit.dart';
import 'issue_drafts_view.dart';

/// صرف بضاعة — نقل مطابق لـ `renderIssue()`: سند صرف جديد (أربعة أنواع توجيه، القوة والاستحقاق،
/// موعد الصرف القادم)، المسودات والأوامر، وسجل الصادرات مع تعديل القوة/الأيام والطباعة المجمّعة.
class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key});

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _Row {
  _Row({this.itemId = '', this.unit = '', double? qty, String notes = '', this.benUnit = '', this.noAuto = false, this.onEdit})
      : cy = 'EXCHANGE', qty = TextEditingController(text: qty == null ? '' : _num(qty)),
        notes = TextEditingController(text: notes) {
    this.qty.addListener(_changed);
    this.notes.addListener(_changed);
  }
  String itemId;
  String unit;
  final TextEditingController qty;
  final TextEditingController notes;
  String cy;
  String benUnit;
  bool noAuto;
  final VoidCallback? onEdit;
  final key = UniqueKey();

  void _changed() => onEdit?.call();

  void dispose() {
    qty.removeListener(_changed);
    notes.removeListener(_changed);
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
  Timer? _autosaveTimer;
  DateTime? _autosavedAt;
  bool _restoringAutosave = false;

  // سندات معلّقة داخل الجلسة (تبويب «سند جديد»)
  final List<ImdDocTab<Map<String, dynamic>>> _suspended = [];
  int _tabSeq = 1;
  int _activeTabId = 0;

  String get _autosaveKey =>
      'imdad.issue.recovery.${context.read<AuthService>().currentUser?.id ?? 'local'}';

  _Row _newRow({String itemId = '', String unit = '', double? qty, String notes = '', String benUnit = '', bool noAuto = false}) =>
      _Row(itemId: itemId, unit: unit, qty: qty, notes: notes, benUnit: benUnit, noAuto: noAuto, onEdit: _scheduleAutosave);


  @override
  void initState() {
    super.initState();
    for (final controller in [_custom, _days, _notes]) {
      controller.addListener(_scheduleAutosave);
    }
    _form();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final c in [_custom, _days, _notes]) {
      c.removeListener(_scheduleAutosave);
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
  }

  // ───────────────────────── النموذج ─────────────────────────
  /// `issFetchAll()` + `issRenderForm()`
  Future<void> _form() async {
    _ready = false;
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
        ..add(_newRow());
      _wh = _whsForCamp('').isNotEmpty ? _whsForCamp('').first.name : '';
      if (_type == 2 || _type == 3) _strength = 0;
      _ready = true;
    });
    await _refreshBal();
    await _restoreAutosave();
  }

  void _scheduleAutosave() {
    if (!_ready || _restoringAutosave || _tab != 'form') return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveAutosave);
    if (_autosavedAt != null && mounted) setState(() => _autosavedAt = null);
  }

  Future<void> _saveAutosave() async {
    if (!_ready || _restoringAutosave || _busy || _tab != 'form') return;
    final prefs = await SharedPreferences.getInstance();
    final snapshot = {..._captureDocSnapshot(), 'savedAt': DateTime.now().toIso8601String()};
    await prefs.setString(_autosaveKey, jsonEncode(snapshot));
    if (mounted) setState(() => _autosavedAt = DateTime.now());
  }

  /// لقطة بيانات سند الصرف الحالي — للحفظ التلقائي وتعليق السند في تبويب.
  Map<String, dynamic> _captureDocSnapshot() => {
        'type': _type,
        'ref': _ref,
        'warehouse': _wh,
        'date': _date,
        'parent': _parent,
        'beneficiary': _ben,
        'facility': _fac,
        'custom': _custom.text,
        'strengthDate': _strDate,
        'days': _days.text,
        'notes': _notes.text,
        'strength': _strength,
        'rows': [
          for (final row in _rows)
            {
              'item': row.itemId,
              'unit': row.unit,
              'qty': row.qty.text,
              'notes': row.notes.text,
              'beneficiary': row.benUnit,
              'cylinder': row.cy,
              'noAuto': row.noAuto,
            },
        ],
      };

  /// يكتب لقطةً محفوظةً (تلقائية أو من تبويبٍ معلّق) رجوعًا إلى حقول النموذج.
  void _applySnapshot(Map<String, dynamic> data) {
    setState(() {
      _type = (data['type'] as num?)?.toInt() ?? _type;
      _ref = '${data['ref'] ?? _ref}';
      _wh = '${data['warehouse'] ?? _wh}';
      _date = '${data['date'] ?? _date}';
      _parent = '${data['parent'] ?? ''}';
      _ben = '${data['beneficiary'] ?? ''}';
      _fac = '${data['facility'] ?? ''}';
      imdSetText(_custom, '${data['custom'] ?? ''}');
      _strDate = '${data['strengthDate'] ?? _date}';
      imdSetText(_days, '${data['days'] ?? '1'}');
      imdSetText(_notes, '${data['notes'] ?? ''}');
      _strength = (data['strength'] as num?)?.toDouble() ?? 0;
      for (final row in _rows) {
        row.dispose();
      }
      final savedRows = data['rows'];
      _rows
        ..clear()
        ..addAll(savedRows is List
            ? [
                for (final value in savedRows.whereType<Map>())
                  _newRow(
                    itemId: '${value['item'] ?? ''}',
                    unit: '${value['unit'] ?? ''}',
                    qty: double.tryParse('${value['qty'] ?? ''}'),
                    notes: '${value['notes'] ?? ''}',
                    benUnit: '${value['beneficiary'] ?? ''}',
                    noAuto: value['noAuto'] == true,
                  )..cy = '${value['cylinder'] ?? 'EXCHANGE'}',
              ]
            : <_Row>[]);
      if (_rows.isEmpty) _rows.add(_newRow());
    });
  }

  // ─────────────────────── تبويبات السندات المعلّقة ───────────────────────
  String _activeTabLabel() => _ref.isNotEmpty ? _ref : 'سند بلا رقم';

  /// زر «سند جديد»: يعلّق السند الحالي في تبويبٍ جانبي ويفتح سندًا فارغًا.
  void _openNewTab() {
    final snap = _captureDocSnapshot();
    setState(() {
      _suspended.add(ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: snap));
      _activeTabId = _tabSeq++;
      _tab = 'form';
    });
    _form();
  }

  void _switchDocTab(int id) {
    if (id == _activeTabId) return;
    final idx = _suspended.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final target = _suspended.removeAt(idx);
    final current = ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: _captureDocSnapshot());
    setState(() {
      _suspended
        ..removeWhere((t) => t.id == target.id)
        ..add(current);
      _activeTabId = target.id;
      _tab = 'form';
    });
    _applySnapshot(target.snapshot);
    _refreshBal();
  }

  void _closeDocTab(int id) => setState(() => _suspended.removeWhere((t) => t.id == id));

  /// يكشف [_isPristine] للاختبار — سباق الاستعادة الحقيقي يتوقف على زمن قراءة
  /// `SharedPreferences` عبر قناة المنصّة، وهذا زمنٌ لا تملك بيئة الاختبار
  /// (قراءاتها مُموَّهة تُحل فورًا عبر microtasks) أن تحاكيه بدقة. فحارس
  /// السلامة نفسه هو ما يُختبر مباشرة، لا توقيت السباق حوله.
  @visibleForTesting
  bool debugIsPristine() => _isPristine();

  /// النموذج ما يزال على حاله الافتراضية الفارغة تمامًا — لم يكتب المستخدم
  /// حرفًا ولم يختر شيئًا بعد. هذا هو الشرط الوحيد الآمن لتطبيق استعادة
  /// المسودة: أي تغييرٍ آخر يعني أن المستخدم بدأ عملًا لا يصحّ إسقاطه.
  bool _isPristine() {
    if (_rows.length != 1) return false;
    final r = _rows.single;
    if (r.itemId.isNotEmpty || r.unit.isNotEmpty) return false;
    if (r.qty.text.isNotEmpty || r.notes.text.isNotEmpty) return false;
    if (r.benUnit.isNotEmpty || r.noAuto) return false;
    if (_custom.text.isNotEmpty || _notes.text.isNotEmpty) return false;
    if (_parent.isNotEmpty || _ben.isNotEmpty || _fac.isNotEmpty) return false;
    if (_days.text.isNotEmpty && _days.text != '1') return false;
    return true;
  }

  Future<void> _restoreAutosave() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autosaveKey);
    if (raw == null || !mounted) return;
    Map<String, dynamic> data;
    try {
      data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      await prefs.remove(_autosaveKey);
      return;
    }
    // هذه القراءة غير متزامنة (SharedPreferences ثم فكّ JSON)، فقد يبدأ
    // المستخدم العمل — يختار صنفًا في الصفّ الافتراضي مثلًا — قبل اكتمالها.
    // استبدال الصفوف حينئذٍ كان يُسقط عمله بلا تنبيه، ويهدم عنصر الصفّ الذي
    // قد يكون مركَّزًا عليه أثناء تفاعله (متحكّمه وعقدة تركيزه تُتلَفان مع
    // الصفّ القديم). فلا تُطبَّق الاستعادة إلا والنموذج ما يزال على حاله
    // الافتراضية الفارغة تمامًا.
    if (!_isPristine()) return;
    _restoringAutosave = true;
    try {
      _applySnapshot(data);
      await _refreshBal();
      final savedAt = DateTime.tryParse('${data['savedAt'] ?? ''}');
      if (mounted) {
        setState(() => _autosavedAt = savedAt);
        showImdToast(context, 'استُعيدت مسودة الصرف المحفوظة تلقائيًا');
      }
    } finally {
      _restoringAutosave = false;
    }
  }

  Future<void> _refreshBal() async {
    // بلا مستودع محدد: إجمالي مستودعات نطاق المستخدم من دفتر الحركات نفسه —
    // لا عمود `items.qty` القديم الذي لا يعرف المستودعات ولا الحركات.
    final b = await _moves.balances(warehouse: _wh, scope: Perm.of(context).scope);
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
    _scheduleAutosave();
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
    _scheduleAutosave();
    _refreshBal();
  }

  Future<void> _onBen(String uid) async {
    setState(() => _ben = uid);
    _scheduleAutosave();
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

  /// `issCheckNextDue(unitId)` — الحساب في [IssueRules.nextDue].
  Future<void> _checkNextDue(String unitId) async {
    final rows = await (_db.select(_db.issues)
          ..where((t) => t.unitId.equals(unitId))
          ..where((t) => t.status.equals('COMPLETED')))
        .get();
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    final due = IssueRules.nextDue([
      for (final v in rows) (date: v.date.isNotEmpty ? v.date : isoDay(v.createdAt), durationDays: v.durationDays),
    ], DateTime.now());
    if (!due.hasHistory) {
      setState(() {
        _nextDue = 'لا يوجد صرف سابق';
        _nextDueColor = const Color(0xFF155724);
      });
      return;
    }
    final date = due.date;
    if (date == null) return;
    final str = isoDay(date);
    setState(() {
      if (due.overdue) {
        _nextDue = '⚠️ متأخر! كان يجب الصرف في $str';
        _nextDueColor = context.imd.danger;
      } else if (due.dueToday) {
        _nextDue = '📢 اليوم! موعد الصرف $str';
        _nextDueColor = const Color(0xFFB78103);
      } else {
        _nextDue = '📅 $str (بعد ${due.daysLeft} يوم)';
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
    final qty = IssueRules.entitledQty(
      monthlyPerPerson: ent.qtyPerPerson,
      measureFactor: _catalog.factorOf(it, ent.measureUnitName),
      strength: _strength,
      days: int.tryParse(_days.text.trim()) ?? 1,
      lineFactor: _catalog.factorOf(it, r.unit),
    );
    if (qty == null) return false;
    r.qty.text = _num(qty);
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
        _rows.add(_newRow(itemId: it.id, unit: uName, qty: qty, benUnit: ben, noAuto: true));
        added++;
      }
      if (_rows.isEmpty) _rows.add(_newRow(benUnit: ben));
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
      if (it != null && !r.noAuto && identical(_rows.last, r)) _rows.add(_newRow(benUnit: _units.isNotEmpty ? _units.first.id : ''));
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
      final have = _whBal[it.id] ?? 0;
      if (_wh.isNotEmpty && IssueRules.shortage([(it.id, qty * factor)], _whBal) != null) {
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
    final short = IssueRules.shortage([for (final r in rows) (r.itemId, r.baseQty)], _whBal);
    return short == null ? '' : MovementsRepo.stockError(_item(short.itemId), _wh, short.available, short.requested);
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
            _newRow(
              itemId: l.groupKey.split('|')[0],
              unit: l.unitName,
              qty: l.qty,
              notes: notesOf[l.groupKey] ?? '',
              benUnit: l.groupKey.split('|')[1],
              noAuto: true,
            )..cy = l.groupKey.split('|')[2].isEmpty ? 'EXCHANGE' : l.groupKey.split('|')[2],
          ...pending,
        ]);
      if (_rows.isEmpty) _rows.add(_newRow());
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
    final row = _newRow(qty: 1);
    setState(() => _rows.add(row));
    _onItem(row, it.id);
    showImdToast(context, '➕ أُضيف: ${it.name}');
  }

  /// `issValidateLive()`
  List<ImdCheck> _validate() {
    final items = <ImdCheck>[];
    for (final p in IssueRules.headerProblems(_header, today: DateTime.now())) {
      items.add(ImdCheck(p.isError ? 'err' : 'warn', p.title, p.detail));
    }
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

  /// رأس السند الحالي لقواعد [IssueRules].
  IssueHeader get _header => IssueHeader(
        target: IssueTarget.of(_type),
        warehouse: _wh,
        date: _date,
        unitId: _ben,
        unitName: _benName,
        facilityId: _fac,
        facilityLabel: _facLabel,
        customRecipient: _custom.text,
      );

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
    final header = _header;
    final problems = IssueRules.headerProblems(header, today: DateTime.now());
    if (problems.isNotEmpty) return showImdToast(context, problems.first.message);
    if (_ref.isEmpty) return showImdToast(context, '✖ المرجع غير جاهز — أعد فتح الشاشة');
    final target = header.recipient;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_autosaveKey);
      _autosavedAt = null;
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
      ImdPageTitle(
        title: 'صرف بضاعة',
        icon: 'upload',
        subtitle: 'سندات الصرف للوحدات والمطابخ والجهات المستفيدة والتحقق الآلي من الاستحقاق والمخزون',
        actions: [
          ImdButton.outline(label: 'سند جديد', icon: 'plus-square', small: true, onPressed: _openNewTab),
          ImdItabs(
            value: _tab,
            onChanged: _switch,
            tabs: const [
              ImdTab('form', 'سند صرف جديد', icon: 'file'),
              ImdTab('drafts', 'المسودات والأوامر', icon: 'save'),
              ImdTab('hist', 'سجل الصادرات', icon: 'file'),
            ],
          ),
        ],
      ),
      if (_suspended.isNotEmpty)
        ImdDocTabsBar<Map<String, dynamic>>(
          activeLabel: _activeTabLabel(),
          suspended: _suspended,
          onSelect: _switchDocTab,
          onClose: _closeDocTab,
        ),
    ];
    if (_tab != 'form') {
      return ImdPage(children: [
        ...head,
        if (_tab == 'drafts')
          const IssueDraftsView()
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
        caption: _autosavedAt == null
            ? 'الحفظ التلقائي محلي على هذا الجهاز'
            : 'حُفظت المسودة تلقائيًا على هذا الجهاز',
        children: [
          ImdButton.outline(label: 'طباعة أمر الصرف', icon: 'printer', small: true, onPressed: _busy ? null : () => _print(false)),
          ImdMenuButton<int>(
            label: 'خيارات إضافية',
            small: true,
            items: (_) => const [
              PopupMenuItem(value: 1, child: Text('إضافة سطر صنف')),
              PopupMenuItem(value: 2, child: Text('طباعة صرف واستلام')),
            ],
            onSelected: (action) {
              if (action == 1 && !_busy) {
                _autoConsolidate();
                setState(() => _rows.add(_newRow()));
                _scheduleAutosave();
              }
              if (action == 2 && !_busy) _print(true);
            },
          ),
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
    final headerReady = IssueRules.headerProblems(_header, today: DateTime.now()).isEmpty;
    final collected = _collect();
    final hasRows = _rows.any((row) => row.itemId.isNotEmpty);
    final hasErrors = _validate().any((x) => x.level == 'err');
    final activeStep = !headerReady
        ? 0
        : !hasRows
            ? 1
            : (collected.err.isNotEmpty || hasErrors)
                ? 2
                : 3;
    const nextSteps = [
      'أكمل المستودع والجهة المستفيدة وتأكد من صحة التاريخ.',
      'أضف صنفًا واحدًا على الأقل وحدد وحدته وكميته.',
      'راجع الرصيد والاستحقاق والملاحظات قبل الإرسال.',
      'اكتمل التحقق. اختر الحفظ كمسودة أو الإرسال أو التنفيذ النهائي.',
    ];
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
      ImdGuidePanel(
        child: ImdSoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdWorkflowSteps(
              const ['حدد الجهة المستفيدة', 'اختر الأصناف', 'راجع الاستحقاق', 'اطبع أو نفّذ أو احفظ مسودة'],
              activeIndex: activeStep,
              hints: nextSteps,
            ),
            ImdQuickGrid([
              ('الأصناف', nf(_items.length)),
              ('الوحدات', nf(_units.length)),
              ('المستودعات', nf(_whs.length)),
              ('المطابخ/الأفران', nf(_facs.length)),
            ]),
            const ImdPrintTip('لو محتاج موافقة تشغيلية قبل الخصم الفعلي، استخدم «إشعار للمستودع» أو «مسودة» بدل التنفيذ المباشر.'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ImdICard(
        title: 'نوع التوجيه والجهة المستفيدة',
        icon: 'target',
        child: ImdCompact(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          const SizedBox(height: 6),
          ImdFormGrid(children: [
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
            lab('تاريخ الصرف', ImdDateField(value: _date, onChanged: (v) { setState(() => _date = v); _scheduleAutosave(); })),
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
          const SizedBox(height: 6),
          ImdFormGrid(children: [
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
                    _scheduleAutosave();
                    _fetchStrength();
                  },
                ),
              ),
            if (_type == 2)
              lab('اسم المستلم (للاستثناءات) *', ImdFld(controller: _custom, hint: 'اكتب اسم المستلم / الجهة...', onChanged: (_) => setState(() {}))),
          ]),
          if (_type == 0 || _type == 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ImdDashedBox(
                child: ImdFormGrid(children: [
                  lab('تاريخ إلحاق القوة (حصر القوة)', ImdDateField(value: _strDate, onChanged: (v) {
                    setState(() => _strDate = v);
                    _scheduleAutosave();
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
          const SizedBox(height: 6),
          ImdCollapsibleSection(
            title: 'ملاحظات السند / الغرض من الصرف',
            child: ImdFld(controller: _notes, hint: 'ملاحظات توثيقية حول أمر الصرف...'),
          ),
        ])),
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
      if (ImdBp.of(context).mobile)
        for (final (i, r) in _rows.indexed) KeyedSubtree(key: r.key, child: _rowView(context, i + 1, r))
      else
        _desktopTable(context),
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

  /// الحقول التفاعلية لسطر صنفٍ واحد — بلا عنوانٍ فوقها ولا تخطيط: المصدر
  /// الوحيد لمنطق الإدخال، يستهلكه عرض الجوال (بطاقةٌ معنونة) وجدول سطح
  /// المكتب (خليةٌ عاريةٌ تحت رأسٍ مشترك) بلا تكرار سطرٍ واحد.
  ({
    bool refill,
    Widget balance,
    Widget picker,
    Widget ben,
    Widget unit,
    Widget qty,
    Widget notes,
    Widget cy,
    Widget delete,
  }) _rowFields(_Row r) {
    final it = _item(r.itemId);
    final units = it == null ? const <ItemUnit>[] : _catalog.unitsOf(it);
    final shown = it == null ? null : displayBalance(it, _whBal[it.id] ?? 0);
    final picker = ImdItemPicker(
      items: _items,
      value: r.itemId,
      detailOf: (i) => 'رصيد ${nf(_whBal[i.id] ?? 0)}',
      onChanged: (v) {
        _onItem(r, v);
        _scheduleAutosave();
      },
    );
    final balance =
        ImdEntryBalanceCell(shown == null ? '' : '${nf(shown.qty)} ${shown.unit}');
    final ben = ImdSelect<String>(
      value: r.benUnit.isEmpty && _units.isNotEmpty ? _units.first.id : r.benUnit,
      items: [for (final u in _units) (u.id, '${u.code} — ${u.name}')],
      onChanged: (v) {
        setState(() => r.benUnit = v ?? '');
        _scheduleAutosave();
      },
    );
    final unit = ImdUnitPicker(
      units: [for (final u in units) u.name],
      value: r.unit,
      onChanged: (v) {
        _scheduleAutosave();
        setState(() {
          final next = v;
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
        });
      },
    );
    // مغادرة الحقل تجمع الأصناف المكررة تلقائيًا وتعيد توزيع الوحدات.
    final qty = Focus(
      onFocusChange: (has) {
        if (!has) _autoConsolidate();
      },
      child: ImdFld(controller: r.qty, number: true, onChanged: (_) => setState(() {})),
    );
    final notes = ImdFld(controller: r.notes, hint: 'ملاحظات على هذا الصنف...');
    // **نوع العملية في صفّ الصنف لا تحته**: صندوقٌ مستقل يستقطع سطرًا لكل
    // أسطوانة، ويقطع تسلسل `Tab` من الكمية إلى السطر التالي.
    final refill = it != null && it.isRefillable;
    final cy = ImdSelect<String>(
      value: r.cy,
      items: CylAction.issueOptions,
      onChanged: (v) {
        setState(() => r.cy = v ?? r.cy);
        _scheduleAutosave();
      },
    );
    final delete = ImdIconButton(
      icon: 'x',
      kind: ImdBtnKind.danger,
      onPressed: () {
        setState(() {
          _rows.remove(r);
          r.dispose();
          if (_rows.isEmpty) _rows.add(_newRow());
        });
        _scheduleAutosave();
      },
    );
    return (
      refill: refill,
      balance: balance,
      picker: picker,
      ben: ben,
      unit: unit,
      qty: qty,
      notes: notes,
      cy: cy,
      delete: delete,
    );
  }

  /// عرض سطح المكتب: الجدول الكثيف المشترك — الأسلوب نفسه في كل السندات.
  ///
  /// «الوحدة المستفيدة» عمودٌ لا يظهر إلا في التوجيه متعدّد الوحدات، و«نوع
  /// العملية» يظهر إن كان في الجدول صنفٌ قابلٌ للتعبئة — شرطٌ على مستوى
  /// الجدول كلّه لا السطر الواحد، فلا تتبدّل الأعمدة وهي تُقرأ.
  Widget _desktopTable(BuildContext context) {
    final fields = [for (final r in _rows) _rowFields(r)];
    final multi = _type == 3;
    final anyRefill = fields.any((f) => f.refill);
    const cell = ImdEntryTable.cell;

    return ImdEntryTable(
      columns: [
        const ImdCol('الصنف', flex: 3),
        const ImdCol('الرصيد', width: 96),
        if (multi) const ImdCol('الوحدة المستفيدة', flex: 2),
        const ImdCol('الوحدة', width: 112),
        const ImdCol('الكمية', width: 88),
        if (anyRefill) const ImdCol('نوع العملية', width: 150),
        const ImdCol('ملاحظة', flex: 2),
        const ImdCol('', width: 56),
      ],
      rowKeys: [for (final r in _rows) r.key],
      rows: [
        for (final f in fields)
          [
            cell(f.picker),
            cell(f.balance),
            if (multi) cell(f.ben),
            cell(f.unit),
            cell(f.qty),
            if (anyRefill) cell(f.refill ? f.cy : const SizedBox.shrink()),
            cell(f.notes),
            cell(f.delete),
          ],
      ],
    );
  }

  Widget _rowView(BuildContext context, int index, _Row r) {
    final it = _item(r.itemId);
    final multi = _type == 3;
    // الرصيد يُعرض بوحدة العرض المختارة في بطاقة الصنف لا بالأساسية دائمًا.
    final shown = it == null
        ? null
        : displayBalance(it, _whBal[it.id] ?? 0);
    final meta = it == null
        ? ''
        : (_wh.isNotEmpty
            ? 'رصيد «$_wh»: ${nf(shown!.qty)} ${shown.unit}'
            : 'المتاح: ${nf(shown!.qty)} ${shown.unit}');
    final f = _rowFields(r);
    Widget labeled(String label, Widget field) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ImdRowLabel(label), field]);
    final picker = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ImdRowLabel('الصنف'),
      f.picker,
      ImdRowMeta(meta),
    ]);
    final ben = labeled('الوحدة المستفيدة', f.ben);
    final unit = labeled('الوحدة', f.unit);
    final qty = labeled('الكمية', f.qty);
    final del = Padding(padding: const EdgeInsets.only(top: 19), child: f.delete);
    final refill = f.refill;
    final cy = labeled('نوع العملية', f.cy);
    const gap = SizedBox(width: ImdSizes.compactGap);
    // بطاقةٌ معنونة للجوال وحده: الشاشة الضيّقة لا تتّسع لرأس جدولٍ يبقى ذا
    // معنى، وسطح المكتب يمرّ من `_desktopTable`.
    final grid = Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: picker),
        gap,
        Expanded(child: multi ? ben : unit),
      ]),
      const SizedBox(height: ImdSizes.compactGap),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (multi) ...[SizedBox(width: 104, child: unit), gap],
        SizedBox(width: 92, child: qty),
        if (refill) ...[gap, Expanded(child: cy)],
        gap,
        del,
      ]),
    ]);
    return ImdRvRow(
      index: index,
      trailing: _baseHint(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        grid,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ImdFld(controller: r.notes, hint: 'ملاحظات على هذا الصنف...'),
        ),
      ]),
    );
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
