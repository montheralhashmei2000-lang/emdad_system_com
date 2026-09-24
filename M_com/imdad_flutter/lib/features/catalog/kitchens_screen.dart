import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';

/// المطابخ والأفران — نقل مطابق لـ `renderKitchens()` بتبويباتها الثلاث:
/// القائمة، بطاقة مطبخ/فرن، اشتراكات الوحدات.
class KitchensScreen extends StatefulWidget {
  const KitchensScreen({super.key});

  @override
  State<KitchensScreen> createState() => _KitchensScreenState();
}

class _KitchensScreenState extends State<KitchensScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _repo = CatalogRepo(_db);

  String _tab = 'list';
  String? _editId;
  List<Facility> _facs = const [];
  List<Warehouse> _whs = const [];
  List<BeneficiaryUnit> _units = const [];
  bool _loading = true;
  String _subFid = '';

  final _name = TextEditingController();
  final _cap = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'KITCHEN';
  String _wh = '';

  /// حالة مربعات الاشتراك قبل الحفظ.
  final Map<String, bool> _subChecks = {};

  @override
  void initState() {
    super.initState();
    _fetch().then((_) => _switch(_tab));
  }

  @override
  void dispose() {
    for (final c in [_name, _cap, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// `kitFetchAll()`
  Future<void> _fetch() async {
    final facs = await _repo.facilities();
    final whs = await _db.select(_db.warehouses).get()
      ..sort((a, b) => a.name.compareTo(b.name));
    final units = await _repo.units();
    if (!mounted) return;
    setState(() {
      _facs = facs;
      _whs = whs;
      _units = units;
      _loading = false;
    });
  }

  void _switch(String t) {
    setState(() => _tab = t);
    if (t == 'form') _initForm();
    if (t == 'subs') _resetChecks();
  }

  int _subCount(String fid) => _units.where((u) => facilityIdsOf(u).contains(fid)).length;

  static bool _isKitchen(Facility f) => f.fType.toUpperCase() == 'KITCHEN';

  @override
  Widget build(BuildContext context) {
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'المطابخ والأفران',
        icon: 'utensils',
        subtitle: 'تعريف مطابخ الإعاشة والأفران، طاقتها الاستيعابية، والمستودع المغذي لها + ربط الوحدات المشتركة',
      ),
      ImdItabs(
        value: _tab,
        onChanged: _switch,
        tabs: const [
          ImdTab('list', 'القائمة', icon: 'clipboard'),
          ImdTab('form', 'بطاقة مطبخ/فرن', icon: 'utensils'),
          ImdTab('subs', 'اشتراكات الوحدات', icon: 'link'),
        ],
      ),
      if (_loading)
        const ImdLd('جارٍ التحميل…')
      else
        switch (_tab) {
          'list' => _list(context),
          'form' => _form(context),
          _ => _subs(context),
        },
    ]);
  }

  // ───────── القائمة ─────────
  Widget _list(BuildContext context) {
    final w = Perm.of(context).writable('kitchens');
    if (_facs.isEmpty) {
      return const ImdICard(child: ImdLdText('لا مطابخ/أفران مسجلة بعد — أضف أول واحد من تبويب «بطاقة مطبخ/فرن»'));
    }
    return ImdTable(
      minWidth: 720,
      columns: [
        const ImdCol('الاسم', flex: 2),
        const ImdCol('النوع'),
        const ImdCol('الطاقة الاستيعابية'),
        const ImdCol('المستودع المغذي', flex: 2),
        const ImdCol('وحدات مشتركة'),
        if (w) const ImdCol('إجراءات', width: 110),
      ],
      rows: [
        for (final f in _facs)
          [
            Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ImdEmojiText(_isKitchen(f) ? '🍽️ مطبخ' : '🔥 فرن'),
            Text(f.capacity != 0 ? '${nf(f.capacity)} فرد' : '—'),
            Text(f.warehouse.isEmpty ? '—' : f.warehouse),
            ImdChip('${nf(_subCount(f.id))} وحدة', tone: ImdTone.ok),
            if (w)
              Row(mainAxisSize: MainAxisSize.min, children: [
                ImdIconButton(
                  icon: 'edit',
                  onPressed: () {
                    _editId = f.id;
                    _switch('form');
                  },
                ),
                const SizedBox(width: 4),
                ImdIconButton(
                  icon: 'trash',
                  kind: ImdBtnKind.danger,
                  onPressed: () async {
                    if (!await imdConfirm(context, 'حذف هذا المطبخ/الفرن نهائيًا؟', ok: 'حذف', danger: true)) return;
                    await (_db.delete(_db.facilities)..where((t) => t.id.equals(f.id))).go();
                    if (!context.mounted) return;
                    showImdToast(context, '✔ تم الحذف');
                    await _fetch();
                  },
                ),
              ]),
          ],
      ],
    );
  }

  // ───────── البطاقة ─────────
  Facility? get _cur => _editId == null ? null : _facs.where((x) => x.id == _editId).firstOrNull;

  void _initForm() {
    final cur = _cur;
    imdSetText(_name, cur?.name ?? '');
    _type = cur == null || _isKitchen(cur) ? 'KITCHEN' : 'OVEN';
    imdSetText(_cap, cur != null && cur.capacity != 0 ? '${cur.capacity}' : '');
    _wh = cur?.warehouse ?? '';
    imdSetText(_notes, cur?.notes ?? '');
  }

  Widget _form(BuildContext context) {
    if (!Perm.of(context).writable('kitchens')) {
      return const ImdICard(
        title: 'عرض فقط',
        icon: 'eye',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: ImdLdText('الإضافة والتعديل متاحان لمدير النظام'),
        ),
      );
    }
    final cur = _cur;
    return ImdICard(
      title: cur != null ? 'وضع التعديل: ${cur.name}' : 'إضافة مطبخ / فرن جديد',
      icon: cur != null ? 'edit' : 'plus-square',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdF2(children: [
          ImdLabeled('الاسم *', ImdFld(controller: _name)),
          ImdLabeled(
            'النوع',
            ImdSelect<String>(
              value: _type,
              items: const [('KITCHEN', 'مطبخ'), ('OVEN', 'فرن')], // ui-icons.js يحذف الرموز من <option>
              onChanged: (v) => setState(() => _type = v ?? 'KITCHEN'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ImdF2(children: [
          ImdLabeled('الطاقة الاستيعابية (أفراد)', ImdFld(controller: _cap, number: true)),
          ImdLabeled(
            'المستودع المغذي',
            ImdSelect<String>(
              value: _wh,
              items: [('', '— بدون تحديد —'), for (final w in _whs) (w.name, w.name)],
              onChanged: (v) => setState(() => _wh = v ?? ''),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: ImdButton.outline(
              label: 'إلغاء / مسح',
              expand: true,
              onPressed: () => setState(() {
                _editId = null;
                _initForm();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ImdButton(
              label: cur != null ? 'حفظ التعديلات' : 'حفظ البطاقة',
              icon: 'save',
              expand: true,
              onPressed: _save,
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return showImdToast(context, '✖ أدخل اسم المطبخ/الفرن');
    final cur = _cur;
    try {
      await _repo.saveFacility(
        id: cur?.id,
        name: name,
        fType: _type,
        capacity: int.tryParse(_cap.text.trim()) ?? (double.tryParse(_cap.text.trim())?.toInt() ?? 0),
        warehouse: _wh,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      showImdToast(context, cur != null ? '✔ حُفظت التعديلات' : '🎉 أُضيف بنجاح');
      _editId = null;
      await _fetch();
      _switch('list');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  // ───────── الاشتراكات ─────────
  void _resetChecks() {
    _subChecks
      ..clear()
      ..addAll({
        for (final u in _units)
          u.id: _subFid.isNotEmpty && facilityIdsOf(u).contains(_subFid),
      });
  }

  Widget _subs(BuildContext context) {
    final w = Perm.of(context).writable('kitchens');
    final c = context.imd;
    if (_facs.isEmpty) return const ImdICard(child: ImdLdText('أضف مطبخًا أو فرنًا أولًا'));
    Widget list;
    if (_subFid.isEmpty) {
      list = const ImdLdText('اختر المطبخ/الفرن');
    } else if (_units.isEmpty) {
      list = const ImdLdText('لا وحدات مسجلة بعد');
    } else {
      list = ImdTable(
        columns: const [ImdCol('اشتراك', width: 70), ImdCol('الكود'), ImdCol('الوحدة', flex: 2), ImdCol('مشترك حاليًا مع', flex: 2)],
        rows: [
          for (final u in _units)
            () {
              // الوحدة قد تشترك في مطبخ وفرن معًا، فتُعرض بقية اشتراكاتها كلها.
              final others = facilityIdsOf(u).where((id) => id != _subFid).toList();
              final linkedName = others.isEmpty
                  ? null
                  : others
                      .map((id) => _facs.where((f) => f.id == id).firstOrNull?.name ?? '')
                      .where((n) => n.isNotEmpty)
                      .join('، ');
              return <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _subChecks[u.id] ?? false,
                    activeColor: c.accent,
                    onChanged: w ? (v) => setState(() => _subChecks[u.id] = v ?? false) : null,
                  ),
                ),
                Text(u.code),
                Text(u.name),
                // لم تعد تحذيرًا: الاشتراك المتعدد صار مسموحًا (مطبخ وفرن معًا).
                linkedName == null ? const Text('—') : ImdChip(linkedName, tone: ImdTone.info),
              ];
            }(),
        ],
      );
    }
    return ImdICard(
      title: 'ربط الوحدات المشتركة بالمطبخ/الفرن',
      icon: 'link',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('اختر المطبخ/الفرن ثم حدد الوحدات التي تُدمج قوتها التموينية تلقائيًا معه',
              style: TextStyle(fontSize: 12, color: c.muted)),
        ),
        ImdSelect<String>(
          value: _subFid,
          items: [('', '— اختر المطبخ/الفرن —'), for (final f in _facs) (f.id, f.name)],
          onChanged: (v) => setState(() {
            _subFid = v ?? '';
            _resetChecks();
          }),
        ),
        const SizedBox(height: 14),
        list,
        if (w)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(label: 'حفظ الاشتراكات', icon: 'save', onPressed: _saveSubs),
            ),
          ),
      ]),
    );
  }

  /// `kitSaveSubs()`
  Future<void> _saveSubs() async {
    if (!Perm.of(context).guard(context, 'kitchens', 'edit')) return;
    if (_subFid.isEmpty) return showImdToast(context, '✖ اختر المطبخ/الفرن أولًا');
    var n = 0;
    await _db.transaction(() async {
      for (final u in _units) {
        final checked = _subChecks[u.id] ?? false;
        final current = facilityIdsOf(u);
        final was = current.contains(_subFid);
        if (checked == was) continue;

        // هذا الاشتراك وحده يُضاف أو يُزال؛ بقية اشتراكات الوحدة لا تُمس.
        final next = checked
            ? [...current, _subFid]
            : current.where((id) => id != _subFid).toList();
        await (_db.update(_db.beneficiaryUnits)..where((t) => t.id.equals(u.id))).write(
          BeneficiaryUnitsCompanion(
            facilityIds: Value(jsonEncode(next)),
            // العمود المفرد يبقى متوافقًا مع التصدير القديم: أول اشتراك.
            facilityId: Value(next.isEmpty ? '' : next.first),
          ),
        );
        n++;
      }
    });
    if (!mounted) return;
    if (n == 0) return showImdToast(context, 'لا تغييرات لحفظها');
    showImdToast(context, '✔ حُفظت الاشتراكات ($n تغيير)');
    await _fetch();
    _resetChecks();
  }
}
