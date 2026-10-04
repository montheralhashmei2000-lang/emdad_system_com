import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';

/// القفل التلقائي بعد الخمول.
///
/// بعد [minutes] دقيقة بلا حركة فأرة أو لمسة أو مفتاح يُقفل التطبيق بغطاءٍ يطلب
/// كلمة مرور المستخدم الحالي — **دون تسجيل خروج**: الشاشات المفتوحة ومسوّدات
/// الإدخال تبقى كما هي خلف الغطاء، فلا يضيع عملٌ بسبب قهوة.
///
/// الإعداد محلي للجهاز (`SettingsRepo.localOnlyKeys['security']`)، والافتراضي
/// [defaultMinutes]؛ الصفر يعطّل القفل. المعيار الزمني ساعة الجهاز، فاستئناف
/// تطبيق أندرويد بعد ساعة في الخلفية يقفل فورًا عند العودة.
class IdleLock extends ChangeNotifier with WidgetsBindingObserver {
  IdleLock(this._db, {DateTime Function()? clock, this.tick = const Duration(seconds: 10)})
      : _now = clock ?? DateTime.now {
    _lastActivity = _now();
  }

  final AppDatabase _db;
  final DateTime Function() _now;

  /// دورية فحص الخمول. المؤقّت لا يُعاد ضبطه مع كل حركة (مكلف)، بل تُسجَّل آخر
  /// حركة ويُقارَن بها كل [tick].
  final Duration tick;

  static const String settingsKey = 'security';
  static const int defaultMinutes = 15;

  /// الخيارات المعروضة في الإعدادات (دقائق؛ 0 = معطّل).
  static const List<int> choices = [0, 5, 10, 15, 30, 60];

  int _minutes = defaultMinutes;
  bool _locked = false;
  bool _active = false;
  late DateTime _lastActivity;
  Timer? _timer;

  int get minutes => _minutes;
  bool get enabled => _minutes > 0;
  bool get locked => _locked;

  /// يقرأ الإعداد المحفوظ. القيم غير المعروفة تُهمَل إلى الافتراضي.
  Future<void> load() async {
    final raw = (await SettingsRepo(_db).read(settingsKey))['idleLockMinutes'];
    final m = raw is num ? raw.toInt() : defaultMinutes;
    _minutes = m < 0 ? defaultMinutes : m;
    notifyListeners();
  }

  Future<void> setMinutes(int minutes) async {
    _minutes = minutes < 0 ? 0 : minutes;
    final repo = SettingsRepo(_db);
    final map = await repo.read(settingsKey);
    map['idleLockMinutes'] = _minutes;
    await repo.write(settingsKey, map);
    _lastActivity = _now();
    notifyListeners();
  }

  /// يبدأ المراقبة عند تسجيل الدخول.
  void activate() {
    if (_active) return;
    _active = true;
    _lastActivity = _now();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(tick, (_) => checkNow());
  }

  /// يوقف المراقبة ويُزيل القفل عند الخروج.
  void deactivate() {
    if (!_active && !_locked) return;
    _active = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (_locked) {
      _locked = false;
      notifyListeners();
    }
  }

  bool _onKey(KeyEvent event) {
    touch();
    return false; // لا يستهلك المفتاح
  }

  /// نشاط مستخدم. أثناء القفل لا يفتح شيئًا: الفتح بكلمة المرور وحدها.
  void touch() {
    if (!_locked) _lastActivity = _now();
  }

  /// يقفل إن انقضت مهلة الخمول. يعيد هل قُفل الآن.
  bool checkNow() {
    if (!_active || _locked || !enabled) return false;
    if (_now().difference(_lastActivity) < Duration(minutes: _minutes)) return false;
    lockNow();
    return true;
  }

  /// قفلٌ فوري (زرّ «قفل الشاشة»).
  void lockNow() {
    if (!_active || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// بعد التحقق من كلمة المرور.
  void unlock() {
    if (!_locked) return;
    _locked = false;
    _lastActivity = _now();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkNow();
  }

  @override
  void dispose() {
    deactivate();
    super.dispose();
  }
}
