import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// حراسة عيب حقيقي ظهر في الاختبار: المعرّف المبني على الوقت وحده يتكرر
/// حين يُكتب سجلّان في الملّي ثانية نفسها، فيطمس أحدهما الآخر.
void main() {
  test('عشرة آلاف معرّف متتالٍ بلا تكرار', () {
    final ids = <String>{};
    for (var i = 0; i < 10000; i++) {
      ids.add(Ids.next('x'));
    }
    expect(ids.length, 10000);
  });

  test('سجلّان يُحفظان في اللحظة نفسها يبقيان سجلّين', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final catalog = CatalogRepo(db);

    // حفظ متتالٍ بلا أي فاصل زمني — هذا ما كان يُسقط أحد السجلين.
    await catalog.saveUnit(code: 'C1', name: 'معسكر أ', type: 'camp');
    await catalog.saveUnit(code: 'U1', name: 'كتيبة أ', type: 'unit');
    await catalog.saveUnit(code: 'U2', name: 'كتيبة ب', type: 'unit');

    final units = await catalog.units();
    expect(units.map((u) => u.name).toSet(), {'معسكر أ', 'كتيبة أ', 'كتيبة ب'});
  });

  test('سند بعدة أصناف يحفظ كل سطوره', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final catalog = CatalogRepo(db);
    final moves = MovementsRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'المخزن الرئيسي');

    final lines = <DocLineInput>[];
    for (var i = 1; i <= 25; i++) {
      final id = await catalog.saveItem(
        code: 'I$i',
        name: 'صنف $i',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      lines.add(DocLineInput(
        itemId: id,
        itemCode: 'I$i',
        itemName: 'صنف $i',
        unitName: 'كجم',
        factor: 1,
        qty: i.toDouble(),
      ));
    }

    final res = await moves.saveReceipt(
      warehouse: 'المخزن الرئيسي',
      supplier: 'مورد',
      date: '2026-09-17',
      lines: lines,
    );
    expect(res.ok, isTrue, reason: res.error);

    final saved = await db.select(db.receipts).get();
    expect(saved.length, 25);
    final balances = await moves.balances(warehouse: 'المخزن الرئيسي');
    expect(balances.length, 25);
  });
}
