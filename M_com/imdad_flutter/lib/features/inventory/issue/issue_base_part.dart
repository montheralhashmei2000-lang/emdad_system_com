part of '../issue_screen.dart';

/// حالة الشاشة: الحقول والمستودعات ومسار المسودة.
///
/// نقلٌ حرفيّ من `_IssueScreenState` — خليطٌ في المكتبة نفسها،
/// فسلوك الشاشة وواجهتها لم يتغيّرا.
mixin _IssueBase on State<IssueScreen> {
  // يُنفَّذ في [_IssueAutosave]؛ مُعلَنٌ هنا لأن الأساس و[_IssueBeneficiary] يستدعيانه.
  void _scheduleAutosave();

  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final MovementsRepo _moves = MovementsRepo(_db);

  String _tab = 'form';

  // ISS
  int _type = 0;
  List<Item> _items = const [];
  List<BeneficiaryUnit> _units = const [];
  List<Warehouse> _whs = const [];
  List<Facility> _facs = const [];
  Map<String, Entitlement> _ents = const {};
  StrengthCalculator? _calc;
  Map<String, double> _whBal = const {};
  double _strength = 0;
  bool _ready = false;
  bool _busy = false;

  // النموذج
  String _wh = '';
  String _date = imdToday();
  String _ref = '';
  String _nextDue = '—';
  Color? _nextDueColor;
  String _parent = '';
  String _ben = '';
  String _fac = '';
  final _custom = TextEditingController();
  String _strDate = imdToday();
  final _days = TextEditingController(text: '1');
  final _notes = TextEditingController();
  final List<_Row> _rows = [];
  Timer? _autosaveTimer;
  DateTime? _autosavedAt;
  bool _restoringAutosave = false;

  // سندات معلّقة داخل الجلسة (تبويب «سند جديد»)
  final List<ImdDocTab<Map<String, dynamic>>> _suspended = [];
  int _tabSeq = 1;
  int _activeTabId = 0;

  ImdScreenActions? _screenActions;

  String get _autosaveUser => context.read<AuthService>().currentUser?.id ?? 'local';

  /// مفتاح التخزين القديم في SharedPreferences (ملفٌّ نصيٌّ مقروء) — للترحيل
  /// والمسح فقط. المسودة الآن في القاعدة المشفّرة ([SettingsRepo.readIssueRecovery]).
  String get _legacyAutosaveKey => 'imdad.issue.recovery.$_autosaveUser';

  late final SettingsRepo _settingsRepo = SettingsRepo(_db);

  Future<void> _clearAutosave() async {
    await _settingsRepo.clearIssueRecovery(_autosaveUser);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyAutosaveKey);
  }

  _Row _newRow({String itemId = '', String unit = '', double? qty, String notes = '', String benUnit = '', bool noAuto = false}) =>
      _Row(itemId: itemId, unit: unit, qty: qty, notes: notes, benUnit: benUnit, noAuto: noAuto, onEdit: _scheduleAutosave);
}
