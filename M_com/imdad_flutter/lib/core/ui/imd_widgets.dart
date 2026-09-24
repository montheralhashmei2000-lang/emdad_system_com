import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'imd_icon.dart';
import 'imd_tokens.dart';

// مكوّنات الواجهة المشتركة — كل مكوّن يقابل صنف CSS في نسخة الويب، بنفس المقاسات
// المقيسة من الصفحة الفعلية (getComputedStyle) لا بالتقدير.

/// `.page-title` + `.page-sub`
class ImdPageTitle extends StatelessWidget {
  const ImdPageTitle({super.key, required this.title, this.icon, this.subtitle, this.trailing});

  final String title;
  final String? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final mobile = ImdBp.of(context).mobile;
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
              Flexible(
                child: Text(title,
                    style: TextStyle(
                        fontSize: mobile ? 19 : 22,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                        height: mobile ? 1.5 : 1.4)),
              ),
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: TextStyle(fontSize: mobile ? 12 : 13.5, color: c.muted, height: 1.6)),
            ),
        ],
      ),
    );
  }
}

/// `.panel` / `.icard` — بطاقة بيضاء بحد رفيع وزوايا 12.
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

/// `.btn` بأنواعه (`btn-p`, `btn-o`, `btn-d`, `btn-blue`, `btn-warn`, `btn-purple`) و`.btn-sm`.
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
        border = _hover ? (c.isDark ? const Color(0xFF52525B) : const Color(0xFFB9B9C6)) : c.lineStrong;
      case ImdBtnKind.danger:
        bg = _hover ? (c.isDark ? const Color(0x40F97066) : const Color(0xFFFDD5D1)) : c.dangerSoft;
        fg = c.danger;
      case ImdBtnKind.blue:
        bg = _hover ? const Color(0xFF1849A9) : (c.isDark ? const Color(0xFF2E6BE6) : c.info);
        fg = Colors.white;
      case ImdBtnKind.warn:
        bg = _hover ? const Color(0xFF93370D) : const Color(0xFFB54708);
        fg = Colors.white;
      case ImdBtnKind.purple:
        bg = _hover ? const Color(0xFF53389E) : const Color(0xFF6941C6);
        fg = Colors.white;
      case ImdBtnKind.dark:
        bg = _hover ? c.text2 : c.text;
        fg = c.isDark ? const Color(0xFF171717) : Colors.white;
    }
    final fs = widget.small ? 12.5 : 13.5;
    final pad = widget.small
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
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
              height: widget.height,
              constraints: widget.height == null ? BoxConstraints(minHeight: ImdSizes.touchMin) : null,
              padding: pad,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(widget.small ? 8 : 10),
                border: border == null ? null : Border.all(color: border),
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
  Widget build(BuildContext context) {
    final b = ImdButton(label: '', icon: icon, onPressed: onPressed, kind: kind, small: true);
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// `.tabbtn` — تبويبات كبسولية؛ النشط أسود.
class ImdPillTabs<T> extends StatelessWidget {
  const ImdPillTabs({super.key, required this.tabs, required this.value, required this.onChanged, this.wrap = true, this.gap = 8});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// false ⇒ صف واحد بفجوة 6 (`.itabs` قابل للتمرير أفقيًا).
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
    final fg = on ? (c.isDark ? const Color(0xFF171717) : Colors.white) : c.text2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
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

/// `.tabs` — مجموعة مقاطع بخلفية رمادية والنشط أبيض (مثل «وحدة مستفيدة / مطبخ / جهة»).
class ImdSegmented<T> extends StatelessWidget {
  const ImdSegmented({super.key, required this.tabs, required this.value, required this.onChanged});

  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in tabs)
            GestureDetector(
              onTap: () => onChanged(t.value),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: t.value == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: t.value == value
                        ? const [BoxShadow(color: Color(0x1A101828), blurRadius: 3, offset: Offset(0, 1))]
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
    );
  }
}

enum ImdTone { ok, off, pend, code, err, info }

/// `.chip` بأنواعه.
class ImdChip extends StatelessWidget {
  const ImdChip(this.label, {super.key, this.tone = ImdTone.off, this.icon, this.onTap});

