import 'package:drift/drift.dart';

import '../repos/audit_repo.dart';
import '../repos/signatures_repo.dart';
import '../sync/sync_marks.dart';
import 'connection/connection.dart';

part 'app_database.g.dart';

/// مخطط قاعدة البيانات المحلية (SQLite عبر Drift) — نقل مباشر لمجموعات نظام الويب:
/// users, items, categories, warehouses, suppliers, units, facilities,
/// receipts, issues, transfers, returns, openingBalances, strengths,
/// kitchenLogs, entitlements, stocktakes, stocktakeLines, auditLogs, appSettings.
/// كل جدول حركة يحفظ سطرًا لكل صنف مع بيانات السند (نفس بنية النسخة الحالية).

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get role => text().withDefault(const Constant('user'))(); // admin | user
  TextColumn get roles => text().withDefault(const Constant('[]'))(); // JSON: قوالب الأدوار
  TextColumn get permissions => text().withDefault(const Constant('{}'))(); // JSON
  TextColumn get warehouseScope => text().withDefault(const Constant('ALL'))(); // ALL أو JSON بأسماء المستودعات
  TextColumn get saltHex => text().withDefault(const Constant(''))();
  TextColumn get hashHex => text().withDefault(const Constant(''))();
  IntColumn get iterations => integer().withDefault(const Constant(45000))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get approved => boolean().withDefault(const Constant(true))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class Items extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get categoryId => text().withDefault(const Constant(''))();
  TextColumn get categoryName => text().withDefault(const Constant(''))();
  TextColumn get baseUnit => text().withDefault(const Constant(''))();
  TextColumn get units => text().withDefault(const Constant('[]'))(); // JSON: [{name,factor,isBase}]
  RealColumn get qty => real().withDefault(const Constant(0))(); // الإجمالي (للتوافق)
  RealColumn get minQty => real().withDefault(const Constant(0))();
  TextColumn get barcode => text().withDefault(const Constant(''))();
  BoolColumn get isRefillable => boolean().withDefault(const Constant(false))();
  /// v7: وحدة العرض الافتراضية — الرصيد يُخزَّن دائمًا بالوحدة الأساسية، لكن
  /// يُعرض بهذه الوحدة في التقارير وفي رصيد شاشات الإدخال. فارغة = الأساسية.
  TextColumn get reportUnit => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class Warehouses extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get manager => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();
  BoolColumn get feedsAllCamps => boolean().withDefault(const Constant(true))();

  /// v10: المخزن الرئيسي للوحدة — منه وحده تُغذّى المعسكرات.
  ///
  /// واحد لا أكثر: تعيين مخزن رئيسيًا يُلغي السابق (`CampLedgerRepo.setMain`).
  BoolColumn get isMain => boolean().withDefault(const Constant(false))();
  TextColumn get campIds => text().withDefault(const Constant('[]'))(); // JSON
  TextColumn get notes => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get contact => text().withDefault(const Constant(''))(); // v2: اسم جهة الاتصال
  TextColumn get city => text().withDefault(const Constant(''))(); // v2: المدينة / العنوان المختصر
  @override
  Set<Column> get primaryKey => {id};
}

/// الوحدات المستفيدة والمعسكرات (شجرة: المعسكر أب والوحدات أبناء)
class BeneficiaryUnits extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('unit'))(); // camp | unit
  TextColumn get parentId => text().withDefault(const Constant(''))();
  TextColumn get parentName => text().withDefault(const Constant(''))();
  BoolColumn get isCamp => boolean().withDefault(const Constant(false))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  /// v6: الوحدة قد تشترك في مطبخ **وفرن معًا**، فصار الربط قائمة لا قيمة واحدة.
  /// `facilityId` يبقى للتوافق مع البيانات القديمة وملفات التصدير السابقة.
  TextColumn get facilityIds => text().withDefault(const Constant('[]'))(); // JSON
  TextColumn get category => text().withDefault(const Constant(''))(); // v2: الاختصاص (مشاة…)
  @override
  Set<Column> get primaryKey => {id};
}

