import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'imd_icon_data.dart';
import 'imd_tokens.dart';

/// أيقونة من مكتبة النظام: مسار SVG بخط 2 داخل `viewBox 24`، بلون النص الحالي.
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

  /// أيقونات تُضاف هنا يدويًا لأن `imd_icon_data.dart` مولَّد فلا يُعدَّل.
  static const Map<String, String> _extra = {
    'log-in': '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><path d="M10 17l5-5-5-5"/><path d="M15 12H3"/>',
    'log-out': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>',
    // كانت تُرسم نقطةً بديلة لأنها غير موجودة في الجدول المولَّد.
    'key': '<path d="m21 2-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/>',
    'copy': '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    'qr-code': '<rect width="5" height="5" x="3" y="3" rx="1"/><rect width="5" height="5" x="16" y="3" rx="1"/><rect width="5" height="5" x="3" y="16" rx="1"/><path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/><path d="M12 7v3a2 2 0 0 1-2 2H7"/><path d="M3 12h.01"/><path d="M12 3h.01"/><path d="M12 16v.01"/><path d="M16 12h1"/><path d="M21 12v.01"/><path d="M12 21v-1"/>',
    'list': '<line x1="8" x2="21" y1="6" y2="6"/><line x1="8" x2="21" y1="12" y2="12"/><line x1="8" x2="21" y1="18" y2="18"/><line x1="3" x2="3.01" y1="6" y2="6"/><line x1="3" x2="3.01" y1="12" y2="12"/><line x1="3" x2="3.01" y1="18" y2="18"/>',
    'mail': '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    'archive': '<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
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

/// نصٌّ قد يبدأ برمزٍ تعبيري ⇒ يُستبدل الرمز بأيقونة النظام المقابلة ويُعرض
/// قبل النص، فتتوحّد الرموز في الواجهة بدل أن تتبع خطّ نظام التشغيل.
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
