import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/security/pbkdf2.dart';
import '../db/app_database.dart';
import 'backup_crypto.dart';
import '../sync/sync_marks.dart';

/// ترحيل بيانات النسخة الحالية (الويب) إلى قاعدة Drift.
/// المصدر: ملف JSON مُصدَّر من النظام الحالي بالشكل:
/// { "items": [...], "warehouses": [...], "receipts": [...], ... }
/// كل مجموعة مصفوفة من الوثائق بنفس أسماء الحقول المستخدمة في الويب.
class WebImportResult {
  WebImportResult();

  final Map<String, int> inserted = {};
  final List<String> warnings = [];

  int get total => inserted.values.fold(0, (a, b) => a + b);

  @override
  String toString() =>
      'استُورد $total سجلًا: ${inserted.entries.map((e) => '${e.key}=${e.value}').join('، ')}';
}

class WebImporter {
  WebImporter(this.db);

  final AppDatabase db;

  /// يستورد ملف نسخة احتياطية، مشفَّرًا كان أو JSON عاديًا.
  ///
  /// [password] تلزم للملف المشفَّر فقط؛ وغيابها عنه يرمي [BackupError] برسالة
  /// صريحة بدل استيراد نصف ملف.
  Future<WebImportResult> importFile(File file, {String password = ''}) async {
    final bytes = await file.readAsBytes();
    if (BackupCrypto.isEncrypted(bytes)) {
      if (password.isEmpty) {
        throw const BackupError('هذه نسخة احتياطية مشفّرة — أدخل كلمة مرورها');
      }
      return importJson(jsonDecode(BackupCrypto.open(bytes, password)) as Map<String, dynamic>);
    }
    return importJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  }

  /// هل الملف نسخة مشفّرة؟ تستعمله الواجهة لتسأل كلمة المرور قبل الاستيراد.
  static Future<bool> isEncryptedFile(File file) async {
    final head = await file.openRead(0, BackupCrypto.magic.length).first;
    return BackupCrypto.isEncrypted(head);
  }

  /// علامات الجهازين: المحلية كما كانت **قبل** الاستيراد (المحفِّزات ستغيّرها
  /// أثناءه)، والواردة مع الحمولة.
  Map<String, SyncMark> _local = const {};
  Map<String, SyncMark> _incoming = const {};

  /// هل يُقبل السجل الوارد؟ يفوز الأحدث ختمًا؛ وعند تساوي الختم يفوز الوارد
  /// (السجلان متطابقان عمليًا، والترجيح الثابت يمنع تذبذب الأجهزة).
  bool _accept(String entity, String rowId) {
    if (rowId.isEmpty) return true;
    final local = _local['$entity/$rowId'];
    if (local == null) return true;
    final incoming = _incoming['$entity/$rowId'];
    if (incoming == null) return false;
    return incoming.stamp >= local.stamp;
  }

  Future<WebImportResult> importJson(Map<String, dynamic> data) async {
    final res = WebImportResult();
    final marks = SyncMarks(db);

    await db.transaction(() async {
      _local = await marks.snapshot();
      _incoming = {
        for (final m in _rows(data['syncMarks']).map(SyncMark.fromMap))
          if (m != null) m.key: m,
      };

      await _importUsers(data['users'], res);
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
      await _importAuditLogs(data['auditLogs'], res);
      await _importSettings(data['settings'], res);
      await _applyTombstones(marks, res);
      await _settleMarks(marks);
    });

    return res;
  }

  /// ما حُذف في الجهاز الآخر يُحذف هنا أيضًا — ما لم يُعدَّل عندنا بعد حذفه.
  Future<void> _applyTombstones(SyncMarks marks, WebImportResult res) async {
    var removed = 0;
    for (final mark in _incoming.values) {
      if (!mark.isDeleted) continue;
      if (!SyncMarks.entities.containsKey(mark.entity)) continue;
      final local = _local[mark.key];
      if (local != null && local.stamp > mark.stamp) continue;
      await marks.applyTombstone(mark);
      removed++;
    }
    if (removed > 0) res.inserted['محذوفات منقولة'] = removed;
  }

