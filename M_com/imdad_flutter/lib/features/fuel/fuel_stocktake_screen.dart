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
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';
import '../inventory/doc_kit.dart';
import 'fuel_print.dart';

/// جرد المحروقات: أمرٌ يمرّ بأربع مراحل قبل أن يمسّ الرصيد.
///
/// **الرصيد لا يتأثر إلا بالترحيل.** جردٌ في مرحلة العدّ يحمل أرقامًا لم
/// تُراجَع بعد، ولو أثّرت في الرصيد لصار كل خزّانٍ لم يُفتح عجزًا مثبتًا،
/// ولَما بقي للمراجعة معنى.
class FuelStocktakeScreen extends StatefulWidget {
  const FuelStocktakeScreen({super.key});

  @override
  State<FuelStocktakeScreen> createState() => _FuelStocktakeScreenState();
}

class _FuelStocktakeScreenState extends State<FuelStocktakeScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelStocktake> _takes = const [];
  List<FuelStocktakeLine> _lines = const [];
  String _openId = '';

  final _committee = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _counts = {};

  String _warehouse = '';
  String _kind = 'full';
  String _fuelFilter = 'all';
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _committee.dispose();
    _notes.dispose();
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final warehouses = await _repo.warehouses(onlyActive: true);
    final takes = await _repo.stocktakes();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _takes = takes;
      if (_warehouse.isEmpty && warehouses.isNotEmpty) {
        _warehouse = warehouses.first.name;
      }
      _loading = false;
    });
    if (_openId.isNotEmpty) await _openLines(_openId);
  }

  Future<void> _openLines(String id) async {
    final lines = await _repo.stocktakeLines(id);
    if (!mounted) return;
    for (final c in _counts.values) {
      c.dispose();
    }
    _counts.clear();
    for (final l in lines) {
      _counts[l.id] = TextEditingController(
          text: l.counted ? _num(l.countedLiters) : '');
    }
    setState(() {
      _openId = id;
      _lines = lines;
    });
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _open() async {
    if (!Perm.of(context).guard(context, 'fuelStocktake', PermAction.create)) {
      return;
    }
    setState(() => _busy = true);
    final res = await _repo.openStocktake(
      date: _date,
      warehouse: _warehouse,
      kind: _kind,
      fuelFilter: _fuelFilter,
      committee: _committee.text.trim(),
      notes: _notes.text.trim(),
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ فُتح الجرد ${res.refNo}' : res.error,
        error: !res.ok);
    if (res.ok) {
      imdSetText(_committee, '');
      imdSetText(_notes, '');
      await _load();
      final latest = (await _repo.stocktakes()).firstOrNull;
      if (latest != null) await _openLines(latest.id);
    }
  }

  Future<void> _saveCounts() async {
    if (!Perm.of(context).guard(context, 'fuelStocktake', PermAction.edit)) {
      return;
    }
    setState(() => _busy = true);
    for (final l in _lines) {
      final text = _counts[l.id]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      await _repo.countLine(
          lineId: l.id, counted: double.tryParse(text) ?? 0);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, '✔ حُفظ العدّ');
    await _openLines(_openId);
  }

  Future<void> _advance(FuelStocktake take) async {
    if (!Perm.of(context).guard(context, 'fuelStocktake', PermAction.approve)) {
      return;
    }
    final next = FuelStocktakeStatus.next(take.status);
    if (next == FuelStocktakeStatus.posted) {
      final ok = await imdConfirm(
        context,
        'ترحيل الجرد ${take.refNo}؟\n'
        'الفروقات ستدخل رصيد المستودع، ولا يُعدَّل بعد الترحيل.',
        ok: 'ترحيل',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final res = await _repo.advanceStocktake(
      take.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, res.ok ? '✔ تمّ الانتقال' : res.error,
        error: !res.ok);
    if (res.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'جرد المحروقات', icon: 'clipboard'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final can = Perm.of(context).writable('fuelStocktake');
    final open = _takes.where((t) => t.status != FuelStocktakeStatus.posted).length;
    final current = _takes.where((t) => t.id == _openId).firstOrNull;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'جرد المحروقات',
        icon: 'clipboard',
        subtitle: 'أمر جرد يمرّ بأربع مراحل: مفتوح ← العدّ الفعلي ← تحليل '
            'الفروقات ← مرحّل. والرصيد لا يتأثر إلا بالترحيل',
      ),
      const ImdWorkflowSteps([
        'يُفتح الأمر فيُلتقط الرصيد الدفتري وقتَه',
        'تعدّ اللجنة الخزّانات وتكتب المعدود',
        'تُراجَع الفروقات قبل إثباتها',
        'يُرحَّل فيدخل الفرق رصيد المستودع',
      ]),
      ImdKpis(children: [
        ImdKpi(label: 'أوامر الجرد', value: nf(_takes.length)),
        ImdKpi(
          label: 'قيد التنفيذ',
          value: nf(open),
          extra: open == 0 ? null : const ImdChip('لم تُرحَّل', tone: ImdTone.pend),
        ),
        ImdKpi(
            label: 'مرحّلة',
            value: nf(_takes.length - open)),
      ]),
      if (can)
        ImdPanel(
          title: 'فتح أمر جرد',
          icon: 'plus-square',
          child: _openForm(),
        ),
      if (current != null)
        ImdPanel(
          title: 'العدّ الفعلي — ${current.refNo}',
          icon: 'scan',
          child: _countPanel(current, can),
        ),
      ImdPanel(title: 'أوامر الجرد', icon: 'list', child: _table(can)),
    ]);
  }

  Widget _openForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ImdNote(
            'الرصيد الدفتري يُلتقط **لحظة الفتح** لا لحظة الترحيل: الفارق بينه '
            'وبين المعدود هو ما يُسأل عنه، ولو قُرئ عند الترحيل لابتلع كل حركةٍ '
            'وقعت أثناء العدّ.',
          ),
          const SizedBox(height: 12),
          ImdF2(children: [
            ImdLabeled(
              'المستودع *',
              ImdSelect<String>(
                items: [
                  for (final w in _warehouses) (w.name, w.name),
                ],
                value: _warehouse,
                onChanged: (v) => setState(() => _warehouse = v ?? ''),
              ),
              size: 11,
            ),
            ImdLabeled(
              'التاريخ',
              ImdDateField(
                  value: _date, onChanged: (v) => setState(() => _date = v)),
              size: 11,
            ),
            ImdLabeled(
              'نوع الجرد',
              ImdSelect<String>(
                items: const [('full', 'جرد كامل'), ('partial', 'جرد جزئي')],
                value: _kind,
                onChanged: (v) => setState(() => _kind = v ?? 'full'),
              ),
              size: 11,
            ),
            ImdLabeled(
              'الوقود',
              ImdSelect<String>(
                items: [
                  ('all', 'الكل'),
                  for (final t in FuelType.all) (t, FuelType.label(t)),
                ],
                value: _fuelFilter,
                onChanged: (v) => setState(() => _fuelFilter = v ?? 'all'),
              ),
              size: 11,
            ),
            ImdLabeled('اللجنة', ImdFld(controller: _committee), size: 11),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
                label: 'فتح أمر الجرد',
                icon: 'clipboard',
                busy: _busy,
                onPressed: _open),
          ),
        ],
      );

  Widget _countPanel(FuelStocktake take, bool can) {
    final c = context.imd;
    final editable = FuelStocktakeStatus.editable(take.status);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdChipsRow(children: [
        ImdChip(FuelStocktakeStatus.label(take.status),
            tone: take.status == FuelStocktakeStatus.posted
                ? ImdTone.ok
                : ImdTone.pend),
        ImdChip(take.warehouse, tone: ImdTone.code),
        if (take.committee.isNotEmpty)
          ImdChip('اللجنة: ${take.committee}', tone: ImdTone.off),
      ]),
      const SizedBox(height: 10),
      ImdTable(
        empty: 'لا سطور',
        minWidth: 700,
        columns: const [
          ImdCol('النوع'),
          ImdCol('الدفتري', numeric: true),
          ImdCol('المعدود', numeric: true),
          ImdCol('الفرق', numeric: true),
          ImdCol('الحالة'),
        ],
        rows: [
          for (final l in _lines)
            [
              Text(FuelType.label(l.fuelType),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${nf(l.bookLiters)} ${Fuel.unit}'),
              if (editable && can)
                SizedBox(
                  width: 130,
                  child: ImdFld(
                    controller: _counts[l.id]!,
                    number: true,
                    hint: 'المعدود',
                    onChanged: (_) => setState(() {}),
                  ),
                )
              else
                Text(l.counted ? '${nf(l.countedLiters)} ${Fuel.unit}' : '—'),
              _diff(l),
              l.counted
                  ? const ImdChip('عُدَّ', tone: ImdTone.ok)
                  : const ImdChip('لم يُعدّ', tone: ImdTone.pend),
            ],
        ],
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (editable && can)
          ImdButton.outline(
              label: 'حفظ العدّ',
              icon: 'save',
              small: true,
              busy: _busy,
              onPressed: _saveCounts),
        if (can && FuelStocktakeStatus.next(take.status) != null)
          ImdButton(
            label: 'الانتقال إلى: '
                '${FuelStocktakeStatus.label(FuelStocktakeStatus.next(take.status)!)}',
            icon: 'arrow-left',
            small: true,
            busy: _busy,
            onPressed: () => _advance(take),
          ),
        ImdButton.outline(
          label: 'طباعة المحضر',
          icon: 'printer',
          small: true,
          onPressed: () => FuelPrint.stocktakeReport(_db, take, _lines),
        ),
        ImdButton.outline(
            label: 'إغلاق',
            icon: 'x',
            small: true,
            onPressed: () => setState(() {
                  _openId = '';
                  _lines = const [];
                })),
      ]),
      if (take.status == FuelStocktakeStatus.posted) ...[
        const SizedBox(height: 10),
        Text('هذا الجرد مرحّل — فروقاته صارت جزءًا من رصيد المستودع.',
            style: TextStyle(fontSize: 12.5, color: c.muted)),
      ],
    ]);
  }

  Widget _diff(FuelStocktakeLine l) {
    final c = context.imd;
    if (!l.counted) return Text('—', style: TextStyle(color: c.muted));
    final d = Fuel.round(l.countedLiters - l.bookLiters);
    if (d == 0) {
      return Text('مطابق', style: TextStyle(color: c.success, fontSize: 12.5));
    }
    return Text(
      '${d > 0 ? '+' : ''}${nf(d)} ${Fuel.unit}',
      style: TextStyle(
          fontWeight: FontWeight.w700, color: d < 0 ? c.danger : c.warn),
    );
  }

  Widget _table(bool can) => ImdTable(
        empty: 'لا أوامر جرد بعد',
        minWidth: 820,
        onRowTap: (i) => _openLines(_takes[i].id),
        columns: const [
          ImdCol('السند'),
          ImdCol('التاريخ'),
          ImdCol('المستودع'),
          ImdCol('النوع'),
          ImdCol('اللجنة'),
          ImdCol('المرحلة'),
          ImdCol('', center: true),
        ],
        rows: [
          for (final t in _takes)
            [
              Text(t.refNo,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(arDigits(t.date)),
              Text(t.warehouse),
              Text(t.kind == 'full' ? 'كامل' : 'جزئي'),
              Text(t.committee.isEmpty ? '—' : t.committee),
              ImdChip(FuelStocktakeStatus.label(t.status),
                  tone: switch (t.status) {
                    FuelStocktakeStatus.posted => ImdTone.ok,
                    FuelStocktakeStatus.analysis => ImdTone.info,
                    _ => ImdTone.pend,
                  }),
              ImdIconButton(
                  icon: 'eye',
                  tooltip: 'فتح السطور',
                  onPressed: () => _openLines(t.id)),
            ],
        ],
      );
}
