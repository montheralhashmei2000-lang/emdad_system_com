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

part 'imd_table/support_part.dart';
part 'imd_table/base_part.dart';
part 'imd_table/data_part.dart';
part 'imd_table/toolbar_part.dart';
part 'imd_table/groups_part.dart';
part 'imd_table/cells_part.dart';
part 'imd_table/cards_part.dart';
part 'imd_table/build_part.dart';

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

  /// عدد الصفوف الذي يُفعَّل بعده الترقيم التلقائي حين لا يُمرَّر [pageSize].
  static const int autoPageThreshold = 300;

  /// حجم الصفحة في الترقيم التلقائي.
  static const int autoPageSize = 100;

  @override
  State<ImdTable> createState() => _ImdTableState();
}

class _ImdTableState extends State<ImdTable>
    with
        _ImdTableBase,
        _ImdTableData,
        _ImdTableToolbar,
        _ImdTableGroups,
        _ImdTableCells,
        _ImdTableCards,
        _ImdTableBuild {
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

  @override
  void dispose() {
    _sink?.remove(this);
    _hScroll.dispose();
    _vScroll.dispose();
    _vScroll2.dispose();
    _find.dispose();
    super.dispose();
  }
}

/// صفٌّ فارغ بإطار جدول («لا …») للقوائم الخالية.
class ImdEmptyBox extends StatelessWidget {
  const ImdEmptyBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ImdTable(columns: const [], rows: const [], empty: text);
}