  /// تثبيت الختم الفائز لكل سجل بدل الختم الذي كتبته المحفِّزات لحظة الاستيراد،
  /// حتى يصل الجهازان إلى العلامات نفسها ولا تتأرجح المزامنة التالية.
  Future<void> _settleMarks(SyncMarks marks) async {
    for (final entry in _incoming.entries) {
      final incoming = entry.value;
      final local = _local[entry.key];
      final winner = (local == null || incoming.stamp >= local.stamp) ? incoming : local;
      await marks.put(winner);
    }
  }

  /// أوامر الجرد وسطورها — بيانات تشغيلية كانت خارج المزامنة، فكانت جلسة جرد
  /// تتم في فرع ولا تبلغ الإدارة أبدًا.
  Future<void> _importStocktakes(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final s in rows) {
      if (!_accept('stocktakes', _id(s))) continue;
      await db.into(db.stocktakes).insertOnConflictUpdate(StocktakesCompanion.insert(
            id: _id(s),
            orderNo: Value(_s(s, 'orderNo')),
            type: Value(_s(s, 'type', 'FULL')),
            date: Value(_s(s, 'date')),
            warehouse: Value(_s(s, 'warehouse')),
            categoryId: Value(_s(s, 'categoryId')),
            categoryName: Value(_s(s, 'categoryName')),
            committee: Value(_s(s, 'committee')),
            freeze: Value(_b(s, 'freeze', true)),
            status: Value(_s(s, 'status', 'COUNTING')),
            itemsCount: Value(_i(s, 'itemsCount')),
            notes: Value(_s(s, 'notes')),
            closedDate: Value(_s(s, 'closedDate')),
            createdBy: Value(_s(s, 'createdBy')),
            createdAt: Value(_created(s)),
            cancelReason: Value(_s(s, 'cancelReason')),
            cancelledBy: Value(_s(s, 'cancelledBy')),
            closedBy: Value(_s(s, 'closedBy')),
            countedCount: Value(_i(s, 'countedCount')),
            varianceCount: Value(_i(s, 'varianceCount')),
            adjustedCount: Value(_i(s, 'adjustedCount')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'أوامر الجرد', rows.length);
  }

  Future<void> _importStocktakeLines(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final l in rows) {
      if (!_accept('stocktake_lines', _id(l))) continue;
      await db.into(db.stocktakeLines).insertOnConflictUpdate(StocktakeLinesCompanion.insert(
            id: _id(l),
            sessionId: _s(l, 'sessionId'),
            itemId: _s(l, 'itemId'),
            itemCode: Value(_s(l, 'itemCode')),
            itemName: Value(_s(l, 'itemName')),
            unitName: Value(_s(l, 'unitName')),
            systemQty: Value(_d(l, 'systemQty')),
            // الكمية المعدودة والفرق يبقيان فارغين ما لم يُعَدّ السطر فعلًا:
            // الصفر هنا يعني «عُدّ فوُجد صفرًا»، وهو غير «لم يُعَدّ بعد».
            countedQty: Value(l['countedQty'] == null ? null : _d(l, 'countedQty')),
            counts: Value(_json(l['counts'], '{}')),
            variance: Value(l['variance'] == null ? null : _d(l, 'variance')),
            reason: Value(_s(l, 'reason')),
            decision: Value(_s(l, 'decision', 'ADJUST')),
            status: Value(_s(l, 'status', 'PENDING')),
            discovered: Value(_b(l, 'discovered')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سطور الجرد', rows.length);
  }

  Future<void> _importSensitiveReviews(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('sensitive_reviews', _id(r))) continue;
      await db.into(db.sensitiveReviews).insertOnConflictUpdate(SensitiveReviewsCompanion.insert(
            id: _id(r),
            logId: _s(r, 'logId'),
            reviewedBy: Value(_s(r, 'reviewedBy')),
            note: Value(_s(r, 'note')),
            reviewedAt: Value(DateTime.tryParse(_s(r, 'reviewedAt')) ?? DateTime.now()),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'مراجعات حساسة', rows.length);
  }

  /// سجل التدقيق: يتجمّع من كل الأجهزة عند الإدارة، فيُرى نشاط الوحدة كله في
  /// مكان واحد. السطور لا تُعدَّل بعد كتابتها، فالدمج بالمعرّف لا يتعارض.
  Future<void> _importAuditLogs(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('audit_logs', _id(a))) continue;
      await db.into(db.auditLogs).insertOnConflictUpdate(AuditLogsCompanion.insert(
            id: _id(a),
            action: _s(a, 'action'),
            entityType: Value(_s(a, 'entityType')),
            summary: Value(_s(a, 'summary')),
            details: Value(_json(a['details'], '{}')),
            risk: Value(_s(a, 'risk', 'normal')),
            actorEmail: Value(_s(a, 'actorEmail')),
            logDate: Value(_s(a, 'logDate')),
            actorName: Value(_s(a, 'actorName')),
            actorRole: Value(_s(a, 'actorRole', 'user')),
            refNo: Value(_s(a, 'refNo')),
            warehouse: Value(_s(a, 'warehouse')),
            target: Value(_s(a, 'target')),
            status: Value(_s(a, 'status')),
            itemCount: Value(_i(a, 'itemCount')),
            qty: Value(_d(a, 'qty')),
            createdAt: Value(_created(a)),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'سجل التدقيق', rows.length);
  }

  // ───────── أدوات مساعدة ─────────
  List<Map<String, dynamic>> _rows(Object? v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  String _s(Map<String, dynamic> m, String k, [String def = '']) {
    final v = m[k];
    if (v == null) return def;
    return v.toString();
  }

  double _d(Map<String, dynamic> m, String k, [double def = 0]) {
    final v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? def;
    return def;
  }

  int _i(Map<String, dynamic> m, String k, [int def = 0]) => _d(m, k, def.toDouble()).round();

  bool _b(Map<String, dynamic> m, String k, [bool def = false]) {
    final v = m[k];
    if (v is bool) return v;
    if (v is String) return v == 'true' || v == '1';
    return def;
  }

  String _json(Object? v, [String def = '[]']) {
    if (v == null) return def;
    if (v is String) return v;
    return jsonEncode(v);
  }

  String _id(Map<String, dynamic> m) {
    final id = _s(m, 'id');
    if (id.isNotEmpty) return id;
    return 'imp-${DateTime.now().microsecondsSinceEpoch}-${m.hashCode.abs()}';
  }

  DateTime _created(Map<String, dynamic> m) {
    final v = m['createdAt'];
    if (v is Map && v['seconds'] is num) {
      return DateTime.fromMillisecondsSinceEpoch(((v['seconds'] as num) * 1000).round());
    }
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.round());
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  void _count(WebImportResult res, String key, int n) =>
      res.inserted[key] = (res.inserted[key] ?? 0) + n;

  // ───────── الجداول ─────────
  Future<void> _importUsers(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    var passwordless = 0;
    for (final u in rows) {
      if (!_accept('users', _id(u))) continue;

      // **كلمة المرور تُنقل مع الحساب.** الملح والبصمة يخرجان في التصدير، وكان
      // الاستيراد لا يقرؤهما — فيصل الحساب إلى الفرع ببصمة فارغة، ويستحيل
      // الدخول به مديرًا كان أو غيره. الحساب بلا بصمته ليس حسابًا.
      final salt = _s(u, 'saltHex');
      final hash = _s(u, 'hashHex');
      final hasSecret = salt.isNotEmpty && hash.isNotEmpty;
      if (!hasSecret) passwordless++;

      await db.into(db.users).insertOnConflictUpdate(UsersCompanion.insert(
            id: _id(u),
            username: _s(u, 'username', _s(u, 'email').split('@').first),
            name: Value(_s(u, 'name')),
            email: Value(_s(u, 'email')),
            role: Value(_s(u, 'role', 'user')),
            roles: Value(_json(u['roles'])),
            permissions: Value(_json(u['permissions'], '{}')),
            warehouseScope: Value(u['warehouseScope'] is List
                ? _json(u['warehouseScope'])
                : _s(u, 'warehouseScope', 'ALL')),
            // حمولةٌ بلا بصمة تترك الأعمدة الثلاثة **غائبة** لا فارغة: الغياب
            // يُبقي كلمة المرور القائمة على هذا الجهاز، والفراغ يمحوها. ونسخة
            // ويب قديمة بلا بصمات كانت ستمحو كلمات المرور عند كل استيراد.
            saltHex: hasSecret ? Value(salt) : const Value.absent(),
            hashHex: hasSecret ? Value(hash) : const Value.absent(),
            iterations: hasSecret
                ? Value(_i(u, 'iterations', Pbkdf2.legacyIterations))
                : const Value.absent(),
            active: Value(_b(u, 'active', true)),
            approved: Value(_b(u, 'approved', true)),
            createdAt: Value(_created(u)),
          ));
    }
    _count(res, 'users', rows.length);
    if (passwordless > 0) {
      res.warnings.add('$passwordless حسابًا وصل بلا كلمة مرور (تصدير قديم لا يحمل '
          'الملح والبصمة) — يُعيّنها مدير النظام من شاشة المستخدمين.');
    }
  }

  Future<void> _importCategories(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final c in rows) {
      if (!_accept('categories', _id(c))) continue;
      await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion.insert(
            id: _id(c),
            name: _s(c, 'name'),
            description: Value(_s(c, 'description')),
          ));
    }
    _count(res, 'categories', rows.length);
  }

  Future<void> _importItems(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final it in rows) {
      if (!_accept('items', _id(it))) continue;
      await db.into(db.items).insertOnConflictUpdate(ItemsCompanion.insert(
            id: _id(it),
            name: _s(it, 'name'),
            code: Value(_s(it, 'code')),
            categoryId: Value(_s(it, 'categoryId')),
            categoryName: Value(_s(it, 'categoryName')),
            baseUnit: Value(_s(it, 'baseUnit')),
            units: Value(_json(it['units'])),
            qty: Value(_d(it, 'qty')),
            // `min` في ملف الويب، و`minQty` في تصدير هذا التطبيق.
            minQty: Value(_d(it, 'minQty', _d(it, 'min'))),
            barcode: Value(_s(it, 'barcode')),
            isRefillable: Value(_b(it, 'isRefillable')),
            reportUnit: Value(_s(it, 'reportUnit')),
            createdAt: Value(_created(it)),
          ));
    }
    _count(res, 'items', rows.length);
  }

  Future<void> _importWarehouses(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final w in rows) {
      if (!_accept('warehouses', _id(w))) continue;
      await db.into(db.warehouses).insertOnConflictUpdate(WarehousesCompanion.insert(
            id: _id(w),
            name: _s(w, 'name'),
            code: Value(_s(w, 'code')),
            manager: Value(_s(w, 'manager')),
            location: Value(_s(w, 'location')),
            feedsAllCamps: Value(_b(w, 'feedsAllCamps', true)),
            campIds: Value(_json(w['campIds'])),
            notes: Value(_s(w, 'notes')),
          ));
    }
    _count(res, 'warehouses', rows.length);
  }

  Future<void> _importSuppliers(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final s in rows) {
      if (!_accept('suppliers', _id(s))) continue;
      await db.into(db.suppliers).insertOnConflictUpdate(SuppliersCompanion.insert(
            id: _id(s),
            name: _s(s, 'name'),
            phone: Value(_s(s, 'phone')),
            notes: Value(_s(s, 'notes')),
            contact: Value(_s(s, 'contact')),
            city: Value(_s(s, 'city')),
          ));
    }
    _count(res, 'suppliers', rows.length);
  }

  Future<void> _importUnits(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final u in rows) {
      if (!_accept('beneficiary_units', _id(u))) continue;
      await db.into(db.beneficiaryUnits).insertOnConflictUpdate(BeneficiaryUnitsCompanion.insert(
            id: _id(u),
            name: _s(u, 'name'),
            code: Value(_s(u, 'code')),
            type: Value(_s(u, 'type', 'unit')),
            parentId: Value(_s(u, 'parentId')),
            parentName: Value(_s(u, 'parentName')),
            isCamp: Value(_b(u, 'isCamp') || _s(u, 'type') == 'camp'),
            facilityId: Value(_s(u, 'facilityId')),
            // القائمة الجديدة، ومع البيانات القديمة يُشتق منها الارتباط المفرد.
            facilityIds: Value(_json(u['facilityIds'], _s(u, 'facilityId').isEmpty
                ? '[]'
                : '["${_s(u, 'facilityId')}"]')),
            category: Value(_s(u, 'category')),
          ));
    }
    _count(res, 'units', rows.length);
  }

