part of '../imd_table.dart';

/// عرض البطاقات على الشاشات الضيّقة، وعدد الصفحات.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableCards on _ImdTableBase, _ImdTableGroups {
  /// عدد الصفحات لحجمٍ معطًى — صفحة واحدة على الأقل حتى لو كانت القائمة فارغة،
  /// فلا يُقسَّم على صفر ولا تُعرض «صفحة صفر من صفر».
  int _pageCount(int totalRows, int pageSize) => totalRows == 0 ? 1 : (totalRows / pageSize).ceil();

  /// عنوانٌ صغيرٌ فوق خليته — بنفس أسلوب `ImdLabeled` في `imd_form.dart` حرفيًّا
  /// (لا استيراد منه: هذا الملف أساسٌ لا يعتمد على ملفاتٍ فوقه).
  Widget _labeledCell(BuildContext context, String label, Widget cell, {Color? labelColor}) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor ?? c.text2, height: 1.6)),
        const SizedBox(height: 2),
        cell,
      ],
    );
  }

  /// بطاقة صفٍّ واحد على الشاشات الضيّقة (`cards: true`) — بديل صف الجدول.
  /// أعمدة `label` غير الفارغة تُكدَّس معنونةً، وأعمدة `label` الفارغة
  /// (أزرار الإجراءات دومًا في الشاشات القائمة) تُجمَع في صفٍّ أسفل البطاقة.
  Widget _card(BuildContext context, int i) {
    final c = context.imd;
    final cols = widget.columns;
    final row = i < widget.rows.length ? widget.rows[i] : const <Widget>[];
    final fields = <Widget>[];
    final actions = <Widget>[];
    for (var j = 0; j < cols.length; j++) {
      final cell = j < row.length ? row[j] : const SizedBox.shrink();
      if (cols[j].label.isEmpty) {
        actions.add(cell);
      } else {
        if (fields.isNotEmpty) fields.add(const SizedBox(height: 8));
        fields.add(_labeledCell(context, cols[j].label, cell));
      }
    }
    final hoverBg = c.rowHover;
    final bg = widget.onRowTap != null && _hover == i
        ? hoverBg
        : widget.rowColor?.call(i) ?? (widget.zebra && i.isOdd ? _zebraColor(context) : c.surface);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13.5, color: c.text, height: 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...fields,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
    if (widget.onRowTap == null && widget.rowMenu == null) return card;
    return MouseRegion(
      cursor: widget.onRowTap != null ? ImdCursor.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = i),
      onExit: (_) => setState(() => _hover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(i),
        onSecondaryTapDown: widget.rowMenu == null ? null : (d) => _openMenu(i, d.globalPosition),
        onLongPressStart: widget.rowMenu == null ? null : (d) => _openMenu(i, d.globalPosition),
        child: card,
      ),
    );
  }

  /// بطاقة الإجماليات — نظير صفّ [ImdTable.footer] في وضع البطاقات، بنفس
  /// ألوان صفّه في الجدول (`accentSoft`/`accent`) لتمييزها عن بطاقات البيانات.
  Widget _footerCard(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final footer = widget.footer!;
    final fields = <Widget>[];
    for (var j = 0; j < cols.length; j++) {
      if (cols[j].label.isEmpty) continue;
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 8));
      final cell = j < footer.length ? footer[j] : const SizedBox.shrink();
      fields.add(_labeledCell(context, cols[j].label, cell, labelColor: c.accent));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.accent, height: 1.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: fields),
      ),
    );
  }
}
