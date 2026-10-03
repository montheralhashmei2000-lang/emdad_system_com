import 'package:drift/drift.dart';

/// جداول «الارتباطات» — أُضيفت في إصدار المخطط v22.
///
/// الارتباطات ثلاثة أبوابٍ مترابطة: **القوة البشرية** للإمداد والتموين
/// (أفرادٌ ببياناتهم وحالاتهم المؤرخة)، **مالية الإمداد** (العهد والإخلاءات
/// وعقود المشتريات)، **تسليح الإمداد**. والترابط كله بمعرّف الفرد
/// ([LinkPersons.id]) مع **لقطة اسمٍ ورقمٍ عسكري** في كل سجلٍ مرتبط — فتبقى
/// القائمة مقروءةً حتى لو حُذف الفرد أو تغيّر اسمه، والمعرّف هو صلة الفتح
/// لملفه من المكانين.

/// فردٌ في القوة البشرية للإمداد والتموين.
class LinkPersons extends Table {
  /// معرّف فريد — `Ids.next('lp')`.
  TextColumn get id => text()();

  /// الاسم الكامل.
  TextColumn get fullName => text()();

  /// الرقم العسكري — المعرّف المؤسسي للفرد في كل الارتباطات.
  TextColumn get militaryNo => text().withDefault(const Constant(''))();

  /// الرتبة (اختيارية).
  TextColumn get rank => text().withDefault(const Constant(''))();

  /// الهاتف الأساسي.
  TextColumn get phone => text().withDefault(const Constant(''))();

  /// هاتف آخر (اختياري).
  TextColumn get phone2 => text().withDefault(const Constant(''))();

  /// الصورة الشخصية — نسخةٌ داخل بيانات التطبيق باسم معرّف الفرد.
  TextColumn get photoPath => text().withDefault(const Constant(''))();

  /// الوحدة الفرعية: إمداد / محروقات / مياه (قابلة للتوسيع من الدليل).
  TextColumn get subUnit => text().withDefault(const Constant(''))();

  /// المعسكر التابع له — من دليل المستودعات (فهي المعسكرات في هذا النظام).
  TextColumn get camp => text().withDefault(const Constant(''))();

  /// القسم: مخزن / مطبخ / فرن / سائق / مكتب / مختص (قابل للإضافة).
  TextColumn get section => text().withDefault(const Constant(''))();

  /// العمل: معلم أرز / معلم مشكل / معلم شواية / معلم خباز / معلم عجان…
  TextColumn get job => text().withDefault(const Constant(''))();

  /// الحالة الحالية — مفاتيحها في [LinkStatus] بالمستودع.
  TextColumn get status => text().withDefault(const Constant('present'))();

  /// بداية الحالة (YYYY-MM-DD) — للحالات ذات المدى.
  TextColumn get statusFrom => text().withDefault(const Constant(''))();

  /// نهاية الحالة (YYYY-MM-DD) — فراغها يعني «مستمرة حتى إشعار».
  TextColumn get statusTo => text().withDefault(const Constant(''))();

  /// عدد أيام الحالة — يُحسب من التاريخين ويُحفظ ليُعرض بلا إعادة حساب.
  IntColumn get statusDays => integer().withDefault(const Constant(0))();

  /// ملاحظات حرة.
  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// سجل الحالات — سطرٌ لكل تغيير حالةٍ أو عودة: به يُعرف تاريخُ الفرد
/// (متى فرار ومتى عاد، كم يومَ إجازةً أخذ، وما الإجراء عند عودته).
class LinkStatusLogs extends Table {
  TextColumn get id => text()();

  /// صلة الفرد.
  TextColumn get personId => text()();

  /// لقطة الاسم لحظة التغيير — يبقى السجل مفهومًا ولو غيّر الفرد اسمه لاحقًا.
  TextColumn get personName => text().withDefault(const Constant(''))();

  /// الحالة (مفتاح [LinkStatus]).
  TextColumn get status => text()();

  /// من تاريخ / إلى تاريخ.
  TextColumn get fromDate => text().withDefault(const Constant(''))();
  TextColumn get toDate => text().withDefault(const Constant(''))();

  /// عدد الأيام المحسوبة.
  IntColumn get days => integer().withDefault(const Constant(0))();

