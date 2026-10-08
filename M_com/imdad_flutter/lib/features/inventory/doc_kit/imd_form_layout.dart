import 'package:flutter/material.dart';
import '../../../core/ui/imd_format.dart';
import '../../../core/ui/imd_icon.dart';
import '../../../core/ui/imd_layout.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';
import 'imd_guides.dart';


/// شبكة حقول بيانات السند: أعمدةٌ متجاوبة — أربعةٌ على سطح المكتب (>900px)
/// وعمودان على الجوال، بفجوةٍ ضيقة كفجوة جدول الإدخال ([ImdSizes.compactGap]
/// و[ImdSizes.compactRowGap]). الفورمة كثيفةٌ لا فسيحة، فلا تُنافس الجدول
/// نفسه على مساحة الشاشة.
class ImdFormGrid extends StatelessWidget {
  const ImdFormGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cols = ImdBp.of(context).mobile ? 2 : 4;
    return LayoutBuilder(builder: (ctx, cons) {
      const gap = ImdSizes.compactGap;
      final w = (cons.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: ImdSizes.compactRowGap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}


/// قسمٌ قابلٌ للطي لتعليمات/ملاحظات السند — مطويٌّ افتراضيًّا فلا يشغل
/// مساحةً رأسية، وعند التوسيع يظهر بعرضٍ كامل أسفل رأسه.
class ImdCollapsibleSection extends StatefulWidget {
  const ImdCollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.icon = 'file',
  });
  final String title;
  final Widget child;
  final String icon;

  @override
  State<ImdCollapsibleSection> createState() => _ImdCollapsibleSectionState();
}


class _ImdCollapsibleSectionState extends State<ImdCollapsibleSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            ImdIcon(widget.icon, size: 14, color: c.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
            ),
            ImdIcon(_open ? 'chevron-up' : 'chevron-down', size: 14, color: c.muted),
          ]),
        ),
      ),
      if (_open) Padding(padding: const EdgeInsets.only(top: 4), child: widget.child),
    ]);
  }
}


/// عنوان حقل صغير داخل صفوف الأصناف (`label style="font-size:11px"` بحد أدنى 15 وهامش 4).
class ImdRowLabel extends StatelessWidget {
  const ImdRowLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final compact = ImdCompact.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 2 : 4),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: compact ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              color: context.imd.text2,
              height: compact ? 1.2 : 1.6)),
    );
  }
}


/// بطاقة سطر صنف: كتلة واحدة تجمع كل بيانات الصنف.
///
/// [index] رقم السطر يُعرض في زاويته، و[trailing] سطر معلومات أسفله (مكافئ
/// الكمية بالوحدة الأساسية مثلًا). الترقيم يفصل الأصناف بصريًا حين تكثر، وقد
/// صار ألزم بعد أن صارت الأسطر تُجمَّع وتُعاد توزيعها تلقائيًا.
class ImdRvRow extends StatelessWidget {
  const ImdRvRow({super.key, required this.child, this.index, this.trailing});

  final Widget child;
  final int? index;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // **البطاقة تُعلن كثافتها فتتبعها حقولها كلها** — فلا يُمرَّر `compact`
    // إلى كل حقلٍ في خمس شاشات، ولا يُنسى في أوّل حقلٍ يُضاف بعدها.
    return ImdCompact(
      child: Container(
        margin: const EdgeInsets.only(bottom: ImdSizes.compactRowGap),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (index == null)
            child
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6, top: 16),
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    nf(index!.toDouble()),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: c.accent),
                  ),
                ),
              ),
              Expanded(child: child),
            ]),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}


