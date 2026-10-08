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
      _incoming = {
        for (final m in _rows(data['syncMarks']).map(SyncMark.fromMap))
          if (m != null) m.key: m,
      };

      await _importUsers(data['users'], res, trusted: trusted);
      await _importCategories(data['categories'], res);
      await _importItems(data['items'], res);
      await _importWarehouses(data['warehouses'], res);
      await _importSuppliers(data['suppliers'], res);
      await _importUnits(data['units'], res);
      await _importFacilities(data['facilities'], res);
      await _importReceipts(data['receipts'], res);
      await _importIssues(data['issues'], res);
      await _importTransfers(data['transfers'], res);
      await _importReturns(data['returns'], res);
      await _importOpening(data['openingBalances'], res);
      await _importAdjustments(data['adjustments'], res);
      await _importStrengths(data['strengths'], res);
      await _importKitchenLogs(data['kitchenLogs'], res);
      await _importEntitlements(data['entitlements'], res);
      await _importStocktakes(data['stocktakes'], res);
      await _importStocktakeLines(data['stocktakeLines'], res);
      await _importSensitiveReviews(data['sensitiveReviews'], res);
      await _importAssets(data['assets'], res);
      await _importAssetAssignments(data['assetAssignments'], res);
      await _importSupplyAuthorities(data['supplyAuthorities'], res);
      await _importWarehouseLimits(data['warehouseStockLimits'], res);
      await _importFuel(data, res);
      await _importRationOrders(data['rationOrders'], res);
      await _importRationOrderLines(data['rationOrderLines'], res);
      await _importMealPlans(data['mealPlans'], res);
      await _importMealPlanEntries(data['mealPlanEntries'], res);
      await _importCampLedgers(data['campLedgers'], res);
      await _importCampStockLimits(data['campStockLimits'], res);
      await _importSettlements(data['monthlySettlements'], res);
      await _importLinkage(data, res);
      await _importAuditLogs(data['auditLogs'], res);
      await _importSettings(data['settings'], res);
      await DeviceActivation(db).mergeRevocations(data['deviceRevocations']);
      await _applyTombstones(marks, res);
      await _settleMarks(marks);
    });

    await _auditNewNegatives(negativesBefore, source);
    return res;
  }
}
