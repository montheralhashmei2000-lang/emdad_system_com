import 'package:drift/drift.dart';


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

  /// v16: عدد القطع في هذا السطر.
  ///
  /// أصلٌ مسلسل قطعةٌ واحدة برقمها، أما خمسون كرسيًّا متطابقًا فسطرٌ واحد
  /// بكمية. وإجبار كلٍّ منها على سطر يجعل إدخال دفعةٍ عملَ ساعة، ويملأ
  /// السجل بخمسين سطرًا لا يفرّق بينها شيء.
  RealColumn get quantity => real().withDefault(const Constant(1))();
  TextColumn get assetType => text().withDefault(const Constant('equipment'))();
  TextColumn get serialNumber => text().withDefault(const Constant(''))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName =>
      text().withDefault(const Constant(''))();
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
  TextColumn get beneficiaryUnitName =>
      text().withDefault(const Constant(''))();
  TextColumn get assignedDate => text().withDefault(const Constant(''))();
  TextColumn get returnedDate => text().withDefault(const Constant(''))();
  TextColumn get assignedTo => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