  final String label;
  final ImdTone tone;
  final String? icon;
  final VoidCallback? onTap;

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
  Widget build(BuildContext context) {
    final (bg, fg) = colors(context.imd, tone);
    // `.chip{white-space:nowrap}` — أصغر عرض للشريحة هو عرض نصها كاملًا،
    // فلا يضغطها عمود الجدول إلى ما دونه (IntrinsicWidth يجعل الأصغر = الأكبر).
    final chip = IntrinsicWidth(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[ImdIcon(icon!, size: 13, color: fg), const SizedBox(width: 6)],
        // الرموز التعبيرية داخل الشارات تُحوَّل أيقونات كما يفعل `ui-icons.js` في الويب.
        ImdEmojiText(label,
            iconSize: 13,
            gap: 4,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.6)),
      ]),
    ));
    if (onTap == null) return chip;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: chip));
  }
}

/// `.note-box` — صندوق ملاحظة أصفر.
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

/// `.alert.err|warn|ok` و`.print-tip`
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

/// زخرفة `.fld` لحقول الإدخال.
InputDecoration imdFieldDecoration(
  BuildContext context, {
  String? hint,
  String? prefixIcon,
  Widget? suffix,
  bool dense = false,
  bool readOnly = false,
}) {
  final c = context.imd;
  OutlineInputBorder b(Color col, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: col, width: w),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.faint, fontSize: 14),
    filled: true,
    fillColor: readOnly ? c.bg : c.surface,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
    prefixIcon: prefixIcon == null
        ? null
        : Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
            child: ImdIcon(prefixIcon, size: 16, color: c.faint),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    border: b(c.lineStrong),
    enabledBorder: b(c.lineStrong),
    disabledBorder: b(c.lineStrong),
    focusedBorder: b(c.accent, 1),
    errorBorder: b(c.danger),
    focusedErrorBorder: b(c.danger),
  );
}

/// `.field` — عنوان فوق الحقل (13/600) ثم الحقل.
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
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
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
                decoration: imdFieldDecoration(context, hint: hint, readOnly: readOnly, prefixIcon: prefixIcon),
              ),
        ],
      ),
    );
  }
}

