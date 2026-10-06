import 'package:drift/drift.dart';


/// v8: طلبيات الإعاشة — فرعٌ يطلب من مستودع مورِّد، ثم تُعتمد وتُستلم.
///
/// المستودعات بأسمائها لا بمعرّفاتها، كما تفعل الحركات: نطاق صلاحيات المستخدم
/// (`Perm.canWh`) يُقاس بالاسم، فتخزينه معرّفًا يعني ترجمةً في كل فحص صلاحية.
/// v18: مستودعات المحروقات — دليلٌ مستقل عن مخازن الإعاشة.
///
/// **خزّان الوقود ليس مخزنًا للإعاشة.** له سعةٌ باللتر وموقعٌ يُشترط فيه
/// البعد عن السكن، ويمسكه أمينٌ غير أمين المستودع، ويُجرد بلجنةٍ أخرى. وجمعُ
/// الاثنين في دليلٍ واحد يجعل كل شاشة تُرشّح ما لا يخصّها، ويُدخل مخزن الطحين
/// في قائمة «من أين نصرف الديزل؟».
class FuelWarehouses extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get manager => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();

  /// السعة باللتر — صفرٌ يعني بلا سعة معلومة، فلا تُحسب نسبة إشغال.
  RealColumn get capacityLiters => real().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v18: الوحدات المستفيدة من المحروقات — دليلٌ مستقل.
///
/// مستفيدُ الوقود ليس مستفيد الإعاشة: تلك وحداتٌ لها قوةٌ تُطعَم، وهذه جهاتٌ
/// لها مركباتٌ تُزوَّد — وقد تكون ورشةً أو مولّدًا أو رتلًا عابرًا لا قوة له.
class FuelUnits extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get commander => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v18: إعدادات قسم المحروقات — سطرٌ واحد بمعرّف ثابت.
///
/// كانت الحدود والتواقيع مدفونةً في الكود، فتغييرُ حدّ التنبيه يحتاج بناءً
/// جديدًا ونشرًا على كل جهاز. وهي إعداداتُ القسم لا إعداداتُ النظام: توقيع
/// مسؤول المحروقات غير توقيع أمين المستودع.
class FuelSettingsRows extends Table {
  TextColumn get id => text()();

  /// النسبة التي يُنبَّه عند بلوغها من سعة الخزّان.
  RealColumn get lowStockPercent => real().withDefault(const Constant(20))();
  RealColumn get defaultDailyLiters =>
      real().withDefault(const Constant(200))();
  RealColumn get defaultWeeklyLiters =>
      real().withDefault(const Constant(1000))();
  RealColumn get defaultMonthlyLiters =>
      real().withDefault(const Constant(4000))();

  /// v19: ترويسة البرقية الرسمية — أربعة أسطر فوق التقرير واسمٌ مختصر
  /// للسندات. كانت مكتوبةً في الطباعة، فتغيير اسم القيادة يحتاج بناءً.
  ///
  /// وقيمها الابتدائية ترويسةُ الفرقة لا فراغ: ورقةٌ بلا رأسٍ لا تُرفع،
  /// وأوّلُ من يفتح الشاشة يطبع قبل أن يمرّ على الإعدادات.
  TextColumn get parentOrg =>
      text().withDefault(const Constant('قيادة القوات المشتركة'))();
  TextColumn get agencyTitle =>
      text().withDefault(const Constant('هيئة إدارة القوات اليمنية'))();
  TextColumn get commandTitle =>
      text().withDefault(const Constant('قيادة الفرقة الأولى'))();
  TextColumn get branchTitle =>
      text().withDefault(const Constant('شعبة الإمداد والتموين'))();

  /// اسم الجهة المختصر كما يظهر على السندات.
  TextColumn get orgName =>
      text().withDefault(const Constant('شعبة الإمداد والتموين'))();

  /// شعار الترويسة — أسطرٌ داخل الدائرة تفصل بينها فاصلة.
  TextColumn get sealLines =>
      text().withDefault(const Constant('الفرقة،الأولى،طوارئ'))();

  /// v20: عملُ كلِّ موقّعٍ ورتبتُه — كانت مكتوبةً في الطباعة، ولا تصلح
  /// لفرقةٍ غير الأولى ولا لشعبةٍ غير الإمداد.
  TextColumn get roleOfficer =>
      text().withDefault(const Constant('مسؤول محروقات المعسكر'))();
  TextColumn get roleSupply =>
      text().withDefault(const Constant('ركن إمداد الفرقة الأولى'))();
  TextColumn get roleChief =>
      text().withDefault(const Constant('رئيس شعبة الإمداد والتموين'))();

  /// تواقيع أوراق المحروقات.
  TextColumn get signOfficer => text().withDefault(const Constant(''))();
  TextColumn get signSupply => text().withDefault(const Constant(''))();
  TextColumn get signChief => text().withDefault(const Constant(''))();

  /// هل يُشترط رقم الشاصي في كل صرف؟
  BoolColumn get requireChassis =>
      boolean().withDefault(const Constant(false))();

  /// هل يُسمح بالصرف الاستثنائي خارج التفريدة؟
  BoolColumn get allowExceptional =>
      boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: تفريدة المحروقات — استحقاق وحدةٍ من الوقود في كل فترة.
///
/// **وهي غير تفريدة الإعاشة.** تلك مقرَّرٌ للفرد يُضرب في القوة، وهذه مخصَّصٌ
/// للوحدة نفسها في كل فترة: مئتا لتر يوميًّا لمعسكرٍ بصرف النظر عن عدد من فيه.
///
/// و[disbursable] ليس تكرارًا لـ[active]: تفريدةٌ سارية قد تُوقَف عن الصرف
/// حتى يأذن القائد، فتبقى قائمةً محسوبةً ولا تُصرف.
class FuelAllocations extends Table {
  TextColumn get id => text()();

