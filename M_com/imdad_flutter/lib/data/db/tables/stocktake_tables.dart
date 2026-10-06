import 'package:drift/drift.dart';


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
  TextColumn get counts =>
      text().withDefault(const Constant('{}'))(); // JSON بالوحدات
  RealColumn get variance => real().nullable()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get decision => text().withDefault(const Constant('ADJUST'))();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  BoolColumn get discovered => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}
