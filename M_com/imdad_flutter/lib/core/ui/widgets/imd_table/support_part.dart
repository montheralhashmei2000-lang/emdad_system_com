part of '../imd_table.dart';

/// أصنافٌ مساعدة خاصة بـ[ImdTable] — نقلٌ حرفيّ بلا تغيير.
/// عرض عمودٍ يتبع محتواه: يبدأ بعرض المحتوى الأقصى،
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

/// بند عرضٍ في [ImdTable]: صفٌّ بفهرسه المطلق، أو رأس مجموعة.
class _TableItem {
  const _TableItem.row(this.row)
      : key = null,
        count = 0,
        collapsed = false;
  const _TableItem.group(String this.key, this.count, this.collapsed) : row = -1;

  final int row;
  final String? key;
  final int count;
  final bool collapsed;

  bool get isGroup => key != null;
}
