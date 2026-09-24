import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/camp_ledger_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/stock_alert.dart';

/// لوحة المعسكرات: ما يوشك أن ينفد قبل أن ينفد.
///
/// التنبيه بأيام الكفاية لا بالكمية وحدها: «٢٠ كجم» لا تقول شيئًا، و«يكفي
/// يومًا واحدًا» تقول كل شيء — ومنها يُقرَّر التحويل من المخزن الرئيسي.
class CampDashboardScreen extends StatefulWidget {
  const CampDashboardScreen({super.key});

  @override
  State<CampDashboardScreen> createState() => _CampDashboardScreenState();
}

class _CampDashboardScreenState extends State<CampDashboardScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CampLedgerRepo _repo = CampLedgerRepo(_db);

  List<BeneficiaryUnit> _camps = const [];
  List<Item> _items = const [];
  List<StockAlert> _alerts = const [];
  List<CampStockLimit> _limits = const [];
  Warehouse? _main;

  String _campFilter = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final camps = await CatalogRepo(_db).camps();
    final items = await CatalogRepo(_db).items();
    final alerts = await _repo.alerts(campId: _campFilter);
    final limits = await _repo.limits(campId: _campFilter);
    final main = await _repo.mainWarehouse();
    if (!mounted) return;
    setState(() {
      _camps = camps;
      _items = items;
      _alerts = alerts;
      _limits = limits;
      _main = main;
      _loading = false;
      _busy = false;
    });
  }

  Future<void> _editLimit({CampStockLimit? existing}) async {
    if (!Perm.of(context).guard(context, 'campDashboard', PermAction.edit)) return;
    var campId = existing?.campId ?? (_campFilter.isNotEmpty ? _campFilter : '');
    var itemId = existing?.itemId ?? '';
    final minCtrl = TextEditingController(text: existing == null ? '' : '${existing.minStock}');
    final maxCtrl = TextEditingController(text: existing == null ? '' : '${existing.maxStock}');
    var days = existing?.alertDaysBefore ?? 2;

    final ok = await showImdModal<bool>(
      context,
      title: existing == null ? 'إضافة حدّ مخزون' : 'تعديل الحدّ',
      icon: 'alert',
      maxWidth: 460,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
          ImdLabeled(
            'المعسكر',
            ImdSelect<String>(
              hint: 'اختر المعسكر',
              items: [for (final c in _camps) (c.id, c.name)],
              value: campId.isEmpty ? null : campId,
              onChanged: existing != null ? null : (v) => setS(() => campId = v ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          ImdLabeled(
            'الصنف',
            ImdSelect<String>(
              hint: 'اختر الصنف',
              items: [for (final i in _items) (i.id, '${i.code} · ${i.name}')],
              value: itemId.isEmpty ? null : itemId,
              onChanged: existing != null ? null : (v) => setS(() => itemId = v ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          ImdF2(children: [
            ImdLabeled('الحد الأدنى', ImdFld(controller: minCtrl, number: true), size: 11),
            ImdLabeled('الحد الأعلى', ImdFld(controller: maxCtrl, number: true), size: 11),
          ]),
          const SizedBox(height: 10),
          ImdLabeled(
            'ينبَّه قبل بلوغ الحد الأدنى بـ',
            ImdSelect<int>(
              items: [for (var d = 1; d <= 7; d++) (d, '${arDigits('$d')} يوم')],
              value: days,
              onChanged: (v) => setS(() => days = v ?? 2),
            ),
          ),
          const SizedBox(height: 10),
          const ImdNote('الحد الأعلى يحدّد الكمية المقترحة للتحويل: تُملأ إليه '
              'ولا تتجاوزه، فلا يتكدّس في المعسكر ما يفسد قبل أن يُطبخ.'),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'حفظ', icon: 'check', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
    final minV = double.tryParse(minCtrl.text.trim()) ?? 0;
    final maxV = double.tryParse(maxCtrl.text.trim()) ?? 0;
    minCtrl.dispose();
    maxCtrl.dispose();
    if (ok != true || !mounted) return;
    if (campId.isEmpty || itemId.isEmpty) {
      showImdToast(context, '✖ اختر المعسكر والصنف', error: true);
      return;
    }
    if (maxV > 0 && maxV < minV) {
      showImdToast(context, '✖ الحد الأعلى دون الأدنى', error: true);
      return;
    }
    final camp = _camps.where((c) => c.id == campId).firstOrNull;
    final item = _items.where((i) => i.id == itemId).firstOrNull;
    await _repo.saveLimit(
      campId: campId,
      campName: camp?.name ?? '',
      itemId: itemId,
      itemName: item?.name ?? '',
      minStock: minV,
      maxStock: maxV,
      alertDaysBefore: days,
    );
    if (!mounted) return;
    showImdToast(context, '✔ حُفظ الحدّ');
    await _load();
  }

  Future<void> _deleteLimit(CampStockLimit l) async {
    if (!Perm.of(context).guard(context, 'campDashboard', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف حدّ «${l.itemName}» في ${l.campName}؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    await _repo.deleteLimit(l.id);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'لوحة المعسكرات', icon: 'radio'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('campDashboard');
    final critical = _alerts.where((a) => a.level == AlertLevel.critical).length;
    final urgent = _alerts.where((a) => a.level == AlertLevel.high).length;
    final active = _alerts.where((a) => a.shouldAlert).toList();

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'لوحة المعسكرات',
        icon: 'radio',
        subtitle: 'ما يوشك أن ينفد في مخازن المعسكرات — بأيام الكفاية لا بالكمية وحدها',
      ),
      if (_main == null)
        const ImdNote('لم يُعيَّن **المخزن الرئيسي** بعد. عيّنه من «المستودعات» ليُفرض '
            'قيد تغذية المعسكرات منه وحده.')
      else
        ImdNote('المخزن الرئيسي: **${_main!.name}** — منه تُغذّى المعسكرات.'),
      ImdKpis(children: [
        ImdKpi(label: 'المعسكرات', value: nf(_camps.length)),
        ImdKpi(label: 'حدود معرَّفة', value: nf(_limits.length)),
        ImdKpi(
          label: 'تنبيهات قائمة',
          value: nf(active.length),
          extra: active.isEmpty ? null : const ImdChip('تحتاج إجراء', tone: ImdTone.pend),
        ),
        ImdKpi(
          label: 'حرجة',
          value: nf(critical),
          extra: critical == 0 ? null : const ImdChip('بلغت الحد', tone: ImdTone.err),
        ),
        ImdKpi(label: 'عاجلة (يوم أو أقل)', value: nf(urgent)),
      ]),
      ImdICard(
        child: ImdF2(children: [
          ImdLabeled(
            'تصفية بالمعسكر',
            ImdSelect<String>(
              items: [('', 'كل المعسكرات'), for (final c in _camps) (c.id, c.name)],
              value: _campFilter,
              onChanged: (v) {
                setState(() => _campFilter = v ?? '');
                _load();
              },
            ),
            size: 11,
          ),
          ImdLabeled(
            ' ',
            Wrap(spacing: 10, children: [
              ImdButton.outline(
                  label: 'تحديث', icon: 'refresh', small: true, busy: _busy, onPressed: _load),
              if (can)
                ImdButton.outline(
                  label: 'حدّ جديد',
                  icon: 'plus-square',
                  small: true,
                  onPressed: () => _editLimit(),
                ),
            ]),
            size: 11,
          ),
        ]),
      ),
      ImdPanel(title: 'حالة المعسكرات', icon: 'radio', child: _campCards()),
      ImdPanel(
        title: 'تفصيل التنبيهات',
        icon: 'alert',
        child: active.isEmpty
            ? ImdEmptyBox(_limits.isEmpty
                ? 'لم تُعرَّف حدود مخزون بعد — أضف حدًّا ليبدأ التنبيه'
                : 'كل الأصناف ضمن المستوى الآمن')
            : _alertsTable(active),
      ),
      if (_limits.isNotEmpty)
        ImdPanel(title: 'حدود المخزون المعرَّفة', icon: 'settings', child: _limitsTable(can)),
    ]);
  }

  /// بطاقة لكل معسكر: حالته العامة وعدد ما ينقصه.
  Widget _campCards() {
    final shown = _campFilter.isEmpty
        ? _camps
        : _camps.where((c) => c.id == _campFilter).toList();
    if (shown.isEmpty) return const ImdEmptyBox('لا معسكرات معرَّفة');
    return ImdAutoGrid(
      minItem: 240,
      children: [
        for (final camp in shown)
          () {
            final own = _alerts.where((a) => a.campId == camp.id).toList();
            final defined = _limits.where((l) => l.campId == camp.id).length;
            final st = StockAlertEngine.statusOf(own);
            final tone = _tone(st.level);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.imd.surface,
                border: Border.all(color: context.imd.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(camp.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  ImdChip(defined == 0 ? 'بلا حدود' : st.label,
                      tone: defined == 0 ? ImdTone.off : tone),
                ]),
                const SizedBox(height: 8),
                Text(
                  defined == 0
                      ? 'لم تُعرَّف حدود مخزون لهذا المعسكر'
                      : st.itemsNeeding == 0
                          ? 'كل الأصناف ضمن المستوى الآمن (${nf(defined)} صنفًا مراقَبًا)'
                          : '${nf(st.itemsNeeding)} صنفًا يحتاج تعزيزًا من '
                              '${nf(defined)} مراقَب',
                  style: TextStyle(fontSize: 12.5, height: 1.7, color: context.imd.muted),
                ),
                if (st.suggestedTotal > 0) ...[
                  const SizedBox(height: 6),
                  Text('المقترح تحويله: ${nf(st.suggestedTotal)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.imd.text2)),
                ],
              ]),
            );
          }(),
      ],
    );
  }

  Widget _alertsTable(List<StockAlert> alerts) => ImdTable(
        empty: 'لا تنبيهات',
        minWidth: 820,
        columns: const [
          ImdCol('المعسكر'),
          ImdCol('الصنف'),
          ImdCol('المخزون', numeric: true),
          ImdCol('الحد الأدنى', numeric: true),
          ImdCol('الاستهلاك اليومي', numeric: true),
          ImdCol('يكفي'),
          ImdCol('المستوى'),
          ImdCol('المقترح تحويله', numeric: true),
        ],
        rows: [
          for (final a in alerts)
            [
              Text(a.campName),
              Text(a.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${nf(a.current)} ${a.unitName}'),
              Text(nf(a.minStock)),
              Text(a.dailyConsumption == 0 ? '—' : nf(a.dailyConsumption)),
              a.daysLeft == null
                  ? Text('لا استهلاك مسجّل',
                      style: TextStyle(fontSize: 12, color: context.imd.faint))
                  : Text('${nf(a.daysLeft)} يوم'),
              ImdChip(a.level.label, tone: _tone(a.level)),
              Text(
                a.suggestedTransfer == 0 ? '—' : nf(a.suggestedTransfer),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
        ],
      );

  Widget _limitsTable(bool can) => ImdTable(
        empty: 'لا حدود',
        minWidth: 640,
        columns: const [
          ImdCol('المعسكر'),
          ImdCol('الصنف'),
          ImdCol('الأدنى', numeric: true),
          ImdCol('الأعلى', numeric: true),
          ImdCol('التنبيه قبل'),
          ImdCol('', center: true),
        ],
        rows: [
          for (final l in _limits)
            [
              Text(l.campName),
              Text(l.itemName),
              Text(nf(l.minStock)),
              Text(nf(l.maxStock)),
              Text('${arDigits('${l.alertDaysBefore}')} يوم'),
              Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                ImdIconButton(
                  icon: 'edit',
                  tooltip: 'تعديل',
                  onPressed: can ? () => _editLimit(existing: l) : null,
                ),
                ImdIconButton(
                  icon: 'trash',
                  tooltip: 'حذف',
                  onPressed: can ? () => _deleteLimit(l) : null,
                ),
              ]),
            ],
        ],
      );

  static ImdTone _tone(AlertLevel level) => switch (level) {
        AlertLevel.critical => ImdTone.err,
        AlertLevel.high => ImdTone.err,
        AlertLevel.medium => ImdTone.pend,
        AlertLevel.low => ImdTone.info,
        AlertLevel.ok => ImdTone.ok,
      };
}
