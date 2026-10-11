import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/security/pbkdf2.dart';
import '../../core/security/device_activation.dart';
import '../../core/security/owner_key.dart';
import '../../core/security/owner_signature.dart';
import '../../domain/section_block.dart';
import '../repos/audit_repo.dart';
import '../repos/movements_repo.dart';
import '../db/app_database.dart';
import '../repos/settings_repo.dart';
import 'backup_crypto.dart';
import '../sync/sync_marks.dart';
import '../../core/error_log.dart';

export 'legacy_import_result.dart';
import 'legacy_import_result.dart';

part 'legacy_import/base_part.dart';
part 'legacy_import/marks_part.dart';
part 'legacy_import/natural_keys_part.dart';
part 'legacy_import/users_part.dart';
part 'legacy_import/docs_part.dart';
part 'legacy_import/fuel_part.dart';
part 'legacy_import/camps_part.dart';
part 'legacy_import/catalog_part.dart';
part 'legacy_import/movements_part.dart';
part 'legacy_import/daily_part.dart';


class LegacyImporter
    with
        _LegacyBase,
        _LegacyMarks,
        _LegacyNaturalKeys,
        _LegacyUsers,
        _LegacyDocs,
        _LegacyFuel,
        _LegacyCamps,
        _LegacyCatalog,
        _LegacyMovements,
        _LegacyDaily {
  /// [ownerPublicKey] حقنٌ للاختبارات؛ الإنتاج يتحقق بالمفتاح المدفون ([OwnerKey]).
  LegacyImporter(this.db, {String? ownerPublicKey}) : _ownerKey = ownerPublicKey ?? OwnerKey.publicKey;

  @override
  final AppDatabase db;

  @override
  final String _ownerKey;

  /// يستورد ملف نسخة احتياطية، مشفَّرًا كان أو JSON عاديًا.
  ///
  /// [password] تلزم للملف المشفَّر فقط؛ وغيابها عنه يرمي [BackupError] برسالة
  /// صريحة بدل استيراد نصف ملف.
  ///
  /// **الاستعادة موثوقة:** يملكها المالك وحده (`sys.backup`) فلا يُشترط توقيعٌ على
  /// الأدوار والحجب في الملف — وإلا استحال استرجاع نسخةٍ قديمة بمديريها. ويُسجَّل
  /// `backup.restore` باسم الملف وعدد الحسابات وما تجاوزه الدمج أو رُفض.
  Future<LegacyImportResult> importFile(File file, {String password = '', String actorEmail = ''}) async {
    final bytes = await file.readAsBytes();
    final Map<String, dynamic> data;
    if (BackupCrypto.isEncrypted(bytes)) {
      if (password.isEmpty) {
        throw const BackupError('هذه نسخة احتياطية مشفّرة — أدخل كلمة مرورها');
      }
      data = jsonDecode(BackupCrypto.open(bytes, password)) as Map<String, dynamic>;
      // ملف استرداد المفتاح بالصيغة المشفّرة نفسها: يُرفض صراحةً بدل «استعادة صفر سجل».
      if (data['kind'] == 'imdad.dbkey.v1') {
        throw const BackupError('هذا ملف استرداد مفتاح القاعدة لا نسخة احتياطية — يُستعمل من شاشة الاسترداد عند الإقلاع');
      }
    } else {
      data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    final result = await importJson(data, trusted: true, source: 'ملف: ${file.uri.pathSegments.last}');
    await AuditRepo(db).log(
      action: 'backup.restore',
      entityType: 'نسخة احتياطية',
      summary: 'استعادة نسخة احتياطية: ${file.uri.pathSegments.last} (${result.inserted['users'] ?? 0} حسابًا)',
      details: {
        'file': file.uri.pathSegments.last,
        'users': result.inserted['users'] ?? 0,
        'rejected': result.rejectedUsers.length,
        'skipped': result.usersSkipped,
        'records': result.total,
      },
      risk: AuditRepo.riskHigh,
      actorEmail: actorEmail,
    );
    return result;
  }

  /// هل الملف نسخة مشفّرة؟ تستعمله الواجهة لتسأل كلمة المرور قبل الاستيراد.
  static Future<bool> isEncryptedFile(File file) async {
    final head = await file.openRead(0, BackupCrypto.magic.length).first;
    return BackupCrypto.isEncrypted(head);
  }

  /// [trusted] = الاستعادة من ملف يقرّرها المالك (`sys.backup`): لا يُشترط توقيع
  /// المالك على رفع الأدوار وفكّ الحجب. المزامنة (الافتراضي) تشترطه.
  ///
  /// [source] مصدر الحمولة لسجل التدقيق (جهاز مزامنة أو ملف)؛ فارغ إن لم يُعرف.
  Future<LegacyImportResult> importJson(
    Map<String, dynamic> data, {
    bool trusted = false,
    String source = '',
  }) async {
    final res = LegacyImportResult();
    final marks = SyncMarks(db);
    final negativesBefore = await _negativeKeys();

    await db.transaction(() async {
      _local = await marks.snapshot();
      _rejectedMarks = {};
      _changedOnTie = {};
      _replacedIds = {};
      _incoming = {
        for (final m in _rows(data['syncMarks']).map(SyncMark.fromMap))
          if (m != null) m.key: m,
      };

      // كل جدولٍ في نقطة حفظٍ مستقلة: عطلٌ غير متوقَّع في جدولٍ واحد كان يُجهض
      // معاملة الاستيراد كلها في كل دورة (H-1) — فتتوقف المزامنة لكل البيانات
      // بسبب سجلٍّ واحد. الآن يُتجاوز الجدول المتعثّر وحده، ولا تُثبَّت علاماته،
      // ولا تتقدّم علامة الماء فيُطلب ثانيةً.
      Future<void> step(List<String> entities, Future<void> Function() body) async {
        try {
          await db.transaction(body);
        } catch (err, stack) {
          ErrorLogger.critical('import.table.${entities.first}', err, stack: stack);
          for (final key in _incoming.keys) {
            if (entities.any((e) => key.startsWith('$e/'))) _rejectedMarks.add(key);
          }
          res.failedRows++;
          res.warnings.add('تعذّر دمج ${entities.join('، ')}: $err');
        }
      }

      await step(['users'], () => _importUsers(data['users'], res, trusted: trusted));
      await step(['categories'], () => _importCategories(data['categories'], res));
      await step(['items'], () => _importItems(data['items'], res));
      await step(['warehouses'], () => _importWarehouses(data['warehouses'], res));
      await step(['suppliers'], () => _importSuppliers(data['suppliers'], res));
      await step(['beneficiary_units'], () => _importUnits(data['units'], res));
      await step(['facilities'], () => _importFacilities(data['facilities'], res));
      await step(['receipts'], () => _importReceipts(data['receipts'], res));
      await step(['issues'], () => _importIssues(data['issues'], res));
      await step(['transfers'], () => _importTransfers(data['transfers'], res));
      await step(['returns'], () => _importReturns(data['returns'], res));
      await step(['opening_balances'], () => _importOpening(data['openingBalances'], res));
      await step(['adjustments'], () => _importAdjustments(data['adjustments'], res));
      await step(['strengths'], () => _importStrengths(data['strengths'], res));
      await step(['kitchen_logs'], () => _importKitchenLogs(data['kitchenLogs'], res));
      await step(['entitlements'], () => _importEntitlements(data['entitlements'], res));
      await step(['stocktakes'], () => _importStocktakes(data['stocktakes'], res));
      await step(['stocktake_lines'], () => _importStocktakeLines(data['stocktakeLines'], res));
      await step(['sensitive_reviews'], () => _importSensitiveReviews(data['sensitiveReviews'], res));
      await step(['assets'], () => _importAssets(data['assets'], res));
      await step(['asset_assignments'], () => _importAssetAssignments(data['assetAssignments'], res));
      await step(['supply_authorities'], () => _importSupplyAuthorities(data['supplyAuthorities'], res));
      await step(['warehouse_stock_limits'], () => _importWarehouseLimits(data['warehouseStockLimits'], res));
      await step([
        for (final e in SyncMarks.entities.keys)
          if (e.startsWith('fuel_')) e,
      ], () => _importFuel(data, res));
      await step(['ration_orders'], () => _importRationOrders(data['rationOrders'], res));
      await step(['ration_order_lines'], () => _importRationOrderLines(data['rationOrderLines'], res));
      await step(['meal_plans'], () => _importMealPlans(data['mealPlans'], res));
      await step(['meal_plan_entries'], () => _importMealPlanEntries(data['mealPlanEntries'], res));
      await step(['camp_ledgers'], () => _importCampLedgers(data['campLedgers'], res));
      await step(['camp_stock_limits'], () => _importCampStockLimits(data['campStockLimits'], res));
      await step(['monthly_settlements'], () => _importSettlements(data['monthlySettlements'], res));
      await step([
        'cables',
        for (final e in SyncMarks.entities.keys)
          if (e.startsWith('link_')) e,
      ], () => _importLinkage(data, res));
      await step(['audit_logs'], () => _importAuditLogs(data['auditLogs'], res));
      await step(['app_settings'], () => _importSettings(data['settings'], res));
      // مفتاح المالك يُمرَّر: قرار الإلغاء الوارد يُتحقَّق منه بالمفتاح نفسه الذي
      // يحرس الحسابات (`_ownerKey`)، لا بالمدفون — وإلا اختلف الحارسان.
      await DeviceActivation(db, ownerPublicKey: _ownerKey)
          .mergeRevocations(data['deviceRevocations']);
      await _applyTombstones(marks, res);
      await _settleMarks(marks);
    });

    await _auditNewNegatives(negativesBefore, source);
    return res;
  }
}
