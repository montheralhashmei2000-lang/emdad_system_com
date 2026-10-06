import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get role =>
      text().withDefault(const Constant('user'))(); // admin | user
  TextColumn get roles =>
      text().withDefault(const Constant('[]'))(); // JSON: قوالب الأدوار
  TextColumn get permissions =>
      text().withDefault(const Constant('{}'))(); // JSON
  TextColumn get warehouseScope => text()
      .withDefault(const Constant('ALL'))(); // ALL أو JSON بأسماء المستودعات
  TextColumn get saltHex => text().withDefault(const Constant(''))();
  TextColumn get hashHex => text().withDefault(const Constant(''))();
  IntColumn get iterations => integer().withDefault(const Constant(45000))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get approved => boolean().withDefault(const Constant(true))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// الأقسام المحجوبة عن المستخدم: JSON بقائمة من `supply` و`fuel` و`admin.*`.
  /// فارغ `[]` = لا حجب. (v25)
  TextColumn get sectionBlocked => text().withDefault(const Constant('[]'))();

  /// توقيع المالك (ECDSA P-256) على منح دور مدير/مالك أو فكّ حجب، يُتحقَّق منه
  /// بالمفتاح العام المدفون في التطبيق. فارغ = غير موقَّع. (v25)
  TextColumn get ownerSig => text().withDefault(const Constant(''))();

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
  TextColumn get units => text()
      .withDefault(const Constant('[]'))(); // JSON: [{name,factor,isBase}]
  RealColumn get qty =>
      real().withDefault(const Constant(0))(); // الإجمالي (للتوافق)
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

  /// v17: سعة المستودع من المحروقات باللتر، و**صفرٌ يعني بلا سعة معلومة**.
  ///
  /// المحروقات تُخزَّن في مستودعات النظام نفسها لا في دليلٍ ثانٍ: المستودع
  /// مكانٌ، وبعضه يحمل وقودًا. ودليلان للمكان الواحد يعنيان تعريفه مرتين
  /// وصيانته مرتين واختلافهما بعد أول تعديل.
  RealColumn get fuelCapacityLiters => real().withDefault(const Constant(0))();

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
  TextColumn get contact =>
      text().withDefault(const Constant(''))(); // v2: اسم جهة الاتصال
  TextColumn get city =>
      text().withDefault(const Constant(''))(); // v2: المدينة / العنوان المختصر
  @override
  Set<Column> get primaryKey => {id};
}


/// الوحدات المستفيدة والمعسكرات (شجرة: المعسكر أب والوحدات أبناء)
class BeneficiaryUnits extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get type =>
      text().withDefault(const Constant('unit'))(); // camp | unit
  TextColumn get parentId => text().withDefault(const Constant(''))();
  TextColumn get parentName => text().withDefault(const Constant(''))();
  BoolColumn get isCamp => boolean().withDefault(const Constant(false))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();

  /// v6: الوحدة قد تشترك في مطبخ **وفرن معًا**، فصار الربط قائمة لا قيمة واحدة.
  /// `facilityId` يبقى للتوافق مع البيانات القديمة وملفات التصدير السابقة.
  TextColumn get facilityIds =>
      text().withDefault(const Constant('[]'))(); // JSON
  TextColumn get category =>
      text().withDefault(const Constant(''))(); // v2: الاختصاص (مشاة…)
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


/// v5: مراجعة الأحداث الحساسة/الحرجة —
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


class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text().withDefault(const Constant(''))();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get details => text().withDefault(const Constant('{}'))(); // JSON
  TextColumn get risk => text().withDefault(const Constant('normal'))();
  TextColumn get actorEmail => text().withDefault(const Constant(''))();
  TextColumn get logDate => text().withDefault(const Constant(''))();
  // v2: حقول سجل التدقيق
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


/// إعدادات عامة (هوية الجهة، تخطيط الطباعة، إعدادات النماذج) بصيغة JSON
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {key};
}
