import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/documents_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// سجل المستندات (`documents-center.js`): التعديل يستبدل السطور ويطبّق الفرق فقط،
/// والإلغاء يعكس الأثر ويحفظ الحالة السابقة وسببها.
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late MovementsRepo mv;
  late DocumentsRepo docs;
  late String riceId;
  late String oilId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    mv = MovementsRepo(db);
    docs = DocumentsRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    riceId = await catalog.saveItem(
      code: '1',
      name: 'أرز',
      units: const [ItemUnit(name: 'كيس', factor: 1, isBase: true)],
    );
    oilId = await catalog.saveItem(
      code: '2',
      name: 'زيت',
      units: const [ItemUnit(name: 'لتر', factor: 1, isBase: true)],
    );
  });

  tearDown(() => db.close());

  DocLineInput line(String id, String code, String name, double qty) =>
      DocLineInput(itemId: id, itemCode: code, itemName: name, unitName: 'كيس', factor: 1, qty: qty);

  Future<DocumentSummary> firstDoc() async => (await docs.list()).first;

  test('تعديل سند استلام: استبدال كامل للسطور وتطبيق الفرق على الرصيد', () async {
    final saved = await mv.saveReceipt(
      warehouse: 'الرئيسي',
      supplier: 'مؤسسة الخير',
      date: '2026-09-10',
      lines: [line(riceId, '1', 'أرز', 100)],
      createdBy: 'admin',
    );
    expect(saved.ok, isTrue);

    final doc = await firstDoc();
    final check = await docs.saveEdit(
      doc: doc,
      rows: [
        DocumentLineRow(
          id: '',
          itemId: riceId,
          itemCode: '1',
          itemName: 'أرز',
          unitName: 'كيس',
          factor: 1,
          qty: 80,
          baseQty: 80,
        ),
        DocumentLineRow(
          id: '',
          itemId: oilId,
          itemCode: '2',
          itemName: 'زيت',
          unitName: 'لتر',
          factor: 1,
          qty: 25,
          baseQty: 25,
        ),
      ],
      reason: 'فرق في الفاتورة',
      availableBaseQty: await mv.balances(),
      date: '2026-09-11',
      warehouse: 'الرئيسي',
      party: 'مؤسسة النور',
      actor: 'admin@imdad',
    );
    expect(check.ok, isTrue);

    final after = await firstDoc();
    expect(after.linesCount, 2);
    expect(after.date, '2026-09-11');
    expect(after.party, 'مؤسسة النور');
    expect(after.editCount, 1);
    expect(after.editLog.single.summary, contains('فرق في الفاتورة'));

    final balances = await mv.balances();
    expect(balances[riceId], 80);
    expect(balances[oilId], 25);
  });

  test('التعديل يُرفض إذا جعل رصيد صنف سالبًا', () async {
    await mv.saveReceipt(
      warehouse: 'الرئيسي',
      supplier: 'مؤسسة الخير',
      date: '2026-09-10',
      lines: [line(riceId, '1', 'أرز', 50)],
    );
    final receipt = await firstDoc();
    await mv.saveIssue(
      warehouse: 'الرئيسي',
      recipientDisplay: 'الكتيبة الأولى',
      date: '2026-09-12',
      lines: [line(riceId, '1', 'أرز', 40)],
    );

    // تخفيض الاستلام إلى 20 يترك رصيدًا سالبًا لأن المصروف 40.
    final check = await docs.saveEdit(
      doc: receipt,
      rows: [
        DocumentLineRow(
          id: '',
          itemId: riceId,
          itemCode: '1',
          itemName: 'أرز',
          unitName: 'كيس',
          factor: 1,
          qty: 20,
          baseQty: 20,
        ),
      ],
      reason: 'تصحيح',
      availableBaseQty: await mv.balances(),
      date: receipt.date,
      warehouse: receipt.warehouse,
      party: receipt.party,
    );
    expect(check.ok, isFalse);
    expect(check.itemId, riceId);
    expect((await mv.balances())[riceId], 10);
  });

  test('الإلغاء يعكس الأثر ويحفظ الحالة السابقة والسبب وسجل التعديل', () async {
    await mv.saveReceipt(
      warehouse: 'الرئيسي',
      supplier: 'مؤسسة الخير',
      date: '2026-09-10',
      lines: [line(riceId, '1', 'أرز', 60)],
    );
    final doc = await firstDoc();
    final check = await docs.cancel(
      doc: doc,
      reason: 'سند مكرر',
      availableBaseQty: await mv.balances(),
      cancelledBy: 'admin@imdad',
    );
    expect(check.ok, isTrue);

    final row = (await db.select(db.receipts).get()).first;
    expect(row.status, 'CANCELLED');
    expect(row.prevStatus, 'COMPLETED');
    expect(row.cancelReason, 'سند مكرر');
    expect(row.cancelledBy, 'admin@imdad');
    expect((jsonDecode(row.editLog) as List).single['summary'], contains('سند مكرر'));

    // دفتر الأرصدة يتجاهل الملغى ⇒ الرصيد يعود صفرًا.
    expect((await mv.balances())[riceId] ?? 0, 0);

    // المستند الملغى لا يظهر إلا عند اختيار الحالة «ملغى» صراحة.
    final cancelled = await docs.list();
    expect(cancelled.single.status, 'CANCELLED');
    expect(cancelled.single.editable, isFalse);
  });
}
