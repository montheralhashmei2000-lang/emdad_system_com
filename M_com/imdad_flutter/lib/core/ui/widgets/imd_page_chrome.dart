import 'package:flutter/material.dart';
import '../imd_density.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';
import 'imd_buttons.dart';

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
