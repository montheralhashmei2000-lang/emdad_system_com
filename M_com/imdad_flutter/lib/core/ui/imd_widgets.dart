import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'imd_context_menu.dart';
import 'imd_density.dart';
import 'imd_format.dart';
import 'imd_icon.dart';
import 'imd_status_bar.dart';
import 'imd_tokens.dart';

// مكوّنات الواجهة المشتركة لنظام الإمداد والتموين: العناوين والأزرار والشارات
// والجداول والحوارات. مقاساتها وألوانها من `ImdSizes` و`ImdColors` وحدهما، فلا
// يُعاد تعريف قياسٍ ولا لونٍ في شاشة.

/// عنوان الشاشة: أيقونةٌ وعنوانٌ وسطرٌ فرعي، ومكانٌ للإجراءات يمينه.
/// يُحيط شاشةً **مضمَّنةً** داخل شاشةٍ أخرى (كأقسام الإعدادات).
///
/// الشاشة المضمَّنة لا تفتح صفحتها الخاصة: لا تمرير ولا حشوة (`ImdPage`)، ولا
/// عنوان صفحة ولا زر «رجوع» — فالشاشة المضيفة هي التي تعرض العنوان والتنقل.
class ImdEmbedScope extends InheritedWidget {
  const ImdEmbedScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImdEmbedScope>() != null;

  @override
  bool updateShouldNotify(ImdEmbedScope oldWidget) => false;
}

/// زر «رجوع إلى الإعدادات» أعلى الشاشات المفتوحة من الإعدادات؛ يختفي حين تكون
/// الشاشة مضمَّنةً داخل الإعدادات نفسها.
class ImdPageBack extends StatelessWidget {
  const ImdPageBack({super.key, required this.onPressed, this.label = 'رجوع إلى الإعدادات'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (ImdEmbedScope.of(context)) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ImdButton.outline(label: label, icon: 'arrow-left', small: true, onPressed: onPressed),
      ),
    );
  }
}

/// وسمٌ يُعلن أن ما تحته **صفّ إجراءات** في رأس الصفحة (تبويبات + أزرار): كل
/// عنصرٍ فيه بارتفاع [ImdSizes.barControl] ومحاذاةٍ وسطيّة واحدة، فتقع كلها على
/// خطٍّ أفقيٍّ واحد في كل الشاشات.
class ImdActionRow extends InheritedWidget {
  const ImdActionRow({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImdActionRow>() != null;

  /// يلفّ [children] في `Wrap` موحَّد المحاذاة والفجوات.
  static Widget wrap(List<Widget> children, {WrapAlignment alignment = WrapAlignment.start}) => ImdActionRow(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final w in children) SizedBox(height: ImdSizes.barControl, child: Align(widthFactor: 1, child: w))],
        ),
      );

  @override
  bool updateShouldNotify(ImdActionRow old) => false;
}

class ImdPageTitle extends StatelessWidget {
  const ImdPageTitle({super.key, required this.title, this.icon, this.subtitle, this.trailing, this.actions});

  final String title;
  final String? icon;
  final String? subtitle;

  /// عنصر واحد عند نهاية سطر العنوان في كل العروض (شارة، عدّاد…).
  final Widget? trailing;

  /// أزرار الإجراءات: عند نهاية سطر العنوان قبل [trailing] على العرض الواسع،
  /// وتنزل تحت العنوان في صفٍّ يلتفّ (`Wrap`) على الجوال. [trailing] يبقى مكانه.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    // مضمَّنةٌ: العنوان للشاشة المضيفة، ويبقى ما يخصّ هذه الشاشة وحدها
    // (أزرار الإجراءات وشارة الحالة) في سطرٍ مضغوط.
    if (ImdEmbedScope.of(context)) {
      final extra = [...?actions, if (trailing != null) trailing!];
      if (extra.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ImdActionRow.wrap(extra),
        ),
      );
    }
    final c = context.imd;
    final bp = ImdBp.of(context);
    final mobile = bp.mobile;
    final acts = actions ?? const <Widget>[];
    final inline = acts.isNotEmpty && !mobile;
    final below = acts.isNotEmpty && mobile;
    final titleText = Text(title,
        style: TextStyle(
            fontSize: mobile ? 19 : 22,
            fontWeight: FontWeight.w700,
            color: c.text,
            height: mobile ? 1.5 : 1.4));
    return Padding(
      padding: EdgeInsets.only(bottom: mobile ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                ImdIcon(icon!, size: (mobile ? 19 : 22) * 1.15, color: c.accent),
                const SizedBox(width: 8),
              ],
              // مع الإجراءات يأخذ العنوان كل المتبقي فتُدفع الأزرار إلى النهاية.
              if (inline) Expanded(child: titleText) else Flexible(child: titleText),
              if (inline) ...[
                const SizedBox(width: 12),
                // سقف العرض يمنع الأزرار الكثيرة من ابتلاع العنوان: تلتف بدل أن تفيض.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bp.width * .6),
                  child: ImdActionRow.wrap(acts, alignment: WrapAlignment.end),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ] else if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: TextStyle(fontSize: mobile ? 12 : 13.5, color: c.muted, height: 1.6)),
            ),
          if (below)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ImdActionRow.wrap(acts),
            ),
        ],
      ),
    );
  }
}

/// لوحةٌ بخلفية السطح وحدٍّ رفيع وزوايا 12 — الحاوية الأساسية لأقسام الشاشة.
class ImdPanel extends StatelessWidget {
  const ImdPanel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.padding,
    this.margin = const EdgeInsets.only(bottom: 20),
    this.actions,
    this.color,
    this.borderColor,
    this.titleGap = 14,
    this.centerVertically = false,
  });

  /// `display:flex; align-items:center` داخل البطاقة.
  final bool centerVertically;

  final Widget child;
  final String? title;
  final String? icon;
  final EdgeInsets? padding;
  final double titleGap;
  final EdgeInsets margin;
  final List<Widget>? actions;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: margin,
      padding: padding ??
          (ImdBp.of(context).mobile
              ? const EdgeInsets.all(12)
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 18)),
      decoration: BoxDecoration(
        color: color ?? c.surface,
        border: Border.all(color: borderColor ?? c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: centerVertically ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.only(bottom: titleGap),
              child: Row(
                children: [
                  if (icon != null) ...[ImdIcon(icon!, size: 15 * 1.15, color: c.accent), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(title!,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                  ...?actions,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

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
  });

  final String label;
  final String icon;
  final bool small;
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
        constraints: BoxConstraints(minHeight: small ? 34 : ImdSizes.touchMin),
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 6 : 9),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineStrong),
          borderRadius: BorderRadius.circular(ImdSizes.radius),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ImdIcon(icon, size: small ? 13 : 15, color: c.text),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: small ? 12.5 : 13.5, fontWeight: FontWeight.w600, color: c.text)),
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
  const ImdIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.kind = ImdBtnKind.outline});

  final String icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final ImdBtnKind kind;

  @override
  Widget build(BuildContext context) =>
      ImdButton(label: '', icon: icon, onPressed: onPressed, kind: kind, small: true);
}

/// تبويبات كبسولية؛ النشط أسود.
class ImdPillTabs<T> extends StatelessWidget {
  const ImdPillTabs({super.key, required this.tabs, required this.value, required this.onChanged, this.wrap = true, this.gap = 8});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// false ⇒ صف واحد بفجوة 6 قابل للتمرير أفقيًا.
  final bool wrap;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = [for (final t in tabs) _PillTab(tab: t, on: t.value == value, onTap: () => onChanged(t.value))];
    if (!wrap) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 6), items[i]],
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(spacing: gap, runSpacing: gap, children: items),
    );
  }
}