/// المطابخ والأفران
class Facilities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get fType => text().withDefault(const Constant('kitchen'))();
  IntColumn get capacity => integer().withDefault(const Constant(0))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

/// أعمدة مشتركة لكل سطور الحركات
mixin MovementColumns on Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))(); // yyyy-MM-dd
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get itemId => text().withDefault(const Constant(''))();
  TextColumn get itemCode => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get factor => real().withDefault(const Constant(1))();
  RealColumn get qty => real().withDefault(const Constant(0))();
  RealColumn get baseQty => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get editCount => integer().withDefault(const Constant(0))();
  TextColumn get editLog => text().withDefault(const Constant('[]'))(); // JSON
  // v2: تعديل وإلغاء المستندات من سجل المستندات (documents-center.js)
  TextColumn get editedBy => text().withDefault(const Constant(''))();
  TextColumn get cancelReason => text().withDefault(const Constant(''))();
  TextColumn get cancelledBy => text().withDefault(const Constant(''))();
  TextColumn get prevStatus => text().withDefault(const Constant(''))();
}

class Receipts extends Table with MovementColumns {
  TextColumn get supplier => text().withDefault(const Constant(''))();
  TextColumn get invoiceNo => text().withDefault(const Constant(''))();
  TextColumn get committee => text().withDefault(const Constant(''))();
  TextColumn get supervision => text().withDefault(const Constant(''))(); // v2: المراجعة والتفتيش
  TextColumn get audit => text().withDefault(const Constant(''))(); // v2: التدقيق
  TextColumn get cylinderAction => text().withDefault(const Constant(''))(); // v2: RECEIVE_FULL | RECEIVE_EMPTY | REFILL
  @override
  Set<Column> get primaryKey => {id};
}

class Issues extends Table with MovementColumns {
  IntColumn get targetType => integer().withDefault(const Constant(0))(); // 0 وحدة 1 منشأة 2 مخصص 3 متعدد
  TextColumn get recipientDisplay => text().withDefault(const Constant(''))();
  TextColumn get unitId => text().withDefault(const Constant(''))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName => text().withDefault(const Constant(''))();
  RealColumn get soldierCount => real().withDefault(const Constant(0))();
  IntColumn get durationDays => integer().withDefault(const Constant(1))();
  // v2: اعتماد/رفض أوامر الصرف كما في الويب
  TextColumn get approvedBy => text().withDefault(const Constant(''))();
  TextColumn get rejectReason => text().withDefault(const Constant(''))();
  TextColumn get rejectedBy => text().withDefault(const Constant(''))();
  TextColumn get cylinderAction => text().withDefault(const Constant(''))(); // v2: EXCHANGE | ISSUE_FULL | ISSUE_EMPTY | CONSUME
  RealColumn get officerCount => real().withDefault(const Constant(0))(); // v2
  @override
  Set<Column> get primaryKey => {id};
}

