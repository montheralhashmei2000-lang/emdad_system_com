import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/cylinders_repo.dart';
import '../../domain/cylinders.dart';

/// تبويب «الأسطوانات» في شاشة الأصول الثابتة: موقف كل صنف قابل للتعبئة —
/// ممتلئة وفارغة وعند المورد في كل مستودع، وعُهد المطابخ والوحدات.
///
/// لا إدخال هنا: الموقف يُحسب من السندات نفسها (استلام، صرف، تحويل، مرتجع)،
/// فلا سجل ثانٍ يُحدَّث يدويًا فيختلف عن الأرصدة.
class CylindersView extends StatefulWidget {
  const CylindersView({super.key});

  @override
  State<CylindersView> createState() => _CylindersViewState();
}

class _CylindersViewState extends State<CylindersView> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CylindersRepo _repo = CylindersRepo(_db);

  List<Item> _items = const [];
  CylinderPosition? _pos;
  String _itemId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final scope = Perm.of(context).scope;
    final items = await _repo.items();
    final pos = await _repo.position(scope: scope);
    if (!mounted) return;
    setState(() {
      _items = items;
      _pos = pos;
      if (!items.any((i) => i.id == _itemId)) _itemId = items.isEmpty ? '' : items.first.id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ImdLd('⏳ جارٍ حساب موقف الأسطوانات…');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CycleGuide(onRefresh: _load),
      if (_items.isEmpty)
        const ImdEmptyBox('لا أصناف قابلة للتعبئة بعد — عرّف «أسطوانة غاز» في «إدارة الأصناف» '
            'وفعّل خيار «صنف قابل للتعبئة»، ثم سجّل شراءها من «استلام بضاعة».')
      else
        ..._position(context),
    ]);
  }

  List<Widget> _position(BuildContext context) {
    final pos = _pos!;
    final total = pos.totalFor(_itemId);
    final byWh = (pos.stock[_itemId] ?? const <String, CylStock>{}).entries.where((e) => e.value.total != 0 || e.value.inTransit != 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final holders = (pos.custody[_itemId] ?? const <String, CylCustody>{}).values.where((c) => c.count != 0).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final custody = pos.custodyTotal(_itemId);

    return [
      if (_items.length > 1)
        ImdICard(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 280,
              child: ImdLabeled(
                'الصنف',
                ImdSelect<String>(
                  items: [for (final i in _items) (i.id, i.code.isEmpty ? i.name : '${i.code} — ${i.name}')],
                  value: _itemId,
                  onChanged: (v) => setState(() => _itemId = v ?? _itemId),
                ),
                size: 11,
              ),
            ),
          ),
        ),
      ImdKpis(children: [
        ImdKpi(label: 'ممتلئة في المستودعات', value: nf(total.full)),
        ImdKpi(label: 'فارغة في المستودعات', value: nf(total.empty)),
        ImdKpi(label: 'عند المورد للتعبئة', value: nf(total.atRefill)),
        ImdKpi(label: 'عهدة لدى الجهات', value: nf(custody)),
        ImdKpi(
          label: 'الإجمالي المملوك',
          value: nf(total.total + total.inTransit + custody),
          extra: total.inTransit > 0 ? ImdChip('منها ${nf(total.inTransit)} في الطريق', tone: ImdTone.pend) : null,
        ),
      ]),
      if (total.unknown.abs() > 1e-9)
        ImdNote(
          '${nf(total.unknown)} أسطوانة حالتها غير مسجلة (رصيد افتتاحي أو تسوية جرد أو سندات قبل تتبع '
          'الحالة). تصحّحها أول عملية استلام أو صرف بحالة محددة، أو جرد يُثبت الممتلئ والفارغ.',
        ),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'في المستودعات',
          icon: 'warehouse',
          child: ImdTable(
            columns: const [
              ImdCol('المستودع'),
              ImdCol('ممتلئة', numeric: true),
              ImdCol('فارغة', numeric: true),
              ImdCol('عند المورد', numeric: true),
              ImdCol('غير مسجلة', numeric: true),
              ImdCol('الرصيد', numeric: true),
            ],
            empty: 'لا أسطوانات في مستودعات نطاقك',
            rows: [
              for (final e in byWh)
                [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (e.value.inTransit > 0)
                      Text('${nf(e.value.inTransit)} محوّلة بانتظار الاستلام',
                          style: TextStyle(fontSize: 11, color: context.imd.muted)),
                  ]),
                  Text(nf(e.value.full), style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(nf(e.value.empty)),
                  Text(e.value.atRefill == 0 ? '—' : nf(e.value.atRefill)),
                  Text(e.value.unknown == 0 ? '—' : nf(e.value.unknown)),
                  Text(nf(e.value.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
            ],
          ),
        ),
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'العهد لدى المطابخ والوحدات',
          icon: 'users',
          child: ImdTable(
            columns: const [ImdCol('الجهة'), ImdCol('النوع'), ImdCol('العدد', numeric: true)],
            empty: 'لا عهد قائمة — تُسجَّل من «صرف بضاعة» بعملية «تسليم عهدة»',
            rows: [
              for (final h in holders)
                [
                  Text(h.name.isEmpty ? '—' : h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(switch (h.kind) {
                    CylHolderKind.unit => 'وحدة مستفيدة',
                    CylHolderKind.facility => 'مطبخ / فرن',
                    CylHolderKind.other => 'جهة أخرى',
                  }),
                  h.count < 0
                      // إرجاع أكثر مما سُلِّم: عهدة سُلِّمت قبل النظام أو إرجاعٌ لغير صاحبه.
                      ? ImdChip('${nf(h.count)} — راجِع', tone: ImdTone.err)
                      : Text(nf(h.count), style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
            ],
          ),
        ),
      ]),
    ];
  }
}

