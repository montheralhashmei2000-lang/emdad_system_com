import '../../core/ui/imd_format.dart';
import '../db/app_database.dart';
import 'catalog_repo.dart';
import 'daily_repo.dart';
import 'movements_repo.dart';

/// مركز التقارير — نقل `reports-center.js`: تسعة تقارير فوق قائمة حركات موحّدة،
/// لكل تقرير فلاتره الخاصة وأعمدته وملخّصه، مع احترام نطاق مستودعات المستخدم.

/// معرّفات التقارير بترتيب قائمة الويب.
enum ReportId { moves, unitAccount, stock, consumption, strength, kitchen, supplier, returns, daily }

/// بطاقة التقرير في القائمة الجانبية (`REPORTS`).
class ReportInfo {
  const ReportInfo(this.id, this.icon, this.name, this.desc);
  final ReportId id;
  final String icon;
  final String name;
  final String desc;
}

const kReports = <ReportInfo>[
  ReportInfo(ReportId.moves, 'repeat', 'حركة المخزون اليومية', 'كل الحركات حسب الفترة والمستودع والنوع'),
  ReportInfo(ReportId.unitAccount, 'file', 'كشف حساب وحدة مستفيدة', 'المصروف والمرتجع لوحدة وفروعها'),
  ReportInfo(ReportId.stock, 'package', 'تقرير أرصدة المخزون', 'الرصيد وحالة كل صنف، إجمالي أو لكل مستودع'),
  ReportInfo(ReportId.consumption, 'chart', 'تحليل الاستهلاك', 'المصروف مجمّعًا حسب الصنف أو الوحدة أو المستودع'),
  ReportInfo(ReportId.strength, 'users', 'تقرير حصر القوة', 'القوة الأساسية والزيادة لكل معسكر ووحدة'),
  ReportInfo(ReportId.kitchen, 'utensils', 'أداء المطابخ والأفران', 'الاستهلاك الفعلي مقابل المتوقع لكل وجبة'),
  ReportInfo(ReportId.supplier, 'truck', 'ملخص توريدات الموردين', 'تفصيلي حسب السند أو مجمّع بالكميات'),
  ReportInfo(ReportId.returns, 'undo', 'تقرير المرتجعات', 'المرتجع من الوحدات وإلى الموردين'),
  ReportInfo(ReportId.daily, 'clipboard', 'تقرير العمل اليومي', 'ملخص وحركات يوم واحد'),
];

const kMoveTypes = <String, String>{
  'IN': 'وارد',
  'OUT': 'صادر',
  'TRANSFER': 'تحويل مخزني',
  'RETURN_IN': 'مرتجع من وحدة',
  'RETURN_OUT': 'مرتجع لمورد',
  'OPENING': 'رصيد افتتاحي',
};

const kMeals = <String, String>{
  'BREAKFAST': 'فطور',
  'LUNCH': 'غداء',
  'DINNER': 'عشاء',
  'BREAD': 'خبز (أفران)',
};

const kMoveStatus = <String, String>{
  'COMPLETED': 'مكتمل',
  'DRAFT': 'مسودة',
  'ORDER': 'أمر معلق',
  'RECEIVED': 'مستلم',
  'IN_TRANSIT': 'قيد النقل',
  'PENDING': 'معلق',
  'CANCELLED': 'ملغى',
  'REJECTED': 'مرفوض',
};

/// الحالات التي لا تؤثر على الأرصدة (`INACTIVE`).
const _inactive = {'DRAFT', 'ORDER', 'CANCELLED', 'REJECTED'};

/// حركة موحّدة من أي سند (`buildMoves`).
class MoveRow {
  MoveRow({
    required this.date,
    required this.type,
    required this.refNo,
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.unitName,
    required this.baseQty,
    required this.baseUnit,
    required this.warehouse,
    required this.party,
    required this.status,
    this.destWarehouse = '',
    this.unitId = '',
    this.facilityId = '',
    this.condition = '',
    this.notes = '',
  });

  final String date;
  final String type;
  final String refNo;
  final String itemId;
  final String itemCode;
  final String itemName;
  final double qty;
  final String unitName;
  final double baseQty;
  final String baseUnit;
  final String warehouse;
  final String destWarehouse;
  final String party;
  final String status;
  final String unitId;
  final String facilityId;
  final String condition;
  final String notes;

  String get typeLabel => kMoveTypes[type] ?? type;
  String get statusLabel => kMoveStatus[status] ?? status;
  bool get active => !_inactive.contains(status);
}

/// عمود في جدول التقرير (`C(k,t,o)`).
class ReportColumn {
  const ReportColumn(this.title, {this.numeric = false, this.sum = false, this.chip = false});

  final String title;
  final bool numeric;

  /// يدخل في سطر الإجمالي (`num` بلا `nosum` في الويب).
  final bool sum;

