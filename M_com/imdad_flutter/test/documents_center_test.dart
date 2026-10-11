import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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

  group('H-4: التعديل والإلغاء يُفحصان لكل مستودع', () {
    DocumentLineRow row(String id, String code, String name, double qty, {String expiry = ''}) => DocumentLineRow(
          id: '',
          itemId: id,
          itemCode: code,
          itemName: name,
          unitName: 'كيس',
          factor: 1,
          qty: qty,
          baseQty: qty,
          expiryDate: expiry,
        );

    Future<DocumentSummary> docOf(String kind) async =>
        (await docs.list()).firstWhere((d) => d.kind.name == kind);

    setUp(() async {
      await catalog.saveWarehouse(code: 'W2', name: 'الفرعي');
    });

    test('نقل سند صرفٍ إلى مستودعٍ بلا رصيد يُرفض', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 50)]);
      await mv.saveIssue(
          warehouse: 'الرئيسي', recipientDisplay: 'ك', date: '2026-09-02', lines: [line(riceId, '1', 'أرز', 30)]);
      final issue = await docOf('issue');
      final check = await docs.saveEdit(
        doc: issue,
        rows: [row(riceId, '1', 'أرز', 30)],
        reason: 'نقل',
        date: issue.date,
        warehouse: 'الفرعي',
        party: issue.party,
      );
      expect(check.ok, isFalse, reason: 'نُقل الصرف إلى مستودعٍ بلا رصيد فصار سالبًا');
      expect(check.warehouse, 'الفرعي');
      expect((await mv.balances(warehouse: 'الفرعي'))[riceId] ?? 0, 0);
    });

    test('زيادة صرفٍ يكفيها مجموع المستودعات لا رصيد مستودعه تُرفض', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 10)]);
      await mv.saveReceipt(
          warehouse: 'الفرعي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 500)]);
      await mv.saveIssue(
          warehouse: 'الرئيسي', recipientDisplay: 'ك', date: '2026-09-02', lines: [line(riceId, '1', 'أرز', 5)]);
      final issue = await docOf('issue');
      final check = await docs.saveEdit(
        doc: issue,
        rows: [row(riceId, '1', 'أرز', 50)],
        reason: 'زيادة',
        date: issue.date,
        warehouse: 'الرئيسي',
        party: issue.party,
      );
      expect(check.ok, isFalse);
      expect((await mv.balances(warehouse: 'الرئيسي'))[riceId], 5);
    });

    test('زيادة تحويلٍ معلّق فوق رصيد المصدر تُرفض', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 20)]);
      final sent = await mv.saveTransfer(
          fromWarehouse: 'الرئيسي', toWarehouse: 'الفرعي', date: '2026-09-02', lines: [line(riceId, '1', 'أرز', 10)]);
      expect(sent.ok, isTrue, reason: sent.error);
      final transfer = await docOf('transfer');
      final check = await docs.saveEdit(
        doc: transfer,
        rows: [row(riceId, '1', 'أرز', 90)],
        reason: 'زيادة',
        date: transfer.date,
        warehouse: 'الرئيسي',
        party: 'الفرعي',
      );
      expect(check.ok, isFalse);
      expect((await mv.balances(warehouse: 'الرئيسي'))[riceId], 10);
    });

    test('إلغاء تحويلٍ مُستلَم صُرف ما وصل به يُرفض', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 20)]);
      final sent = await mv.saveTransfer(
          fromWarehouse: 'الرئيسي', toWarehouse: 'الفرعي', date: '2026-09-02', lines: [line(riceId, '1', 'أرز', 20)]);
      await mv.receiveTransfer(sent.refNo);
      await mv.saveIssue(
          warehouse: 'الفرعي', recipientDisplay: 'ك', date: '2026-09-03', lines: [line(riceId, '1', 'أرز', 15)]);
      final transfer = await docOf('transfer');
      final check = await docs.cancel(doc: transfer, reason: 'خطأ');
      expect(check.ok, isFalse, reason: 'سحب الإلغاء رصيدًا صُرف في مستودع الاستلام');
      expect(check.warehouse, 'الفرعي');
      expect((await db.select(db.transfers).get()).single.status, 'RECEIVED');
    });

    test('مستودعٌ مجمَّد بأمر جرد لا يُعدَّل فيه سند ولا يُلغى', () async {
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [line(riceId, '1', 'أرز', 20)]);
      await db.into(db.stocktakes).insert(StocktakesCompanion.insert(
            id: 'st-1',
            orderNo: const Value('ج-1'),
            warehouse: const Value('الرئيسي'),
            freeze: const Value(true),
            status: const Value('COUNTING'),
          ));
      final receipt = await docOf('receipt');
      final edit = await docs.saveEdit(
        doc: receipt,
        rows: [row(riceId, '1', 'أرز', 25)],
        reason: 'ت',
        date: receipt.date,
        warehouse: 'الرئيسي',
        party: receipt.party,
      );
      expect(edit.ok, isFalse);
      expect(edit.error, contains('مجمّد'));
      expect((await docs.cancel(doc: receipt, reason: 'ت')).ok, isFalse);
    });

    test('تعديل سند الوارد يُبقي تاريخ صلاحية الدفعة (M-8)', () async {
      await mv.saveReceipt(warehouse: 'الرئيسي', supplier: 'م', date: '2026-09-01', lines: [
        DocLineInput(
            itemId: riceId, itemCode: '1', itemName: 'أرز', unitName: 'كيس', factor: 1, qty: 20, expiryDate: '2027-01-31'),
      ]);
      final receipt = await docOf('receipt');
      final lines = await docs.lines(DocKind.receipt, receipt.refNo);
      expect(lines.single.expiryDate, '2027-01-31');
      lines.single.qty = 22;
      final check = await docs.saveEdit(
        doc: receipt,
        rows: lines,
        reason: 'ت',
        date: receipt.date,
        warehouse: 'الرئيسي',
        party: receipt.party,
      );
      expect(check.ok, isTrue);
      expect((await db.select(db.receipts).get()).single.expiryDate, '2027-01-31');
    });
  });
}
