part of '../imd_table.dart';

/// بناء الجدول وشريط ترقيم الصفحات.
///
/// نقلٌ حرفيّ من `_ImdTableState` — خليطٌ في المكتبة نفسها، فواجهة
/// [ImdTable] العامة لم تتغيّر.
mixin _ImdTableBuild on _ImdTableBase, _ImdTableData, _ImdTableToolbar, _ImdTableGroups, _ImdTableCells, _ImdTableCards {
  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final rows = widget.rows;
    // جدولٌ طويل بلا ترقيم يبني كل صفوفه دفعةً واحدة (`Table` ليس كسولًا)، فبعد
    // [ImdTable.autoPageThreshold] صفًّا يُرقَّم تلقائيًّا بـ[ImdTable.autoPageSize].
    // جداول الإدخال ([flushCells]) مستثناة: حقولها بحالةٍ مرتبطةٍ بمفاتيح صفوفها.
    final pageSize = widget.pageSize ??
        (!widget.flushCells && widget.rows.length > ImdTable.autoPageThreshold ? ImdTable.autoPageSize : null);
    final visible = _visibleRows();
    final items = _items(visible);
    _report(visible.length);
    // مُشتقّةٌ من `_page` لا مُساويةٌ له: لو ضاقت `rows` (تصفيةٌ جديدة) دون
    // أن يتغيّر `key` الودجة، تبقى `_page` القديمة صالحةً هنا للعرض فورًا بدل
    // صفحةٍ فارغة، وتُصحَّح القيمة المخزَّنة عند أول تنقّل.
    final pageCount = pageSize == null ? 1 : _pageCount(items.length, pageSize);
    // `int.clamp` يُعيد `num` لا `int` (موروثةٌ من `num`)، فـ`.toInt()` هنا
    // ضرورةٌ لا زخرفة — بدونها لا تُقبل `page`/`pageEnd` فهارس مباشرةً.
    final int page = _page.clamp(0, pageCount - 1).toInt();
    final int pageStart = pageSize == null ? 0 : page * pageSize;
    final int pageEnd = pageSize == null ? items.length : (pageStart + pageSize).clamp(0, items.length).toInt();

    if (widget.cards && ImdBp.of(context).mobile && rows.isNotEmpty && cols.isNotEmpty) {
      final cardsArea = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var k = pageStart; k < pageEnd; k++) ...[
            if (items[k].isGroup)
              _groupCard(context, items[k])
            else
              widget.rowKeys == null
                  ? _card(context, items[k].row)
                  : KeyedSubtree(key: widget.rowKeys![items[k].row], child: _card(context, items[k].row)),
            if (k != pageEnd - 1 || widget.footer != null) SizedBox(height: ImdDensity.cardGap),
          ],
          if (widget.footer != null) _footerCard(context),
        ],
      );
      if (pageSize == null && !_tools) return cardsArea;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tools) _toolbar(context, visible.length),
          cardsArea,
          if (pageSize != null)
            _pager(context, page: page, pageCount: pageCount, pageStart: pageStart, pageEnd: pageEnd, total: items.length),
        ],
      );
    }

    // جدولٌ بلا صفوف لا جسم له يُمرَّر تحت الرأس، فلا رأس ثابتًا له.
    final sticky = widget.maxHeight != null && items.isNotEmpty && cols.isNotEmpty;
    final mobile = ImdBp.of(context).mobile;

    // الجوال بلا بطاقات: جدولٌ بعرضٍ طبيعيٍّ يُمرَّر أفقيًّا (والعمود الأول مثبَّت)
    // بدل ضغط الأعمدة في عرض الشاشة حتى لا يُقرأ منها شيء.
    var minW = widget.minWidth;
    if (mobile && !widget.cards && cols.isNotEmpty) {
      final natural = [for (final col in cols) col.width ?? (col.flex > 1 ? 180.0 : 110.0)].fold<double>(0, (a, b) => a + b);
      if (minW == null || natural > minW) minW = natural;
    }

    /// الجدول بإطاره. [frozenWidth] ≠ null ⇒ العمود الأول بهذا العرض الثابت (نسخة
    /// التثبيت). [vc] متحكّم التمرير الرأسي، و[bar] هل يُرسم شريط التمرير.
    Widget buildTable(ScrollController vc, {double? frozenWidth, bool bar = true}) {
      final Widget body;
      if (cols.isEmpty) {
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: ImdEmojiText(widget.empty,
              style: TextStyle(fontSize: ImdDensity.cellFont, fontWeight: FontWeight.w500, color: c.muted, height: 1.5)),
        );
      } else {
        // الرأس الثابت يفصل الجدول جدولين، فعرض العمود لا يصحّ أن يُقاس من
        // محتواه: لكلٍّ محتواه فيختلفان. الصريح يبقى، وما عداه نسبيٌّ — وكلاهما
        // يُحسب من عرض الحاوية وحده فيتطابق الجدولان.
        final widths = <int, TableColumnWidth>{
          for (var j = 0; j < cols.length; j++)
            j: (j == 0 && frozenWidth != null)
                ? FixedColumnWidth(frozenWidth)
                : cols[j].width != null
                    ? FixedColumnWidth(cols[j].width!)
                    : (cols[j].auto && !sticky)
                        ? const _HtmlColumnWidth()
                        : FlexColumnWidth(cols[j].flex.toDouble()),
        };
        final headerRow = TableRow(
          decoration: BoxDecoration(
            color: widget.headerBackground ?? c.tableHead,
            border: widget.headerBackground == null ? Border(bottom: BorderSide(color: c.line)) : null,
          ),
          children: [
            for (var j = 0; j < cols.length; j++)
              _cell(
                cols[j],
                _header(context, cols[j], j),
                row: -1,
                pad: widget.headerPadding ?? EdgeInsets.symmetric(horizontal: 12, vertical: ImdDensity.headPadV),
              ),
          ],
        );
        // `i` فهرسُ الصفّ المطلق في `rows` (لا موضعه في الصفحة ولا بعد التصفية):
        // `zebra` و`rowColor` و`onRowTap` تبقى كما لو لم يُفعَّل ترقيمٌ ولا تصفيةٌ
        // أصلًا — تمريرها فهرسًا محليًّا كان يكسر أيّ استخدامٍ يعتمد على فهرس
        // القائمة الكاملة. و`k` موضعه في بنود العرض، لتمييز آخر صفٍّ معروض.
        TableRow bodyRow(int i, int k) => TableRow(
              key: widget.rowKeys?[i],
              decoration: BoxDecoration(
                color: _hover == i
                    ? c.rowHover
                    : (widget.rowColor?.call(i) ?? (widget.zebra && i.isOdd ? _zebraColor(context) : null)),
                // آخر صفٍّ من الصفحة **المعروضة** لا آخر صفٍّ في القائمة كلها،
                // وإلا بقي خط الفاصل تحت كل الصفحات إلا الأخيرة. ومع
                // [gridLines] يرسمها `TableBorder` فلا تُزدوج هنا.
                border: (widget.gridLines || (k == pageEnd - 1 && widget.footer == null))
                    ? null
                    : Border(bottom: BorderSide(color: c.tableRowLine)),
              ),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(
                          fontSize: widget.cellFontSize ?? ImdDensity.cellFont, color: c.text, height: 1.5),
                      child: j < rows[i].length ? rows[i][j] : const SizedBox.shrink(),
                    ),
                    row: i,
                  ),
              ],
            );
        final bodyRows = <TableRow>[
          for (var k = pageStart; k < pageEnd; k++)
            if (items[k].isGroup) _groupRow(context, items[k]) else bodyRow(items[k].row, k),
          if (widget.footer != null && items.isNotEmpty)
            TableRow(
              decoration: BoxDecoration(color: c.accentSoft),
              children: [
                for (var j = 0; j < cols.length; j++)
                  _cell(
                    cols[j],
                    DefaultTextStyle.merge(
                      style: TextStyle(fontSize: ImdDensity.cellFont, fontWeight: FontWeight.w700, color: c.accent, height: 1.5),
                      child: j < widget.footer!.length ? widget.footer![j] : const SizedBox.shrink(),
                    ),
                    row: -1,
                  ),
              ],
            ),
        ];
        // الشبكة من `TableBorder` لا من زخرفة كل خلية: هي وحدها تعرف حدود
        // الأعمدة بعد توزيع العرض، فلا ينزاح خطٌّ عن عموده.
        final grid = !widget.gridLines
            ? null
            : TableBorder(
                verticalInside: BorderSide(color: c.line),
                horizontalInside: BorderSide(color: c.tableRowLine),
              );
        if (items.isEmpty) {
          // الجدول الفارغ يُبقي رأسه ويعرض سطرًا رماديًّا صغيرًا — بلا حالةٍ فارغةٍ كبيرة.
          final emptyText = rows.isEmpty ? widget.empty : 'لا نتائج مطابقة للتصفية';
          body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Table(columnWidths: widths, border: grid, children: [headerRow]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: ImdEmojiText(emptyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.faint, height: 1.4)),
            ),
          ]);
        } else if (!sticky) {
          body = Table(columnWidths: widths, border: grid, children: [headerRow, ...bodyRows]);
        } else {
          final vTable = SingleChildScrollView(
            controller: vc,
            child: Table(columnWidths: widths, border: grid, children: bodyRows),
          );
          // `Flexible` لا `Expanded`: جدولٌ أقصر من السقف يأخذ ارتفاعه لا السقف،
          // فلا يبقى تحته فراغٌ أبيض. وشريط التمرير ظاهرٌ دائمًا ورفيع (كلاسيكي).
          body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // الرأس بلا شبكةٍ أفقية: حدّه السفلي هو الفاصل بينه وبين الجسم،
              // ورسمُهما معًا يُثخّن الخط.
              Table(
                columnWidths: widths,
                border: grid == null ? null : TableBorder(verticalInside: grid.verticalInside),
                children: [headerRow],
              ),
              Flexible(
                child: bar
                    ? Scrollbar(controller: vc, thumbVisibility: true, thickness: 6, child: vTable)
                    : vTable,
              ),
            ],
          );
        }
      }
      Widget table = Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          // إطارٌ خارجيٌّ أغمق قليلًا مع الشبكة، فيُقرأ الجدول كتلةً واحدة
          // لا شبكةً سائبة.
          border: Border.all(color: widget.gridLines ? c.lineStrong : c.line),
          borderRadius: BorderRadius.circular(mobile ? 10 : ImdSizes.radius),
        ),
        child: body,
      );
      // السقف على الإطار كلّه (الرأس + الجسم)، وبه يصير للعمود `Flexible` داخله
      // ارتفاعٌ محدود فيُمرَّر — بلا حدٍّ أعلى لا تمريرَ أصلًا داخل صفحةٍ مُمرَّرة.
      if (sticky) {
        table = ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.maxHeight!), child: table);
      }
      return table;
    }

    Widget tableArea;
    final minWidth = minW;
    if (minWidth == null || items.isEmpty) {
      tableArea = buildTable(_vScroll);
    } else {
      tableArea = LayoutBuilder(builder: (context, cons) {
        if (cons.maxWidth >= minWidth) return buildTable(_vScroll);
        final frozen = (widget.freezeFirst ?? widget.values != null) &&
            !widget.flushCells &&
            cols.isNotEmpty &&
            cols[0].label.isNotEmpty;
        final fw = frozen ? (cols[0].width ?? 120.0) : null;
        // شريط تمرير ظاهر، وإلا لم يعرف
        // المستخدم أن هناك أعمدة خارج الشاشة (لا تمرير أفقي بعجلة الفأرة).
        final scroller = Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          thickness: 6,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: buildTable(_vScroll, frozenWidth: fw)),
            ),
          ),
        );
        if (!frozen) return scroller;
        // العمود الأول: نسخةٌ من الجدول بعرضه الكامل مقصوصةٌ على العمود وحده، لا
        // تتحرك مع التمرير الأفقي فيبقى ظاهرًا فوق الأصل. **لا تُبنى إلا بعد أن
        // يُمرَّر الجدول أفقيًّا**: عند الإزاحة صفر العمود الأول ظاهرٌ في الأصل، فبناء
        // النسخة كان يضاعف كلفة كل جدولٍ عريضٍ بلا فائدة.
        return Stack(children: [
          scroller,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 10,
            width: fw,
            child: ListenableBuilder(
              listenable: _hScroll,
              builder: (context, _) {
                if (!_hScroll.hasClients || _hScroll.offset.abs() < .5) return const SizedBox.shrink();
                // النسخة وُلدت الآن بإزاحةٍ رأسيةٍ صفر: تُطابَق بالأصل بعد هذا الإطار.
                WidgetsBinding.instance.addPostFrameCallback((_) => _syncV(_vScroll, _vScroll2));
                return ExcludeSemantics(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.topStart,
                      minWidth: minWidth,
                      maxWidth: minWidth,
                      child: buildTable(_vScroll2, frozenWidth: fw, bar: false),
                    ),
                  ),
                );
              },
            ),
          ),
        ]);
      });
    }
    final tableWithTools = !_tools
        ? tableArea
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [_toolbar(context, visible.length), tableArea],
          );
    if (pageSize == null || items.isEmpty) return tableWithTools;
    // شريط الترقيم تحت الجدول وخارج تمريره الأفقي: هو معلومةٌ عن كامل
    // البيانات لا عمودٍ من أعمدته، فيبقى ظاهرًا مهما مُرِّر الجدول أفقيًّا.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tableWithTools,
        _pager(context, page: page, pageCount: pageCount, pageStart: pageStart, pageEnd: pageEnd, total: items.length),
      ],
    );
  }

  void _goToPage(int target, int pageCount) {
    final int next = target.clamp(0, pageCount - 1).toInt();
    setState(() => _page = next);
    widget.onPageChanged?.call(next);
  }

  Widget _pager(
    BuildContext context, {
    required int page,
    required int pageCount,
    required int pageStart,
    required int pageEnd,
    required int total,
  }) {
    final c = context.imd;
    final textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.muted);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('عرض ${nf(pageStart + 1)}–${nf(pageEnd)} من ${nf(total)}', style: textStyle),
          Row(mainAxisSize: MainAxisSize.min, children: [
            // «السابق» نحو بداية القائمة، و«التالي» نحو تاليها — بلا فرقٍ يدويٍّ
            // بين فاتح/داكن ولا بين نظام تشغيل، فالأيقونتان مسارا SVG ثابتان.
            ImdIconButton(
              icon: 'chevron-right',
              tooltip: 'الصفحة السابقة',
              onPressed: page > 0 ? () => _goToPage(page - 1, pageCount) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('صفحة ${nf(page + 1)} من ${nf(pageCount)}', style: textStyle),
            ),
            ImdIconButton(
              icon: 'chevron-left',
              tooltip: 'الصفحة التالية',
              onPressed: page < pageCount - 1 ? () => _goToPage(page + 1, pageCount) : null,
            ),
          ]),
        ],
      ),
    );
  }
}
