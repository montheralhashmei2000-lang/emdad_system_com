import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/fuel.dart';

/// سجل المركبات — ما شربته كل مركبة بشاصيها.
///
/// **الشاصي هو ما يُحاسب عليه.** السائق يتبدّل والوحدة تتبدّل، ورقم الشاصي
/// يبقى — وبه وحده يُكشف صرفٌ متكرر لمركبةٍ واحدة بأسماء سائقين مختلفين.
class FuelVehiclesScreen extends StatefulWidget {
  const FuelVehiclesScreen({super.key});

  @override
  State<FuelVehiclesScreen> createState() => _FuelVehiclesScreenState();
}

class _FuelVehiclesScreenState extends State<FuelVehiclesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelChassisLog> _logs = const [];
  List<FuelIssue> _issues = const [];
  final _q = TextEditingController();
  String _open = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final logs = await _repo.chassisLogs();
    final issues = await _repo.issues();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _issues = issues;
      _loading = false;
    });
  }

  List<FuelChassisLog> get _visible {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs
        .where((v) =>
            v.chassisNo.toLowerCase().contains(q) ||
            v.vehicleType.toLowerCase().contains(q) ||
            v.lastDriver.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'سجل المركبات', icon: 'truck'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final total = _logs.fold<double>(0, (s, v) => s + v.liters);
    final noChassis = _issues.where((i) => i.chassisNo.trim().isEmpty).length;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'سجل المركبات',
        icon: 'truck',
        subtitle: 'ما شربته كل مركبة بشاصيها — السائق يتبدّل والشاصي يبقى',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'المركبات', value: nf(_logs.length)),
        ImdKpi(label: 'إجمالي ما صُرف لها', value: '${nf(total)} ${Fuel.unit}'),
        ImdKpi(
          label: 'صرف بلا شاصي',
          value: nf(noChassis),
          extra: noChassis == 0
              ? null
              : const ImdChip('لا يُحاسب عليه', tone: ImdTone.pend),
        ),
      ]),
      ImdICard(
        child: ImdSearchBar(
          controller: _q,
          hint: 'بحث بالشاصي أو نوع المركبة أو السائق…',
          onChanged: (_) => setState(() {}),
          actions: [
            ImdButton.outline(
                label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
          ],
        ),
      ),
      if (noChassis > 0)
        ImdNote(
          'يوجد ${nf(noChassis)} سند صرف بلا رقم شاصي، فلا يدخل هذا السجل. '
          'ويمكن **اشتراط الشاصي** في كل صرف من «إعدادات المحروقات».',
        ),
      ImdPanel(
        title: 'المركبات',
        icon: 'list',
        child: ImdTable(
          empty: 'لا مركبات بعد — يظهر هنا كل شاصي صُرف له وقود',
          minWidth: 820,
          onRowTap: (i) => setState(() => _open =
              _open == _visible[i].chassisNo ? '' : _visible[i].chassisNo),
          columns: const [
            ImdCol('رقم الشاصي'),
            ImdCol('نوع المركبة'),
            ImdCol('آخر سائق'),
            ImdCol('آخر صرف'),
            ImdCol('عدد المرات', numeric: true),
            ImdCol('الإجمالي', numeric: true),
          ],
          pageSize: 50,
          maxHeight: ImdSizes.tableMaxHeight(context),
          rows: [
            for (final v in _visible)
              [
                Text(v.chassisNo,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(v.vehicleType.isEmpty ? '—' : v.vehicleType),
                Text(v.lastDriver.isEmpty ? '—' : v.lastDriver),
                Text(arDigits(v.lastDate)),
                Text(nf(v.count)),
                Text('${nf(v.liters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
          ],
        ),
      ),
      if (_open.isNotEmpty)
        ImdPanel(
          title: 'سندات المركبة $_open',
          icon: 'file',
          child: ImdTable(
            empty: 'لا سندات',
            minWidth: 760,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المستودع'),
              ImdCol('المستفيد'),
              ImdCol('السائق'),
              ImdCol('الكمية', numeric: true),
            ],
            pageSize: 50,
            rows: [
              for (final i in _issues.where((x) => x.chassisNo.trim() == _open))
                [
                  Text(i.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(i.date)),
                  Text(FuelType.label(i.fuelType)),
                  Text(i.warehouse),
                  Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
                  Text(i.driverName.isEmpty ? '—' : i.driverName),
                  Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ),
    ]);
  }
}
