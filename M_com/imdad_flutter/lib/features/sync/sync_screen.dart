import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/sync/auto_sync.dart';
import '../../data/sync/lan_sync.dart';
import '../../data/sync/sync_crypto.dart';
import '../../data/sync/sync_trust.dart';
import '../../domain/access_control.dart';

/// مزامنة الأجهزة عبر الشبكة المحلية، بلا إنترنت.
/// جهاز واحد يعمل «مستقبِلًا» ويعرض رمز اقتران، وبقية الأجهزة تقترن به ثم
/// ترسل إليه أو تسحب منه.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, this.firstRun = false, this.onReceived});

  /// تجهيز جهاز جديد قبل تسجيل الدخول: الشاشة نفسها، بلا حارس الصلاحيات،
  /// والحسابات مشمولة في السحب لأن جلبها هو الغرض كله.
  final bool firstRun;

  /// يُنادى بعد أول سحب ناجح — عنده صار على الجهاز حسابات يدخل بها.
  final VoidCallback? onReceived;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  // يُنشأ في initState لا بتهيئة كسولة: dispose يستدعي _sync، وقراءة context
  // أثناء إزالة الشاشة ترمي خطأ إذا لم تُستخدم المزامنة قبل مغادرتها.
  late final LanSync _sync;

  /// خدمة المزامنة التلقائية — تُلتقط في initState لأن dispose يحتاجها.
  late final AutoSyncService _auto0;

  final _host = TextEditingController();
  final _code = TextEditingController();

  /// الجهاز المقترن — بدونه لا يُقبل إرسال ولا سحب.
  SyncPeer? _paired;
  final List<String> _log = [];
  List<({String address, String device, String id})> _found = const [];
  String _addresses = '';
  bool _receiving = false;
  bool _busy = false;
  bool _includeUsers = false;

  /// المزامنة التلقائية: محفوظة في قاعدة البيانات لا في الذاكرة، فهي قرار
  /// للجهاز لا لهذه الشاشة.
  bool _auto = false;
  List<TrustedPeer> _trusted = const [];
  DateTime? _lastAuto;

  @override
  void initState() {
    super.initState();
    _sync = LanSync(context.read<AppDatabase>());
    _auto0 = context.read<AutoSyncService>();
    _includeUsers = widget.firstRun;
    // المنفذ واحد: تتنحّى المزامنة التلقائية ما دامت هذه الشاشة مفتوحة، وتعود
    // إلى حالتها المحفوظة عند الخروج منها.
    unawaited(_auto0.pause());
    _loadAddresses();
    _loadTrust();
  }

  Future<void> _loadTrust() async {
    final store = SyncTrust(context.read<AppDatabase>());
    final auto = await store.isAuto();
    final peers = await store.peers();
    final last = await store.lastSyncAt();
    if (!mounted) return;
    setState(() {
      _auto = auto;
      _trusted = peers;
      _lastAuto = last;
    });
  }

  @override
  void dispose() {
    _sync.stopReceiving();
    // تُقرأ من حقل محفوظ لا من السياق: السياق لا يُقرأ بعد بدء الإزالة.
    unawaited(_auto0.resume());
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    final list = await LanSync.localAddresses();
    if (mounted) setState(() => _addresses = list.join('، '));
  }

  bool _can(String action) {
    // جهاز لم يصله حساب بعد لا يوجد فيه من يملك صلاحية: الحارس هنا هو رمز
    // الاقتران المعروض على شاشة جهاز الإدارة، لا جدول الصلاحيات الفارغ.
    if (widget.firstRun) return true;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return false;
    final perms = auth.permissionsOf(user).map(
          (k, v) => MapEntry(k, (v as Map).map((a, b) => MapEntry(a.toString(), b == true))),
        );
    return AccessControl.can(
      isAdmin: user.role == 'admin',
      permissions: perms,
      page: 'settings',
      action: action,
    );
  }

  void _note(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)} — $message');
      if (_log.length > 40) _log.removeLast();
    });
  }

  Future<void> _toggleReceiving() async {
    if (_receiving) {
      await _sync.stopReceiving();
      setState(() => _receiving = false);
      _note('أُوقف الاستقبال');
      return;
    }
    setState(() => _busy = true);
    try {
      final addresses = await _sync.startReceiving(onEvent: _note);
      if (!mounted) return;
      setState(() {
        _receiving = true;
        _addresses = addresses;
      });
    } catch (e) {
      _note('تعذّر فتح المنفذ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() async {
    setState(() => _busy = true);
    _note('جارٍ البحث عن أجهزة مستقبِلة…');
    final found = await _sync.discover();
    if (!mounted) return;
    setState(() {
      _found = found;
      _busy = false;
    });
    _note(found.isEmpty ? 'لم يُعثر على أجهزة' : 'وُجد ${found.length} جهازًا');
  }

  /// الاقتران: الرمز المعروض على الجهاز المستقبِل يُدخل هنا فيُشتق منه مفتاح
  /// الجلسة. بدونه لا يستجيب الجهاز الآخر لأي طلب بيانات.
  Future<void> _pair() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      showImdToast(context, '✖ اكتب عنوان الجهاز المستقبِل', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await _sync.pair(host, _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _paired = res.peer;
    });
    _note(res.ok
        ? 'اقتران ناجح مع ${res.peer!.info.deviceName} — '
            'بصمة المفتاح ${res.peer!.session.fingerprint}'
        : res.message);
    if (!res.ok) {
      showImdToast(context, '✖ ${res.message}', error: true);
      return;
    }
    // الاقتران اليدوي هو اللحظة الوحيدة التي يحضرها إنسان، فمنه يُؤخذ المفتاح
    // الدائم. تأجيله إلى ضغطة زر ثانية يعني أن أحدًا لن يضغطها.
    if (_auto) await _grantTrust(res.peer!);
  }

  /// تحويل الاقتران المؤقت إلى ثقة دائمة على الجهازين.
  Future<void> _grantTrust(SyncPeer peer) async {
    final granted = await _sync.trust(peer);
    if (!mounted) return;
    if (granted == null) {
      _note('تعذّر تثبيت الاقتران الدائم — الجهاز الآخر لم يقبل المنح');
      return;
    }
    await _loadTrust();
    if (!mounted) return;
    _note('ثُبّت الاقتران مع ${granted.name.isEmpty ? granted.deviceId : granted.name} — '
        'لن يُطلب رمز بعد اليوم');
  }

  /// الاقتران صالح فقط للعنوان المكتوب الآن ولم تنتهِ مدته.
  SyncPeer? get _peer {
    final p = _paired;
    if (p == null || p.isExpired) return null;
    return p.host == _host.text.trim() ? p : null;
  }

  Future<void> _push() async {
    final peer = _peer;
    if (peer == null) {
      showImdToast(context, '✖ اقترن بالجهاز أولًا برمز الاقتران المعروض عليه', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await _sync.push(peer, includeUsers: _includeUsers);
    if (!mounted) return;
    setState(() => _busy = false);
    _note(res.ok ? 'إرسال: ${res.message}' : res.message);
    showImdToast(context, res.ok ? '✔ ${res.message}' : '✖ ${res.message}', error: !res.ok);
  }

  Future<void> _pull() async {
    final peer = _peer;
    if (peer == null) {
      showImdToast(context, '✖ اقترن بالجهاز أولًا برمز الاقتران المعروض عليه', error: true);
      return;
    }
    final confirmed = await imdConfirm(
      context,
      'ستُدمج بيانات «${peer.info.deviceName}» مع بياناتك: عند اختلاف النسختين يفوز '
      'التعديل الأحدث، والجديد يُضاف، وما حُذف هناك يُحذف هنا.',
      ok: 'سحب ودمج',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    final res = await _sync.pull(peer, includeUsers: _includeUsers);
    if (!mounted) return;
    setState(() => _busy = false);
    _note(res.ok ? 'سحب: ${res.message}' : res.message);
    showImdToast(context, res.ok ? '✔ ${res.message}' : '✖ ${res.message}', error: !res.ok);
    if (res.ok && widget.firstRun) widget.onReceived?.call();
  }

  /// دورة تلقائية الآن، بلا انتظار المؤقّت — لتأكيد أن الإعداد يعمل فعلًا.
  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final res = await _sync.autoSync(onEvent: _note);
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadTrust();
    if (!mounted) return;
    _note(res.message);
    showImdToast(context, res.ok ? '✔ ${res.message}' : '✖ ${res.message}', error: !res.ok);
    if (res.ok && widget.firstRun) widget.onReceived?.call();
  }

  Future<void> _setAuto(bool on) async {
    await SyncTrust(context.read<AppDatabase>()).setAuto(on);
    if (!mounted) return;
    setState(() => _auto = on);
    _note(on
        ? 'شُغّلت المزامنة التلقائية — اقترن بجهاز الإدارة مرة واحدة ليثبت الاقتران'
        : 'أُوقفت المزامنة التلقائية');
  }

  Future<void> _forget(TrustedPeer peer) async {
    final ok = await imdConfirm(
      context,
      'سيُنسى الجهاز «${peer.name.isEmpty ? peer.deviceId : peer.name}» فلا يزامن تلقائيًا '
      'ولا يُقبل منه طلب. يحتاج اقترانًا برمز من جديد. متابعة؟',
      ok: 'نسيان',
      danger: true,
    );
    if (!ok || !mounted) return;
    await SyncTrust(context.read<AppDatabase>()).forget(peer.deviceId);
    await _loadTrust();
  }

  @override
  Widget build(BuildContext context) {
    if (!_can(PermAction.view)) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'مزامنة الأجهزة', icon: 'swap'),
        ImdNote('👁 المزامنة متاحة لمن يملك صلاحية الإعدادات.'),
      ]);
    }
    final editable = _can(PermAction.edit);

    return ImdPage(children: [
      ImdPageTitle(
        title: widget.firstRun ? 'تجهيز هذا الجهاز' : 'مزامنة الأجهزة',
        icon: 'swap',
        subtitle: widget.firstRun
            ? 'هذا الجهاز مفعَّل ولا حساب عليه بعد. شغّل «بدء الاستقبال» على جهاز '
                'الإدارة، ثم اكتب عنوانه ورمز الاقتران هنا واسحب البيانات — تصل '
                'الحسابات معها فتستطيع الدخول.'
            : 'نقل البيانات بين أجهزة الوحدة عبر الشبكة المحلية بلا إنترنت: '
                'جهاز واحد يستقبل، والبقية تقترن به برمز ثم ترسل إليه أو تسحب منه.',
      ),
      _autoPanel(editable),
      const SizedBox(height: 12),
      ImdGrid2(children: [
        _receiverPanel(editable, _sync.session),
        _peerPanel(editable, _peer),
      ]),
      const SizedBox(height: 12),
      ImdPanel(
        title: 'سجل المزامنة',
        icon: 'activity',
        child: _log.isEmpty
            ? const ImdEmptyBox('لا توجد أحداث بعد')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final l in _log) _logLine(l)],
              ),
      ),
      const SizedBox(height: 12),
      const ImdNote(
        'لا يتصل جهاز بجهاز إلا برمز الاقتران المعروض على المستقبِل: منه يُشتق مفتاح '
        'تُوقَّع به الطلبات وتُشفَّر الحمولة، ولا يعبر المفتاح الشبكة. المنفذ يُغلق وحده '
        'بانتهاء مدة الجلسة أو بعد خمس محاولات فاشلة.',
      ),
      const SizedBox(height: 8),
      const ImdNote(
        'الدمج يعتمد معرّف كل سجل: عند اختلاف النسختين يفوز التعديل الأحدث لا آخر من '
        'زامن، والحذف ينتقل بين الأجهزة فلا يعود المحذوف — إلا إذا عُدّل في الجهاز '
        'الآخر بعد حذفه هنا.',
      ),
    ]);
  }

  /// لوحة المزامنة التلقائية — المفتاح والأجهزة الموثوقة وآخر دورة.
  ///
  /// موضعها فوق اللوحتين عن قصد: الاقتران اليدوي وسيلة لبلوغها لا غاية، فمن
  /// شغّلها مرة لم يعد يفتح هذه الشاشة أصلًا.
  Widget _autoPanel(bool editable) {
    final c = context.imd;
    return ImdPanel(
      title: 'المزامنة التلقائية',
      icon: 'refresh',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdCheckbox(
          value: _auto,
          label: 'زامن هذا الجهاز تلقائيًا مع الأجهزة الموثوقة',
          onChanged: editable ? _setAuto : null,
        ),
        const SizedBox(height: 8),
        Text(
          _trusted.isEmpty
              ? 'لم يُوثَّق جهاز بعد. اقترن بجهاز الإدارة مرة واحدة برمز الاقتران '
                  'وهذه الخانة مفعّلة، فيُحفظ مفتاح دائم على الجهازين ولا يُطلب '
                  'الرمز بعدها أبدًا.'
              : 'تجري دورة عند فتح التطبيق ثم كل '
                  '${SyncTrust.defaultInterval.inMinutes} دقيقة: تسحب الجديد وترسل '
                  'ما تغيّر هنا، والحسابات معها.',
          style: TextStyle(fontSize: 12.5, height: 1.8, color: c.muted),
        ),
        if (_trusted.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final p in _trusted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: ImdChipsRow(children: [
                    ImdChip(p.name.isEmpty ? p.deviceId : p.name, tone: ImdTone.ok),
                    ImdChip(p.deviceId, tone: ImdTone.code),
                    if (p.host.isNotEmpty) ImdChip(p.host, tone: ImdTone.info),
                  ]),
                ),
                ImdButton.outline(
                  label: 'نسيان',
                  icon: 'trash',
                  small: true,
                  onPressed: editable ? () => _forget(p) : null,
                ),
              ]),
            ),
        ],
        if (_lastAuto != null) ...[
          const SizedBox(height: 6),
          Text(
            'آخر مزامنة تلقائية: ${_lastAuto!.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(
            label: 'زامن الآن',
            icon: 'refresh',
            busy: _busy,
            onPressed: editable && _trusted.isNotEmpty ? _syncNow : null,
          ),
        ),
      ]),
    );
  }

  /// لوحة «هذا الجهاز مستقبِل» — العنوان وحالة الاستقبال ورمز الاقتران.
  Widget _receiverPanel(bool editable, SyncSession? session) {
    final c = context.imd;
    return ImdPanel(
      title: 'هذا الجهاز مستقبِل',
      icon: 'radio',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          ImdChip(
            _receiving ? 'يستقبل على المنفذ ${_sync.port}' : 'الاستقبال متوقف',
            tone: _receiving ? ImdTone.ok : ImdTone.off,
          ),
          if (_addresses.isNotEmpty) ImdChip('العنوان: $_addresses', tone: ImdTone.code),
        ]),
        const SizedBox(height: 10),
        Text(
          _receiving
              ? 'أملِ رمز الاقتران على مشغّل الجهاز الآخر، ثم دعه يرسل إليك أو يسحب منك.'
              : 'شغّل الاستقبال على جهاز واحد فقط، ثم أرسل إليه من البقية.',
          style: TextStyle(fontSize: 12.5, height: 1.8, color: c.muted),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(
            label: _receiving ? 'إيقاف الاستقبال' : 'بدء الاستقبال',
            icon: _receiving ? 'x' : 'radio',
            kind: _receiving ? ImdBtnKind.danger : ImdBtnKind.primary,
            busy: _busy,
            onPressed: editable ? _toggleReceiving : null,
          ),
        ),
        // رمز الاقتران يُقرأ من هذه الشاشة ويُملى على مشغّل الجهاز الآخر.
        if (_receiving && session != null) ...[
          const SizedBox(height: 12),
          _PairingCode(session: session),
        ],
      ]),
    );
  }

  /// لوحة «الاتصال بجهاز آخر» — البحث والاقتران ثم الإرسال أو السحب.
  Widget _peerPanel(bool editable, SyncPeer? peer) {
    return ImdPanel(
      title: 'الاتصال بجهاز آخر',
      icon: 'link',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdLabeled(
          'عنوان الجهاز المستقبِل',
          Row(children: [
            Expanded(child: ImdFld(controller: _host, hint: 'مثال: 192.168.1.20')),
            const SizedBox(width: 8),
            ImdButton.outline(label: 'بحث', icon: 'search', onPressed: _busy ? null : _discover),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          'زر «بحث» لا يجد إلا أجهزة الشبكة نفسها — نداء البحث لا يعبر الراوتر. '
          'أما فرعٌ في موقع آخر فاكتب عنوانه في الشبكة الافتراضية (VPN) يدويًا: '
          'يُحفظ مع الاقتران الدائم وتستعمله المزامنة التلقائية بعدها وحدها.',
          style: TextStyle(fontSize: 12, height: 1.7, color: context.imd.muted),
        ),
        if (_found.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _found)
                ImdButton.outline(
                  label: '${d.device.isEmpty ? d.id : d.device} · ${d.address}',
                  icon: 'monitor',
                  small: true,
                  onPressed: () => setState(() => imdSetText(_host, d.address)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        ImdLabeled(
          'رمز الاقتران (٦ أرقام)',
          Row(children: [
            SizedBox(width: 150, child: ImdFld(controller: _code, number: true)),
            const SizedBox(width: 8),
            ImdButton(
              label: 'اقتران',
              icon: 'link',
              busy: _busy,
              onPressed: editable ? _pair : null,
            ),
          ]),
        ),
        if (peer != null) ...[
          const SizedBox(height: 10),
          ImdChipsRow(children: [
            ImdChip('مقترن بـ ${peer.info.deviceName}', tone: ImdTone.ok),
            ImdChip('بصمة ${peer.session.fingerprint}', tone: ImdTone.code),
            ImdChip('${peer.info.records} سجلًا لديه', tone: ImdTone.info),
          ]),
        ],
        const SizedBox(height: 10),
        ImdCheckbox(
          value: _includeUsers,
          label: 'تضمين حسابات المستخدمين (عند تجهيز جهاز جديد فقط)',
          onChanged: editable ? (v) => setState(() => _includeUsers = v) : null,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ImdButton(
            label: 'إرسال بياناتي إليه',
            icon: 'upload',
            busy: _busy,
            onPressed: editable ? _push : null,
          ),
          ImdButton.outline(
            label: 'سحب بياناته إليّ',
            icon: 'download',
            onPressed: editable && !_busy ? _pull : null,
          ),
        ]),
      ]),
    );
  }

  Widget _logLine(String text) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.faint, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, height: 1.6, color: c.text2)),
        ),
      ]),
    );
  }
}

/// رمز الاقتران على الجهاز المستقبِل — يُقرأ بصوت عالٍ أو يُملى على المشغّل الآخر.
class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.session});

  final SyncSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.accentSoft,
        border: Border.all(color: c.ring),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('رمز الاقتران', style: TextStyle(fontSize: 12.5, color: c.muted)),
        const SizedBox(height: 2),
        Text(
          session.code,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
            color: c.accent,
          ),
        ),
        Text(
          'بصمة المفتاح ${session.fingerprint} — تنتهي الجلسة '
          '${TimeOfDay.fromDateTime(session.expiresAt).format(context)}',
          style: TextStyle(fontSize: 12, height: 1.7, color: c.muted),
        ),
      ]),
    );
  }
}
