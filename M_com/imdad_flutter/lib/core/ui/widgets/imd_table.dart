import 'package:flutter/material.dart';
import '../imd_context_menu.dart';
import '../imd_density.dart';
import '../imd_format.dart';
import '../imd_icon.dart';
import '../imd_status_bar.dart';
import '../imd_tokens.dart';
import 'imd_buttons.dart';
import 'imd_column_filter.dart';
import 'imd_dialogs.dart';
import 'imd_fields.dart';

/// عمود في `table.u`
class ImdCol {
  const ImdCol(this.label, {this.flex = 1, this.width, this.numeric = false, this.center = false, this.auto = true});
  final String label;

  /// يُستخدم فقط حين `auto: false` (عمود نسبي ثابت لخلايا لا تدعم القياس الذاتي مثل القوائم المنسدلة).
  final int flex;
  final double? width;
  final bool numeric;
  final bool center;

  /// عرض تلقائي حسب المحتوى كجداول HTML (الافتراضي).
  final bool auto;
}

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

/// جدول قراءة بيانات كثيفة: رأس رمادي فاتح، صفوف بخط فاصل، وتظليل عند المرور.
class ImdTable extends StatefulWidget {
  const ImdTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowKeys,
    this.empty = 'لا توجد بيانات',
    this.onRowTap,
    this.rowMenu,
    this.rowColor,
    this.footer,
    this.minWidth,
    this.maxHeight,
    this.onHeaderTap,
    this.sortIndex,
    this.sortAsc = true,
    this.zebra = false,
    this.pageSize,
    this.onPageChanged,
    this.cards = false,
    this.headerBackground,
    this.headerForeground,
    this.headerPadding,
    this.cellPadding,
    this.gridLines = false,
    this.cellFontSize,
    this.flushCells = false,
    this.values,
    this.filterable = true,
    this.groupable = true,
    this.freezeFirst,
  })  : assert(rowKeys == null || rowKeys.length == rows.length,
            'rowKeys.length يجب أن يساوي rows.length — مفتاحٌ واحدٌ لكل صفّ'),
        assert(values == null || values.length == rows.length,
            'values.length يجب أن يساوي rows.length — صفّ قيمٍ لكل صفّ');

  final List<ImdCol> columns;
  final List<List<Widget>> rows;

  /// مفتاحٌ لكل صفّ، بترتيب [rows] نفسه — يُحافظ على هوية عنصر الصفّ (حالته
  /// ومتحكّماته الداخلية) عبر إدراج صفٍّ أو حذفه في المنتصف، بدل أن يُعاد
  /// بناء كل صفٍّ تالٍ من الصفر بفهرسه الجديد. لازمٌ لجداول الإدخال التي
  /// تحمل حقولًا تفاعلية بحالة (كـImdItemPicker)؛ جداول القراءة (بلا حالةٍ
  /// في خلاياها) لا تحتاجه فتتركه `null`.
  final List<LocalKey>? rowKeys;

  final String empty;
  final ValueChanged<int>? onRowTap;

  /// بنود قائمة السياق للصفّ ذي الفهرس المعطى: كليك يمين على سطح المكتب،
  /// وضغطةٌ مطوّلة على اللمس. `null` أو قائمةٌ فارغة ⇒ لا قائمة. الفهرس مطلقٌ
  /// (من أول [rows]) حتى مع الترقيم، كـ[onRowTap].
  final List<ImdMenuItem> Function(int index)? rowMenu;
  final Color? Function(int index)? rowColor;
  final List<Widget>? footer;

  /// تلوين الصفوف الفردية بلونٍ خفيف جدًّا لتسهيل تتبّع السطر في جدولٍ كثيف.
  /// يخسر أمام [rowColor] عند كليهما، ولا يمسّ الصف عند المرور (hover) ولا صفّ [footer].
  final bool zebra;

  /// أقل عرضٍ للجدول — تمرير أفقي إذا ضاقت المساحة عنه.
  final double? minWidth;

  /// سقف ارتفاع الجدول ⇒ **رأسٌ ثابت**: تبقى عناوين الأعمدة ظاهرةً ويُمرَّر
  /// الجسم تحتها، فلا يضيع معنى العمود بعد عشرين سطرًا.
  ///
  /// الرأس والجسم جدولان منفصلان ليثبت الأول ويتحرّك الثاني، فلا بدّ أن يكون
  /// عرض الأعمدة **حتميًّا** حتى يتطابقا: العمود بعرضٍ صريح يبقى عليه، وما
  /// عداه يصير نسبيًّا بـ[ImdCol.flex]. أي أن [ImdCol.auto] (القياس من
  /// المحتوى) لا يعمل في هذا الوضع — ولذلك هو اختياريٌّ لا افتراضي: الجداول
  /// القائمة تبقى على قياسها الذاتي ما لم يُطلب السقف.
  ///
  /// يُتجاهل في عرض البطاقات على الجوال، وعند خلوّ الجدول.
  final double? maxHeight;

  /// ضغط رأس العمود (`th[data-k]{cursor:pointer}`) — يُستخدم للفرز.
  final ValueChanged<int>? onHeaderTap;

  /// فهرس العمود المفروز حاليًّا (من أعمدة هذا الجدول لا من بيانات الشاشة)،
  /// أو `null` فلا فرز. الفرز نفسه يبقى على الشاشة؛ هذه علامته البصرية فقط:
  /// سهمٌ بلون التمييز على رأس العمود يبيّن العمود والاتجاه معًا، فلا يحتاج
  /// المستخدم أن يتذكّر ما ضغط. تجاهلها الشاشةُ ⇒ لا سهم كما كان.
  final int? sortIndex;

  /// اتجاه [sortIndex]: تصاعدي (الافتراضي) أو تنازلي.
  final bool sortAsc;

  /// `null` (الافتراضي) ⇒ كل الصفوف كما هي اليوم. عدد صحيح ⇒ ترقيم صفحات
  /// داخلي بهذا الحجم، مع شريطٍ تحت الجدول. الفرز خارج مسؤولية هذه الودجة
  /// تمامًا (كما هو الحال دائمًا هنا) — فمن أراد إعادة الصفحة إلى الأولى عند
  /// تغيّر الفرز يُمرِّر `key` يتغيّر معه (كما في `reports_center_screen.dart`)
  /// فتُعاد الودجة بحالةٍ جديدة بدل تمرير حالة فرزٍ إلى مكوّنٍ لا يعرفها.
  final int? pageSize;

  /// إشعارٌ اختياري بفهرس الصفحة الحالية (من صفر) بعد أي تنقّل.
  final ValueChanged<int>? onPageChanged;

  /// `false` (الافتراضي) ⇒ على الجوال (<900) يبقى **جدولًا** بعرضه الطبيعي يُمرَّر
  /// أفقيًّا مع تثبيت العمود الأول ([freezeFirst]) — لا يُضغط في عرض الشاشة ولا
  /// يتحوّل بطاقات. `true` ⇒ كل صف بطاقة على الجوال: للجداول الصغيرة التي لا
  /// تستفيد من التمرير الأفقي. العرض ≥900 يبقى جدولًا دائمًا.
  ///
  /// عمودٌ بعنوانٍ فارغ (`ImdCol('')`، كما تفعل كل أعمدة الإجراءات في
  /// الشاشات القائمة) لا يُعنوَن في البطاقة، بل يُجمَع مع أمثاله في صفّ
  /// إجراءاتٍ أسفلها.
  final bool cards;

  /// خلفية صف الرأس — `null` (الافتراضي) ⇒ الرمادي الفاتح المعتاد `c.tableHead`.
  /// تستعملها جداول الإدخال الكثيفة لتلوين رأسها بلون التمييز، فيتّبع
  /// السمة تلقائيًّا (زمردي داكن في الفاتح، زمردي فاتح في الداكن) بدل لونٍ
  /// صلبٍ واحد يخالف الوضع الداكن.
  final Color? headerBackground;

  /// نص صف الرأس — `null` (الافتراضي) ⇒ `c.muted` المعتاد.
  final Color? headerForeground;

  /// حشوة خلايا الرأس — `null` (الافتراضي) ⇒ 12 أفقيًّا و10 رأسيًّا كالمعتاد.
  final EdgeInsets? headerPadding;

  /// حشوة خلايا الجسم — `null` (الافتراضي) ⇒ 12 أفقيًّا و9 رأسيًّا كالمعتاد.
  /// جداول الإدخال الكثيفة تُضيّقها لتوفير المساحة على عشرات الأسطر.
  final EdgeInsets? cellPadding;

  /// خطوط شبكةٍ بين الخلايا رأسيًّا وأفقيًّا، وإطارٌ خارجيٌّ أغمق قليلًا.
  ///
  /// جدول القراءة يفصل صفوفه بخطٍّ أفقيٍّ وحده — أهدأ للعين حين يُمسح
  /// عموديًّا. أمّا جدول الإدخال فخلاياه حقولٌ تُملأ واحدةً واحدة، فحدُّ
  /// كل خليةٍ يبيّن أين تبدأ وأين تنتهي.
  final bool gridLines;

  /// حجم خطّ خلايا الجسم — `null` (الافتراضي) ⇒ 13.5 كالمعتاد.
  final double? cellFontSize;

  /// خلايا الجسم بلا حشوةٍ ولا محاذاة: ما فيها يملأ الخلية كلّها (عرضًا
  /// وارتفاعًا) فتلتصق الحقول بخطوط الشبكة بلا فراغ. لجداول الإدخال
  /// ([ImdEntryTable]) — يتولّى محتوى الخلية ارتفاعه (`ImdEntryTable.cell`).
  final bool flushCells;

  /// القيم الخام لكل خلية بترتيب [rows] وأعمدتها — **تفعّل التصفية والتجميع**.
  ///
  /// الخلايا ودجاتٌ جاهزة لا يُعرف نصّها، فلا تُصفَّى ولا تُجمَّع من تلقاء
  /// نفسها؛ تُمرِّر الشاشة ما يقابل كل خليةٍ من قيمة (`null` لخلية الإجراءات).
  /// بلا [values] يبقى الجدول كما كان تمامًا (لا شريط أدوات ولا أيقونات رؤوس).
  ///
  /// التصفية على مستوى العمود: أيقونةٌ في رأسه تفتح قائمةً بقيمه المميّزة.
  /// الفهارس التي تُمرَّر إلى [onRowTap] و[rowMenu] و[rowColor] تبقى **مطلقةً**
  /// من أول [rows] مهما صُفّي الجدول أو جُمِّع.
  ///
  /// صفّ الإجماليات [footer] تحسبه الشاشة من كل البيانات: لا يتبع التصفية.
  final List<List<Object?>>? values;

  /// السماح بتصفية الأعمدة (مع [values]).
  final bool filterable;

  /// السماح بالتجميع حسب عمود (مع [values]).
  final bool groupable;

  /// تثبيت العمود الأول أثناء التمرير الأفقي (حين يضيق العرض عن [minWidth]).
  ///
  /// `null` (الافتراضي) ⇒ يتبع [values]: مفعَّلٌ لجداول القراءة الكبيرة التي
  /// مرّرت قيمها، ومعطَّلٌ لغيرها. السبب أن التثبيت يرسم **نسخةً ثانية** من
  /// الجدول مقصوصةً على العمود الأول (فيتطابق ارتفاع الصفوف حتمًا)، فكل ودجةٍ في
  /// الجدول — أزرار الإجراءات وحقول الإدخال — تُبنى مرتين. هذا مقبولٌ في جدول قراءةٍ
  /// خلاياه نصوصٌ وأزرارٌ عديمة الحالة، وغير مقبولٍ في جدول إدخالٍ ([flushCells])
  /// خلاياه حقولٌ بحالة؛ وعمودٌ أول بلا عنوان (أزرار إجراءات) لا يُثبَّت أيضًا.
  /// النسخة الثانية مستبعَدةٌ من شجرة الإتاحة. عرض العمود المثبَّت [ImdCol.width] أو 120.
  final bool? freezeFirst;

  @override
  State<ImdTable> createState() => _ImdTableState();
}

