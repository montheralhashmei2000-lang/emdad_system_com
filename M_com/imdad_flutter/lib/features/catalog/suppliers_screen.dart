import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_context_menu.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_shimmer.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';

/// الموردون — نقل مطابق لـ `renderSuppliers()`: بحث وإحصاءات، نموذج إضافة/تعديل،
/// ملاحظات تشغيلية، وجدول بالاستخدام (الوارد والمرتجع للمورد) وآخر استخدام.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _Usage {
  int count = 0, receipts = 0, returns = 0;
  String lastDate = '';
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _repo = CatalogRepo(_db);

  List<Supplier> _items = const [];
  Map<String, _Usage> _usage = const {};
  String? _editId;
  bool _loading = true;

  final _q = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    for (final c in [_q, _name, _contact, _phone, _city, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// `supLoad()` ثم `renderSuppliers()`
  Future<void> _render() async {
    final sups = await _repo.suppliers();
    final moves = MovementsRepo(_db);
    final receipts = await moves.usageOf('receipts', 'supplier');
    final returns = await moves.usageOf('returns', 'party', where: "type = 'TO_SUPPLIER'");
    sups.sort((a, b) => a.name.compareTo(b.name));
    final usage = <String, _Usage>{};
    void add(Map<String, ({int count, String lastDate})> src, String kind) {
      src.forEach((k, v) {
        final u = usage.putIfAbsent(k, _Usage.new);
        u.count += v.count;
        if (kind == 'receipts') u.receipts += v.count;
        if (kind == 'returns') u.returns += v.count;
        if (v.lastDate.isNotEmpty && (u.lastDate.isEmpty || v.lastDate.compareTo(u.lastDate) > 0)) u.lastDate = v.lastDate;
      });
    }

    add(receipts, 'receipts');
    add(returns, 'returns');
    if (!mounted) return;
    final cur = sups.where((x) => x.id == _editId).firstOrNull;
    imdSetText(_name, cur?.name ?? '');
    imdSetText(_contact, cur?.contact ?? '');
    imdSetText(_phone, cur?.phone ?? '');
    imdSetText(_city, cur?.city ?? '');
    imdSetText(_notes, cur?.notes ?? '');
    setState(() {
      _items = sups;
      _usage = usage;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'suppliers', _editId != null ? 'edit' : 'create')) return;
    final name = _name.text.trim();
    if (name.isEmpty) return showImdToast(context, '✖ أدخل اسم المورد');
    final dup = _items.any((x) => x.id != _editId && x.name.trim().toLowerCase() == name.toLowerCase());
    if (dup) return showImdToast(context, '✖ يوجد مورد بنفس الاسم بالفعل');
    final audit = AuditRepo(_db);
    final actor = context.read<AuthService>().currentUser;
    try {
      await _repo.saveSupplier(
        id: _editId,
        name: name,
        contact: _contact.text.trim(),
        phone: _phone.text.trim(),
        city: _city.text.trim(),
        notes: _notes.text.trim(),
      );
      if (_editId != null) {
        await audit.write('SUPPLIER_UPDATED', 'supplier', 'تعديل بيانات مورد',
            details: {'target': name, 'status': 'UPDATED', 'risk': 'normal'}, actor: actor);
        if (mounted) showImdToast(context, '✔ تم تحديث المورد');
      } else {
        await audit.write('SUPPLIER_CREATED', 'supplier', 'إضافة مورد جديد',
            details: {'target': name, 'status': 'CREATED', 'risk': 'normal'}, actor: actor);
        if (mounted) showImdToast(context, '🎉 تم إضافة المورد');
      }
      _editId = null;
      await _render();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  Future<void> _delete(Supplier it) async {
    if (!Perm.of(context).guard(context, 'suppliers', 'delete')) return;
    final u = _usage[it.name.trim()];
    if ((u?.count ?? 0) > 0 &&
        !await imdConfirm(context, 'هذا المورد مستخدم في سجلات سابقة (${nf(u!.count)}). هل تريد حذفه رغم ذلك؟',
            danger: true)) {
      return;
    }
    if (!mounted || !await imdConfirm(context, 'حذف المورد «${it.name}»؟', ok: 'حذف', danger: true)) return;
    if (!mounted) return;
    final actor = context.read<AuthService>().currentUser;
    try {
      await _repo.deleteSupplier(it.id);
      await AuditRepo(_db).write('SUPPLIER_DELETED', 'supplier', 'حذف مورد',
          details: {'target': it.name, 'status': 'DELETED', 'qty': u?.count ?? 0, 'risk': 'sensitive'}, actor: actor);
      if (!mounted) return;
      showImdToast(context, '✔ تم حذف المورد');
      if (_editId == it.id) _editId = null;
      await _render();
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e');
    }
  }

  void _newRecord() {
    _editId = null;
    _render();
  }

  @override
  Widget build(BuildContext context) {
    // الإضافة والتعديل والحذف بصلاحية «الموردون» نفسها (لا بالمدير وحده)، وكل إجراءٍ محروسٌ في دالته.
    final can = Perm.of(context).writable('suppliers');
    final cur = _items.where((x) => x.id == _editId).firstOrNull;
    final q = _q.text.trim().toLowerCase();
    final rows = _items
        .where((x) => q.isEmpty || [x.name, x.phone, x.city, x.contact, x.notes].any((v) => v.toLowerCase().contains(q)))
        .toList();
    final withPhone = _items.where((x) => x.phone.trim().isNotEmpty).length;
    final used = _items.where((x) => (_usage[x.name.trim()]?.count ?? 0) > 0).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الموردون',
        icon: 'truck',
        subtitle: 'إدارة بيانات الموردين المستخدمة في سندات الاستلام والمرتجعات وإعدادات التوريد',
      ),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث باسم المورد أو الهاتف أو المدينة…',
            onChanged: (_) => setState(() {}),
            actions: [
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _render),
              if (can) ImdButton.outline(label: 'مورد جديد', icon: 'plus-square', small: true, onPressed: _newRecord),
            ],
          ),
          ImdChipsRow(bottom: 0, children: [
            ImdChip('إجمالي الموردين: ${nf(_items.length)}', tone: ImdTone.ok),
            ImdChip('بأرقام هاتف: ${nf(withPhone)}', tone: ImdTone.code),
            ImdChip('موردون مستخدمون: ${nf(used)}', tone: ImdTone.pend),
            ImdChip('غير مستخدمين: ${nf(_items.length - used)}', tone: ImdTone.off),
          ]),
        ]),
      ),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: cur != null ? 'تعديل مورد: ${cur.name}' : 'إضافة مورد جديد',
          icon: cur != null ? 'edit' : 'plus-square',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled('اسم المورد *', ImdFld(controller: _name, enabled: can), size: 11),
              ImdLabeled('اسم جهة الاتصال', ImdFld(controller: _contact, enabled: can), size: 11),
              ImdLabeled('رقم الهاتف', ImdFld(controller: _phone, enabled: can), size: 11),
              ImdLabeled('المدينة / العنوان المختصر', ImdFld(controller: _city, enabled: can), size: 11),
            ]),
            const SizedBox(height: 4),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, enabled: can), size: 11),
            if (can)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ImdRbar(bottom: 0, children: [
                  ImdButton(
                    label: cur != null ? 'حفظ التعديلات' : 'إضافة المورد',
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
            'يفضل توحيد اسم المورد بنفس الصياغة المستخدمة في سندات الاستلام.',
            'أضف رقم الهاتف واسم جهة الاتصال لتسريع المتابعة وقت التوريد أو المرتجعات.',
            'حذف المورد المستخدم سابقًا قد يربك السجلات التاريخية؛ الأفضل إيقاف استخدامه فقط أو تعديل بياناته.',
          ]),
        ),
      ]),
      if (_loading)
        const ImdShimmerTable(rows: 6, columns: 5)
      else
        ImdTable(
          minWidth: 820,
          empty: 'لا موردين مطابقين — أضف أول مورد من النموذج أعلاه',
          columns: [
            const ImdCol('الاسم', flex: 2),
            const ImdCol('جهة الاتصال'),
            const ImdCol('الهاتف'),
            const ImdCol('المدينة'),
            const ImdCol('الاستخدام', flex: 2),
            const ImdCol('آخر استخدام'),
            const ImdCol('ملاحظات'),
            if (can) const ImdCol('', width: 110),
          ],
          pageSize: 50,
          maxHeight: ImdSizes.tableMaxHeight(context),
          rowMenu: !can
              ? null
              : (i) => [
                    ImdMenuItem(
                      label: 'تعديل',
                      icon: 'edit',
                      onTap: () {
                        _editId = rows[i].id;
                        _render();
                      },
                    ),
                    ImdMenuItem(label: 'حذف', icon: 'trash', danger: true, onTap: () => _delete(rows[i])),
                  ],
          // قيم الخلايا الخام: تصفية الأعمدة والتجميع (مثلًا حسب المدينة).
          values: [
            for (final x in rows)
              () {
                final u = _usage[x.name.trim()];
                String or(String v) => v.isEmpty ? '—' : v;
                return <Object?>[
                  or(x.name),
                  or(x.contact),
                  or(x.phone),
                  or(x.city),
                  (u?.count ?? 0) > 0 ? 'وارد ${nf(u!.receipts)} • مرتجع ${nf(u.returns)}' : '—',
                  or(u?.lastDate ?? ''),
                  or(x.notes),
                ];
              }(),
          ],
          rows: [
            for (final x in rows)
              () {
                final u = _usage[x.name.trim()];
                String or(String v) => v.isEmpty ? '—' : v;
                return <Widget>[
                  Text(or(x.name), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(or(x.contact)),
                  Text(or(x.phone)),
                  Text(or(x.city)),
                  Text((u?.count ?? 0) > 0 ? 'وارد ${nf(u!.receipts)} • مرتجع ${nf(u.returns)}' : '—'),
                  Text(or(u?.lastDate ?? '')),
                  Text(or(x.notes)),
                  if (can)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ImdIconButton(
                        icon: 'edit',
                        onPressed: () {
                          _editId = x.id;
                          _render();
                        },
                      ),
                      const SizedBox(width: 4),
                      ImdIconButton(icon: 'trash', kind: ImdBtnKind.danger, onPressed: () => _delete(x)),
                    ]),
                ];
              }(),
          ],
        ),
    ]);
  }
}
