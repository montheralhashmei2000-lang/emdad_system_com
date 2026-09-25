import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/alerts_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/domain/stock_alerts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime(2026, 9, 20);

  ExpiryLot lot(String received, String expiry, double qty, {String wh = 'W'}) =>
      ExpiryLot(warehouse: wh, itemId: 'milk', receivedOn: received, expiryDate: expiry, baseQty: qty);

  group('الحد الأدنى', () {
    test('الحد صفر = لا تنبيه، والرصيد عند الحد تمامًا ينبّه', () {
      expect(StockAlerts.isLow(0, 0), isFalse);
      expect(StockAlerts.isLow(10, 10), isTrue);
      expect(StockAlerts.isLow(11, 10), isFalse);
    });

    test('الأشد نقصًا نسبةً إلى حده أولًا', () {
      final out = StockAlerts.lowStock(
        const [(id: 'a', minQty: 100), (id: 'b', minQty: 10), (id: 'c', minQty: 5)],
        {'a': 50, 'b': 1, 'c': 20},
      );
      expect([for (final a in out) a.itemId], ['b', 'a']);
      expect(out.first.shortfall, 9);
    });
  });

  group('قرب انتهاء الصلاحية (الوارد أولًا يُصرف أولًا)', () {
    test('الدفعة القديمة المستهلكة لا تنبّه', () {
      // استُلم 10 قديمة و10 حديثة، والرصيد 10 ⇒ الباقي هو الحديثة.
      final out = StockAlerts.expiring(
        lots: [lot('2026-08-01', '2026-09-25', 10), lot('2026-09-10', '2027-01-01', 10)],
        balances: {'W': {'milk': 10}},
        today: today,
      );
      expect(out, isEmpty);
    });

    test('الجزء الباقي من دفعة قديمة ينبّه بكميته فقط', () {
      final out = StockAlerts.expiring(
        lots: [lot('2026-08-01', '2026-09-25', 10), lot('2026-09-10', '2027-01-01', 10)],
        balances: {'W': {'milk': 14}},
        today: today,
      );
      expect(out.single.remainingQty, 4);
      expect(out.single.daysLeft, 5);
    });

    test('المنتهية تظهر بأيام سالبة، والأقرب انتهاءً أولًا', () {
      final out = StockAlerts.expiring(
        lots: [lot('2026-09-01', '2026-09-28', 5), lot('2026-08-01', '2026-09-18', 5)],
        balances: {'W': {'milk': 10}},
        today: today,
      );
      expect([for (final a in out) a.daysLeft], [-2, 8]);
      expect(out.first.expired, isTrue);
    });

    test('وارد أحدث بلا صلاحية يأخذ نصيبه من الرصيد أولًا', () {
      final out = StockAlerts.expiring(
        lots: [lot('2026-08-01', '2026-09-25', 10), lot('2026-09-15', '', 10)],
        balances: {'W': {'milk': 10}},
        today: today,
      );
      expect(out, isEmpty);
    });

    test('خارج المدة لا ينبّه', () {
      final out = StockAlerts.expiring(
        lots: [lot('2026-09-01', '2026-12-01', 5)],
        balances: {'W': {'milk': 5}},
        today: today,
        withinDays: 30,
      );
      expect(out, isEmpty);
    });
  });

  group('AlertsRepo', () {
    late AppDatabase db;
    late MovementsRepo mv;
    late String milk;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      mv = MovementsRepo(db);
      final catalog = CatalogRepo(db);
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await catalog.saveWarehouse(code: 'W2', name: 'الفرعي');
      milk = await catalog.saveItem(
        code: 'M1',
        name: 'حليب',
        baseUnit: 'علبة',
        units: const [ItemUnit(name: 'علبة', factor: 1, isBase: true)],
        minQty: 20,
      );
    });

    tearDown(() => db.close());

    DocLineInput line(double qty, {String expiry = ''}) => DocLineInput(
        itemId: milk, itemCode: 'M1', itemName: 'حليب', unitName: 'علبة', factor: 1, qty: qty, expiryDate: expiry);

    test('تاريخ الصلاحية يُحفظ مع السطر، والصرف يُنقص الدفعة الأقدم', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-08-01', lines: [line(30, expiry: '2026-09-25')]);
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-10', lines: [line(30, expiry: '2027-03-01')]);
      expect((await db.select(db.receipts).get()).first.expiryDate, '2026-09-25');

      var alerts = await AlertsRepo(db).expiring(today: today);
      expect(alerts.single.remainingQty, 30);

      await mv.saveIssue(warehouse: 'الرئيسي', recipientDisplay: 'س', date: '2026-09-15', lines: [line(25)]);
      alerts = await AlertsRepo(db).expiring(today: today);
      expect(alerts.single.remainingQty, 5, reason: 'صُرف 25 من الدفعة الأقدم');
    });

    test('نطاق المستخدم يحصر الحد الأدنى والصلاحية', () async {
      await mv.saveReceipt(
          warehouse: 'الفرعي', supplier: 'م', date: '2026-09-01', lines: [line(5, expiry: '2026-09-22')]);

      expect((await AlertsRepo(db).lowStock()).single.balance, 5);
      expect(await AlertsRepo(db).expiring(today: today), hasLength(1));
      expect(await AlertsRepo(db).expiring(scope: ['الرئيسي'], today: today), isEmpty);
      expect((await AlertsRepo(db).lowStock(scope: ['الرئيسي'])).single.outOfStock, isTrue);
    });
  });

  test('الترقية من v11 تضيف أعمدة v12 وv13 ولا تمس السندات القائمة', () async {
    final dir = await Directory.systemTemp.createTemp('imdad_mig');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // قاعدة بصيغة v11: بلا العمود الجديد وبسند قائم.
    final v8 = AppDatabase.forTesting(NativeDatabase(file));
    await v8.customStatement("INSERT INTO receipts (id, ref_no, base_qty) VALUES ('r1', 'و-000001', 4)");
    await v8.customStatement('ALTER TABLE receipts DROP COLUMN expiry_date');
    // وأعمدة v13 (حالة الأسطوانات في التحويل والمرتجع): الترقية تمر بالخطوتين.
    await v8.customStatement('ALTER TABLE transfers DROP COLUMN cylinder_action');
    await v8.customStatement('ALTER TABLE "returns" DROP COLUMN cylinder_action');
    await v8.customStatement('PRAGMA user_version = 11');
    await v8.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);
    final r = await upgraded.select(upgraded.receipts).getSingle();
    expect(r.refNo, 'و-000001');
    expect(r.expiryDate, '');
    await upgraded.customStatement("INSERT INTO transfers (id, cylinder_action) VALUES ('t1', 'TRANSFER_FULL')");
    expect((await upgraded.select(upgraded.transfers).getSingle()).cylinderAction, 'TRANSFER_FULL');
  });
}