class ImdTab<T> {
  const ImdTab(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final String? icon;
}

class _PillTab extends StatefulWidget {
  const _PillTab({required this.tab, required this.on, required this.onTap});
  final ImdTab tab;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_PillTab> createState() => _PillTabState();
}

class _PillTabState extends State<_PillTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = widget.on;
    final fg = on ? c.onText : c.text2;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: ImdSizes.barControl,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? c.text : (_hover ? c.hover : c.surface),
            border: Border.all(color: on ? c.text : c.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.tab.icon != null) ...[
                ImdIcon(widget.tab.icon!, size: 13 * 1.1, color: fg),
                const SizedBox(width: 6),
              ],
              Text(widget.tab.label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// مجموعة مقاطع بخلفية رمادية والنشط أبيض (مثل «وحدة مستفيدة / مطبخ / جهة»).
class ImdSegmented<T> extends StatelessWidget {
  const ImdSegmented({super.key, required this.tabs, required this.value, required this.onChanged});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // المقاطع الكثيرة تُمرَّر أفقيًّا في الشاشة الضيّقة بدل أن تفيض.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in tabs)
            GestureDetector(
              onTap: () => onChanged(t.value),
              child: MouseRegion(
                cursor: ImdCursor.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: t.value == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: t.value == value
                        ? [BoxShadow(color: c.shadowHairline, blurRadius: 3, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (t.icon != null) ...[
                      ImdIcon(t.icon!, size: 14, color: t.value == value ? c.text : c.text2),
                      const SizedBox(width: 6)
                    ],
                    Text(t.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: t.value == value ? c.text : c.text2)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    ),
      ),
    );
  }
}

enum ImdTone { ok, off, pend, code, err, info }

/// شارة حالة: نصٌّ قصير بخلفيةٍ ولونٍ يحدّدهما [ImdTone].
class ImdChip extends StatefulWidget {
  const ImdChip(this.label,
      {super.key, this.tone = ImdTone.off, this.icon, this.onTap, this.deriveBackgroundFromText = false});

  final String label;
  final ImdTone tone;
  final String? icon;
  final VoidCallback? onTap;

  /// الخلفية = لون النص بشفافية 0.15 بدل لون `*Soft` من القالب.
  /// تضمن تطابق الخلفية مع النص في أي سمة (فاتحة أو داكنة أو وقود).
  final bool deriveBackgroundFromText;

  static (Color, Color) colors(ImdColors c, ImdTone tone) {
    switch (tone) {
      case ImdTone.ok:
        return (c.successSoft, c.success);
      case ImdTone.off:
        return (c.subtle, c.text2);
      case ImdTone.pend:
        return (c.warnSoft, c.warn);
      case ImdTone.code:
      case ImdTone.info:
        return (c.infoSoft, c.info);
      case ImdTone.err:
        return (c.dangerSoft, c.danger);
    }
  }

  @override
  State<ImdChip> createState() => _ImdChipState();
}

class _ImdChipState extends State<ImdChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final (soft, fg) = ImdChip.colors(context.imd, widget.tone);
    final bg = widget.deriveBackgroundFromText ? fg.withValues(alpha: .15) : soft;
    final hoverBg = widget.onTap != null && _hover ? Color.alphaBlend(fg.withValues(alpha: .1), bg) : bg;
    // الشارة لا يلتفّ نصّها، فأصغر عرضٍ لها هو عرض نصّها كاملًا،
    // فلا يضغطها عمود الجدول إلى ما دونه (IntrinsicWidth يجعل الأصغر = الأكبر).
    final chip = IntrinsicWidth(
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: hoverBg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.icon != null) ...[ImdIcon(widget.icon!, size: 13, color: fg), const SizedBox(width: 6)],
        // الرموز التعبيرية داخل الشارات تُحوَّل أيقوناتٍ من مكتبة النظام.
        //
        // و[Flexible] هنا ليس زينة: [IntrinsicWidth] أعلاه يجعل أصغر عرضٍ
        // للشارة عرضَ نصها كاملًا، فإن ضاق أبوها عن ذلك — شارةٌ طويلة في
        // عمودٍ ثابت العرض مثلًا — رسمت نفسها خارجه بفارق العرض بالضبط.
        // فبه يتقلّص النص ويُقصّ بنقاط بدل أن يفيض على جاره.
        Flexible(
          child: ImdEmojiText(widget.label,
              iconSize: 13,
              gap: 4,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.6)),
        ),
      ]),
    ));
    if (widget.onTap == null) return chip;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: chip),
    );
  }
}

/// اسمٌ بديل لـ[ImdChip] لعرض الحالات: `ImdTone.pend` «لم يُضبط بعد» برتقالي،
/// `ok` «مضبوط» أخضر، `off` «قيد الانتظار» رمادي، `err` أحمر، `info` أزرق.
typedef StatusBadge = ImdChip;

/// صندوق ملاحظة أصفر.
class ImdNote extends StatelessWidget {
  const ImdNote(this.text, {super.key, this.child, this.margin = EdgeInsets.zero});

  final String? text;
  final Widget? child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.noteBg,
        border: Border.all(color: c.noteBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child ??
          ImdEmojiText(text ?? '',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.noteText, height: 1.6)),
    );
  }
}

/// شريط تنبيه: خطأ أو تحذير أو نجاح أو معلومة، بنبرة [ImdTone].
class ImdAlert extends StatelessWidget {
  const ImdAlert(this.text, {super.key, this.tone = ImdTone.err, this.margin = const EdgeInsets.only(bottom: 12)});

  final String text;
  final ImdTone tone;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ImdChip.colors(context.imd, tone);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: ImdEmojiText(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg, height: 1.6)),
    );
  }
}

/// زخرفة حقول الإدخال الموحّدة.
/// وسمٌ يُعلن أن ما تحته نمطٌ مدمج.
///
/// **تُكتب مرةً حول الجدول فتتبعها حقوله كلها** — بديلًا عن تمرير `compact:`
/// إلى كل حقلٍ في خمس شاشات، وهو ما يُنسى في أوّل حقلٍ يُضاف بعده.
class ImdCompact extends InheritedWidget {
  const ImdCompact({super.key, this.on = true, this.flush = false, required super.child});

  final bool on;

  /// حقولٌ ملتصقةٌ بحدود خليّتها: بلا زوايا مدوَّرة ولا حدٍّ خاص — الفاصل بين
  /// الخلايا خطُّ الشبكة وحده (جداول الإدخال ومجموعات الإدخال [ImdInputGroup]).
  final bool flush;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImdCompact>()?.on ?? false;

  static bool flushOf(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<ImdCompact>();
    return (w?.on ?? false) && w!.flush;
  }

  @override
  bool updateShouldNotify(ImdCompact old) => old.on != on || old.flush != flush;
}

InputDecoration imdFieldDecoration(
  BuildContext context, {
  String? hint,
  String? prefixIcon,
  Widget? suffix,
  bool dense = false,
  bool readOnly = false,
  String? errorText,
}) {
  final c = context.imd;
  final compact = ImdCompact.of(context);
  final flush = ImdCompact.flushOf(context);
  final hasError = errorText != null && errorText.isNotEmpty;
  // رسالة الخطأ من `colorScheme.error`، وحدّ الحقل يوافقها فلا يختلف لونان.
  final err = Theme.of(context).colorScheme.error;
  // الملتصق: بلا زوايا، وبلا حدٍّ في الحالة العادية (خطّ الشبكة يفصل الخلايا)؛
  // يظهر حدّ التركيز والخطأ فقط.
  OutlineInputBorder b(Color col, [double w = 1, bool quiet = false]) => OutlineInputBorder(
        borderRadius: flush
            ? BorderRadius.zero
            : BorderRadius.circular(compact ? ImdSizes.compactRadius : 10),
        borderSide: flush && quiet ? BorderSide.none : BorderSide(color: col, width: w),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    errorText: hasError ? errorText : null,
    errorStyle: TextStyle(fontSize: 12, height: 1.4, color: err),
    errorMaxLines: 2,
    hintStyle: TextStyle(color: c.faint, fontSize: compact ? 12.5 : 14),
    filled: true,
    fillColor: readOnly ? c.bg : c.surface,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compact ? ImdSizes.compactPadH : 12,
      vertical: compact ? ImdSizes.compactPadV : (dense ? 8 : 12),
    ),
    prefixIcon: prefixIcon == null
        ? null
        : Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
            child: ImdIcon(prefixIcon, size: 16, color: c.faint),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    // `suffix` يقع عند نهاية الحقل: يسار الحقل في RTL ويمينه في LTR.
    suffixIcon: suffix == null
        ? null
        : Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: suffix),
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    border: b(c.lineStrong, 1, true),
    enabledBorder: b(c.lineStrong, 1, true),
    disabledBorder: b(c.lineStrong, 1, true),
    focusedBorder: b(c.accent, 1),
    errorBorder: b(hasError ? err : c.danger),
    focusedErrorBorder: b(hasError ? err : c.danger),
  );
}

/// عنوان فوق الحقل (13/600) ثم الحقل.
class ImdField extends StatelessWidget {
  const ImdField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.child,
    this.required = false,
    this.readOnly = false,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.obscure = false,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.onSubmitted,
    this.prefixIcon,
    this.focusNode,
    this.autofocus = false,
    this.errorText,
    this.suffix,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;

  /// رسالة خطأ تظهر تحت الحقل بلون `colorScheme.error`.
  final String? errorText;