/// دليل مختصر: أيّ سند لأيّ مرحلة من دورة الأسطوانة.
class _CycleGuide extends StatefulWidget {
  const _CycleGuide({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  State<_CycleGuide> createState() => _CycleGuideState();
}

class _CycleGuideState extends State<_CycleGuide> {
  bool _open = false;

  static const _steps = <(String, String, String)>[
    ('التعريف', 'إدارة الأصناف', 'صنف واحد «أسطوانة غاز» مع تفعيل «صنف قابل للتعبئة» — لا يُسجَّل أصلًا ثابتًا.'),
    ('الشراء', 'استلام بضاعة', '«شراء جديد — ممتلئة» أو «شراء جديد — فارغة»: تُضاف إلى عدد المستودع.'),
    ('إلى مستودع آخر', 'تحويل مخزني', 'اختر حالتها (ممتلئة/فارغة): تنتقل إلى المستودع المستلم عند تأكيد الاستلام.'),
    ('عهدة لمطبخ أو وحدة', 'صرف بضاعة', 'وجّه الصرف للمطبخ أو الوحدة واختر «تسليم عهدة — ممتلئة/فارغة»: تخرج من المستودع إلى عهدة الجهة.'),
    ('الاستبدال', 'صرف بضاعة', '«استبدال»: الجهة تعيد فارغة وتأخذ ممتلئة — عهدتها وعدد المستودع ثابتان.'),
    ('إلى المورد للتعبئة', 'صرف بضاعة', 'مستلم «جهة أخرى» باسم المورد و«إرسال الفارغة للمورد للتعبئة»: تبقى ملك المستودع.'),
    ('العودة من التعبئة', 'استلام بضاعة', '«عودة من التعبئة»: تعود ممتلئة إلى المستودع نفسه، دون زيادة عددها.'),
    ('إرجاع العهدة', 'المرتجعات', 'مرتجع من الوحدة مع حالة الأسطوانة: تُسقط من عهدتها وتعود للمستودع (والتالفة لا تعود للرصيد).'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return ImdICard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Row(children: [
                ImdIcon(_open ? 'chevron-down' : 'chevron-left', size: 14, color: c.accent),
                const SizedBox(width: 6),
                const Text('دورة الأسطوانة: أيّ سند لكل مرحلة', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(_open ? 'إخفاء' : 'عرض', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: widget.onRefresh),
        ]),
        if (_open) ...[
          const SizedBox(height: 10),
          for (final (i, s) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ImdChip(nf(i + 1), tone: ImdTone.code),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${s.$1} — ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '«${s.$2}»: ', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                      TextSpan(text: s.$3),
                    ]),
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
