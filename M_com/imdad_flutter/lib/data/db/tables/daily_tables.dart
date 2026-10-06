import 'package:drift/drift.dart';


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
  TextColumn get mode =>
      text().withDefault(const Constant('detail'))(); // camp | detail
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
  RealColumn get qtyPerPerson =>
      real().withDefault(const Constant(0))(); // للشهر
  TextColumn get measureUnitName => text().withDefault(const Constant(''))();
  RealColumn get measureFactor => real().withDefault(const Constant(1))();
  TextColumn get notes =>
      text().withDefault(const Constant(''))(); // v3: ملاحظة أو شرط المقرر
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {itemId};
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