  /// عنصر عند نهاية الحقل (يسار الحقل في RTL). لا يُطبَّق مع [child] المخصص.
  final Widget? suffix;
  final Widget? child;
  final bool required;
  final bool readOnly;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final ValueChanged<String>? onSubmitted;
  final String? prefixIcon;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (required) TextSpan(text: ' *', style: TextStyle(color: c.danger)),
                ]),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text2),
              ),
            ),
          child ??
              TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                readOnly: readOnly,
                keyboardType: keyboardType,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                maxLines: maxLines,
                obscureText: obscure,
                inputFormatters: inputFormatters,
                textAlign: textAlign,
                style: TextStyle(fontSize: 14, color: readOnly ? c.muted : c.text),
                decoration: imdFieldDecoration(context,
                    hint: hint,
                    readOnly: readOnly,
                    prefixIcon: prefixIcon,
                    suffix: suffix,
                    errorText: errorText),
              ),
          // الحقل المخصص يرسم ديكوره بنفسه، فتُعرض رسالة الخطأ تحته هنا.
          if (child != null && errorText != null && errorText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(errorText!,
                  style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// قائمة اختيارٍ تُفتح كنافذةٍ كبيرة بها بحثٌ وقائمةُ خيارات — لا القائمة الصغيرة
/// المنسدلة الافتراضية: على سطح المكتب تُقرأ عشرات الخيارات دفعةً واحدة، وعلى
/// الجوال تُنقر بالإصبع بلا تصويبٍ على سطرٍ ضيّق.
///
/// الحقل نفسه يعرض القيمة المختارة بإطار الحقول المعتاد. [onChanged] `null` ⇒
/// معطَّل.
class ImdSelect<T> extends StatelessWidget {
  const ImdSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.dense = false,
    this.title,
  });

  final List<(T, String)> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool dense;

  /// عنوان النافذة — الافتراضي [hint] أو «اختر».
  final String? title;

  Future<void> _open(BuildContext context) async {
    final picked = await showImdModal<_Pick<T>>(
      context,
      title: title ?? hint ?? 'اختر',
      icon: 'search',
      maxWidth: 460,
      builder: (ctx) => ImdPickerBody<T>(items: items, value: value),
    );
    if (picked != null) onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final compact = ImdCompact.of(context);
    final shown = [for (final e in items) if (e.$1 == value) e.$2];
    final enabled = onChanged != null;
    final fontSize = compact ? 13.0 : 14.0;
    // الارتفاع **ثابتٌ** لا حدٌّ أدنى: يساوي الحقل المدمج تمامًا فلا يعلو زرّ «+»
    // المجاور له ([ImdInputGroup]).
    return SizedBox(
      height: compact ? ImdSizes.compactField : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? ImdSizes.compactRadius : ImdSizes.radius),
        onTap: enabled ? () => _open(context) : null,
        child: InputDecorator(
          isEmpty: shown.isEmpty,
          decoration: imdFieldDecoration(context, dense: dense, readOnly: !enabled),
          child: Row(children: [
            Expanded(
              child: shown.isEmpty
                  ? Text(hint ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.faint, fontSize: compact ? 12.5 : 14))
                  : Text(shown.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: fontSize,
                          color: enabled ? c.text : c.muted,
                          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily)),
            ),
            ImdIcon('chevron-down', size: 16, color: c.muted),
          ]),
        ),
      ),
    );
  }
}

/// اختيارٌ مُرجَع: يميّز «اختير عنصرٌ قيمته null» عن «أُغلقت النافذة بلا اختيار».
class _Pick<T> {
  const _Pick(this.value);
  final T? value;
}

/// محتوى نافذة الاختيار: بحثٌ فوريّ وقائمةٌ تُمرَّر. Enter يختار أول المطابقات،
/// والخيار الحالي معلَّمٌ بعلامة ✓.
class ImdPickerBody<T> extends StatefulWidget {
  const ImdPickerBody({super.key, required this.items, required this.value});

  final List<(T, String)> items;
  final T? value;

  @override
  State<ImdPickerBody<T>> createState() => _ImdPickerBodyState<T>();
}

class _ImdPickerBodyState<T> extends State<ImdPickerBody<T>> {
  String _q = '';

  List<(T, String)> get _list =>
      _q.isEmpty ? widget.items : [for (final e in widget.items) if (e.$2.toLowerCase().contains(_q.toLowerCase())) e];

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final list = _list;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.length > 6) ...[
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v.trim()),
            onSubmitted: (_) {
              if (list.isNotEmpty) Navigator.of(context).pop(_Pick<T>(list.first.$1));
            },
            style: TextStyle(fontSize: 13.5, color: c.text),
            decoration: imdFieldDecoration(context, dense: true).copyWith(hintText: 'بحث…'),
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text('لا خيارات مطابقة', style: TextStyle(color: c.muted, fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final on = e.$1 == widget.value;
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => Navigator.of(context).pop(_Pick<T>(e.$1)),
                        child: Container(
                          constraints: BoxConstraints(minHeight: ImdSizes.touchMin - 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: on ? c.accentSoft : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(e.$2,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                                      color: on ? c.accent : c.text)),
                            ),
                            if (on) ImdIcon('check', size: 15, color: c.accent),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// عمود في `table.u`
class ImdCol {
  const ImdCol(this.label, {this.flex = 1, this.width, this.numeric = false, this.center = false, this.auto = true});
  final String label;

  /// يُستخدم فقط حين `auto: false` (عمود نسبي ثابت لخلايا لا تدعم القياس الذاتي مثل القوائم المنسدلة).
  final int flex;
  final double? width;
  final bool numeric;
  final bool center;

  /// عرض تلقائي حسب المحتوى كجداول HTML (الافتراضي).
  final bool auto;
}

/// عرض عمودٍ يتبع محتواه: يبدأ بعرض المحتوى الأقصى،
/// يُوزَّع الفائض بنسبة عرض المحتوى، ويُضغط العمود عند الضيق حتى أصغر عرض لمحتواه (مع التفاف النص).
class _HtmlColumnWidth extends TableColumnWidth {
  const _HtmlColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var w = 0.0;
    for (final c in cells) {
      final v = c.getMinIntrinsicWidth(double.infinity);
      if (v > w) w = v;
    }
    return w;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var w = 0.0;
    for (final c in cells) {
      final v = c.getMaxIntrinsicWidth(double.infinity);
      if (v > w) w = v;
    }
    return w;
  }

  @override
  double? flex(Iterable<RenderBox> cells) {
    final w = maxIntrinsicWidth(cells, double.infinity);
    return w <= 0 ? 1 : w;
  }
}

/// بند عرضٍ في [ImdTable]: صفٌّ بفهرسه المطلق، أو رأس مجموعة.
class _TableItem {
  const _TableItem.row(this.row)
      : key = null,
        count = 0,
        collapsed = false;
  const _TableItem.group(String this.key, this.count, this.collapsed) : row = -1;

  final int row;
  final String? key;
  final int count;
  final bool collapsed;

  bool get isGroup => key != null;
}

/// محتوى حوار تصفية عمود: بحثٌ وقائمةُ قيمه المميّزة بمربّعات اختيار. يُرجع
/// `Set<String>` بالقيم المسموحة (كل القيم = لا تصفية).
class ImdColumnFilterBody extends StatefulWidget {
  const ImdColumnFilterBody({super.key, required this.values, required this.selected, required this.shown});

  final List<String> values;

  /// المسموح حاليًّا، أو `null` فكلها مسموحة.
  final Set<String>? selected;

  /// نصّ العرض للقيمة (الفارغة «(فارغ)»).
  final String Function(String) shown;

  @override
  State<ImdColumnFilterBody> createState() => _ImdColumnFilterBodyState();
}

class _ImdColumnFilterBodyState extends State<ImdColumnFilterBody> {
  late final Set<String> _sel = {...(widget.selected ?? widget.values)};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final list = [
      for (final v in widget.values)
        if (_q.isEmpty || widget.shown(v).contains(_q)) v,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v.trim()),
          style: TextStyle(fontSize: 13.5, color: c.text),
          decoration: imdFieldDecoration(context).copyWith(hintText: 'بحث في القيم'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(
            onPressed: () => setState(() => _sel.addAll(list)),
            child: const Text('تحديد الكل', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => setState(() => _sel.removeAll(list)),
            child: const Text('إلغاء الكل', style: TextStyle(fontSize: 12)),
          ),
        ]),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text('لا قيم مطابقة', style: TextStyle(color: c.muted, fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final v = list[i];
                      final on = _sel.contains(v);
                      return InkWell(
                        onTap: () => setState(() => on ? _sel.remove(v) : _sel.add(v)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Checkbox(
                              value: on,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) => setState(() => on ? _sel.remove(v) : _sel.add(v)),
                            ),
                            Expanded(
                              child: Text(widget.shown(v),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: v.isEmpty ? c.muted : c.text)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          // لا يُسمح بتصفيةٍ فارغة: تُخفي كل الصفوف فلا يعرف المستخدم ما جرى.
          ImdButton(
            label: 'تطبيق',
            onPressed: _sel.isEmpty ? null : () => Navigator.of(context).pop(Set<String>.of(_sel)),
          ),
        ]),
      ],
    );
  }
}