class _ImdTableState extends State<ImdTable> {
  int _hover = -1;
  int _headerHover = -1;
  int _page = 0;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  /// متحكّم تمرير نسخة العمود المثبَّت — يُزامَن مع [_vScroll].
  final _vScroll2 = ScrollController();
  final _find = TextEditingController();
  String _findQ = '';

  /// القيم المسموحة لكل عمود مصفّى (فهرس العمود ← نصوص القيم).
  final Map<int, Set<String>> _filters = {};

  /// العمود المجمَّع عليه، أو `null` فلا تجميع.
  int? _groupBy;

  /// قيم المجموعات المطويّة.
  final Set<String> _collapsed = {};

  ImdRecordSink? _sink;

  bool get _tools => widget.values != null && widget.columns.isNotEmpty && (widget.filterable || widget.groupable);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ImdRecordScope.maybeOf(context);
    if (!identical(next, _sink)) {
      _sink?.remove(this);
      _sink = next;
    }
  }

  @override
  void initState() {
    super.initState();
    _vScroll.addListener(() => _syncV(_vScroll, _vScroll2));
    _vScroll2.addListener(() => _syncV(_vScroll2, _vScroll));
  }

  /// يطابق تمرير النسختين رأسيًّا (الأصل والعمود المثبَّت).
  void _syncV(ScrollController from, ScrollController to) {
    if (!from.hasClients || !to.hasClients) return;
    final o = from.offset;
    if ((to.offset - o).abs() < .5) return;
    to.jumpTo(o.clamp(to.position.minScrollExtent, to.position.maxScrollExtent).toDouble());
  }

  @override
  void dispose() {
    _sink?.remove(this);
    _hScroll.dispose();
    _vScroll.dispose();
    _vScroll2.dispose();
    _find.dispose();
    super.dispose();
  }

  /// نصّ قيمة الخلية — أساس التصفية والتجميع. الفارغ يُعرض «(فارغ)».
  String _text(int row, int col) {
    final v = widget.values![row];
    final x = col < v.length ? v[col] : null;
    return x?.toString().trim() ?? '';
  }

  static const String _blank = '(فارغ)';
  String _shown(String t) => t.isEmpty ? _blank : t;

  /// الصفوف المطابقة لكل المرشِّحات، بترتيبها الأصلي.
  List<int> _visibleRows() {
    final n = widget.rows.length;
    if (!_tools || (_filters.isEmpty && _findQ.isEmpty)) return List<int>.generate(n, (i) => i);
    final q = _findQ.toLowerCase();
    final colCount = widget.columns.length;
    bool found(int i) {
      if (q.isEmpty) return true;
      for (var j = 0; j < colCount; j++) {
        if (_text(i, j).toLowerCase().contains(q)) return true;
      }
      return false;
    }

    return [
      for (var i = 0; i < n; i++)
        if (found(i) && _filters.entries.every((f) => f.value.contains(_text(i, f.key)))) i,
    ];
  }

  /// قيم عمودٍ المميّزة مرتَّبة (رقميًّا إن كانت كلها أرقامًا).
  List<String> _distinct(int col) {
    final list = <String>{for (var i = 0; i < widget.rows.length; i++) _text(i, col)}.toList();
    final nums = {for (final t in list) t: num.tryParse(t)};
    if (list.isNotEmpty && list.every((t) => t.isEmpty || nums[t] != null)) {
      list.sort((a, b) => (nums[a] ?? double.negativeInfinity).compareTo(nums[b] ?? double.negativeInfinity));
    } else {
      list.sort();
    }
    return list;
  }

  Future<void> _editFilter(int col) async {
    final all = _distinct(col);
    final r = await showImdModal<Set<String>>(
      context,
      title: 'تصفية: ${widget.columns[col].label}',
      icon: 'sliders',
      maxWidth: 380,
      builder: (ctx) => ImdColumnFilterBody(values: all, selected: _filters[col], shown: _shown),
    );
    if (r == null || !mounted) return;
    setState(() {
      _page = 0;
      // اختيار كل القيم = لا تصفية (ولا يُحتفظ بمجموعةٍ تتقادم مع البيانات).
      if (r.length == all.length) {
        _filters.remove(col);
      } else {
        _filters[col] = r;
      }
    });
  }

  void _clearFilters() => setState(() {
        _filters.clear();
        _page = 0;
      });

  /// بنود العرض: صفوفٌ (فهرسها المطلق) أو رؤوس مجموعات.
  List<_TableItem> _items(List<int> visible) {
    final g = _groupBy;
    if (!_tools || g == null) return [for (final i in visible) _TableItem.row(i)];
    final groups = <String, List<int>>{};
    for (final i in visible) {
      groups.putIfAbsent(_text(i, g), () => []).add(i);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys) ...[
        _TableItem.group(k, groups[k]!.length, _collapsed.contains(k)),
        if (!_collapsed.contains(k)) for (final i in groups[k]!) _TableItem.row(i),
      ],
    ];
  }

  void _toggleGroup(String key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
        _page = 0;
      });

  /// يُبلّغ شريط الحالة بعدد الصفوف — بعد الإطار لا أثناءه (الإبلاغ يُعيد بناء الشريط).
  void _report(int shown) {
    final sink = _sink;
    if (sink == null) return;
    final total = widget.rows.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sink.report(this, shown: shown, total: total);
    });
  }

  /// شريط أدوات الجدول: بحثٌ فوري، لوحة التجميع (إسقاط رأس عمود)، قائمتا التجميع
  /// والتصفية، وشارات الفلاتر الفعّالة. يظهر مع [ImdTable.values] وحدها.
  Widget _toolbar(BuildContext context, int shown) {
    final c = context.imd;
    final cols = widget.columns;
    final desktop = !ImdBp.of(context).mobile;
    final labelled = [
      for (var j = 0; j < cols.length; j++)
        if (cols[j].label.isNotEmpty) j,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
              child: TextField(
                controller: _find,
                onChanged: (v) => setState(() {
                  _findQ = v.trim();
                  _page = 0;
                }),
                style: TextStyle(fontSize: ImdDensity.cellFont, color: c.text),
                decoration: imdFieldDecoration(context, dense: true).copyWith(
                  hintText: 'بحث فوري…',
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
                    child: ImdIcon('search', size: 14, color: c.faint),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: _findQ.isEmpty
                      ? null
                      : InkWell(
                          onTap: () => setState(() {
                            _find.clear();
                            _findQ = '';
                          }),
                          child: Padding(padding: const EdgeInsets.all(10), child: ImdIcon('x', size: 12, color: c.muted)),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
            if (widget.groupable && !desktop)
              ImdMenuButton<int>(
                label: _groupBy == null ? 'تجميع حسب' : 'مجمَّع: ${cols[_groupBy!].label}',
                icon: 'folder',
                small: true,
                items: (_) => [
                  if (_groupBy != null) const PopupMenuItem<int>(value: -1, child: Text('إلغاء التجميع')),
                  for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label)),
                ],
                onSelected: (j) => _setGroup(j < 0 ? null : j),
              ),
            if (widget.filterable && !desktop)
              ImdMenuButton<int>(
                label: 'تصفية',
                icon: 'sliders',
                small: true,
                items: (_) => [for (final j in labelled) PopupMenuItem<int>(value: j, child: Text(cols[j].label))],
                onSelected: _editFilter,
              ),
            // الفلاتر الفعّالة برتقاليةٌ: لونٌ يلفت إلى أن ما يُرى ليس كل البيانات.
            for (final e in _filters.entries)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _editFilter(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        '${cols[e.key].label}: ${e.value.length == 1 ? _shown(e.value.first) : '${e.value.length} قيم'}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.warn)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _filters.remove(e.key);
                        _page = 0;
                      }),
                      child: ImdIcon('x', size: 11, color: c.warn),
                    ),
                  ]),
                ),
              ),
            if (_filters.isNotEmpty)
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.muted),
                child: const Text('مسح الفلاتر', style: TextStyle(fontSize: 12)),
              ),
            if (_filters.isNotEmpty || _findQ.isNotEmpty)
              Text('${nf(shown)} من ${nf(widget.rows.length)}', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        if (widget.groupable && desktop) ...[
          const SizedBox(height: 6),
          _groupPanel(context),
        ],
      ]),
    );
  }

  void _setGroup(int? col) => setState(() {
        _groupBy = col;
        _collapsed.clear();
        _page = 0;
      });

  /// لوحة التجميع: يُسقَط عليها رأس عمودٍ لتجميع الجدول به، وتعرض العمود الحالي.
  Widget _groupPanel(BuildContext context) {
    final c = context.imd;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => widget.columns[d.data].label.isNotEmpty,
      onAcceptWithDetails: (d) => _setGroup(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hot ? c.accentSoft : c.subtle,
            border: Border.all(color: hot ? c.accent : c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            ImdIcon('folder', size: 13, color: c.muted),
            const SizedBox(width: 8),
            if (_groupBy == null)
              Text('اسحب رأس العمود هنا للتجميع', style: TextStyle(fontSize: 12, color: c.muted))
            else
              InkWell(
                onTap: () => _setGroup(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.columns[_groupBy!].label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text2)),
                    const SizedBox(width: 6),
                    ImdIcon('x', size: 11, color: c.muted),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// صفّ رأس مجموعة. ارتفاعه ثابتٌ وعرض خليته الأولى صفر عمدًا: نصّه يمتدّ فوق
  /// الأعمدة المجاورة (فارغةٍ) من غير أن يوسّع العمود الأول بقياسه الذاتي.
  TableRow _groupRow(BuildContext context, _TableItem g) {
    final c = context.imd;
    final h = ImdDensity.isHigh ? 26.0 : 34.0;
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
      const SizedBox(width: 6),
      Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
      const SizedBox(width: 8),
      Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
    return TableRow(
      key: ValueKey('group:${g.key}'),
      decoration: BoxDecoration(color: c.subtle, border: Border(bottom: BorderSide(color: c.tableRowLine))),
      children: [
        for (var j = 0; j < widget.columns.length; j++)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: MouseRegion(
              cursor: ImdCursor.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleGroup(g.key!),
                child: SizedBox(
                  width: j == 0 ? 0 : null,
                  height: h,
                  child: j == 0
                      ? Stack(clipBehavior: Clip.none, children: [
                          PositionedDirectional(start: 12, top: 0, bottom: 0, child: Center(child: label)),
                        ])
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// رأس مجموعة في عرض البطاقات.
  Widget _groupCard(BuildContext context, _TableItem g) {
    final c = context.imd;
    return InkWell(
      onTap: () => _toggleGroup(g.key!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          ImdIcon(g.collapsed ? 'chevron-left' : 'chevron-down', size: 13, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${widget.columns[_groupBy!].label}: ${_shown(g.key!)}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text2)),
          ),
          Text('(${nf(g.count)})', style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
      ),
    );
  }

  /// لونٌ محايد خفيف جدًّا فوق سطح الجدول — يعمل في كل سمة (فاتحة/داكنة/محروقات)
  /// لأنه مشتقٌّ من ألوان السمة الحالية لا لونًا ثابتًا.
  Color _zebraColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(scheme.onSurface.withValues(alpha: .035), scheme.surface);
  }

  void _openMenu(int row, Offset at) {
    final items = widget.rowMenu?.call(row) ?? const <ImdMenuItem>[];
    showImdContextMenu(context, at, items);
  }

  Widget _cell(ImdCol col, Widget child, {required int row, EdgeInsets? pad}) {
    // `row >= 0` = خليةُ جسمٍ؛ الرأس والإجماليات يبقيان بحشوتهما.
    final Widget w0 = (widget.flushCells && row >= 0)
        ? child
        : Padding(
            padding: pad ?? widget.cellPadding ?? EdgeInsets.symmetric(horizontal: 12, vertical: ImdDensity.cellPadV),
            child: Align(
              alignment: col.center ? Alignment.center : AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: child,
            ),
          );
    Widget w = w0;
    if (row >= 0) {
      w = MouseRegion(
        cursor: widget.onRowTap != null ? ImdCursor.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = row),
        onExit: (_) => setState(() => _hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
          onSecondaryTapDown: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          onLongPressStart: widget.rowMenu == null ? null : (d) => _openMenu(row, d.globalPosition),
          child: w,
        ),
      );
    }
    // «middle» لا «fill»: خلايا fill لا تُسهم في ارتفاع الصف فينهار الصف إذا كانت كلها كذلك.
    return TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: w);
  }

  Widget _header(BuildContext context, ImdCol col, int index) {
    final c = context.imd;
    final sorted = widget.sortIndex == index;
    final headerFg = widget.headerForeground;
    final label = ImdEmojiText(col.label,
        iconSize: 13,
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: sorted ? FontWeight.w700 : FontWeight.w600,
            color: headerFg ?? (sorted ? c.accent : c.muted),
            height: 1.3));
    // السهم على العمود المفروز وحده: لو وُضع على كل عمودٍ قابلٍ للفرز لاتّسعت
    // كل الأعمدة (عرضها ذاتيٌّ من محتواها) وضاق الجدول بلا طائل.
    final text = !sorted
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 4),
              ImdIcon(widget.sortAsc ? 'chevron-up' : 'chevron-down', size: 12, color: c.accent),
            ],
          );
    Widget head = _headerWithFilter(context, index, text);
    // رأس العمود يُسحب إلى لوحة التجميع (سطح المكتب).
    if (_tools && widget.groupable && widget.columns[index].label.isNotEmpty && !ImdBp.of(context).mobile) {
      head = Draggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4)),
            child: Text(widget.columns[index].label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onAccent)),
          ),
        ),
        child: head,
      );
    }
    if (widget.onHeaderTap == null) return head;
    final hovered = _headerHover == index;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _headerHover = index),
      onExit: (_) => setState(() => _headerHover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onHeaderTap!(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: hovered ? c.headerHover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: head,
        ),
      ),
    );
  }

  /// أيقونة تصفية العمود بجوار عنوانه — سطح المكتب فقط (على اللمس يُستعمل زر
  /// «تصفية» في شريط الأدوات: أيقونةٌ بحجم 12 لا تصلح هدفَ إصبع).
  Widget _headerWithFilter(BuildContext context, int index, Widget text) {
    if (!_tools || !widget.filterable || widget.columns[index].label.isEmpty || ImdBp.of(context).mobile) return text;
    final c = context.imd;
    final active = _filters.containsKey(index);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: text),
      const SizedBox(width: 4),
      Tooltip(
        message: 'تصفية العمود',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _editFilter(index),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ImdIcon('sliders', size: 11, color: active ? c.accent : c.faint),
          ),
        ),
      ),
    ]);
  }

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

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final cols = widget.columns;
    final rows = widget.rows;
    final pageSize = widget.pageSize;
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
        // تتحرك مع التمرير الأفقي فيبقى ظاهرًا فوق الأصل.
        return Stack(children: [
          scroller,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 10,
            width: fw,
            child: ExcludeSemantics(
              child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minWidth: minWidth,
                maxWidth: minWidth,
                child: buildTable(_vScroll2, frozenWidth: fw, bar: false),
              ),
            ),
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

/// صفٌّ فارغ بإطار جدول («لا …») للقوائم الخالية.
class ImdEmptyBox extends StatelessWidget {
  const ImdEmptyBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ImdTable(columns: const [], rows: const [], empty: text);
}
