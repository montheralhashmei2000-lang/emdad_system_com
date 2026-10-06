import '../../../core/ui/imd_format.dart';
import '../../db/app_database.dart';

/// معرّفات التقارير بترتيب قائمتها.
enum ReportId {
  moves,
  unitAccount,
  stock,
  consumption,
  strength,
  kitchen,
  supplier,
  returns,
  daily
}


/// بطاقة التقرير في القائمة الجانبية (`REPORTS`).
class ReportInfo {
  const ReportInfo(this.id, this.icon, this.name, this.desc);
  final ReportId id;
  final String icon;
  final String name;
  final String desc;
}


const kReports = <ReportInfo>[
  ReportInfo(ReportId.moves, 'repeat', 'حركة المخزون اليومية',
      'كل الحركات حسب الفترة والمستودع والنوع'),
  ReportInfo(ReportId.unitAccount, 'file', 'كشف حساب وحدة مستفيدة',
      'المصروف والمرتجع لوحدة وفروعها'),
  ReportInfo(ReportId.stock, 'package', 'تقرير أرصدة المخزون',
      'الرصيد وحالة كل صنف، إجمالي أو لكل مستودع'),
  ReportInfo(ReportId.consumption, 'chart', 'تحليل الاستهلاك',
      'المصروف مجمّعًا حسب الصنف أو الوحدة أو المستودع'),
  ReportInfo(ReportId.strength, 'users', 'تقرير حصر القوة',
      'القوة الأساسية والزيادة لكل معسكر ووحدة'),
  ReportInfo(ReportId.kitchen, 'utensils', 'أداء المطابخ والأفران',
      'الاستهلاك الفعلي مقابل المتوقع لكل وجبة'),
  ReportInfo(ReportId.supplier, 'truck', 'ملخص توريدات الموردين',
      'تفصيلي حسب السند أو مجمّع بالكميات'),
  ReportInfo(ReportId.returns, 'undo', 'تقرير المرتجعات',
      'المرتجع من الوحدات وإلى الموردين'),
  ReportInfo(ReportId.daily, 'clipboard', 'تقرير العمل اليومي',
      'ملخص وحركات يوم واحد'),
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
  const ReportColumn(this.title,
      {this.numeric = false, this.sum = false, this.chip = false});

  final String title;
  final bool numeric;

  /// يدخل في سطر الإجمالي (عمودٌ رقميٌّ يُجمَع).
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


/// سطر الإجمالي لتقريرٍ ما — أو `null` إن لم يكن له معنى.
///
/// **الورقة تُوقَّع بمجموعها**، فالحساب هنا لا في الشاشة: منه تُبنى الشاشة
/// والورقة وملف Excel، فلا يختلف مجموعٌ عن مجموع.
///
/// ولا يُجمع سطرٌ وحيد: «الإجمالي ١٠٠» تحت «١٠٠» تكرارٌ لا خبر.
List<String>? reportTotalsRow(
  List<ReportColumn> columns,
  List<List<ReportCell>> rows, {
  String label = 'الإجمالي',
}) {
  if (rows.length < 2 || !columns.any((c) => c.numeric && c.sum)) return null;
  return [
    label,
    for (final (i, c) in columns.indexed)
      c.numeric && c.sum
          ? nf(rows.fold<double>(
              0, (a, r) => a + (i < r.length ? (r[i].value ?? 0) : 0)))
          : '',
  ];
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
  final List<(String, String)> Function(ReportData data, Map<String, String> f)?
      options;
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
    this.from = '',
    this.to = '',
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

  /// النافذة الزمنية التي حُمّلت بها [moves] — فارغة تعني «كل التاريخ».
  ///
  /// تقرأها الشاشة لتعرف أن ما بين يديها يكفي الفلتر المطلوب أم يلزم تحميل
  /// أوسع؛ بغيرها إمّا تُعيد التحميل في كل نقرة أو ترشّح على بيانات ناقصة.
  final String from;
  final String to;

  /// هل تغطّي هذه البيانات المدى المطلوب؟
  bool covers(String wantFrom, String wantTo) {
    if (from.isEmpty && to.isEmpty) return true;
    if (wantFrom.isEmpty || wantTo.isEmpty) return false;
    return from.compareTo(wantFrom) <= 0 && to.compareTo(wantTo) >= 0;
  }

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
