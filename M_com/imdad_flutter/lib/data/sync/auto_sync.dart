import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import 'lan_sync.dart';
import 'sync_trust.dart';

/// المزامنة التلقائية: تُدار مرة واحدة لعمر التطبيق.
///
/// **لماذا الجهاز يستقبل ويطلب معًا:** المزامنة هنا ليست خادمًا وعملاء، بل
/// أجهزة متكافئة على شبكة الوحدة. لو انتظر كل جهاز أن يبدأ الآخرُ الاستقبالَ
/// لما زامن أحد. فكل جهاز موافق يفتح منفذه للموثوقين، ويطرق أبوابهم في كل
/// دورة — ومن كان مغلقًا اليوم يُسحب منه غدًا.
///
/// **ولماذا الاستقبال هنا بلا رمز:** رمز الأرقام الستة حارسٌ لدقائق يحضرها
/// إنسان، لا لمنفذ مفتوح طول النهار. الحارس في هذا الوضع مفتاح دائم لا يُمنح
/// إلا باقتران يدوي سابق (انظر `SyncSession.fromKey`).
class AutoSyncService with ChangeNotifier {
  AutoSyncService(this.db) : _sync = LanSync(db);

  final AppDatabase db;
  final LanSync _sync;

  Timer? _timer;
  bool _running = false;
  bool _enabled = false;
  bool _paused = false;
  String _status = '';
  DateTime? _lastAt;

  /// هل المزامنة التلقائية مشتغلة على هذا الجهاز؟
  bool get enabled => _enabled;

  /// هل تجري دورة الآن؟ تمنع تداخل دورتين على قاعدة واحدة.
  bool get isRunning => _running;

  /// آخر سطر حالة — يُعرض في الواجهة عند الحاجة.
  String get status => _status;

  DateTime? get lastAt => _lastAt;

  /// يُنادى عند إقلاع التطبيق وبعد كل تغيير في الإعداد.
  ///
  /// آمن للنداء مرارًا: يُعيد ضبط المؤقّت والمنفذ على الحالة المحفوظة ولا
  /// يراكم مؤقّتات.
  Future<void> refresh() async {
    if (_paused) return;
    final store = SyncTrust(db);
    _enabled = await store.isAuto();
    _lastAt = await store.lastSyncAt();
    _timer?.cancel();
    _timer = null;

    if (!_enabled) {
      if (_sync.isTrustedOnly) await _sync.stopReceiving();
      _status = '';
      notifyListeners();
      return;
    }

    // المنفذ لا يُفتح إلا إن كان ثمّ من يُقبل منه: منفذ مفتوح بلا جهاز موثوق
    // بابٌ لا يدخل منه إلا من لا نعرفه.
    final trusted = await store.accepted();
    if (trusted.isNotEmpty && !_sync.isReceiving) {
      try {
        await _sync.startReceiving(trustedOnly: true);
      } catch (e) {
        _status = 'تعذّر فتح منفذ المزامنة: $e';
      }
    }

    final every = await store.interval();
    _timer = Timer.periodic(every, (_) => unawaited(runOnce()));
    notifyListeners();
    await runOnce();
  }

  /// تتنحّى عن المنفذ وتوقف الدورات ما دامت شاشة المزامنة مفتوحة.
  ///
  /// المنفذ واحد على الجهاز: لو بقي الاستقبال التلقائي مفتوحًا لفشل «بدء
  /// الاستقبال» اليدوي بأن المنفذ مشغول — ولبدا للمدير أن المزامنة معطوبة وهي
  /// تعمل. والدورات تتوقف معه حتى لا تتزاحم مع سحب يدوي على قاعدة واحدة.
  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    if (_sync.isTrustedOnly) await _sync.stopReceiving();
    notifyListeners();
  }

  /// تعود إلى حالتها المحفوظة بعد إغلاق شاشة المزامنة.
  Future<void> resume() async {
    _paused = false;
    await refresh();
  }

  /// دورة واحدة الآن. لا تفعل شيئًا إن كانت المزامنة موقوفة أو دورة جارية.
  Future<void> runOnce() async {
    if (!_enabled || _running || _paused) return;
    _running = true;
    notifyListeners();
    try {
      final res = await _sync.autoSync();
      _status = res.message;
      if (res.ok) _lastAt = DateTime.now();
    } catch (e) {
      _status = 'تعثّرت المزامنة التلقائية: $e';
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// يُشغَّل من الواجهة بعد موافقة المدير (سؤال ما بعد التفعيل).
  Future<void> enable() async {
    await SyncTrust(db).setAuto(true);
    await refresh();
  }

  Future<void> disable() async {
    await SyncTrust(db).setAuto(false);
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_sync.stopReceiving());
    super.dispose();
  }
}
