import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';
import 'fuel_print.dart';

/// حركة المحروقات: الصرف والتوريد والتحويل والرصيد الافتتاحي.
///
/// الأربعة في شاشةٍ واحدة بتبويبات لأنها تُدار من مقعدٍ واحد ومن شخصٍ واحد:
/// أمين المحروقات يورّد صباحًا ويصرف نهارًا ويحوّل عند الطلب، وتفريقها على
/// أربع شاشات يجعله يبحث عن الشاشة أكثر مما يكتب فيها.
class FuelMovesScreen extends StatefulWidget {
  const FuelMovesScreen({super.key});

  @override
  State<FuelMovesScreen> createState() => _FuelMovesScreenState();
}

class _FuelMovesScreenState extends State<FuelMovesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelAllocationRow> _allocations = const [];
  List<FuelStock> _stocks = const [];
  List<FuelIssue> _issues = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelTransfer> _transfers = const [];
  List<FuelOpening> _openings = const [];

  String _tab = 'issue';
  bool _loading = true;
  bool _busy = false;

  // مشترك
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  String _fuelType = FuelType.diesel;
  String _warehouse = '';
  final _qty = TextEditingController();
  final _notes = TextEditingController();

  // صرف
  String _source = FuelSource.allocation;
  String _allocationId = '';
  String _orderAuthority = '';
  final _driver = TextEditingController();
  final _vehicle = TextEditingController();
  final _chassis = TextEditingController();
  final _justification = TextEditingController();
  final _purpose = TextEditingController();
  final _beneficiary = TextEditingController();

  // توريد
  final _supplier = TextEditingController();
  final _transport = TextEditingController();

  // تحويل
  String _toWarehouse = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _qty,
      _notes,
      _driver,
      _vehicle,
      _chassis,
      _justification,
      _purpose,
      _beneficiary,
      _supplier,
      _transport,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final warehouses = await _repo.warehouses(onlyActive: true);
    final allocations = await _repo.allocations(onlyActive: true);
    final stocks = await _repo.stocks();
    final issues = await _repo.issues();
    final supplies = await _repo.supplies();
    final transfers = await _repo.transfers();
    final openings = await _repo.openings();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _allocations = allocations;
      _stocks = stocks;
      _issues = issues;
      _supplies = supplies;
      _transfers = transfers;
      _openings = openings;
      if (_warehouse.isEmpty && warehouses.isNotEmpty) {
        _warehouse = warehouses.first.name;
      }
      _loading = false;
    });
  }

  double get _available => _stocks
      .where((s) => s.warehouse == _warehouse && s.fuelType == _fuelType)
      .firstOrNull
      ?.stock ??
      0;

  double get _qtyValue => double.tryParse(_qty.text.trim()) ?? 0;

  FuelAllocationRow? get _allocation =>
      _allocations.where((a) => a.allocation.id == _allocationId).firstOrNull;

  void _clearForm() {
    for (final c in [
      _qty,
      _notes,
      _driver,
      _vehicle,
      _chassis,
      _justification,
      _purpose,
      _beneficiary,
      _supplier,
      _transport,
    ]) {
      imdSetText(c, '');
    }
    setState(() {
      _allocationId = '';
      _orderAuthority = '';
    });
  }

  Future<void> _submit() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelMoves', PermAction.create)) return;
    setState(() => _busy = true);
    final actor = context.read<AuthService>().currentUser?.email ?? '';
    late FuelResult res;
    switch (_tab) {
      case 'issue':
        res = await _repo.saveIssue(
          date: _date,
          fuelType: _fuelType,
          warehouse: _warehouse,
          quantityLiters: _qtyValue,
          source: _source,
          allocationId: _allocationId,
          beneficiaryName: _beneficiary.text.trim(),
          driverName: _driver.text.trim(),
          vehicleType: _vehicle.text.trim(),
          chassisNo: _chassis.text.trim(),
          justification: _justification.text.trim(),
          orderAuthority: _orderAuthority,
          purpose: _purpose.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      case 'supply':
        res = await _repo.saveSupply(
          date: _date,
          fuelType: _fuelType,
          warehouse: _warehouse,
          quantityLiters: _qtyValue,
          supplierName: _supplier.text.trim(),
          transportVehicleType: _transport.text.trim(),
          driverName: _driver.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      case 'transfer':
        res = await _repo.saveTransfer(
          date: _date,
          fuelType: _fuelType,
          fromWarehouse: _warehouse,
          toWarehouse: _toWarehouse,
          quantityLiters: _qtyValue,
          driverName: _driver.text.trim(),
          transportVehicleType: _transport.text.trim(),
          notes: _notes.text.trim(),
          actor: actor,
        );
      default:
        res = await _repo.saveOpening(
          warehouse: _warehouse,
          fuelType: _fuelType,
          liters: _qtyValue,
          asOfDate: _date,
          note: _notes.text.trim(),
          actor: actor,
        );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(
      context,
      res.ok
          ? '✔ حُفظ${res.refNo.isEmpty ? '' : ' السند ${res.refNo}'}'
          : res.error,
      error: !res.ok,
    );
    if (res.ok) {
      _clearForm();
      await _load();
    }
  }

  /// طباعة سند الصرف مع استحقاق تفريدته وقت الطباعة.
  Future<void> _printIssue(FuelIssue issue) async {
    final row = issue.allocationId.isEmpty
        ? null
        : _allocations
            .where((a) => a.allocation.id == issue.allocationId)
            .firstOrNull;
    await FuelPrint.issueVoucher(_db, issue, allocation: row);
  }

  Future<void> _printLog() async {
    switch (_tab) {
      case 'issue':
        if (_issues.isEmpty) {
          showImdToast(context, '✖ لا سندات للطباعة');
          return;
        }
        await FuelPrint.issuesReport(_db, _issues);
      default:
        showImdToast(context, 'ℹ الكشف المجمّع متاح لسجل الصرف');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'حركة المحروقات', icon: 'swap'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    if (_warehouses.isEmpty) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'حركة المحروقات', icon: 'swap'),
        ImdEmptyBox('عرّف مستودعًا أولًا من شاشة المستودعات'),
      ]);
    }
    final can = Perm.of(context).writable('fuelMoves');

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'حركة المحروقات',
        icon: 'swap',
        subtitle: 'الصرف والتوريد والتحويل والرصيد الافتتاحي — كلها تحرّك '
            'رصيد المستودع من الوقود',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _clearForm();
        }),
        tabs: const [
          ImdTab('issue', 'صرف', icon: 'upload'),
          ImdTab('supply', 'توريد', icon: 'download'),
          ImdTab('transfer', 'تحويل', icon: 'swap'),
          ImdTab('opening', 'رصيد افتتاحي', icon: 'clipboard'),
        ],
      ),
      const SizedBox(height: 4),
      if (can)
        ImdPanel(
          title: switch (_tab) {
            'issue' => 'صرف محروقات',
            'supply' => 'توريد محروقات',
            'transfer' => 'تحويل بين مستودعين',
            _ => 'ضبط رصيد افتتاحي',
          },
          icon: 'plus-square',
          child: _form(),
        ),
      ImdPanel(
        title: 'السجل',
        icon: 'list',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_tab == 'issue')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ImdButton.outline(
                  label: 'طباعة كشف الصرف',
                  icon: 'printer',
                  small: true,
                  onPressed: _printLog,
                ),
              ),
            ),
          _log(),
        ]),
      ),
    ]);
  }

  Widget _stockHint() {
    return ImdChipsRow(bottom: 0, children: [
      ImdChip(
        'المتاح في «$_warehouse» من ${FuelType.label(_fuelType)}: '
        '${nf(_available)} ${Fuel.unit}',
        tone: _available <= 0 ? ImdTone.err : ImdTone.ok,
      ),
      if (_tab == 'issue' && _source == FuelSource.allocation && _allocation != null)
        ImdChip(
          'متبقي التفريدة: ${nf(_allocation!.remaining)} ${Fuel.unit}',
          tone: _allocation!.remaining <= 0 ? ImdTone.err : ImdTone.info,
        ),
    ]);
  }

  Widget _form() {
    final common = <Widget>[
      ImdLabeled(
        'التاريخ *',
        ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)),
        size: 11,
      ),
      ImdLabeled(
        'نوع الوقود *',
        ImdSelect<String>(
          items: [for (final t in FuelType.all) (t, FuelType.label(t))],
          value: _fuelType,
          onChanged: (v) => setState(() => _fuelType = v ?? FuelType.diesel),
        ),
        size: 11,
      ),
      ImdLabeled(
        _tab == 'transfer' ? 'من مستودع *' : 'المستودع *',
        ImdSelect<String>(
          items: [
            // نطاق مستودعات الإعاشة لا يحكم خزّانات الوقود: دليلٌ مستقل
            // وصلاحياتٌ مستقلة (`fuelMoves`).
            for (final w in _warehouses) (w.name, w.name),
          ],
          value: _warehouse,
          onChanged: (v) => setState(() => _warehouse = v ?? ''),
        ),
        size: 11,
      ),
      if (_tab == 'transfer')
        ImdLabeled(
          'إلى مستودع *',
          ImdSelect<String>(
            items: [
              ('', '— اختر —'),
              for (final w in _warehouses)
                if (w.name != _warehouse) (w.name, w.name),
            ],
            value: _toWarehouse,
            onChanged: (v) => setState(() => _toWarehouse = v ?? ''),
          ),
          size: 11,
        ),
      ImdLabeled(
        'الكمية (${Fuel.unit}) *',
        ImdFld(
            controller: _qty, number: true, onChanged: (_) => setState(() {})),
        size: 11,
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stockHint(),
      const SizedBox(height: 12),
      ImdF2(children: [
        ...common,
        if (_tab == 'issue') ..._issueFields(),
        if (_tab == 'supply') ..._supplyFields(),
        if (_tab == 'transfer') ..._transportFields(),
      ]),
      const SizedBox(height: 10),
      ImdLabeled(
          _tab == 'opening' ? 'ملاحظة' : 'ملاحظات',
          ImdFld(controller: _notes, maxLines: 2)),
      if (_tab == 'opening') ...[
        const SizedBox(height: 10),
        const ImdNote(
          'الرصيد الافتتاحي هو ما كان في الخزّان **قبل أن يبدأ النظام**. '
          'ولا يُستعمل لتصحيح فرقٍ بعد التشغيل — ذلك بابه الجرد، فيبقى له أثرٌ '
          'ولجنةٌ وتاريخ.',
        ),
      ],
      if (_tab == 'issue' && _source == FuelSource.exceptional) ...[
        const SizedBox(height: 10),
        const ImdNote(
          'الأمر الاستثنائي يخرج عن كل تفريدة، فيلزمه **مبرر وجهة أمر** '
          'ويُسجَّل في التدقيق عالي الخطورة.',
        ),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        ImdButton(
          label: 'حفظ',
          icon: 'check',
          busy: _busy,
          onPressed: _submit,
        ),
        ImdButton.outline(label: 'مسح', icon: 'eraser', onPressed: _clearForm),
      ]),
    ]);
  }

  List<Widget> _issueFields() => [
        ImdLabeled(
          'مصدر الصرف *',
          ImdSelect<String>(
            items: [for (final s in FuelSource.all) (s, FuelSource.label(s))],
            value: _source,
            onChanged: (v) => setState(() {
              _source = v ?? FuelSource.allocation;
              _allocationId = '';
            }),
          ),
          size: 11,
        ),
        if (_source == FuelSource.allocation)
          ImdLabeled(
            'التفريدة *',
            ImdSelect<String>(
              items: [
                ('', '— اختر —'),
                for (final a in _allocations)
                  if (a.allocation.fuelType == _fuelType)
                    (
                      a.allocation.id,
                      '${a.allocation.unitName} — متبقي ${nf(a.remaining)}'
                    ),
              ],
              value: _allocationId,
              onChanged: (v) => setState(() => _allocationId = v ?? ''),
            ),
            size: 11,
          )
        else ...[
          ImdLabeled(
              'الجهة المستفيدة', ImdFld(controller: _beneficiary), size: 11),
          ImdLabeled(
            'جهة الأمر *',
            ImdSelect<String>(
              items: [
                ('', '— اختر —'),
                for (final a in Fuel.orderAuthorities) (a, a),
              ],
              value: _orderAuthority,
              onChanged: (v) => setState(() => _orderAuthority = v ?? ''),
            ),
            size: 11,
          ),
          ImdLabeled('المبرر *', ImdFld(controller: _justification), size: 11),
        ],
        ImdLabeled('اسم السائق', ImdFld(controller: _driver), size: 11),
        ImdLabeled('نوع المركبة', ImdFld(controller: _vehicle), size: 11),
        ImdLabeled(
          'رقم الشاصي',
          ImdFld(controller: _chassis, hint: 'به يُعرف ما شربته المركبة'),
          size: 11,
        ),
        ImdLabeled('الغرض', ImdFld(controller: _purpose), size: 11),
      ];

  List<Widget> _supplyFields() => [
        ImdLabeled('المورّد', ImdFld(controller: _supplier), size: 11),
        ..._transportFields(),
      ];

  List<Widget> _transportFields() => [
        ImdLabeled('اسم السائق', ImdFld(controller: _driver), size: 11),
        ImdLabeled('مركبة النقل', ImdFld(controller: _transport), size: 11),
      ];

  Widget _log() {
    final c = context.imd;
    return switch (_tab) {
      'issue' => ImdTable(
          empty: 'لا صرف بعد',
          minWidth: 980,
          columns: const [
            ImdCol('السند'),
            ImdCol('التاريخ'),
            ImdCol('النوع'),
            ImdCol('المستودع'),
            ImdCol('المستفيد'),
            ImdCol('المصدر'),
            ImdCol('الشاصي'),
            ImdCol('الكمية', numeric: true),
            ImdCol('', center: true),
          ],
          rows: [
            for (final i in _issues)
              [
                Text(i.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
                Text(arDigits(i.date)),
                Text(FuelType.label(i.fuelType)),
                Text(i.warehouse),
                Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
                i.source == FuelSource.exceptional
                    ? const ImdChip('استثنائي', tone: ImdTone.pend)
                    : const ImdChip('تفريدة', tone: ImdTone.ok),
                Text(i.chassisNo.isEmpty ? '—' : i.chassisNo),
                Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdIconButton(
                    icon: 'printer',
                    tooltip: 'طباعة السند',
                    onPressed: () => _printIssue(i)),
              ],
          ],
        ),
      'supply' => ImdTable(
          empty: 'لا توريد بعد',
          minWidth: 820,
          columns: const [
            ImdCol('السند'),
            ImdCol('التاريخ'),
            ImdCol('النوع'),
            ImdCol('المستودع'),
            ImdCol('المورّد'),
            ImdCol('الكمية', numeric: true),
            ImdCol('', center: true),
          ],
          rows: [
            for (final s in _supplies)
              [
                Text(s.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
                Text(arDigits(s.date)),
                Text(FuelType.label(s.fuelType)),
                Text(s.warehouse),
                Text(s.supplierName.isEmpty ? '—' : s.supplierName),
                Text('${nf(s.quantityLiters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdIconButton(
                    icon: 'printer',
                    tooltip: 'طباعة السند',
                    onPressed: () => FuelPrint.supplyVoucher(_db, s)),
              ],
          ],
        ),
      'transfer' => ImdTable(
          empty: 'لا تحويلات بعد',
          minWidth: 820,
          columns: const [
            ImdCol('السند'),
            ImdCol('التاريخ'),
            ImdCol('النوع'),
            ImdCol('من ← إلى'),
            ImdCol('السائق'),
            ImdCol('الكمية', numeric: true),
            ImdCol('', center: true),
          ],
          rows: [
            for (final t in _transfers)
              [
                Text(t.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
                Text(arDigits(t.date)),
                Text(FuelType.label(t.fuelType)),
                Text('${t.fromWarehouse} ← ${t.toWarehouse}'),
                Text(t.driverName.isEmpty ? '—' : t.driverName),
                Text('${nf(t.quantityLiters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdIconButton(
                    icon: 'printer',
                    tooltip: 'طباعة السند',
                    onPressed: () => FuelPrint.transferVoucher(_db, t)),
              ],
          ],
        ),
      _ => ImdTable(
          empty: 'لا أرصدة افتتاحية',
          minWidth: 700,
          columns: const [
            ImdCol('المستودع'),
            ImdCol('النوع'),
            ImdCol('بتاريخ'),
            ImdCol('الرصيد', numeric: true),
            ImdCol('ملاحظة'),
          ],
          rows: [
            for (final o in _openings)
              [
                Text(o.warehouse),
                Text(FuelType.label(o.fuelType)),
                Text(arDigits(o.asOfDate)),
                Text('${nf(o.liters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(o.note.isEmpty ? '—' : o.note,
                    style: TextStyle(color: c.muted)),
              ],
          ],
        ),
    };
  }
}
