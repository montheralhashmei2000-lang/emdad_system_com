import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/device_activation.dart';
import '../../core/security/esign.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/sync/auto_sync.dart';
import '../../data/sync/sync_trust.dart';
import '../home/home_shell.dart';
import '../sync/sync_screen.dart';
import '../inventory/doc_kit.dart' show ImdReadonlyField;

/// هل يُعرض لهذا الجهاز طريقُ استقبال الحسابات بالمزامنة؟
///
/// **التفعيل شرط لا زينة.** المزامنة تسلّم الحسابات والبيانات كاملة، فلو فُتحت
/// لجهاز غير مفعَّل لصار رمز الاقتران وحده بابًا إلى النظام — ولسقط معنى بطاقة
/// التفعيل الموقَّعة من الإدارة. ومن يقترن اليوم بلا رمز تفعيل يملك غدًا نسخة
/// من بيانات الوحدة بلا أن يأذن له أحد.
///
/// وجهاز الإدارة لا يحتاجه: هو يُنشئ حسابه بنفسه ([canBootstrap]).
bool showsReceiveAccounts({
  required bool activated,
  required bool hasUsers,
  required bool canBootstrap,
}) =>
    activated && !hasUsers && !canBootstrap;

/// تفعيل الأجهزة — إدخال رمز التفعيل على جهاز الفرع، وإصداره من جهاز الإدارة.
///
/// الرمز موقَّع بـECDSA ويُملى هاتفيًا أو يُمسح من QR، فلا يحتاج إنترنت إطلاقًا
/// (انظر [DeviceActivation]).
class DeviceActivationScreen extends StatefulWidget {
  const DeviceActivationScreen({super.key, this.standalone = false, this.onActivated});

  /// مستقلة قبل تسجيل الدخول (جهاز جديد غير مفعَّل) — بلا زر رجوع للإعدادات.
  final bool standalone;

  final VoidCallback? onActivated;

  @override
  State<DeviceActivationScreen> createState() => _DeviceActivationScreenState();
}