/// `select.fld`
class ImdSelect<T> extends StatelessWidget {
  const ImdSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.dense = false,
  });

  final List<(T, String)> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final has = items.any((e) => e.$1 == value);
    return DropdownButtonFormField<T>(
      initialValue: has ? value : null,
      isExpanded: true,
      icon: ImdIcon('chevron-down', size: 16, color: c.muted),
      dropdownColor: c.surface,
      borderRadius: BorderRadius.circular(10),
      // الخط من القالب لا ثابتًا: المستخدم يختاره من الإعدادات.
      style: TextStyle(fontSize: 14, color: c.text, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
      hint: hint == null ? null : Text(hint!, style: TextStyle(color: c.faint, fontSize: 14)),
      decoration: imdFieldDecoration(context, dense: dense),
      items: [
        for (final e in items)
          DropdownMenuItem<T>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
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

/// عرض عمود بأسلوب `table-layout:auto` في المتصفح: يبدأ بعرض المحتوى الأقصى،
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

/// `.twrap > table.u` — جدول قراءة بيانات كثيفة: رأس رمادي فاتح، صفوف بخط فاصل، وتظليل عند المرور.
class ImdTable extends StatefulWidget {
  const ImdTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty = 'لا توجد بيانات',
    this.onRowTap,
    this.rowColor,
    this.footer,
    this.minWidth,
    this.onHeaderTap,
  });

  final List<ImdCol> columns;
  final List<List<Widget>> rows;
  final String empty;
  final ValueChanged<int>? onRowTap;
  final Color? Function(int index)? rowColor;
  final List<Widget>? footer;

  /// `style="min-width:…"` — تمرير أفقي إذا ضاقت المساحة عنه.
  final double? minWidth;

  /// ضغط رأس العمود (`th[data-k]{cursor:pointer}`) — يُستخدم للفرز.
  final ValueChanged<int>? onHeaderTap;

  @override
  State<ImdTable> createState() => _ImdTableState();
}

class _ImdTableState extends State<ImdTable> {
  int _hover = -1;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Widget _cell(ImdCol col, Widget child, {required int row, EdgeInsets? pad}) {
    Widget w = Padding(
      padding: pad ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Align(
        alignment: col.center ? Alignment.center : AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: child,
      ),
    );
    if (row >= 0) {
      w = MouseRegion(
        cursor: widget.onRowTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = row),
        onExit: (_) => setState(() => _hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
          child: w,
        ),
      );
    }
    // «middle» لا «fill»: خلايا fill لا تُسهم في ارتفاع الصف فينهار الصف إذا كانت كلها كذلك.
    return TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: w);
  }

  Widget _header(BuildContext context, ImdCol col, int index) {
    final c = context.imd;
    final text = ImdEmojiText(col.label,
        iconSize: 13,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.muted, height: 1.3));
    if (widget.onHeaderTap == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onHeaderTap!(index),
        child: text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final rows = widget.rows;
    final Widget body;
    if (rows.isEmpty || cols.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: ImdEmojiText(widget.empty,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.muted, height: 1.5)),
      );
    } else {
      body = Table(
        columnWidths: {
          for (var j = 0; j < cols.length; j++)
            j: cols[j].width != null
                ? FixedColumnWidth(cols[j].width!)
                : cols[j].auto
                    ? const _HtmlColumnWidth()
                    : FlexColumnWidth(cols[j].flex.toDouble()),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: c.tableHead, border: Border(bottom: BorderSide(color: c.line))),
            children: [
              for (var j = 0; j < cols.length; j++)
                _cell(
                  cols[j],
                  _header(context, cols[j], j),
                  row: -1,
                  pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: BoxDecoration(
                color: _hover == i ? (c.isDark ? const Color(0xFF26262A) : c.tableHead) : widget.rowColor?.call(i),
                border: (i == rows.length - 1 && widget.footer == null)
                    ? null
                    : Border(bottom: BorderSide(color: c.tableRowLine)),
              ),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 13.5, color: c.text, height: 1.5),
                      child: j < rows[i].length ? rows[i][j] : const SizedBox.shrink(),
                    ),
                    row: i,
                  ),
              ],
            ),
          if (widget.footer != null)
            TableRow(
              decoration: BoxDecoration(color: c.accentSoft),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.accent, height: 1.5),
                      child: j < widget.footer!.length ? widget.footer![j] : const SizedBox.shrink(),
                    ),
                    row: -1,
                  ),
              ],
            ),
        ],
      );
    }
    final table = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdBp.of(context).mobile ? 10 : ImdSizes.radius),
      ),
      child: body,
    );
    final minW = widget.minWidth;
    if (minW == null || rows.isEmpty) return table;
    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth >= minW) return table;
      // شريط تمرير ظاهر كما في `.twrap{overflow:auto}` بالويب، وإلا لم يعرف
      // المستخدم أن هناك أعمدة خارج الشاشة (لا تمرير أفقي بعجلة الفأرة).
      return Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minW, child: table),
          ),
        ),
      );
    });
  }
}

/// صف فارغ بإطار (`.twrap` بنص «لا …») كما يظهر في الويب عند خلو القوائم.
class ImdEmptyBox extends StatelessWidget {
  const ImdEmptyBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ImdTable(columns: const [], rows: const [], empty: text);
}

/// `.toast` — رسالة سوداء عائمة.
void showImdToast(BuildContext context, String message, {bool error = false}) {
  final c = context.imd;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.isDark ? const Color(0xFF303036) : c.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 420,
      duration: const Duration(milliseconds: 3200),
      content: ImdEmojiText(
        error && !message.startsWith('✖') ? '✖ $message' : message,
        // الإشعار يُعرض في طبقة فوق الشاشة فلا يرث خط التطبيق تلقائيًا،
        // فيُؤخذ من القالب صراحةً ليتبع الخط المختار في الإعدادات.
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
      ),
    ));
}

/// `.modal` — نافذة بزوايا 16.
Future<T?> showImdModal<T>(
  BuildContext context, {
  required String title,
  String? icon,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? actions,
  double maxWidth = 560,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x73111111),
    builder: (ctx) {
      final c = ctx.imd;
      return Dialog(
        backgroundColor: c.surface,
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
    },
  );
}

/// تأكيد (`confirm()` في الويب).
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

/// `.main` — منطقة المحتوى القابلة للتمرير بحشوة الويب حسب العرض.
class ImdPage extends StatelessWidget {
  const ImdPage({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  static EdgeInsets paddingOf(BuildContext context) {
    final bp = ImdBp.of(context);
    if (bp.mobile) return ImdSizes.mainPaddingMobile;
    if (bp.tablet) return ImdSizes.mainPaddingTablet;
    if (bp.wide) return ImdSizes.mainPadding;
    return ImdSizes.mainPaddingMid;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: paddingOf(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// `prompt()` في الويب — نافذة إدخال نص واحد.
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