  Future<void> _importFacilities(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final f in rows) {
      if (!_accept('facilities', _id(f))) continue;
      await db.into(db.facilities).insertOnConflictUpdate(FacilitiesCompanion.insert(
            id: _id(f),
            name: _s(f, 'name'),
            fType: Value(_s(f, 'fType', 'KITCHEN')),
            capacity: Value(_i(f, 'capacity')),
            warehouse: Value(_s(f, 'warehouse')),
            notes: Value(_s(f, 'notes')),
          ));
    }
    _count(res, 'facilities', rows.length);
  }

  Future<void> _importReceipts(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('receipts', _id(r))) continue;
      await db.into(db.receipts).insertOnConflictUpdate(ReceiptsCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            supplier: Value(_s(r, 'supplier')),
            invoiceNo: Value(_s(r, 'invoiceNo')),
            committee: Value(_s(r, 'committee')),
            supervision: Value(_s(r, 'supervision')),
            audit: Value(_s(r, 'audit')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            expiryDate: Value(_s(r, 'expiryDate')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'receipts', rows.length);
  }

  Future<void> _importIssues(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('issues', _id(r))) continue;
      await db.into(db.issues).insertOnConflictUpdate(IssuesCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            targetType: Value(_i(r, 'targetType')),
            recipientDisplay: Value(_s(r, 'recipientDisplay')),
            unitId: Value(_s(r, 'unitId')),
            facilityId: Value(_s(r, 'facilityId')),
            beneficiaryUnitId: Value(_s(r, 'beneficiaryUnitId')),
            beneficiaryUnitName: Value(_s(r, 'beneficiaryUnitName')),
            soldierCount: Value(_d(r, 'soldierCount')),
            durationDays: Value(_i(r, 'durationDays', 1)),
            officerCount: Value(_d(r, 'officerCount')),
            cylinderAction: Value(_s(r, 'cylinderAction')),
            approvedBy: Value(_s(r, 'approvedBy')),
            rejectReason: Value(_s(r, 'rejectReason')),
            rejectedBy: Value(_s(r, 'rejectedBy')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'issues', rows.length);
  }

  Future<void> _importTransfers(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('transfers', _id(r))) continue;
      await db.into(db.transfers).insertOnConflictUpdate(TransfersCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'PENDING')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            destWarehouse: Value(_s(r, 'destWarehouse')),
            campId: Value(_s(r, 'campId')),
            campName: Value(_s(r, 'campName')),
            strength: Value(_d(r, 'strength')),
            durationDays: Value(_i(r, 'durationDays', 1)),
            rejectReason: Value(_s(r, 'rejectReason')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'transfers', rows.length);
  }

  Future<void> _importReturns(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('returns', _id(r))) continue;
      await db.into(db.returns).insertOnConflictUpdate(ReturnsCompanion.insert(
            id: _id(r),
            refNo: Value(_s(r, 'refNo')),
            date: Value(_s(r, 'date')),
            warehouse: Value(_s(r, 'warehouse')),
            itemId: Value(_s(r, 'itemId')),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            factor: Value(_d(r, 'factor', 1)),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            status: Value(_s(r, 'status', 'COMPLETED')),
            notes: Value(_s(r, 'notes')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
            party: Value(_s(r, 'party')),
            type: Value(_s(r, 'type', 'FROM_UNIT')),
            condition: Value(_s(r, 'condition', 'صالحة')),
            origRef: Value(_s(r, 'origRef')),
            editCount: Value(_i(r, 'editCount')),
            editLog: Value(_json(r['editLog'])),
            editedBy: Value(_s(r, 'editedBy')),
            cancelReason: Value(_s(r, 'cancelReason')),
            cancelledBy: Value(_s(r, 'cancelledBy')),
            prevStatus: Value(_s(r, 'prevStatus')),
          ));
    }
    _count(res, 'returns', rows.length);
  }

  Future<void> _importOpening(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('opening_balances', _id(r))) continue;
      await db.into(db.openingBalances).insertOnConflictUpdate(OpeningBalancesCompanion.insert(
            id: _id(r),
            itemId: _s(r, 'itemId'),
            itemCode: Value(_s(r, 'itemCode')),
            itemName: Value(_s(r, 'itemName')),
            warehouse: Value(_s(r, 'warehouse')),
            qty: Value(_d(r, 'qty')),
            date: Value(_s(r, 'date')),
            setBy: Value(_s(r, 'setBy')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'openingBalances', rows.length);
    if (rows.any((r) => _s(r, 'warehouse').isEmpty)) {
      res.warnings.add('بعض الأرصدة الافتتاحية بلا مستودع — حدّد لها مستودعًا بعد الترحيل لتدخل في رصيده.');
    }
  }

  /// تسويات الجرد — موجودة في نسخ التطبيق الأصلي فقط، وبدونها تختل الأرصدة
  /// المستعادة لأن فروق الجرد المعتمدة جزء من رصيد المستودع.
  Future<void> _importAdjustments(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final a in rows) {
      if (!_accept('adjustments', _id(a))) continue;
      await db.into(db.adjustments).insertOnConflictUpdate(AdjustmentsCompanion.insert(
            id: _id(a),
            refNo: Value(_s(a, 'refNo')),
            date: Value(_s(a, 'date')),
            warehouse: Value(_s(a, 'warehouse')),
            itemId: Value(_s(a, 'itemId')),
            itemCode: Value(_s(a, 'itemCode')),
            itemName: Value(_s(a, 'itemName')),
            unitName: Value(_s(a, 'unitName')),
            factor: Value(_d(a, 'factor', 1)),
            qty: Value(_d(a, 'qty')),
            baseQty: Value(_d(a, 'baseQty')),
            status: Value(_s(a, 'status', 'COMPLETED')),
            notes: Value(_s(a, 'notes')),
            createdBy: Value(_s(a, 'createdBy')),
            createdAt: Value(_created(a)),
            sessionId: Value(_s(a, 'sessionId')),
            reason: Value(_s(a, 'reason')),
            approvedBy: Value(_s(a, 'approvedBy')),
            editCount: Value(_i(a, 'editCount')),
            editLog: Value(_json(a['editLog'])),
            editedBy: Value(_s(a, 'editedBy')),
            cancelReason: Value(_s(a, 'cancelReason')),
            cancelledBy: Value(_s(a, 'cancelledBy')),
            prevStatus: Value(_s(a, 'prevStatus')),
          ));
    }
    if (rows.isNotEmpty) _count(res, 'adjustments', rows.length);
  }

  Future<void> _importStrengths(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('strengths', _id(r))) continue;
      await db.into(db.strengths).insertOnConflictUpdate(StrengthsCompanion.insert(
            id: _id(r),
            unitId: _s(r, 'unitId'),
            unitName: Value(_s(r, 'unitName')),
            campId: Value(_s(r, 'campId')),
            campName: Value(_s(r, 'campName')),
            strengthDate: _s(r, 'strengthDate', _s(r, 'date')),
            soldierCount: Value(_d(r, 'soldierCount')),
            officerCount: Value(_d(r, 'officerCount')),
            total: Value(_d(r, 'total')),
            pct: Value(_d(r, 'pct')),
            mode: Value(_s(r, 'mode', 'detail')),
            createdBy: Value(_s(r, 'createdBy')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'strengths', rows.length);
  }

  Future<void> _importKitchenLogs(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      if (!_accept('kitchen_logs', _id(r))) continue;
      await db.into(db.kitchenLogs).insertOnConflictUpdate(KitchenLogsCompanion.insert(
            id: _id(r),
            facilityId: _s(r, 'facilityId'),
            facilityName: Value(_s(r, 'facilityName')),
            date: _s(r, 'date'),
            mealType: Value(_s(r, 'mealType', 'LUNCH')),
            strength: Value(_d(r, 'strength')),
            itemId: Value(_s(r, 'itemId')),
            itemName: Value(_s(r, 'itemName')),
            unitName: Value(_s(r, 'unitName')),
            qty: Value(_d(r, 'qty')),
            baseQty: Value(_d(r, 'baseQty')),
            expectedBase: Value(_d(r, 'expectedBase')),
            varianceBase: Value(_d(r, 'varianceBase')),
            notes: Value(_s(r, 'notes')),
            createdAt: Value(_created(r)),
          ));
    }
    _count(res, 'kitchenLogs', rows.length);
  }

  Future<void> _importEntitlements(Object? raw, WebImportResult res) async {
    final rows = _rows(raw);
    for (final r in rows) {
      final itemId = _s(r, 'itemId', _id(r));
      if (!_accept('entitlements', itemId)) continue;
      final unitName = _s(r, 'measureUnitName', _s(r, 'unitName'));
      // `entFactor(ent,item)`: المعامل من وحدات الصنف بالاسم (الويب لا يخزّنه في المقرر)،
      // وإلا فالمعامل المصدَّر مع المقرر (تصدير هذا التطبيق) حين لا يكون الصنف هنا بعد.
      var factor = _d(r, 'measureFactor', 1);
      if (factor <= 0) factor = 1;
      final item = await (db.select(db.items)..where((t) => t.id.equals(itemId))).getSingleOrNull();
      if (item != null) {
        try {
          final units = jsonDecode(item.units);
          if (units is List) {
            for (final u in units.whereType<Map>()) {
              if (u['name']?.toString() == unitName && u['factor'] is num && (u['factor'] as num) > 0) {
                factor = (u['factor'] as num).toDouble();
              }
            }
          }
        } catch (_) {}
      }
      // `entMeasureQty`: السجلات القديمة (بدون qtyUnit='measure') محفوظة بالوحدة الأساسية فتُحوَّل.
      final q = _d(r, 'qtyPerPerson');
      final measureQty = _s(r, 'qtyUnit') == 'measure' ? q : q / factor;
      await db.into(db.entitlements).insertOnConflictUpdate(EntitlementsCompanion.insert(
            itemId: itemId,
            itemName: Value(_s(r, 'itemName')),
            qtyPerPerson: Value((measureQty * 1000).round() / 1000),
            measureUnitName: Value(unitName),
            measureFactor: Value(factor),
            notes: Value(_s(r, 'notes')),
            updatedAt: Value(DateTime.now()),
          ));
    }
    _count(res, 'entitlements', rows.length);
  }

  Future<void> _importSettings(Object? raw, WebImportResult res) async {
    if (raw is! Map) return;
    final map = raw.cast<String, dynamic>();
    for (final entry in map.entries) {
      if (!_accept('app_settings', entry.key)) continue;
      await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
            key: entry.key,
            value: Value(_json(entry.value, '{}')),
            updatedAt: Value(DateTime.now()),
          ));
    }
    _count(res, 'settings', map.length);
  }
}
