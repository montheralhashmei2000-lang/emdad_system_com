part of '../imd_table.dart';

/// طبقة القيم: نصّ الخلية، والتصفية، والتجميع، وإبلاغ شريط الحالة بالعدد.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableData on _ImdTableBase {
  /// نصّ قيمة الخلية — أساس التصفية والتجميع. الفارغ يُعرض «(فارغ)».
  String _text(int row, int col) {
    final v = widget.values![row];
    final x = col < v.length ? v[col] : null;
    return x?.toString().trim() ?? '';
  }

  static const String _blank = '(فارغ)';
  String _shown(String t) => t.isEmpty ? _blank : t;

  /// الصفوف المطابقة لكل المرشِّحات، بترتيبها الأصلي.
  List<int> _visibleRows() {
    final n = widget.rows.length;
    if (!_tools || (_filters.isEmpty && _findQ.isEmpty)) return List<int>.generate(n, (i) => i);
    final q = _findQ.toLowerCase();
    final colCount = widget.columns.length;
    bool found(int i) {
      if (q.isEmpty) return true;
      for (var j = 0; j < colCount; j++) {
        if (_text(i, j).toLowerCase().contains(q)) return true;
      }
      return false;
    }

    return [
      for (var i = 0; i < n; i++)
        if (found(i) && _filters.entries.every((f) => f.value.contains(_text(i, f.key)))) i,
    ];
  }

  /// قيم عمودٍ المميّزة مرتَّبة (رقميًّا إن كانت كلها أرقامًا).
  List<String> _distinct(int col) {
    final list = <String>{for (var i = 0; i < widget.rows.length; i++) _text(i, col)}.toList();
    final nums = {for (final t in list) t: num.tryParse(t)};
    if (list.isNotEmpty && list.every((t) => t.isEmpty || nums[t] != null)) {
      list.sort((a, b) => (nums[a] ?? double.negativeInfinity).compareTo(nums[b] ?? double.negativeInfinity));
    } else {
      list.sort();
    }
    return list;
  }

  Future<void> _editFilter(int col) async {
    final all = _distinct(col);
    final r = await showImdModal<Set<String>>(
      context,
      title: 'تصفية: ${widget.columns[col].label}',
      icon: 'sliders',
      maxWidth: 380,
      builder: (ctx) => ImdColumnFilterBody(values: all, selected: _filters[col], shown: _shown),
    );
    if (r == null || !mounted) return;
    setState(() {
      _page = 0;
      // اختيار كل القيم = لا تصفية (ولا يُحتفظ بمجموعةٍ تتقادم مع البيانات).
      if (r.length == all.length) {
        _filters.remove(col);
      } else {
        _filters[col] = r;
      }
    });
  }

  void _clearFilters() => setState(() {
        _filters.clear();
        _page = 0;
      });

  /// بنود العرض: صفوفٌ (فهرسها المطلق) أو رؤوس مجموعات.
  List<_TableItem> _items(List<int> visible) {
    final g = _groupBy;
    if (!_tools || g == null) return [for (final i in visible) _TableItem.row(i)];
    final groups = <String, List<int>>{};
    for (final i in visible) {
      groups.putIfAbsent(_text(i, g), () => []).add(i);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys) ...[
        _TableItem.group(k, groups[k]!.length, _collapsed.contains(k)),
        if (!_collapsed.contains(k)) for (final i in groups[k]!) _TableItem.row(i),
      ],
    ];
  }

  void _toggleGroup(String key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
        _page = 0;
      });

  /// يُبلّغ شريط الحالة بعدد الصفوف — بعد الإطار لا أثناءه (الإبلاغ يُعيد بناء الشريط).
  void _report(int shown) {
    final sink = _sink;
    if (sink == null) return;
    final total = widget.rows.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sink.report(this, shown: shown, total: total);
    });
  }
}
