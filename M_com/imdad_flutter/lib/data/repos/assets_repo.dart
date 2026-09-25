import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/assets.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';

/// الأصول الثابتة وعهدها.
///
/// مستودع مستقل لا إضافة إلى [CatalogRepo]: الأصول ليست أصنافًا تُصرف، ولها
/// دورة حياة خاصة (اقتناء، عهدة، صيانة، استهلاك). خلطها بالأصناف يجعل كل
/// استعلام كتالوج يحمل شرطًا لاستبعادها.
class AssetsRepo {
  AssetsRepo(this.db);

  final AppDatabase db;

  // ───────────────────────── قراءة

  /// [scope] نطاق مستودعات المستخدم: `null` ⇒ كل المستودعات.
  ///
  /// الترشيح هنا لا في الشاشة: شاشةٌ تجلب كل شيء ثم تخفي بعضه تسرّب البيانات
  /// إلى أي تصدير أو طباعة تُبنى من المصدر نفسه.
  Future<List<Asset>> assets({
    String query = '',
    String type = '',
    String status = '',
    List<String>? scope,
  }) async {
    final q = db.select(db.assets);
    if (type.isNotEmpty) q.where((t) => t.assetType.equals(type));
    if (status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (scope != null) {
      // مستودع فارغ يعني أصلًا غير مربوط بمستودع: يبقى ظاهرًا للجميع، وإخفاؤه
      // يجعله أصلًا لا يراه أحد فلا يُجرد أبدًا.
      q.where((t) => t.warehouse.isIn(scope) | t.warehouse.equals(''));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final rows = await q.get();

    final s = query.trim().toLowerCase();
    if (s.isEmpty) return rows;
    return rows
        .where((a) =>
            a.name.toLowerCase().contains(s) ||
            a.serialNumber.toLowerCase().contains(s) ||
            a.beneficiaryUnitName.toLowerCase().contains(s) ||
            a.facilityName.toLowerCase().contains(s))
        .toList();
  }

  Future<Asset?> byId(String id) =>
      (db.select(db.assets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// بحث بالباركود: الرقم التسلسلي أولًا، ثم الرمز المشتقّ من المعرّف.
  Future<Asset?> byBarcode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final bySerial =
        await (db.select(db.assets)..where((t) => t.serialNumber.equals(c))).get();
    if (bySerial.isNotEmpty) return bySerial.first;
    final all = await db.select(db.assets).get();
    for (final a in all) {
      if (AssetRules.barcodeOf(id: a.id, serialNumber: a.serialNumber) == c.toUpperCase()) {
        return a;
      }
    }
    return null;
  }

  /// هل الرقم التسلسلي مستعمل في أصل آخر؟ الفراغ لا يُعدّ تكرارًا.
  Future<bool> serialTaken(String serial, {String exceptId = ''}) async {
    final s = serial.trim();
    if (s.isEmpty) return false;
    final rows =
        await (db.select(db.assets)..where((t) => t.serialNumber.equals(s))).get();
    return rows.any((a) => a.id != exceptId);
  }

  // ───────────────────────── كتابة

  /// حفظ دفعة أصول تتشارك بياناتها العامة وتختلف في الاسم والكمية.
  ///
  /// أكثر ما يُدخَل من الأصول يأتي دفعةً واحدة: فاتورةٌ واحدة، ومورّدٌ واحد،
  /// وتاريخُ اقتناءٍ واحد، ومستودعٌ واحد — ويختلف السطور في الاسم والعدد.
  /// فتُفصل البيانات المشتركة عن المتغيّرة بدل إعادة كتابتها في كل سطر.
  ///
  /// والدفعة تُحفظ كلّها أو لا شيء: نصفُ دفعةٍ محفوظ يترك المستخدم لا يدري
  /// أيّ سطرٍ وصل، فيعيد إدخال الكل ويُضاعف ما حُفظ.
  Future<({bool ok, String error, int saved})> saveBatch({
    required List<AssetDraft> rows,
    required String assetType,
    String facilityId = '',
    String facilityName = '',
    String beneficiaryUnitId = '',
    String beneficiaryUnitName = '',
    String warehouse = '',
    String status = AssetStatus.isNew,
    String acquisitionDate = '',
    String supplierId = '',
    String supplierName = '',
    String invoiceNumber = '',
    String notes = '',
    String actor = '',
  }) async {
    final error = AssetRules.validateBatch(rows);
    if (error != null) return (ok: false, error: '✖ $error', saved: 0);

    // الرقم التسلسلي يعرّف قطعة بعينها في النظام كلّه لا في الدفعة وحدها.
    final serials = rows
        .map((r) => r.serial.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (serials.isNotEmpty) {
      final clash = await (db.select(db.assets)
            ..where((t) => t.serialNumber.isIn(serials))
            ..limit(1))
          .getSingleOrNull();
      if (clash != null) {
        return (
          ok: false,
          error: '✖ الرقم التسلسلي «${clash.serialNumber}» مسجَّل سلفًا '
              'للأصل «${clash.name}»',
          saved: 0
        );
      }
    }

    final now = DateTime.now();
    await db.transaction(() async {
      for (final r in rows) {
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: Ids.next('ast'),
              name: r.name.trim(),
              quantity: Value(r.quantity),
              assetType: Value(assetType),
              serialNumber: Value(r.serial.trim()),
              facilityId: Value(facilityId),
              facilityName: Value(facilityName),
              beneficiaryUnitId: Value(beneficiaryUnitId),
              beneficiaryUnitName: Value(beneficiaryUnitName),
              warehouse: Value(warehouse),
              status: Value(status),
              acquisitionDate: Value(acquisitionDate),
              value: Value(r.value),
              lifespanMonths: Value(r.lifespanMonths),
              supplierId: Value(supplierId),
              supplierName: Value(supplierName),
              invoiceNumber: Value(invoiceNumber),
              notes: Value(notes),
              createdBy: Value(actor),
              createdAt: Value(now),
            ));
      }
    });

    await AuditRepo(db).log(
      action: 'asset.createBatch',
      entityType: 'أصل ثابت',
      summary: 'إضافة ${rows.length} أصلًا '
          '(${AssetRules.totalPieces(rows).toInt()} قطعة) دفعةً واحدة',
      details: {
        'rows': rows.length,
        'pieces': AssetRules.totalPieces(rows),
        'value': AssetRules.totalValue(rows),
        'type': assetType,
      },
      actorEmail: actor,
    );
    return (ok: true, error: '', saved: rows.length);
  }

  Future<String> save({
    String? id,
    required String name,
    double quantity = 1,
    required String assetType,
    String serialNumber = '',
    String facilityId = '',
    String facilityName = '',
    String beneficiaryUnitId = '',
    String beneficiaryUnitName = '',
    String warehouse = '',
    String status = AssetStatus.isNew,
    String acquisitionDate = '',
    double value = 0,
    int lifespanMonths = 0,
    String supplierId = '',
    String supplierName = '',
    String invoiceNumber = '',
    String notes = '',
    String actor = '',
  }) async {
    final assetId = id ?? Ids.next('ast');
    final now = DateTime.now();
    await db.into(db.assets).insertOnConflictUpdate(AssetsCompanion.insert(
          id: assetId,
          name: name.trim(),
          quantity: Value(quantity),
          assetType: Value(assetType),
          serialNumber: Value(serialNumber.trim()),
          facilityId: Value(facilityId),
          facilityName: Value(facilityName),
          beneficiaryUnitId: Value(beneficiaryUnitId),
          beneficiaryUnitName: Value(beneficiaryUnitName),
          warehouse: Value(warehouse),
          status: Value(status),
          acquisitionDate: Value(acquisitionDate),
          value: Value(value),
          lifespanMonths: Value(lifespanMonths),
          supplierId: Value(supplierId),
          supplierName: Value(supplierName),
          invoiceNumber: Value(invoiceNumber),
          notes: Value(notes),
          createdBy: Value(actor),
          updatedAt: Value(id == null ? null : now),
        ));
    await AuditRepo(db).log(
      action: id == null ? 'asset.create' : 'asset.update',
      entityType: 'أصل ثابت',
      summary: '${id == null ? 'إضافة' : 'تعديل'} الأصل «${name.trim()}»',
      details: {'assetId': assetId, 'type': assetType, 'status': status},
      actorEmail: actor,
    );
    return assetId;
  }

  /// الحذف يُمنع ما دامت عليه عهدة قائمة: أصلٌ يُحذف وهو بيد وحدةٍ يضيع أثره
  /// ولا يُسأل عنه أحد.
  Future<({bool ok, String error})> delete(String id, {String actor = ''}) async {
    final open = await (db.select(db.assetAssignments)
          ..where((t) => t.assetId.equals(id) & t.returnedDate.equals('')))
        .get();
    if (open.isNotEmpty) {
      final who = open.first.beneficiaryUnitName;
      return (
        ok: false,
        error: 'الأصل في عهدة ${who.isEmpty ? 'وحدة' : who} — سلّمه أولًا ثم احذفه',
      );
    }
    final asset = await byId(id);
    await db.transaction(() async {
      await (db.delete(db.assetAssignments)..where((t) => t.assetId.equals(id))).go();
      await (db.delete(db.assets)..where((t) => t.id.equals(id))).go();
    });
    await AuditRepo(db).log(
      action: 'asset.delete',
      entityType: 'أصل ثابت',
      summary: 'حذف الأصل «${asset?.name ?? id}»',
      details: {'assetId': id},
      risk: AuditRepo.riskHigh,
      actorEmail: actor,
    );
    return (ok: true, error: '');
  }

  // ───────────────────────── العهد

  Future<List<AssetAssignment>> assignments(String assetId) =>
      (db.select(db.assetAssignments)
            ..where((t) => t.assetId.equals(assetId))
            ..orderBy([(t) => OrderingTerm.desc(t.assignedDate)]))
          .get();

  /// العهدة القائمة على أصل، إن وُجدت.
  Future<AssetAssignment?> openAssignment(String assetId) async {
    final rows = await (db.select(db.assetAssignments)
          ..where((t) => t.assetId.equals(assetId) & t.returnedDate.equals('')))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// تسليم عهدة. يُرفض إن كان الأصل خارج الخدمة أو في عهدة قائمة.
  Future<({bool ok, String error})> assign({
    required String assetId,
    required String beneficiaryUnitId,
    required String beneficiaryUnitName,
    required String assignedDate,
    String assignedTo = '',
    String notes = '',
    String actor = '',
  }) async {
    final asset = await byId(assetId);
    if (asset == null) return (ok: false, error: 'الأصل غير موجود');
    if (AssetStatus.outOfService.contains(asset.status)) {
      return (
        ok: false,
        error: 'الأصل «${AssetStatus.label(asset.status)}» — لا يُسلَّم عهدةً',
      );
    }
    if (await openAssignment(assetId) != null) {
      return (ok: false, error: 'الأصل في عهدة قائمة — استرجعه أولًا');
    }
    await db.into(db.assetAssignments).insert(AssetAssignmentsCompanion.insert(
          id: Ids.next('asg'),
          assetId: assetId,
          assetName: Value(asset.name),
          beneficiaryUnitId: Value(beneficiaryUnitId),
          beneficiaryUnitName: Value(beneficiaryUnitName),
          assignedDate: Value(assignedDate),
          assignedTo: Value(assignedTo),
          notes: Value(notes),
          createdBy: Value(actor),
        ));
    await AuditRepo(db).log(
      action: 'asset.assign',
      entityType: 'عهدة أصل',
      summary: 'تسليم «${asset.name}» عهدةً إلى $beneficiaryUnitName',
      details: {'assetId': assetId, 'unit': beneficiaryUnitName},
      actorEmail: actor,
    );
    return (ok: true, error: '');
  }

  Future<void> returnAssignment(
    String assignmentId, {
    required String returnedDate,
    String actor = '',
  }) async {
    final rows = await (db.select(db.assetAssignments)
          ..where((t) => t.id.equals(assignmentId)))
        .get();
    if (rows.isEmpty) return;
    await (db.update(db.assetAssignments)..where((t) => t.id.equals(assignmentId)))
        .write(AssetAssignmentsCompanion(returnedDate: Value(returnedDate)));
    await AuditRepo(db).log(
      action: 'asset.return',
      entityType: 'عهدة أصل',
      summary: 'استرجاع «${rows.first.assetName}» من ${rows.first.beneficiaryUnitName}',
      details: {'assetId': rows.first.assetId},
      actorEmail: actor,
    );
  }

  // ───────────────────────── مؤشرات

  /// عدّادات لوحة الأصول: الإجمالي، وما خرج من الخدمة، وما قارب عمره الانقضاء.
  Future<({int total, int inService, int nearingEnd, int expired, double value})>
      summary({List<String>? scope}) async {
    final rows = await assets(scope: scope);
    var inService = 0;
    var nearing = 0;
    var expired = 0;
    var value = 0.0;
    for (final a in rows) {
      value += a.value;
      if (!AssetStatus.outOfService.contains(a.status)) inService++;
      switch (AssetRules.lifeOf(
        acquisitionDate: a.acquisitionDate,
        lifespanMonths: a.lifespanMonths,
      )) {
        case AssetLife.nearingEnd:
          nearing++;
        case AssetLife.expired:
          expired++;
        case AssetLife.healthy:
        case AssetLife.unknown:
          break;
      }
    }
    return (
      total: rows.length,
      inService: inService,
      nearingEnd: nearing,
      expired: expired,
      value: value,
    );
  }
}
