import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';

/// شاشة الدخول — مطابقة لـ `#loginScreen` في نسخة الويب (`lg-*` في ui-theme.css + auth-ux.js):
/// الشعار، العنوان، رسالة الخطأ، اسم المستخدم، كلمة المرور بزر الإظهار، زر الدخول،
/// «نسيت كلمة المرور» مع لوحة إعادة التعيين المحلية، وقسم «تهيئة حساب المدير الأول» القابل للطي.
/// الشاشة فاتحة دائمًا في كل الأوضاع كما في الويب.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _text = Color(0xFF202123);
  static const _text2 = Color(0xFF343541);
  static const _muted = Color(0xFF5B5E6B);
  static const _faint = Color(0xFF8E8EA0);

  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _showPass = false;
  bool _busy = false;
  bool _resetPanel = false;
  String _error = '';
  String _msg = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }


  void _lErr(String m) => setState(() {
        _error = m;
        _msg = '';
      });



  /// تسجيل الدخول — المسار الوحيد للدخول إلى النظام.
  /// إنشاء الحسابات لم يعد من هنا: يُنشئها المدير على جهازه وتصل بالمزامنة.
  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _msg = '';
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

  Future<void> _localReset() async {
    final ok = await imdConfirm(
      context,
      'سيتم مسح بيانات الدخول المحلية. سيظهر خيار تهيئة حساب مدير جديد. '
      '(حساب Firebase القديم يبقى — استخدم اسم مستخدم جديدًا). متابعة؟',
      ok: 'متابعة',
      danger: true,
    );
    if (!ok || !mounted) return;
    await context.read<AuthService>().localReset();
    if (!mounted) return;
    // إعادة التعيين تمحو الحسابات المحلية؛ البوابة في جذر التطبيق ستطلب
    // تفعيل الجهاز من جديد، ولا يُنشأ حساب من هنا.
    showImdToast(context, '✔ تمت إعادة التعيين المحلية — أعد تشغيل التطبيق');
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
    final inputH = narrow ? 52.0 : 48.0;
    final inputFs = narrow ? 16.0 : 15.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // .lg-brand
        Center(
          child: SizedBox(
            width: narrow ? 112 : 132,
            height: narrow ? 96 : 112,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 14),
        Text('نظام الإمداد والتموين',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: narrow ? 22 : 24, fontWeight: FontWeight.w700, color: _text, height: 1.35)),
        const SizedBox(height: 8),
        const Text('سجّل الدخول للمتابعة',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: _muted)),
        const SizedBox(height: 26),
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
        ),
        _PrimaryBtn(
          label: _busy ? 'جارٍ التحقق…' : 'دخول إلى النظام',
          busy: _busy,
          height: inputH,
          fontSize: inputFs,
          onTap: _login,
          topMargin: 6,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 18,
            child: _msg.isEmpty
                ? null
                : ImdEmojiText(_msg,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: _muted)),
          ),
        ),
        _LinkBtn(
          label: 'نسيت كلمة المرور أو لا أستطيع الدخول؟',
          onTap: () => setState(() => _resetPanel = !_resetPanel),
        ),
        if (_resetPanel)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F8),
              border: Border.all(color: const Color(0xFFE3E3E8)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'استرجاع الدخول\n', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: '1) إذا كان حسابك موجودًا لدى Firebase، أدخل اسم المستخدم (أو البريد كاملًا) '
                            'مع كلمة المرور نفسها.\n'
                            '2) إذا لم يتذكر أحد كلمة المرور: اضغط «إعادة تعيين محلي» ثم أعد تهيئة حساب مدير '
                            'جديد باسم مستخدم مختلف.'),
                  ]),
                  style: TextStyle(fontSize: 13, color: _text2, height: 1.7),
                ),
                const SizedBox(height: 10),
                Center(child: _SecBtn(label: 'إعادة تعيين محلي', icon: 'rotate-ccw', onTap: _localReset)),
              ],
            ),
          ),
        Container(height: 1, color: const Color(0xFFECECF1), margin: const EdgeInsets.only(top: 18, bottom: 12)),
        const SizedBox(height: 20),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImdIcon('lock', size: 14, color: _faint),
            SizedBox(width: 6),
            Text('جلسة مُؤمَّنة · محاولات محدودة', style: TextStyle(fontSize: 12, color: _faint)),
          ],
        ),
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
    required this.busy,
    required this.height,
    required this.fontSize,
    required this.onTap,
    this.topMargin = 0,
  });

  final String label;
  final bool busy;
  final double height;
  final double fontSize;
  final VoidCallback onTap;
  final double topMargin;

  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: widget.topMargin),
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

/// `.lg-link`
class _LinkBtn extends StatefulWidget {
  const _LinkBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_LinkBtn> createState() => _LinkBtnState();
}

class _LinkBtnState extends State<_LinkBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFE6F4F2) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
          ),
        ),
      ),
    );
  }
}

/// `.lg-btn-sec`
class _SecBtn extends StatelessWidget {
  const _SecBtn({required this.label, required this.icon, required this.onTap});
  final String label;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD1D1DB)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ImdIcon(icon, size: 15, color: const Color(0xFF202123)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF202123))),
          ]),
        ),
      ),
    );
  }
}
