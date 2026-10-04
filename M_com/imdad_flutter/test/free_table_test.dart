import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/cable_print.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/cable_repo.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/domain/free_table.dart';

/// الجدول الحر في البرقية، ورقم فاتورة العقد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الجدول الحر: ترميز وفك وصيغة قديمة', () {
    final t = FreeTable(
      title: 'المرسَل إليهم',
      cols: const [FreeCol('الاسم', 6), FreeCol('الرتبة', 3), FreeCol('ملاحظة', 4)],
      rows: const [
        ['أحمد', 'رائد', ''],
        ['', '', ''],
      ],
    );
    final back = FreeTable.decode(t.encode());
    expect(back.title, 'المرسَل إليهم');
    expect(back.cols.map((c) => c.title), ['الاسم', 'الرتبة', 'ملاحظة']);
    expect(back.cols[0].weight, 6);
    expect(back.filledRows, [
      ['أحمد', 'رائد', '']
    ]);

    // الصيغة القديمة (قائمة name/unit/note) تُقرأ دون ضياع.
    final legacy = FreeTable.decode(CableRecipient.encode(const [CableRecipient(name: 'س', unit: 'شعبة')]));
    expect(legacy.cols.length, 3);
    expect(legacy.filledRows.first.take(2), ['س', 'شعبة']);
    expect(FreeTable.decode('ليس json').isEmpty, isTrue);
  });

  test('البرقية تُطبع بجدول حر وبدونه', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CableRepo(db);
    Future<Cable> make(String id, String json) async {
      await repo.insert(
        CablesCompanion(id: Value(id), subject: const Value('موضوع'), recipientsJson: Value(json)),
        actor: 't',
      );
      return (await repo.byId(id))!;
    }

    final withTable = await make(
        'a', FreeTable(cols: const [FreeCol('الجهة', 5), FreeCol('تاريخ الاستلام', 3)], rows: const [['شعبة', '2026']]).encode());
    final without = await make('b', '[]');
    expect(String.fromCharCodes((await CablePrint.build(db, withTable)).take(5)), '%PDF-');
    expect((await CablePrint.build(db, without)).isNotEmpty, isTrue);
  });

  test('رقم فاتورة العقد: من الرأس وإلا من أول صنف', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LinkageRepo(db);
    await repo.insertContract(LinkPurchaseContractsCompanion(
      id: const Value('h'),
      title: const Value('بهارات'),
      invoiceNo: const Value('446'),
    ));
    await repo.insertContract(LinkPurchaseContractsCompanion(
      id: const Value('i'),
      title: const Value('قديم'),
      itemsJson: Value(ContractItem.encode(const [ContractItem(name: 'ص', invoiceNo: 'A-7')])),
    ));
    final all = await repo.contracts();
    final h = all.firstWhere((c) => c.id == 'h');
    final old = all.firstWhere((c) => c.id == 'i');
    expect(h.displayInvoiceNo, '446');
    expect(h.matchesInvoice(' 446 '), isTrue);
    expect(old.displayInvoiceNo, 'A-7');
    expect(old.matchesInvoice('a-7'), isTrue);
    expect(old.matchesInvoice('446'), isFalse);
  });
}
