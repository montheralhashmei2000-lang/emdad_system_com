import 'package:flutter/material.dart';
import '../../../core/ui/imd_icon.dart';
import '../../../core/ui/imd_layout.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';

/// بطاقةٌ خفيفة بخلفيةٍ باهتة — تُصدَّر بها رؤوس شاشات السندات.
class ImdSoftCard extends StatelessWidget {
  const ImdSoftCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: ImdBp.of(context).mobile
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: child,
    );
  }
}


/// `.workflow-steps > .wstep`
///
/// بلا [activeIndex] شريطُ خطواتٍ ساكن كما كان. ومعه تُعلَّم الخطوات المنجزة
/// والخطوة الحالية، فيرى المستخدم أين هو من السند. ومع [hints] يُعرض تحتها
/// سطرٌ يقول ما ينقصه الآن تحديدًا — وهو ما يسأل عنه من يقف أمام نموذجٍ لا
/// يعرف لماذا لا يُعتمد.
class ImdWorkflowSteps extends StatelessWidget {
  const ImdWorkflowSteps(this.steps, {super.key, this.activeIndex, this.hints})
      : assert(hints == null || hints.length == steps.length,
            'لكل خطوة إرشادها: طول hints يساوي طول steps');
  final List<String> steps;

  /// الخطوة الأرجح التالية بناءً على اكتمال النموذج.
  final int? activeIndex;

  /// إرشادُ كل خطوة — يُعرض منه إرشاد [activeIndex] وحده. الخطوة الأخيرة
  /// تعني «جاهز» فتُعرض بنبرة نجاح لا معلومة.
  final List<String>? hints;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final i = activeIndex;
    final hint = (hints == null || i == null || i < 0 || i >= hints!.length) ? null : hints![i];
    final chips = Padding(
      padding: EdgeInsets.only(bottom: hint == null ? 10 : 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < steps.length; i++)
          Builder(builder: (context) {
            final active = i == activeIndex;
            final done = activeIndex != null && i < activeIndex!;
            final fg = done ? c.success : (active ? c.accent : c.muted);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: done ? c.successSoft : (active ? c.accentSoft : c.surface),
                border: Border.all(color: active ? c.accent : c.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: done ? '✓' : '${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                  TextSpan(text: ' ${steps[i]}'),
                ]),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? c.text : c.text2, height: 1.6),
              ),
            );
          }),
      ]),
    );
    if (hint == null) return chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        chips,
        ImdAlert(hint, tone: i == steps.length - 1 ? ImdTone.ok : ImdTone.info),
      ],
    );
  }
}


/// شبكة أرقامٍ سريعة: بطاقاتٌ صغيرة تتوزّع تلقائيًا بحدٍّ أدنى 170.
class ImdQuickGrid extends StatelessWidget {
  const ImdQuickGrid(this.cards, {super.key});
  final List<(String, String)> cards;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, cons) {
        const gap = 10.0;
        // auto-fit يطوي المسارات الفارغة فتتمدد البطاقات على كامل العرض.
        final cols = ((cons.maxWidth + gap) / (170 + gap))
            .floor()
            .clamp(1, cards.isEmpty ? 1 : cards.length);
        final children = [
          for (final (l, v) in cards)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(ImdSizes.radius),
                boxShadow: imdShadow(c),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: c.muted,
                            height: 1.6)),
                    const SizedBox(height: 6),
                    Text(v,
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                            height: 1.6)),
                  ]),
            ),
        ];
        return ImdGridRows(cols: cols, gap: gap, children: children);
      }),
    );
  }
}


/// سطر إرشادٍ عن الطباعة أسفل بطاقة السند — مطويٌّ افتراضيًّا خلف زر
/// "إظهار التعليمات"، وعند الفتح يظهر بعرضٍ كامل.
class ImdPrintTip extends StatefulWidget {
  const ImdPrintTip(this.text, {super.key});
  final String text;

  @override
  State<ImdPrintTip> createState() => _ImdPrintTipState();
}


class _ImdPrintTipState extends State<ImdPrintTip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: ImdIcon(_open ? 'chevron-up' : 'info', size: 14, color: c.accent),
            label: Text(_open ? 'إخفاء التعليمات' : 'إظهار التعليمات',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: c.accent)),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.infoSoft,
                  border: Border.all(color: c.infoLine),
                  borderRadius: BorderRadius.circular(ImdSizes.radius),
                ),
                child: Text(widget.text,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                        color: c.infoStrong)),
              ),
            ),
          ),
      ],
    );
  }
}


/// غلافٌ يطوي خطوات العمل والإحصاءات السريعة خلف زر «إظهار» — مطويٌّ
/// افتراضيًّا كي لا يشغل مساحةً رأسية، ويُفتح بعرضٍ كامل عند الحاجة.
class ImdGuidePanel extends StatefulWidget {
  const ImdGuidePanel({super.key, required this.child, this.label = 'خطوات العمل والإحصاءات'});
  final Widget child;
  final String label;

  @override
  State<ImdGuidePanel> createState() => _ImdGuidePanelState();
}


class _ImdGuidePanelState extends State<ImdGuidePanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              ImdIcon('info', size: 13, color: c.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_open ? 'إخفاء ${widget.label}' : 'إظهار ${widget.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted)),
              ),
              const SizedBox(width: 4),
              ImdIcon(_open ? 'chevron-up' : 'chevron-down', size: 13, color: c.muted),
            ]),
          ),
        ),
        if (_open) Padding(padding: const EdgeInsets.only(top: 6), child: widget.child),
      ],
    );
  }
}
