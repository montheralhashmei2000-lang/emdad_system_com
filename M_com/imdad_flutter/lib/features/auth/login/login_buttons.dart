part of '../login_screen.dart';

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

/// زرّ «الدخول بالبصمة»: ثانويٌّ بإطارٍ بلون التمييز تحت زر «دخول».
class _BioBtn extends StatelessWidget {
  const _BioBtn({required this.height, required this.fontSize, required this.busy, required this.onTap});
  final double height;
  final double fontSize;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Semantics(
      button: true,
      label: 'الدخول بالبصمة',
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: .08),
            border: Border.all(color: c.accent.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ImdIcon('fingerprint', size: fontSize + 5, color: c.accent),
            const SizedBox(width: 8),
            Text('الدخول بالبصمة',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: c.accent)),
          ]),
        ),
      ),
    );
  }
}
