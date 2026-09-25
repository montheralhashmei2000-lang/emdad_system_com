import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/warehouse_limits_repo.dart';
import 'package:imdad/domain/warehouse_limits.dart';

/// حدود مخزون المستودعات.
///
/// الخطر هنا **وحدتان لرقم واحد**: الرصيد بوحدة الأساس والمستخدم يكتب بوحدة
/// التعامل. فخطأٌ في التحويل لا يُسقط شيئًا — يُظهر مخزونًا كافيًا وهو نافد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('التحويل بين الوحدات', () {
    test('الإدخال بالكرتون يُخزَّن بالحبة', () {
      // كرتون = ١٢ حبة، فـ٥ كراتين = ٦٠ حبة.
      expect(WarehouseLimits.toBase(5, 12), 60);
      expect(WarehouseLimits.fromBase(60, 12), 5);
    });

    test('معامل غير موجب يُعامَل ١ فلا تُقسم كمية على صفر', () {
      expect(WarehouseLimits.safeFactor(0), 1);
      expect(WarehouseLimits.safeFactor(-3), 1);
      expect(WarehouseLimits.fromBase(60, 0), 60);
      expect(WarehouseLimits.toBase(5, 0), 5);
    });

    test('الذهاب والإياب لا يُراكم كسرًا', () {
      for (final f in [1.0, 2.5, 12.0, 0.5, 33.0]) {
        final base = WarehouseLimits.toBase(7, f);
        expect(WarehouseLimits.fromBase(base, f), 7, reason: 'معامل $f');
      }
    });
  });

  group('الحكم على الرصيد', () {
    LimitStatus st(double bal, double min, double max) =>
        WarehouseLimits.statusOf(balance: bal, minStock: min, maxStock: max);

    test('بلا حدود لا حكم', () {
      expect(st(0, 0, 0), LimitStatus.none,
          reason: 'مستودع بلا حدّ لا يُنبَّه عليه كلما فرغ صنف لا يعني أحدًا');
    });

    test('تحت الأدنى', () => expect(st(5, 10, 100), LimitStatus.low));
    test('فوق الأعلى', () => expect(st(150, 10, 100), LimitStatus.over));
    test('ضمن الحدود', () => expect(st(50, 10, 100), LimitStatus.ok));

    test('الحد الأدنى بلا أعلى يحكم وحده', () {
      expect(st(5, 10, 0), LimitStatus.low);
      expect(st(50, 10, 0), LimitStatus.ok);
    });

    test('المساواة للأدنى ليست نقصًا', () {
      expect(st(10, 10, 100), LimitStatus.ok);
    });

    test('النقص والفائض يُحسبان', () {
      expect(WarehouseLimits.shortfall(balance: 4, minStock: 10), 6);
      expect(WarehouseLimits.shortfall(balance: 40, minStock: 10), 0);
      expect(WarehouseLimits.surplus(balance: 140, maxStock: 100), 40);
      expect(WarehouseLimits.surplus(balance: 40, maxStock: 100), 0);
    });

    test('نسبة الامتلاء تتجاوز ١ عند الفائض', () {
      expect(WarehouseLimits.fillRatio(balance: 50, maxStock: 100), 0.5);
      expect(WarehouseLimits.fillRatio(balance: 150, maxStock: 100), 1.5);
      expect(WarehouseLimits.fillRatio(balance: 5, maxStock: 0), isNull);
    });
  });

  group('التحقق قبل الحفظ', () {
    test('صنف بلا معرّف يُرفض', () {
      expect(WarehouseLimits.validate(itemId: '', min: 1, max: 2),
          contains('الصنف'));
    });

    test('حدّان صفران يُرفضان', () {
      expect(WarehouseLimits.validate(itemId: 'i1', min: 0, max: 0),
          contains('حدًّا واحدًا'));
    });

    test('الأعلى دون الأدنى يُرفض', () {
      expect(WarehouseLimits.validate(itemId: 'i1', min: 50, max: 10),
          contains('أقل من الأدنى'));
    });

    test('السالب يُرفض', () {
      expect(WarehouseLimits.validate(itemId: 'i1', min: -1, max: 10),
          contains('سالبة'));
    });

    test('حدٌّ واحد يكفي', () {
      expect(WarehouseLimits.validate(itemId: 'i1', min: 10, max: 0), isNull);
      expect(WarehouseLimits.validate(itemId: 'i1', min: 0, max: 10), isNull);
    });

    test('الصنف المكرر في الدفعة يُرفض', () {
      final err = WarehouseLimits.validateBatch([
        (itemId: 'i1', min: 5.0, max: 10.0),
        (itemId: 'i1', min: 7.0, max: 20.0),
      ]);
      expect(err, contains('مكرر'),
          reason: 'آخر سطر يدهس ما قبله صامتًا فلا يدري أيّهما بقي');
    });

    test('دفعة فارغة تُرفض', () {
      expect(WarehouseLimits.validateBatch([]), contains('سطرًا'));
    });
  });

  group('اللوحة على قاعدة حقيقية', () {
    late AppDatabase db;
    late WarehouseLimitsRepo repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = WarehouseLimitsRepo(db);
      await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1', name: 'الرئيسي', isMain: const Value(true)));
      await CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'رز',
        baseUnit: 'كجم',
        units: const [
          ItemUnit(name: 'كجم', factor: 1, isBase: true),
          ItemUnit(name: 'شوال', factor: 50),
        ],
      );
    });

    tearDown(() => db.close());

    Future<String> itemId() async => (await CatalogRepo(db).items()).single.id;

    Future<void> opening(double qty) async {
      await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
            id: Ids.next('ob'),
            itemId: await itemId(),
            warehouse: const Value('الرئيسي'),
            qty: Value(qty),
            date: const Value('2026-01-01'),
          ));
    }

    test('الحفظ بالشوال يُخزَّن بالكجم ويُعرض بالشوال', () async {
      final id = await itemId();
      final res = await repo.saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
            itemId: id,
            itemName: 'رز',
            unitName: 'شوال',
            factor: 50,
            min: 4,
            max: 20,
          ),
        ],
      );
      expect(res.ok, isTrue, reason: res.error);

      final stored = (await repo.limits()).single;
      expect(stored.minStock, 200, reason: '٤ شوالات = ٢٠٠ كجم');
      expect(stored.maxStock, 1000);

      await opening(300);
      final row = (await repo.dashboard('الرئيسي')).single;
      expect(row.min, 4, reason: 'يُعاد إلى صاحبه بالوحدة التي كتبها');
      expect(row.max, 20);
      expect(row.balance, 6, reason: '٣٠٠ كجم = ٦ شوالات');
      expect(row.status, LimitStatus.ok);
    });

    test('الرصيد دون الأدنى يظهر تحت الأدنى بالنقص الصحيح', () async {
      final id = await itemId();
      await repo.saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
            itemId: id,
            itemName: 'رز',
            unitName: 'شوال',
            factor: 50,
            min: 10,
            max: 0,
          ),
        ],
      );
      await opening(100); // شوالان
      final row = (await repo.dashboard('الرئيسي')).single;
      expect(row.status, LimitStatus.low);
      expect(row.shortfall, 8, reason: 'ينقصه ٨ شوالات لا ٤٠٠ كجم');
    });

    test('الحفظ مرتين يُحدّث ولا يُكرّر', () async {
      final id = await itemId();
      final row = LimitInput(
          itemId: id,
          itemName: 'رز',
          unitName: 'كجم',
          factor: 1,
          min: 10,
          max: 50);
      await repo.saveBatch(
          warehouseId: 'wh1', warehouseName: 'الرئيسي', rows: [row]);
      await repo.saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
              itemId: id,
              itemName: 'رز',
              unitName: 'كجم',
              factor: 1,
              min: 20,
              max: 80),
        ],
      );
      final all = await repo.limits();
      expect(all, hasLength(1), reason: 'ضبط الحد مرتين أنشأ سطرين');
      expect(all.single.minStock, 20);
    });

    test('لوحة مستودع لا حدود فيه فارغة', () async {
      expect(await repo.dashboard('الرئيسي'), isEmpty);
    });

    test('الأحرج يُعرض أولًا', () async {
      // يُلتقط معرّف الرز قبل إضافة صنف ثانٍ.
      final id = await itemId();
      await opening(100); // الرز سليم، والسكر تحت الأدنى (صفر)
      await CatalogRepo(db).saveItem(
        code: 'X2',
        name: 'سكر',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final sugar =
          (await CatalogRepo(db).items()).firstWhere((i) => i.code == 'X2');
      await repo.saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
              itemId: id,
              itemName: 'رز',
              unitName: 'كجم',
              factor: 1,
              min: 10,
              max: 0),
          LimitInput(
              itemId: sugar.id,
              itemName: 'سكر',
              unitName: 'كجم',
              factor: 1,
              min: 500,
              max: 0),
        ],
      );
      final rows = await repo.dashboard('الرئيسي');
      expect(rows.first.limit.itemName, 'سكر',
          reason: 'ما هو تحت الأدنى يُقرأ قبل ما هو سليم');
    });

    test('الحذف يزيل الحد وحده', () async {
      final id = await itemId();
      await repo.saveBatch(
        warehouseId: 'wh1',
        warehouseName: 'الرئيسي',
        rows: [
          LimitInput(
              itemId: id,
              itemName: 'رز',
              unitName: 'كجم',
              factor: 1,
              min: 10,
              max: 0),
        ],
      );
      final limit = (await repo.limits()).single;
      expect((await repo.delete(limit.id)).ok, isTrue);
      expect(await repo.limits(), isEmpty);
      expect((await CatalogRepo(db).items()), hasLength(1),
          reason: 'حذف الحد مسّ الصنف نفسه');
    });
  });
}
