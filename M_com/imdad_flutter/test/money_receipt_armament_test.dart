import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/money_receipt_print.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';

/// سند استلام المبلغ المالي (سندٌ واحد في الصفحة، وكتابة المبلغ تلقائية)،
/// وحقول القرون والذخيرة في التسليح مع تعديل السجل المحفوظ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LinkageRepo repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LinkageRepo(db);
  });
  tearDown(() => db.close());

  int pages(List<int> pdf) => RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(pdf)).length;
  bool isPdf(List<int> b) => String.fromCharCodes(b.take(5)) == '%PDF-';

  group('استلام مبلغ مالي', () {
    test('المبلغ بالحروف يُشتق من الرقم وبعملته', () {
      expect(MoneyReceiptPrint.words(0, 'sar'), isEmpty);
      expect(MoneyReceiptPrint.words(2200, 'yer'), 'ألفان ومئتان ريال يمني فقط لا غير');
      expect(MoneyReceiptPrint.words(15000, 'sar'), contains('ريال سعودي'));
      expect(MoneyReceiptPrint.figure(15000, 'sar'), '15,000.00 ر.س.');
    });

    test('حفظ وتعديل وحذف السند', () async {
      await repo.saveMoneyReceipt(const LinkMoneyReceiptsCompanion(
        id: Value('r1'),
        receiverName: Value('سالم'),
        amount: Value(500),
      ));
      var rows = await repo.moneyReceipts();
      expect(rows.single.receiverName, 'سالم');

      await repo.saveMoneyReceipt(const LinkMoneyReceiptsCompanion(id: Value('r1'), receiverName: Value('أحمد'), amount: Value(900)));
      rows = await repo.moneyReceipts();
      expect(rows, hasLength(1));
      expect(rows.single.receiverName, 'أحمد');
      expect(rows.single.amount, 900);

      await repo.deleteMoneyReceipt(rows.single);
      expect(await repo.moneyReceipts(), isEmpty);
    });

    test('الطباعة: سندٌ واحد في صفحة واحدة — مملوءًا أو فارغًا', () async {
      await repo.saveMoneyReceipt(LinkMoneyReceiptsCompanion(
        id: const Value('r2'),
        receiverName: const Value('سالم'),
        capacity: const Value('أمين مخزن'),
        amount: const Value(3700),
        receiptDate: const Value('2026-10-04'),
        purpose: Value('شراء ' * 40),
        method: const Value('transfer'),
        transferNo: const Value('12345'),
      ));
      final filled = await MoneyReceiptPrint.build(db, (await repo.moneyReceipts()).single);
      final blank = await MoneyReceiptPrint.build(db, null);
      expect(isPdf(filled), isTrue);
      expect(isPdf(blank), isTrue);
      expect(pages(filled), 1);
      expect(pages(blank), 1);
    });
  });

  group('التسليح', () {
    test('القرون والذخيرة تُحفظ وتُعدَّل على السجل نفسه', () async {
      await repo.insertArmament(const LinkArmamentsCompanion(
        id: Value('a1'),
        personName: Value('سالم'),
        weaponType: Value('كلاشنكوف'),
        magazines: Value(4),
        magazineType: Value('روسي'),
        ammoQty: Value(120),
      ));
      var a = (await repo.armaments()).single;
      expect((a.magazines, a.magazineType, a.ammoQty), (4, 'روسي', 120));

      await repo.updateArmament(
        'a1',
        const LinkArmamentsCompanion(
          id: Value('a1'),
          personName: Value('سالم'),
          weaponType: Value('كلاشنكوف'),
          magazines: Value(6),
          magazineType: Value('صيني'),
          ammoQty: Value(180),
        ),
      );
      a = (await repo.armaments()).single;
      expect((a.magazines, a.magazineType, a.ammoQty), (6, 'صيني', 180));
      expect(a.updatedAt, isNotNull);
    });
  });
}
