part of '../issue_screen.dart';

/// الرصيد والمستفيد والقوة والاستحقاق وحساب الأسطر.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueBeneficiary on _IssueBase {
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
      if (t == 2) {
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
    final rows = await _moves.completedIssuesOfUnit(unitId);
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    final due = IssueRules.nextDue([
      for (final v in rows) (date: v.date.isNotEmpty ? v.date : isoDay(v.createdAt), durationDays: v.durationDays),
    ], DateTime.now());
    if (!due.hasHistory) {
      setState(() {
        _nextDue = 'لا يوجد صرف سابق';
        _nextDueColor = context.imd.success;
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
        _nextDueColor = context.imd.warn;
      } else {
        _nextDue = '📅 $str (بعد ${due.daysLeft} يوم)';
        _nextDueColor = context.imd.success;
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
        _rows.add(_newRow(itemId: it.id, unit: uName, qty: qty, noAuto: true));
        added++;
      }
      if (_rows.isEmpty) _rows.add(_newRow());
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
}
