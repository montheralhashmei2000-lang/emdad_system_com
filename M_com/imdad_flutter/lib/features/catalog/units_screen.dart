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

/// الوحدات المستفيدة — نقل مطابق لـ `renderUnits()`: الشجرة التنظيمية (معسكرات ووحدات تابعة)
/// مع الترقيم التلقائي من `imdad-upgrade-v4.js`، وسجل الصرف الاستهلاكي للوحدة.
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _repo = CatalogRepo(_db);

  String _tab = 'tree';
  String? _editId;
  List<BeneficiaryUnit> _units = const [];
  final Map<String, bool> _open = {};
  bool _loading = true;

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _cat = TextEditingController();
  final _search = TextEditingController();
  String _parent = '';
  String _type = 'camp';

  // سجل الصرف
  String _hUnit = '';
  late String _hFrom = _dstr(DateTime.now().subtract(const Duration(days: 30)));
  late String _hTo = _dstr(DateTime.now());
  Widget? _histOut;

  static String _dstr(DateTime d) => isoDay(d);

  @override
  void initState() {
    super.initState();
    _fetch().then((_) => _initForm());
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _cat, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  /// `unFetch()` — بترتيب الإنشاء.
  Future<void> _fetch() async {
    final rows = await _db.select(_db.beneficiaryUnits).get();
    if (!mounted) return;
    setState(() {
      _units = rows;
      _loading = false;
    });
  }

  List<BeneficiaryUnit> _children(String pid) => _units.where((u) => u.parentId == pid).toList();

  /// `unDescSet(id)`
  Set<String> _desc(String id) {
    final set = <String>{};
    final q = [id];
    while (q.isNotEmpty) {
      final c = q.removeLast();
      for (final u in _units.where((u) => u.parentId == c)) {
        if (set.add(u.id)) q.add(u.id);
      }
    }
    return set;
  }

  /// `nextCode(units, parentId)` — ترقيم تلقائي: المعسكر رقم تسلسلي، والتابعة «كود الأب-تسلسل».
  String _nextCode(String parentId) {
    var max = 0;
    for (final u in _units.where((u) => u.parentId == parentId)) {
      final m = RegExp(r'(\d+)$').firstMatch(u.code);
      if (m != null) max = [max, int.parse(m.group(1)!)].reduce((a, b) => a > b ? a : b);
    }
    final p = parentId.isEmpty ? null : _units.where((u) => u.id == parentId).firstOrNull;
    return p != null ? '${p.code.isEmpty ? '1' : p.code}-${max + 1}' : '${max + 1}';
  }

  BeneficiaryUnit? get _cur => _editId == null ? null : _units.where((x) => x.id == _editId).firstOrNull;

  void _initForm() {
    final cur = _cur;
    _parent = cur?.parentId ?? '';
    imdSetText(_code, cur?.code ?? _nextCode(_parent));
    imdSetText(_name, cur?.name ?? '');
    _type = cur?.type == 'unit' ? 'unit' : 'camp';
    imdSetText(_cat, cur?.category ?? '');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الوحدات المستفيدة',
        icon: 'users',
        subtitle: 'شجرة المعسكرات والوحدات التابعة + سجل الصرف الاستهلاكي',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (t) => setState(() => _tab = t),
        tabs: const [
          ImdTab('tree', 'الشجرة التنظيمية', icon: 'tent'),
          ImdTab('hist', 'سجل الصرف', icon: 'file'),
        ],
      ),
      if (_loading)
        const ImdLd('جارٍ التحميل…')
      else if (_tab == 'tree')
        _tree(context)
      else
        _hist(context),
    ]);
  }

  // ───────── الشجرة ─────────
  Widget _tree(BuildContext context) {
    final w = Perm.of(context).writable('units');
    final c = context.imd;
    final cur = _cur;
    final skip = cur == null ? <String>{} : _desc(cur.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (w)
        ImdICard(
          title: cur != null ? 'وضع التعديل: ${cur.code} — ${cur.name}' : 'إضافة معسكر / وحدة',
          icon: cur != null ? 'edit' : 'plus-square',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled(
                'كود الوحدة *',
                Tooltip(
                  message: 'يتم توليد الكود تلقائيًا',
                  child: TextField(
                    controller: _code,
                    readOnly: true,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text),
                    decoration: imdFieldDecoration(context).copyWith(
                      fillColor: c.isDark ? c.bg : const Color(0xFFEEF1EE),
                    ),
                  ),
                ),
              ),
              ImdLabeled(
                'التسلسل التبعي',
                ImdSelect<String>(
                  value: _parent,
                  items: [
                    ('', '— بدون (معسكر رئيسي) —'),
                    for (final u in _units)
                      if (u.id != cur?.id && !skip.contains(u.id)) (u.id, '${u.code} — ${u.name}'),
                  ],
                  onChanged: (v) => setState(() {
                    _parent = v ?? '';
                    if (_editId == null) imdSetText(_code, _nextCode(_parent));
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ImdF2(children: [
              ImdLabeled('اسم المعسكر / الوحدة *', ImdFld(controller: _name)),
              ImdLabeled(
                'نوع الجهة *',
                ImdSelect<String>(
                  value: _type,
                  items: const [('camp', 'معسكر رئيسي'), ('unit', 'وحدة مستفيدة')],
                  onChanged: (v) => setState(() => _type = v ?? 'camp'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ImdF2(children: [
              ImdLabeled('الاختصاص (مثال: مشاة)', ImdFld(controller: _cat)),
              const SizedBox.shrink(),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ImdButton.outline(
                  label: 'إلغاء / مسح',
                  expand: true,
                  onPressed: () {
                    _editId = null;
                    _initForm();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ImdButton(
                  label: cur != null ? 'حفظ التعديلات' : 'إضافة وحدة',
                  icon: cur != null ? 'save' : 'plus',
                  expand: true,
                  onPressed: _save,
                ),
              ),
            ]),
          ]),
        )
      else
        const ImdICard(
          title: 'عرض فقط',
          icon: 'eye',
          child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: ImdLdText('الإضافة والتعديل متاحان لمدير النظام')),
        ),
      // .unbar
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 14, color: c.text),
              decoration: imdFieldDecoration(context, hint: 'بحث بالكود أو الاسم أو الاختصاص…'),
            ),
          ),
          const SizedBox(width: 8),
          ImdIconButton(
            icon: 'refresh',
            onPressed: () async {
              await _fetch();
              if (context.mounted) showImdToast(context, '🔄 حُدّثت الشجرة');
            },
          ),
        ]),
      ),
      // .uTree
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(ImdSizes.radius),
          boxShadow: imdShadow(c),
        ),
        child: () {
          final nodes = _build(_children(''), w);
          if (nodes.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Text('لا توجد وحدات بعد — أضف أول معسكر من النموذج أعلاه',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: nodes);
        }(),
      ),
    ]);
  }

  /// `unPaintTree(q)` — بناء تكراري مع إبقاء آباء النتائج المطابقة.
  List<Widget> _build(List<BeneficiaryUnit> list, bool w) {
    final q = _search.text.trim().toLowerCase();
    bool hit(BeneficiaryUnit u) => q.isEmpty || [u.code, u.name, u.category].any((v) => v.toLowerCase().contains(q));
    final out = <Widget>[];
    for (final u in list) {
      final kids = _children(u.id);
      final kidNodes = _build(kids, w);
      final isCamp = u.parentId.isEmpty;
      if (!hit(u) && kidNodes.isEmpty) continue;
      final open = q.isNotEmpty ? true : (_open[u.id] != false);
      out.add(_node(u, isCamp, kids.length, open, w));
      if (kids.isNotEmpty && open) {
        out.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 22, top: 4, bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kidNodes),
        ));
      }
    }
    return out;
  }

  Widget _node(BeneficiaryUnit u, bool isCamp, int kids, bool open, bool w) {
    final c = context.imd;
    final fg = isCamp ? Colors.white : c.text;
    return Container(
      margin: EdgeInsets.only(bottom: isCamp ? 4 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCamp ? (c.isDark ? const Color(0xFF303036) : c.text) : c.surface,
        border: Border.all(color: isCamp ? (c.isDark ? const Color(0xFF3F3F46) : c.text) : c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg, fontSize: isCamp ? 14 : 13.5, fontWeight: isCamp ? FontWeight.w600 : FontWeight.w400),
        child: Row(
          children: [
            if (isCamp && kids > 0)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _open[u.id] = !open),
                  child: Container(
                    width: 28,
                    height: ImdSizes.touchMin,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(8)),
                    child: ImdIcon(open ? 'chevron-down' : 'chevron-left', size: 14, color: Colors.white),
                  ),
                ),
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Row(children: [
              Text(u.code,
                  style: TextStyle(fontWeight: FontWeight.w900, color: isCamp ? const Color(0xFF5EEAD4) : fg)),
              const SizedBox(width: 8),
              Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis)),
              if (u.category.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCamp ? const Color(0x1FFFFFFF) : c.subtle,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(u.category,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isCamp ? const Color(0xFFE4E4E7) : c.text2)),
                  ),
                ),
              ],
              ]),
            ),
            if (isCamp) Text('${nf(kids)} تابعة', style: const TextStyle(fontSize: 11.5, color: Color(0xFF9DB3A6))),
            if (w) ...[
              const SizedBox(width: 8),
              ImdIconButton(
                icon: 'edit',
                onPressed: () {
                  _editId = u.id;
                  _initForm();
                },
              ),
              if (kids == 0) ...[
                const SizedBox(width: 6),
                ImdIconButton(icon: 'trash', kind: ImdBtnKind.danger, onPressed: () => _delete(u)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BeneficiaryUnit u) async {
    if (!Perm.of(context).guard(context, 'units', 'delete')) return;
    if (!await imdConfirm(context, 'حذف هذه الوحدة نهائيًا؟', ok: 'حذف', danger: true)) return;
    try {
      await (_db.delete(_db.beneficiaryUnits)..where((t) => t.id.equals(u.id))).go();
      if (_editId == u.id) _editId = null;
      if (!mounted) return;
      showImdToast(context, '✔ حُذفت الوحدة');
      await _fetch();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  /// `unSave()`
  Future<void> _save() async {
    if (!Perm.of(context).guard(context, 'units', _editId != null ? 'edit' : 'create')) return;
    final code = _code.text.trim(), name = _name.text.trim(), cat = _cat.text.trim();
    if (code.isEmpty) return showImdToast(context, '✖ أدخل كود الوحدة');
    if (name.isEmpty) return showImdToast(context, '✖ أدخل اسم الوحدة');
    final dup = _units.where((x) => x.code == code).firstOrNull;
    if (dup != null && dup.id != _editId) return showImdToast(context, '✖ الكود مستخدم لوحدة أخرى');
    final parent = _parent.isEmpty ? null : _units.where((x) => x.id == _parent).firstOrNull;
    try {
      await _repo.saveUnit(
        id: _editId,
        code: code,
        name: name,
        category: cat,
        type: _type,
        parentId: _parent,
        parentName: parent?.name ?? '',
        facilityId: _editId == null ? '' : null,
      );
      if (!mounted) return;
      showImdToast(context, _editId != null ? '✔ حُفظت التعديلات' : '🎉 أُضيفت الوحدة بنجاح');
      _editId = null;
      await _fetch();
      _initForm();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  // ───────── سجل الصرف ─────────
  Widget _hist(BuildContext context) {
    return ImdICard(
      title: 'سجل الصرف الاستهلاكي للوحدة',
      icon: 'file',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdSelect<String>(
          value: _hUnit,
          items: [('', '— اختر الوحدة —'), for (final u in _units) (u.id, '${u.code} — ${u.name}')],
          onChanged: (v) => setState(() => _hUnit = v ?? ''),
        ),
        const SizedBox(height: 10),
        ImdF2(children: [
          ImdLabeled('من تاريخ', ImdDateField(value: _hFrom, onChanged: (v) => setState(() => _hFrom = v))),
          ImdLabeled('إلى تاريخ', ImdDateField(value: _hTo, onChanged: (v) => setState(() => _hTo = v))),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(label: 'عرض السجل', icon: 'search', onPressed: _loadHist),
        ),
        const SizedBox(height: 14),
        _histOut ?? const ImdLdText('اختر الوحدة ثم اضغط «عرض السجل»'),
      ]),
    );
  }

  /// `unLoadHist()`
  Future<void> _loadHist() async {
    final u = _units.where((x) => x.id == _hUnit).firstOrNull;
    final c = context.imd;
    if (u == null) {
      setState(() => _histOut = const ImdLdText('اختر الوحدة أولًا'));
      return;
    }
    final f = _hFrom, t = _hTo;
    if (f.isNotEmpty && t.isNotEmpty && f.compareTo(t) > 0) {
      setState(() => _histOut = ImdEmojiText('✖ نطاق التاريخ غير صحيح (من بعد إلى؟)', style: TextStyle(color: c.danger)));
      return;
    }
    setState(() => _histOut = const ImdLdText('⏳ جارٍ التحميل…'));
    final iss = await _db.select(_db.issues).get();
    final items = {for (final i in await _db.select(_db.items).get()) i.id: i.name.isNotEmpty ? i.name : i.code};
    final fMs = f.isEmpty ? null : DateTime.parse('${f}T00:00:00').millisecondsSinceEpoch;
    final tMs = t.isEmpty ? null : DateTime.parse('${t}T23:59:59').millisecondsSinceEpoch;
    final rows = iss.where((r) {
      if (r.status == 'DRAFT') return false;
      if (r.unitId != u.id &&
          r.beneficiaryUnitId != u.id &&
          r.beneficiaryUnitName != u.name &&
          r.recipientDisplay != u.name) {
        return false;
      }
      final m = r.createdAt.millisecondsSinceEpoch;
      if (fMs != null && m < fMs) return false;
      if (tMs != null && m > tMs) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      if (rows.isEmpty) {
        _histOut = const ImdLdText('لا حركات صرف لهذه الوحدة في النطاق المحدد');
        return;
      }
      _histOut = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          ImdChip('الحركات: ${nf(rows.length)}', tone: ImdTone.ok),
          if (f.isNotEmpty || t.isNotEmpty)
            ImdChip('${f.isEmpty ? '…' : f} ← ${t.isEmpty ? '…' : t}', tone: ImdTone.code),
        ]),
        ImdTable(
          minWidth: 560,
          columns: const [ImdCol('التاريخ'), ImdCol('الصنف', flex: 2), ImdCol('الكمية'), ImdCol('المرجع'), ImdCol('ملاحظات', flex: 2)],
          rows: [
            for (final r in rows)
              [
                Text(arDate(r.createdAt)),
                Text(r.itemName.isNotEmpty ? r.itemName : (items[r.itemId] ?? '—'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('-${nf(r.qty)} ${r.unitName}', style: TextStyle(fontWeight: FontWeight.w900, color: c.danger)),
                Text(r.refNo.isEmpty ? '—' : r.refNo),
                Text(r.notes),
              ],
          ],
        ),
      ]);
    });
  }
}
