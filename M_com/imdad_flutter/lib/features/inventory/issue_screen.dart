import 'dart:async';
import 'dart:convert';

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
import '../../core/ui/imd_screen_actions.dart';
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

part 'issue/issue_base_part.dart';
part 'issue/issue_beneficiary_part.dart';
part 'issue/issue_autosave_part.dart';
part 'issue/issue_doc_tabs_part.dart';
part 'issue/issue_rows_part.dart';
part 'issue/issue_submit_part.dart';
part 'issue/issue_rows_view_part.dart';
part 'issue/issue_form_body_part.dart';
part 'issue/issue_log_part.dart';


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

class _IssueScreenState extends State<IssueScreen>
    with
        _IssueBase,
        _IssueBeneficiary,
        _IssueAutosave,
        _IssueDocTabs,
        _IssueRows,
        _IssueSubmit,
        _IssueRowsView,
        _IssueFormBody,
        _IssueLog {
  @override
  void initState() {
    super.initState();
    for (final controller in [_custom, _days, _notes]) {
      controller.addListener(_scheduleAutosave);
    }
    _form();
    _screenActions = ImdScreenActions.maybeOf(context)
      ?..register(
        onSave: () {
          if (!_busy) _submit('DRAFT');
        },
        onPrint: () {
          if (!_busy) _print(false);
        },
        onNewDoc: _openNewTab,
        onRefresh: _refreshBal,
      );
  }

  @override
  void dispose() {
    _screenActions?.clear();
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

  @override
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
}
