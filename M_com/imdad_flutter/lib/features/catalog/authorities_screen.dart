import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/ration_repo.dart';
import '../../domain/access_control.dart';

/// جهات الإمداد: من يطلب منهم **المخزن الرئيسي**.
///
/// المخزن الرئيسي لا يطلب من مستودعٍ آخر — يطلب من جهةٍ في تسلسل الفرقة: ركن
/// الإمداد، رئيس الشعبة، قائد الفرقة. وهذه ليست طرفًا مخزنيًّا فلا رصيد لها
/// ولا حركة عليها؛ ولذلك دليلٌ مستقل لا صفٌّ في المستودعات.
///
/// ويُدار من هنا لا من الكود: تُضاف جهةٌ أو يُغيَّر مسمّاها بلا تحديثٍ
/// للبرنامج، ويُزامَن كبقية الأدلة.
class AuthoritiesScreen extends StatefulWidget {
  const AuthoritiesScreen({super.key});

  @override
  State<AuthoritiesScreen> createState() => _AuthoritiesScreenState();
}

class _AuthoritiesScreenState extends State<AuthoritiesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final RationRepo _repo = RationRepo(_db);

  List<SupplyAuthority> _items = const [];

  /// عدد الطلبيات المعلّقة بكل جهة — بها تُعرف الجهة التي لا تُحذف.
  Map<String, int> _usage = const {};
  String? _editId;
  bool _loading = true;
  bool _active = true;

  final _name = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _render() async {
    final rows = await _repo.authorities();
    final orders = await _db.select(_db.rationOrders).get();
    final usage = <String, int>{};
    for (final o in orders) {
      if (o.authorityId.isEmpty) continue;
      usage.update(o.authorityId, (v) => v + 1, ifAbsent: () => 1);
    }
    if (!mounted) return;
    setState(() {
      _items = rows;
      _usage = usage;
      _loading = false;
    });
  }

  void _reset() {
    imdSetText(_name, '');
    imdSetText(_title, '');
    imdSetText(_notes, '');
    setState(() {
      _editId = null;
      _active = true;
    });
  }

  void _edit(SupplyAuthority a) {
    imdSetText(_name, a.name);
    imdSetText(_title, a.title);
    imdSetText(_notes, a.notes);
    setState(() {
      _editId = a.id;
      _active = a.active;
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'supplyAuthorities',
        _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    final res = await _repo.saveAuthority(
      id: _editId,
      name: _name.text,
      title: _title.text,
      notes: _notes.text,
      active: _active,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُفظت الجهة' : res.error, error: !res.ok);
    if (res.ok) {
      _reset();
      await _render();
    }
  }

  Future<void> _delete(SupplyAuthority a) async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'supplyAuthorities', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف الجهة «${a.name}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.deleteAuthority(
      a.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذفت الجهة' : res.error, error: !res.ok);
    if (res.ok) {
      if (_editId == a.id) _reset();
      await _render();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'جهات الإمداد', icon: 'users'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('supplyAuthorities');
    final active = _items.where((a) => a.active).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'جهات الإمداد',
        icon: 'users',
        subtitle: 'من يطلب منهم المخزن الرئيسي: ركن الإمداد، رئيس الشعبة، '
            'قائد الفرقة. جهاتٌ في تسلسل الفرقة لا مستودعات — فلا رصيد لها',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي الجهات', value: nf(_items.length)),
        ImdKpi(label: 'مفعَّلة', value: nf(active)),
        ImdKpi(
          label: 'معطَّلة',
          value: nf(_items.length - active),
          extra: _items.length == active
              ? null
              : const ImdChip('لا تظهر في الطلبيات', tone: ImdTone.off),
        ),
      ]),
      if (can)
        ImdPanel(
          title: _editId == null ? 'إضافة جهة' : 'تعديل جهة',
          icon: _editId == null ? 'plus-square' : 'edit',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImdF2(children: [
                ImdLabeled('اسم الجهة *', ImdFld(controller: _name), size: 11),
                ImdLabeled(
                  'المسمّى الوظيفي',
                  ImdFld(controller: _title, hint: 'ركن إمداد الفرقة'),
                  size: 11,
                ),
              ]),
              const SizedBox(height: 10),
              ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
              const SizedBox(height: 10),
              ImdCheckbox(
                value: _active,
                label: 'مفعَّلة — تظهر في قائمة الطلبيات',
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                ImdButton(
                  label: _editId == null ? 'إضافة' : 'حفظ التعديل',
                  icon: 'check',
                  onPressed: _save,
                ),
                if (_editId != null)
                  ImdButton.outline(
                      label: 'إلغاء', icon: 'x', onPressed: _reset),
              ]),
            ],
          ),
        ),
      ImdPanel(
        title: 'الجهات',
        icon: 'list',
        child: ImdTable(
          empty: 'لا جهات بعد — أضف ركن الإمداد أولًا',
          minWidth: 660,
          columns: const [
            ImdCol('الجهة'),
            ImdCol('المسمّى'),
            ImdCol('الحالة'),
            ImdCol('طلبياتها', numeric: true),
            ImdCol('ملاحظات'),
            ImdCol('إجراءات', center: true),
          ],
          rows: [
            for (final a in _items)
              [
                Text(a.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(a.title.isEmpty ? '—' : a.title),
                a.active
                    ? const ImdChip('مفعَّلة', tone: ImdTone.ok)
                    : const ImdChip('معطَّلة', tone: ImdTone.off),
                Text(nf(_usage[a.id] ?? 0)),
                Text(a.notes.isEmpty ? '—' : a.notes,
                    style: TextStyle(color: context.imd.muted)),
                Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                  if (can)
                    ImdIconButton(
                        icon: 'edit',
                        tooltip: 'تعديل',
                        onPressed: () => _edit(a)),
                  if (can && (_usage[a.id] ?? 0) == 0)
                    ImdIconButton(
                        icon: 'trash',
                        tooltip: 'حذف',
                        onPressed: () => _delete(a)),
                ]),
              ],
          ],
        ),
      ),
    ]);
  }
}
