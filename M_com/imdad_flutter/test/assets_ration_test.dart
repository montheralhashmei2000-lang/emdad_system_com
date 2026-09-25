import 'package:drift/drift.dart' show Value;
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

  group('مسار الطلبية: من يطلب ممّن', () {
    Future<void> warehouses() async {
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
      await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرع'));
    }

    List<RationLineInput> oneLine() => const [
          RationLineInput(
            itemId: 'i1',
            itemCode: 'X1',
            itemName: 'دقيق',
            unitName: 'كجم',
            factor: 1,
            requestedQty: 10,
          ),
        ];

    test('بلا مخزن رئيسي لا تُبنى طلبية — المسار مجهول', () async {
      final res = await RationRepo(db).save(
        requestingWarehouse: 'الفرع',
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('مخزن رئيسي'));
    });

    test('المخزن الفرعي يطلب من الرئيسي تلقائيًّا', () async {
      await warehouses();
      final res = await RationRepo(db).save(
        requestingWarehouse: 'الفرع',
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isTrue, reason: res.error);
      final o = (await RationRepo(db).orders()).single;
      expect(o.supplyingWarehouse, 'الرئيسي',
          reason: 'المطلوب منه يُملأ عن الفرع لا يُترك لاختياره');
      expect(o.orderKind, RationKind.branch);
    });

    test('المخزن الرئيسي لا يطلب من نفسه كفرع', () async {
      await warehouses();
      final res = await RationRepo(db).save(
        requestingWarehouse: 'الرئيسي',
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('لا يطلب من نفسه'));
    });

    test('طلبية المخزن الرئيسي بلا جهة تُرفض', () async {
      await warehouses();
      final res = await RationRepo(db).save(
        kind: RationKind.main,
        requestingWarehouse: 'الرئيسي',
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('الجهة'));
    });

    test('طلبية المخزن الرئيسي تُبنى بجهة ولا مستودع مورِّد لها', () async {
      await warehouses();
      final auth = await RationRepo(db)
          .saveAuthority(name: 'ركن إمداد الفرقة', title: 'ركن إمداد');
      final res = await RationRepo(db).save(
        kind: RationKind.main,
        requestingWarehouse: 'الرئيسي',
        authorityId: auth.refNo,
        authorityName: 'ركن إمداد الفرقة',
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isTrue, reason: res.error);
      final o = (await RationRepo(db).orders()).single;
      expect(o.orderKind, RationKind.main);
      expect(o.authorityName, 'ركن إمداد الفرقة');
      expect(o.supplyingWarehouse, isEmpty,
          reason: 'الجهة ليست مستودعًا — لا رصيد لها ولا حركة عليها');
    });

    test('غير الرئيسي لا يفتح طلبية جهة', () async {
      await warehouses();
      final auth = await RationRepo(db).saveAuthority(name: 'قائد الفرقة');
      final res = await RationRepo(db).save(
        kind: RationKind.main,
        requestingWarehouse: 'الفرع',
        authorityId: auth.refNo,
        date: '2026-01-01',
        lines: oneLine(),
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('يطلبها'));
    });
  });

  group('دليل الجهات', () {
    test('الاسم المكرر يُرفض', () async {
      final repo = RationRepo(db);
      expect((await repo.saveAuthority(name: 'ركن الإمداد')).ok, isTrue);
      final again = await repo.saveAuthority(name: 'ركن الإمداد');
      expect(again.ok, isFalse);
    });

    test('الجهة التي عليها طلبيات تُعطَّل ولا تُحذف', () async {
      final repo = RationRepo(db);
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
      final auth = await repo.saveAuthority(name: 'رئيس الشعبة');
      await repo.save(
        kind: RationKind.main,
        requestingWarehouse: 'الرئيسي',
        authorityId: auth.refNo,
        date: '2026-01-01',
        lines: const [
          RationLineInput(
            itemId: 'i1',
            itemCode: 'X1',
            itemName: 'دقيق',
            unitName: 'كجم',
            factor: 1,
            requestedQty: 10,
          ),
        ],
      );
      final res = await repo.deleteAuthority(auth.refNo);
      expect(res.ok, isFalse);
      expect(res.error, contains('عطّلها'));
    });
  });

  group('الطلبية لا تحرّك المخزون', () {
    Future<String> seed() async {
      await CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'دقيق',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final item = (await CatalogRepo(db).items()).single;
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
      await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرع'));
      final res = await RationRepo(db).save(
        requestingWarehouse: 'الفرع',
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

    test('التنفيذ يربط بمستندٍ قائم ولا يولّد سندًا', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      await repo.approve(id);
      final res = await repo.linkTransfer(id, transferRef: 'ح-000007');

      expect(res.ok, isTrue, reason: res.error);
      // هذا هو جوهر التغيير: كان التنفيذ يولّد سند استلام بلا أن يُنقص أحدًا،
      // فيزيد مخزون النظام من العدم كلما حُوِّلت بضاعة بين مستودعين.
      expect(await db.select(db.receipts).get(), isEmpty,
          reason: 'الطلبية أنشأت حركة مخزنية — وهي طلبٌ لا حركة');
      expect(await db.select(db.transfers).get(), isEmpty,
          reason: 'سند التحويل يُنشئه أمين المخزن لا الطلبية');

      final order = (await repo.byId(id))!.order;
      expect(order.status, RationStatus.received);
      expect(order.fulfillRef, 'ح-000007');
      expect(order.fulfillKind, RationFulfillKind.transfer);
    });

    test('التنفيذ قبل الاعتماد يُرفض', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      final res = await repo.linkTransfer(id, transferRef: 'ح-1');
      expect(res.ok, isFalse);
      expect((await repo.byId(id))!.order.fulfillRef, isEmpty);
    });

    test('التنفيذ بلا مرجع مستند يُرفض', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      await repo.approve(id);
      expect((await repo.linkTransfer(id, transferRef: '  ')).ok, isFalse);
    });

    test('المنفَّذ هو المعتمد لا المطلوب', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      final lineId = (await repo.byId(id))!.lines.single.id;
      await repo.approve(id, approved: {lineId: 60});
      await repo.linkTransfer(id, transferRef: 'ح-2');

      final line = (await repo.byId(id))!.lines.single;
      expect(line.receivedQty, 60);
      expect(line.requestedQty, 100, reason: 'المطلوب يبقى ليُعرف حجم العجز');
    });

    test('طلبية الرئيسي تُطابَق بسند توريد لا بتحويل', () async {
      final repo = RationRepo(db);
      await CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'دقيق',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
      final auth = await repo.saveAuthority(name: 'ركن إمداد الفرقة');
      await repo.save(
        kind: RationKind.main,
        requestingWarehouse: 'الرئيسي',
        authorityId: auth.refNo,
        authorityName: 'ركن إمداد الفرقة',
        date: '2026-01-01',
        lines: const [
          RationLineInput(
            itemId: 'i1',
            itemCode: 'X1',
            itemName: 'دقيق',
            unitName: 'كجم',
            factor: 1,
            requestedQty: 500,
          ),
        ],
      );
      final id = (await repo.orders()).single.id;
      await repo.submit(id);
      expect((await repo.awaitingReceiptMatch()), isEmpty,
          reason: 'لم تُعتمد بعد');
      await repo.approve(id);
      expect((await repo.awaitingReceiptMatch()).single.id, id);

      await repo.matchReceipt(id, receiptRef: 'و-000012');
      final o = (await repo.byId(id))!.order;
      expect(o.fulfillKind, RationFulfillKind.receipt);
      expect(await db.select(db.receipts).get(), isEmpty,
          reason: 'المطابقة ربطٌ بسندٍ قائم لا إنشاءٌ له');
    });

    test('readyForTransfer تُظهر المعتمدة للمخزن المورِّد وحده', () async {
      final repo = RationRepo(db);
      final id = await seed();
      expect(await repo.readyForTransfer('الرئيسي'), isEmpty,
          reason: 'المسودة ليست جاهزة');
      await repo.submit(id);
      expect(await repo.readyForTransfer('الرئيسي'), isEmpty,
          reason: 'المرسلة لم يأذن بها أحد');
      await repo.approve(id);

      final ready = await repo.readyForTransfer('الرئيسي');
      expect(ready.single.order.id, id);
      expect(ready.single.lines.single.approvedQty, 100);
      expect(await repo.readyForTransfer('الفرع'), isEmpty,
          reason: 'الفرع ليس مَن يحوّل');
    });

    test('لا تُحذف طلبية منفَّذة — سندها قائم', () async {
      final repo = RationRepo(db);
      final id = await seed();
      await repo.submit(id);
      await repo.approve(id);
      await repo.linkTransfer(id, transferRef: 'ح-3');
      expect((await repo.delete(id)).ok, isFalse);
    });
  });

  group('الجداول الجديدة داخل المزامنة', () {
    test('الخمسة مسجّلة، فلا تبقى بياناتها حبيسة جهازها', () {
      for (final t in [
        'assets',
        'asset_assignments',
        'ration_orders',
        'ration_order_lines',
        'supply_authorities',
      ]) {
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
