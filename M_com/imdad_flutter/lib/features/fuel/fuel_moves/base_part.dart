part of '../fuel_moves_screen.dart';

/// حالة الشاشة: الحقول والمتحكّمات والقراءة من المستودع والقيمُ المحسوبة منها.
///
/// نقلٌ حرفيّ من `_FuelMovesScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _FuelMovesBase on State<FuelMovesScreen> {
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

}
