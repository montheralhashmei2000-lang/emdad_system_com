import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../db/app_database.dart';

// بحثٌ عامٌّ واحد يمسح جداول النظام الستة عشر — بديلُ أن يفتح المستخدم كل
// شاشةٍ ويبحث فيها وحدها حين لا يذكر إلا طرفًا من اسمٍ أو رقم سند.
//
// الخدمة في طبقة البيانات فلا تعرف شيئًا عن التنقّل: تُعيد لكل نتيجةٍ معرّف
// صفحتها (`SearchHit.page`) وتترك الفتح للواجهة. أي أن اختيار نتيجةٍ يفتح
// شاشتها لا السجل نفسه؛ الشل اليوم لا يمرّر وسائط إلى الشاشات.
//
// TODO: direct record opening needs _pageBody args — future phase
// TODO: SearchSeed mechanism to pre-filter screen on navigate from search

/// ما تحتاجه الخدمة من صلاحيات المستخدم — لا أكثر.
///
/// تبنيه الواجهة من `Perm`، فتبقى الخدمة بلا `BuildContext` ولا `Perm`.
class SearchAccess {
  const SearchAccess({required this.canView, required this.scope});

  /// صلاحية **عرض** الصفحة (`perm.has(page)`): بلا صلاحيةٍ لا يُستعلم جدولها.
  final bool Function(String page) canView;

  /// نطاق مستودعات المستخدم: `null` ⇒ كل المستودعات، وقائمةٌ فارغة ⇒ لا شيء
  /// (فشلٌ مغلق كما في `parseWarehouseScope`).
  final List<String>? scope;

  /// كلُّ شيءٍ مسموح — للاختبارات وللمالك.
  static final SearchAccess all = SearchAccess(canView: (_) => true, scope: null);
}

/// نتيجةٌ واحدة: نوعها (مفتاح التصنيف في القائمة)، ومعرّفها، وسطراها،
/// ومعرّف الصفحة التي تعرضها.
class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  /// عنوان القسم في النتائج («الأصناف»، «سندات الصرف» …).
  final String type;
  final String id;
  final String title;
  final String subtitle;

  /// معرّف صفحة الشل (`_go`) — تستعمله الواجهة لفتح الشاشة.
  final String page;
}

/// النتائج مصنَّفةً بنوعها، بترتيب الأنواع كما مُسحت.
class SearchHits {
  const SearchHits(this.byType, this.total);

  const SearchHits.empty() : byType = const {}, total = 0;

  final Map<String, List<SearchHit>> byType;

  /// مجموع النتائج المعادة (لا مجموع المطابقات في القاعدة).
  final int total;

  bool get isEmpty => total == 0;
}

/// يبحث في جداول الكتالوج والمستندات والارتباطات واليوميات.
class SearchService {
  SearchService(this.db);

  final AppDatabase db;

  /// أقصر مدخلٍ يُبحث به — حرفٌ واحد يطابق كل شيء فلا يفيد.
  static const int minQuery = 2;

  /// سقف النتائج الكلّي بصرف النظر عن عدد الأنواع.
  static const int maxTotal = 50;

  /// حالات المستندات التي لا تُعرض في البحث (ملغاة أو مرفوضة).
  static const String _dropped = "('CANCELLED','REJECTED')";

  /// (الجدول، الصفحة، الصلاحية) لكل مَمسحٍ — يقرؤها `search_perm_test` ليثبت أن
  /// صلاحية كل جدول هي صلاحية صفحته لا صلاحيةَ جارةٍ أوسع منها.
  @visibleForTesting
  static List<({String table, String page, String perm})> get scanned =>
      [for (final t in _tables) (table: t.table, page: t.page, perm: t.perm)];

  /// يمسح الجداول المسموحة ويعيد حتى [perType] نتيجة لكل نوع.
  ///
  /// مدخلٌ أقصر من [minQuery] يعيد نتائجَ فارغة بلا استعلام.
  Future<SearchHits> search(String query, {required SearchAccess access, int perType = 5}) async {
    final q = query.trim();
    if (q.length < minQuery) return const SearchHits.empty();
    final like = '%${_escapeLike(q)}%';

    final out = <String, List<SearchHit>>{};
    var total = 0;
    for (final table in _tables) {
      if (total >= maxTotal) break;
      if (!access.canView(table.perm)) continue;
      final where = table.scopeColumns.isEmpty ? null : _scopeWhere(table.scopeColumns, access.scope);
      // نطاقٌ فارغ ⇒ لا صفّ من هذا الجدول يُعرض.
      if (where == _scopeNone) continue;
      final room = (perType).clamp(0, maxTotal - total);
      if (room == 0) break;
      final hits = await _query(table, like, where, room);
      if (hits.isEmpty) continue;
      out[table.type] = hits;
      total += hits.length;
    }
    return SearchHits(out, total);
  }

