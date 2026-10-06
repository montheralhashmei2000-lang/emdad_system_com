import 'package:drift/drift.dart';


/// v14: الجهات التي يُطلب منها — لا مستودعات ولا موردون.
///
/// المخزن الرئيسي لا يطلب من مستودعٍ آخر: يطلب من **جهة** في تسلسل الفرقة —
/// ركن الإمداد أو رئيس الشعبة أو قائد الفرقة. وهذه ليست طرفًا مخزنيًّا، فلا
/// رصيد لها ولا حركة عليها؛ ولذلك جدولٌ مستقل لا صفٌّ في [Warehouses].
///
/// ولأنها تُدار من الأدلة لا من الكود، تُضاف جهةٌ أو يُغيَّر مسمّاها بلا
/// تحديثٍ للبرنامج — وتُزامَن كبقية الأدلة.
class SupplyAuthorities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// المسمّى الوظيفي إن اختلف عن الاسم (مثل «ركن إمداد الفرقة»).
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


class RationOrders extends Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get requestingWarehouse =>
      text().withDefault(const Constant(''))();
  TextColumn get supplyingWarehouse => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get requiredDate => text().withDefault(const Constant(''))();

  /// DRAFT | PENDING | APPROVED | RECEIVED | REJECTED
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
  TextColumn get priority => text().withDefault(const Constant('NORMAL'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get rejectReason => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  TextColumn get approvedBy => text().withDefault(const Constant(''))();
  TextColumn get receivedBy => text().withDefault(const Constant(''))();

  /// مرجع سند الاستلام الذي وُلّد عند استلام الطلبية — به يُربط الطلب بأثره
  /// المخزني، فلا تبقى الطلبية ورقةً بلا حركة.
  TextColumn get receiptRef => text().withDefault(const Constant(''))();

  /// v14: نوع الطلبية — `MAIN` أو `BRANCH` (انظر `RationKind`).
  ///
  /// الافتراضي `BRANCH` لأن كل ما سبق هذا العمود كان بين مستودعين.
  TextColumn get orderKind => text().withDefault(const Constant('BRANCH'))();

  /// v14: الجهة المطلوب منها — لطلبية المخزن الرئيسي وحدها.
  TextColumn get authorityId => text().withDefault(const Constant(''))();
  TextColumn get authorityName => text().withDefault(const Constant(''))();

  /// v14: المستند الذي نُفِّذت به الطلبية — سند التحويل للفرعي، وسند التوريد
  /// للرئيسي. **الطلبية نفسها لا تحرّك مخزونًا**، وهذا الحقل هو كل صلتها به:
  /// به تُطابَق لاحقًا ويُعرف ما وصل مما طُلب.
  TextColumn get fulfillRef => text().withDefault(const Constant(''))();

  /// `TRANSFER` | `RECEIPT`
  TextColumn get fulfillKind => text().withDefault(const Constant(''))();
  TextColumn get fulfillDate => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}


class RationOrderLines extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get itemId => text().withDefault(const Constant(''))();
  TextColumn get itemCode => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get factor => real().withDefault(const Constant(1))();
  RealColumn get requestedQty => real().withDefault(const Constant(0))();
  RealColumn get approvedQty => real().withDefault(const Constant(0))();
  RealColumn get receivedQty => real().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}


/// v10: سجل حساب المعسكر — شهرٌ واحد لمعسكر واحد وصنف واحد.
///
/// **رصيدان لا واحد**، وخلطهما أصل الغلط في هذا الباب:
/// • **رصيد الاستحقاق** = المُرحَّل + المستحق − المُسلَّم. يُجيب: «هل أخذ
///   المعسكر حقه؟». موجب ⇒ له عندنا، سالب ⇒ أخذ أكثر من حقه.
/// • **رصيد المخزون** = المُرحَّل عينًا + المُسلَّم − المستهلك في المطبخ.
///   يُجيب: «كم بقي في مخزن المعسكر الآن؟».
///
/// وحدةٌ أخذت كامل حقها وطبخته: رصيد استحقاقها صفر ومخزونها صفر. وأخرى أخذت
/// حقها ولم تطبخه: استحقاقها صفر ومخزونها ممتلئ. الرقمان مختلفان ويُسأل عن
/// كليهما — ولذلك عمودان للترحيل لا عمود.
class CampLedgers extends Table {
  TextColumn get id => text()();
  TextColumn get campId => text()();
  TextColumn get campName => text().withDefault(const Constant(''))();
  TextColumn get itemId => text()();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  IntColumn get year => integer()();
  IntColumn get month => integer()();

