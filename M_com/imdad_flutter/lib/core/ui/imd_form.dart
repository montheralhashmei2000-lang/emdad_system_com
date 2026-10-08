import 'package:flutter/material.dart';

import 'imd_format.dart';
import 'imd_icon.dart';
import 'imd_layout.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

// عناصر النماذج والبطاقات المتكررة: شريط التبويبات، البطاقة المعنونة، شبكات
// الحقول بعمودين إلى أربعة، عنوان الحقل الصغير، الحقل النصي، صف الشارات،
// ونص التحميل/الفراغ.

/// صف تبويبات أفقي قابل للتمرير بفجوة 6.
class ImdItabs extends StatelessWidget {
  const ImdItabs(
      {super.key,
      required this.tabs,
      required this.value,
      required this.onChanged});
  final List<ImdTab<String>> tabs;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // داخل صفّ إجراءات العنوان ([ImdActionRow]) بلا أيّ حشوةٍ سفلية، وإلا
    // ارتفع التبويب عن الأزرار المجاورة وطفا عن خطّها الأفقي.
    final inline = ImdActionRow.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: inline ? 0 : 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(bottom: inline ? 0 : 6),
        child: ImdPillTabs<String>(
            tabs: tabs, value: value, onChanged: onChanged, wrap: false),
      ),
    );
  }
}

/// حشوة 16 وهامش 14 وعنوان h4.
class ImdICard extends StatelessWidget {
  const ImdICard(
      {super.key, this.title, required this.child, this.icon, this.titleColor});
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
                if (icon != null) ...[
                  ImdIcon(icon!, size: 17, color: c.accent),
                  const SizedBox(width: 6)
                ],
                Expanded(
                  child: Text(title!,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor ?? c.text)),
                ),
              ]),
            ),
          child,
        ],
      ),
    );
  }
}

/// عمودان بفجوة 12، وعمود واحد ≤600.
class ImdF2 extends StatelessWidget {
  const ImdF2(
      {super.key, required this.children, this.cols = 2, this.gap = 12});
  final List<Widget> children;

  /// عدد الأعمدة: ٢ أو ٣ أو ٤، وتنهار إلى عمودٍ واحد على الشاشات الضيّقة.
  final int cols;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // عمودٌ واحد على الجوال بنقطة الفصل الوحيدة (900) كبقية النظام.
    final one = ImdBp.of(context).mobile;
    final n = one ? 1 : cols;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += n) {
      if (i > 0) rows.add(SizedBox(height: gap));
      final slice = children.sublist(i, (i + n).clamp(0, children.length));
      rows.add(n == 1
          ? slice.first
          : ImdEqualRow(gap: gap, children: [
              for (var j = 0; j < n; j++)
                j < slice.length
                    ? Align(alignment: Alignment.topCenter, child: slice[j])
                    : const SizedBox.shrink(),
            ]));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows);
  }
}

/// حقل بعنوان صغير (`label style="font-size:12px;font-weight:700"`).
class ImdLabeled extends StatelessWidget {
  const ImdLabeled(this.label, this.child, {super.key, this.size = 12});
  final String label;
  final Widget child;

  /// 12 ⇒ عنوانٌ أبرز بوزن 700، و11 ⇒ عنوانٌ أصغر بوزن 600 بلون النص الثانوي.
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
    this.suggestions = const [],
    this.errorText,
    this.suffix,
    this.autofocus = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String? hint;

  /// يأخذ التركيز عند أول بناء — لحقلٍ هو سبب فتح الحوار (كمدخل البحث العام)،
  /// لا لحقول النماذج فيُسرق التركيز من أولها.
  final bool autofocus;

  /// ضغط Enter في الحقل (لا يُستدعى في الحقول متعددة الأسطر).
  final ValueChanged<String>? onSubmitted;

  /// رسالة خطأ تظهر تحت الحقل بلون `colorScheme.error`.
  final String? errorText;

  /// عنصر عند نهاية الحقل (يسار الحقل في RTL).
  final Widget? suffix;
  final bool readOnly;
  final bool number;
  final bool dense;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  /// حقل كلمة مرور — يُخفي النص المكتوب.
  final bool obscure;

  /// قيمٌ تُقترح ولا تُلزم — كـ`<datalist>`: الحقل يبقى نصًّا حرًّا، والقائمة
  /// تختصر الكتابة وتوحّد الإملاء («مكتب القائد» لا «مكتب قائد»).
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final field = TextField(
      controller: controller,
      readOnly: readOnly,
      enabled: enabled,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      maxLines: maxLines,
      textAlignVertical: ImdCompact.of(context) ? TextAlignVertical.center : null,
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      style: TextStyle(
          fontSize: ImdCompact.of(context) ? 13 : 14,
          color: enabled ? c.text : c.muted),
      decoration: imdFieldDecoration(context,
          hint: hint,
          readOnly: readOnly || !enabled,
          dense: dense,
          suffix: suffix,
          errorText: errorText),
    );
    final compact = ImdCompact.of(context);
    final fixed = compact && maxLines == 1 && (errorText == null || errorText!.isEmpty);
    // مدمجٌ بسطرٍ واحد ⇒ ارتفاعٌ **مطابقٌ** لا حدٌّ أدنى، فلا يعلو حقلٌ أخاه.
    final fieldBox = suggestions.isEmpty || readOnly || !enabled
          ? field
          : _ImdSuggestions(
              controller: controller,
              items: suggestions,
              onPick: onChanged,
              child: field,
            );
    if (fixed && suggestions.isEmpty) {
      return SizedBox(height: ImdSizes.compactField, child: fieldBox);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? ImdSizes.compactField : ImdSizes.touchMin),
      child: fieldBox,
    );
  }
}