/// جدول قراءة بيانات كثيفة: رأس رمادي فاتح، صفوف بخط فاصل، وتظليل عند المرور.
class ImdTable extends StatefulWidget {
  const ImdTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowKeys,
    this.empty = 'لا توجد بيانات',
    this.onRowTap,
    this.rowMenu,
    this.rowColor,
    this.footer,
    this.minWidth,
    this.maxHeight,
    this.onHeaderTap,
    this.sortIndex,
    this.sortAsc = true,
    this.zebra = false,
    this.pageSize,
    this.onPageChanged,
    this.cards = false,
    this.headerBackground,
    this.headerForeground,
    this.headerPadding,
    this.cellPadding,
    this.gridLines = false,
    this.cellFontSize,
    this.flushCells = false,
    this.values,
    this.filterable = true,
    this.groupable = true,
    this.freezeFirst,
  })  : assert(rowKeys == null || rowKeys.length == rows.length,
            'rowKeys.length يجب أن يساوي rows.length — مفتاحٌ واحدٌ لكل صفّ'),
        assert(values == null || values.length == rows.length,
            'values.length يجب أن يساوي rows.length — صفّ قيمٍ لكل صفّ');

  final List<ImdCol> columns;
  final List<List<Widget>> rows;

  /// مفتاحٌ لكل صفّ، بترتيب [rows] نفسه — يُحافظ على هوية عنصر الصفّ (حالته
  /// ومتحكّماته الداخلية) عبر إدراج صفٍّ أو حذفه في المنتصف، بدل أن يُعاد
  /// بناء كل صفٍّ تالٍ من الصفر بفهرسه الجديد. لازمٌ لجداول الإدخال التي
  /// تحمل حقولًا تفاعلية بحالة (كـImdItemPicker)؛ جداول القراءة (بلا حالةٍ
  /// في خلاياها) لا تحتاجه فتتركه `null`.
  final List<LocalKey>? rowKeys;

  final String empty;
  final ValueChanged<int>? onRowTap;

  /// بنود قائمة السياق للصفّ ذي الفهرس المعطى: كليك يمين على سطح المكتب،
  /// وضغطةٌ مطوّلة على اللمس. `null` أو قائمةٌ فارغة ⇒ لا قائمة. الفهرس مطلقٌ
  /// (من أول [rows]) حتى مع الترقيم، كـ[onRowTap].
  final List<ImdMenuItem> Function(int index)? rowMenu;
  final Color? Function(int index)? rowColor;
  final List<Widget>? footer;

  /// تلوين الصفوف الفردية بلونٍ خفيف جدًّا لتسهيل تتبّع السطر في جدولٍ كثيف.
  /// يخسر أمام [rowColor] عند كليهما، ولا يمسّ الصف عند المرور (hover) ولا صفّ [footer].
  final bool zebra;

  /// أقل عرضٍ للجدول — تمرير أفقي إذا ضاقت المساحة عنه.
  final double? minWidth;

  /// سقف ارتفاع الجدول ⇒ **رأسٌ ثابت**: تبقى عناوين الأعمدة ظاهرةً ويُمرَّر
  /// الجسم تحتها، فلا يضيع معنى العمود بعد عشرين سطرًا.
  ///
  /// الرأس والجسم جدولان منفصلان ليثبت الأول ويتحرّك الثاني، فلا بدّ أن يكون
  /// عرض الأعمدة **حتميًّا** حتى يتطابقا: العمود بعرضٍ صريح يبقى عليه، وما
  /// عداه يصير نسبيًّا بـ[ImdCol.flex]. أي أن [ImdCol.auto] (القياس من
  /// المحتوى) لا يعمل في هذا الوضع — ولذلك هو اختياريٌّ لا افتراضي: الجداول
  /// القائمة تبقى على قياسها الذاتي ما لم يُطلب السقف.
  ///
  /// يُتجاهل في عرض البطاقات على الجوال، وعند خلوّ الجدول.
  final double? maxHeight;

  /// ضغط رأس العمود (`th[data-k]{cursor:pointer}`) — يُستخدم للفرز.
  final ValueChanged<int>? onHeaderTap;

  /// فهرس العمود المفروز حاليًّا (من أعمدة هذا الجدول لا من بيانات الشاشة)،
  /// أو `null` فلا فرز. الفرز نفسه يبقى على الشاشة؛ هذه علامته البصرية فقط:
  /// سهمٌ بلون التمييز على رأس العمود يبيّن العمود والاتجاه معًا، فلا يحتاج
  /// المستخدم أن يتذكّر ما ضغط. تجاهلها الشاشةُ ⇒ لا سهم كما كان.
  final int? sortIndex;

  /// اتجاه [sortIndex]: تصاعدي (الافتراضي) أو تنازلي.
  final bool sortAsc;

  /// `null` (الافتراضي) ⇒ كل الصفوف كما هي اليوم. عدد صحيح ⇒ ترقيم صفحات
  /// داخلي بهذا الحجم، مع شريطٍ تحت الجدول. الفرز خارج مسؤولية هذه الودجة
  /// تمامًا (كما هو الحال دائمًا هنا) — فمن أراد إعادة الصفحة إلى الأولى عند
  /// تغيّر الفرز يُمرِّر `key` يتغيّر معه (كما في `reports_center_screen.dart`)
  /// فتُعاد الودجة بحالةٍ جديدة بدل تمرير حالة فرزٍ إلى مكوّنٍ لا يعرفها.
  final int? pageSize;

  /// إشعارٌ اختياري بفهرس الصفحة الحالية (من صفر) بعد أي تنقّل.
  final ValueChanged<int>? onPageChanged;

  /// `false` (الافتراضي) ⇒ على الجوال (<900) يبقى **جدولًا** بعرضه الطبيعي يُمرَّر
  /// أفقيًّا مع تثبيت العمود الأول ([freezeFirst]) — لا يُضغط في عرض الشاشة ولا
  /// يتحوّل بطاقات. `true` ⇒ كل صف بطاقة على الجوال: للجداول الصغيرة التي لا
  /// تستفيد من التمرير الأفقي. العرض ≥900 يبقى جدولًا دائمًا.
  ///
  /// عمودٌ بعنوانٍ فارغ (`ImdCol('')`، كما تفعل كل أعمدة الإجراءات في
  /// الشاشات القائمة) لا يُعنوَن في البطاقة، بل يُجمَع مع أمثاله في صفّ
  /// إجراءاتٍ أسفلها.
  final bool cards;

  /// خلفية صف الرأس — `null` (الافتراضي) ⇒ الرمادي الفاتح المعتاد `c.tableHead`.
  /// تستعملها جداول الإدخال الكثيفة لتلوين رأسها بلون التمييز، فيتّبع
  /// السمة تلقائيًّا (زمردي داكن في الفاتح، زمردي فاتح في الداكن) بدل لونٍ
  /// صلبٍ واحد يخالف الوضع الداكن.
  final Color? headerBackground;

  /// نص صف الرأس — `null` (الافتراضي) ⇒ `c.muted` المعتاد.
  final Color? headerForeground;

  /// حشوة خلايا الرأس — `null` (الافتراضي) ⇒ 12 أفقيًّا و10 رأسيًّا كالمعتاد.
  final EdgeInsets? headerPadding;

  /// حشوة خلايا الجسم — `null` (الافتراضي) ⇒ 12 أفقيًّا و9 رأسيًّا كالمعتاد.
  /// جداول الإدخال الكثيفة تُضيّقها لتوفير المساحة على عشرات الأسطر.
  final EdgeInsets? cellPadding;

  /// خطوط شبكةٍ بين الخلايا رأسيًّا وأفقيًّا، وإطارٌ خارجيٌّ أغمق قليلًا.
  ///
  /// جدول القراءة يفصل صفوفه بخطٍّ أفقيٍّ وحده — أهدأ للعين حين يُمسح
  /// عموديًّا. أمّا جدول الإدخال فخلاياه حقولٌ تُملأ واحدةً واحدة، فحدُّ
  /// كل خليةٍ يبيّن أين تبدأ وأين تنتهي.
  final bool gridLines;

  /// حجم خطّ خلايا الجسم — `null` (الافتراضي) ⇒ 13.5 كالمعتاد.
  final double? cellFontSize;

  /// خلايا الجسم بلا حشوةٍ ولا محاذاة: ما فيها يملأ الخلية كلّها (عرضًا
  /// وارتفاعًا) فتلتصق الحقول بخطوط الشبكة بلا فراغ. لجداول الإدخال
  /// ([ImdEntryTable]) — يتولّى محتوى الخلية ارتفاعه (`ImdEntryTable.cell`).
  final bool flushCells;

  /// القيم الخام لكل خلية بترتيب [rows] وأعمدتها — **تفعّل التصفية والتجميع**.
  ///
  /// الخلايا ودجاتٌ جاهزة لا يُعرف نصّها، فلا تُصفَّى ولا تُجمَّع من تلقاء
  /// نفسها؛ تُمرِّر الشاشة ما يقابل كل خليةٍ من قيمة (`null` لخلية الإجراءات).
  /// بلا [values] يبقى الجدول كما كان تمامًا (لا شريط أدوات ولا أيقونات رؤوس).
  ///
  /// التصفية على مستوى العمود: أيقونةٌ في رأسه تفتح قائمةً بقيمه المميّزة.
  /// الفهارس التي تُمرَّر إلى [onRowTap] و[rowMenu] و[rowColor] تبقى **مطلقةً**
  /// من أول [rows] مهما صُفّي الجدول أو جُمِّع.
  ///
  /// صفّ الإجماليات [footer] تحسبه الشاشة من كل البيانات: لا يتبع التصفية.
  final List<List<Object?>>? values;

  /// السماح بتصفية الأعمدة (مع [values]).
  final bool filterable;

  /// السماح بالتجميع حسب عمود (مع [values]).
  final bool groupable;

  /// تثبيت العمود الأول أثناء التمرير الأفقي (حين يضيق العرض عن [minWidth]).
  ///
  /// `null` (الافتراضي) ⇒ يتبع [values]: مفعَّلٌ لجداول القراءة الكبيرة التي
  /// مرّرت قيمها، ومعطَّلٌ لغيرها. السبب أن التثبيت يرسم **نسخةً ثانية** من
  /// الجدول مقصوصةً على العمود الأول (فيتطابق ارتفاع الصفوف حتمًا)، فكل ودجةٍ في
  /// الجدول — أزرار الإجراءات وحقول الإدخال — تُبنى مرتين. هذا مقبولٌ في جدول قراءةٍ
  /// خلاياه نصوصٌ وأزرارٌ عديمة الحالة، وغير مقبولٍ في جدول إدخالٍ ([flushCells])
  /// خلاياه حقولٌ بحالة؛ وعمودٌ أول بلا عنوان (أزرار إجراءات) لا يُثبَّت أيضًا.
  /// النسخة الثانية مستبعَدةٌ من شجرة الإتاحة. عرض العمود المثبَّت [ImdCol.width] أو 120.
  final bool? freezeFirst;

  @override
  State<ImdTable> createState() => _ImdTableState();
}

