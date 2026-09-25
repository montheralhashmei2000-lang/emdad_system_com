import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_window.dart';

/// شاشة الدخول: الشعار والعنوان، رسالة الخطأ، اسم المستخدم، كلمة المرور بزر
/// الإظهار، ثم «دخول» و«خروج» جنبًا إلى جنب.
///
/// على ويندوز تُعرض في نافذة صغيرة بمقاس البطاقة بلا شريط عنوان ([ImdWindow.login])،
/// فتُسحب النافذة من منطقة الشعار، ويغلق «خروج» التطبيق.
/// الشاشة فاتحة دائمًا في كل الأوضاع كما في الويب.
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
  static const _text = Color(0xFF202123);
  static const _text2 = Color(0xFF343541);

  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _showPass = false;
  bool _busy = false;
  String _error = '';

  /// زر «خروج» حيث يمكن للتطبيق أن يغلق نفسه (ويندوز وأندرويد).
  static bool get _canExit =>
      LoginScreen.debugShowExit ?? (!kIsWeb && (Platform.isWindows || Platform.isAndroid));

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
      widget.onSignedIn();
      return;
    }
    _lErr(res.message);
  }

  Future<void> _exit() async {
    if (ImdWindow.supported) {
      await ImdWindow.exit();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 520;
    // الشاشة فاتحة دائمًا.
    return Theme(
      data: Theme.of(context).copyWith(extensions: const [ImdColors.light]),
      child: Scaffold(
        backgroundColor: narrow ? Colors.white : const Color(0xFFF7F7F8),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: narrow ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 420),
                child: Container(
                  padding: narrow
                      ? const EdgeInsets.fromLTRB(20, 40, 20, 24)
                      : const EdgeInsets.fromLTRB(32, 36, 32, 24),
                  decoration: narrow
                      ? null
                      : BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE3E3E8)),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
                            BoxShadow(color: Color(0x14101828), blurRadius: 40, offset: Offset(0, 16)),
                          ],
                        ),
                  child: _card(narrow),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(bool narrow) {
    final inputH = narrow ? 50.0 : 48.0;
    final inputFs = narrow ? 15.5 : 15.0;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: narrow ? 112 : 132,
            height: narrow ? 96 : 112,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 12),
        Text('نظام الإمداد والتموين',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: narrow ? 22 : 24, fontWeight: FontWeight.w700, color: _text, height: 1.35)),
        const SizedBox(height: 22),
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
              color: const Color(0xFFFEF3F2),
              border: Border.all(color: const Color(0xFFFECDCA)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ImdEmojiText(_error,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFB42318), height: 1.5)),
          ),
        _label('اسم المستخدم'),
        _input(
          controller: _user,
          hint: 'مثال: admin',
          icon: 'user',
          height: inputH,
          fontSize: inputFs,
          onSubmitted: (_) => _login(),
        ),
        _label('كلمة المرور'),
        _input(
          controller: _pass,
          hint: '••••••••',
          icon: 'lock',
          height: inputH,
          fontSize: inputFs,
          obscure: !_showPass,
          ltr: true,
          onSubmitted: (_) => _login(),
          eye: true,
          bottom: 22,
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
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _text2)),
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

/// `.lg-input` مع أيقونة يمينًا وزر إظهار يسارًا، ولون الأيقونة يتحول للأساسي عند التركيز.
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
    const accent = Color(0xFF0F766E);
    final border = focused ? accent : (_hover ? const Color(0xFFB9B9C6) : const Color(0xFFD1D1DB));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
          boxShadow: focused ? const [BoxShadow(color: Color(0x2E0F766E), spreadRadius: 3)] : null,
        ),
        child: Row(
          children: [
            if (widget.icon != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
                child: ImdIcon(widget.icon!, size: 18, color: focused ? accent : const Color(0xFF8E8EA0)),
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
                style: TextStyle(fontSize: widget.fontSize, color: const Color(0xFF202123)),
                cursorColor: accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintTextDirection: TextDirection.rtl,
                  hintStyle: TextStyle(fontSize: widget.fontSize, color: const Color(0xFF8E8EA0)),
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
    return Tooltip(
      message: widget.on ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFF2F2F5) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ImdIcon(
              'eye',
              size: 18,
              color: widget.on
                  ? const Color(0xFF0F766E)
                  : (_hover ? const Color(0xFF202123) : const Color(0xFF5B5E6B)),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.lg-btn`
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
    return Padding(
      padding: EdgeInsets.zero,
      child: MouseRegion(
        cursor: widget.busy ? SystemMouseCursors.progress : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.height,
            decoration: BoxDecoration(
              color: (_hover && !widget.busy ? const Color(0xFF115E59) : const Color(0xFF0F766E))
                  .withValues(alpha: widget.busy ? .85 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white, backgroundColor: Color(0x66FFFFFF)),
                  ),
                  const SizedBox(width: 8),
                ] else if (widget.icon != null) ...[
                  ImdIcon(widget.icon!, size: widget.fontSize + 2, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ),
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
    final fg = _hover ? const Color(0xFFB42318) : const Color(0xFF343541);
    return Tooltip(
      message: 'إغلاق النظام',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.height,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFFEF3F2) : Colors.white,
              border: Border.all(color: _hover ? const Color(0xFFFECDCA) : const Color(0xFFD1D1DB)),
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
