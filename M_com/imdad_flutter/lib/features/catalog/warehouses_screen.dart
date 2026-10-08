import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/camp_ledger_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import 'warehouse_dashboard_view.dart';
import 'camp_link_field.dart';

/// المستودعات — نقل مطابق لـ `renderStores()`: بحث وإحصاءات، نموذج إضافة/تعديل مع حقل «يغذي معسكر»،
/// ملاحظات تشغيلية، وجدول بالاستخدام (وارد/صرف/تحويل) وآخر حركة.
class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _Usage {
  int count = 0, receipts = 0, issues = 0, transfers = 0, returns = 0, facs = 0;
  String lastDate = '';
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _repo = CatalogRepo(_db);

  List<Warehouse> _items = const [];
  List<BeneficiaryUnit> _camps = const [];
  Map<String, _Usage> _usage = const {};
  bool _feedsAll = true;
  List<String> _campIds = const [];
  String? _editId;
  bool _loading = true;

  final _q = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    for (final c in [_q, _code, _name, _manager, _location, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// `stoLoad()` ثم `renderStores()`
  Future<void> _render() async {
    final moves = MovementsRepo(_db);
    final whs = await _repo.warehouses();
    final receipts = await moves.usageOf('receipts', 'warehouse');
    final issues = await moves.usageOf('issues', 'warehouse');
    final transfers = await moves.usageOf('transfers', 'warehouse');
    final transfersIn = await moves.usageOf('transfers', 'dest_warehouse');
    final returns = await moves.usageOf('returns', 'warehouse');
    final facs = await _repo.facilities();
    final units = await _repo.units();
    whs.sort((a, b) => a.name.compareTo(b.name));
    final camps = units.where((u) => u.type == 'camp' || u.parentId.isEmpty).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    final usage = <String, _Usage>{};
    void add(String name, String kind, int n, String date) {
      final k = name.trim();
      if (k.isEmpty) return;
      final u = usage.putIfAbsent(k, _Usage.new);
      u.count += n;
      switch (kind) {
        case 'receipts':
          u.receipts += n;
        case 'issues':
          u.issues += n;
        case 'transfers':
          u.transfers += n;
        case 'returns':
          u.returns += n;
        case 'facs':
          u.facs += n;
      }
      if (date.isNotEmpty && (u.lastDate.isEmpty || date.compareTo(u.lastDate) > 0)) u.lastDate = date;
    }

    void addAll(Map<String, ({int count, String lastDate})> src, String kind) =>
        src.forEach((k, v) => add(k, kind, v.count, v.lastDate));

    addAll(receipts, 'receipts');
    addAll(issues, 'issues');
    addAll(transfers, 'transfers');
    addAll(transfersIn, 'transfers');
    addAll(returns, 'returns');
    for (final f in facs) {
      add(f.warehouse, 'facs', 1, '');
    }
    if (!mounted) return;
    final cur = whs.where((x) => x.id == _editId).firstOrNull;
    imdSetText(_code, cur?.code ?? '');
    imdSetText(_name, cur?.name ?? '');
    imdSetText(_manager, cur?.manager ?? '');
    imdSetText(_location, cur?.location ?? '');
    imdSetText(_notes, cur?.notes ?? '');
    final ids = cur == null ? <String>[] : _repo.campsOf(cur);
    setState(() {
      _items = whs;
      _camps = camps;
      _usage = usage;
      _campIds = ids;
      _feedsAll = cur == null ? true : (cur.feedsAllCamps && ids.isEmpty);
      _loading = false;
    });
  }

  /// `stoFeedsCampLabel(w)`
  String _feedsLabel(Warehouse w) {
    if (w.feedsAllCamps) return 'كل المعسكرات';
    final ids = _repo.campsOf(w);
    if (ids.isEmpty) return '—';
    final names = [for (final id in ids) _camps.where((c) => c.id == id).firstOrNull?.name].whereType<String>();
    return names.isEmpty ? '—' : names.join('، ');
  }

  /// `stoSave()`
  Future<void> _save() async {
    if (!Perm.of(context).guard(context, 'stores', _editId != null ? 'edit' : 'create')) return;
    final name = _name.text.trim(), code = _code.text.trim();
    if (name.isEmpty) return showImdToast(context, '✖ أدخل اسم المستودع');
    if (_items.any((x) => x.id != _editId && x.name.trim().toLowerCase() == name.toLowerCase())) {
      return showImdToast(context, '✖ يوجد مستودع بنفس الاسم بالفعل');
    }
    if (code.isNotEmpty && _items.any((x) => x.id != _editId && x.code.trim().toLowerCase() == code.toLowerCase())) {
      return showImdToast(context, '✖ يوجد مستودع بنفس الكود بالفعل');
    }
    // «محدد» بلا أي معسكر يُعامل كجميع المعسكرات حتى لا يختفي المستودع من الصرف والتحويل.
    final all = _feedsAll || _campIds.isEmpty;
    final audit = AuditRepo(_db);
    final actor = context.read<AuthService>().currentUser;
    try {
      await _repo.saveWarehouse(
        id: _editId,
        code: code,
        name: name,
        manager: _manager.text.trim(),
        location: _location.text.trim(),
        notes: _notes.text.trim(),
        feedsAllCamps: all,
        campIds: all ? const [] : _campIds,
      );
      if (_editId != null) {
        await audit.write('WAREHOUSE_UPDATED', 'warehouse', 'تعديل بيانات مستودع',
            details: {'target': name, 'status': 'UPDATED', 'risk': 'normal'}, actor: actor);
        if (mounted) showImdToast(context, '✔ تم تحديث المستودع');
      } else {
        await audit.write('WAREHOUSE_CREATED', 'warehouse', 'إضافة مستودع جديد',
            details: {'target': name, 'status': 'CREATED', 'risk': 'normal'}, actor: actor);
        if (mounted) showImdToast(context, '🎉 تم إضافة المستودع');
      }
      _editId = null;
      await _render();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _delete(Warehouse it) async {
    if (!Perm.of(context).guard(context, 'stores', 'delete')) return;
    final u = _usage[it.name.trim()];
    if ((u?.count ?? 0) > 0 &&
        !await imdConfirm(context, 'هذا المستودع مرتبط بحركات سابقة (${nf(u!.count)}). هل تريد حذفه رغم ذلك؟',
            danger: true)) {
      return;
    }
    if (!mounted || !await imdConfirm(context, 'حذف المستودع «${it.name}»؟', ok: 'حذف', danger: true)) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _repo.deleteWarehouse(it.id);
      await AuditRepo(_db).write('WAREHOUSE_DELETED', 'warehouse', 'حذف مستودع',
          details: {'target': it.name, 'status': 'DELETED', 'qty': u?.count ?? 0, 'risk': 'sensitive'}, actor: actor);
      if (!mounted) return;
      showImdToast(context, '✔ تم حذف المستودع');
      if (_editId == it.id) _editId = null;
      await _render();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  /// تعيين المخزن الرئيسي — منه وحده تُغذّى المعسكرات.
  Future<void> _setMain(Warehouse w) async {
    if (!Perm.of(context).guard(context, 'stores', 'edit')) return;
    final current = await CampLedgerRepo(_db).mainWarehouse();
    if (!mounted) return;
    final ok = await imdConfirm(
      context,
      current == null
          ? 'تعيين «${w.name}» مخزنًا رئيسيًا؟ تغذية المعسكرات ستكون منه وحده.'
          : 'نقل الصفة من «${current.name}» إلى «${w.name}»؟ '
              'تغذية المعسكرات ستكون من «${w.name}» وحده بعد ذلك.',
      ok: 'تعيين',
    );
    if (!ok || !mounted) return;
    await CampLedgerRepo(_db).setMainWarehouse(
      w.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, '✔ صار «${w.name}» المخزن الرئيسي');
    await _render();
  }

  void _newRecord() {
    _editId = null;
    _render();
  }

  /// dir | board
  String _tab = 'dir';

  @override
  Widget build(BuildContext context) {
    // الإضافة والتعديل والحذف بصلاحية «المستودعات» نفسها (لا بالمدير وحده)، وكل إجراءٍ محروسٌ في دالته.
    final can = Perm.of(context).writable('stores');
    // صلاحية الحذف وحدها: `writable` يصدق بالإضافة أو التعديل أو الاعتماد،
    // فكان زرُّ الحذف يظهر لمن لا يملك الحذف.
    final canDel = Perm.of(context).canDelete('stores');
    final cur = _items.where((x) => x.id == _editId).firstOrNull;
    final q = _q.text.trim().toLowerCase();
    final rows = _items
        .where((x) => q.isEmpty || [x.code, x.name, x.manager, x.notes, x.location].any((v) => v.toLowerCase().contains(q)))
        .toList();
    final used = _items.where((x) => (_usage[x.name.trim()]?.count ?? 0) > 0).length;
    final withCode = _items.where((x) => x.code.trim().isNotEmpty).length;
    final linkedF = _items.where((x) => (_usage[x.name.trim()]?.facs ?? 0) > 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'المستودعات',
        icon: 'warehouse',
        subtitle: 'تعريف المستودعات وحدود مخزونها — ما تحت الحد الأدنى وما فوق الأعلى',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('dir', 'دليل المستودعات', icon: 'warehouse'),
          ImdTab('board', 'لوحة المستودعات', icon: 'radio'),
        ],
      ),
      const SizedBox(height: 4),
      // اللوحة حيث يقع الرصيد لا في شاشةٍ أخرى تُبحث عنها: من يعرّف المستودع
      // هو من يضبط حدوده ويقرأ نقصها.
      if (_tab == 'board')
        WarehouseDashboardView(warehouses: _items)
      else ...[
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث بالكود أو الاسم أو الموقع…',
            onChanged: (_) => setState(() {}),
            actions: [
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _render),
              if (can) ImdButton.outline(label: 'مستودع جديد', icon: 'plus-square', small: true, onPressed: _newRecord),
            ],
          ),
          ImdChipsRow(bottom: 0, children: [
            ImdChip('المستودعات: ${nf(_items.length)}', tone: ImdTone.ok),
            ImdChip('بأكواد: ${nf(withCode)}', tone: ImdTone.code),
            ImdChip('نشطة بالحركات: ${nf(used)}', tone: ImdTone.pend),
            ImdChip('مرتبطة بمطابخ/أفران: ${nf(linkedF)}', tone: ImdTone.off),
          ]),
        ]),
      ),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: cur != null ? 'تعديل مستودع: ${cur.name}' : 'إضافة مستودع جديد',
          icon: cur != null ? 'edit' : 'plus-square',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled('الكود', ImdFld(controller: _code, enabled: can), size: 11),
              ImdLabeled('اسم المستودع *', ImdFld(controller: _name, enabled: can), size: 11),
              ImdLabeled('المسؤول', ImdFld(controller: _manager, enabled: can), size: 11),
              ImdLabeled('الموقع', ImdFld(controller: _location, enabled: can), size: 11),
              // forms-ux.js يُدرج الحقل بعد خانة «الموقع» داخل شبكة .f2 نفسها فيأخذ نصف العرض.
              CampLinkField(
                camps: _camps,
                all: _feedsAll,
                ids: _campIds,
                enabled: can,
                onChanged: (all, ids) => setState(() {
                  _feedsAll = all;
                  _campIds = all ? const [] : ids;
                }),
              ),
            ]),
            const SizedBox(height: 13),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, enabled: can), size: 11),
            if (can)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ImdRbar(bottom: 0, children: [
                  ImdButton(
                    label: cur != null ? 'حفظ التعديلات' : 'إضافة المستودع',
                    icon: cur != null ? 'save' : 'plus',
                    onPressed: _save,
                  ),
                  ImdButton.outline(label: 'إلغاء', onPressed: _newRecord),
                ]),
              )
            else
              const Padding(padding: EdgeInsets.only(top: 8), child: ImdLdText('👁 عرض فقط — الإدارة متاحة لمدير النظام')),
          ]),
        ),
        const ImdPanel(
          margin: EdgeInsets.zero,
          title: 'ملاحظات تشغيلية',
          icon: 'pin',
          child: ImdBullets([
            'يفضل إعطاء كل مستودع كودًا مختصرًا ثابتًا لتسهيل الطباعة والتقارير.',
            'لا تحذف مستودعًا له حركات تاريخية إلا بعد التأكد من عدم تأثير ذلك على الأرشفة.',
            'اربط المستودع بالمسؤول والموقع لتقليل أخطاء التحويل والاستلام.',
          ]),
        ),
      ]),
      if (_loading)
        const ImdLd('جارٍ التحميل…')
      else
        ImdTable(
          minWidth: 960,
          cards: true,
          empty: 'لا مستودعات مطابقة — أضف أول مستودع من النموذج أعلاه',
          columns: [
            const ImdCol('الكود'),
            const ImdCol('اسم المستودع', flex: 2),
            const ImdCol('المسؤول'),
            const ImdCol('الموقع'),
            const ImdCol('🏕️ يغذي معسكر', flex: 2),
            const ImdCol('رئيسي', center: true),
            const ImdCol('الاستخدام', flex: 2),
            const ImdCol('آخر حركة'),
            const ImdCol('ملاحظات'),
            if (can) const ImdCol('', width: 110),
          ],
          pageSize: 50,
          rows: [
            for (final x in rows)
              () {
                final u = _usage[x.name.trim()];
                String or(String v) => v.isEmpty ? '—' : v;
                return <Widget>[
                  Text(or(x.code), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(or(x.name)),
                  Text(or(x.manager)),
                  Text(or(x.location)),
                  Text(_feedsLabel(x)),
                  x.isMain
                      ? const ImdChip('المخزن الرئيسي', tone: ImdTone.ok)
                      : (can
                          ? ImdButton.outline(
                              label: 'تعيين',
                              icon: 'shield',
                              small: true,
                              onPressed: () => _setMain(x),
                            )
                          : const Text('—')),
                  Text((u?.count ?? 0) > 0
                      ? 'وارد ${nf(u!.receipts)} • صرف ${nf(u.issues)} • تحويل ${nf(u.transfers)}'
                      : '—'),
                  Text(or(u?.lastDate ?? '')),
                  Text(or(x.notes)),
                  if (can)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ImdIconButton(
                        icon: 'edit',
                        tooltip: 'تعديل',
                        onPressed: () {
                          _editId = x.id;
                          _render();
                        },
                      ),
                      if (canDel) ...[
                        const SizedBox(width: 4),
                        ImdIconButton(
                            icon: 'trash',
                            tooltip: 'حذف',
                            kind: ImdBtnKind.danger,
                            onPressed: () => _delete(x)),
                      ],
                    ]),
                ];
              }(),
          ],
        ),
      ],
    ]);
  }
}
