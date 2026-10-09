import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;

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
/// **ولماذا الاستقبال هنا بلا رمز:** رمز الاقتران (٨ أحرف) حارسٌ لدقائق يحضرها
/// إنسان، لا لمنفذ مفتوح طول النهار. الحارس في هذا الوضع مفتاح دائم لا يُمنح
/// إلا باقتران يدوي سابق (انظر `SyncSession.fromKey`).
class AutoSyncService with ChangeNotifier {
  /// [sync] للاختبارات وحدها: منفذٌ خاص بكل اختبار حتى لا يقتسم خادمان منفذًا
  /// واحدًا.
  AutoSyncService(this.db, {LanSync? sync}) : _sync = sync ?? LanSync(db) {
    // أندرويد يجمّد المؤقّتات في الخلفية: جهاز الفرع يُفتح دقيقةً ثم يُطوى،
    // فلا تبلغ دورةُ الربع ساعة أبدًا. العودة إلى الواجهة هي اللحظة التي
    // يكون فيها الجهاز على الشبكة ومعه كهرباء وانتباه — فتُشغَّل دورة.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) unawaited(_onResume());
      },
    );
  }

  final AppDatabase db;
  final LanSync _sync;

  AppLifecycleListener? _lifecycle;

  Timer? _timer;
  bool _running = false;
  bool _enabled = false;
  bool _paused = false;
  String _status = '';
  bool _failed = false;
  DateTime? _lastAt;

  /// المنفذ متنحٍّ لأجل اقتران يدوي — انظر [releasePort].
  bool _portYielded = false;

  /// أقلُّ ما بين دورتي عودةٍ إلى الواجهة: التنقّل بين التطبيقات لا يُطلق
  /// دورةً كل مرة.
  static const Duration resumeThrottle = Duration(minutes: 2);
  DateTime? _lastResumeRun;

  Future<void> _onResume() async {
    if (!_enabled || _paused) return;
    final last = _lastResumeRun;
    if (last != null && DateTime.now().difference(last) < resumeThrottle) return;
    _lastResumeRun = DateTime.now();
    // المنفذ يُفقد مع تجميد العملية، فيُعاد فتحه قبل الدورة.
    await _openPortIfNeeded();
    await runOnce();
  }

  /// هل المزامنة التلقائية مشتغلة على هذا الجهاز؟
  bool get enabled => _enabled;

  /// هل تجري دورة الآن؟ تمنع تداخل دورتين على قاعدة واحدة.
  bool get isRunning => _running;

  /// هل المنفذ مفتوح لأقراننا الموثوقين الآن؟ تقرأه شاشة المزامنة فلا تقول
  /// «الاستقبال متوقف» والجهاز مسموع.
  bool get listening => _sync.isTrustedOnly && _sync.isReceiving;

  /// آخر سطر حالة — يُعرض في الواجهة عند الحاجة.
  String get status => _status;

  /// هل فشلت آخر محاولة (أو تعذّر فتح المنفذ)؟ حالةٌ صريحة — الواجهة لا تستنتجها
  /// من نصّ [status] العربي.
  bool get failed => _failed;

  DateTime? get lastAt => _lastAt;

  /// يُنادى عند إقلاع التطبيق وبعد كل تغيير في الإعداد.
  ///
  /// آمن للنداء مرارًا: يُعيد ضبط المؤقّت والمنفذ على الحالة المحفوظة ولا
  /// يراكم مؤقّتات.
  Future<void> refresh() async {
    final store = SyncTrust(db);
    _enabled = await store.isAuto();
    _lastAt = await store.lastSyncAt();
    _timer?.cancel();
    _timer = null;

    if (!_enabled) {
      if (_sync.isTrustedOnly) await _sync.stopReceiving();
      _status = '';
      _failed = false;
      notifyListeners();
      return;
    }

    // ترميم علاقات اقترنت قبل أن تُكتب الثقة في الاتجاهين — مرة واحدة وبلا
    // أثر إن كانت القائمتان متطابقتين سلفًا.
    await store.mirror();
    await _openPortIfNeeded();

    if (_paused) {
      notifyListeners();
      return;
    }

    _every = await store.interval();
    _arm(_every);
    notifyListeners();
    await runOnce();
  }

  /// الدورة المحفوظة — يُعاد إليها بعد كل نجاح.
  Duration _every = SyncTrust.defaultInterval;

  /// دورةُ إعادة المحاولة بعد فشل: الأجهزة تلتقي على الشبكة في لحظةٍ لا تُعرف
  /// مقدَّمًا (يُفتح الواي‑فاي، يُشغَّل جهاز الإدارة)، وانتظارُ ربع ساعة بعدها
  /// يجعل المزامنة تبدو معطوبة. ودقيقتان على شبكة محلية بلا ثمن.
  static const Duration retryInterval = Duration(minutes: 2);

  void _arm(Duration every) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(runOnce()));
  }

  /// يفتح منفذ الموثوقين إن كان ثمّ من يُقبل منه.
  ///
  /// منفذ مفتوح بلا جهاز موثوق بابٌ لا يدخل منه إلا من لا نعرفه — فيُشترط
  /// قرينٌ في إحدى القائمتين. و[SyncTrust.peers] تُحسب معها: الجهاز الذي
  /// نسحب منه هو نفسه الذي يُرجَّح أن يبدأ دورةً نحونا.
  Future<void> _openPortIfNeeded() async {
    if (!_enabled || _portYielded || _sync.isReceiving) return;
    final store = SyncTrust(db);
    if ((await store.accepted()).isEmpty && (await store.peers()).isEmpty) return;
    try {
      await _sync.startReceiving(trustedOnly: true);
    } catch (_) {
      // محاولةٌ ثانية بعد لحظة: الخروج من شاشة المزامنة يُغلق خادمَها اليدوي
      // ويفتح هذا خادمَه في النفس الواحد، فيتصادمان على المنفذ مرة.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await _sync.startReceiving(trustedOnly: true);
      } catch (e) {
        _status = 'تعذّر فتح منفذ المزامنة: $e';
        _failed = true;
      }
    }
  }

  /// توقف الدورات الدوريّة ما دامت شاشة المزامنة مفتوحة — **ويبقى المنفذ
  /// مفتوحًا**.
  ///
  /// الدورات تتوقف حتى لا تتزاحم مع سحب يدوي على قاعدة واحدة. أما المنفذ فكان
  /// يُغلق معها، وهذا هو ما كان يُعطِّل «زامن الآن»: المشغّل يفتح شاشة المزامنة
  /// على الجهازين ليضغط الزر، فيصمت الجهازان معًا ولا يجد أحدهما الآخر —
  /// «خارج الشبكة» وهما على طاولة واحدة. تنحّي المنفذ صار صريحًا في
  /// [releasePort]، ولا يُطلب إلا للاقتران اليدوي الذي يحتاج رمزًا.
  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// تتنحّى عن المنفذ لأجل «بدء الاستقبال» اليدوي (وضع رمز الاقتران).
  ///
  /// المنفذ واحد على الجهاز: لو بقي استقبال الموثوقين مفتوحًا لفشل الاقتران
  /// اليدوي بأن المنفذ مشغول — ولبدا للمدير أن المزامنة معطوبة وهي تعمل.
  Future<void> releasePort() async {
    _portYielded = true;
    if (_sync.isTrustedOnly) await _sync.stopReceiving();
    notifyListeners();
  }

  /// تستعيد المنفذ بعد إيقاف الاقتران اليدوي، بلا أن تُعيد تشغيل الدورات.
  ///
  /// شاشة المزامنة قد تبقى مفتوحة بعد إيقاف وضع الرمز، فالدورات تبقى موقوفة
  /// ([pause]) ويبقى الجهاز مع ذلك مسموعًا لأقرانه الموثوقين.
  Future<void> reclaimPort() async {
    _portYielded = false;
    await _openPortIfNeeded();
    notifyListeners();
  }

  /// تعود إلى حالتها المحفوظة بعد إغلاق شاشة المزامنة.
  Future<void> resume() async {
    _paused = false;
    _portYielded = false;
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
      _failed = res.failed;
      if (res.ok) _lastAt = DateTime.now();
      // الفشل يقرّب الدورة التالية، والنجاح يعيدها إلى الدورة المحفوظة.
      if (_timer != null) _arm(res.ok ? _every : retryInterval);
    } catch (e) {
      _status = 'تعثّرت المزامنة التلقائية: $e';
      _failed = true;
      if (_timer != null) _arm(retryInterval);
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

  /// إنهاء نظيف قبل إغلاق التطبيق — **ينتظر** إغلاق المقبس والخادم.
  ///
  /// [dispose] يُطلق الإغلاق بلا انتظار، وذلك يناسب تفكيك شجرة الواجهة.
  /// أما إغلاق التطبيق فلا يناسبه: خادمٌ يستمع على منفذ ومقبسُ اكتشافٍ
  /// مفتوح يُبقيان العملية حيّةً بعد اختفاء النافذة، فيظنّ المستخدم أن
  /// التطبيق علّق وقد انتهى شأنه.
  Future<void> shutdown() async {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _sync.stopReceiving();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_sync.stopReceiving());
    super.dispose();
  }
}