  /// يُعرض شارةً ملوّنة بدل نص عادي.
  final bool chip;
}

/// خلية بنص وربما لون شارة: ok | pend | err | code.
class ReportCell {
  const ReportCell(this.text, {this.tone = '', this.value});
  final String text;
  final String tone;

  /// القيمة الرقمية للفرز والجمع (تُستعمل حين يختلف النص المعروض عن الرقم).
  final double? value;
}

class ReportResult {
  const ReportResult({
    this.columns = const [],
    this.rows = const [],
    this.summary = const [],
    this.note = '',
    this.message = '',
    this.title = '',
  });

  final List<ReportColumn> columns;
  final List<List<ReportCell>> rows;

  /// بطاقات الملخّص أعلى الجدول (الاسم، القيمة).
  final List<(String, num)> summary;
  final String note;

  /// رسالة بدل الجدول (مثل «اختر الوحدة الرئيسية»).
  final String message;

  /// لاحقة عنوان التقرير عند الطباعة.
  final String title;
}

/// تعريف فلتر واحد في شريط الفلاتر.
class ReportFilterDef {
  const ReportFilterDef({
    required this.key,
    required this.type,
    this.label = '',
    this.options,
    this.fromDaysAgo = 30,
    this.defaultOn = false,
  });

  /// range | date | select
  final String type;
  final String key;
  final String label;

  /// خيارات القائمة، وقد تعتمد على قيم فلاتر أخرى (الوحدة الفرعية تتبع الرئيسية).
  final List<(String, String)> Function(ReportData data, Map<String, String> f)? options;
  final int fromDaysAgo;

  /// «تحديد فترة» مفعّلة ابتداءً.
  final bool defaultOn;
}

/// كل البيانات المطلوبة للتقارير، تُحمَّل مرة واحدة (`loadAll`).
class ReportData {
  ReportData({
    required this.items,
    required this.units,
    required this.warehouses,
    required this.categories,
    required this.suppliers,
    required this.facilities,
    required this.strengths,
    required this.kitchenLogs,
    required this.moves,
    required this.balances,
    required this.scoped,
  });

  final List<Item> items;
  final List<BeneficiaryUnit> units;
  final List<Warehouse> warehouses;
  final List<Category> categories;
  final List<Supplier> suppliers;
  final List<Facility> facilities;
  final List<Strength> strengths;
  final List<KitchenLog> kitchenLogs;
  final List<MoveRow> moves;

  /// أرصدة الأصناف ضمن نطاق المستخدم (تُستخدم في تقرير الأرصدة).
  final Map<String, double> balances;

  /// المستخدم محصور بنطاق مستودعات.
  final bool scoped;

  Item? itemById(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  BeneficiaryUnit? unitById(String id) {
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }
}

class ReportsRepo {
  ReportsRepo(this.db);

  final AppDatabase db;

