import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// حواجز الكميات في القاعدة، وفحص الرصيد داخل معاملة الحفظ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
  });

  tearDown(() => db.close());

  DocLineInput line(String id, double qty) => DocLineInput(
        itemId: id,
        itemCode: 'X1',
        itemName: 'دقيق',
        unitName: 'كجم',
        factor: 1,
        qty: qty,
      );

  Future<String> seedItem() => CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'دقيق',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

  group('حواجز الكميات', () {
    test('كمية سالبة في سند وارد تُرفض من القاعدة نفسها', () async {
      final bad = ReceiptsCompanion.insert(
        id: 'r1',
        qty: const Value(-5),
        baseQty: const Value(-5),
      );
      await expectLater(db.into(db.receipts).insert(bad), throwsA(anything));
    });

    test('تعديل كمية موجودة إلى سالبة يُرفض', () async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r1',
            qty: const Value(5),
            baseQty: const Value(5),
          ));
      await expectLater(
        (db.update(db.receipts)..where((t) => t.id.equals('r1')))
            .write(const ReceiptsCompanion(baseQty: Value(-1))),
        throwsA(anything),
      );
    });

    test('رصيد افتتاحي سالب يُرفض، والتسوية السالبة تبقى مسموحة', () async {
      await expectLater(
        db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(id: 'o1', itemId: 'i', qty: const Value(-1))),
        throwsA(anything),
      );
      await db.into(db.adjustments).insert(AdjustmentsCompanion.insert(
            id: 'a1',
            qty: const Value(-3),
            baseQty: const Value(-3),
          ));
    });
  });

  group('فحص الرصيد داخل المعاملة', () {
    test('صرف يفوق الرصيد يُرفض ولا يُكتب منه شيء', () async {
      final id = await seedItem();
      await mv.saveReceipt(warehouse: 'م1', supplier: 's', date: '2026-01-01', lines: [line(id, 10)]);

      final res = await mv.saveIssue(
        warehouse: 'م1',
        recipientDisplay: 'وحدة',
        date: '2026-01-02',
        lines: [line(id, 11)],
      );
      expect(res.ok, isFalse);
      expect(await db.select(db.issues).get(), isEmpty);
    });

    test('صرفان متزامنان على رصيد يكفي أحدهما فقط: ينجح واحد ويفشل الآخر', () async {
      final id = await seedItem();
      await mv.saveReceipt(warehouse: 'م1', supplier: 's', date: '2026-01-01', lines: [line(id, 10)]);

      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          mv.saveIssue(
            warehouse: 'م1',
            recipientDisplay: 'وحدة $i',
            date: '2026-01-02',
            lines: [line(id, 8)],
          ),
      ]);
      expect(results.where((r) => r.ok), hasLength(1));
      expect((await mv.ledger()).balanceOf(id, warehouse: 'م1'), 2);
    });
  });

  group('تقريب الكميات إلى ثلاث خانات', () {
    test('كسر عائم يُقرَّب فور كتابته', () async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r1',
            qty: const Value(0.1 + 0.2),
            baseQty: const Value(0.30000000000000004),
          ));
      final row = await (db.select(db.receipts)..where((t) => t.id.equals('r1'))).getSingle();
      expect(row.qty, 0.3);
      expect(row.baseQty, 0.3);
    });

    test('التعديل يُقرَّب كذلك، والتسويات تُقرَّب وتبقى سالبة', () async {
      await db.into(db.adjustments).insert(AdjustmentsCompanion.insert(id: 'a1', qty: const Value(-1), baseQty: const Value(-1)));
      await (db.update(db.adjustments)..where((t) => t.id.equals('a1')))
          .write(const AdjustmentsCompanion(baseQty: Value(-2.00049)));
      final row = await (db.select(db.adjustments)..where((t) => t.id.equals('a1'))).getSingle();
      expect(row.baseQty, -2.0);
    });

    test('الرصيد المحسوب لا يحمل ضجيج الفاصلة العائمة', () async {
      final id = await seedItem();
      for (var i = 0; i < 10; i++) {
        await mv.saveReceipt(warehouse: 'م1', supplier: 's', date: '2026-01-01', lines: [line(id, 0.1)]);
      }
      expect((await mv.ledger()).balanceOf(id, warehouse: 'م1'), 1.0);
    });
  });

  group('حماية الأصناف ذات الحركات', () {
    test('حذف صنف له حركات يُرفض برسالة واضحة', () async {
      final id = await seedItem();
      await mv.saveReceipt(warehouse: 'م1', supplier: 's', date: '2026-01-01', lines: [line(id, 1)]);
      await expectLater(CatalogRepo(db).deleteItem(id), throwsA(isA<StateError>()));
      expect(await db.select(db.items).get(), hasLength(1));
    });

    test('المشغّل يحرس القاعدة حتى لو تجاوز المسارُ المستودع', () async {
      final id = await seedItem();
      await mv.saveReceipt(warehouse: 'م1', supplier: 's', date: '2026-01-01', lines: [line(id, 1)]);
      await expectLater(db.customStatement('DELETE FROM items WHERE id = ?', [id]), throwsA(anything));
    });

    test('صنف بلا حركات يُحذف عادةً', () async {
      final id = await seedItem();
      await CatalogRepo(db).deleteItem(id);
      expect(await db.select(db.items).get(), isEmpty);
    });
  });

  group('الاستيراد لا يُجهَض بسجل معيب', () {
    test('سطر سالب يُتجاوز مع تحذير ويدخل السليم', () async {
      final res = await LegacyImporter(db).importJson({
        'receipts': [
          {'id': 'bad', 'qty': -4, 'baseQty': -4, 'factor': 1, 'itemId': 'i'},
          {'id': 'good', 'qty': 4, 'baseQty': 4, 'factor': 1, 'itemId': 'i'},
        ],
      });
      final ids = (await db.select(db.receipts).get()).map((r) => r.id).toList();
      expect(ids, ['good']);
      expect(res.warnings.any((w) => w.contains('bad')), isTrue);
    });
  });
}