class _ImdTableState extends State<ImdTable> {
  int _hover = -1;
  int _headerHover = -1;
  int _page = 0;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  /// متحكّم تمرير نسخة العمود المثبَّت — يُزامَن مع [_vScroll].
  final _vScroll2 = ScrollController();
  final _find = TextEditingController();
  String _findQ = '';

  /// القيم المسموحة لكل عمود مصفّى (فهرس العمود ← نصوص القيم).
  final Map<int, Set<String>> _filters = {};

  /// العمود المجمَّع عليه، أو `null` فلا تجميع.
  int? _groupBy;

  /// قيم المجموعات المطويّة.
  final Set<String> _collapsed = {};

  ImdRecordSink? _sink;

  bool get _tools => widget.values != null && widget.columns.isNotEmpty && (widget.filterable || widget.groupable);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ImdRecordScope.maybeOf(context);
    if (!identical(next, _sink)) {
      _sink?.remove(this);
      _sink = next;
    }
  }

  @override
  void initState() {
    super.initState();
    _vScroll.addListener(() => _syncV(_vScroll, _vScroll2));
    _vScroll2.addListener(() => _syncV(_vScroll2, _vScroll));
  }

  /// يطابق تمرير النسختين رأسيًّا (الأصل والعمود المثبَّت).
  void _syncV(ScrollController from, ScrollController to) {
    if (!from.hasClients || !to.hasClients) return;
    final o = from.offset;
    if ((to.offset - o).abs() < .5) return;
    to.jumpTo(o.clamp(to.position.minScrollExtent, to.position.maxScrollExtent).toDouble());
  }

  @override
  void dispose() {
    _sink?.remove(this);
    _hScroll.dispose();
    _vScroll.dispose();
    _vScroll2.dispose();
    _find.dispose();
    super.dispose();
  }

  /// نصّ قيمة الخلية — أساس التصفية والتجميع. الفارغ يُعرض «(فارغ)».
  String _text(int row, int col) {
    final v = widget.values![row];
    final x = col < v.length ? v[col] : null;
    return x?.toString().trim() ?? '';
  }

  static const String _blank = '(فارغ)';
  String _shown(String t) => t.isEmpty ? _blank : t;

  /// الصفوف المطابقة لكل المرشِّحات، بترتيبها الأصلي.
  List<int> _visibleRows() {
    final n = widget.rows.length;
    if (!_tools || (_filters.isEmpty && _findQ.isEmpty)) return List<int>.generate(n, (i) => i);
    final q = _findQ.toLowerCase();
    final colCount = widget.columns.length;
    bool found(int i) {
      if (q.isEmpty) return true;
      for (var j = 0; j < colCount; j++) {
        if (_text(i, j).toLowerCase().contains(q)) return true;
      }
      return false;
    }

    return [
      for (var i = 0; i < n; i++)
        if (found(i) && _filters.entries.every((f) => f.value.contains(_text(i, f.key)))) i,
    ];
  }

  /// قيم عمودٍ المميّزة مرتَّبة (رقميًّا إن كانت كلها أرقامًا).
  List<String> _distinct(int col) {
    final list = <String>{for (var i = 0; i < widget.rows.length; i++) _text(i, col)}.toList();
    final nums = {for (final t in list) t: num.tryParse(t)};
    if (list.isNotEmpty && list.every((t) => t.isEmpty || nums[t] != null)) {
      list.sort((a, b) => (nums[a] ?? double.negativeInfinity).compareTo(nums[b] ?? double.negativeInfinity));
    } else {
      list.sort();
    }
    return list;
  }

  Future<void> _editFilter(int col) async {
    final all = _distinct(col);
    final r = await showImdModal<Set<String>>(
      context,
      title: 'تصفية: ${widget.columns[col].label}',
      icon: 'sliders',
      maxWidth: 380,
      builder: (ctx) => ImdColumnFilterBody(values: all, selected: _filters[col], shown: _shown),
    );
    if (r == null || !mounted) return;
    setState(() {
      _page = 0;
      // اختيار كل القيم = لا تصفية (ولا يُحتفظ بمجموعةٍ تتقادم مع البيانات).
      if (r.length == all.length) {
        _filters.remove(col);
      } else {
        _filters[col] = r;
      }
    });
  }

  void _clearFilters() => setState(() {
        _filters.clear();
        _page = 0;
      });

  /// بنود العرض: صفوفٌ (فهرسها المطلق) أو رؤوس مجموعات.
  List<_TableItem> _items(List<int> visible) {
    final g = _groupBy;
    if (!_tools || g == null) return [for (final i in visible) _TableItem.row(i)];
    final groups = <String, List<int>>{};
    for (final i in visible) {
      groups.putIfAbsent(_text(i, g), () => []).add(i);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys) ...[
        _TableItem.group(k, groups[k]!.length, _collapsed.contains(k)),
        if (!_collapsed.contains(k)) for (final i in groups[k]!) _TableItem.row(i),
      ],
    ];
  }

  void _toggleGroup(String key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
        _page = 0;
      });

  /// يُبلّغ شريط الحالة بعدد الصفوف — بعد الإطار لا أثناءه (الإبلاغ يُعيد بناء الشريط).
  void _report(int shown) {
    final sink = _sink;
    if (sink == null) return;
    final total = widget.rows.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sink.report(this, shown: shown, total: total);
    });
  }

  /// شريط أدوات الجدول: بحثٌ فوري، لوحة التجميع (إسقاط رأس عمود)، قائمتا التجميع
  /// والتصفية، وشارات الفلاتر الفعّالة. يظهر مع [ImdTable.values] وحدها.
  Widget _toolbar(BuildContext context, int shown) {
    final c = context.imd;
    final cols = widget.columns;
    final desktop = !ImdBp.of(context).mobile;
    final labelled = [
      for (var j = 0; j < cols.length; j++)
        if (cols[j].label.isNotEmpty) j,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
              child: TextField(
                controller: _find,
                onChanged: (v) => setState(() {
                  _findQ = v.trim();
                  _page = 0;
                }),
                style: TextStyle(fontSize: ImdDensity.cellFont, color: c.text),
                decoration: imdFieldDecoration(context, dense: true).copyWith(
                  hintText: 'بحث فوري…',
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
                    child: ImdIcon('search', size: 14, color: c.faint),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: _findQ.isEmpty
                      ? null
                      : InkWell(
                          onTap: () => setState(() {
                            _find.clear();
                            _findQ = '';
                          }),
                          child: Padding(padding: const EdgeInsets.all(10), child: ImdIcon('x', size: 12, color: c.muted)),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
            if (widget.groupable && !desktop)
              ImdMenuButton<int>(
                label: _groupBy == null ? 'تجميع حسب' : 'مجمَّع: ${cols[_groupBy!].label}',
                icon: 'folder',
                small: true,
                items: (_) => [
                  if (_groupBy != null) const PopupMenuItem<int>(value: -1, child: Text('إلغاء التجميع')),
                  for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label)),
                ],
                onSelected: (j) => _setGroup(j < 0 ? null : j),
              ),
            if (widget.filterable && !desktop)
              ImdMenuButton<int>(
                label: 'تصفية',
                icon: 'sliders',
                small: true,
                items: (_) => [for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label))],
                onSelected: _editFilter,
              ),
            // الفلاتر الفعّالة برتقاليةٌ: لونٌ يلفت إلى أن ما يُرى ليس كل البيانات.
            for (final e in _filters.entries)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _editFilter(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        '${cols[e.key].label}: ${e.value.length == 1 ? _shown(e.value.first) : '${e.value.length} قيم'}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.warn)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _filters.remove(e.key);
                        _page = 0;
                      }),
                      child: ImdIcon('x', size: 11, color: c.warn),
                    ),
                  ]),
                ),
              ),
            if (_filters.isNotEmpty)
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.muted),
                child: const Text('مسح الفلاتر', style: TextStyle(fontSize: 12)),
              ),
            if (_filters.isNotEmpty || _findQ.isNotEmpty)
              Text('${nf(shown)} من ${nf(widget.rows.length)}', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        if (widget.groupable && desktop) ...[
          const SizedBox(height: 6),
          _groupPanel(context),
        ],
      ]),
    );
  }

  void _setGroup(int? col) => setState(() {
        _groupBy = col;
        _collapsed.clear();
        _page = 0;
      });

  /// لوحة التجميع: يُسقَط عليها رأس عمودٍ لتجميع الجدول به، وتعرض العمود الحالي.
  Widget _groupPanel(BuildContext context) {
    final c = context.imd;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => widget.columns[d.data].label.isNotEmpty,
      onAcceptWithDetails: (d) => _setGroup(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hot ? c.accentSoft : c.subtle,
            border: Border.all(color: hot ? c.accent : c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            ImdIcon('folder', size: 13, color: c.muted),
            const SizedBox(width: 8),
            if (_groupBy == null)
              Text('اسحب رأس العمود هنا للتجميع', style: TextStyle(fontSize: 12, color: c.muted))
            else
              InkWell(
                onTap: () => _setGroup(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.columns[_groupBy!].label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text2)),
                    const SizedBox(width: 6),
                    ImdIcon('x', size: 11, color: c.muted),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// صفّ رأس مجموعة. ارتفاعه ثابتٌ وعرض خليته الأولى صفر عمدًا: نصّه يمتدّ فوق
  /// الأعمدة المجاورة (فارغةٍ) من غير أن يوسّع العمود الأول بقياسه الذاتي.
  TableRow _groupRow(BuildContext context, _TableItem g) {
    final c = context.imd;
    final h = ImdDensity.isHigh ? 26.0 : 34.0;
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
      const SizedBox(width: 6),
      Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
      const SizedBox(width: 8),
      Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
    return TableRow(
      key: ValueKey('group:${g.key}'),
      decoration: BoxDecoration(color: c.subtle, border: Border(bottom: BorderSide(color: c.tableRowLine))),
      children: [
        for (var j = 0; j < widget.columns.length; j++)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: MouseRegion(
              cursor: ImdCursor.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleGroup(g.key!),
                child: SizedBox(
                  width: j == 0 ? 0 : null,
                  height: h,
                  child: j == 0
                      ? Stack(clipBehavior: Clip.none, children: [
                          PositionedDirectional(start: 12, top: 0, bottom: 0, child: Center(child: label)),
                        ])
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// رأس مجموعة في عرض البطاقات.
  Widget _groupCard(BuildContext context, _TableItem g) {
    final c = context.imd;
    return InkWell(
      onTap: () => _toggleGroup(g.key!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
          ),
          Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
      ),
    );
  }

  /// لونٌ محايد خفيف جدًّا فوق سطح الجدول — يعمل في كل سمة (فاتحة/داكنة/محروقات)
  /// لأنه مشتقٌّ من ألوان السمة الحالية لا لونًا ثابتًا.
  Color _zebraColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(scheme.onSurface.withValues(alpha: .035), scheme.surface);
  }

  void _openMenu(int row, Offset at) {
    final items = widget.rowMenu?.call(row) ?? const <ImdMenuItem>[];
    showImdContextMenu(context, at, items);
  }

  Widget _cell(ImdCol col, Widget child, {required int row, EdgeInsets? pad}) {
    // `row >= 0` = خليةُ جسمٍ؛ الرأس والإجماليات يبقيان بحشوتهما.
    final Widget w0 = (widget.flushCells && row >= 0)
        ? child
        : Padding(
            padding: pad ?? widget.cellPadding ?? EdgeInsets.symmetric(horizontal: 12, vertical: ImdDensity.cellPadV),
            child: Align(
              alignment: col.center ? Alignment.center : AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: child,
            ),
          );
    Widget w = w0;
    if (row >= 0) {
      w = MouseRegion(
        cursor: widget.onRowTap != null ? ImdCursor.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = row),
        onExit: (_) => setState(() => _hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
          onSecondaryTapDown: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          onLongPressStart: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          child: w,
        ),
      );
    }
    // «middle» لا «fill»: خلايا fill لا تُسهم في ارتفاع الصف فينهار الصف إذا كانت كلها كذلك.
    return TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: w);
  }

  Widget _header(BuildContext context, ImdCol col, int index) {
    final c = context.imd;
    final sorted = widget.sortIndex == index;
    final headerFg = widget.headerForeground;
    final label = ImdEmojiText(col.label,
        iconSize: 13,
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: sorted ? FontWeight.w700 : FontWeight.w600,
            color: headerFg ?? (sorted ? c.accent : c.muted),
            height: 1.3));
    // السهم على العمود المفروز وحده: لو وُضع على كل عمودٍ قابلٍ للفرز لاتّسعت
    // كل الأعمدة (عرضها ذاتيٌّ من محتواها) وضاق الجدول بلا طائل.
    final text = !sorted
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 4),
              ImdIcon(widget.sortAsc ? 'chevron-up' : 'chevron-down', size: 12, color: c.accent),
            ],
          );
    Widget head = _headerWithFilter(context, index, text);
    // رأس العمود يُسحب إلى لوحة التجميع (سطح المكتب).
    if (_tools && widget.groupable && widget.columns[index].label.isNotEmpty && !ImdBp.of(context).mobile) {
      head = Draggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4)),
            child: Text(widget.columns[index].label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onAccent)),
          ),
        ),
        child: head,
      );
    }
    if (widget.onHeaderTap == null) return head;
    final hovered = _headerHover == index;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _headerHover = index),
      onExit: (_) => setState(() => _headerHover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onHeaderTap!(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: hovered ? c.headerHover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: head,
        ),
      ),
    );
  }

  /// أيقونة تصفية العمود بجوار عنوانه — سطح المكتب فقط (على اللمس يُستعمل زر
  /// «تصفية» في شريط الأدوات: أيقونةٌ بحجم 12 لا تصلح هدفَ إصبع).
  Widget _headerWithFilter(BuildContext context, int index, Widget text) {
    if (!_tools || !widget.filterable || widget.columns[index].label.isEmpty || ImdBp.of(context).mobile) return text;
    final c = context.imd;
    final active = _filters.containsKey(index);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: text),
      const SizedBox(width: 4),
      Tooltip(
        message: 'تصفية العمود',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _editFilter(index),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ImdIcon('sliders', size: 11, color: active ? c.accent : c.faint),
          ),
        ),
      ),
    ]);
  }

  /// عدد الصفحات لحجمٍ معطًى — صفحة واحدة على الأقل حتى لو كانت القائمة فارغة،
  /// فلا يُقسَّم على صفر ولا تُعرض «صفحة صفر من صفر».
  int _pageCount(int totalRows, int pageSize) => totalRows == 0 ? 1 : (totalRows / pageSize).ceil();

  /// عنوانٌ صغيرٌ فوق خليته — بنفس أسلوب `ImdLabeled` في `imd_form.dart` حرفيًّا
  /// (لا استيراد منه: هذا الملف أساسٌ لا يعتمد على ملفاتٍ فوقه).
  Widget _labeledCell(BuildContext context, String label, Widget cell, {Color? labelColor}) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor ?? c.text2, height: 1.6)),
        const SizedBox(height: 2),
        cell,
      ],
    );
  }

  /// بطاقة صفٍّ واحد على الشاشات الضيّقة (`cards: true`) — بديل صف الجدول.
  /// أعمدة `label` غير الفارغة تُكدَّس معنونةً، وأعمدة `label` الفارغة
  /// (أزرار الإجراءات دومًا في الشاشات القائمة) تُجمَع في صفٍّ أسفل البطاقة.
  Widget _card(BuildContext context, int i) {
    final c = context.imd;
    final cols = widget.columns;
    final row = i < widget.rows.length ? widget.rows[i] : const <Widget>[];
    final fields = <Widget>[];
    final actions = <Widget>[];
    for (var j = 0; j < cols.length; j++) {
      final cell = j < row.length ? row[j] : const SizedBox.shrink();
      if (cols[j].label.isEmpty) {
        actions.add(cell);
      } else {
        if (fields.isNotEmpty) fields.add(const SizedBox(height: 8));
        fields.add(_labeledCell(context, cols[j].label, cell));
      }
    }
    final hoverBg = c.rowHover;
    final bg = widget.onRowTap != null && _hover == i
        ? hoverBg
        : widget.rowColor?.call(i) ?? (widget.zebra && i.isOdd ? _zebraColor(context) : c.surface);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13.5, color: c.text, height: 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...fields,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
    if (widget.onRowTap == null && widget.rowMenu == null) return card;
    return MouseRegion(
      cursor: widget.onRowTap != null ? ImdCursor.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = i),
      onExit: (_) => setState(() => _hover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(i),
        onSecondaryTapDown: widget.rowMenu == null ? null : (d) => _openMenu(i, d.globalPosition),
        onLongPressStart: widget.rowMenu == null ? null : (d) => _openMenu(i, d.globalPosition),
        child: card,
      ),
    );
  }

  /// بطاقة الإجماليات — نظير صفّ [ImdTable.footer] في وضع البطاقات، بنفس
  /// ألوان صفّه في الجدول (`accentSoft`/`accent`) لتمييزها عن بطاقات البيانات.
  Widget _footerCard(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final footer = widget.footer!;
    final fields = <Widget>[];
    for (var j = 0; j < cols.length; j++) {
      if (cols[j].label.isEmpty) continue;
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 8));
      final cell = j < footer.length ? footer[j] : const SizedBox.shrink();
      fields.add(_labeledCell(context, cols[j].label, cell, labelColor: c.accent));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.accent, height: 1.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: fields),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final rows = widget.rows;
    final pageSize = widget.pageSize;
    final visible = _visibleRows();
    final items = _items(visible);
    _report(visible.length);
    // مُشتقّةٌ من `_page` لا مُساويةٌ له: لو ضاقت `rows` (تصفيةٌ جديدة) دون
    // أن يتغيّر `key` الودجة، تبقى `_page` القديمة صالحةً هنا للعرض فورًا بدل
    // صفحةٍ فارغة، وتُصحَّح القيمة المخزَّنة عند أول تنقّل.
    final pageCount = pageSize == null ? 1 : _pageCount(items.length, pageSize);
    // `int.clamp` يُعيد `num` لا `int` (موروثةٌ من `num`)، فـ`.toInt()` هنا
    // ضرورةٌ لا زخرفة — بدونها لا تُقبل `page`/`pageEnd` فهارس مباشرةً.
    final int page = _page.clamp(0, pageCount - 1).toInt();
    final int pageStart = pageSize == null ? 0 : page * pageSize;
    final int pageEnd = pageSize == null ? items.length : (pageStart + pageSize).clamp(0, items.length).toInt();

    if (widget.cards && ImdBp.of(context).mobile && rows.isNotEmpty && cols.isNotEmpty) {
      final cardsArea = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var k = pageStart; k < pageEnd; k++) ...[
            if (items[k].isGroup)
              _groupCard(context, items[k])
            else
              widget.rowKeys == null
                  ? _card(context, items[k].row)
                  : KeyedSubtree(key: widget.rowKeys![items[k].row], child: _card(context, items[k].row)),
            if (k != pageEnd - 1 || widget.footer != null) SizedBox(height: ImdDensity.cardGap),
          ],
          if (widget.footer != null) _footerCard(context),
        ],
      );
      if (pageSize == null && !_tools) return cardsArea;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tools) _toolbar(context, visible.length),
          cardsArea,
          if (pageSize != null)
            _pager(context, page: page, pageCount: pageCount, pageStart: pageStart, pageEnd: pageEnd, total: items.length),
        ],
      );
    }

    // جدولٌ بلا صفوف لا جسم له يُمرَّر تحت الرأس، فلا رأس ثابتًا له.
    final sticky = widget.maxHeight != null && items.isNotEmpty && cols.isNotEmpty;
    final mobile = ImdBp.of(context).mobile;

    // الجوال بلا بطاقات: جدولٌ بعرضٍ طبيعيٍّ يُمرَّر أفقيًّا (والعمود الأول مثبَّت)
    // بدل ضغط الأعمدة في عرض الشاشة حتى لا يُقرأ منها شيء.
    var minW = widget.minWidth;
    if (mobile && !widget.cards && cols.isNotEmpty) {
      final natural = [for (final col in cols) col.width ?? (col.flex > 1 ? 180.0 : 110.0)].fold<double>(0, (a, b) => a + b);
      if (minW == null || natural > minW) minW = natural;
    }

    /// الجدول بإطاره. [frozenWidth] ≠ null ⇒ العمود الأول بهذا العرض الثابت (نسخة
    /// التثبيت). [vc] متحكّم التمرير الرأسي، و[bar] هل يُرسم شريط التمرير.
    Widget buildTable(ScrollController vc, {double? frozenWidth, bool bar = true}) {
      final Widget body;
      if (cols.isEmpty) {
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: ImdEmojiText(widget.empty,
              style: TextStyle(fontSize: ImdDensity.cellFont, fontWeight: FontWeight.w500, color: c.muted, height: 1.5)),
        );
      } else {
        // الرأس الثابت يفصل الجدول جدولين، فعرض العمود لا يصحّ أن يُقاس من
        // محتواه: لكلٍّ محتواه فيختلفان. الصريح يبقى، وما عداه نسبيٌّ — وكلاهما
        // يُحسب من عرض الحاوية وحده فيتطابق الجدولان.
        final widths = <int, TableColumnWidth>{
          for (var j = 0; j < cols.length; j++)
            j: (j == 0 && frozenWidth != null)
                ? FixedColumnWidth(frozenWidth)
                : cols[j].width != null
                    ? FixedColumnWidth(cols[j].width!)
                    : (cols[j].auto && !sticky)
                        ? const _HtmlColumnWidth()
                        : FlexColumnWidth(cols[j].flex.toDouble()),
        };
        final headerRow = TableRow(
          decoration: BoxDecoration(
            color: widget.headerBackground ?? c.tableHead,
            border: widget.headerBackground == null ? Border(bottom: BorderSide(color: c.line)) : null,
          ),
          children: [
            for (var j = 0; j < cols.length; j++)
              _cell(
                cols[j],
                _header(context, cols[j], j),
                row: -1,
                pad: widget.headerPadding ?? EdgeInsets.symmetric(horizontal: 12, vertical: ImdDensity.headPadV),
              ),
          ],
        );
        // `i` فهرسُ الصفّ المطلق في `rows` (لا موضعه في الصفحة ولا بعد التصفية):
        // `zebra` و`rowColor` و`onRowTap` تبقى كما لو لم يُفعَّل ترقيمٌ ولا تصفيةٌ
        // أصلًا — تمريرها فهرسًا محليًّا كان يكسر أيّ استخدامٍ يعتمد على فهرس
        // القائمة الكاملة. و`k` موضعه في بنود العرض، لتمييز آخر صفٍّ معروض.
        TableRow bodyRow(int i, int k) => TableRow(
              key: widget.rowKeys?[i],
              decoration: BoxDecoration(
                color: _hover == i
                    ? c.rowHover
                    : (widget.rowColor?.call(i) ?? (widget.zebra && i.isOdd ? _zebraColor(context) : null)),
                // آخر صفٍّ من الصفحة **المعروضة** لا آخر صفٍّ في القائمة كلها،
                // وإلا بقي خط الفاصل تحت كل الصفحات إلا الأخيرة. ومع
                // [gridLines] يرسمها `TableBorder` فلا تُزدوج هنا.
                border: (widget.gridLines || (k == pageEnd - 1 && widget.footer == null))
                    ? null
                    : Border(bottom: BorderSide(color: c.tableRowLine)),
              ),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(
                          fontSize: widget.cellFontSize ?? ImdDensity.cellFont, color: c.text, height: 1.5),
                      child: j < rows[i].length ? rows[i][j] : const SizedBox.shrink(),
                    ),
                    row: i,
                  ),
              ],
            );
        final bodyRows = <TableRow>[
          for (var k = pageStart; k < pageEnd; k++)
            if (items[k].isGroup) _groupRow(context, items[k]) else bodyRow(items[k].row, k),
          if (widget.footer != null && items.isNotEmpty)
            TableRow(
              decoration: BoxDecoration(color: c.accentSoft),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: ImdDensity.cellFont, fontWeight: FontWeight.w700, color: c.accent, height: 1.5),
                      child: j < widget.footer!.length ? widget.footer![j] : const SizedBox.shrink(),
                    ),
                    row: -1,
                  ),
              ],
            ),
        ];
        // الشبكة من `TableBorder` لا من زخرفة كل خلية: هي وحدها تعرف حدود
        // الأعمدة بعد توزيع العرض، فلا ينزاح خطٌّ عن عموده.
        final grid = !widget.gridLines
            ? null
            : TableBorder(
                verticalInside: BorderSide(color: c.line),
                horizontalInside: BorderSide(color: c.tableRowLine),
              );
        if (items.isEmpty) {
          // الجدول الفارغ يُبقي رأسه ويعرض سطرًا رماديًّا صغيرًا — بلا حالةٍ فارغةٍ كبيرة.
          final emptyText = rows.isEmpty ? widget.empty : 'لا نتائج مطابقة للتصفية';
          body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Table(columnWidths: widths, border: grid, children: [headerRow]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: ImdEmojiText(emptyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.faint, height: 1.4)),
            ),
          ]);
        } else if (!sticky) {
          body = Table(columnWidths: widths, border: grid, children: [headerRow, ...bodyRows]);
        } else {
          final vTable = SingleChildScrollView(
            controller: vc,
            child: Table(columnWidths: widths, border: grid, children: bodyRows),
          );
          // `Flexible` لا `Expanded`: جدولٌ أقصر من السقف يأخذ ارتفاعه لا السقف،
          // فلا يبقى تحته فراغٌ أبيض. وشريط التمرير ظاهرٌ دائمًا ورفيع (كلاسيكي).
          body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // الرأس بلا شبكةٍ أفقية: حدّه السفلي هو الفاصل بينه وبين الجسم،
              // ورسمُهما معًا يُثخّن الخط.
              Table(
                columnWidths: widths,
                border: grid == null ? null : TableBorder(verticalInside: grid.verticalInside),
                children: [headerRow],
              ),
              Flexible(
                child: bar
                    ? Scrollbar(controller: vc, thumbVisibility: true, thickness: 6, child: vTable)
                    : vTable,
              ),
            ],
          );
        }
      }
      Widget table = Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          // إطارٌ خارجيٌّ أغمق قليلًا مع الشبكة، فيُقرأ الجدول كتلةً واحدة
          // لا شبكةً سائبة.
          border: Border.all(color: widget.gridLines ? c.lineStrong : c.line),
          borderRadius: BorderRadius.circular(mobile ? 10 : ImdSizes.radius),
        ),
        child: body,
      );
      // السقف على الإطار كلّه (الرأس + الجسم)، وبه يصير للعمود `Flexible` داخله
      // ارتفاعٌ محدود فيُمرَّر — بلا حدٍّ أعلى لا تمريرَ أصلًا داخل صفحةٍ مُمرَّرة.
      if (sticky) {
        table = ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.maxHeight!), child: table);
      }
      return table;
    }

    Widget tableArea;
    final minWidth = minW;
    if (minWidth == null || items.isEmpty) {
      tableArea = buildTable(_vScroll);
    } else {
      tableArea = LayoutBuilder(builder: (context, cons) {
        if (cons.maxWidth >= minWidth) return buildTable(_vScroll);
        final frozen = (widget.freezeFirst ?? widget.values != null) &&
            !widget.flushCells &&
            cols.isNotEmpty &&
            cols[0].label.isNotEmpty;
        final fw = frozen ? (cols[0].width ?? 120.0) : null;
        // شريط تمرير ظاهر، وإلا لم يعرف
        // المستخدم أن هناك أعمدة خارج الشاشة (لا تمرير أفقي بعجلة الفأرة).
        final scroller = Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          thickness: 6,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: buildTable(_vScroll, frozenWidth: fw)),
            ),
          ),
        );
        if (!frozen) return scroller;
        // العمود الأول: نسخةٌ من الجدول بعرضه الكامل مقصوصةٌ على العمود وحده، لا
        // تتحرك مع التمرير الأفقي فيبقى ظاهرًا فوق الأصل.
        return Stack(children: [
          scroller,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 10,
            width: fw,
            child: ExcludeSemantics(
              child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minWidth: minWidth,
                maxWidth: minWidth,
                child: buildTable(_vScroll2, frozenWidth: fw, bar: false),
              ),
            ),
            ),
          ),
        ]);
      });
    }
    final tableWithTools = !_tools
        ? tableArea
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [_toolbar(context, visible.length), tableArea],
          );
    if (pageSize == null || items.isEmpty) return tableWithTools;
    // شريط الترقيم تحت الجدول وخارج تمريره الأفقي: هو معلومةٌ عن كامل
    // البيانات لا عمودٍ من أعمدته، فيبقى ظاهرًا مهما مُرِّر الجدول أفقيًّا.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tableWithTools,
        _pager(context, page: page, pageCount: pageCount, pageStart: pageStart, pageEnd: pageEnd, total: items.length),
      ],
    );
  }

  void _goToPage(int target, int pageCount) {
    final int next = target.clamp(0, pageCount - 1).toInt();
    setState(() => _page = next);
    widget.onPageChanged?.call(next);
  }

  Widget _pager(
    BuildContext context, {
    required int page,
    required int pageCount,
    required int pageStart,
    required int pageEnd,
    required int total,
  }) {
    final c = context.imd;
    final textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.muted);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('عرض ${nf(pageStart + 1)}–${nf(pageEnd)} من ${nf(total)}', style: textStyle),
          Row(mainAxisSize: MainAxisSize.min, children: [
            // «السابق» نحو بداية القائمة، و«التالي» نحو تاليها — بلا فرقٍ يدويٍّ
            // بين فاتح/داكن ولا بين نظام تشغيل، فالأيقونتان مسارا SVG ثابتان.
            ImdIconButton(
              icon: 'chevron-right',
              tooltip: 'الصفحة السابقة',
              onPressed: page > 0 ? () => _goToPage(page - 1, pageCount) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('صفحة ${nf(page + 1)} من ${nf(pageCount)}', style: textStyle),
            ),
            ImdIconButton(
              icon: 'chevron-left',
              tooltip: 'الصفحة التالية',
              onPressed: page < pageCount - 1 ? () => _goToPage(page + 1, pageCount) : null,
            ),
          ]),
        ],
      ),
    );
  }
}