class Transfers extends Table with MovementColumns {
  TextColumn get destWarehouse => text().withDefault(const Constant(''))();
  TextColumn get campId => text().withDefault(const Constant(''))();
  TextColumn get campName => text().withDefault(const Constant(''))();
  RealColumn get strength => real().withDefault(const Constant(0))();
  IntColumn get durationDays => integer().withDefault(const Constant(1))();
  TextColumn get rejectReason => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class Returns extends Table with MovementColumns {
  TextColumn get party => text().withDefault(const Constant(''))();

  /// v11: الوحدة التي أعادت الأصناف — **بمعرّفها** لا باسمها وحده.
  ///
  /// كان الربط بالاسم ([party]) فقط، فتفشل نسبةُ المرتجع إلى معسكره صامتةً
  /// كلما اختلف الإملاء أو أُعيدت تسمية الوحدة — فيبدو المعسكر مستلمًا ما
  /// ردّه، ويُحرم من استحقاقه في الشهر التالي.
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant('FROM_UNIT'))(); // FROM_UNIT | TO_SUPPLIER
  TextColumn get condition => text().withDefault(const Constant('صالحة'))();
  TextColumn get origRef => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class OpeningBalances extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  TextColumn get itemCode => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  RealColumn get qty => real().withDefault(const Constant(0))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get setBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// حصر القوة اليومي (التفريدة)
class Strengths extends Table {
  TextColumn get id => text()();
  TextColumn get unitId => text()();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  TextColumn get campId => text().withDefault(const Constant(''))();
  TextColumn get campName => text().withDefault(const Constant(''))();
  TextColumn get strengthDate => text()(); // yyyy-MM-dd
  RealColumn get soldierCount => real().withDefault(const Constant(0))();
  RealColumn get officerCount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get pct => real().withDefault(const Constant(0))();
  TextColumn get mode => text().withDefault(const Constant('detail'))(); // camp | detail
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class KitchenLogs extends Table {
  TextColumn get id => text()();
  TextColumn get facilityId => text()();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get date => text()();
  TextColumn get mealType => text().withDefault(const Constant('LUNCH'))();
  RealColumn get strength => real().withDefault(const Constant(0))();
  TextColumn get itemId => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get qty => real().withDefault(const Constant(0))();
  RealColumn get baseQty => real().withDefault(const Constant(0))();
  RealColumn get expectedBase => real().withDefault(const Constant(0))();
  RealColumn get varianceBase => real().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// نسب الاستحقاق: كمية شهرية للفرد بوحدة مختارة
class Entitlements extends Table {
  TextColumn get itemId => text()();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  RealColumn get qtyPerPerson => real().withDefault(const Constant(0))(); // للشهر
  TextColumn get measureUnitName => text().withDefault(const Constant(''))();
  RealColumn get measureFactor => real().withDefault(const Constant(1))();
  TextColumn get notes => text().withDefault(const Constant(''))(); // v3: ملاحظة أو شرط المقرر
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {itemId};
}

/// v5: مراجعة الأحداث الحساسة/الحرجة (`sensitiveReviews` في الويب) —
/// سطر لكل حدث في سجل التدقيق تمت مراجعته، فلا يظهر ضمن «غير المراجَع».
class SensitiveReviews extends Table {
  TextColumn get id => text()();
  TextColumn get logId => text()();
  TextColumn get reviewedBy => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get reviewedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class Stocktakes extends Table {
  TextColumn get id => text()();
  TextColumn get orderNo => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant('FULL'))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().withDefault(const Constant(''))();
  TextColumn get categoryName => text().withDefault(const Constant(''))(); // v4
  TextColumn get committee => text().withDefault(const Constant(''))();
  BoolColumn get freeze => boolean().withDefault(const Constant(true))();
  TextColumn get status => text().withDefault(const Constant('COUNTING'))();
  IntColumn get itemsCount => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get closedDate => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // v4: إلغاء أمر الجرد وإحصاءات الإغلاق كما في stocktake-center.js
  TextColumn get cancelReason => text().withDefault(const Constant(''))();
  TextColumn get cancelledBy => text().withDefault(const Constant(''))();
  TextColumn get closedBy => text().withDefault(const Constant(''))();
  IntColumn get countedCount => integer().withDefault(const Constant(0))();
  IntColumn get varianceCount => integer().withDefault(const Constant(0))();
  IntColumn get adjustedCount => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class StocktakeLines extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get itemId => text()();
  TextColumn get itemCode => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get systemQty => real().withDefault(const Constant(0))();
  RealColumn get countedQty => real().nullable()();
  TextColumn get counts => text().withDefault(const Constant('{}'))(); // JSON بالوحدات
  RealColumn get variance => real().nullable()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get decision => text().withDefault(const Constant('ADJUST'))();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  BoolColumn get discovered => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// تسويات الجرد: فرق موجب أو سالب يدخل رصيد المستودع بعد اعتماد أمر الجرد.
class Adjustments extends Table with MovementColumns {
  TextColumn get sessionId => text().withDefault(const Constant(''))();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get approvedBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text().withDefault(const Constant(''))();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get details => text().withDefault(const Constant('{}'))(); // JSON
  TextColumn get risk => text().withDefault(const Constant('normal'))();
  TextColumn get actorEmail => text().withDefault(const Constant(''))();
  TextColumn get logDate => text().withDefault(const Constant(''))();
  // v2: حقول auditWrite في الويب
  TextColumn get actorName => text().withDefault(const Constant(''))();
  TextColumn get actorRole => text().withDefault(const Constant('user'))();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get target => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant(''))();
  IntColumn get itemCount => integer().withDefault(const Constant(0))();
  RealColumn get qty => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// v8: الأصول الثابتة — ما يُقتنى ويُعمَّر ثم يُستهلك، لا ما يُصرف.
///
/// المعرّف نصّي كبقية جداول النظام لا رقمًا تلقائيًا: جهازان يعملان بلا شبكة
/// يولّدان الرقم `1` لأصلين مختلفين، فيدهس أحدهما الآخر عند أول مزامنة.
///
/// و[warehouse] ليس زينة: به يخضع الأصل لنطاق مستودعات المستخدم كما تخضع
/// الحركات، فلا يرى مسؤول فرعٍ أصولَ فرعٍ آخر.
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get assetType => text().withDefault(const Constant('equipment'))();
  TextColumn get serialNumber => text().withDefault(const Constant(''))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('NEW'))();

  /// yyyy-MM-dd — نصًّا كتواريخ الحركات، فلا يزيحها اختلاف المناطق الزمنية.
  TextColumn get acquisitionDate => text().withDefault(const Constant(''))();
  RealColumn get value => real().withDefault(const Constant(0))();
  IntColumn get lifespanMonths => integer().withDefault(const Constant(0))();
  TextColumn get supplierId => text().withDefault(const Constant(''))();
  TextColumn get supplierName => text().withDefault(const Constant(''))();
  TextColumn get invoiceNumber => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// عهدة أصل لدى وحدة مستفيدة. [returnedDate] فارغة ⇒ العهدة قائمة.
///
/// الفراغ لا `NULL` كبقية النظام: عمود نصّي واحد يُقارن ويُصدَّر ويُدمج بلا
/// حالة ثالثة.
class AssetAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get assetName => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName => text().withDefault(const Constant(''))();
  TextColumn get assignedDate => text().withDefault(const Constant(''))();
  TextColumn get returnedDate => text().withDefault(const Constant(''))();
  TextColumn get assignedTo => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// v8: طلبيات الإعاشة — فرعٌ يطلب من مستودع مورِّد، ثم تُعتمد وتُستلم.
///
/// المستودعات بأسمائها لا بمعرّفاتها، كما تفعل الحركات: نطاق صلاحيات المستخدم
/// (`Perm.canWh`) يُقاس بالاسم، فتخزينه معرّفًا يعني ترجمةً في كل فحص صلاحية.
/// v12: الجهات التي يُطلب منها — لا مستودعات ولا موردون.
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
  TextColumn get requestingWarehouse => text().withDefault(const Constant(''))();
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

  /// v12: نوع الطلبية — `MAIN` أو `BRANCH` (انظر `RationKind`).
  ///
  /// الافتراضي `BRANCH` لأن كل ما سبق هذا العمود كان بين مستودعين.
  TextColumn get orderKind => text().withDefault(const Constant('BRANCH'))();

  /// v12: الجهة المطلوب منها — لطلبية المخزن الرئيسي وحدها.
  TextColumn get authorityId => text().withDefault(const Constant(''))();
  TextColumn get authorityName => text().withDefault(const Constant(''))();

  /// v12: المستند الذي نُفِّذت به الطلبية — سند التحويل للفرعي، وسند التوريد
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

/// v9: خطة الوجبات — ما يُطبخ في كل يوم ووجبة، وكم لكل فرد.
///
/// **وهي غير نسب الاستحقاق.** النسبة مقرَّر شهري ثابت للفرد من كل صنف
/// (`Entitlements`)، والخطة قائمة طعام: أرزٌ يوم الأحد ومعكرونة يوم الاثنين.
/// من النسبة تُعرف حصة الشهر، ومن الخطة يُعرف طلب الغد.
class MealPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// WEEKLY | BIWEEKLY | MONTHLY | CUSTOM
  TextColumn get planType => text().withDefault(const Constant('WEEKLY'))();
  TextColumn get startDate => text().withDefault(const Constant(''))();
  TextColumn get endDate => text().withDefault(const Constant(''))();

  /// DRAFT | ACTIVE | ARCHIVED
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();

  /// المطبخ أو الفرن الذي تنفَّذ فيه الخطة — فارغ يعني الوحدة كلها.
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// صنف واحد في وجبة واحدة من يوم واحد.
///
/// [qtyPerPerson] بوحدة [unitName]، و[factor] يحوّلها إلى وحدة الأساس — نفس
/// اصطلاح سطور الحركات، فيُجمع الاثنان بلا ترجمة.
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text()();
  TextColumn get entryDate => text().withDefault(const Constant(''))();

  /// BREAKFAST | LUNCH | DINNER | SNACK
  TextColumn get mealType => text().withDefault(const Constant('LUNCH'))();
  TextColumn get itemId => text().withDefault(const Constant(''))();
  TextColumn get itemCode => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();
  RealColumn get factor => real().withDefault(const Constant(1))();
  RealColumn get qtyPerPerson => real().withDefault(const Constant(0))();
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

/// إعدادات عامة (هوية الجهة، تخطيط الطباعة، إعدادات النماذج) بصيغة JSON
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  SupplyAuthorities,
  Users,
  Categories,
  Items,
  Warehouses,
  Suppliers,
  BeneficiaryUnits,
  Facilities,
  Receipts,
  Issues,
  Transfers,
  Returns,
  OpeningBalances,
  Strengths,
  KitchenLogs,
  Entitlements,
  Stocktakes,
  StocktakeLines,
  Adjustments,
  AuditLogs,
  SensitiveReviews,
  Assets,
  AssetAssignments,
  RationOrders,
  RationOrderLines,
  MealPlans,
  MealPlanEntries,
  CampLedgers,
  CampStockLimits,
  MonthlySettlements,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

  /// الفهارس المخدومة فعليًا بالاستعلامات: البحث بالمرجع (فتح سند من سجل
  /// المستندات)، وبالحالة (الأوامر المعلقة والمسودات)، وبالمستودع والصنف
  /// (حساب الأرصدة)، وبالتاريخ (تقارير المدى).
  ///
  /// تُنشأ عند كل فتح بـ `IF NOT EXISTS` لا في ترقية بنسخة جديدة: العملية
  /// بلا تكلفة إذا كان الفهرس موجودًا، وتشمل قواعد البيانات القديمة كلها.
  Future<void> _createIndexes() async {
    const movementTables = ['receipts', 'issues', 'transfers', 'returns', 'adjustments'];
    final statements = <String>[
      for (final t in movementTables) ...[
        'CREATE INDEX IF NOT EXISTS ix_${t}_ref ON $t (ref_no)',
        'CREATE INDEX IF NOT EXISTS ix_${t}_status ON $t (status)',
        'CREATE INDEX IF NOT EXISTS ix_${t}_wh_item ON $t (warehouse, item_id)',
        'CREATE INDEX IF NOT EXISTS ix_${t}_date ON $t (date)',
      ],
      'CREATE INDEX IF NOT EXISTS ix_opening_wh_item ON opening_balances (warehouse, item_id)',
      'CREATE INDEX IF NOT EXISTS ix_transfers_dest ON transfers (dest_warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_items_code ON items (code)',
      'CREATE INDEX IF NOT EXISTS ix_items_barcode ON items (barcode)',
      'CREATE INDEX IF NOT EXISTS ix_items_category ON items (category_id)',
      'CREATE INDEX IF NOT EXISTS ix_audit_date ON audit_logs (log_date)',
      'CREATE INDEX IF NOT EXISTS ix_audit_created ON audit_logs (created_at)',
      'CREATE INDEX IF NOT EXISTS ix_stocktake_lines_session ON stocktake_lines (session_id)',
      'CREATE INDEX IF NOT EXISTS ix_stocktakes_wh ON stocktakes (warehouse, status)',
      'CREATE INDEX IF NOT EXISTS ix_strengths_date ON strengths (strength_date)',
      'CREATE INDEX IF NOT EXISTS ix_kitchen_logs_date ON kitchen_logs (date)',
      'CREATE INDEX IF NOT EXISTS ix_assets_type_status ON assets (asset_type, status)',
      'CREATE INDEX IF NOT EXISTS ix_assets_wh ON assets (warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_asset_assign_asset ON asset_assignments (asset_id)',
      'CREATE INDEX IF NOT EXISTS ix_ration_status ON ration_orders (status)',
      'CREATE INDEX IF NOT EXISTS ix_ration_wh ON ration_orders (requesting_warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_ration_lines_order ON ration_order_lines (order_id)',
      'CREATE INDEX IF NOT EXISTS ix_meal_plans_status ON meal_plans (status)',
      'CREATE INDEX IF NOT EXISTS ix_meal_entries_plan ON meal_plan_entries (plan_id, entry_date)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_camp_ledger ON camp_ledgers (camp_id, item_id, year, month)',
      'CREATE INDEX IF NOT EXISTS ix_camp_ledger_month ON camp_ledgers (year, month, status)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_camp_limit ON camp_stock_limits (camp_id, item_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_settlement_month ON monthly_settlements (year, month)',
      'CREATE INDEX IF NOT EXISTS ix_returns_unit ON returns (beneficiary_unit_id)',
      'CREATE INDEX IF NOT EXISTS ix_ration_kind ON ration_orders (order_kind, status)',
      'CREATE INDEX IF NOT EXISTS ix_ration_supply ON ration_orders (supplying_warehouse, status)',
    ];
    for (final sql in statements) {
      await customStatement(sql);
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: حقول الموردين وسجل التدقيق كما في نسخة الويب.
          if (from < 2) {
            await m.addColumn(suppliers, suppliers.contact);
            await m.addColumn(suppliers, suppliers.city);
            await m.addColumn(beneficiaryUnits, beneficiaryUnits.category);
            await m.addColumn(issues, issues.approvedBy);
            await m.addColumn(issues, issues.rejectReason);
            await m.addColumn(issues, issues.rejectedBy);
            await m.addColumn(issues, issues.cylinderAction);
            await m.addColumn(issues, issues.officerCount);
            await m.addColumn(receipts, receipts.supervision);
            await m.addColumn(receipts, receipts.audit);
            await m.addColumn(receipts, receipts.cylinderAction);
            for (final col in [
              receipts.editedBy, receipts.cancelReason, receipts.cancelledBy, receipts.prevStatus,
            ]) {
              await m.addColumn(receipts, col);
            }
            for (final col in [
              issues.editedBy, issues.cancelReason, issues.cancelledBy, issues.prevStatus,
            ]) {
              await m.addColumn(issues, col);
            }
            for (final col in [
              transfers.editedBy, transfers.cancelReason, transfers.cancelledBy, transfers.prevStatus,
            ]) {
              await m.addColumn(transfers, col);
            }
            for (final col in [
              returns.editedBy, returns.cancelReason, returns.cancelledBy, returns.prevStatus,
            ]) {
              await m.addColumn(returns, col);
            }
            for (final col in [
              adjustments.editedBy, adjustments.cancelReason, adjustments.cancelledBy, adjustments.prevStatus,
            ]) {
              await m.addColumn(adjustments, col);
            }
            for (final col in [
              auditLogs.actorName,
              auditLogs.actorRole,
              auditLogs.refNo,
              auditLogs.warehouse,
              auditLogs.target,
              auditLogs.status,
              auditLogs.itemCount,
              auditLogs.qty,
            ]) {
              await m.addColumn(auditLogs, col);
            }
          }
          // v3: ملاحظة المقرر في شاشة نسب الاستهلاك.
          if (from < 3) {
            await m.addColumn(entitlements, entitlements.notes);
          }
          // v5: جدول مراجعة الأحداث الحساسة.
          if (from < 5) {
            await m.createTable(sensitiveReviews);
          }
          // v7: وحدة العرض الافتراضية في بطاقة الصنف.
          if (from < 7) {
            await m.addColumn(items, items.reportUnit);
          }
          // v6: ربط الوحدة بأكثر من منشأة (مطبخ وفرن معًا).
          if (from < 6) {
            await m.addColumn(beneficiaryUnits, beneficiaryUnits.facilityIds);
            // نقل الارتباط المفرد القديم إلى القائمة حتى لا تنقطع الاشتراكات.
            await customStatement(
              "UPDATE beneficiary_units SET facility_ids = '[\"' || facility_id || '\"]' "
              "WHERE facility_id <> '' AND (facility_ids = '[]' OR facility_ids IS NULL)",
            );
          }
          // v4: حقول إلغاء أمر الجرد وإحصاءات إغلاقه.
          if (from < 4) {
            for (final col in [
              stocktakes.categoryName,
              stocktakes.cancelReason,
              stocktakes.cancelledBy,
              stocktakes.closedBy,
              stocktakes.countedCount,
              stocktakes.varianceCount,
              stocktakes.adjustedCount,
            ]) {
              await m.addColumn(stocktakes, col);
            }
          }
          // v8: الأصول الثابتة وعهدها، وطلبيات الإعاشة وسطورها.
          if (from < 8) {
            await m.createTable(assets);
            await m.createTable(assetAssignments);
            await m.createTable(rationOrders);
            await m.createTable(rationOrderLines);
          }
          // v9: خطط الوجبات ومدخلاتها.
          if (from < 9) {
            await m.createTable(mealPlans);
            await m.createTable(mealPlanEntries);
          }
          // v10: سجل حساب المعسكرات وحدود مخزونها وأرشيف التصفيات.
          if (from < 10) {
            await m.addColumn(warehouses, warehouses.isMain);
            await m.createTable(campLedgers);
            await m.createTable(campStockLimits);
            await m.createTable(monthlySettlements);
          }
          // v11: ربط المرتجع بوحدته بالمعرّف لا بالاسم.
          if (from < 11) {
            await m.addColumn(returns, returns.beneficiaryUnitId);
            await m.addColumn(returns, returns.beneficiaryUnitName);
          }
          // v12: نوع الطلبية وجهتها ومستند تنفيذها.
          if (from < 12) {
            await m.createTable(supplyAuthorities);
            await m.addColumn(rationOrders, rationOrders.orderKind);
            await m.addColumn(rationOrders, rationOrders.authorityId);
            await m.addColumn(rationOrders, rationOrders.authorityName);
            await m.addColumn(rationOrders, rationOrders.fulfillRef);
            await m.addColumn(rationOrders, rationOrders.fulfillKind);
            await m.addColumn(rationOrders, rationOrders.fulfillDate);
            // الطلبيات المستلمة قبل هذا الإصدار وُلِّد لها سند استلام فعلًا،
            // فيُنقل مرجعه إلى حقل التنفيذ حتى لا تبدو بلا أثر.
            await customStatement(
              "UPDATE ration_orders SET fulfill_ref = receipt_ref, "
              "fulfill_kind = 'RECEIPT' WHERE receipt_ref <> ''",
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          await _createIndexes();
          await SyncMarks.install(this);
          await SignaturesRepo.install(this);
          // شواهد الحذف تنمو بلا حد لو تُركت: تُنظَّف القديمة عند كل تشغيل.
          await SyncMarks(this).pruneTombstones();
          // وكذلك سجل التدقيق العادي — وعالي الخطورة يبقى.
          await AuditRepo(this).prune();
        },
      );
}

QueryExecutor _open() => openConnection();
