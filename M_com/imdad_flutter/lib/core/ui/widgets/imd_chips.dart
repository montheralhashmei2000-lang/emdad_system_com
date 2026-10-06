import 'package:flutter/material.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';

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