  static String today() => _iso(DateTime.now());
  static String daysAgo(int n) => _iso(DateTime.now().subtract(Duration(days: n)));
  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `loadAll()`
  Future<ReportData> load({List<String>? scope}) async {
    final catalog = CatalogRepo(db);
    final daily = DailyRepo(db);
    final items = await catalog.items();
    final units = await catalog.units();
    final warehouses = await catalog.warehouses(scope: scope);
    final categories = await catalog.categories();
    final suppliers = await catalog.suppliers();
    final facilities = await catalog.facilities();
    final strengths = await daily.strengths();
    final logs = await daily.kitchenLogs();
    final balances = await MovementsRepo(db).balances(scope: scope);

    final byId = {for (final i in items) i.id: i};
    final moves = <MoveRow>[];

    void push(
      dynamic r,
      String type,
      String warehouse,
      String party, {
      String destWarehouse = '',
      String unitId = '',
      String facilityId = '',
      String condition = '',
    }) {
      final it = byId[r.itemId as String? ?? ''];
      moves.add(MoveRow(
        date: (r.date as String).isEmpty ? '' : (r.date as String).substring(0, 10),
        type: type,
        refNo: r.refNo as String,
        itemId: r.itemId as String,
        itemCode: (r.itemCode as String).isNotEmpty ? r.itemCode as String : (it?.code ?? ''),
        itemName: (r.itemName as String).isNotEmpty ? r.itemName as String : (it?.name ?? ''),
        qty: (r.qty as num).toDouble(),
        unitName: (r.unitName as String).isNotEmpty ? r.unitName as String : (it?.baseUnit ?? ''),
        baseQty: (r.baseQty as num).toDouble(),
        baseUnit: it?.baseUnit ?? (r.unitName as String),
        warehouse: warehouse,
        destWarehouse: destWarehouse,
        party: party,
        status: r.status as String,
        unitId: unitId,
        facilityId: facilityId,
        condition: condition,
        notes: r.notes as String,
      ));
    }

    for (final r in await db.select(db.receipts).get()) {
      push(r, 'IN', r.warehouse, r.supplier);
    }
    for (final r in await db.select(db.issues).get()) {
      push(
        r,
        'OUT',
        r.warehouse,
        r.beneficiaryUnitName.isNotEmpty ? r.beneficiaryUnitName : r.recipientDisplay,
        unitId: r.beneficiaryUnitId.isNotEmpty ? r.beneficiaryUnitId : r.unitId,
        facilityId: r.facilityId,
      );
    }
    for (final r in await db.select(db.transfers).get()) {
      push(r, 'TRANSFER', r.warehouse, 'إلى: ${r.destWarehouse.isEmpty ? '—' : r.destWarehouse}',
          destWarehouse: r.destWarehouse);
    }
    for (final r in await db.select(db.returns).get()) {
      push(r, r.type == 'TO_SUPPLIER' ? 'RETURN_OUT' : 'RETURN_IN', r.warehouse, r.party,
          condition: r.condition, unitId: r.beneficiaryUnitId);
    }
    for (final r in await db.select(db.openingBalances).get()) {
      final it = byId[r.itemId];
      moves.add(MoveRow(
        date: r.date,
        type: 'OPENING',
        refNo: '',
        itemId: r.itemId,
        itemCode: r.itemCode,
        itemName: r.itemName,
        qty: r.qty,
        unitName: it?.baseUnit ?? '',
        baseQty: r.qty,
        baseUnit: it?.baseUnit ?? '',
        warehouse: r.warehouse,
        party: r.setBy,
        status: 'COMPLETED',
      ));
    }

    moves.sort((a, b) => b.date.compareTo(a.date));
    final scoped = scope != null;
    final visible = !scoped
        ? moves
        : moves
            .where((m) =>
                scope.contains(m.warehouse) ||
                (m.destWarehouse.isNotEmpty && scope.contains(m.destWarehouse)))
            .toList();

    return ReportData(
      items: items,
      units: units,
      warehouses: warehouses,
      categories: categories,
      suppliers: suppliers,
      facilities: facilities,
      strengths: strengths,
      kitchenLogs: logs,
      moves: visible,
      balances: balances,
      scoped: scoped,
    );
  }