  /// إجراء العودة: «مواصلة عمل» أو «مباشرة عمل» — يُسجَّل في سطر العودة.
  TextColumn get returnAction => text().withDefault(const Constant(''))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get actor => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// دليل المسميات: الأقسام والأعمال والوحدات الفرعية — تُضاف إليه القيم
/// الجديدة تلقائيًّا عند حفظ فردٍ بقيمةٍ لم تُسبق، ويُدار (حذف) من شاشته.
class LinkTerms extends Table {
  /// النوع: `section` (قسم) | `job` (عمل) | `subunit` (وحدة فرعية) | `holder` (جهة مسؤولة عن عهدة).
  TextColumn get kind => text()();

  /// المسمى نفسه.
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {kind, name};
}

/// العهد — مالية الإمداد. العهدة تخصّ **جهةً مسؤولة** (قسم/مطبخ/مستودع/مكتب…)
/// لا فردًا من القوة البشرية، وتُغلق بإخلاءٍ مسجَّل في [LinkClearances].
class LinkFinCustodies extends Table {
  TextColumn get id => text()();

  /// رقم العهدة الرسمي.
  TextColumn get custodyNo => text().withDefault(const Constant(''))();

  /// الجهة المسؤولة عن العهدة (نص حر مع اقتراحات من دليل المسميات).
  TextColumn get holder => text().withDefault(const Constant(''))();

  /// بيان العهدة.
  TextColumn get title => text()();

  TextColumn get serialNo => text().withDefault(const Constant(''))();

  RealColumn get qty => real().withDefault(const Constant(1))();
  TextColumn get unit => text().withDefault(const Constant(''))();

  /// القيمة المالية للعهدة.
  RealColumn get valueAmount => real().withDefault(const Constant(0))();

  TextColumn get custodyDate => text().withDefault(const Constant(''))();

  /// آخر أجل للإخلاء.
  TextColumn get dueDate => text().withDefault(const Constant(''))();

  /// تُضبط عند تسجيل إخلاءٍ للعهدة وتُصفَّر عند حذفه.
  BoolColumn get cleared => boolean().withDefault(const Constant(false))();
  TextColumn get clearedDate => text().withDefault(const Constant(''))();
  TextColumn get clearanceNotes => text().withDefault(const Constant(''))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// الإخلاءات — إغلاقٌ ماليٌّ لعهدةٍ أو عقد (أو إخلاءٌ حر)، بتاريخه وبيانه.
class LinkClearances extends Table {
  TextColumn get id => text()();

  /// رقم الإخلاء.
  TextColumn get clearanceNo => text().withDefault(const Constant(''))();

  /// `custody` عهدة | `contract` عقد | `other` حر.
  TextColumn get kind => text().withDefault(const Constant('custody'))();

  /// معرّف العهدة أو العقد المُخلى (فارغ للإخلاء الحر).
  TextColumn get refId => text().withDefault(const Constant(''))();

  /// لقطة بيان المرجع — تبقى مقروءة ولو حُذف المرجع.
  TextColumn get refTitle => text().withDefault(const Constant(''))();

  /// الجهة المُخلى طرفها (المسؤول عن العهدة / المورد).
  TextColumn get partyName => text().withDefault(const Constant(''))();

  /// المبلغ المسوّى.
  RealColumn get amount => real().withDefault(const Constant(0))();

  TextColumn get clearanceDate => text().withDefault(const Constant(''))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// عقد شراء — «قائمة الكمية المستهلكة» بفواتير التاجر. الأصناف نصٌّ حرّ
/// ([itemsJson]) لا صلة له بأصناف النظام لأن مسمياتها عند التجار تختلف.
class LinkPurchaseContracts extends Table {
  TextColumn get id => text()();

  TextColumn get contractNo => text().withDefault(const Constant(''))();

  /// التصنيف: «مواد غذائية» أو «بهارات» أو أي مسمى.
  TextColumn get title => text()();

  /// اسم المحل أو التاجر.
  TextColumn get supplier => text().withDefault(const Constant(''))();

  /// عملة الفاتورة: `sar` سعودي | `yer` يمني.
  TextColumn get currency => text().withDefault(const Constant('sar'))();

  /// سعر الصرف (ريال يمني لكل ريال سعودي) — يُستعمل عند العملة اليمنية فقط.
  RealColumn get exchangeRate => real().withDefault(const Constant(0))();