/// شبكة حقول سطر الصنف على الجوال — الصنف ووحدته وكميته في صفٍّ واحد.
///
/// الكمية بلا وحدتها رقمٌ بلا معنى، فالثلاثة وحدةُ قراءةٍ واحدة. وكان التخطيط
/// في شاشات السندات الأربع يضع «الصنف والوحدة» في صفّ ثم «الكمية» وحدها في
/// صفٍّ تحته: تنفصل الكميةُ عن وحدتها، وتبتعد الوحدةُ عن الرقم الذي تصفه،
/// ويبقى في الصفّ الثاني فراغٌ عريضٌ لا يشغله شيء.
///
/// فإن ضاق العرض عن الثلاثة مجتمعةً نزل **الصنف** وحده إلى صفّه — هو أطول
/// الحقول نصًّا وأحوجها إلى العرض — وبقيت الوحدة والكمية مقترنتين تحته. أمّا
/// الحقول الثانوية ([extras]: نوع العملية، تاريخ الانتهاء) فلها صفٌّ ثالث لا
/// تزاحم به الأساسية.
class ImdEntryRowGrid extends StatelessWidget {
  const ImdEntryRowGrid({
    super.key,
    required this.item,
    required this.unit,
    required this.qty,
    this.itemLabel = 'الصنف',
    this.unitLabel = 'الوحدة',
    this.qtyLabel = 'الكمية',
    this.meta,
    this.leading,
    this.extras = const <(String, Widget)>[],
    this.actions = const <Widget>[],
  });

  final Widget item;
  final Widget unit;
  final Widget qty;
  final String itemLabel;
  final String unitLabel;
  final String qtyLabel;

  /// سطر معلوماتٍ تحت الصنف (الرصيد المتاح مثلًا).
  final String? meta;

  /// حقلٌ يسبق الوحدة ويشاركها صفَّها — «الوحدة المستفيدة» في الصرف الموجَّه.
  /// وجودُه يُنزل الصنف إلى صفّه دائمًا: أربعةُ حقولٍ لا تجتمع في سطرٍ واحد.
  final (String, Widget)? leading;

  /// حقولٌ ثانوية في صفٍّ تحت الأساسية.
  final List<(String, Widget)> extras;

  /// أزرار آخر السطر (حذف، نسخ) — تحاذي الحقول لا عناوينها.
  final List<Widget> actions;

  /// أقلّ عرضٍ تجتمع عنده الثلاثة: الصنف لا يقلّ عن ١٣٠ ليُقرأ اسمه.
  static const double _oneRowMin = 130 + _unitW + _qtyW + 3 * ImdSizes.compactGap + 40;
  static const double _unitW = 96;
  static const double _qtyW = 78;

  Widget _labeled(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [ImdRowLabel(label), field],
      );

  /// الأزرار تحت عنوانٍ شفّاف: يحجز ارتفاع العنوان فتحاذي الأزرارُ الحقولَ
  /// مهما تغيّر ارتفاع العنوان بالكثافة — بدل حشوةٍ علويةٍ برقمٍ مُقدَّر.
  Widget _actionsColumn() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Opacity(opacity: 0, child: ImdRowLabel(' ')),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: ImdSizes.compactGap);
    final itemColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ImdRowLabel(itemLabel),
        item,
        if (meta != null) ImdRowMeta(meta!),
      ],
    );
    final extrasRow = extras.isEmpty
        ? null
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < extras.length; i++) ...[
              if (i > 0) gap,
              Expanded(child: _labeled(extras[i].$1, extras[i].$2)),
            ],
          ]);

    return LayoutBuilder(builder: (context, box) {
      final oneRow = leading == null && box.maxWidth >= _oneRowMin;
      final rows = <Widget>[];
      if (oneRow) {
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: itemColumn),
          gap,
          SizedBox(width: _unitW, child: _labeled(unitLabel, unit)),
          gap,
          SizedBox(width: _qtyW, child: _labeled(qtyLabel, qty)),
          if (actions.isNotEmpty) ...[gap, _actionsColumn()],
        ]));
      } else {
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: itemColumn),
          if (actions.isNotEmpty) ...[gap, _actionsColumn()],
        ]));
        rows.add(const SizedBox(height: ImdSizes.compactGap));
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leading != null) ...[
            Expanded(child: _labeled(leading!.$1, leading!.$2)),
            gap,
          ],
          Expanded(child: _labeled(unitLabel, unit)),
          gap,
          Expanded(child: _labeled(qtyLabel, qty)),
        ]));
      }
      if (extrasRow != null) {
        rows.add(const SizedBox(height: ImdSizes.compactGap));
        rows.add(extrasRow);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      );
    });
  }
}


/// بياناتٌ ثانوية لسطر الصنف تُعرض تحته بخطٍّ أصغر.
class ImdRowMeta extends StatelessWidget {
  const ImdRowMeta(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final compact = ImdCompact.of(context);
    return Padding(
      padding: EdgeInsets.only(top: compact ? 3 : 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 13 : 16),
        child: ImdEmojiText(text,
            iconSize: compact ? 11 : 12,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.w500,
                color: context.imd.muted)),
      ),
    );
  }
}


