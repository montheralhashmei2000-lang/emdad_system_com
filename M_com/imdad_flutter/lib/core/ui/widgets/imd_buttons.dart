import 'package:flutter/material.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';
import 'imd_fields.dart';

enum ImdBtnKind { primary, outline, danger, blue, warn, purple, dark }

/// زر قائمة للإجراءات الثانوية في الشاشات التشغيلية.
class ImdMenuButton<T> extends StatelessWidget {
  const ImdMenuButton({
    super.key,
    required this.label,
    required this.items,
    required this.onSelected,
    this.icon = 'menu',
    this.small = false,
    this.dense = false,
  });

  final String label;
  final String icon;
  final bool small;

  /// أصغر من [small]: لشريط التطبيق العلوي (ارتفاع 28).
  final bool dense;
  final List<PopupMenuEntry<T>> Function(BuildContext) items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: items,
      child: Container(
        constraints: BoxConstraints(minHeight: dense ? 28 : (small ? 34 : ImdSizes.touchMin)),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 9 : (small ? 12 : 16), vertical: dense ? 3 : (small ? 6 : 9)),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineStrong),
          borderRadius: BorderRadius.circular(ImdSizes.radius),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ImdIcon(icon, size: small || dense ? 13 : 15, color: c.text),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: dense ? 12 : (small ? 12.5 : 13.5), fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(width: 4),
          ImdIcon('chevron-down', size: 13, color: c.muted),
        ]),
      ),
    );
  }
}

/// زرّ النظام بأنواعه: أساسي، مُحاط، خطر، أزرق، تحذير، بنفسجي، داكن — وبمقاسٍ صغير.
class ImdButton extends StatefulWidget {
  const ImdButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = ImdBtnKind.primary,
    this.small = false,
    this.expand = false,
    this.busy = false,
    this.height,
  });

  const ImdButton.outline({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.small = false,
    this.expand = false,
    this.busy = false,
    this.height,
  }) : kind = ImdBtnKind.outline;

  final String label;
  final String? icon;
  final VoidCallback? onPressed;
  final ImdBtnKind kind;
  final bool small;
  final bool expand;
  final bool busy;
  final double? height;

  @override
  State<ImdButton> createState() => _ImdButtonState();
}

class _ImdButtonState extends State<ImdButton> {
  bool _hover = false;
  bool _down = false;

  /// زر بعرض محتواه ما لم يُطلب التمدد (inline-flex في CSS).
  Widget _maybeIntrinsic(Widget child) => widget.expand ? child : IntrinsicWidth(child: child);

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final enabled = widget.onPressed != null && !widget.busy;
    Color bg;
    Color fg;
    Color? border;
    switch (widget.kind) {
      case ImdBtnKind.primary:
        bg = _hover ? c.accentHover : c.accent;
        fg = c.onAccent;
      case ImdBtnKind.outline:
        bg = _hover ? c.hover : c.surface;
        fg = c.text;
        border = _hover ? c.lineHover : c.lineStrong;
      case ImdBtnKind.danger:
        bg = _hover ? c.dangerHover : c.dangerSoft;
        fg = c.danger;
      case ImdBtnKind.blue:
        bg = c.info;
        fg = c.isDark ? c.bg : c.surface;
      case ImdBtnKind.warn:
        bg = _hover ? c.warn.withValues(alpha: .88) : c.warn;
        fg = c.isDark ? c.bg : c.surface;
      case ImdBtnKind.purple:
        bg = c.info;
        fg = c.isDark ? c.bg : c.surface;
      case ImdBtnKind.dark:
        bg = _hover ? c.text2 : c.text;
        fg = c.onText;
    }
    // داخل [ImdCompact] (نماذج السندات وجداول الإدخال) يأخذ الزرّ ارتفاع الحقل
    // المدمج وزواياه نفسها، فلا يعلو أخاه الحقل بجواره: زرّ «+» بجانب قائمة
    // المستودع كان ٤٤ والقائمة ٣٤، فيتّسع الصفّ كلّه به.
    final compact = ImdCompact.of(context);
    final flush = ImdCompact.flushOf(context);
    final h = widget.height ?? (compact ? ImdSizes.compactField : null);
    final iconOnly = widget.label.isEmpty;
    final fs = (widget.small || compact) ? 12.5 : 13.5;
    final pad = compact
        ? EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10)
        : widget.small
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 9);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(
            width: fs + 2,
            height: fs + 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (widget.icon != null)
          ImdIcon(widget.icon!, size: fs * 1.1, color: fg),
        if ((widget.busy || widget.icon != null) && widget.label.isNotEmpty) const SizedBox(width: 6),
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600, color: fg, height: 1.3)),
          ),
      ],
    );
    return MouseRegion(
      cursor: enabled ? ImdCursor.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _down ? .98 : 1,
          duration: const Duration(milliseconds: 80),
          child: Opacity(
            opacity: widget.onPressed == null ? .5 : 1,
            child: _maybeIntrinsic(AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: h,
              // زرّ أيقونةٍ وحدها في الكثافة المدمجة مربّعٌ بضلع الحقل.
              width: compact && iconOnly && h != null ? h : null,
              constraints: h == null ? BoxConstraints(minHeight: ImdSizes.touchMin) : null,
              padding: pad,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: flush
                    ? BorderRadius.zero
                    : BorderRadius.circular(
                        compact ? ImdSizes.compactRadius : (widget.small ? 8 : 10)),
                border: (border == null || flush) ? null : Border.all(color: border),
                // رفعٌ خفيف عند تمرير الفأرة، ويزول عند الضغط — إحساس زرٍّ
                // مادّي لا مسطّحٍ كصفحات الويب.
                boxShadow: enabled && _hover && !_down && !flush
                    ? [
                        BoxShadow(
                          color: c.shadowMd,
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: content,
            )),
          ),
        ),
      ),
    );
  }
}

/// أزرار أيقونة فقط بإطار (`btn btn-o btn-sm` بأيقونة).
class ImdIconButton extends StatelessWidget {
  const ImdIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.kind = ImdBtnKind.outline, this.dense = false});

  final String icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final ImdBtnKind kind;

  /// ارتفاع 28 لشريط التطبيق العلوي.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final button = ImdButton(
        label: '', icon: icon, onPressed: onPressed, kind: kind, small: true, height: dense ? 28 : null);
    final hint = tooltip?.trim() ?? '';
    if (hint.isEmpty) return button;
    // زرٌّ بأيقونةٍ بلا نصّ: [tooltip] هو اسمُه الوحيد. كان الوسيط يُستقبَل
    // ويُهمَل، فلا تظهر تلميحةٌ على سطح المكتب ولا يجد قارئُ الشاشة ما ينطق به
    // في ١١٤ موضعًا من الشاشات.
    //
    // والاثنان لازمان لا أحدهما: `Tooltip` يُظهر النصّ عند الوقوف بالمؤشّر لكنه
    // لا يُسمّي الزرَّ نفسه في شجرة الدلالات (الرسالة تلحق بالطبقة العائمة حين
    // تظهر)، و`Semantics` يُسمّيه لقارئ الشاشة ولا يُظهر شيئًا للمُبصر.
    return Semantics(
      label: hint,
      button: true,
      child: Tooltip(message: hint, child: button),
    );
  }
}