/// قائمة اقتراحاتٍ تحت الحقل، تُفتح بالضغط على السهم وتُغلق بالاختيار.
///
/// لا تُبنى على [Autocomplete]: ذاك يملك متحكّمه الخاص، وحقولُ النظام كلها
/// تُدار بمتحكّمٍ خارجي يُقرأ عند الحفظ.
class _ImdSuggestions extends StatefulWidget {
  const _ImdSuggestions({
    required this.controller,
    required this.items,
    required this.child,
    this.onPick,
  });

  final TextEditingController controller;
  final List<String> items;
  final Widget child;
  final ValueChanged<String>? onPick;

  @override
  State<_ImdSuggestions> createState() => _ImdSuggestionsState();
}

class _ImdSuggestionsState extends State<_ImdSuggestions> {
  final MenuController _menu = MenuController();

  void _pick(String v) {
    imdSetText(widget.controller, v);
    widget.onPick?.call(v);
    _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // The list floats in an overlay menu, so it never grows the field's own
    // box (cells in entry tables have a fixed row height).
    return Row(children: [
      Expanded(child: widget.child),
      const SizedBox(width: 6),
      MenuAnchor(
        controller: _menu,
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surface),
          maximumSize: const WidgetStatePropertyAll(Size(320, 280)),
        ),
        menuChildren: [
          for (final v in widget.items)
            MenuItemButton(
              onPressed: () => _pick(v),
              child: Text(v, style: TextStyle(fontSize: 13, color: c.text2)),
            ),
        ],
        builder: (context, controller, _) => ImdIconButton(
          icon: controller.isOpen ? 'chevron-up' : 'chevron-down',
          tooltip: 'اقتراحات',
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    ]);
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

/// نص تحميل/فراغ رمادي.
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
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.imd.muted),
      );
}

/// شريط أدواتٍ بحقل بحث: الحقل يأخذ عرض السطر كاملًا فتنزل الأزرار تحته،
/// و`inline: true` ⇒ الحقل والأزرار في سطرٍ واحد.
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
      Row(children: [
        Expanded(child: field),
        for (final l in leading) ...[const SizedBox(width: 6), l]
      ]),
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
      children: [
        for (final l in lines)
          Text('• $l', style: TextStyle(fontSize: 13, height: 2, color: c.text))
      ],
    );
  }
}

/// `input type=date` — قيمة YYYY-MM-DD مع منتقي التاريخ.
class ImdDateField extends StatelessWidget {
  const ImdDateField(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static String _display(String v) {
    final d = DateTime.tryParse(v);
    if (d == null) return 'يوم-شهر-سنة';
    return fmtDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: enabled ? ImdCursor.click : SystemMouseCursors.basic,
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
        child: SizedBox(
          height: ImdCompact.of(context) ? ImdSizes.compactField : ImdSizes.touchMin,
          child: InputDecorator(
            expands: true,
            textAlignVertical: TextAlignVertical.center,
            decoration: imdFieldDecoration(context, readOnly: !enabled).copyWith(
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: ImdIcon('calendar', size: 16, color: c.muted),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            // عرض حقل date في كروم بالعربية: يوم/شهر/سنة بأرقام هندية.
            child: Text(_display(value),
                textAlign: TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: ImdCompact.of(context) ? 12.5 : 14,
                    color: value.isEmpty ? c.faint : c.text)),
          ),
        ),
      ),
    );
  }
}

/// `<input type="checkbox">` مع نصه — مربع 18px بحدود السمة ووزن نص 500.
class ImdCheckbox extends StatelessWidget {
  const ImdCheckbox(
      {super.key, required this.value, required this.label, this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = onChanged != null;
    return MouseRegion(
      cursor: on ? ImdCursor.click : SystemMouseCursors.basic,
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
                border:
                    Border.all(color: value ? c.accent : c.line, width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: value
                  // على خلفية التمييز، فلونه onAccent لا أبيضَ ثابتًا: في
                  // الداكن التمييز فاتحٌ (#10B981) فالعلامة البيضاء تبهت عليه.
                  ? ImdIcon('check', size: 13, color: c.onAccent)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ImdEmojiText(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: on ? c.text : c.muted)),
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

/// قائمةٌ أو حقلٌ + زرّ («+» إضافة سريعة) في **مجموعة إدخالٍ** واحدة: الاثنان
/// بارتفاعٍ واحد، وحدودهما ملتصقة بفاصلٍ رفيعٍ واحد داخل إطارٍ واحدٍ مدوَّر.
class ImdInputGroup extends StatelessWidget {
  const ImdInputGroup({super.key, required this.field, required this.button});
  final Widget field;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // المجموعة مدمجةٌ دائمًا: ارتفاعها ارتفاع الحقل المدمج، فتتساوى مع جيرانها
    // في صفّ النموذج.
    final h = ImdSizes.compactField;
    return ImdCompact(
      flush: true,
      child: Container(
        height: h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineStrong),
          borderRadius: BorderRadius.circular(ImdSizes.compactRadius),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: field),
          VerticalDivider(width: 1, thickness: 1, color: c.lineStrong),
          SizedBox(width: h, child: button),
        ]),
      ),
    );
  }
}