/// صندوق عملية الأصناف القابلة للتعبئة.
class ImdCyBox extends StatelessWidget {
  const ImdCyBox(
      {super.key,
      required this.label,
      required this.value,
      required this.options,
      required this.onChanged});
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.noteBg,
        border: Border.all(color: c.noteBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ImdEmojiText(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.noteText)),
            ImdFit(
                width: 180,
                child: ImdSelect<String>(
                    value: value,
                    items: options,
                    onChanged: (v) => onChanged(v ?? value))),
          ]),
    );
  }
}


/// عنصر فحص (`paintValidationBox`).
class ImdCheck {
  const ImdCheck(this.level, this.title, this.desc);
  final String level; // ok | warn | err
  final String title;
  final String desc;
}


/// `paintValidationBox(elId, title, items)`
class ImdValidationBox extends StatelessWidget {
  const ImdValidationBox({super.key, required this.title, required this.items});
  final String title;
  final List<ImdCheck> items;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    if (items.isEmpty) {
      return ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ImdEmojiText('✅ $title',
                style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
          ),
          Text('لا توجد ملاحظات حرجة حاليًا — تقدر تكمل بثقة.',
              style: TextStyle(fontSize: 12.5, color: c.muted)),
        ]),
      );
    }
    return ImdSoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title,
              style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
        ),
        ImdStatusList(items: [
          for (final it in items)
            (
              it.level == 'err' ? 'err' : (it.level == 'warn' ? 'warn' : ''),
              it.title,
              it.desc
            ),
        ]),
      ]),
    );
  }
}


/// مقاطع نوع التوجيه (الزر النشط أبيض بظل خفيف).
class ImdTargetPills<T> extends StatelessWidget {
  const ImdTargetPills(
      {super.key,
      required this.tabs,
      required this.value,
      required this.onChanged});
  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(builder: (context, cons) {
        // flex:1 بحد أدنى 90 مع التفاف
        final perRow =
            ((cons.maxWidth + 6) / (90 + 6)).floor().clamp(1, tabs.length);
        final rows = <Widget>[];
        for (var i = 0; i < tabs.length; i += perRow) {
          final slice = tabs.sublist(i, (i + perRow).clamp(0, tabs.length));
          if (i > 0) rows.add(const SizedBox(height: 6));
          rows.add(Row(children: [
            for (var j = 0; j < slice.length; j++) ...[
              if (j > 0) const SizedBox(width: 6),
              Expanded(child: _pill(context, slice[j])),
            ],
          ]));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      }),
    );
  }

  Widget _pill(BuildContext context, ImdTab<T> t) {
    final c = context.imd;
    final on = t.value == value;
    return MouseRegion(
      cursor: ImdCursor.click,
      child: GestureDetector(
        onTap: () => onChanged(t.value),
        child: Container(
          constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: on
                ? [
                    BoxShadow(
                        color: c.shadowHairline,
                        blurRadius: 3,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (t.icon != null) ...[
              ImdIcon(t.icon!, size: 14, color: on ? c.text : c.text2),
              const SizedBox(width: 6)
            ],
            Flexible(
              child: Text(t.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: on ? c.text : c.text2)),
            ),
          ]),
        ),
      ),
    );
  }
}


/// حقل للقراءة فقط بخلفية مخصصة (`readonly style="background:…;font-weight:…"`).
class ImdReadonlyField extends StatelessWidget {
  const ImdReadonlyField(
      {super.key,
      required this.text,
      this.bg,
      this.color,
      this.weight = FontWeight.w900});
  final String text;
  final Color? bg;
  final Color? color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return ConstrainedBox(
      constraints: BoxConstraints(
          minHeight: ImdCompact.of(context)
              ? ImdSizes.compactField
              : ImdSizes.touchMin),
      child: InputDecorator(
        decoration: imdFieldDecoration(context).copyWith(
            fillColor: bg ?? c.fieldFill),
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: ImdCompact.of(context) ? 13 : 14,
                fontWeight: weight,
                color: color ?? c.muted)),
      ),
    );
  }
}
