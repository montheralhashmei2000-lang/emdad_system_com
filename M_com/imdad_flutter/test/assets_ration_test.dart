import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/assets_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/ration_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/domain/assets.dart';
import 'package:imdad/domain/ration_order.dart';

/// الأصول الثابتة وطلبيات الإعاشة — القواعد أولًا، ثم أثرها في المخزون.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('عمر الأصل', () {
    test('الشهور تُضاف بالتقويم لا بثلاثين يومًا', () {
      // ١٢ شهرًا من ١٥ يناير تنتهي ١٥ يناير التالي بالضبط. حساب ٣٠×١٢ يومًا
      // ينتهي في ١٠ يناير — خمسة أيام تُسقط أصلًا من قائمة «قارب الانتهاء».
      final expiry = AssetRules.expiryOf(acquisitionDate: '2025-01-15', lifespanMonths: 12);
      expect(expiry, DateTime(2026, 1, 15));
    });

    test('شهر واحد من آخر يناير لا يقع خارج فبراير', () {
      final expiry = AssetRules.expiryOf(acquisitionDate: '2025-01-31', lifespanMonths: 1);
      expect(expiry!.month, 3, reason: 'DateTime ينقل الفائض إلى الشهر التالي');
    });

    test('بلا تاريخ أو بلا عمر ⇒ لا حكم', () {
      expect(
        AssetRules.lifeOf(acquisitionDate: '', lifespanMonths: 12),
        AssetLife.unknown,
      );
      expect(
        AssetRules.lifeOf(acquisitionDate: '2025-01-01', lifespanMonths: 0),
        AssetLife.unknown,
      );
    });

    test('الحالات الثلاث تُميَّز بحدودها', () {
      final now = DateTime(2026, 1, 1);
      expect(
        AssetRules.lifeOf(acquisitionDate: '2025-01-01', lifespanMonths: 24, now: now),
        AssetLife.healthy,
      );
      expect(
        AssetRules.lifeOf(acquisitionDate: '2025-01-15', lifespanMonths: 12, now: now),
        AssetLife.nearingEnd,
      );
      expect(
        AssetRules.lifeOf(acquisitionDate: '2024-01-01', lifespanMonths: 12, now: now),
        AssetLife.expired,
      );
    });

    test('الباركود يثبت للأصل ولو لم يكن له رقم تسلسلي', () {
      final a = AssetRules.barcodeOf(id: 'ast-abc-123456', serialNumber: '');
      final b = AssetRules.barcodeOf(id: 'ast-abc-123456', serialNumber: '');
      expect(a, b);
      expect(a, startsWith('AST-'));
      expect(AssetRules.barcodeOf(id: 'ast-x', serialNumber: 'SN-9'), 'SN-9');
    });

    test('أصل بلا موضع مرفوض', () {
      expect(AssetRules.validatePlacement(), isNotNull);
      expect(AssetRules.validatePlacement(warehouse: 'الرئيسي'), isNull);
    });
  });

  group('عهد الأصول', () {
    Future<String> newAsset({String status = AssetStatus.isNew}) =>
        AssetsRepo(db).save(name: 'فرن غاز', assetType: AssetType.oven, status: status);

    test('لا تُسلَّم عهدة على أصل تالف', () async {
      final id = await newAsset(status: AssetStatus.damaged);
      final res = await AssetsRepo(db).assign(
        assetId: id,
        beneficiaryUnitId: 'u1',
        beneficiaryUnitName: 'السرية الأولى',
        assignedDate: '2026-01-01',
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('تالف'));
    });

    test('لا عهدتان على أصل واحد', () async {
      final repo = AssetsRepo(db);
      final id = await newAsset();
      expect(
        (await repo.assign(
          assetId: id,
          beneficiaryUnitId: 'u1',
          beneficiaryUnitName: 'الأولى',
          assignedDate: '2026-01-01',
        ))
            .ok,
        isTrue,
      );
      final second = await repo.assign(
        assetId: id,
        beneficiaryUnitId: 'u2',
        beneficiaryUnitName: 'الثانية',
        assignedDate: '2026-01-02',
      );
      expect(second.ok, isFalse, reason: 'سُلّم أصل هو في عهدة قائمة');
    });

    test('لا يُحذف أصل في عهدة، ويُحذف بعد استرجاعه', () async {
      final repo = AssetsRepo(db);
      final id = await newAsset();
      await repo.assign(
        assetId: id,
        beneficiaryUnitId: 'u1',
        beneficiaryUnitName: 'الأولى',
        assignedDate: '2026-01-01',
      );
      expect((await repo.delete(id)).ok, isFalse);

      final open = await repo.openAssignment(id);
      await repo.returnAssignment(open!.id, returnedDate: '2026-02-01');
      expect((await repo.delete(id)).ok, isTrue);
    });

    test('الرقم التسلسلي لا يتكرر بين أصلين', () async {
      final repo = AssetsRepo(db);
      await repo.save(name: 'فرن', assetType: AssetType.oven, serialNumber: 'SN-1');
      expect(await repo.serialTaken('SN-1'), isTrue);
      expect(await repo.serialTaken(''), isFalse, reason: 'الفراغ ليس تكرارًا');
    });
  });

  group('دورة طلبية الإعاشة', () {
    test('الاستلام لا يقع إلا على معتمدة', () {
      expect(RationRules.canReceive(RationStatus.pending), isFalse);
      expect(RationRules.canReceive(RationStatus.approved), isTrue);
      expect(RationRules.next(RationStatus.pending, 'receive'), isNull);
      expect(RationRules.next(RationStatus.approved, 'receive'), RationStatus.received);
    });

    test('المستودع الطالب لا يكون هو المورِّد', () {
      expect(
        RationRules.validateWarehouses(requesting: 'أ', supplying: 'أ'),
        isNotNull,
      );
      expect(RationRules.validateWarehouses(requesting: 'أ', supplying: 'ب'), isNull);
    });

    test('صنف مكرر في الطلبية مرفوض', () {
      final lines = [
        const RationLineDraft(itemId: 'i1', requestedQty: 5),
        const RationLineDraft(itemId: 'i1', requestedQty: 3),
      ];
      expect(RationRules.validateLines(lines), contains('مكرر'));
    });

    test('الكمية المعتمدة لا تتجاوز المطلوبة', () {
      expect(
        RationRules.validateApproved(
          [const RationLineDraft(itemId: 'i1', requestedQty: 5, approvedQty: 7)],
        ),
        isNotNull,
      );
      expect(
        RationRules.validateApproved(
          [const RationLineDraft(itemId: 'i1', requestedQty: 5, approvedQty: 5)],
        ),
        isNull,
      );
    });
  });

  group('أثر الطلبية في المخزون', () {
    Future<String> seed() async {
      await CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'دقيق',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final item = (await CatalogRepo(db).items()).single;
      final res = await RationRepo(db).save(
        requestingWarehouse: 'الفرع',
        supplyingWarehouse: 'الرئيسي',
        date: '2026-01-01',
        lines: [
          RationLineInput(
            itemId: item.id,
            itemCode: item.code,
            itemName: item.name,
            unitName: 'كجم',
            factor: 1,
            requestedQty: 100,
          ),
        ],
      );
      expect(res.ok, isTrue, reason: res.error);
      return (await RationRepo(db).orders()).single.id;
    }

    test('الاستلام يولّد سند استلام حقيقي لا تعليمًا على ورقة', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      await repo.approve(id);
      final res = await repo.receive(id, actor: 'admin@imdad.local');

      expect(res.ok, isTrue, reason: res.error);
      final receipts = await db.select(db.receipts).get();
      expect(receipts, hasLength(1), reason: 'استُلمت الطلبية بلا حركة مخزنية');
      expect(receipts.single.warehouse, 'الفرع');
      expect(receipts.single.qty, 100);

      final order = (await repo.byId(id))!.order;
      expect(order.status, RationStatus.received);
      expect(order.receiptRef, receipts.single.refNo,
          reason: 'الطلبية لا تشير إلى سندها');
    });

    test('الاستلام قبل الاعتماد يُرفض ولا يحرّك رصيدًا', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      final res = await repo.receive(id);

      expect(res.ok, isFalse);
      expect(await db.select(db.receipts).get(), isEmpty);
    });

    test('الاعتماد بكمية أقل يُستلم بالمعتمدة لا بالمطلوبة', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      final lineId = (await repo.byId(id))!.lines.single.id;
      await repo.approve(id, approved: {lineId: 60});
      await repo.receive(id);

      expect((await db.select(db.receipts).get()).single.qty, 60);
    });

    test('لا تُحذف طلبية مستلمة — أثرها المخزني قائم', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      await repo.approve(id);
      await repo.receive(id);
      expect((await repo.delete(id)).ok, isFalse);
    });
  });

  group('الجداول الجديدة داخل المزامنة', () {
    test('الأربعة مسجّلة، فلا تبقى بياناتها حبيسة جهازها', () {
      for (final t in ['assets', 'asset_assignments', 'ration_orders', 'ration_order_lines']) {
        expect(SyncMarks.entities.containsKey(t), isTrue, reason: '$t خارج المزامنة');
      }
    });

    test('إنشاء أصل يكتب له علامة تغيير', () async {
      final id = await AssetsRepo(db).save(name: 'خزان ماء', assetType: AssetType.equipment);
      final marks = await SyncMarks(db).changedSince(0);
      expect(
        marks.where((m) => m.entity == 'assets').map((m) => m.rowId),
        contains(id),
      );
    });
  });
}
