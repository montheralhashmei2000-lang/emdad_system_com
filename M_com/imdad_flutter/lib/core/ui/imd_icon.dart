import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'imd_icon_data.dart';
import 'imd_tokens.dart';

/// أيقونة من مكتبة الويب نفسها (`IMDAD_ICON(name)`): خط 2، viewBox 24، بلون النص الحالي.
class ImdIcon extends StatelessWidget {
  const ImdIcon(this.name, {super.key, this.size, this.color, this.strokeWidth = 2});

  final String name;
  final double? size;
  final Color? color;
  final double strokeWidth;

  /// النغمة اللونية المرافقة للرموز التعبيرية (`ic-success` …).
  static Color? toneColor(BuildContext context, String? tone) {
    final c = context.imd;
    switch (tone) {
      case 'success':
        return c.success;
      case 'danger':
        return c.danger;
      case 'warn':
        return c.warn;
      case 'accent':
        return c.accent;
    }
    return null;
  }

  static final Map<String, String> _cache = {};

  /// أيقونات خاصة بالتطبيق الأصلي، غير موجودة في مكتبة الويب المولَّدة
  /// (`imd_icon_data.dart` يُعاد توليده فلا يُعدَّل يدويًا).
  static const Map<String, String> _extra = {
    'log-in': '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><path d="M10 17l5-5-5-5"/><path d="M15 12H3"/>',
    'log-out': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>',
  };

  static String _svg(String name, double stroke) {
    final key = '$name@$stroke';
    return _cache.putIfAbsent(key, () {
      final body = kImdIconBodies[name] ?? _extra[name] ?? kImdIconBodies['dot'] ?? '';
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
          'stroke="#000" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final fs = style.fontSize ?? 14;
    // .ic { width: 1.15em; height: 1.15em }
    final s = size ?? fs * 1.15;
    final col = color ?? IconTheme.of(context).color ?? style.color ?? context.imd.text;
    return SizedBox(
      width: s,
      height: s,
      child: SvgPicture.string(
        _svg(name, strokeWidth),
        width: s,
        height: s,
        colorFilter: ColorFilter.mode(col, BlendMode.srcIn),
      ),
    );
  }
}

/// نص قد يبدأ برمز تعبيري (كما في نصوص الويب) ⇒ يُعرض أيقونة + نص كما يفعل `ui-icons.js`.
class ImdEmojiText extends StatelessWidget {
  const ImdEmojiText(this.text,
      {super.key,
      this.style,
      this.gap = 6,
      this.iconSize,
      this.textAlign,
      this.maxLines,
      this.overflow});

  final String text;
  final TextStyle? style;
  final double gap;
  final double? iconSize;
  final TextAlign? textAlign;

  /// يمرّران إلى [Text.rich]: بهما يقصّ النص بدل أن يفيض حين يضيق أبوه.
  final int? maxLines;
  final TextOverflow? overflow;

  static final RegExp _re = () {
    final keys = kImdEmojiIcons.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    return RegExp('(${keys.map(RegExp.escape).join('|')})️?\\s?');
  }();

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final def = kImdEmojiIcons[m.group(1)]!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsetsDirectional.only(end: gap),
          child: ImdIcon(def[0], size: iconSize, color: def.length > 1 ? ImdIcon.toneColor(context, def[1]) : null),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow);
  }
}
