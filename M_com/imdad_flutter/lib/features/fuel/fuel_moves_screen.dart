import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_screen_actions.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/fuel.dart';
import '../inventory/doc_kit.dart';
import 'fuel_print.dart';

/// حركة المحروقات: الصرف والتوريد والتحويل والرصيد الافتتاحي.
///
/// الأربعة في شاشةٍ واحدة بتبويبات لأنها تُدار من مقعدٍ واحد ومن شخصٍ واحد:
/// أمين المحروقات يورّد صباحًا ويصرف نهارًا ويحوّل عند الطلب.
///
/// وكل تبويبٍ **بطاقاتٌ لا شبكةُ حقول**: الصرف سؤالٌ بعد سؤال — من أي مخزن،
/// وعلى أي أساس، ولمن، وبأي مركبة — وخلطُها في شبكةٍ واحدة يجعل الكاتب يقفز
/// بين المعاني في السطر الواحد.
class FuelMovesScreen extends StatefulWidget {
  const FuelMovesScreen({super.key, this.initialTab = 'issue', this.standalone = false});

  /// issue | supply | transfer | opening — يُفتح عليه القادم من القائمة.
  final String initialTab;

  /// `true` ⇒ الشاشة فُتحت من بند شجرةٍ مباشر (لا من باب «حركة المحروقات»
  /// الجامع)، فيُخفى شريط التبويبات الداخلي — التبويبة الواحدة هي الشاشة كلها.
  final bool standalone;

  @override
  State<FuelMovesScreen> createState() => _FuelMovesScreenState();
}

class _FuelMovesScreenState extends State<FuelMovesScreen> {
  /// أنواع الوسائل المعتادة — تُقترح ولا تُلزم.
  static const List<String> vehicles = [
    'شاص',
    'هايلوكس',
    'مولد',
    'دينة',
    'قاطرة',
    'كرار',
    'ماطور ماء',
    'ماطور الطلاء',
    'دراجة نارية',
    'وسيلة مدني',
    'باص مدني',
    'برادو',
  ];

  late final AppDatabase _db = context.read<AppDatabase>();
  late final FuelRepo _repo = FuelRepo(_db);

  List<FuelWarehouse> _warehouses = const [];
  List<FuelUnit> _units = const [];
  List<FuelAllocationRow> _allocations = const [];
  List<FuelStock> _stocks = const [];
  List<FuelIssue> _issues = const [];
  List<FuelSupply> _supplies = const [];
  List<FuelTransfer> _transfers = const [];
  List<FuelOpening> _openings = const [];
  FuelSettingsRow? _settings;

  late String _tab = widget.initialTab;
  bool _loading = true;
  bool _busy = false;

  /// آخر سندٍ حُفظ — يظهر شريطه فوق النموذج ليُطبع قبل أن يُنسى.
  String _savedRef = '';

  // مشترك
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  String _fuelType = FuelType.petrol;
  String _warehouse = '';
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  final _q = TextEditingController();

  // صرف
  String _source = FuelSource.allocation;
  String _allocationId = '';
  String _unitId = '';
  final _orderAuthority = TextEditingController(text: 'استحقاق');
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

  // سندات معلّقة داخل الجلسة (زر «سند جديد»)
  final List<ImdDocTab<Map<String, dynamic>>> _suspended = [];
  int _tabSeq = 1;
  int _activeTabId = 0;

  ImdScreenActions? _screenActions;

  List<TextEditingController> get _all => [
        _qty,
        _notes,
        _q,
        _orderAuthority,
        _driver,
        _vehicle,
        _chassis,
        _justification,
        _purpose,
        _beneficiary,
        _supplier,
        _transport,
      ];

  @override
  void initState() {
    super.initState();
    _load();
    _screenActions = ImdScreenActions.maybeOf(context)
      ?..register(
        onSave: () {
          if (!_busy) _submit();
        },
        onPrint: () {
          if (!_busy) _printSaved();
        },
        onNewDoc: _openNewTab,
        onRefresh: _load,
      );
  }

  @override
  void didUpdateWidget(covariant FuelMovesScreen old) {
    super.didUpdateWidget(old);
    // التنقّل بين بنود القائمة يعيد بناء الشاشة نفسها بتبويبٍ آخر.
    if (old.initialTab != widget.initialTab) {
      setState(() {
        _tab = widget.initialTab;
        _savedRef = '';
      });
    }
  }