  Future<List<SearchHit>> _query(_Table t, String like, String? scopeWhere, int limit) async {
    final cols = t.searchColumns;
    final match = cols.map((c) => "COALESCE($c,'') LIKE ? ESCAPE '\\'").join(' OR ');
    final filters = <String>[
      '($match)',
      if (t.dropStatus) 'COALESCE(status,\'\') NOT IN $_dropped',
      if (scopeWhere != null) scopeWhere,
    ];
    final sql = 'SELECT ${t.selected.join(', ')} FROM "${t.table}" '
        'WHERE ${filters.join(' AND ')} ORDER BY ${t.orderBy} LIMIT ?';
    final rows = await db.customSelect(
      sql,
      variables: [for (var i = 0; i < cols.length; i++) Variable<String>(like), Variable<int>(limit)],
    ).get();
    return [
      for (final r in rows)
        SearchHit(
          type: t.type,
          id: r.readNullable<String>('id') ?? '',
          title: t.title(r),
          subtitle: t.subtitle(r),
          page: t.page,
        ),
    ];
  }

  /// علامة «لا شيء مسموح» — نطاقٌ فارغ يُسقط الجدول كله بلا استعلام.
  static const String _scopeNone = '\u0000none';

  /// شرط نطاق المستودعات على عمودٍ أو أكثر (التحويل له مستودعان).
  ///
  /// `null` (ALL) ⇒ لا شرط. قائمةٌ فارغة ⇒ [_scopeNone]. وإلا: العمود داخل
  /// النطاق أو فارغ (صفٌّ بلا مستودع لا يُحجب بنطاقٍ لا يخصّه).
  static String? _scopeWhere(List<String> columns, List<String>? scope) {
    if (scope == null) return null;
    if (scope.isEmpty) return _scopeNone;
    final list = scope.map(_quote).join(', ');
    return columns.map((c) => "(COALESCE($c,'') = '' OR TRIM($c) IN ($list))").join(' AND ');
  }

  /// أسماء المستودعات تأتي من القاعدة لا من المستخدم، ومع ذلك تُقتبَس بتضعيف
  /// الفردية حتى لا يُفسد اسمٌ فيه `'` نصَّ الاستعلام.
  static String _quote(String v) => "'${v.replaceAll("'", "''")}'";

