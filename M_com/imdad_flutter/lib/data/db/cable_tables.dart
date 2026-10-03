import 'package:drift/drift.dart';

/// جداول «البرقيات» — أُضيفت في إصدار المخطط v23.
///
/// برقية رسمية (واردة أو صادرة) بتصنيف ودرجة أولوية وحالة معالجة،
/// مع مرفق PDF اختياري يُخزَّن في مجلد `cables/` داخل بيانات التطبيق.

/// برقية رسمية بنموذج «برقية صادرة/واردة» المعتمد: الحقول المتغيرة تُكتب
/// بالإدخال اليدوي، وجسم البرقية نصٌّ حرّ.
class Cables extends Table {
  /// معرّف فريد — `Ids.next('cb')`.
  TextColumn get id => text()();

  /// الاتجاه: `in` واردة | `out` صادرة.
  TextColumn get direction => text().withDefault(const Constant('in'))();

  /// رقم البرقية الرسمي.
  TextColumn get cableNo => text().withDefault(const Constant(''))();

  /// تاريخ البرقية (YYYY-MM-DD).
  TextColumn get cableDate => text().withDefault(const Constant(''))();

  /// الموضوع.
  TextColumn get subject => text()();

  /// نص البرقية / الملخص.
  TextColumn get body => text().withDefault(const Constant(''))();

  /// الجهة المرسلة.
  TextColumn get fromParty => text().withDefault(const Constant(''))();

  /// الجهة المستلمة.
  TextColumn get toParty => text().withDefault(const Constant(''))();

  /// التصنيف: `normal` عادي | `secret` سري | `top` سري للغاية.
  TextColumn get classification => text().withDefault(const Constant('normal'))();

  /// الأولوية: `normal` عادي | `urgent` عاجل | `immediate` عاجل جدًا.
  TextColumn get priority => text().withDefault(const Constant('normal'))();

  /// الحالة: `new` جديد | `processing` قيد المعالجة | `replied` تم الرد | `archived` مؤرشف.
  TextColumn get status => text().withDefault(const Constant('new'))();

  /// ساعة إنشاء البرقية (HH:mm).
  TextColumn get cableTime => text().withDefault(const Constant(''))();

  /// نسخة إلى — أكثر من سطر، سطرٌ لكل جهة.
  TextColumn get ccParty => text().withDefault(const Constant(''))();

  /// جدول المرسَل إليهم (م / الاسم / الوحدة / ملاحظة) مُرمَّزًا JSON:
  /// `[{"name":"","unit":"","note":""}]` — الصفوف متغيرة العدد.
  TextColumn get recipientsJson => text().withDefault(const Constant('[]'))();

  /// ─── قسم «لاستعمال المركز / المكتب» (كله إدخالٌ يدوي) ───
  /// محرر البرقية.
  TextColumn get editorName => text().withDefault(const Constant(''))();
  TextColumn get editorRank => text().withDefault(const Constant(''))();
  TextColumn get editorJob => text().withDefault(const Constant(''))();

  /// تسلسل / نرس.
  TextColumn get serialNo => text().withDefault(const Constant(''))();

  /// وسيلة الإرسال.
  TextColumn get sendMethod => text().withDefault(const Constant(''))();

  /// وقت الإرسال والتاريخ.
  TextColumn get sendDateTime => text().withDefault(const Constant(''))();

  /// المختص.
  TextColumn get specialist => text().withDefault(const Constant(''))();

  /// الاستقبال: اسم المأمور ووقت الاستلام.
  TextColumn get receiverName => text().withDefault(const Constant(''))();
  TextColumn get receiveTime => text().withDefault(const Constant(''))();

  /// رقم برقية الرد (إن وُجد).
  TextColumn get replyToNo => text().withDefault(const Constant(''))();

  /// ─── مرفق PDF ───
  /// الاسم الأصلي للملف كما اختاره المستخدم.
  TextColumn get attachName => text().withDefault(const Constant(''))();

  /// المسار المطلق للنسخة المخزَّنة داخل مجلد cables/.
  TextColumn get attachPath => text().withDefault(const Constant(''))();

  /// حجم المرفق بالبايت.
  IntColumn get attachSize => integer().withDefault(const Constant(0))();

  /// بصمة SHA-256 لمحتوى المرفق.
  TextColumn get attachSha256 => text().withDefault(const Constant(''))();

  /// ملاحظات.
  TextColumn get notes => text().withDefault(const Constant(''))();

  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