/// صفٌّ فارغ بإطار جدول («لا …») للقوائم الخالية.
class ImdEmptyBox extends StatelessWidget {
  const ImdEmptyBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ImdTable(columns: const [], rows: const [], empty: text);
}

/// رسالة سوداء عائمة.
void showImdToast(BuildContext context, String message, {bool error = false}) {
  final c = context.imd;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverse,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 420,
      duration: const Duration(milliseconds: 3200),
      content: ImdEmojiText(
        error && !message.startsWith('✖') ? '✖ $message' : message,
        // الإشعار يُعرض في طبقة فوق الشاشة فلا يرث خط التطبيق تلقائيًا،
        // فيُؤخذ من القالب صراحةً ليتبع الخط المختار في الإعدادات.
        style: TextStyle(
          color: c.onInverse,
          fontWeight: FontWeight.w500,
          fontSize: 14,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
      ),
    ));
}

/// نافذة بزوايا 16.
Future<T?> showImdModal<T>(
  BuildContext context, {
  required String title,
  String? icon,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? actions,
  double maxWidth = 560,

  /// يُبنى بسياق الحوار الداخلي (كـ[actions]) ويُستدعى عند Enter/Numpad Enter
  /// — لحوارات التأكيد البسيطة ذات إجراءٍ أساسيٍّ واحد لا لبس فيه. يُترك
  /// `null` (الافتراضي) لحوارات النماذج التي قد تحوي حقول نصٍّ متعددة
  /// الأسطر، فلا يُصادَر Enter منها.
  VoidCallback Function(BuildContext)? onEnter,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: context.imd.scrim,
    builder: (ctx) {
      final c = ctx.imd;
      Widget dialog = Dialog(
        backgroundColor: c.surface,
        elevation: 10,
        shadowColor: c.shadowBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (icon != null) ...[ImdIcon(icon, size: 18, color: c.accent), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  ImdIconButton(icon: 'x', onPressed: () => Navigator.of(ctx).pop()),
                ]),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: builder(ctx))),
                if (actions != null) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions(ctx)),
                ],
              ],
            ),
          ),
        ),
      );
      if (onEnter != null) {
        final enterAction = onEnter(ctx);
        dialog = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): enterAction,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): enterAction,
          },
          child: Focus(autofocus: true, child: dialog),
        );
      }
      return dialog;
    },
  );
}

