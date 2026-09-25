import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/alerts_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../domain/stock_alerts.dart';

/// تنبيهات المخزون: الأصناف تحت حدها الأدنى، والدفعات القريبة من انتهاء صلاحيتها.
class StockAlertsScreen extends StatefulWidget {
  const StockAlertsScreen({super.key});

  @override
  State<StockAlertsScreen> createState() => _StockAlertsScreenState();
}

class _StockAlertsScreenState extends State<StockAlertsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final AlertsRepo _repo = AlertsRepo(_db);

  String _tab = 'low';
  int _days = 30;
  bool _loading = true;
  Map<String, Item> _items = const {};
  List<LowStockAlert> _low = const [];
  List<ExpiryAlert> _expiry = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final scope = Perm.of(context).scope;
    final items = {for (final i in await _db.select(_db.items).get()) i.id: i};
    final low = await _repo.lowStock(scope: scope);
    final expiry = await _repo.expiring(scope: scope, withinDays: _days);
    if (!mounted) return;
    setState(() {
      _items = items;
      _low = low;
      _expiry = expiry;
      _loading = false;
    });
  }

  String _qty(String itemId, double base) {
    final it = _items[itemId];
    if (it == null) return nf(base);
    final d = displayBalance(it, base);
    return '${nf(d.qty)} ${d.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expiry.where((e) => e.expired).length;
    return ImdPage(children: [
      ImdPageTitle(
        title: 'تنبيهات المخزون',
        icon: 'alert',
        subtitle: 'الأصناف التي بلغت حدها الأدنى، والدفعات التي تقترب صلاحيتها من الانتهاء وما زال منها رصيد',
        trailing: ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
      ),
      ImdChipsRow(children: [
        ImdChip('تحت الحد: ${nf(_low.length)}', tone: ImdTone.pend),
        ImdChip('نافدة: ${nf(_low.where((l) => l.outOfStock).length)}', tone: ImdTone.err),
        ImdChip('تنتهي خلال $_days يومًا: ${nf(_expiry.length - expired)}', tone: ImdTone.pend),
        ImdChip('منتهية: ${nf(expired)}', tone: ImdTone.err),
      ]),
      ImdPillTabs<String>(
        value: _tab,
        onChanged: (t) => setState(() => _tab = t),
        tabs: const [
          ImdTab('low', 'تحت الحد الأدنى', icon: 'package'),
          ImdTab('expiry', 'قرب انتهاء الصلاحية', icon: 'calendar'),
        ],
      ),
      if (_loading)
        const ImdLd('⏳ جارٍ التحميل…')
      else if (_tab == 'low')
        _lowView()
      else
        _expiryView(),
    ]);
  }

  Widget _lowView() => ImdTable(
        columns: const [
          ImdCol('الكود'),
          ImdCol('الصنف'),
          ImdCol('الرصيد', numeric: true),
          ImdCol('الحد الأدنى', numeric: true),
          ImdCol('المطلوب لبلوغ الحد', numeric: true),
          ImdCol('الحالة'),
        ],
        empty: 'لا أصناف تحت حدها الأدنى 👌 (يُضبط الحد من بطاقة الصنف)',
        rows: [
          for (final a in _low)
            [
              Text(_items[a.itemId]?.code ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(_items[a.itemId]?.name ?? a.itemId),
              Text(_qty(a.itemId, a.balance), style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(_qty(a.itemId, a.minQty)),
              Text(_qty(a.itemId, a.shortfall)),
              a.outOfStock ? const ImdChip('نافد', tone: ImdTone.err) : const ImdChip('تحت الحد', tone: ImdTone.pend),
            ],
        ],
      );

  Widget _expiryView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 220,
            child: ImdSelect<int>(
              dense: true,
              value: _days,
              items: const [(7, 'خلال أسبوع'), (30, 'خلال 30 يومًا'), (60, 'خلال 60 يومًا'), (90, 'خلال 90 يومًا')],
              onChanged: (v) {
                setState(() => _days = v ?? 30);
                _load();
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        ImdTable(
          columns: const [
            ImdCol('الصنف'),
            ImdCol('المستودع'),
            ImdCol('سند الوارد'),
            ImdCol('تاريخ الانتهاء'),
            ImdCol('الباقي التقديري', numeric: true),
            ImdCol('الحالة'),
          ],
          empty: 'لا دفعات تنتهي صلاحيتها في هذه المدة 👌 (يُسجَّل تاريخ الانتهاء في سند الاستلام)',
          rows: [
            for (final e in _expiry)
              [
                Text(_items[e.lot.itemId]?.name ?? e.lot.itemId, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(e.lot.warehouse),
                Text(e.lot.refNo.isEmpty ? '—' : e.lot.refNo),
                Text(e.lot.expiryDate),
                Text(_qty(e.lot.itemId, e.remainingQty), style: const TextStyle(fontWeight: FontWeight.w900)),
                e.expired
                    ? ImdChip('منتهية منذ ${nf(-e.daysLeft)} يوم', tone: ImdTone.err)
                    : ImdChip(e.daysLeft == 0 ? 'تنتهي اليوم' : 'بعد ${nf(e.daysLeft)} يوم',
                        tone: e.daysLeft <= 7 ? ImdTone.err : ImdTone.pend),
              ],
          ],
        ),
      ]);
}
