import 'package:drift/drift.dart';

import '../../core/error_log.dart';
import '../../core/security/device_activation.dart';
import '../../core/security/owner_promotion.dart';
import '../repos/audit_repo.dart';
import '../repos/signatures_repo.dart';
import '../sync/sync_marks.dart';
import 'connection/connection.dart';
import 'pre_migration_backup.dart';

import 'archive_tables.dart';
import 'cable_tables.dart';
import 'linkage_tables.dart';

export 'tables/core_tables.dart';
export 'tables/movement_tables.dart';
export 'tables/stocktake_tables.dart';
export 'tables/asset_tables.dart';
export 'tables/fuel_tables.dart';
export 'tables/daily_tables.dart';
export 'tables/ration_tables.dart';
import 'tables/core_tables.dart';
import 'tables/movement_tables.dart';
import 'tables/stocktake_tables.dart';
import 'tables/asset_tables.dart';
import 'tables/fuel_tables.dart';
import 'tables/daily_tables.dart';
import 'tables/ration_tables.dart';

part 'app_database.g.dart';

/// مخطط قاعدة البيانات المحلية (SQLite عبر Drift):
/// users, items, categories, warehouses, suppliers, units, facilities,
/// receipts, issues, transfers, returns, openingBalances, strengths,
/// kitchenLogs, entitlements, stocktakes, stocktakeLines, auditLogs, appSettings.
/// كل جدول حركة يحفظ سطرًا لكل صنف مع بيانات السند.


