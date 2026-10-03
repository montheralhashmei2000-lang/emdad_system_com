import 'package:drift/drift.dart';

/// جداول الأرشيف الإلكتروني — أُضيفت في إصدار المخطط v21.
///
/// **الملف نفسه لا يُخزَّن في القاعدة**: القاعدة تحفظ بياناته الوصفية وحدها،
/// ويليق الملف في مجلد الأرشيف التطبيقي (انظر [ArchiveRepo]) بنسخةٍ لا يلمسها
/// المستخدم، مع بصمة SHA-256 تكشف أيّ عبثٍ لاحق.
///
/// الوسوم قائمة JSON (`["سنوي","تعاقد"]`) — تُقرأ وتُكتب عبر [ArchiveRepo]
/// فلا تفتح أي شاشة ترميز JSON بنفسها.

/// ملفٌ مؤرشف: سندٌ ممحوح، عقدٌ ممسوح ضوئيًّا، كشفٌ مصوَّر…
class ArchiveFiles extends Table {
  /// معرّف فريد — `Ids.next('ar')`.
  TextColumn get id => text()();

  /// مساحة العمل المالكة للملف: `supply` أو `fuel` — تمهيدًا لتعصيب
  /// أرشيف كل قسمٍ على أهله.
  TextColumn get space => text().withDefault(const Constant('supply'))();

  /// عنوان المستند كما يظهر في القائمة (لا اسم الملف).
  TextColumn get title => text()();

  /// التصنيف (عقود، كشوفات، مراسلات…) — نصٌّ حرّ يقترح عليه الموجود.
  TextColumn get category => text().withDefault(const Constant('عام'))();

  /// وسوم البحث — قائمة JSON نصية.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// رقم السند المرتبط في سجل المستندات، إن وُجد — يفتح العرضُ من الأرشيف
  /// طريقه إلى السند نفسه.
  TextColumn get docRef => text().withDefault(const Constant(''))();

  /// المستودع المتعلق — يُقيَّد بنطاق صلاحيات المستخدم.
  TextColumn get warehouse => text().withDefault(const Constant(''))();

  /// تاريخ المستند الوثائقي (YYYY-MM-DD) — قد يسبق تاريخ الأرشفة سنوات.
  TextColumn get docDate => text().withDefault(const Constant(''))();

  /// الاسم الأصلي للملف كما وُلد على الجهاز.
  TextColumn get fileName => text()();

  /// المسار المطلق للنسخة المخزَّنة داخل مجلد الأرشيف.
  TextColumn get storedPath => text()();

  /// نوع MIME — لاختيار المعاينة (صورة/PDF/أخرى).
  TextColumn get mime => text().withDefault(const Constant(''))();

  /// حجم الملف بالبايت.
  IntColumn get sizeBytes => integer()();

  /// بصمة SHA-256 لمحتوى الملف الأصلي — تُحسب لحظة الأرشفة.
  TextColumn get sha256 => text().withDefault(const Constant(''))();

  /// مصدر الأرشفة: `manual` (يدوي من الشاشة) أو `auto` (تلقائي عند الطباعة
  /// بعد تفعيل العملية من إعدادات الأرشفة التلقائية).
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// نوع العملية في الأرشفة التلقائية — receipt / issue / transfer / return /
  /// rationOrder / stocktake / report — فارغٌ في الأرشفة اليدوية.
  TextColumn get opType => text().withDefault(const Constant(''))();

  /// ملاحظات حرة.
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// تثبيت في أعلى القائمة.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// من أرشفه (بريد حسابه) — فارغٌ في التلقائي فيُعرض «تلقائي».
  TextColumn get createdBy => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
