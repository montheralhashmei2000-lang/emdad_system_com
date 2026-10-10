part of '../issue_screen.dart';

/// تحميل النموذج والحفظ التلقائي واستعادة المسودة.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueAutosave on _IssueBase, _IssueBeneficiary {
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
    final whs = (await _catalog.warehouses())
        .where((w) => perm.canWh(w.name))
        .toList();
    final facs = await _catalog.facilities();
    final ents = {for (final e in await DailyRepo(_db).entitlements()) e.itemId: e};
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
      if (_type == 2) _strength = 0;
      _ready = true;
    });
    await _refreshBal();
    await _restoreAutosave();
  }

  @override
  void _scheduleAutosave() {
    if (!_ready || _restoringAutosave || _tab != 'form') return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveAutosave);
    if (_autosavedAt != null && mounted) setState(() => _autosavedAt = null);
  }

  Future<void> _saveAutosave() async {
    if (!_ready || _restoringAutosave || _busy || _tab != 'form') return;
    final snapshot = {..._captureDocSnapshot(), 'savedAt': DateTime.now().toIso8601String()};
    await _settingsRepo.writeIssueRecovery(_autosaveUser, snapshot);
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
              'cylinder': row.cy,
              'noAuto': row.noAuto,
            },
        ],
      };

  /// يكتب لقطةً محفوظةً (تلقائية أو من تبويبٍ معلّق) رجوعًا إلى حقول النموذج.
  void _applySnapshot(Map<String, dynamic> data) {
    setState(() {
      _type = (data['type'] as num?)?.toInt() ?? _type;
      // «وحدات متعددة» (3) حُذف من الشاشة: مسودةٌ محفوظةٌ عليه تعود إلى «وحدة مستفيدة».
      if (_type == 3) _type = 0;
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
                    noAuto: value['noAuto'] == true,
                  )..cy = '${value['cylinder'] ?? 'EXCHANGE'}',
              ]
            : <_Row>[]);
      if (_rows.isEmpty) _rows.add(_newRow());
    });
  }

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
    if (r.noAuto) return false;
    if (_custom.text.isNotEmpty || _notes.text.isNotEmpty) return false;
    if (_parent.isNotEmpty || _ben.isNotEmpty || _fac.isNotEmpty) return false;
    if (_days.text.isNotEmpty && _days.text != '1') return false;
    return true;
  }

  Future<void> _restoreAutosave() async {
    Map<String, dynamic>? data = await _settingsRepo.readIssueRecovery(_autosaveUser);
    if (data == null) {
      // ترحيل مرةٍ واحدة: مسودةٌ قديمة في SharedPreferences تُنقل إلى القاعدة
      // المشفّرة ثم تُمسح من الملف النصي.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyAutosaveKey);
      if (raw != null) {
        await prefs.remove(_legacyAutosaveKey);
        try {
          data = (jsonDecode(raw) as Map).cast<String, dynamic>();
          await _settingsRepo.writeIssueRecovery(_autosaveUser, data);
        } catch (_) {
          data = null;
        }
      }
    }
    if (data == null || !mounted) return;
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
}