  /// «قائمة الكمية المستهلكة بتاريخ» — يُدخل يدويًا حسب تاريخ الفاتورة.
  TextColumn get listDate => text().withDefault(const Constant(''))();

  /// أسطر الأصناف JSON: `[{"name","unit","qty","price","total","invoiceNo","date","note"}]`.
  TextColumn get itemsJson => text().withDefault(const Constant('[]'))();

  /// إجمالي القائمة بعملة الفاتورة (محسوب عند الحفظ).
  RealColumn get amount => real().withDefault(const Constant(0))();

  /// تاريخ انتهاء اختياري — للتنبيه عند التأخر.
  TextColumn get endDate => text().withDefault(const Constant(''))();

  TextColumn get status => text().withDefault(const Constant('open'))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// مسير عهدة — كشف حسابٍ لعهدةٍ تشغيلية (العهدة والمنصرف والمرتجع والمتبقي)
/// بتنسيق ملف Excel المعتمد. أسطره في [LinkCustodySheetRows].
class LinkCustodySheets extends Table {
  TextColumn get id => text()();

  /// رقم العهدة التشغيلية: «2» أو «2 ورقم 3».
  TextColumn get sheetNo => text().withDefault(const Constant(''))();

  /// عنوان المسير للتعريف به في القائمة.
  TextColumn get title => text().withDefault(const Constant(''))();

  /// سعر الصرف الافتراضي للأسطر الجديدة.
  RealColumn get defaultRate => real().withDefault(const Constant(410))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// سطر في مسير العهدة. الأعمدة بترتيب ملف Excel.
class LinkCustodySheetRows extends Table {
  TextColumn get id => text()();

  TextColumn get sheetId => text()();

  /// ترتيب السطر في المسير.
  IntColumn get seq => integer().withDefault(const Constant(0))();

  /// التاريخ (YYYY-MM-DD) — يدوي.
  TextColumn get date => text().withDefault(const Constant(''))();

  /// مبلغ العهدة (سعودي).
  RealColumn get grantSar => real().withDefault(const Constant(0))();

  /// المرتجع.
  RealColumn get returnSar => real().withDefault(const Constant(0))();
  RealColumn get returnYer => real().withDefault(const Constant(0))();

  /// المبلغ المنصرف — إدخال اليمني يحسب السعودي = اليمني ÷ سعر الصرف.
  RealColumn get spentSar => real().withDefault(const Constant(0))();
  RealColumn get spentYer => real().withDefault(const Constant(0))();

  RealColumn get rate => real().withDefault(const Constant(410))();

  /// الاسم (المستلم أو الأجير…).
  TextColumn get person => text().withDefault(const Constant(''))();

  /// البيان.
  TextColumn get statement => text().withDefault(const Constant(''))();

  /// الفئة (أصول ثابتة، صيانة، أجور…).
  TextColumn get category => text().withDefault(const Constant(''))();

  /// رقم القيد.
  TextColumn get entryNo => text().withDefault(const Constant(''))();

  /// رقم الفاتورة — تكراره يُلوَّن.
  TextColumn get invoiceNo => text().withDefault(const Constant(''))();

  /// اسم المحل.
  TextColumn get shop => text().withDefault(const Constant(''))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// سلاحٌ سُلّم لفردٍ من تسليح الإمداد — يُردَّع بتاريخه.
class LinkArmaments extends Table {
  TextColumn get id => text()();

  /// الارتباط بالفرد — صلةٌ ولقطة.
  TextColumn get personId => text().withDefault(const Constant(''))();
  TextColumn get personName => text().withDefault(const Constant(''))();
  TextColumn get personMilitaryNo => text().withDefault(const Constant(''))();

  /// نوع السلاح ورقمه المسلسل.
  TextColumn get weaponType => text().withDefault(const Constant(''))();
  TextColumn get serialNo => text().withDefault(const Constant(''))();

  /// الكمية (سلاحٌ واحد غالبًا).
  IntColumn get qty => integer().withDefault(const Constant(1))();

  /// تاريخ التسليم.
  TextColumn get assignedDate => text().withDefault(const Constant(''))();

  /// هل رُدِّع؟ وتاريخه.
  BoolColumn get returned => boolean().withDefault(const Constant(false))();
  TextColumn get returnedDate => text().withDefault(const Constant(''))();

  /// حالة السلاح عند التسليم.
  TextColumn get condition => text().withDefault(const Constant(''))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
