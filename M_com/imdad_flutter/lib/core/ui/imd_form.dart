import 'package:flutter/material.dart';

import 'imd_format.dart';
import 'imd_icon.dart';
import 'imd_layout.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

// عناصر النماذج والبطاقات المتكررة في شاشات الويب: `.itabs`، `.icard`، `.f2/.f3/.f4`،
// عنوان الحقل الصغير، `.fld`، `.chips-row`، `.ld`.

/// `.itabs` — صف تبويبات أفقي قابل للتمرير بفجوة 6.
class ImdItabs extends StatelessWidget {
  const ImdItabs({super.key, required this.tabs, required this.value, required this.onChanged});
  final List<ImdTab<String>> tabs;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        child: ImdPillTabs<String>(tabs: tabs, value: value, onChanged: onChanged, wrap: false),
      ),
    );
  }
}

/// `.icard` — حشوة 16 وهامش 14 وعنوان h4.
class ImdICard extends StatelessWidget {
  const ImdICard({super.key, this.title, required this.child, this.icon, this.titleColor});
  final String? title;
  final String? icon;
  final Color? titleColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              if (icon != null) ...[ImdIcon(icon!, size: 17, color: c.accent), const SizedBox(width: 6)],
              Expanded(
                child: Text(title!,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: titleColor ?? c.text)),
              ),
            ]),
          ),
          child,
        ],
      ),
    );
  }
}

/// `.f2` — عمودان بفجوة 12، وعمود واحد ≤600.
class ImdF2 extends StatelessWidget {
  const ImdF2({super.key, required this.children, this.cols = 2, this.gap = 12});
  final List<Widget> children;

  /// 2 = `.f2`، 3 = `.f3`، 4 = `.f4`.
  final int cols;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final one = MediaQuery.sizeOf(context).width <= 600;
    final n = one ? 1 : cols;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += n) {
      if (i > 0) rows.add(SizedBox(height: gap));
      final slice = children.sublist(i, (i + n).clamp(0, children.length));
      rows.add(n == 1
          ? slice.first
          : ImdEqualRow(gap: gap, children: [
              for (var j = 0; j < n; j++)
                j < slice.length ? Align(alignment: Alignment.topCenter, child: slice[j]) : const SizedBox.shrink(),
            ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// حقل بعنوان صغير (`label style="font-size:12px;font-weight:700"`).
class ImdLabeled extends StatelessWidget {
  const ImdLabeled(this.label, this.child, {super.key, this.size = 12});
  final String label;
  final Widget child;

  /// 12 = `font-size:12px;font-weight:700`، 11 = `font-size:11px` (يُلوَّن text-2 بوزن 600 في ui-theme).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ImdEmojiText(label,
            style: TextStyle(
                fontSize: size,
                fontWeight: size <= 11 ? FontWeight.w600 : FontWeight.w700,
                color: size <= 11 ? c.text2 : c.text,
                height: 1.6)),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

class ImdFld extends StatelessWidget {
  const ImdFld({
    super.key,
    required this.controller,
    this.hint,
    this.readOnly = false,
    this.number = false,
    this.dense = false,
    this.enabled = true,
    this.onChanged,
    this.maxLines = 1,
    this.obscure = false,
  });
  final TextEditingController controller;
  final String? hint;
  final bool readOnly;
  final bool number;
  final bool dense;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  /// حقل كلمة مرور — يُخفي النص المكتوب.
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscure,
        onChanged: onChanged,
        maxLines: maxLines,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        style: TextStyle(fontSize: 14, color: enabled ? c.text : c.muted),
        decoration: imdFieldDecoration(context, hint: hint, readOnly: readOnly || !enabled, dense: dense),
      ),
    );
  }
}

class ImdChipsRow extends StatelessWidget {
  const ImdChipsRow({super.key, required this.children, this.bottom = 12});
  final List<Widget> children;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// `.ld` — نص تحميل/فراغ رمادي.
class ImdLd extends StatelessWidget {
  const ImdLd(this.text, {super.key, this.center = false});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final t = ImdLdText(text, center: center);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: t);
  }
}

class ImdLdText extends StatelessWidget {
  const ImdLdText(this.text, {super.key, this.center = false});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => ImdEmojiText(
        text,
        textAlign: center ? TextAlign.center : null,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.imd.muted),
      );
}

/// `.rbar` بحقل بحث: الحقل بعرض كامل (`.fld{width:100%}`) فتنتقل الأزرار لسطر تحته،
/// و`inline: true` ⇒ `.lst-bar` (الحقل والأزرار في سطر واحد).
class ImdSearchBar extends StatelessWidget {
  const ImdSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.actions = const [],
    this.inline = false,
    this.leading = const [],
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final List<Widget> actions;
  final bool inline;

  /// عناصر بجوار الحقل مباشرة (مثل زر الكاميرا).
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final field = ConstrainedBox(
      constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: c.text),
        decoration: imdFieldDecoration(context, hint: hint),
      ),
    );
    if (inline && !ImdBp.of(context).mobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: field),
          for (final l in leading) ...[const SizedBox(width: 6), l],
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ]),
      );
    }
    return ImdRbar(fullFirst: true, children: [
      Row(children: [Expanded(child: field), for (final l in leading) ...[const SizedBox(width: 6), l]]),
      ...actions,
    ]);
  }
}

/// نقاط ملاحظات (`<div>• …</div>` بخط 13 وارتفاع سطر 2).
class ImdBullets extends StatelessWidget {
  const ImdBullets(this.lines, {super.key});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final l in lines) Text('• $l', style: TextStyle(fontSize: 13, height: 2, color: c.text))],
    );
  }
}

/// `input type=date` — قيمة YYYY-MM-DD مع منتقي التاريخ.
class ImdDateField extends StatelessWidget {
  const ImdDateField({super.key, required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static String _display(String v) {
    final d = DateTime.tryParse(v);
    if (d == null) return arDigits('يوم/شهر/سنة');
    return arDigits('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: !enabled
            ? null
            : () async {
                final init = DateTime.tryParse(value) ?? DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: init,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  locale: const Locale('ar'),
                );
                if (d != null) onChanged(isoDay(d));
              },
        child: InputDecorator(
          decoration: imdFieldDecoration(context, readOnly: !enabled).copyWith(
            suffixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: ImdIcon('calendar', size: 16, color: c.muted),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          // عرض حقل date في كروم بالعربية: يوم/شهر/سنة بأرقام هندية.
          child: Text(_display(value),
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 14, color: value.isEmpty ? c.faint : c.text)),
        ),
      ),
    );
  }
}

/// `<input type="checkbox">` مع نصه — مربع 18px بحدود السمة ووزن نص 500.
class ImdCheckbox extends StatelessWidget {
  const ImdCheckbox({super.key, required this.value, required this.label, this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = onChanged != null;
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: on ? () => onChanged!(!value) : null,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? c.accent : c.surface,
                border: Border.all(color: value ? c.accent : c.line, width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: value ? const ImdIcon('check', size: 13, color: Colors.white) : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ImdEmojiText(label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? c.text : c.muted)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// إسناد نص إلى حقل موجود دون كسر موضع المؤشر.
/// الإسناد المباشر (`controller.text = v`) يُبقي التحديد القديم فيصير خارج النص
/// الجديد، فيرمي الإطار «editable.dart: 'isValid': is not true».
void imdSetText(TextEditingController c, String value) {
  if (c.text == value) return;
  c.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}
