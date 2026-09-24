import 'package:drift/drift.dart';

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

/// إعدادات عامة (هوية الجهة، تخطيط الطباعة، إعدادات النماذج) بصيغة JSON
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
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
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          await _createIndexes();
          await SyncMarks.install(this);
          await SignaturesRepo.install(this);
          // شواهد الحذف تنمو بلا حد لو تُركت: تُنظَّف القديمة عند كل تشغيل.
          await SyncMarks(this).pruneTombstones();
        },
      );
}

QueryExecutor _open() => openConnection();