  /// رصيد الاستحقاق المُرحَّل من الشهر السابق.
  RealColumn get openingEntitled => real().withDefault(const Constant(0))();

  /// رصيد المخزون العيني المُرحَّل.
  RealColumn get openingStock => real().withDefault(const Constant(0))();

  /// المستحق: المعدل اليومي للفرد × مجموع القوى اليومية.
  RealColumn get entitlementTotal => real().withDefault(const Constant(0))();
  RealColumn get transferredIn => real().withDefault(const Constant(0))();
  RealColumn get issuedDirect => real().withDefault(const Constant(0))();
  RealColumn get returnedQty => real().withDefault(const Constant(0))();
  RealColumn get consumedKitchen => real().withDefault(const Constant(0))();

  /// مجموع القوى اليومية وعدد أيامها — يُحفظان ليُقرأ التقرير بعد إغلاق الشهر
  /// بلا إعادة حساب من جداول قد تتغيّر.
  RealColumn get strengthSum => real().withDefault(const Constant(0))();
  IntColumn get strengthDays => integer().withDefault(const Constant(0))();

  /// OPEN | CLOSED
  TextColumn get status => text().withDefault(const Constant('OPEN'))();
  TextColumn get closedBy => text().withDefault(const Constant(''))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// حدّا المخزون لصنف في معسكر — منهما يُحسب التنبيه قبل النفاد.
/// v16: حدود مخزون الصنف في **مستودع**.
///
/// كانت الحدود معلّقةً بالمعسكرات، والمعسكر جهةٌ مستفيدة لا مكان تخزين:
/// الرصيد الذي يُقارَن بالحد يقع في مستودع، ومن المستودع يُطلب التعويض.
/// فربطُها بالمستودع يجعل السؤال والجواب في مكانٍ واحد.
///
/// **[minStock] و[maxStock] بوحدة الأساس**، وبها تُقارن الأرصدة مهما اختلفت
/// وحدة الإدخال. و[unitName] و[factor] يحفظان ما أدخله المستخدم فعلًا، فيُعاد
/// عرضه كما كتبه: من أدخل «٥ كراتين» يرى ٥ كراتين لا ١٢٠ حبة.
class WarehouseStockLimits extends Table {
  TextColumn get id => text()();
  TextColumn get warehouseId => text()();
  TextColumn get warehouseName => text().withDefault(const Constant(''))();
  TextColumn get itemId => text()();
  TextColumn get itemName => text().withDefault(const Constant(''))();

  /// وحدة الإدخال ومعاملها إلى وحدة الأساس.
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get factor => real().withDefault(const Constant(1))();

  /// بوحدة الأساس دائمًا.
  RealColumn get minStock => real().withDefault(const Constant(0))();
  RealColumn get maxStock => real().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


class CampStockLimits extends Table {
  TextColumn get id => text()();
  TextColumn get campId => text()();
  TextColumn get campName => text().withDefault(const Constant(''))();
  TextColumn get itemId => text()();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  RealColumn get minStock => real().withDefault(const Constant(0))();
  RealColumn get maxStock => real().withDefault(const Constant(0))();

  /// كم يومًا قبل بلوغ الحد الأدنى يبدأ التنبيه.
  IntColumn get alertDaysBefore => integer().withDefault(const Constant(2))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// أرشيف تصفيات الشهر — سطر لكل شهر أُغلق.
class MonthlySettlements extends Table {
  TextColumn get id => text()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  TextColumn get settledBy => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get campsCount => integer().withDefault(const Constant(0))();
  IntColumn get itemsCount => integer().withDefault(const Constant(0))();
  RealColumn get totalCredit => real().withDefault(const Constant(0))();
  RealColumn get totalDebit => real().withDefault(const Constant(0))();
  DateTimeColumn get settledAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
