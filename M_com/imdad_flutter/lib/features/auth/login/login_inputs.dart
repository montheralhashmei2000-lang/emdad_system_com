part of '../login_screen.dart';

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