class _DeviceActivationScreenState extends State<DeviceActivationScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final DeviceActivation _act = DeviceActivation(_db);
  late final AuthService _auth = context.read<AuthService>();

  final _token = TextEditingController();
  final _adminUser = TextEditingController();
  final _adminPass = TextEditingController();
  final _adminPass2 = TextEditingController();
  final _ownerKey = TextEditingController();
  final _targetDevice = TextEditingController();
  final _branch = TextEditingController();

  String _deviceId = '';
  bool _fresh = false; // لا حساب مدير مُهيّأ محليًا
  bool _hasUsers = false; // أي حساب على الجهاز، ولو وصل بالمزامنة
  bool _activated = false; // بطاقة تفعيل سارية على هذا الجهاز
  String _issued = '';
  bool _canIssue = false;
  bool _isMaster = false;
  bool _loading = true;
  bool _busy = false;
  ActivationState? _state;
  int _months = 12;
  DeviceRole _role = DeviceRole.branch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_token, _targetDevice, _branch, _adminUser, _adminPass, _adminPass2, _ownerKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final id = await _act.deviceId();
    final state = await _act.current();
    final canIssue = await _act.canIssue();
    final isMaster = await _act.isMaster();
    final fresh = await _auth.needsBootstrap();
    final hasUsers = await _auth.hasAnyUser();
    final activated = await _act.isActivated();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
      _state = state;
      _activated = activated;
      _canIssue = canIssue;
      _isMaster = isMaster;
      _fresh = fresh;
      _hasUsers = hasUsers;
      _loading = false;
    });
  }

  Future<void> _activate() async {
    final raw = _token.text.trim();
    if (raw.isEmpty) {
      showImdToast(context, '✖ أدخل رمز التفعيل', error: true);
      return;
    }
    setState(() => _busy = true);
    final state = await _act.activate(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = state;
    });
    showImdToast(context, state.ok ? '✔ ${state.reason}' : '✖ ${state.reason}', error: !state.ok);
    if (!state.ok) return;
    // الدور لا يُعرف إلا بعد قبول الرمز، ولوحة «تهيئة جهاز الإدارة» معلَّقة عليه:
    // بلا إعادة القراءة هذه يبقى _isMaster على قيمته قبل التفعيل (false) فلا
    // تظهر اللوحة، ويخرج المدير إلى شاشة دخول بلا حساب واحد.
    await _load();
    if (!mounted) return;
    await _offerAutoSync();
    if (!mounted) return;
    widget.onActivated?.call();
  }

  /// سؤال ما بعد التفعيل: أتُزامن هذا الجهاز نفسه؟
  ///
  /// موضعه هنا لا في الإعدادات لأنه اللحظة الوحيدة التي يقف فيها المدير أمام
  /// الجهاز الجديد. ولا يُسأل مرتين: من أجاب مرة يغيّر جوابه من شاشة المزامنة.
  Future<void> _offerAutoSync() async {
    final store = SyncTrust(_db);
    if (await store.isAuto()) return;
    if (!mounted) return;
    final yes = await imdConfirm(
      context,
      'هل تشغّل المزامنة التلقائية على هذا الجهاز؟\n\n'
      'بعد اقتران واحد برمز من جهاز الإدارة، يزامن الجهاز نفسه كل '
      '${SyncTrust.defaultInterval.inMinutes} دقيقة على شبكة الوحدة: تصل الحسابات '
      'والبيانات وتُرسل تعديلاته بلا أن يفتح أحد شاشة المزامنة.',
      ok: 'نعم، زامن تلقائيًا',
      cancel: 'لاحقًا',
    );
    if (!mounted) return;
    if (yes) {
      await context.read<AutoSyncService>().enable();
      if (!mounted) return;
      showImdToast(context, '✔ شُغّلت المزامنة التلقائية — بقي اقتران واحد برمز');
    }
  }

  /// بوابة المزامنة موصولة ببوابة التفعيل: جهاز مفعَّل بلا حسابات يُفتح له
  /// الاقتران من هنا مباشرة، ولا يُترك أمام شاشة دخول فارغة.
  Future<void> _receiveAccounts() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: SyncScreen(
            firstRun: true,
            onReceived: () {
              Navigator.of(context).pop();
              widget.onActivated?.call();
            },
          ),
        ),
      ),
    ));
    if (!mounted) return;
    await _load();
  }

  Future<void> _scan() async {
    final v = await ImdScanner.scan(context);
    if (v == null || v.isEmpty) return;
    imdSetText(_token, v);
    await _activate();
  }

  Future<void> _issue() async {
    final device = _targetDevice.text.trim().toUpperCase();
    if (device.length != 8) {
      showImdToast(context, '✖ معرّف الجهاز ثمانية أحرف', error: true);
      return;
    }
    setState(() => _busy = true);
    final token = await _act.issue(
      deviceId: device,
      branch: _branch.text.trim(),
      role: _role,
      expiresAt: DateTime.now().add(Duration(days: 30 * _months)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _issued = token ?? '';
    });
    if (token == null) {
      showImdToast(context, '✖ لا يوجد مفتاح إصدار على هذا الجهاز — استورده أولًا', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'تفعيل الأجهزة', icon: 'shield'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    // الإصدار يحتاج المفتاح الخاص على هذا الجهاز، لا مجرد صلاحية مدير.
    final canIssue = _canIssue;

    return ImdPage(children: [
      if (!widget.standalone)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ImdButton.outline(
              label: 'رجوع إلى الإعدادات',
              icon: 'arrow-left',
              small: true,
              onPressed: () => context.read<ImdNav>().go('settings'),
            ),
          ),
        ),
      const ImdPageTitle(
        title: 'تفعيل الأجهزة',
        icon: 'shield',
        subtitle: 'لا يعمل جهاز في النظام إلا برمز تفعيل موقَّع من الإدارة. '
            'الرمز يُملى هاتفيًا أو يُمسح من QR — ولا يحتاج إنترنت.',
      ),
      _thisDevice(),
      const SizedBox(height: 12),
      _enterToken(),
      // جهاز الفرع **المفعَّل** ينتظر حساباته من المزامنة، فيُقال له ذلك صراحة
      // بدل أن يُترك أمام شاشة دخول لا حساب خلفها. وغير المفعَّل لا يرى إلا
      // خانة الرمز فوق: لا مزامنة قبل بطاقة تفعيل موقَّعة.
      if (showsReceiveAccounts(
        activated: _activated,
        hasUsers: _hasUsers,
        canBootstrap: _canBootstrap,
      )) ...[
        const SizedBox(height: 12),
        _awaitingAccounts(),
      ],
      // إنشاء الحساب لا يظهر إلا على جهاز الإدارة وبلا حساب مدير سابق:
      // إمّا حمل رمزًا بدور الإدارة، أو كان عليه مفتاح المالك الخاص.
      if (_fresh && _canBootstrap) ...[
        const SizedBox(height: 12),
        _masterSetup(),
      ],
      // متاحة دائمًا عن قصد: حيازة المفتاح الخاص **هي** إثبات الملكية، والمفتاح
      // الخاطئ يُرفض. لو خُبّئت خلف «جهاز إدارة» لاستحال تفعيل الجهاز الأول:
      // الإدارة تحتاج رمزًا، والرمز يحتاج المفتاح، والمفتاح يحتاج هذه اللوحة.
      const SizedBox(height: 12),
      _ownerKeyPanel(),
      if (canIssue) ...[
        const SizedBox(height: 12),
        _issuer(),
      ],
    ]);
  }

  /// هل يحقّ لهذا الجهاز إنشاء حساب المدير الأول؟
  ///
  /// رمز بدور الإدارة، **أو** حيازة مفتاح المالك الخاص. الثانية ليست تساهلًا:
  /// من يملك المفتاح يستطيع أن يصدر لنفسه رمز إدارة في نفس الشاشة، فاشتراط
  /// الرمز عليه لا يزيد حماية — بل يصنع حلقة مقفلة يعلق فيها الجهاز الأول.
  bool get _canBootstrap => _isMaster || _canIssue;

  /// جهاز فرع مفعَّل بلا حسابات — الدخول مستحيل حتى تصل الحسابات بالمزامنة،
  /// فالمزامنة تُفتح من هنا بدل إحالة المستخدم إلى شاشة لا يبلغها إلا بالدخول.
  Widget _awaitingAccounts() => ImdPanel(
        title: 'لا توجد حسابات على هذا الجهاز',
        icon: 'users',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdNote(
            'الجهاز لا يُنشئ حسابات لنفسه. تصل الحسابات من جهاز الإدارة عبر '
            '**المزامنة المحلية**: شغّل «بدء الاستقبال» هناك، ثم اسحبها من هنا '
            'وادخل بحسابك المعتاد.\n\n'
            'إن كان هذا هو جهاز الإدارة نفسه فاستورد مفتاح المالك أدناه، أو أدخل '
            'رمز تفعيل بدور الإدارة، لتظهر لوحة تهيئة حساب المدير.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
              label: 'استقبال الحسابات بالمزامنة',
              icon: 'swap',
              onPressed: _receiveAccounts,
            ),
          ),
        ]),
      );

  Widget _thisDevice() {
    final c = context.imd;
    final state = _state;
    return ImdPanel(
      title: 'هذا الجهاز',
      icon: 'monitor',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ImdChipsRow(children: [
          if (state == null)
            const ImdChip('غير مفعَّل', tone: ImdTone.pend)
          else
            ImdChip(state.reason, tone: state.ok ? ImdTone.ok : ImdTone.err),
          if (state?.branch.isNotEmpty == true) ImdChip(state!.branch, tone: ImdTone.info),
          if (state?.expiresAt != null)
            ImdChip('حتى ${state!.expiresAt!.toIso8601String().substring(0, 10)}',
                tone: ImdTone.code),
        ]),
        const SizedBox(height: 12),
        // يُتلى على المدير هاتفيًا، والبصمة تؤكد صحة ما سُمع.
        ImdLabeled(
          'معرّف هذا الجهاز (اتلُه على الإدارة)',
          ImdReadonlyField(text: '$_deviceId · ${DeviceActivation.checksum(_deviceId)}'),
        ),
        const SizedBox(height: 6),
        Text(
          'الرقم الأخير بعد النقطة بصمة تأكيد — إن اختلفت عند الإدارة فقد سُمع المعرّف خطأً.',
          style: TextStyle(fontSize: 12, height: 1.7, color: c.muted),
        ),
      ]),
    );
  }

  Widget _enterToken() => ImdPanel(
        title: 'إدخال رمز التفعيل',
        icon: 'key',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdLabeled('الرمز', ImdFld(controller: _token, hint: 'IMDACT1|…')),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ImdButton(label: 'تفعيل', icon: 'check', busy: _busy, onPressed: _activate),
            if (ImdScanner.supported)
              ImdButton.outline(label: 'مسح QR', icon: 'camera', onPressed: _scan),
          ]),
        ]),
      );


  /// إنشاء حساب المدير ومفتاح التوقيع على جهاز الإدارة — مرة واحدة.
  Future<void> _setupMaster() async {
    final user = _adminUser.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_.]{3,20}$').hasMatch(user)) {
      showImdToast(context, '✖ اسم المستخدم: ٣-٢٠ حرفًا إنجليزيًا/أرقام/نقطة/شرطة', error: true);
      return;
    }
    if (_adminPass.text.length < 6) {
      showImdToast(context, '✖ كلمة المرور ٦ أحرف على الأقل', error: true);
      return;
    }
    if (_adminPass.text != _adminPass2.text) {
      showImdToast(context, '✖ كلمتا المرور غير متطابقتين', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.createAdmin(
            username: user,
            password: _adminPass.text,
            name: user,
          );
      // مفتاح توقيع المستندات (غير مفتاح المالك) يُهيَّأ هنا للمدير.
      await ESign(_db).ensureKey();
      if (!mounted) return;
      showImdToast(context, '✔ جُهّز جهاز الإدارة — أنشئ باقي الحسابات من شاشة المستخدمين');
      widget.onActivated?.call();
    } on ArgumentError catch (e) {
      if (mounted) showImdToast(context, '✖ ${e.message}', error: true);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _masterSetup() => ImdPanel(
        title: 'تهيئة جهاز الإدارة',
        icon: 'users',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdNote('استعمل هذا القسم على **جهازك أنت** وحده. ينشئ حساب المدير '
              'ومفتاح التوقيع الذي تُصدَر به رموز تفعيل بقية الأجهزة. أجهزة الفروع '
              'تُفعَّل برمز وتستقبل حساباتها بالمزامنة، ولا تنشئ حسابات.'),
          const SizedBox(height: 12),
          ImdLabeled('اسم المستخدم', ImdFld(controller: _adminUser)),
          const SizedBox(height: 10),
          ImdLabeled('كلمة المرور', ImdFld(controller: _adminPass, obscure: true)),
          const SizedBox(height: 10),
          ImdLabeled('تأكيد كلمة المرور', ImdFld(controller: _adminPass2, obscure: true)),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ImdButton(
              label: 'تهيئة جهاز الإدارة',
              icon: 'shield',
              busy: _busy,
              onPressed: _setupMaster,
            ),
          ),
        ]),
      );


  /// استيراد مفتاح المالك الخاص — به وحده تُصدَر رموز تفعيل الأجهزة.
  Widget _ownerKeyPanel() => ImdPanel(
        title: 'مفتاح إصدار التفعيل',
        icon: 'key',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdNote(_canIssue
              ? '✔ المفتاح موجود على هذا الجهاز — يمكنك إصدار رموز التفعيل.'
              : 'الصق المفتاح الخاص من ملف `owner-private-key.txt` لتتمكن من إصدار '
                  'رموز الأجهزة. يبقى على هذا الجهاز ولا يغادره.'),
          if (!_canIssue) ...[
            const SizedBox(height: 12),
            ImdLabeled('المفتاح الخاص (٦٤ حرفًا)', ImdFld(controller: _ownerKey, obscure: true)),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(
                label: 'استيراد المفتاح',
                icon: 'lock',
                busy: _busy,
                onPressed: _importOwnerKey,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(
                label: 'إزالة المفتاح من هذا الجهاز',
                icon: 'trash',
                kind: ImdBtnKind.danger,
                small: true,
                onPressed: () async {
                  await _act.forgetPrivateKey();
                  await _load();
                  if (mounted) showImdToast(context, '✔ أُزيل المفتاح من هذا الجهاز');
                },
              ),
            ),
          ],
        ]),
      );

  Future<void> _importOwnerKey() async {
    setState(() => _busy = true);
    final ok = await _act.importPrivateKey(_ownerKey.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showImdToast(context, '✖ المفتاح غير صحيح أو لا يطابق مفتاح هذا الإصدار', error: true);
      return;
    }
    _ownerKey.clear();
    await _load();
    if (mounted) showImdToast(context, '✔ استُورد المفتاح — يمكنك إصدار رموز التفعيل');
  }

  Widget _issuer() {
    final c = context.imd;
    return ImdPanel(
      title: 'إصدار رمز لجهاز آخر',
      icon: 'edit',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote('اطلب من مشغّل الجهاز الجديد معرّف جهازه، ثم أصدر له رمزًا '
            'وأملِه عليه. الرمز مرتبط بذلك الجهاز وحده ولا يعمل على غيره.'),
        const SizedBox(height: 12),
        ImdGrid2(children: [
          ImdLabeled('معرّف الجهاز (٨ أحرف)', ImdFld(controller: _targetDevice, hint: 'ABCD2345')),
          ImdLabeled('الفرع / الجهة', ImdFld(controller: _branch, hint: 'اللواء الأول')),
        ]),
        const SizedBox(height: 10),
        ImdLabeled(
          'دور الجهاز',
          ImdSelect<DeviceRole>(
            value: _role,
            items: const [
              (DeviceRole.branch, 'جهاز فرع (يستقبل الحسابات)'),
              (DeviceRole.master, 'جهاز إدارة (ينشئ الحسابات ويصدر الرموز)'),
            ],
            onChanged: (v) => setState(() => _role = v ?? DeviceRole.branch),
          ),
        ),
        const SizedBox(height: 10),
        ImdLabeled(
          'مدة الصلاحية',
          ImdSelect<int>(
            value: _months,
            items: const [(3, '٣ أشهر'), (6, '٦ أشهر'), (12, 'سنة'), (36, 'ثلاث سنوات')],
            onChanged: (v) => setState(() => _months = v ?? 12),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(label: 'إصدار الرمز', icon: 'shield', busy: _busy, onPressed: _issue),
        ),
        if (_issued.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.accentSoft,
              border: Border.all(color: c.ring),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _issued,
              style: TextStyle(fontSize: 12.5, height: 1.9, color: c.text, fontFamily: 'monospace'),
            ),
          ),
        ],
      ]),
    );
  }
}