  /// `FILTERS(id)` — تعريف فلاتر كل تقرير.
  static List<ReportFilterDef> filtersFor(ReportId id) {
    List<(String, String)> whOpts(ReportData d, Map<String, String> f) => [
          ('', 'الكل'),
          for (final w in d.warehouses) (w.name, w.code.isEmpty ? w.name : '${w.code} — ${w.name}'),
        ];
    List<(String, String)> typeOpts(ReportData d, Map<String, String> f) =>
        [('', 'الكل'), for (final e in kMoveTypes.entries) (e.key, e.value)];

    switch (id) {
      case ReportId.moves:
        return [
          const ReportFilterDef(key: 'range', type: 'range', defaultOn: true),
          ReportFilterDef(key: 'wh', type: 'select', label: 'المستودع', options: whOpts),
          ReportFilterDef(key: 'type', type: 'select', label: 'نوع الحركة', options: typeOpts),
        ];
      case ReportId.unitAccount:
        return [
          ReportFilterDef(
            key: 'parent',
            type: 'select',
            label: 'الوحدة الرئيسية',
            options: (d, f) => [
              ('', '— اختر —'),
              for (final u in d.units.where((x) => x.parentId.isEmpty)) (u.id, _unitLabel(u)),
            ],
          ),
          ReportFilterDef(
            key: 'child',
            type: 'select',
            label: 'الوحدة الفرعية',
            options: (d, f) => [
              ('', 'الكل (مع الفروع)'),
              for (final u in d.units.where((x) => f['parent'] != null && x.parentId == f['parent']))
                (u.id, _unitLabel(u)),
            ],
          ),
          const ReportFilterDef(key: 'range', type: 'range'),
        ];
      case ReportId.stock:
        return [
          ReportFilterDef(key: 'wh', type: 'select', label: 'المستودع', options: whOpts),
          ReportFilterDef(
            key: 'cat',
            type: 'select',
            label: 'التصنيف',
            options: (d, f) => [('', 'الكل'), for (final c in d.categories) (c.id, c.name)],
          ),
          ReportFilterDef(
            key: 'status',
            type: 'select',
            label: 'حالة الرصيد',
            options: (d, f) => const [
              ('', 'الكل'),
              ('OK', 'طبيعي'),
              ('LOW', 'منخفض'),
              ('EMPTY', 'نفد'),
            ],
          ),
        ];
      case ReportId.consumption:
        return [
          const ReportFilterDef(key: 'range', type: 'range', defaultOn: true),
          ReportFilterDef(
            key: 'group',
            type: 'select',
            label: 'تجميع حسب',
            options: (d, f) => const [
              ('item', 'الصنف'),
              ('unit', 'الوحدة المستفيدة'),
              ('wh', 'المستودع'),
            ],
          ),
        ];
      case ReportId.strength:
        return [
          const ReportFilterDef(key: 'range', type: 'range'),
          ReportFilterDef(
            key: 'camp',
            type: 'select',
            label: 'المعسكر',
            options: (d, f) => [
              ('', 'الكل'),
              for (final u in d.units.where((x) => x.isCamp || x.type == 'camp')) (u.id, _unitLabel(u)),
            ],
          ),
          ReportFilterDef(
            key: 'mode',
            type: 'select',
            label: 'مستوى العرض',
            options: (d, f) => const [
              ('', 'الكل'),
              ('camp', 'إجمالي المعسكر'),
              ('detail', 'الوحدات الفرعية'),
            ],
          ),
        ];
      case ReportId.kitchen:
        return [
          const ReportFilterDef(key: 'range', type: 'range'),
          ReportFilterDef(
            key: 'fac',
            type: 'select',
            label: 'المنشأة',
            options: (d, f) => [('', 'الكل'), for (final x in d.facilities) (x.id, x.name)],
          ),
          ReportFilterDef(
            key: 'meal',
            type: 'select',
            label: 'الوجبة',
            options: (d, f) => [('', 'الكل'), for (final e in kMeals.entries) (e.key, e.value)],
          ),
        ];
      case ReportId.supplier:
        return [
          const ReportFilterDef(key: 'range', type: 'range', fromDaysAgo: 90),
          ReportFilterDef(
            key: 'sup',
            type: 'select',
            label: 'المورد',
            options: (d, f) => [('', 'الكل'), for (final s in d.suppliers) (s.name, s.name)],
          ),
          ReportFilterDef(
            key: 'view',
            type: 'select',
            label: 'نوع العرض',
            options: (d, f) => const [
              ('detail', 'تفصيلي (حسب السند)'),
              ('summary', 'مجمّع (إجمالي الكميات)'),
            ],
          ),
        ];
      case ReportId.returns:
        return [
          const ReportFilterDef(key: 'range', type: 'range', fromDaysAgo: 90),
          ReportFilterDef(
            key: 'type',
            type: 'select',
            label: 'نوع المرتجع',
            options: (d, f) => const [
              ('', 'الكل'),
              ('RETURN_OUT', 'إرجاع إلى مورد'),
              ('RETURN_IN', 'مرتجع من وحدة'),
            ],
          ),
          ReportFilterDef(key: 'wh', type: 'select', label: 'المستودع', options: whOpts),
        ];
      case ReportId.daily:
        return [
          const ReportFilterDef(key: 'day', type: 'date', label: 'تاريخ اليوم'),
          ReportFilterDef(key: 'wh', type: 'select', label: 'المستودع', options: whOpts),
          ReportFilterDef(key: 'type', type: 'select', label: 'نوع الحركة', options: typeOpts),
        ];
    }
  }

  static String _unitLabel(BeneficiaryUnit u) =>
      (u.code.isEmpty ? u.name : '${u.code} - ${u.name}').trim();

  /// `RUN[id](f)`
  ReportResult run(ReportId id, ReportData d, Map<String, String> f) {
    switch (id) {
      case ReportId.moves:
        return _moves(d, f);
      case ReportId.unitAccount:
        return _unitAccount(d, f);
      case ReportId.stock:
        return _stock(d, f);
      case ReportId.consumption:
        return _consumption(d, f);
      case ReportId.strength:
        return _strength(d, f);
      case ReportId.kitchen:
        return _kitchen(d, f);
      case ReportId.supplier:
        return _supplier(d, f);
      case ReportId.returns:
        return _returns(d, f);
      case ReportId.daily:
        return _daily(d, f);
    }
  }

  static bool _inRange(String date, Map<String, String> f) {
    if (f['dateOn'] != '1') return true;
    if (date.isEmpty) return false;
    final from = f['from'] ?? '';
    final to = f['to'] ?? '';
    if (from.isNotEmpty && date.compareTo(from) < 0) return false;
    if (to.isNotEmpty && date.compareTo(to) > 0) return false;
    return true;
  }

  static List<(String, num)> _countBy(List<MoveRow> rows, String Function(MoveRow) key) {
    final counts = <String, int>{};
    for (final r in rows) {
      counts.update(key(r), (v) => v + 1, ifAbsent: () => 1);
    }
    return [('إجمالي السطور', rows.length), for (final e in counts.entries) (e.key, e.value)];
  }

  /// خلية رقمية: تُعرض بأرقام ar-EG كما في `fmt()` وتحتفظ بقيمتها للفرز والجمع.
  static ReportCell _n(num v) => ReportCell(nf((v * 100).round() / 100), value: v.toDouble());
  static ReportCell _t(String v) => ReportCell(v.isEmpty ? '—' : v);