  @override
  void dispose() {
    _screenActions?.clear();
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final warehouses = await _repo.warehouses(onlyActive: true);
    final units = await _repo.units(onlyActive: true);
    final allocations = await _repo.allocations(onlyActive: true);
    final stocks = await _repo.stocks();
    final issues = await _repo.issues();
    final supplies = await _repo.supplies();
    final transfers = await _repo.transfers();
    final openings = await _repo.openings();
    final settings = await _repo.settings();
    if (!mounted) return;
    setState(() {
      _warehouses = warehouses;
      _units = units;
      _allocations = allocations;
      _stocks = stocks;
      _issues = issues;
      _supplies = supplies;
      _transfers = transfers;
      _openings = openings;
      _settings = settings;
      if (_warehouse.isEmpty && warehouses.isNotEmpty) {
        _warehouse = warehouses.first.name;
      }
      _loading = false;
    });
  }

  // ───────────────────────── قيمٌ محسوبة

  double get _available =>
      _stocks
          .where((s) => s.warehouse == _warehouse && s.fuelType == _fuelType)
          .firstOrNull
          ?.stock ??
      0;

  double get _capacity =>
      _warehouses
          .where((w) => w.name == _warehouse)
          .firstOrNull
          ?.capacityLiters ??
      0;

  double get _qtyValue => double.tryParse(_qty.text.trim()) ?? 0;

  FuelAllocationRow? get _allocation =>
      _allocations.where((a) => a.allocation.id == _allocationId).firstOrNull;

  List<FuelAllocationRow> get _pickable => _allocations
      .where(
          (a) => a.allocation.fuelType == _fuelType && a.allocation.disbursable)
      .toList();

  /// مانع الصرف من التفريدة المختارة، أو `null` إن جاز.
  String? get _allocationError {
    final a = _allocation;
    if (a == null) return null;
    return Fuel.issueBlock(
      allocation: a.calc,
      date: _date,
      qty: _qtyValue,
      alreadyIssued: a.issued,
    );
  }

  bool get _chassisRequired => _settings?.requireChassis ?? false;
  bool get _allowExceptional => _settings?.allowExceptional ?? true;

  /// آخر سندٍ لهذا الشاصي — منه يُعبّأ السائق والوسيلة.
  FuelIssue? get _lastForChassis {
    final v = _chassis.text.trim();
    if (v.isEmpty) return null;
    return _issues.where((i) => i.chassisNo.trim() == v).firstOrNull;
  }

  // ───────────────────────── أفعال

  void _onChassis(String v) {
    final prev = _lastForChassis;
    if (prev != null) {
      if (_driver.text.trim().isEmpty) imdSetText(_driver, prev.driverName);
      if (_vehicle.text.trim().isEmpty) imdSetText(_vehicle, prev.vehicleType);
    }
    setState(() {});
  }

