import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/security/auth_service.dart';
import '../../data/db/app_database.dart';
import 'change_password_dialog.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';

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

  /// زر «خروج» حيث يمكن للتطبيق أن يغلق نفسه (ويندوز وأندرويد).
  static bool get _canExit =>
      LoginScreen.debugShowExit ?? (Platform.isWindows || Platform.isAndroid);

  static const _rememberedUserKey = 'imdad.login.rememberedUsername';

  @override
  void initState() {
    super.initState();
    _restoreRememberedUser();
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
      final weak = user != null &&
          AuthService.shouldSuggestPasswordChange(role: user.role, password: _pass.text);
      widget.onSignedIn();
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

/// حقل الدخول: أيقونة يمينًا وزر إظهار يسارًا، ولون الأيقونة يتحول للأساسي عند التركيز.
class _LgInput extends StatefulWidget {
  const _LgInput({
    required this.controller,
    required this.fontSize,
    this.hint,
    this.icon,
    this.obscure = false,
    this.ltr = false,
    this.eye,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final double fontSize;
  final String? hint;
  final String? icon;
  final bool obscure;
  final bool ltr;
  final Widget? eye;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_LgInput> createState() => _LgInputState();
}

class _LgInputState extends State<_LgInput> {
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final c = context.imd;
    final accent = c.accent;
    final border =
        focused ? accent : (_hover ? Color.lerp(c.lineStrong, c.faint, .45)! : c.lineStrong);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
          boxShadow: focused ? [BoxShadow(color: accent.withValues(alpha: .18), spreadRadius: 3)] : null,
        ),
        child: Row(
          children: [
            if (widget.icon != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
                child: ImdIcon(widget.icon!, size: 18, color: focused ? accent : c.faint),
              )
            else
              const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                obscureText: widget.obscure,
                textDirection: widget.ltr ? TextDirection.ltr : null,
                textAlign: TextAlign.start,
                onSubmitted: widget.onSubmitted,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(fontSize: widget.fontSize, color: c.text),
                cursorColor: accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintTextDirection: TextDirection.rtl,
                  hintStyle: TextStyle(fontSize: widget.fontSize, color: c.faint),
                ),
              ),
            ),
            if (widget.eye != null) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: widget.eye)
            else const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

class _EyeBtn extends StatefulWidget {
  const _EyeBtn({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  State<_EyeBtn> createState() => _EyeBtnState();
}

class _EyeBtnState extends State<_EyeBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ImdIcon(
            'eye',
            size: 18,
            color: widget.on ? c.accent : (_hover ? c.text : c.muted),
          ),
        ),
      ),
    );
  }
}

/// زرّ الدخول الأساسي — يعرض مؤشر انتظارٍ أثناء التحقق.
class _PrimaryBtn extends StatefulWidget {
  const _PrimaryBtn({
    required this.label,
    this.icon,
    required this.busy,
    required this.height,
    required this.fontSize,
    required this.onTap,
  });

  final String label;
  final String? icon;
  final bool busy;
  final double height;
  final double fontSize;
  final VoidCallback onTap;

  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: EdgeInsets.zero,
      child: MouseRegion(
        cursor: widget.busy ? SystemMouseCursors.progress : ImdCursor.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.height,
            decoration: BoxDecoration(
              color: (_hover && !widget.busy ? c.accentHover : c.accent)
                  .withValues(alpha: widget.busy ? .85 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                        backgroundColor: c.onAccent.withValues(alpha: .4)),
                  ),
                  const SizedBox(width: 8),
                ] else if (widget.icon != null) ...[
                  ImdIcon(widget.icon!, size: widget.fontSize + 2, color: c.onAccent),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: c.onAccent)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// علامة الإغلاق عند الزاوية — دائرةٌ صغيرة تحمرّ عند المرور، بنفس دلالة
/// «خروج»: تغلق التطبيق نهائيًّا، لا تُخفي النافذة فحسب.
class _CornerCloseBtn extends StatefulWidget {
  const _CornerCloseBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CornerCloseBtn> createState() => _CornerCloseBtnState();
}

class _CornerCloseBtnState extends State<_CornerCloseBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? c.dangerSoft : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: ImdIcon('x', size: 15, color: _hover ? c.danger : c.text2),
        ),
      ),
    );
  }
}

/// زر «خروج»: ثانوي بإطار، ويتلوّن بلون التحذير عند المرور لأنه يغلق التطبيق.
class _ExitBtn extends StatefulWidget {
  const _ExitBtn({required this.height, required this.fontSize, required this.onTap});
  final double height;
  final double fontSize;
  final VoidCallback onTap;

  @override
  State<_ExitBtn> createState() => _ExitBtnState();
}

class _ExitBtnState extends State<_ExitBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = _hover ? c.danger : c.text2;
    return Semantics(
      label: 'إغلاق النظام',
      child: MouseRegion(
        cursor: ImdCursor.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.height,
            decoration: BoxDecoration(
              color: _hover ? c.dangerSoft : c.surface,
              border: Border.all(color: _hover ? c.danger.withValues(alpha: .35) : c.lineStrong),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ImdIcon('log-out', size: widget.fontSize + 2, color: fg),
              const SizedBox(width: 8),
              Text('خروج', style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}
