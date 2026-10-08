part of '../issue_screen.dart';

/// سجل الصادرات: تعديل القوة والطباعة المجمّعة.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueLog on _IssueBase {
  // ───────────────────────── السجل ─────────────────────────

  /// أسطر الصرف المعتمدة ضمن نطاق المستخدم — يجلبها التقرير المجمّع بنفسه
  /// بعد أن صار السجل مكوّنًا مشتركًا لا يملك هذه الشاشة حالته.
  Future<List<Issue>> _issuedLines() async {
    final perm = Perm.of(context);
    final rows = await _moves.completedIssues();
    return rows.where((r) => perm.canWh(r.warehouse)).toList();
  }


  /// زر «تعديل القوة» داخل سجل الصادرات — قدرة لا يغطيها نموذج التعديل العام
  /// (يحافظ على القوة والأيام ولا يسمح بتغييرهما).
  Future<void> _editEntByRef(String refNo, Future<void> Function() reload) async {
    final group = await _moves.issueRowsByRef(refNo);
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
      await _moves.updateIssueStrength(group, soldiers: s, officers: o, days: dd);
      if (!mounted) return;
      showImdToast(context, '✔ تم تحديث بيانات السند والقوة بنجاح');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  /// `issPrintAggregated()` — مجموع الكميات لكل (صنف|وحدة) ضمن نتائج البحث.
  Future<void> _printAggregated() async {
    if (!Perm.of(context).guard(context, 'issue', 'print')) return;
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