  /// يُحيّد محارف `LIKE` الخاصة في مدخل المستخدم، فيُبحث عنها كأحرفٍ عادية.
  static String _escapeLike(String v) =>
      v.replaceAll('\\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static String _s(QueryRow r, String col) => r.readNullable<String>(col)?.trim() ?? '';

  static String _or(String v, [String def = '—']) => v.isEmpty ? def : v;

  /// وصلٌ يتجاهل الفراغات — سطرٌ فرعيٌّ لا يبدأ بفاصلةٍ ولا ينتهي بها.
  static String _join(List<String> parts) => parts.where((p) => p.isNotEmpty).join(' • ');

  /// الجداول الستة عشر بترتيب عرضها.
  static final List<_Table> _tables = [
    _Table(
      type: 'الأصناف',
      table: 'items',
      page: 'items',
      perm: 'items',
      searchColumns: ['name', 'code', 'barcode', 'category_name'],
      selected: ['id', 'name', 'code', 'category_name', 'base_unit'],
      orderBy: 'name',
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _join([_s(r, 'code'), _s(r, 'category_name'), _s(r, 'base_unit')]),
    ),
    _Table(
      type: 'التصنيفات',
      table: 'categories',
      page: 'items',
      perm: 'items',
      searchColumns: ['name', 'description'],
      selected: ['id', 'name', 'description'],
      orderBy: 'name',
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _or(_s(r, 'description'), 'تصنيف'),
    ),
    _Table(
      type: 'المستودعات',
      table: 'warehouses',
      page: 'stores',
      perm: 'stores',
      searchColumns: ['name', 'code', 'manager', 'location'],
      selected: ['id', 'name', 'code', 'manager', 'location'],
      orderBy: 'name',
      scopeColumns: ['name'],
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _join([_s(r, 'code'), _s(r, 'manager'), _s(r, 'location')]),
    ),
    _Table(
      type: 'الموردون',
      table: 'suppliers',
      page: 'suppliers',
      perm: 'suppliers',
      searchColumns: ['name', 'contact', 'phone', 'city'],
      selected: ['id', 'name', 'contact', 'phone', 'city'],
      orderBy: 'name',
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _join([_s(r, 'contact'), _s(r, 'phone'), _s(r, 'city')]),
    ),
    _Table(
      type: 'الوحدات المستفيدة',
      table: 'beneficiary_units',
      page: 'units',
      perm: 'units',
      searchColumns: ['name', 'code', 'parent_name'],
      selected: ['id', 'name', 'code', 'parent_name'],
      orderBy: 'name',
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _join([_s(r, 'code'), _s(r, 'parent_name')]),
    ),
    _Table(
      type: 'جهات الإمداد',
      table: 'supply_authorities',
      page: 'rationOrders',
      perm: 'rationOrders',
      searchColumns: ['name', 'title'],
      selected: ['id', 'name', 'title'],
      orderBy: 'name',
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _or(_s(r, 'title'), 'جهة إمداد'),
    ),
    _Table(
      type: 'سندات الاستلام',
      table: 'receipts',
      page: 'receive',
      perm: 'receive',
      searchColumns: ['ref_no', 'item_name', 'item_code', 'supplier', 'invoice_no'],
      selected: ['id', 'ref_no', 'item_name', 'supplier', 'warehouse', 'date'],
      orderBy: 'date DESC',
      scopeColumns: ['warehouse'],
      dropStatus: true,
      title: (r) => _or(_s(r, 'ref_no'), 'سند استلام'),
      subtitle: (r) => _join([_s(r, 'item_name'), _s(r, 'supplier'), _s(r, 'warehouse'), _s(r, 'date')]),
    ),
    _Table(
      type: 'سندات الصرف',
      table: 'issues',
      page: 'issue',
      perm: 'issue',
      searchColumns: ['ref_no', 'item_name', 'recipient_display', 'beneficiary_unit_name'],
      selected: ['id', 'ref_no', 'item_name', 'recipient_display', 'warehouse', 'date'],
      orderBy: 'date DESC',
      scopeColumns: ['warehouse'],
      dropStatus: true,
      title: (r) => _or(_s(r, 'ref_no'), 'سند صرف'),
      subtitle: (r) =>
          _join([_s(r, 'item_name'), _s(r, 'recipient_display'), _s(r, 'warehouse'), _s(r, 'date')]),
    ),
    _Table(
      type: 'سندات التحويل',
      table: 'transfers',
      page: 'transfer',
      perm: 'transfer',
      searchColumns: ['ref_no', 'item_name', 'warehouse', 'dest_warehouse'],
      selected: ['id', 'ref_no', 'item_name', 'warehouse', 'dest_warehouse', 'date'],
      orderBy: 'date DESC',
      // التحويل يمسّ مستودعين، فيلزم أن يكون كلاهما في النطاق.
      scopeColumns: ['warehouse', 'dest_warehouse'],
      dropStatus: true,
      title: (r) => _or(_s(r, 'ref_no'), 'سند تحويل'),
      subtitle: (r) => _join([
        _s(r, 'item_name'),
        '${_or(_s(r, 'warehouse'))} ← ${_or(_s(r, 'dest_warehouse'))}',
        _s(r, 'date'),
      ]),
    ),
    _Table(
      type: 'المرتجعات',
      table: 'returns',
      page: 'returns',
      perm: 'returns',
      searchColumns: ['ref_no', 'item_name', 'party', 'beneficiary_unit_name'],
      selected: ['id', 'ref_no', 'item_name', 'party', 'warehouse', 'date'],
      orderBy: 'date DESC',
      scopeColumns: ['warehouse'],
      dropStatus: true,
      title: (r) => _or(_s(r, 'ref_no'), 'سند مرتجع'),
      subtitle: (r) => _join([_s(r, 'item_name'), _s(r, 'party'), _s(r, 'warehouse'), _s(r, 'date')]),
    ),
    _Table(
      type: 'أوامر الجرد',
      table: 'stocktakes',
      page: 'stocktake',
      perm: 'stocktake',
      searchColumns: ['order_no', 'warehouse', 'category_name', 'committee'],
      selected: ['id', 'order_no', 'warehouse', 'category_name', 'date', 'status'],
      orderBy: 'date DESC',
      scopeColumns: ['warehouse'],
      dropStatus: true,
      title: (r) => _or(_s(r, 'order_no'), 'أمر جرد'),
      subtitle: (r) =>
          _join([_s(r, 'warehouse'), _s(r, 'category_name'), _s(r, 'date'), _s(r, 'status')]),
    ),
    _Table(
      type: 'الأفراد',
      table: 'link_persons',
      page: 'personnel',
      // `personnel` صلاحيةٌ مستقلة في `PermCatalog` وليست من معادلات `linkages`
      // (خلاف `linkFinances`/`linkArmament`). وكانت هنا `linkages` فكان من يملك
      // المالية وحدها يقرأ بالبحث أسماءَ الأفراد وأرقامهم العسكرية ورتبهم —
      // بياناتٌ شخصية تحجبها عنه شاشتُها.
      perm: 'personnel',
      searchColumns: ['full_name', 'military_no', 'rank', 'sub_unit', 'camp'],
      selected: ['id', 'full_name', 'military_no', 'rank', 'sub_unit', 'camp'],
      orderBy: 'full_name',
      title: (r) => _s(r, 'full_name'),
      subtitle: (r) =>
          _join([_s(r, 'rank'), _s(r, 'military_no'), _s(r, 'sub_unit'), _s(r, 'camp')]),
    ),
    _Table(
      type: 'مسيرات العهدة',
      table: 'link_custody_sheets',
      page: 'linkFinances',
      perm: 'linkages',
      searchColumns: ['sheet_no', 'title', 'holder_name'],
      selected: ['id', 'sheet_no', 'title', 'holder_name'],
      orderBy: 'sheet_no DESC',
      title: (r) => _or(_s(r, 'title'), _or(_s(r, 'sheet_no'), 'مسيرة عهدة')),
      subtitle: (r) => _join([_s(r, 'sheet_no'), _s(r, 'holder_name')]),
    ),
    _Table(
      type: 'سندات القبض',
      table: 'link_money_receipts',
      page: 'linkFinances',
      perm: 'linkages',
      searchColumns: ['receiver_name', 'purpose', 'transfer_no', 'deliverer_name'],
      selected: ['id', 'receiver_name', 'purpose', 'transfer_no', 'receipt_date'],
      orderBy: 'receipt_date DESC',
      title: (r) => _or(_s(r, 'receiver_name'), 'سند قبض'),
      subtitle: (r) => _join([_s(r, 'purpose'), _s(r, 'transfer_no'), _s(r, 'receipt_date')]),
    ),
    _Table(
      type: 'سجل التشغيل',
      table: 'kitchen_logs',
      page: 'kitchenLog',
      perm: 'kitchenLog',
      searchColumns: ['facility_name', 'item_name', 'date', 'notes'],
      selected: ['id', 'facility_name', 'item_name', 'date', 'meal_type'],
      orderBy: 'date DESC',
      title: (r) => _join([_or(_s(r, 'facility_name'), 'مطبخ'), _s(r, 'item_name')]),
      subtitle: (r) => _join([_s(r, 'date'), _s(r, 'meal_type')]),
    ),
    _Table(
      type: 'خطط الوجبات',
      table: 'meal_plans',
      page: 'mealPlans',
      perm: 'mealPlans',
      searchColumns: ['name', 'facility_name', 'warehouse'],
      selected: ['id', 'name', 'facility_name', 'warehouse', 'status'],
      orderBy: 'name',
      scopeColumns: ['warehouse'],
      title: (r) => _s(r, 'name'),
      subtitle: (r) => _join([_s(r, 'facility_name'), _s(r, 'warehouse'), _s(r, 'status')]),
    ),
  ];
}

/// وصفُ جدولٍ واحد في البحث: ما يُبحث فيه، وما يُقرأ منه، وكيف يُعرض.
class _Table {
  _Table({
    required this.type,
    required this.table,
    required this.page,
    required this.perm,
    required this.searchColumns,
    required this.selected,
    required this.orderBy,
    required this.title,
    required this.subtitle,
    this.scopeColumns = const [],
    this.dropStatus = false,
  });

  final String type;
  final String table;
  final String page;
  final String perm;
  final List<String> searchColumns;
  final List<String> selected;
  final String orderBy;

  /// أعمدة المستودع التي يُقاس عليها نطاق المستخدم (فارغة ⇒ لا نطاق).
  final List<String> scopeColumns;

  /// إسقاط الصفوف الملغاة/المرفوضة (للمستندات التي تحمل `status`).
  final bool dropStatus;

  final String Function(QueryRow r) title;
  final String Function(QueryRow r) subtitle;
}
