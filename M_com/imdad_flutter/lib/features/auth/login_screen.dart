import '../../domain/access_control.dart' show UserRole;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/sys_notice.dart';
import '../../data/db/app_database.dart';
import 'change_password_dialog.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';

part 'login/login_inputs.dart';
part 'login/login_buttons.dart';
part 'login/login_bio_dialog.dart';


/// شاشة الدخول: الشعار والعنوان، رسالة الخطأ، اسم المستخدم، كلمة المرور بزر
/// الإظهار، ثم «دخول» و«خروج» جنبًا إلى جنب.
///
/// على ويندوز تُعرض في نافذة صغيرة بمقاس البطاقة بلا شريط عنوان ([ImdWindow.login])،
/// فتُسحب النافذة من منطقة الشعار، ويغلق «خروج» التطبيق.
/// الشاشة تتبع سمة التطبيق (فاتح/داكن/تلقائي) كبقية الشاشات.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  /// يُظهر زر «خروج» على منصة لا يظهر فيها (الاختبارات وأداة اللقطات على لينكس).
  @visibleForTesting
  static bool? debugShowExit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _showPass = false;
  bool _busy = false;
  bool _remember = false;
  String _error = '';

  /// الدخول بالبصمة: مفعَّلةٌ على هذا الجهاز ومتاحةٌ الآن (أندرويد فقط).
  bool _bioReady = false;
  late final BiometricService _bio;

  /// زر «خروج» حيث يمكن للتطبيق أن يغلق نفسه (ويندوز وأندرويد).
  static bool get _canExit =>
      LoginScreen.debugShowExit ?? (Platform.isWindows || Platform.isAndroid);

  static const _rememberedUserKey = 'imdad.login.rememberedUsername';

  @override
  void initState() {
    super.initState();
    _bio = BiometricService(context.read<AppDatabase>(), context.read<AuthService>());
    _restoreRememberedUser();
    _initBiometric();
  }

  /// يفحص جاهزية البصمة ثم يعرض نافذتها تلقائيًّا مرةً واحدة عند فتح الشاشة.
  Future<void> _initBiometric() async {
    if (await _bio.availability() != BiometricAvailability.available) return;
    if (await _bio.enrolledUserId() == null) return;
    if (!mounted) return;
    setState(() => _bioReady = true);
    // بعد أول إطار فتظهر الشاشة خلف نافذة البصمة لا فراغًا أسود.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loginWithBiometric();
    });
  }

  Future<void> _loginWithBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final res = await _bio.signIn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.isOk) {
      widget.onSignedIn();
      return;
    }
    // الاعتماد أُبطل (تغيّرت كلمة المرور مثلًا): يختفي الزر ويبقى الدخول بالكلمة.
    if (await _bio.enrolledUserId() == null && mounted) setState(() => _bioReady = false);
    _lErr(res.message);
  }

  /// بعد دخولٍ ناجح بكلمة المرور: يعرض تفعيل البصمة إن كانت متاحةً ولم تُفعَّل
  /// لهذا الحساب ولم يرفض المستخدم العرض من قبل.
  Future<void> _offerBiometric(User user, ScaffoldMessengerState? messenger) async {
    if (await _bio.availability() != BiometricAvailability.available) return;
    if (await _bio.enrolledUserId() == user.id) return;
    if (await _bio.declinedPrompt()) return;
    if (!mounted) return;
    final choice = await showDialog<_BioChoice>(
      context: context,
      builder: (_) => const _BioOfferDialog(),
    );
    if (choice == _BioChoice.never) {
      await _bio.rememberDeclined();
    } else if (choice == _BioChoice.enable) {
      final ok = await _bio.enroll(user);
      messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(ok ? 'تم تفعيل الدخول بالبصمة' : 'لم يُفعَّل الدخول بالبصمة'),
      ));
    }
  }

  /// اسم المستخدم المحفوظ من دخولٍ سابق — كلمة المرور لا تُحفظ أبدًا.
  Future<void> _restoreRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rememberedUserKey);
    if (!mounted || saved == null || saved.isEmpty) return;
    setState(() {
      _user.text = saved;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }


  void _lErr(String m) => setState(() => _error = m);



  /// تسجيل الدخول — المسار الوحيد للدخول إلى النظام.
  /// إنشاء الحسابات لم يعد من هنا: يُنشئها المدير على جهازه وتصل بالمزامنة.
  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final res = await context.read<AuthService>().login(_user.text.trim(), _pass.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.isOk) {
      final prefs = await SharedPreferences.getInstance();
      if (_remember) {
        await prefs.setString(_rememberedUserKey, _user.text.trim());
      } else {
        await prefs.remove(_rememberedUserKey);
      }
      if (!mounted) return;
      // قبل الانتقال: المرسِل والقاعدة يُلتقطان الآن، فالشاشة تُستبدل بعد قليل.
      final messenger = ScaffoldMessenger.maybeOf(context);
      final db = context.read<AppDatabase>();
      final laterColor = Theme.of(context).colorScheme.inversePrimary;
      final user = res.user;
      // لا مالك وأكثر من مدير: يُنبَّه المدير ليحدّد المالك (مرة في كل دخول حتى يُحدَّد).
      final ownerPending = user != null &&
          UserRole.isAdmin(user.role) &&
          await context.read<AuthService>().ownerSelectionNeeded();
      if (!mounted) return;
      // مرحلة الانتقال: مرةً واحدة لكل مدير غير مالك.
      final sysNotice = SysTransitionNotice(db);
      final showSysNotice = user != null && await sysNotice.shouldShow(user);
      if (showSysNotice) await sysNotice.markSeen(user);
      if (!mounted) return;
      final weak = user != null &&
          AuthService.shouldSuggestPasswordChange(role: user.role, password: _pass.text);
      if (user != null) await _offerBiometric(user, messenger);
      if (!mounted) return;
      widget.onSignedIn();
      if (showSysNotice && messenger != null) {
        messenger.showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 15),
          content: Text(SysTransitionNotice.message),
        ));
      }
      if (ownerPending && messenger != null) {
        messenger.showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 12),
          content: Text('لم يُحدَّد مالك للنظام — حدّد المالك من الإعدادات ← نظرة عامة.'),
        ));
      }
      if (weak && messenger != null) _offerPasswordUpgrade(messenger, db, user.id, laterColor);
      return;
    }
    _lErr(res.message);
  }

  /// تنبيه لا يمنع الدخول: كلمة المرور أقصر من الحد الجديد (٨ أحرف).
  /// «غيّرها الآن» يفتح نافذة التغيير، و«لاحقًا» يُغلق التنبيه.
  void _offerPasswordUpgrade(ScaffoldMessengerState messenger, AppDatabase db, String userId, Color laterColor) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 15),
        // «لاحقًا» داخل المحتوى لأن SnackBar يقبل إجراءً واحدًا فقط.
        content: Row(children: [
          const Expanded(
            child: Text('كلمة مرورك أقصر من ${AuthService.minPasswordLength} أحرف — يُنصح بتغييرها.'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: laterColor),
            onPressed: messenger.hideCurrentSnackBar,
            child: const Text('لاحقًا'),
          ),
        ]),
        action: SnackBarAction(
          label: 'غيّرها الآن',
          onPressed: () => showChangePasswordDialog(db: db, userId: userId),
        ),
      ));
  }

  Future<void> _exit() async {
    await ImdWindow.exit();
    if (!ImdWindow.supported) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 520;
    final c = context.imd;
    // خطّ البطاقة ثابتٌ (Cairo) بصرف النظر عن خط الواجهة المختار في
    // الإعدادات — أما ألوانها فتتبع سمة التطبيق كبقية الشاشات.
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Cairo'),
      ),
      child: Scaffold(
        backgroundColor: narrow ? c.surface : c.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: narrow ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 420),
                    child: Container(
                      padding: narrow
                          ? const EdgeInsets.fromLTRB(20, 22, 20, 18)
                          : const EdgeInsets.fromLTRB(32, 36, 32, 24),
                      decoration: narrow
                          ? null
                          : BoxDecoration(
                              color: c.surface,
                              border: Border.all(color: c.line),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                    color: c.shadowXs,
                                    blurRadius: 2,
                                    offset: const Offset(0, 1)),
                                BoxShadow(
                                    color: c.shadowSm,
                                    blurRadius: 40,
                                    offset: const Offset(0, 16)),
                              ],
                            ),
                      child: _card(narrow),
                    ),
                  ),
                ),
              ),
              // النافذة بلا شريط عنوان، فلا زرّ إغلاقٍ أصليّ من ويندوز —
              // هذا بديله: علامة إغلاقٍ نهائي عند الزاوية العليا اليمنى دومًا،
              // بصرف النظر عن اتجاه النص.
              if (_canExit)
                Positioned(top: 10, right: 10, child: _CornerCloseBtn(onTap: _exit)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(bool narrow) {
    final c = context.imd;
    final inputH = narrow ? 44.0 : 48.0;
    final inputFs = narrow ? 15.0 : 15.0;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: narrow ? 84 : 132,
            height: narrow ? 72 : 112,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 8),
        Text('نظام الإمداد والتموين',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: narrow ? 19 : 24, fontWeight: FontWeight.w700, color: c.text, height: 1.3)),
        SizedBox(height: narrow ? 12 : 22),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // نافذة الدخول بلا شريط عنوان: تُسحب من منطقة الشعار.
        ImdWindow.supported ? DragToMoveArea(child: header) : header,
        // #lErr
        if (_error.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.dangerSoft,
              border: Border.all(color: c.danger.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ImdEmojiText(_error,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: c.danger, height: 1.5)),
          ),
        _label('اسم المستخدم'),
        _input(
          controller: _user,
          icon: 'user',
          height: inputH,
          fontSize: inputFs,
          onSubmitted: (_) => _login(),
          bottom: 10,
        ),
        _label('كلمة المرور'),
        _input(
          controller: _pass,
          icon: 'lock',
          height: inputH,
          fontSize: inputFs,
          obscure: !_showPass,
          ltr: true,
          onSubmitted: (_) => _login(),
          eye: true,
          bottom: 2,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ImdCheckbox(
            value: _remember,
            label: 'تذكّر اسم المستخدم',
            onChanged: (v) => setState(() => _remember = v),
          ),
        ),
        Row(children: [
          Expanded(
            flex: 3,
            child: _PrimaryBtn(
              label: _busy ? 'جارٍ التحقق…' : 'دخول',
              icon: 'log-in',
              busy: _busy,
              height: inputH,
              fontSize: inputFs,
              onTap: _login,
            ),
          ),
          if (_canExit) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _ExitBtn(height: inputH, fontSize: inputFs, onTap: _exit),
            ),
          ],
        ]),
        if (_bioReady) ...[
          const SizedBox(height: 10),
          _BioBtn(height: inputH, fontSize: inputFs, busy: _busy, onTap: _loginWithBiometric),
        ],
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.imd.text2)),
      );

  Widget _input({
    required TextEditingController controller,
    String? hint,
    String? icon,
    required double height,
    required double fontSize,
    bool obscure = false,
    bool ltr = false,
    bool eye = false,
    double bottom = 16,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height,
        child: _LgInput(
          controller: controller,
          hint: hint,
          icon: icon,
          fontSize: fontSize,
          obscure: obscure,
          ltr: ltr,
          onSubmitted: onSubmitted,
          eye: eye
              ? _EyeBtn(on: _showPass, onTap: () => setState(() => _showPass = !_showPass))
              : null,
        ),
      ),
    );
  }
}
