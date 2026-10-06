import 'package:drift/drift.dart';


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
  TextColumn get supervision =>
      text().withDefault(const Constant(''))(); // v2: المراجعة والتفتيش
  TextColumn get audit =>
      text().withDefault(const Constant(''))(); // v2: التدقيق
  // v12: تاريخ انتهاء صلاحية دفعة هذا السطر (yyyy-MM-dd)، فارغ للأصناف بلا صلاحية.
  TextColumn get expiryDate => text().withDefault(const Constant(''))();
  TextColumn get cylinderAction => text().withDefault(
      const Constant(''))(); // v2: RECEIVE_FULL | RECEIVE_EMPTY | REFILL
  @override
  Set<Column> get primaryKey => {id};
}


class Issues extends Table with MovementColumns {
  IntColumn get targetType => integer()
      .withDefault(const Constant(0))(); // 0 وحدة 1 منشأة 2 مخصص 3 متعدد
  TextColumn get recipientDisplay => text().withDefault(const Constant(''))();
  TextColumn get unitId => text().withDefault(const Constant(''))();
  TextColumn get facilityId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitName =>
      text().withDefault(const Constant(''))();
  RealColumn get soldierCount => real().withDefault(const Constant(0))();
  IntColumn get durationDays => integer().withDefault(const Constant(1))();
  // v2: اعتماد/رفض أوامر الصرف
  TextColumn get approvedBy => text().withDefault(const Constant(''))();
  TextColumn get rejectReason => text().withDefault(const Constant(''))();
  TextColumn get rejectedBy => text().withDefault(const Constant(''))();
  TextColumn get cylinderAction => text().withDefault(const Constant(
      ''))(); // v2: EXCHANGE | ISSUE_FULL | ISSUE_EMPTY | CONSUME
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
  // v13: حالة الأسطوانات المحوَّلة: TRANSFER_FULL | TRANSFER_EMPTY (فارغ لغيرها).
  TextColumn get cylinderAction => text().withDefault(const Constant(''))();
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
  TextColumn get beneficiaryUnitName =>
      text().withDefault(const Constant(''))();
  TextColumn get type => text()
      .withDefault(const Constant('FROM_UNIT'))(); // FROM_UNIT | TO_SUPPLIER
  TextColumn get condition => text().withDefault(const Constant('صالحة'))();
  TextColumn get origRef => text().withDefault(const Constant(''))();
  // v13: حالة الأسطوانات المرتجعة: RETURN_FULL | RETURN_EMPTY (فارغ لغيرها).
  TextColumn get cylinderAction => text().withDefault(const Constant(''))();
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


/// تسويات الجرد: فرق موجب أو سالب يدخل رصيد المستودع بعد اعتماد أمر الجرد.
class Adjustments extends Table with MovementColumns {
  TextColumn get sessionId => text().withDefault(const Constant(''))();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get approvedBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}