  void _pickAllocation(String id) {
    final a = _allocations.where((x) => x.allocation.id == id).firstOrNull;
    setState(() => _allocationId = id);
    if (a == null) return;
    // الكمية المقترحة حصّةُ الفترة، ولا تتجاوز ما بقي من الاستحقاق.
    final suggested = a.allocation.quantityPerPeriod;
    final value = suggested > a.remaining ? a.remaining : suggested;
    imdSetText(_qty, value <= 0 ? '' : _num(value));
    imdSetText(_orderAuthority, 'استحقاق');
    if (_beneficiary.text.trim().isEmpty) {
      imdSetText(_beneficiary, a.allocation.unitName);
    }
    setState(() {});
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _clearForm() {
    for (final c in _all) {
      if (c == _q) continue;
      imdSetText(c, '');
    }
    imdSetText(
        _orderAuthority, _source == FuelSource.allocation ? 'استحقاق' : '');
    setState(() {
      _allocationId = '';
      _unitId = '';
      _savedRef = '';
    });
  }

  // ─────────────────────── تبويبات السندات المعلّقة ───────────────────────
  static String _tabLabel(String tab) => switch (tab) {
        'issue' => 'صرف',
        'supply' => 'توريد',
        'transfer' => 'تحويل',
        _ => 'رصيد افتتاحي',
      };

  String _activeTabLabel() =>
      _savedRef.isNotEmpty ? _savedRef : '${_tabLabel(_tab)} جديد';

  /// لقطة بيانات السند الجاري تعبئته — لتعليقه في تبويبٍ جانبي.
  Map<String, dynamic> _captureDocSnapshot() => {
        'tab': _tab,
        'date': _date,
        'fuelType': _fuelType,
        'warehouse': _warehouse,
        'qty': _qty.text,
        'notes': _notes.text,
        'source': _source,
        'allocationId': _allocationId,
        'unitId': _unitId,
        'orderAuthority': _orderAuthority.text,
        'driver': _driver.text,
        'vehicle': _vehicle.text,
        'chassis': _chassis.text,
        'justification': _justification.text,
        'purpose': _purpose.text,
        'beneficiary': _beneficiary.text,
        'supplier': _supplier.text,
        'transport': _transport.text,
        'toWarehouse': _toWarehouse,
        'savedRef': _savedRef,
      };

  /// يكتب لقطةً محفوظةً من تبويبٍ معلّق رجوعًا إلى حقول النموذج — بلا
  /// المرور بـ[_clearForm] حتى لا تُمحى اللقطة المُستعادة نفسها.
  void _applySnapshot(Map<String, dynamic> data) {
    setState(() {
      _tab = '${data['tab'] ?? _tab}';
      _date = '${data['date'] ?? _date}';
      _fuelType = '${data['fuelType'] ?? _fuelType}';
      _warehouse = '${data['warehouse'] ?? _warehouse}';
      imdSetText(_qty, '${data['qty'] ?? ''}');
      imdSetText(_notes, '${data['notes'] ?? ''}');
      _source = '${data['source'] ?? FuelSource.allocation}';
      _allocationId = '${data['allocationId'] ?? ''}';
      _unitId = '${data['unitId'] ?? ''}';
      imdSetText(_orderAuthority, '${data['orderAuthority'] ?? ''}');
      imdSetText(_driver, '${data['driver'] ?? ''}');
      imdSetText(_vehicle, '${data['vehicle'] ?? ''}');
      imdSetText(_chassis, '${data['chassis'] ?? ''}');
      imdSetText(_justification, '${data['justification'] ?? ''}');
      imdSetText(_purpose, '${data['purpose'] ?? ''}');
      imdSetText(_beneficiary, '${data['beneficiary'] ?? ''}');
      imdSetText(_supplier, '${data['supplier'] ?? ''}');
      imdSetText(_transport, '${data['transport'] ?? ''}');
      _toWarehouse = '${data['toWarehouse'] ?? ''}';
      _savedRef = '${data['savedRef'] ?? ''}';
    });
  }

  /// زر «سند جديد»: يعلّق السند الحالي في تبويبٍ جانبي ويفتح سندًا فارغًا
  /// بنفس التبويبة الحالية (صرف/توريد/تحويل/رصيد).
  void _openNewTab() {
    final snap = _captureDocSnapshot();
    setState(() {
      _suspended.add(ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: snap));
      _activeTabId = _tabSeq++;
    });
    _clearForm();
  }

  void _switchDocTab(int id) {
    if (id == _activeTabId) return;
    final idx = _suspended.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final target = _suspended.removeAt(idx);
    final current = ImdDocTab<Map<String, dynamic>>(id: _activeTabId, label: _activeTabLabel(), snapshot: _captureDocSnapshot());
    setState(() {
      _suspended
        ..removeWhere((t) => t.id == target.id)
        ..add(current);
      _activeTabId = target.id;
    });
    _applySnapshot(target.snapshot);
  }

  void _closeDocTab(int id) => setState(() => _suspended.removeWhere((t) => t.id == id));