  /// رمز التفريدة — يُرقَّم كبقية سندات النظام بـ`DocNumbering`، ولذلك اسمه
  /// `refNo`: العدّاد يقرأ هذا العمود بعينه في كل جدول.
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get unitId => text().withDefault(const Constant(''))();
  TextColumn get unitName => text().withDefault(const Constant(''))();

  /// petrol | diesel
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();

  /// daily | weekly | monthly | custom
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();
  RealColumn get quantityPerPeriod => real().withDefault(const Constant(0))();

  /// إجمالي الفترة المحددة (periodType = custom) — صفرٌ لغيرها.
  RealColumn get totalQuantity => real().withDefault(const Constant(0))();
  RealColumn get weeklyLiters => real().withDefault(const Constant(0))();
  RealColumn get monthlyLiters => real().withDefault(const Constant(0))();
  TextColumn get issueLocation => text().withDefault(const Constant(''))();
  TextColumn get startDate => text().withDefault(const Constant(''))();

  /// فارغ ⇒ بلا نهاية.
  TextColumn get endDate => text().withDefault(const Constant(''))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get disbursable => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: صرف محروقات — لمركبةٍ بسائقها ورقم شاصيها.
///
/// الوقود لا يُصرف لوحدةٍ في الهواء: يُصرف لمركبةٍ بعينها. و[chassisNo] هو ما
/// يجعل السؤال «كم شربت هذه المركبة هذا الشهر؟» قابلًا للإجابة — وبه يُكشف
/// الصرف المتكرر لمركبةٍ واحدة بأسماء سائقين مختلفين.
class FuelIssues extends Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();

  /// allocation | exceptional
  TextColumn get source => text().withDefault(const Constant('allocation'))();
  RealColumn get quantityLiters => real().withDefault(const Constant(0))();
  TextColumn get driverName => text().withDefault(const Constant(''))();
  TextColumn get vehicleType => text().withDefault(const Constant(''))();
  TextColumn get chassisNo => text().withDefault(const Constant(''))();
  TextColumn get allocationId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryUnitId => text().withDefault(const Constant(''))();
  TextColumn get beneficiaryName => text().withDefault(const Constant(''))();

  /// الاستحقاق وقت الصرف — يُحفظ كما كان، فلا يتغيّر السند بتغيّر التفريدة.
  RealColumn get entitledLiters => real().withDefault(const Constant(0))();
  TextColumn get periodType => text().withDefault(const Constant(''))();
  TextColumn get customFrom => text().withDefault(const Constant(''))();
  TextColumn get customTo => text().withDefault(const Constant(''))();
  TextColumn get justification => text().withDefault(const Constant(''))();
  TextColumn get orderAuthority => text().withDefault(const Constant(''))();
  TextColumn get purpose => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: توريد محروقات إلى مستودع.
class FuelSupplies extends Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();
  RealColumn get quantityLiters => real().withDefault(const Constant(0))();
  TextColumn get supplierName => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get transportVehicleType =>
      text().withDefault(const Constant(''))();
  TextColumn get driverName => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: رصيد محروقات افتتاحي لمستودع.
class FuelOpenings extends Table {
  TextColumn get id => text()();
  TextColumn get warehouse => text().withDefault(const Constant(''))();
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();
  RealColumn get liters => real().withDefault(const Constant(0))();
  TextColumn get asOfDate => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: تحويل محروقات بين مستودعين.
class FuelTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();
  RealColumn get quantityLiters => real().withDefault(const Constant(0))();
  TextColumn get fromWarehouse => text().withDefault(const Constant(''))();
  TextColumn get toWarehouse => text().withDefault(const Constant(''))();
  TextColumn get driverName => text().withDefault(const Constant(''))();
  TextColumn get transportVehicleType =>
      text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


/// v17: جرد محروقات — أمرٌ يمرّ بأربع مراحل قبل أن يمسّ الرصيد.
///
/// **لا يُعدَّل الرصيد إلا عند الترحيل** (`posted`): جردٌ في مرحلة العدّ يحمل
/// أرقامًا لم تُراجَع بعد، ولو أثّرت في الرصيد لصار كل عدٍّ ناقصٍ عجزًا مثبتًا.
class FuelStocktakes extends Table {
  TextColumn get id => text()();
  TextColumn get refNo => text().withDefault(const Constant(''))();
  TextColumn get date => text().withDefault(const Constant(''))();
  TextColumn get warehouse => text().withDefault(const Constant(''))();

  /// full | partial
  TextColumn get kind => text().withDefault(const Constant('full'))();

  /// all | petrol | diesel
  TextColumn get fuelFilter => text().withDefault(const Constant('all'))();
  TextColumn get committee => text().withDefault(const Constant(''))();

  /// open | counting | analysis | posted
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}


/// سطر جرد: الرصيد الدفتري وقت الفتح، والمعدود فعلًا.
///
/// [counted] يفصل «عُدَّ فوُجد صفرًا» عن «لم يُعدّ بعد» — والفراغ لا يُفرّق
/// بينهما، فيصير خزّانٌ لم يُفتح عجزًا كاملًا عند الترحيل.
class FuelStocktakeLines extends Table {
  TextColumn get id => text()();
  TextColumn get stocktakeId => text()();
  TextColumn get fuelType => text().withDefault(const Constant('diesel'))();
  RealColumn get bookLiters => real().withDefault(const Constant(0))();
  BoolColumn get counted => boolean().withDefault(const Constant(false))();
  RealColumn get countedLiters => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
