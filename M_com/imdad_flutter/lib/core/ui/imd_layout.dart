import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'imd_tokens.dart';

/// `.kpis` — شبكة المؤشرات: auto-fit بحد أدنى 210، وأربعة أعمدة عند ≥1200،
/// وعمودان بفجوة 8 على الجوال، وعمود واحد ≤420.
class ImdKpis extends StatelessWidget {
  const ImdKpis({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bp = ImdBp.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(builder: (context, cons) {
        final gap = bp.mobile ? 8.0 : 14.0;
        int cols;
        if (bp.tiny) {
          cols = 1;
        } else if (bp.mobile) {
          cols = 2;
        } else if (bp.wide) {
          cols = 4;
        } else {
          cols = ((cons.maxWidth + gap) / (210 + gap)).floor().clamp(1, children.length);
        }
        return ImdGridRows(cols: cols, gap: gap, children: children);
      }),
    );
  }
}

/// `.kpi`
class ImdKpi extends StatelessWidget {
  const ImdKpi({super.key, required this.label, required this.value, this.color, this.extra});
  final String label;
  final String value;
  final Color? color;

  /// محتوى إضافي أسفل القيمة (مثل شارة الحالة).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final mobile = ImdBp.of(context).mobile;
    return Container(
      padding: mobile ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.muted, height: 1.6)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  fontSize: mobile ? 22 : 28, fontWeight: FontWeight.w700, color: color ?? c.text, height: 1)),
          if (extra != null) ...[const SizedBox(height: 6), extra!],
        ],
      ),
    );
  }
}

/// صفوف شبكة متساوية الأعمدة بارتفاع موحّد داخل كل صف (سلوك CSS grid: align-items: stretch).
class ImdGridRows extends StatelessWidget {
  const ImdGridRows({super.key, required this.children, required this.cols, this.gap = 16, this.runGap});
  final List<Widget> children;
  final int cols;
  final double gap;
  final double? runGap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, (i + cols).clamp(0, children.length));
      rows.add(ImdEqualRow(
        gap: gap,
        children: [for (var j = 0; j < cols; j++) j < slice.length ? slice[j] : const SizedBox.shrink()],
      ));
      if (i + cols < children.length) rows.add(SizedBox(height: runGap ?? gap));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// صف بأعمدة متساوية العرض، يُمدَّد كل عمود لارتفاع أطول عمود.
/// بديل لـ IntrinsicHeight يعمل مع LayoutBuilder: قياس أول بارتفاع حر ثم تخطيط نهائي بارتفاع ثابت.
class ImdEqualRow extends MultiChildRenderObjectWidget {
  const ImdEqualRow({super.key, required super.children, this.gap = 16});
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEqualRow(gap, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderEqualRow renderObject) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  RenderEqualRow(this._gap, this._dir);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _dir;
  set textDirection(TextDirection v) {
    if (v == _dir) return;
    _dir = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualRowParentData) child.parentData = _EqualRowParentData();
  }

  @override
  void performLayout() {
    final n = childCount;
    if (n == 0) {
      size = constraints.smallest;
      return;
    }
    final width = constraints.maxWidth;
    final colW = ((width - _gap * (n - 1)) / n).clamp(0.0, double.infinity);
    var maxH = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints(minWidth: colW, maxWidth: colW), parentUsesSize: true);
      if (child.size.height > maxH) maxH = child.size.height;
      child = childAfter(child);
    }
    child = firstChild;
    var i = 0;
    while (child != null) {
      // حد أدنى للارتفاع لا قيد ثابت: القيد الثابت يجعل الخلية حدًّا لإعادة التخطيط،
      // فلا يصل تغيّر محتواها (بعد تحميل البيانات) إلى الصف فيحدث فيض.
      child.layout(BoxConstraints(minWidth: colW, maxWidth: colW, minHeight: maxH), parentUsesSize: true);
      final pd = child.parentData! as _EqualRowParentData;
      final x = i * (colW + _gap);
      pd.offset = Offset(_dir == TextDirection.rtl ? width - x - colW : x, 0);
      child = childAfter(child);
      i++;
    }
    size = constraints.constrain(Size(width, maxH));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// `.grid-2` — عمودان متساويان بفجوة 16 وهامش سفلي 20؛ عمود واحد ≤920.
class ImdGrid2 extends StatelessWidget {
  const ImdGrid2({super.key, required this.children, this.cols = 2, this.gap = 16, this.bottom = 20});
  final List<Widget> children;
  final int cols;
  final double gap;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final one = ImdBp.of(context).tablet;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ImdGridRows(cols: one ? 1 : cols, gap: gap, children: children),
    );
  }
}

/// `.rbar` — شريط أزرار ملتف بفجوة 8؛ على الجوال كل زر بعرض كامل.
class ImdRbar extends StatelessWidget {
  const ImdRbar({super.key, required this.children, this.bottom = 10, this.fullFirst = false});
  final List<Widget> children;
  final double bottom;

  /// العنصر الأول بعرض كامل (حقل `.fld` داخل الشريط) والباقي في سطر تحته.
  final bool fullFirst;

  @override
  Widget build(BuildContext context) {
    final mobile = ImdBp.of(context).mobile;
    if (fullFirst && !mobile && children.isNotEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          children.first,
          if (children.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: children.sublist(1)),
          ],
        ]),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  children[i],
                ],
              ],
            )
          : Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: children),
    );
  }
}

/// `.status-list > .status-item` — نقطة حالة + عنوان + وصف.
class ImdStatusList extends StatelessWidget {
  const ImdStatusList({super.key, required this.items});

  /// (الحالة: '' | 'warn' | 'err'، العنوان، الوصف)
  final List<(String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(ImdSizes.radius),
              boxShadow: imdShadow(c),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: items[i].$1 == 'err'
                        ? c.danger
                        : items[i].$1 == 'warn'
                            ? const Color(0xFFF79009)
                            : c.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].$2,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text, height: 1.6)),
                      Text(items[i].$3, style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// `repeat(auto-fit, minmax(<minItem>px, 1fr))` — شبكة تتكيّف بعدد الأعمدة حسب العرض.
class ImdAutoGrid extends StatelessWidget {
  const ImdAutoGrid({super.key, required this.children, this.minItem = 180, this.gap = 12, this.bottom = 0});
  final List<Widget> children;
  final double minItem;
  final double gap;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: LayoutBuilder(builder: (context, cons) {
        final cols = ((cons.maxWidth + gap) / (minItem + gap)).floor().clamp(1, children.isEmpty ? 1 : children.length);
        return ImdGridRows(cols: cols, gap: gap, children: children);
      }),
    );
  }
}