@DriftDatabase(tables: [
  FuelWarehouses,
  FuelUnits,
  FuelSettingsRows,
  FuelAllocations,
  FuelIssues,
  FuelSupplies,
  FuelOpenings,
  FuelTransfers,
  FuelStocktakes,
  FuelStocktakeLines,
  SupplyAuthorities,
  WarehouseStockLimits,
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
  Assets,
  AssetAssignments,
  RationOrders,
  RationOrderLines,
  MealPlans,
  MealPlanEntries,
  CampLedgers,
  CampStockLimits,
  MonthlySettlements,
  AppSettings,
  ArchiveFiles,
  LinkPersons,
  LinkStatusLogs,
  LinkTerms,
  LinkFinCustodies,
  LinkClearances,
  LinkPurchaseContracts,
  LinkCustodySheets,
  LinkCustodySheetRows,
  LinkArmaments,
  LinkMoneyReceipts,
  LinkFinanceLedger,
  Cables,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  /// إصدار المخطط الحالي. ثابتٌ ساكن لتقرأه طبقة الاتصال (النسخة الاحتياطية قبل
  /// الترحيل) قبل أن تُنشأ نسخةٌ من القاعدة.
  static const int kSchemaVersion = 26;

  @override
  int get schemaVersion => kSchemaVersion;

  /// الفهارس المخدومة فعليًا بالاستعلامات: البحث بالمرجع (فتح سند من سجل
  /// المستندات)، وبالحالة (الأوامر المعلقة والمسودات)، وبالمستودع والصنف
  /// (حساب الأرصدة)، وبالتاريخ (تقارير المدى).
  ///
  /// تُنشأ عند كل فتح بـ `IF NOT EXISTS` لا في ترقية بنسخة جديدة: العملية
  /// بلا تكلفة إذا كان الفهرس موجودًا، وتشمل قواعد البيانات القديمة كلها.
  Future<void> _createIndexes() async {
    const movementTables = [
      'receipts',
      'issues',
      'transfers',
      'returns',
      'adjustments'
    ];
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
      'CREATE INDEX IF NOT EXISTS ix_assets_type_status ON assets (asset_type, status)',
      'CREATE INDEX IF NOT EXISTS ix_assets_wh ON assets (warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_asset_assign_asset ON asset_assignments (asset_id)',
      'CREATE INDEX IF NOT EXISTS ix_ration_status ON ration_orders (status)',
      'CREATE INDEX IF NOT EXISTS ix_ration_wh ON ration_orders (requesting_warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_ration_lines_order ON ration_order_lines (order_id)',
      'CREATE INDEX IF NOT EXISTS ix_meal_plans_status ON meal_plans (status)',
      'CREATE INDEX IF NOT EXISTS ix_meal_entries_plan ON meal_plan_entries (plan_id, entry_date)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_camp_ledger ON camp_ledgers (camp_id, item_id, year, month)',
      'CREATE INDEX IF NOT EXISTS ix_camp_ledger_month ON camp_ledgers (year, month, status)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_camp_limit ON camp_stock_limits (camp_id, item_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_settlement_month ON monthly_settlements (year, month)',
      'CREATE INDEX IF NOT EXISTS ix_returns_unit ON returns (beneficiary_unit_id)',
      'CREATE INDEX IF NOT EXISTS ix_ration_kind ON ration_orders (order_kind, status)',
      'CREATE INDEX IF NOT EXISTS ix_ration_supply ON ration_orders (supplying_warehouse, status)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_wh_limit ON warehouse_stock_limits (warehouse_id, item_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_fuel_wh_name ON fuel_warehouses (name)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_fuel_unit_name ON fuel_units (name)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_issue_date ON fuel_issues (date)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_issue_alloc ON fuel_issues (allocation_id)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_issue_chassis ON fuel_issues (chassis_no)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_supply_date ON fuel_supplies (date)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_transfer_date ON fuel_transfers (date)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_alloc_unit ON fuel_allocations (unit_id, active)',
      'CREATE INDEX IF NOT EXISTS ix_fuel_stline_doc ON fuel_stocktake_lines (stocktake_id)',
      'CREATE INDEX IF NOT EXISTS ix_link_persons_status ON link_persons (status)',
      'CREATE INDEX IF NOT EXISTS ix_link_status_person ON link_status_logs (person_id)',
      'CREATE INDEX IF NOT EXISTS ix_link_custody_cleared ON link_fin_custodies (cleared)',
      'CREATE INDEX IF NOT EXISTS ix_link_clear_ref ON link_clearances (kind, ref_id)',
      'CREATE INDEX IF NOT EXISTS ix_link_contract_custody ON link_purchase_contracts (custody_id)',
      'CREATE INDEX IF NOT EXISTS ix_link_sheet_custody ON link_custody_sheets (custody_id)',
      'CREATE INDEX IF NOT EXISTS ix_link_ledger_party ON link_finance_ledger (party_name)',
      'CREATE INDEX IF NOT EXISTS ix_link_contracts_status ON link_purchase_contracts (status)',
      'CREATE INDEX IF NOT EXISTS ix_link_sheet_rows ON link_custody_sheet_rows (sheet_id, seq)',
      'CREATE INDEX IF NOT EXISTS ix_link_arm_person ON link_armaments (person_id)',
      'CREATE INDEX IF NOT EXISTS ix_archive_cat ON archive_files (category)',
      'CREATE INDEX IF NOT EXISTS ix_archive_date ON archive_files (doc_date)',
      'CREATE INDEX IF NOT EXISTS ix_archive_ref ON archive_files (doc_ref)',
      'CREATE INDEX IF NOT EXISTS ix_archive_wh ON archive_files (warehouse)',
      'CREATE INDEX IF NOT EXISTS ix_archive_op_ref ON archive_files (op_type, doc_ref)',
      'CREATE INDEX IF NOT EXISTS ix_cables_date ON cables (cable_date)',
      'CREATE INDEX IF NOT EXISTS ix_cables_dir ON cables (direction)',
      'CREATE INDEX IF NOT EXISTS ix_cables_status ON cables (status)',
      'CREATE INDEX IF NOT EXISTS ix_cables_class ON cables (classification)',
    ];
    for (final sql in statements) {
      await customStatement(sql);
    }
  }

  /// الجداول التي تحمل كميات الأصناف، وأعمدة الكمية في كل منها.
  static const Map<String, List<String>> _quantityColumns = {
    'receipts': ['qty', 'base_qty'],
    'issues': ['qty', 'base_qty'],
    'transfers': ['qty', 'base_qty'],
    'returns': ['qty', 'base_qty'],
    'adjustments': ['qty', 'base_qty'],
    'opening_balances': ['qty'],
  };

  /// جداول الحركات التي يُمنع فيها السالب (التسويات مستثناة: فرق الجرد سالب بطبيعته).
  static const List<String> _nonNegativeTables = ['receipts', 'issues', 'transfers', 'returns', 'opening_balances'];

  /// شرط SQL: للصنف [itemIdSql] أي حركة مسجَّلة (يصلح بعد `WHERE`).
  static String itemHasMovementsSql(String itemIdSql) => [
        for (final t in _quantityColumns.keys) 'EXISTS (SELECT 1 FROM "$t" WHERE item_id = $itemIdSql)',
      ].join(' OR ');

  /// الكميات تُخزَّن بثلاث خانات عشرية بالضبط.
  static const int quantityScale = 3;

  /// حواجز سلامة الكميات في القاعدة نفسها، أيًّا كان المسار الذي كتب (واجهة أو
  /// مزامنة أو استيراد):
  ///
  /// 1. **لا سالب**: كمية أو معامل تحويل سالب في الوارد والصرف والتحويل والمرتجع
  ///    والرصيد الافتتاحي يُرفض.
  /// 2. **تقريب إلى [quantityScale] خانات**: الأعمدة `REAL` فيراكم جمعها كسورًا
  ///    عائمة (٠٫١+٠٫٢). أي قيمة تُكتب بأكثر من ثلاث خانات تُقرَّب فور كتابتها،
  ///    فلا يدخل القاعدة إلا ما يمثّله الرقم العشري بدقة.
  /// 3. **لا حذف لصنف له حركات**: تبقى سطور الحركات يتيمةً فتضيع أرصدتها.
  ///
  /// مشغّلات لا `CHECK` ولا `FOREIGN KEY`: إضافتهما لجدول قائم في SQLite تعني
  /// إعادة بنائه، وهي تُسقط مشغّلات المزامنة والتوقيع المعلّقة عليه. والمشغّل يُنشأ
  /// بـ `IF NOT EXISTS` عند كل فتح فيشمل القواعد القديمة بلا ترقية مخطط.
  ///
  /// ولا مفتاح أجنبي على `item_id` في الحركات عمدًا: الاستعادة من نسخة قديمة قد
  /// تحمل حركاتٍ بأصناف سبق حذفها، ومنعها يفقد بياناتٍ لا تُستعاد. اليتامى القائمة
  /// يكشفها فحص السلامة (`orphanMoves`) لا المنع.
  Future<void> _createQuantityGuards() async {
    for (final t in _nonNegativeTables) {
      final cols = _quantityColumns[t]!;
      final negative = [
        for (final c in cols) 'NEW.$c < 0',
        if (t != 'opening_balances') 'NEW.factor < 0',
      ].join(' OR ');
      for (final event in const ['INSERT', 'UPDATE']) {
        await customStatement('''
          CREATE TRIGGER IF NOT EXISTS tg_${t}_${event.toLowerCase()}_qty_guard
          BEFORE $event ON "$t"
          WHEN $negative
          BEGIN
            SELECT RAISE(ABORT, 'كمية أو معامل تحويل سالب في $t');
          END
        ''');
      }
    }

    for (final entry in _quantityColumns.entries) {
      final t = entry.key;
      final needs = [for (final c in entry.value) 'NEW.$c <> ROUND(NEW.$c, $quantityScale)'].join(' OR ');
      final set = [for (final c in entry.value) '$c = ROUND($c, $quantityScale)'].join(', ');
      for (final event in const ['INSERT', 'UPDATE']) {
        // الشرط يمنع التكرار: بعد التقريب لا يصدق، فلا يُعاد تنفيذ المشغّل.
        await customStatement('''
          CREATE TRIGGER IF NOT EXISTS tg_${t}_${event.toLowerCase()}_qty_round
          AFTER $event ON "$t"
          WHEN $needs
          BEGIN
            UPDATE "$t" SET $set WHERE rowid = NEW.rowid;
          END
        ''');
      }
    }

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tg_items_delete_guard
      BEFORE DELETE ON items
      WHEN ${itemHasMovementsSql('OLD.id')}
      BEGIN
        SELECT RAISE(ABORT, 'لا يُحذف صنف له حركات');
      END
    ''');
  }

  /// أسماء أعمدة جدول قائم.
  Future<Set<String>> _columnsOf(String table) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return {for (final r in rows) r.data['name'] as String};
  }

  /// يضيف العمود إن لم يكن موجودًا.
  ///
  /// الترحيل لا بد أن يحتمل قاعدةً سبقت طابَعها: جهازٌ فتح نسخةً أحدث ثم
  /// فُتحت عليه نسخةٌ أقدم يُخفَّض طابَعُه وتبقى أعمدته. فإذا رُقّي بعدها
  /// أعاد الترحيل إضافةَ عمودٍ قائم، فتُرمى `duplicate column name` **أثناء
  /// فتح القاعدة** — أي أن التطبيق لا يفتح أصلًا ولا يعرض خطأً مفهومًا،
  /// ولا سبيل للمستخدم إلى إصلاحه من داخله.
  ///
  /// وهذا ليس فرضًا نظريًّا: وقع فعلًا عند تبادل نسختين في يوم واحد.
  Future<void> _addCol(
      Migrator m, TableInfo<Table, dynamic> t, GeneratedColumn c) async {
    if ((await _columnsOf(t.actualTableName)).contains(c.name)) return;
    await m.addColumn(t, c);
  }

  /// ينشئ الجدول إن لم يكن موجودًا — للسبب نفسه.
  Future<void> _createIfMissing(Migrator m, TableInfo<Table, dynamic> t) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(t.actualTableName)],
    ).get();
    if (rows.isNotEmpty) return;
    await m.createTable(t);
  }

  /// يضمن أن كل جدول وعمود يصفه المخطط موجودٌ فعلًا في القاعدة.
  ///
  /// بوابات `if (from < N)` تكفي قاعدةً تدرّجت في إصداراتها بالترتيب. لكن
  /// قاعدةً فُتحت عليها نسختان مختلفتا المخطط يُخفَّض طابَعُها ثم يُرفع، فتمرّ
  /// البوابةُ **وهي لم تُنفَّذ قط**: يصير الطابَع 15 وفي الجدول عمودٌ ناقص.
  /// وقتها لا يسقط الفتح بل تسقط أول قراءة، فيبدو العطل في الشاشة.
  ///
  /// ولذلك لا يُعتمد على الطابَع وحده: يُقارَن المخطط بالواقع عند كل فتح.
  /// ثمنُه استعلامٌ خفيف لكل جدول، وعائدُه أن انحرافًا كهذا يُصلَح نفسه بدل
  /// أن يترك التطبيق لا يفتح.
  Future<int> _ensureSchema() async {
    final m = createMigrator();
    var added = 0;
    for (final table in allTables) {
      await _createIfMissing(m, table);
      final present = await _columnsOf(table.actualTableName);
      for (final col in table.$columns) {
        if (present.contains(col.name)) continue;
        // عمودٌ بلا افتراضٍ ولا قبولٍ للفراغ لا يُضاف إلى جدولٍ فيه سطور:
        // SQLite ترفضه، وإضافته قسرًا تفسد أكثر مما تصلح.
        if (col.defaultValue == null && !col.$nullable) continue;
        await m.addColumn(table, col);
        added++;
      }
    }
    return added;
  }

  /// ترقية المالك بعد الانتقال إلى v25: القاعدة نفسها التي تجري عند الدخول
  /// ([OwnerPromotion.run])، تُستدعى هنا لتحدث عند أول فتحٍ بعد التحديث لا عند
  /// أول دخول فقط. جهاز الفرع لا يُرقّي (يصله المالك بالمزامنة).
  ///
  /// لا تُفشل الفتح أبدًا: تعذّرها يُسجَّل، وتُعاد عند الدخول التالي.
  Future<void> _promoteOwnerAfterUpgrade() async {
    try {
      final branch = await DeviceActivation(this).isBranch();
      await OwnerPromotion.run(this, isBranchDevice: branch);
    } catch (err, stack) {
      ErrorLogger.log('migration.v25.ownerPromotion', err, stack);
    }
  }

  /// ترحيل العهد القديمة إلى النموذج المالي الجديد دون حذف شيء:
  /// الحالة من `cleared`، والمبلغ من `value_amount`، والجهة المسؤولة تصير
  /// «مستلِمًا» لعهدة مسلَّمة (العهد القديمة كانت تُسلَّم لجهات).
  /// يُستدعى عند أول فتح بعد v24؛ عامٌّ ليُختبر.
  Future<void> backfillFinance() async {
    await customStatement("UPDATE link_fin_custodies SET status = 'cleared' WHERE cleared = 1");
    await customStatement('UPDATE link_fin_custodies SET amount = value_amount WHERE amount = 0 AND value_amount > 0');
    await customStatement(
        "UPDATE link_fin_custodies SET kind = 'delivered', receiver_name = holder WHERE holder <> '' AND receiver_name = ''");
  }

  /// يملأ القيم الفارغة في أعمدةٍ لا تقبل الفراغ.
  ///
  /// قاعدةٌ تنقّلت بين نسختين مختلفتي المخطط قد تحمل `NULL` في عمودٍ يصفه
  /// المخطط الحالي `NOT NULL`. وقتها لا يسقط الاستعلام بل **يسقط تحويل
  /// السطر إلى كائن** عند أول قراءة — فيبدو العطل في الشاشة لا في القاعدة،
  /// ويعجز المستخدم عن بلوغ أي زرّ لإصلاحه.
  ///
  /// والإصلاح يضع القيمة الافتراضية التي يصفها المخطط نفسه: فراغٌ للنص
  /// وصفرٌ للرقم. ولا يضيع شيء — `NULL` هنا غيابُ قيمةٍ لا قيمةٌ ذات معنى.
  Future<int> _repairNulls() async {
    var fixed = 0;
    for (final table in allTables) {
      final name = table.actualTableName;
      final present = await _columnsOf(name);
      for (final col in table.$columns) {
        if (col.$nullable || !present.contains(col.name)) continue;
        final fallback = switch (col.type) {
          DriftSqlType.string => "''",
          DriftSqlType.bool => '0',
          DriftSqlType.int || DriftSqlType.bigInt || DriftSqlType.double => '0',
          _ => null,
        };
        if (fallback == null) continue;
        await customStatement(
          'UPDATE "$name" SET "${col.name}" = $fallback '
          'WHERE "${col.name}" IS NULL',
        );
        fixed += await customSelect('SELECT changes() AS c')
            .getSingle()
            .then((r) => r.data['c'] as int);
      }
    }
    return fixed;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: حقول الموردين وسجل التدقيق.
          if (from < 2) {
            await _addCol(m, suppliers, suppliers.contact);
            await _addCol(m, suppliers, suppliers.city);
            await _addCol(m, beneficiaryUnits, beneficiaryUnits.category);
            await _addCol(m, issues, issues.approvedBy);
            await _addCol(m, issues, issues.rejectReason);
            await _addCol(m, issues, issues.rejectedBy);
            await _addCol(m, issues, issues.cylinderAction);
            await _addCol(m, issues, issues.officerCount);
            await _addCol(m, receipts, receipts.supervision);
            await _addCol(m, receipts, receipts.audit);
            await _addCol(m, receipts, receipts.cylinderAction);
            for (final col in [
              receipts.editedBy,
              receipts.cancelReason,
              receipts.cancelledBy,
              receipts.prevStatus,
            ]) {
              await _addCol(m, receipts, col);
            }
            for (final col in [
              issues.editedBy,
              issues.cancelReason,
              issues.cancelledBy,
              issues.prevStatus,
            ]) {
              await _addCol(m, issues, col);
            }
            for (final col in [
              transfers.editedBy,
              transfers.cancelReason,
              transfers.cancelledBy,
              transfers.prevStatus,
            ]) {
              await _addCol(m, transfers, col);
            }
            for (final col in [
              returns.editedBy,
              returns.cancelReason,
              returns.cancelledBy,
              returns.prevStatus,
            ]) {
              await _addCol(m, returns, col);
            }
            for (final col in [
              adjustments.editedBy,
              adjustments.cancelReason,
              adjustments.cancelledBy,
              adjustments.prevStatus,
            ]) {
              await _addCol(m, adjustments, col);
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
              await _addCol(m, auditLogs, col);
            }
          }
          // v3: ملاحظة المقرر في شاشة نسب الاستهلاك.
          if (from < 3) {
            await _addCol(m, entitlements, entitlements.notes);
          }
          // v5: جدول مراجعة الأحداث الحساسة.
          if (from < 5) {
            await _createIfMissing(m, sensitiveReviews);
          }
          // v7: وحدة العرض الافتراضية في بطاقة الصنف.
          if (from < 7) {
            await _addCol(m, items, items.reportUnit);
          }
          // v6: ربط الوحدة بأكثر من منشأة (مطبخ وفرن معًا).
          if (from < 6) {
            await _addCol(m, beneficiaryUnits, beneficiaryUnits.facilityIds);
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
              await _addCol(m, stocktakes, col);
            }
          }
          // v8: الأصول الثابتة وعهدها، وطلبيات الإعاشة وسطورها.
          if (from < 8) {
            await _createIfMissing(m, assets);
            await _createIfMissing(m, assetAssignments);
            await _createIfMissing(m, rationOrders);
            await _createIfMissing(m, rationOrderLines);
          }
          // v9: خطط الوجبات ومدخلاتها.
          if (from < 9) {
            await _createIfMissing(m, mealPlans);
            await _createIfMissing(m, mealPlanEntries);
          }
          // v10: سجل حساب المعسكرات وحدود مخزونها وأرشيف التصفيات.
          if (from < 10) {
            await _addCol(m, warehouses, warehouses.isMain);
            await _createIfMissing(m, campLedgers);
            await _createIfMissing(m, campStockLimits);
            await _createIfMissing(m, monthlySettlements);
          }
          // v11: ربط المرتجع بوحدته بالمعرّف لا بالاسم.
          if (from < 11) {
            await _addCol(m, returns, returns.beneficiaryUnitId);
            await _addCol(m, returns, returns.beneficiaryUnitName);
          }
          // v12: صلاحية دفعات الوارد لتنبيهات قرب الانتهاء.
          if (from < 12) {
            await _addCol(m, receipts, receipts.expiryDate);
          }
          // v13: حالة الأسطوانات (ممتلئة/فارغة) في التحويلات والمرتجعات.
          if (from < 13) {
            await _addCol(m, transfers, transfers.cylinderAction);
            await _addCol(m, returns, returns.cylinderAction);
          }
          // v14: نوع الطلبية وجهتها ومستند تنفيذها.
          //
          // بُني هذا الترحيل رقمًا 12 قبل أن يُدمج عمل الأسطوانات وصلاحية
          // الدفعات، وكان الرقم 12 مأخوذًا فيهما. ورقمان مختلفان لإصدارٍ
          // واحد يعني أن جهازًا ترقّى بأحدهما يتخطّى الآخر صامتًا — فيفتح
          // النظامُ قاعدةً ينقصها جدول، ويسقط عند أول طلبية. فأُعيد ترقيمه
          // هنا فوق ما استقر.
          if (from < 14) {
            await _createIfMissing(m, supplyAuthorities);
            await _addCol(m, rationOrders, rationOrders.orderKind);
            await _addCol(m, rationOrders, rationOrders.authorityId);
            await _addCol(m, rationOrders, rationOrders.authorityName);
            await _addCol(m, rationOrders, rationOrders.fulfillRef);
            await _addCol(m, rationOrders, rationOrders.fulfillKind);
            await _addCol(m, rationOrders, rationOrders.fulfillDate);
            // الطلبيات المستلمة قبل هذا الإصدار وُلِّد لها سند استلام فعلًا،
            // فيُنقل مرجعه إلى حقل التنفيذ حتى لا تبدو بلا أثر.
            await customStatement(
              "UPDATE ration_orders SET fulfill_ref = receipt_ref, "
              "fulfill_kind = 'RECEIPT' WHERE receipt_ref <> ''",
            );
          }
          // v16: كمية الأصل، وحدود المخزون بالمستودع لا بالمعسكر.
          if (from < 16) {
            await _addCol(m, assets, assets.quantity);
            await _createIfMissing(m, warehouseStockLimits);
          }
          // v17: قسم المحروقات — جداوله وسعة المستودع منها.
          if (from < 17) {
            await _addCol(m, warehouses, warehouses.fuelCapacityLiters);
            // النوع مذكور صراحةً: قائمةٌ من جداول مولَّدة مختلفة تُستنتج
            // `List<Table>` فلا تقبلها `_createIfMissing`.
            for (final t in <TableInfo<Table, dynamic>>[
              fuelAllocations,
              fuelIssues,
              fuelSupplies,
              fuelOpenings,
              fuelTransfers,
              fuelStocktakes,
              fuelStocktakeLines,
            ]) {
              await _createIfMissing(m, t);
            }
          }
          // v18: فصل قسم المحروقات — دليلا مستودعاته ووحداته وإعداداته.
          if (from < 18) {
            for (final t in <TableInfo<Table, dynamic>>[
              fuelWarehouses,
              fuelUnits,
              fuelSettingsRows,
            ]) {
              await _createIfMissing(m, t);
            }
            // ما كان يستعمل دليل الإعاشة يُنسخ إلى دليله الجديد بمعرّفه
            // نفسه: السندات تشير إلى **الاسم**، فلو أُنشئ معرّف جديد بقيت
            // السندات معلّقة باسمٍ لا صفَّ له في الدليل.
            await customStatement(
              'INSERT OR IGNORE INTO fuel_warehouses '
              '(id, code, name, manager, location, capacity_liters, active, notes) '
              'SELECT id, code, name, manager, location, fuel_capacity_liters, 1, notes '
              'FROM warehouses WHERE fuel_capacity_liters > 0 '
              'OR name IN (SELECT warehouse FROM fuel_issues) '
              'OR name IN (SELECT warehouse FROM fuel_supplies) '
              'OR name IN (SELECT warehouse FROM fuel_openings) '
              'OR name IN (SELECT from_warehouse FROM fuel_transfers) '
              'OR name IN (SELECT to_warehouse FROM fuel_transfers) '
              'OR name IN (SELECT warehouse FROM fuel_stocktakes)',
            );
            await customStatement(
              'INSERT OR IGNORE INTO fuel_units (id, code, name, active) '
              'SELECT id, code, name, 1 FROM beneficiary_units '
              'WHERE id IN (SELECT unit_id FROM fuel_allocations)',
            );
          }
          // v19: ترويسة البرقية الرسمية في الإعدادات لا في الكود.
          if (from < 19) {
            for (final c in <GeneratedColumn>[
              fuelSettingsRows.parentOrg,
              fuelSettingsRows.agencyTitle,
              fuelSettingsRows.commandTitle,
              fuelSettingsRows.branchTitle,
              fuelSettingsRows.orgName,
              fuelSettingsRows.sealLines,
            ]) {
              await _addCol(m, fuelSettingsRows, c);
            }
          }
          // v20: عمل كل موقّعٍ في الإعدادات لا في الكود.
          if (from < 20) {
            for (final c in <GeneratedColumn>[
              fuelSettingsRows.roleOfficer,
              fuelSettingsRows.roleSupply,
              fuelSettingsRows.roleChief,
            ]) {
              await _addCol(m, fuelSettingsRows, c);
            }
          }
          // v21: الأرشيف الإلكتروني — جدول ملفاته الوصفية.
          if (from < 21) {
            await _createIfMissing(m, archiveFiles);
          }
          // v22: الارتباطات — القوة البشرية والمالية والتسليح.
          if (from < 22) {
            await _createIfMissing(m, linkPersons);
            await _createIfMissing(m, linkStatusLogs);
            await _createIfMissing(m, linkTerms);
            await _createIfMissing(m, linkFinCustodies);
            await _createIfMissing(m, linkClearances);
            await _createIfMissing(m, linkPurchaseContracts);
            await _createIfMissing(m, linkCustodySheets);
            await _createIfMissing(m, linkCustodySheetRows);
            await _createIfMissing(m, linkArmaments);
          }
          // v23: البرقيات.
          if (from < 23) {
            await _createIfMissing(m, cables);
          }
          // v24: النموذج المالي المتكامل — دفتر رصيد المالية (أعمدة العهد والإخلاء
          // والعقد والمسير الجديدة يضيفها _ensureSchema بقيمها الافتراضية).
          if (from < 24) {
            await _createIfMissing(m, linkFinanceLedger);
          }
          // v25: حجب الأقسام وتوقيع المالك على حساب المستخدم. الإضافة مشروطة بغياب
          // العمود: قاعدةٌ تنقّلت بين نسختين قد تحمله سلفًا، وإضافتُه ثانيةً ترمي
          // `duplicate column name` أثناء الفتح فلا يفتح التطبيق.
          if (from < 25) {
            final userCols = await _columnsOf('users');
            if (!userCols.contains('section_blocked')) await m.addColumn(users, users.sectionBlocked);
            if (!userCols.contains('owner_sig')) await m.addColumn(users, users.ownerSig);
          }
          // v26: سقف تراكم استحقاق المحروقات وما شُطب منه بالتصفير (H-6).
          if (from < 26) {
            await _addCol(m, fuelSettingsRows, fuelSettingsRows.carryCapPeriods);
            await _addCol(m, fuelAllocations, fuelAllocations.writtenOffLiters);
          }
          // v15: إصلاح ما خلّفه تنقّل القاعدة بين نسختين مختلفتي المخطط.
          //
          // يجري بعد كل ترقية لا في هذا الإصدار وحده: الانحراف قد يتكرر كلما
          // فُتحت نسخة أقدم على قاعدة أحدث، وثمنُ الفحص لحظةٌ عند الترقية
          // مقابل تطبيق لا يفتح.
          await _repairNulls();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          // المخطط يُطابَق بالواقع قبل أي شيء: الفهارس والملء الرجعي أدناه
          // تفترض أعمدةً موجودة، وهي قد لا تكون.
          // العهد قبل v24 بلا عمود الحالة: يُلتقط ذلك قبل إضافة الأعمدة ليُرحَّل مرةً واحدة.
          final custodyColsBefore = await _columnsOf('link_fin_custodies');
          final needFinanceBackfill = custodyColsBefore.isNotEmpty && !custodyColsBefore.contains('status');
          final healed = await _ensureSchema();
          if (needFinanceBackfill) await backfillFinance();
          if (healed > 0) await _repairNulls();
          await _createIndexes();
          await _createQuantityGuards();
          await SyncMarks.install(this);
          await SignaturesRepo.install(this);
          // شواهد الحذف تنمو بلا حد لو تُركت: تُنظَّف القديمة عند كل تشغيل.
          await SyncMarks(this).pruneTombstones();
          // وكذلك سجل التدقيق العادي — وعالي الخطورة يبقى.
          await AuditRepo(this).prune();
          // نسخة ما قبل الترحيل: تسجيل إنشائها بعد نجاح الفتح، وحذف المنقضية.
          await PreMigrationBackup.settle(this, schemaVersion: schemaVersion);
          // ترقية المالك: مرةً واحدةً بعد ترقيةٍ إلى v25 (المدير المحلي الوحيد ← مالك).
          final before = details.versionBefore;
          if (details.hadUpgrade && before != null && before < 25) await _promoteOwnerAfterUpgrade();
        },
      );
}


QueryExecutor _open() => openConnection();