  ReportResult _moves(ReportData d, Map<String, String> f) {
    final wh = f['wh'] ?? '';
    final type = f['type'] ?? '';
    final rows = d.moves
        .where((m) =>
            _inRange(m.date, f) &&
            (wh.isEmpty || m.warehouse == wh || m.destWarehouse == wh) &&
            (type.isEmpty || m.type == type))
        .toList();
    return ReportResult(
      columns: const [
        ReportColumn('التاريخ'),
        ReportColumn('النوع'),
        ReportColumn('رقم السند'),
        ReportColumn('الكود'),
        ReportColumn('الصنف'),
        ReportColumn('الكمية', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('المستودع'),
        ReportColumn('الجهة'),
        ReportColumn('الحالة'),
      ],
      rows: [
        for (final m in rows)
          [
            _t(m.date),
            _t(m.typeLabel),
            _t(m.refNo),
            _t(m.itemCode),
            _t(m.itemName),
            _n(m.qty),
            _t(m.unitName),
            _t(m.warehouse),
            _t(m.party),
            _t(m.statusLabel),
          ],
      ],
      summary: _countBy(rows, (m) => m.typeLabel),
    );
  }

  ReportResult _unitAccount(ReportData d, Map<String, String> f) {
    final root = (f['child'] ?? '').isNotEmpty ? f['child']! : (f['parent'] ?? '');
    if (root.isEmpty) {
      return const ReportResult(message: 'اختر الوحدة الرئيسية لعرض كشف الحساب.');
    }
    // الوحدة وكل فروعها في الشجرة.
    final ids = <String>{};
    void add(String id) {
      ids.add(id);
      for (final u in d.units) {
        if (u.parentId == id && !ids.contains(u.id)) add(u.id);
      }
    }

    add(root);
    final names = {
      for (final id in ids)
        if ((d.unitById(id)?.name ?? '').isNotEmpty) d.unitById(id)!.name,
    };

    final rows = d.moves
        .where((m) =>
            _inRange(m.date, f) &&
            ((m.type == 'OUT' && (ids.contains(m.unitId) || names.contains(m.party))) ||
                (m.type == 'RETURN_IN' && names.contains(m.party))))
        .toList();
    final items = <String>{for (final r in rows) r.itemId.isEmpty ? r.itemName : r.itemId};
    final u = d.unitById(root);

    return ReportResult(
      title: u == null ? '' : _unitLabel(u),
      columns: const [
        ReportColumn('التاريخ'),
        ReportColumn('الحركة'),
        ReportColumn('رقم السند'),
        ReportColumn('الوحدة'),
        ReportColumn('الصنف'),
        ReportColumn('المصروف', numeric: true),
        ReportColumn('المرتجع', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('المستودع'),
        ReportColumn('ملاحظات'),
      ],
      rows: [
        for (final m in rows)
          [
            _t(m.date),
            _t(m.typeLabel),
            _t(m.refNo),
            _t(m.party),
            _t(m.itemName),
            _n(m.type == 'OUT' ? m.qty : 0),
            _n(m.type == 'RETURN_IN' ? m.qty : 0),
            _t(m.unitName),
            _t(m.warehouse),
            _t(m.notes),
          ],
      ],
      summary: [
        ('عدد الحركات', rows.length),
        ('أصناف مستلمة', items.length),
        ('وحدات مشمولة', ids.length),
      ],
    );
  }

  ReportResult _stock(ReportData d, Map<String, String> f) {
    final wh = f['wh'] ?? '';
    final cat = f['cat'] ?? '';
    final status = f['status'] ?? '';
    // الرصيد من دفتر الحركات: إما لمستودع محدد أو لكامل نطاق المستخدم.
    final balances = wh.isEmpty ? d.balances : _warehouseBalances(d, wh);
    final cats = {for (final c in d.categories) c.id: c.name};

    String stateOf(double bal, double min) =>
        bal <= 0 ? 'EMPTY' : (min > 0 && bal <= min ? 'LOW' : 'OK');
    const labels = {'OK': 'طبيعي', 'LOW': 'منخفض', 'EMPTY': 'نفد'};
    const tones = {'OK': 'ok', 'LOW': 'pend', 'EMPTY': 'err'};

    final items = d.items.where((it) => cat.isEmpty || it.categoryId == cat).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    final rows = <List<ReportCell>>[];
    var low = 0, empty = 0, count = 0;
    for (final it in items) {
      final bal = balances[it.id] ?? 0;
      final st = stateOf(bal, it.minQty);
      if (status.isNotEmpty && st != status) continue;
      count++;
      if (st == 'LOW') low++;
      if (st == 'EMPTY') empty++;
      // الرصيد مخزَّن بالوحدة الأساسية ويُعرض بوحدة العرض المختارة للصنف.
      final shown = displayBalance(it, bal);
      final shownMin = displayBalance(it, it.minQty);
      rows.add([
        _t(it.code),
        _t(it.name),
        _t(it.categoryName.isNotEmpty ? it.categoryName : (cats[it.categoryId] ?? '')),
        _n(shownMin.qty),
        _n(shown.qty),
        _t(shown.unit),
        ReportCell(labels[st]!, tone: tones[st]!),
      ]);
    }

    return ReportResult(
      columns: const [
        ReportColumn('الكود'),
        ReportColumn('الصنف'),
        ReportColumn('التصنيف'),
        ReportColumn('حد التنبيه', numeric: true),
        ReportColumn('الرصيد', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('الحالة', chip: true),
      ],
      rows: rows,
      note: wh.isEmpty
          ? ''
          : 'رصيد المستودع محسوب من حركاته المعتمدة: الرصيد الافتتاحي والوارد '
              'والمرتجع من الوحدات والتحويلات المستلمة، ناقص المنصرف والتحويلات الصادرة.',
      summary: [('الأصناف', count), ('منخفض', low), ('نفد', empty)],
    );
  }

  Map<String, double> _warehouseBalances(ReportData d, String warehouse) {
    final out = <String, double>{};
    for (final m in d.moves) {
      if (!m.active || m.itemId.isEmpty) continue;
      if (m.warehouse == warehouse) {
        if (m.type == 'IN' || m.type == 'RETURN_IN' || m.type == 'OPENING') {
          out[m.itemId] = (out[m.itemId] ?? 0) + m.baseQty;
        } else {
          out[m.itemId] = (out[m.itemId] ?? 0) - m.baseQty;
        }
      }
      if (m.type == 'TRANSFER' && m.destWarehouse == warehouse && m.status == 'RECEIVED') {
        out[m.itemId] = (out[m.itemId] ?? 0) + m.baseQty;
      }
    }
    return out;
  }

  ReportResult _consumption(ReportData d, Map<String, String> f) {
    final group = (f['group'] ?? 'item').isEmpty ? 'item' : f['group']!;
    final src = d.moves.where((m) => m.type == 'OUT' && m.active && _inRange(m.date, f)).toList();

    final g = <String, ({String label, String unit, double qty, Set<String> refs, Set<String> items})>{};
    var total = 0.0;
    for (final m in src) {
      final key = switch (group) {
        'unit' => m.party.isEmpty ? '—' : m.party,
        'wh' => m.warehouse.isEmpty ? '—' : m.warehouse,
        _ => m.itemId.isEmpty ? m.itemName : m.itemId,
      };
      final label = switch (group) {
        'unit' || 'wh' => key,
        _ => m.itemCode.isEmpty ? m.itemName : '${m.itemCode} - ${m.itemName}',
      };
      final e = g.putIfAbsent(
        key,
        () => (label: label, unit: group == 'item' ? m.baseUnit : '', qty: 0, refs: <String>{}, items: <String>{}),
      );
      g[key] = (label: e.label, unit: e.unit, qty: e.qty + m.baseQty, refs: e.refs..add(m.refNo), items: e.items..add(m.itemId));
      total += m.baseQty;
    }

    final entries = g.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
    final groupLabel = switch (group) {
      'unit' => 'الوحدة المستفيدة',
      'wh' => 'المستودع',
      _ => 'الصنف',
    };

    return ReportResult(
      columns: [
        ReportColumn(groupLabel),
        if (group == 'item') ...const [
          ReportColumn('الكمية المصروفة', numeric: true),
          ReportColumn('وحدة الأساس'),
          ReportColumn('عدد السندات', numeric: true),
          ReportColumn('النسبة %', numeric: true),
        ] else ...const [
          ReportColumn('عدد الأصناف', numeric: true),
          ReportColumn('عدد السندات', numeric: true, sum: true),
          ReportColumn('حصة الكمية %', numeric: true),
        ],
      ],
      rows: [
        for (final e in entries)
          [
            _t(e.label),
            if (group == 'item') ...[
              _n(e.qty),
              _t(e.unit),
              _n(e.refs.length),
              _n(total == 0 ? 0 : (e.qty / total * 1000).round() / 10),
            ] else ...[
              _n(e.items.length),
              _n(e.refs.length),
              _n(total == 0 ? 0 : (e.qty / total * 1000).round() / 10),
            ],
          ],
      ],
      summary: [('سطور الصرف', src.length), ('المجموعات', entries.length)],
    );
  }

  ReportResult _strength(ReportData d, Map<String, String> f) {
    final camp = f['camp'] ?? '';
    final mode = f['mode'] ?? '';
    final rows = d.strengths
        .where((s) =>
            _inRange(s.strengthDate, f) &&
            (camp.isEmpty || s.campId == camp) &&
            (mode.isEmpty || s.mode == mode))
        .toList()
      ..sort((a, b) {
        final byDate = b.strengthDate.compareTo(a.strengthDate);
        return byDate != 0 ? byDate : a.campName.compareTo(b.campName);
      });

    return ReportResult(
      columns: const [
        ReportColumn('تاريخ الحصر'),
        ReportColumn('المعسكر'),
        ReportColumn('الوحدة'),
        ReportColumn('المستوى'),
        ReportColumn('القوة الأساسية', numeric: true, sum: true),
        ReportColumn('الزيادة %', numeric: true),
        ReportColumn('الزيادة', numeric: true, sum: true),
        ReportColumn('الإجمالي', numeric: true, sum: true),
      ],
      rows: [
        for (final s in rows)
          [
            _t(s.strengthDate),
            _t(s.campName),
            _t(s.mode == 'camp' ? '— إجمالي المعسكر —' : s.unitName),
            _t(s.mode == 'camp' ? 'إجمالي' : 'تفصيلي'),
            _n(s.soldierCount),
            _n(s.pct),
            _n(s.officerCount),
            _n(s.total != 0 ? s.total : s.soldierCount + s.officerCount),
          ],
      ],
      summary: [
        ('سجلات الحصر', rows.length),
        ('المعسكرات', {for (final r in rows) r.campName}.length),
        ('أيام الحصر', {for (final r in rows) r.strengthDate}.length),
      ],
    );
  }

  ReportResult _kitchen(ReportData d, Map<String, String> f) {
    final fac = f['fac'] ?? '';
    final meal = f['meal'] ?? '';
    final g = <String, ({String date, String fac, String meal, double strength, int lines, double actual, double expected})>{};
    for (final r in d.kitchenLogs) {
      if (!_inRange(r.date, f)) continue;
      if (fac.isNotEmpty && r.facilityId != fac) continue;
      if (meal.isNotEmpty && r.mealType != meal) continue;
      final k = '${r.date}|${r.facilityId}|${r.mealType}';
      final e = g[k] ??
          (date: r.date, fac: r.facilityName, meal: kMeals[r.mealType] ?? r.mealType, strength: r.strength, lines: 0, actual: 0.0, expected: 0.0);
      g[k] = (
        date: e.date,
        fac: e.fac,
        meal: e.meal,
        strength: e.strength,
        lines: e.lines + 1,
        actual: e.actual + r.baseQty,
        expected: e.expected + r.expectedBase,
      );
    }
    final rows = g.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    var over = 0;

    final cells = <List<ReportCell>>[];
    for (final x in rows) {
      final variance = x.actual - x.expected;
      final vpct = x.expected == 0 ? 0.0 : (variance / x.expected * 1000).round() / 10;
      if (x.expected != 0 && vpct.abs() > 10) over++;
      final flag = x.expected == 0 ? '—' : (vpct.abs() <= 10 ? 'ضمن الحد' : (vpct > 0 ? 'زيادة' : 'نقص'));
      cells.add([
        _t(x.date),
        _t(x.fac),
        _t(x.meal),
        _n(x.strength),
        _n(x.lines),
        _n(x.actual),
        _n(x.expected),
        _n(variance),
        _n(vpct),
        x.expected == 0
            ? const ReportCell('—')
            : ReportCell(flag, tone: vpct.abs() <= 10 ? 'ok' : 'pend'),
      ]);
    }

    return ReportResult(
      columns: const [
        ReportColumn('التاريخ'),
        ReportColumn('المنشأة'),
        ReportColumn('الوجبة'),
        ReportColumn('القوة', numeric: true),
        ReportColumn('عدد الأصناف', numeric: true, sum: true),
        ReportColumn('الفعلي (أساس)', numeric: true),
        ReportColumn('المتوقع (أساس)', numeric: true),
        ReportColumn('الفرق', numeric: true),
        ReportColumn('الفرق %', numeric: true),
        ReportColumn('التقييم', chip: true),
      ],
      rows: cells,
      summary: [('وجبات مسجلة', rows.length), ('تجاوز ±10%', over)],
      note: 'الكميات بوحدة الأساس لكل صنف؛ المتوقع محسوب من نسب الاستحقاق × القوة.',
    );
  }

  ReportResult _supplier(ReportData d, Map<String, String> f) {
    final sup = f['sup'] ?? '';
    final view = (f['view'] ?? 'detail').isEmpty ? 'detail' : f['view']!;
    final src = d.moves
        .where((m) => m.type == 'IN' && m.active && _inRange(m.date, f) && (sup.isEmpty || m.party == sup))
        .toList();

    if (view == 'summary') {
      final g = <String, ({String sup, String item, String unit, double qty, Set<String> refs})>{};
      for (final m in src) {
        final k = '${m.party}|${m.itemId.isEmpty ? m.itemName : m.itemId}';
        final e = g[k] ?? (sup: m.party.isEmpty ? '—' : m.party, item: m.itemName, unit: m.baseUnit, qty: 0.0, refs: <String>{});
        g[k] = (sup: e.sup, item: e.item, unit: e.unit, qty: e.qty + m.baseQty, refs: e.refs..add(m.refNo));
      }
      final rows = g.values.toList()
        ..sort((a, b) {
          final byName = a.sup.compareTo(b.sup);
          return byName != 0 ? byName : b.qty.compareTo(a.qty);
        });
      return ReportResult(
        columns: const [
          ReportColumn('المورد'),
          ReportColumn('الصنف'),
          ReportColumn('إجمالي الكمية', numeric: true),
          ReportColumn('وحدة الأساس'),
          ReportColumn('عدد السندات', numeric: true, sum: true),
        ],
        rows: [
          for (final e in rows) [_t(e.sup), _t(e.item), _n(e.qty), _t(e.unit), _n(e.refs.length)],
        ],
        summary: [
          ('الموردون', {for (final e in rows) e.sup}.length),
          ('الأصناف', rows.length),
        ],
      );
    }

    return ReportResult(
      columns: const [
        ReportColumn('التاريخ'),
        ReportColumn('رقم السند'),
        ReportColumn('المورد'),
        ReportColumn('المستودع'),
        ReportColumn('الصنف'),
        ReportColumn('الكمية', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('الحالة'),
      ],
      rows: [
        for (final m in src)
          [
            _t(m.date),
            _t(m.refNo),
            _t(m.party),
            _t(m.warehouse),
            _t(m.itemName),
            _n(m.qty),
            _t(m.unitName),
            _t(m.statusLabel),
          ],
      ],
      summary: [
        ('سطور التوريد', src.length),
        ('السندات', {for (final m in src) m.refNo}.length),
      ],
    );
  }

  ReportResult _returns(ReportData d, Map<String, String> f) {
    final type = f['type'] ?? '';
    final wh = f['wh'] ?? '';
    final rows = d.moves
        .where((m) =>
            (m.type == 'RETURN_IN' || m.type == 'RETURN_OUT') &&
            _inRange(m.date, f) &&
            (type.isEmpty || m.type == type) &&
            (wh.isEmpty || m.warehouse == wh))
        .toList();
    return ReportResult(
      columns: const [
        ReportColumn('التاريخ'),
        ReportColumn('النوع'),
        ReportColumn('رقم السند'),
        ReportColumn('الجهة'),
        ReportColumn('المستودع'),
        ReportColumn('الصنف'),
        ReportColumn('الكمية', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('الحالة'),
        ReportColumn('ملاحظات'),
      ],
      rows: [
        for (final m in rows)
          [
            _t(m.date),
            _t(m.typeLabel),
            _t(m.refNo),
            _t(m.party),
            _t(m.warehouse),
            _t(m.itemName),
            _n(m.qty),
            _t(m.unitName),
            _t(m.condition),
            _t(m.notes),
          ],
      ],
      summary: _countBy(rows, (m) => m.typeLabel),
    );
  }

  ReportResult _daily(ReportData d, Map<String, String> f) {
    final day = (f['day'] ?? '').isEmpty ? today() : f['day']!;
    final wh = f['wh'] ?? '';
    final type = f['type'] ?? '';
    final rows = d.moves
        .where((m) =>
            m.date == day &&
            (wh.isEmpty || m.warehouse == wh || m.destWarehouse == wh) &&
            (type.isEmpty || m.type == type))
        .toList();
    final meals = {
      for (final r in d.kitchenLogs.where((r) => r.date == day)) '${r.facilityId}|${r.mealType}',
    };
    final strengths = d.strengths.where((s) => s.strengthDate == day).length;

    return ReportResult(
      title: day,
      columns: const [
        ReportColumn('النوع'),
        ReportColumn('رقم السند'),
        ReportColumn('الصنف'),
        ReportColumn('الكمية', numeric: true),
        ReportColumn('الوحدة'),
        ReportColumn('المستودع'),
        ReportColumn('الجهة'),
        ReportColumn('الحالة'),
        ReportColumn('ملاحظات'),
      ],
      rows: [
        for (final m in rows)
          [
            _t(m.typeLabel),
            _t(m.refNo),
            _t(m.itemName),
            _n(m.qty),
            _t(m.unitName),
            _t(m.warehouse),
            _t(m.party),
            _t(m.statusLabel),
            _t(m.notes),
          ],
      ],
      summary: [
        ..._countBy(rows, (m) => m.typeLabel),
        ('وجبات مسجلة', meals.length),
        ('سجلات حصر القوة', strengths),
      ],
    );
  }
}
