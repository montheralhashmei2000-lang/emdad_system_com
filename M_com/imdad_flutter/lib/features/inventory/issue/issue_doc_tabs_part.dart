part of '../issue_screen.dart';

/// تبويبات السندات المعلّقة داخل الجلسة.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueDocTabs on _IssueBase, _IssueBeneficiary, _IssueAutosave {
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
}