/// حوار تأكيدٍ بسؤالٍ وزرَّي موافقة وإلغاء.
Future<bool> imdConfirm(
  BuildContext context,
  String message, {
  String ok = 'تأكيد',
  String cancel = 'إلغاء',
  bool danger = false,
}) async {
  final r = await showImdModal<bool>(
    context,
    title: 'تأكيد',
    icon: danger ? 'alert' : 'info',
    maxWidth: 440,
    builder: (ctx) => Text(message, style: TextStyle(fontSize: 14, color: ctx.imd.text, height: 1.7)),
    actions: (ctx) => [
      ImdButton.outline(label: cancel, onPressed: () => Navigator.of(ctx).pop(false)),
      ImdButton(
        label: ok,
        kind: danger ? ImdBtnKind.danger : ImdBtnKind.primary,
        onPressed: () => Navigator.of(ctx).pop(true),
      ),
    ],
    onEnter: (ctx) => () => Navigator.of(ctx).pop(true),
  );
  return r ?? false;
}

/// شبكة أعمدة متجاوبة (`grid-2/3/4`): عدد الأعمدة يقل مع ضيق العرض.
class ImdGrid extends StatelessWidget {
  const ImdGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.gap = 16,
    this.minItemWidth = 220,
  });

  final List<Widget> children;
  final int columns;
  final double gap;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      var cols = columns;
      while (cols > 1 && (cons.maxWidth - gap * (cols - 1)) / cols < minItemWidth) {
        cols--;
      }
      final w = (cons.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// منطقة المحتوى القابلة للتمرير، بحشوةٍ تتبع عرض الشاشة.
class ImdPage extends StatelessWidget {
  const ImdPage({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  static EdgeInsets paddingOf(BuildContext context) {
    final bp = ImdBp.of(context);
    if (bp.mobile) return ImdSizes.mainPaddingMobile;
    if (bp.tablet) return ImdSizes.mainPaddingTablet;
    final base = bp.wide ? ImdSizes.mainPadding : ImdSizes.mainPaddingMid;
    // الكثافة العالية تضيّق حشوة الصفحة على سطح المكتب لتتّسع المساحة للبيانات.
    final f = ImdDensity.spaceFactor;
    return f == 1 ? base : EdgeInsets.symmetric(horizontal: base.horizontal / 2 * f, vertical: base.vertical / 2 * f);
  }

  @override
  Widget build(BuildContext context) {
    // مضمَّنةٌ داخل شاشةٍ تمرّر نفسها: لا تمريرَ داخل تمرير ولا حشوةً مضاعفة.
    if (ImdEmbedScope.of(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return SingleChildScrollView(
      controller: controller,
      padding: paddingOf(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// حوار إدخال نصٍّ واحد.
Future<String?> imdPrompt(BuildContext context, String message, {String ok = 'تأكيد', String initial = ''}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showImdModal<String>(
    context,
    title: message,
    icon: 'edit',
    maxWidth: 460,
    builder: (ctx) => TextField(
      controller: ctrl,
      autofocus: true,
      maxLines: 3,
      minLines: 1,
      style: TextStyle(fontSize: 14, color: ctx.imd.text),
      decoration: imdFieldDecoration(ctx),
      onSubmitted: (v) => Navigator.of(ctx).pop(v),
    ),
    actions: (ctx) => [
      ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
      ImdButton(label: ok, onPressed: () => Navigator.of(ctx).pop(ctrl.text)),
    ],
  );
  ctrl.dispose();
  return r;
}