  Future<void> _submit() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'fuelMoves', PermAction.create)) return;
    setState(() => _busy = true);
    final actor = context.read<AuthService>().currentUser?.email ?? '';
    late FuelResult res;
    switch (_tab) {
      case 'issue':
        final unit = _allocation?.allocation.unitId ?? _unitId;
        res = await _repo.saveIssue(
          date: _date,
          fuelType: _fuelType,
          warehouse: _warehouse,
          quantityLiters: _qtyValue,
          source: _source,
          allocationId: _source == FuelSource.allocation ? _allocationId : '',
          beneficiaryUnitId: unit,
          beneficiaryName: _beneficiary.text.trim().isNotEmpty
              ? _beneficiary.text.trim()
              : (_units.where((u) => u.id == unit).firstOrNull?.name ??
                  _driver.text.trim()),
          driverName: _driver.text.trim(),
          vehicleType: _vehicle.text.trim(),
          chassisNo: _chassis.text.trim(),
          justification: _justification.text.trim(),
          orderAuthority: _orderAuthority.text.trim().isNotEmpty
              ? _orderAuthority.text.trim()
              : (_source == FuelSource.allocation ? 'استحقاق' : 'أمر استثنائي'),
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
      if (mounted) setState(() => _savedRef = res.refNo);
    }
  }

  Future<void> _printIssue(FuelIssue issue) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
    final row = issue.allocationId.isEmpty
        ? null
        : _allocations
            .where((a) => a.allocation.id == issue.allocationId)
            .firstOrNull;
    await FuelPrint.issueVoucher(_db, issue, allocation: row);
  }

  Future<void> _printSaved() async {
    if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
    switch (_tab) {
      case 'issue':
        final doc = _issues.where((i) => i.refNo == _savedRef).firstOrNull;
        if (doc != null) await _printIssue(doc);
      case 'supply':
        final doc = _supplies.where((s) => s.refNo == _savedRef).firstOrNull;
        if (doc != null) await FuelPrint.supplyVoucher(_db, doc);
      case 'transfer':
        final doc = _transfers.where((t) => t.refNo == _savedRef).firstOrNull;
        if (doc != null) await FuelPrint.transferVoucher(_db, doc);
    }
  }

  Future<void> _reverse(FuelTransfer t) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', PermAction.create)) {
      return;
    }
    if (!await imdConfirm(
      context,
      'يُنشأ سند تحويل عكسي بنفس الكمية والصنف من «${t.toWarehouse}» إلى '
      '«${t.fromWarehouse}». متابعة؟',
      ok: 'تأكيد العكس',
    )) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.reverseTransfer(
      t.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ سند عكس ${res.refNo}' : res.error,
        error: !res.ok);
    if (res.ok) await _load();
  }

  Future<void> _deleteOpening(FuelOpening o) async {
    if (!Perm.of(context).guard(context, 'fuelMoves', PermAction.delete)) {
      return;
    }
    if (!await imdConfirm(context, 'حذف الرصيد الافتتاحي لـ«${o.warehouse}»؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    await _repo.deleteOpening(o.id);
    if (!mounted) return;
    showImdToast(context, '✔ حُذف الرصيد الافتتاحي');
    await _load();
  }

  // ───────────────────────── البناء

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
        ImdEmptyState.noData(title: 'عرّف مستودعًا أولًا من شاشة المستودعات'),
      ]);
    }
    final can = Perm.of(context).writable('fuelMoves');

    return ImdPage(children: [
      ImdPageTitle(
        title: switch (_tab) {
          'issue' => 'صرف محروقات',
          'supply' => 'توريد محروقات',
          'transfer' => 'التحويل المخزني',
          _ => 'الرصيد الافتتاحي',
        },
        icon: switch (_tab) {
          'issue' => 'upload',
          'supply' => 'download',
          'transfer' => 'swap',
          _ => 'compass',
        },
        subtitle: switch (_tab) {
          'issue' => 'يُخصم من رصيد المستودع فورًا — الجهة المستفيدة وجهة '
              'الأمر تظهران في التقرير اليومي',
          'supply' => 'تُضاف الكمية إلى رصيد المخزن المستلم فور الحفظ',
          'transfer' => 'نقل نفس الصنف بين مستودعين — يمكن عكس السند إذا بقي '
              'الرصيد كافيًا',
          _ => 'أرصدة بداية الفترة لكل مستودع وصنف — تدخل في حساب الجرد',
        },
        actions: [
          ImdButton.outline(label: 'سند جديد', icon: 'plus-square', small: true, onPressed: _openNewTab),
          if (!widget.standalone)
            ImdItabs(
              value: _tab,
              onChanged: (v) => setState(() {
                _tab = v;
                _savedRef = '';
                _clearForm();
              }),
              tabs: const [
                ImdTab('issue', 'صرف', icon: 'upload'),
                ImdTab('supply', 'توريد', icon: 'download'),
                ImdTab('transfer', 'تحويل', icon: 'swap'),
                ImdTab('opening', 'رصيد افتتاحي', icon: 'compass'),
              ],
            ),
        ],
        trailing: can
            ? ImdButton(
                label: switch (_tab) {
                  'issue' => 'حفظ الصرف',
                  'supply' => 'حفظ التوريد',
                  'transfer' => 'حفظ التحويل',
                  _ => 'حفظ الرصيد',
                },
                icon: 'check',
                busy: _busy,
                onPressed: _submit,
              )
            : null,
      ),
      if (_suspended.isNotEmpty)
        ImdDocTabsBar<Map<String, dynamic>>(
          activeLabel: _activeTabLabel(),
          suspended: _suspended,
          onSelect: _switchDocTab,
          onClose: _closeDocTab,
        ),
      const SizedBox(height: 4),
      if (_savedRef.isNotEmpty) _savedBanner(),
      if (can)
        ...switch (_tab) {
          'issue' => _issueForm(),
          'supply' => _supplyForm(),
          'transfer' => _transferForm(),
          _ => _openingForm(),
        },
      ...switch (_tab) {
        'issue' => _issueLog(),
        'supply' => _supplyLog(),
        'transfer' => _transferLog(),
        _ => _openingLog(),
      },
    ]);
  }

  Widget _savedBanner() {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.successSoft,
        border: Border.all(color: c.success),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('حُفظ السند $_savedRef',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          if (_tab != 'opening')
            ImdButton.outline(
                label: 'طباعة السند',
                icon: 'printer',
                small: true,
                onPressed: _printSaved),
          ImdButton.outline(
            label: 'حركة جديدة',
            icon: 'plus',
            small: true,
            onPressed: () => setState(() => _savedRef = ''),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── الصرف

  List<Widget> _issueForm() => [
        ImdPanel(
          title: 'بيانات الصرف',
          icon: 'file',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _fuelField(),
              _warehouseField('المخزن *'),
              _dateField('التاريخ *'),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip(
                'الرصيد المتاح في المخزن: ${nf(_available)} ${Fuel.unit}',
                tone: _available <= 0 ? ImdTone.err : ImdTone.ok,
              ),
            ]),
          ]),
        ),
        ImdPanel(
          title: 'مصدر الصرف',
          icon: 'scale',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdPillTabs<String>(
              value: _source,
              onChanged: (v) => setState(() {
                _source = v;
                _allocationId = '';
                imdSetText(_orderAuthority,
                    v == FuelSource.allocation ? 'استحقاق' : '');
              }),
              tabs: [
                for (final s in FuelSource.all) ImdTab(s, FuelSource.label(s)),
              ],
            ),
            const SizedBox(height: 14),
            if (_source == FuelSource.allocation) ...[
              ImdLabeled(
                'التفريدة *',
                ImdSelect<String>(
                  items: [
                    ('', '— اختر التفريدة —'),
                    for (final a in _pickable)
                      (
                        a.allocation.id,
                        '${a.allocation.refNo} — ${a.allocation.unitName} '
                            '— ${nf(a.allocation.quantityPerPeriod)} '
                            '${Fuel.unit}'
                      ),
                  ],
                  value: _allocationId,
                  onChanged: (v) => _pickAllocation(v ?? ''),
                ),
                size: 11,
              ),
              if (_allocation != null) ...[
                const SizedBox(height: 12),
                _allocationBox(_allocation!),
              ],
            ] else ...[
              if (!_allowExceptional)
                const ImdNote(
                    'الصرف الاستثنائي **موقوف من الإعدادات** — لن يُحفظ.'),
              ImdF2(children: [
                ImdLabeled(
                  'الوحدة المستفيدة',
                  ImdSelect<String>(
                    items: [
                      ('', '— اختر الوحدة (اختياري) —'),
                      for (final u in _units) (u.id, u.name),
                    ],
                    value: _unitId,
                    onChanged: (v) => setState(() => _unitId = v ?? ''),
                  ),
                  size: 11,
                ),
              ]),
              const SizedBox(height: 10),
              ImdLabeled(
                'مبرر الأمر الاستثنائي *',
                ImdFld(
                    controller: _justification,
                    maxLines: 2,
                    hint: 'اذكر سبب الصرف الاستثنائي…'),
              ),
              const SizedBox(height: 8),
              const ImdNote(
                'الأمر الاستثنائي يخرج عن كل تفريدة، فيلزمه **مبرر وجهة '
                'أمر** ويُسجَّل في التدقيق عالي الخطورة.',
              ),
            ],
          ]),
        ),
        ImdPanel(
          title: 'الجهة المستفيدة وجهة الأمر',
          icon: 'building',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLdText('تظهر كما هي في اليومية الرسمية'),
            const SizedBox(height: 10),
            ImdF2(children: [
              ImdLabeled(
                'الجهة المستفيدة',
                ImdFld(
                    controller: _beneficiary,
                    hint: 'الاسم كما سيظهر في التقرير'),
                size: 11,
              ),
              ImdLabeled(
                'جهة الأمر',
                ImdFld(
                  controller: _orderAuthority,
                  hint: 'استحقاق / مكتب القائد',
                  suggestions: Fuel.orderAuthorities,
                ),
                size: 11,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled(
              'الغرض',
              ImdFld(
                  controller: _purpose, hint: 'إصلاح الاتصالات / تشغيل مولد…'),
            ),
          ]),
        ),
        ImdPanel(
          title: 'بيانات الوسيلة والكمية',
          icon: 'truck',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              ImdLabeled(
                'اسم السائق',
                ImdFld(controller: _driver, hint: 'اختياري'),
                size: 11,
              ),
              ImdLabeled(
                'نوع الوسيلة *',
                ImdFld(
                  controller: _vehicle,
                  hint: 'شاص / هايلوكس / مولد',
                  suggestions: vehicles,
                ),
                size: 11,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled(
              _chassisRequired ? 'رقم الشاصي *' : 'رقم الشاصي (اختياري)',
              Row(children: [
                Expanded(
                  child: ImdFld(
                    controller: _chassis,
                    hint: 'يدويًا أو بمسح الكاميرا',
                    onChanged: _onChassis,
                  ),
                ),
                if (ImdScanner.supported) ...[
                  const SizedBox(width: 8),
                  ImdScanButton(controller: _chassis, onScanned: _onChassis),
                ],
              ]),
            ),
            if (_lastForChassis != null) ...[
              const SizedBox(height: 6),
              const ImdLdText(
                  'وُجدت حركة سابقة لهذه المركبة — عُبّئ السائق ونوع '
                  'الوسيلة تلقائيًا إن كانا فارغين.'),
            ],
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  Widget _allocationBox(FuelAllocationRow a) {
    final c = context.imd;
    final err = _allocationError;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.subtle,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        _kv('الوحدة', a.allocation.unitName),
        _kv(
            'مكان الصرف',
            a.allocation.issueLocation.isEmpty
                ? '—'
                : a.allocation.issueLocation),
        _kv('الاستحقاق الأسبوعي', '${nf(Fuel.weeklyOf(a.calc))} ${Fuel.unit}'),
        _kv('الكمية المقررة',
            '${nf(a.allocation.quantityPerPeriod)} ${Fuel.unit}'),
        _kv('المتبقي من الاستحقاق', '${nf(a.remaining)} ${Fuel.unit}',
            strong: true),
        if (err != null) ...[
          const SizedBox(height: 8),
          Text(err, style: TextStyle(fontSize: 12, color: c.danger)),
        ],
      ]),
    );
  }

  Widget _kv(String k, String v, {bool strong = false}) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: c.muted)),
          Text(v,
              style: TextStyle(
                fontSize: 12.5,
                color: strong ? c.accent : c.text,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              )),
        ],
      ),
    );
  }

  List<Widget> _issueLog() {
    final c = context.imd;
    final rows = _search(
        _issues,
        (i) => '${i.refNo} ${i.chassisNo} ${i.driverName} ${i.beneficiaryName} '
            '${i.orderAuthority} ${i.purpose} ${i.warehouse}');
    return [
      ImdPanel(
        title: 'سجل الصرف',
        icon: 'list',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث برقم السند أو الجهة أو الشاصي…',
            onChanged: (_) => setState(() {}),
            actions: [
              ImdButton.outline(
                label: 'طباعة كشف الصرف',
                icon: 'printer',
                small: true,
                onPressed: () {
                  if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                  if (_issues.isEmpty) {
                    showImdToast(context, '✖ لا سندات للطباعة');
                  } else {
                    FuelPrint.issuesReport(_db, rows);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ImdTable(
            empty: 'لا صرف بعد',
            minWidth: 1000,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المستودع'),
              ImdCol('الجهة المستفيدة'),
              ImdCol('جهة الأمر'),
              ImdCol('الوسيلة'),
              ImdCol('الكمية', numeric: true),
              ImdCol('', center: true),
            ],
            pageSize: 100,
            rows: [
              for (final i in rows)
                [
                  Text(i.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(i.date)),
                  ImdChip(FuelType.label(i.fuelType),
                      tone: i.fuelType == FuelType.diesel
                          ? ImdTone.code
                          : ImdTone.info),
                  Text(i.warehouse),
                  Text(i.beneficiaryName.isEmpty ? '—' : i.beneficiaryName),
                  i.source == FuelSource.exceptional
                      ? ImdChip(
                          i.orderAuthority.isEmpty
                              ? 'أمر استثنائي'
                              : i.orderAuthority,
                          tone: ImdTone.pend)
                      : Text(i.orderAuthority.isEmpty
                          ? 'استحقاق'
                          : i.orderAuthority),
                  Text(i.vehicleType.isEmpty ? '—' : i.vehicleType),
                  Text('${nf(i.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () => _printIssue(i)),
                ],
            ],
          ),
        ]),
      ),
    ];
  }

  // ───────────────────────── التوريد

  List<Widget> _supplyForm() => [
        ImdPanel(
          title: 'بيانات التوريد',
          icon: 'download',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _fuelField(),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('تاريخ التوريد *'),
              ImdLabeled(
                'جهة التوريد *',
                ImdFld(controller: _supplier, hint: 'اسم المورد / الجهة'),
                size: 11,
              ),
              _warehouseField('المخزن المستلم *'),
              ImdLabeled(
                'نوع الوسيلة',
                ImdFld(controller: _transport, hint: 'صهريج / شاحنة'),
                size: 11,
              ),
              ImdLabeled('اسم السائق', ImdFld(controller: _driver), size: 11),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip('الرصيد الحالي: ${nf(_available)} ${Fuel.unit}'),
              if (_capacity > 0) ...[
                ImdChip('السعة ${nf(_capacity)} ${Fuel.unit}',
                    tone: ImdTone.off),
                ImdChip(
                  'المتبقي '
                  '${nf(_capacity - _available < 0 ? 0 : _capacity - _available)} '
                  '${Fuel.unit}',
                  tone: ImdTone.info,
                ),
              ],
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  List<Widget> _supplyLog() {
    final c = context.imd;
    final rows = _search(_supplies,
        (s) => '${s.refNo} ${s.supplierName} ${s.driverName} ${s.warehouse}');
    return [
      ImdPanel(
        title: 'آخر التوريدات',
        icon: 'list',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث برقم السند أو الجهة…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ImdTable(
            empty: 'لا توريد بعد',
            minWidth: 900,
            columns: const [
              ImdCol('السند'),
              ImdCol('التاريخ'),
              ImdCol('النوع'),
              ImdCol('المخزن المستلم'),
              ImdCol('جهة التوريد'),
              ImdCol('الوسيلة'),
              ImdCol('الكمية', numeric: true),
              ImdCol('', center: true),
            ],
            pageSize: 100,
            rows: [
              for (final s in rows)
                [
                  Text(s.refNo,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(arDigits(s.date)),
                  ImdChip(FuelType.label(s.fuelType),
                      tone: s.fuelType == FuelType.diesel
                          ? ImdTone.code
                          : ImdTone.info),
                  Text(s.warehouse),
                  Text(s.supplierName.isEmpty ? '—' : s.supplierName),
                  Text(s.transportVehicleType.isEmpty
                      ? '—'
                      : s.transportVehicleType),
                  Text('${nf(s.quantityLiters)} ${Fuel.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () {
                if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                FuelPrint.supplyVoucher(_db, s);
              }),
                ],
            ],
          ),
        ]),
      ),
    ];
  }

  // ───────────────────────── التحويل

  List<Widget> _transferForm() => [
        ImdPanel(
          title: 'سند تحويل مخزني جديد',
          icon: 'swap',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _warehouseField('من مستودع *'),
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
              _fuelField(label: 'الصنف *'),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('التاريخ *'),
              ImdLabeled('السائق', ImdFld(controller: _driver), size: 11),
              ImdLabeled('وسيلة النقل', ImdFld(controller: _transport),
                  size: 11),
            ]),
            const SizedBox(height: 10),
            ImdChipsRow(bottom: 0, children: [
              ImdChip(
                'المتاح في المصدر: ${nf(_available)} ${Fuel.unit}',
                tone: _available <= 0 ? ImdTone.err : ImdTone.ok,
              ),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 2)),
          ]),
        ),
      ];

  List<Widget> _transferLog() {
    final c = context.imd;
    if (_transfers.isEmpty) {
      return const [
        ImdEmptyState.noData(
          title: 'لا توجد تحويلات بعد',
          message: 'استخدم النموذج أعلاه لنقل الرصيد',
        ),
      ];
    }
    return [
      ImdPanel(
        title: 'سجل التحويل',
        icon: 'list',
        child: ImdTable(
          empty: 'لا تحويلات بعد',
          minWidth: 980,
          columns: const [
            ImdCol('السند'),
            ImdCol('التاريخ'),
            ImdCol('النوع'),
            ImdCol('من ← إلى'),
            ImdCol('السائق'),
            ImdCol('الكمية', numeric: true),
            ImdCol('الحالة'),
            ImdCol('', center: true),
          ],
          pageSize: 100,
          rows: [
            for (final t in _transfers)
              [
                Text(t.refNo, style: TextStyle(color: c.muted, fontSize: 12.5)),
                Text(arDigits(t.date)),
                ImdChip(FuelType.label(t.fuelType),
                    tone: t.fuelType == FuelType.diesel
                        ? ImdTone.code
                        : ImdTone.info),
                Text('${t.fromWarehouse} ← ${t.toWarehouse}'),
                Text(t.driverName.isEmpty ? '—' : t.driverName),
                Text('${nf(t.quantityLiters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (FuelRepo.isReverse(t.notes))
                    const ImdChip('عكس', tone: ImdTone.pend),
                  if (FuelRepo.reversedAlready(_transfers, t.refNo))
                    const ImdChip('معكوس', tone: ImdTone.off),
                ]),
                Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                  ImdIconButton(
                      icon: 'printer',
                      tooltip: 'طباعة السند',
                      onPressed: () {
                if (!Perm.of(context).guard(context, 'fuelMoves', 'print')) return;
                FuelPrint.transferVoucher(_db, t);
              }),
                  if (!FuelRepo.isReverse(t.notes) &&
                      !FuelRepo.reversedAlready(_transfers, t.refNo))
                    ImdIconButton(
                        icon: 'undo',
                        tooltip: 'عكس السند',
                        onPressed: () => _reverse(t)),
                ]),
              ],
          ],
        ),
      ),
    ];
  }

  // ───────────────────────── الرصيد الافتتاحي

  List<Widget> _openingForm() => [
        ImdPanel(
          title: 'رصيد افتتاحي جديد',
          icon: 'compass',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdF2(children: [
              _warehouseField('المستودع *'),
              _fuelField(label: 'الصنف *'),
              ImdLabeled(
                'الكمية (${Fuel.unit}) *',
                ImdFld(
                    controller: _qty,
                    number: true,
                    onChanged: (_) => setState(() {})),
                size: 11,
              ),
              _dateField('اعتبارًا من *'),
            ]),
            const SizedBox(height: 10),
            ImdLabeled('ملاحظة', ImdFld(controller: _notes, maxLines: 2)),
            const SizedBox(height: 10),
            const ImdNote(
              'الرصيد الافتتاحي هو ما كان في الخزّان **قبل أن يبدأ '
              'النظام**. ولا يُستعمل لتصحيح فرقٍ بعد التشغيل — ذلك بابه '
              'الجرد، فيبقى له أثرٌ ولجنةٌ وتاريخ.',
            ),
          ]),
        ),
      ];

  List<Widget> _openingLog() {
    final c = context.imd;
    final can = Perm.of(context).writable('fuelMoves');
    return [
      ImdPanel(
        title: 'الأرصدة الافتتاحية',
        icon: 'list',
        child: ImdTable(
          empty: 'لا أرصدة افتتاحية — أدخل أرصدة بداية الفترة لتصح التقارير',
          minWidth: 780,
          columns: const [
            ImdCol('المستودع'),
            ImdCol('الصنف'),
            ImdCol('اعتبارًا من'),
            ImdCol('الرصيد', numeric: true),
            ImdCol('ملاحظة'),
            ImdCol('', center: true),
          ],
          pageSize: 100,
          rows: [
            for (final o in _openings)
              [
                Text(o.warehouse,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ImdChip(FuelType.label(o.fuelType),
                    tone: o.fuelType == FuelType.diesel
                        ? ImdTone.code
                        : ImdTone.info),
                Text(arDigits(o.asOfDate)),
                Text('${nf(o.liters)} ${Fuel.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(o.note.isEmpty ? '—' : o.note,
                    style: TextStyle(color: c.muted)),
                if (can)
                  ImdIconButton(
                      icon: 'trash',
                      tooltip: 'حذف',
                      onPressed: () => _deleteOpening(o))
                else
                  const SizedBox.shrink(),
              ],
          ],
        ),
      ),
    ];
  }

  // ───────────────────────── حقولٌ مشتركة

  Widget _fuelField({String label = 'نوع الصنف *'}) => ImdLabeled(
        label,
        ImdSelect<String>(
          items: [for (final t in FuelType.all) (t, FuelType.label(t))],
          value: _fuelType,
          onChanged: (v) => setState(() {
            _fuelType = v ?? FuelType.petrol;
            _allocationId = '';
          }),
        ),
        size: 11,
      );

  Widget _warehouseField(String label) => ImdLabeled(
        label,
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
      );

  Widget _dateField(String label) => ImdLabeled(
        label,
        ImdDateField(value: _date, onChanged: (v) => setState(() => _date = v)),
        size: 11,
      );

  /// ترشيحٌ نصّي على السجل — البحث في السجل أسرع من تقليب صفحاته.
  List<T> _search<T>(List<T> list, String Function(T) hay) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) => hay(e).toLowerCase().contains(q)).toList();
  }
}
