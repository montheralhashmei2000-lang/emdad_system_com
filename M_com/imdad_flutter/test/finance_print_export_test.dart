import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/export/excel_export.dart';
import 'package:imdad/core/print/cable_print.dart';
import 'package:imdad/core/print/contract_print.dart';
import 'package:imdad/core/print/custody_sheet_print.dart';
import 'package:imdad/core/print/document_pdf.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/cable_repo.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/domain/free_table.dart';

/// الطباعة والتصدير على الحالات الحدّية: فارغ، ضخم، أعمدة كثيرة، نصوص طويلة،
/// عملتان. المطلوب ألّا يسقط شيءٌ، وأن يكون الناتج ملفًا صالحًا.
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
  final long = 'نص طويل جدًا ' * 250;

  group('مسير العهدة', () {
    Future<List<int>> sheet(int n, String cur, {String text = 'بيان'}) async {
      final id = await repo.saveCustodySheet(
        sheetNo: 'عهدة-00001', title: 't', defaultRate: 400, notes: '', currency: cur, holderName: 'سالم',
        rows: [
          for (var i = 0; i < n; i++)
            LinkCustodySheetRowsCompanion(
              date: const Value('2026-10-01'), grantSar: Value(i == 0 ? 1000 : 0), grantYer: Value(i == 0 ? 400000 : 0),
              spentSar: Value(i + 1.0), spentYer: Value((i + 1.0) * 400), rate: const Value(400),
              statement: Value(text), shop: Value(text), person: Value(text), invoiceNo: Value('F${i % 7}'),
            ),
        ],
      );
      final sh = (await repo.custodySheets()).firstWhere((s) => s.id == id);
      final out = await CustodySheetPrint.build(db, sh, await repo.sheetRows(id));
      await repo.deleteCustodySheet(sh);
      return out;
    }

    test('بلا أسطر، وسطر واحد، ومئات الأسطر بالعملتين', () async {
      for (final cur in ['sar', 'yer']) {
        expect(isPdf(await sheet(0, cur)), isTrue);
        expect(isPdf(await sheet(1, cur)), isTrue);
        expect(pages(await sheet(1, cur)), 1);
        expect(pages(await sheet(400, cur)), greaterThan(2));
      }
    });

    test('نصوص طويلة جدًا في الخلايا لا تُسقط الطباعة', () async {
      expect(isPdf(await sheet(3, 'yer', text: long)), isTrue);
    });
  });

  group('عقد الشراء', () {
    Future<LinkPurchaseContract> contract(String id, int n, {String cur = 'sar', double rate = 0, String name = 'صنف', String notes = '', String custody = ''}) async {
      final items = [for (var i = 0; i < n; i++) ContractItem(name: '$name $i', unit: 'حبة', qty: 2, price: 10, total: 20, invoiceNo: 'F$i', date: '2026-10-01')];
      await repo.insertContract(LinkPurchaseContractsCompanion(
        id: Value(id), title: const Value('بهارات'), supplier: const Value('الوكيل'), currency: Value(cur), exchangeRate: Value(rate),
        listDate: const Value('2026-10-01'), itemsJson: Value(ContractItem.encode(items)), amount: Value(ContractItem.sum(items)),
        notes: Value(notes), custodyId: Value(custody),
      ));
      return (await repo.contracts()).firstWhere((c) => c.id == id);
    }

    test('بلا أصناف، وبمئة صنف، وبأسماء طويلة، وبملاحظات ضخمة', () async {
      expect(isPdf(await ContractPrint.build(db, await contract('a', 0))), isTrue);
      expect(pages(await ContractPrint.build(db, await contract('b', 150, cur: 'yer', rate: 410))), greaterThan(1));
      expect(isPdf(await ContractPrint.build(db, await contract('c', 3, name: long))), isTrue);
      expect(isPdf(await ContractPrint.build(db, await contract('d', 3, notes: long))), isTrue);
    });

    test('العهدة المرتبطة لا تُطبع: مصدر الطباعة لا يقرؤها أصلًا', () async {
      await repo.insertCustody(const LinkFinCustodiesCompanion(id: Value('cu'), title: Value('عهدة-سرية-123'), amount: Value(10)));
      expect(isPdf(await ContractPrint.build(db, await contract('e', 2, custody: 'cu'))), isTrue);
      final src = File('lib/core/print/contract_print.dart').readAsStringSync();
      expect(src.contains('custodyId') || src.contains('custody'), isFalse, reason: 'ربط العهدة داخليّ لا يُطبع');
      expect(ContractPrint.showsSarEquivalent(await contract('f', 1, cur: 'yer', rate: 410)), isTrue);
    });
  });

  group('البرقية', () {
    Future<Cable> cable(String id, {String body = 'نص', String table = '[]', String cc = ''}) async {
      await CableRepo(db).insert(
        CablesCompanion(id: Value(id), subject: const Value('موضوع'), body: Value(body), recipientsJson: Value(table), ccParty: Value(cc)),
        actor: 't',
      );
      return (await CableRepo(db).byId(id))!;
    }

    test('فارغة، وجسم ضخم متعدد الصفحات، وجدول حر بأعمدة كثيرة ونصوص طويلة', () async {
      expect(isPdf(await CablePrint.build(db, await cable('a', body: ''))), isTrue);
      expect(pages(await CablePrint.build(db, await cable('b', body: ('سطر من البرقية\n' * 120)))), greaterThan(1));
      final wide = FreeTable(
        title: 'جدول واسع',
        cols: [for (var i = 0; i < 12; i++) FreeCol('عمود $i', 1 + i.toDouble())],
        rows: [
          [for (var i = 0; i < 12; i++) long.substring(0, 60)],
          [for (var i = 0; i < 12; i++) 'x$i'],
        ],
      );
      expect(isPdf(await CablePrint.build(db, await cable('c', table: wide.encode(), cc: 'أ\nب\nج\nد\nه\nو\nز'))), isTrue);
    });
  });

  group('حقول ضخمة في كل خانة', () {
    test('برقية: موضوع وجهات ومحرر ووظيفة وتسلسل بآلاف الأحرف', () async {
      await CableRepo(db).insert(
        CablesCompanion(
          id: const Value('g'), subject: Value(long), toParty: Value(long), fromParty: Value(long), ccParty: Value(long),
          editorName: Value(long), editorRank: Value(long), editorJob: Value(long), serialNo: Value(long), sendMethod: Value(long),
          sendDateTime: Value(long), receiverName: Value(long), receiveTime: Value(long), signerText: Value(long), body: Value(long),
        ),
        actor: 't',
      );
      expect(isPdf(await CablePrint.build(db, (await CableRepo(db).byId('g'))!)), isTrue);
    });

    test('عقد: تصنيف وتاجر ورقم عقد بآلاف الأحرف', () async {
      await repo.insertContract(LinkPurchaseContractsCompanion(
        id: const Value('g'), title: Value(long), supplier: Value(long), contractNo: Value(long), invoiceNo: Value(long), amount: const Value(5),
        itemsJson: Value(ContractItem.encode([ContractItem(name: long, unit: long, qty: 1, price: 5, total: 5, invoiceNo: long, note: long)])),
      ));
      expect(isPdf(await ContractPrint.build(db, (await repo.contracts()).single)), isTrue);
    });

    test('مسير: رقم العهدة وصاحبها بآلاف الأحرف', () async {
      final id = await repo.saveCustodySheet(
          sheetNo: long, title: long, defaultRate: 400, notes: long, holderName: long, currency: 'yer',
          rows: [LinkCustodySheetRowsCompanion(spentYer: const Value(5), category: Value(long), entryNo: Value(long), notes: Value(long))]);
      final sh = (await repo.custodySheets()).single;
      expect(isPdf(await CustodySheetPrint.build(db, sh, await repo.sheetRows(id))), isTrue);
    });
  });

  group('وثائق الطباعة العامة (الإخلاء وكشف الحساب)', () {
    test('وثيقة الإخلاء وكشف الحساب بصفوف كثيرة وأرصدة بعملتين', () async {
      final clearance = PrintDoc(
        title: 'إخلاء عهدة',
        headers: const ['البيان', 'القيمة'],
        columnFlex: const [2, 5],
        rows: [for (var i = 0; i < 16; i++) ['حقل $i', i.isEven ? long : '']],
        signatureLines: const ['صاحب العهدة\n....', 'المُخلِّي\n....', 'المراجع\n....'],
      );
      expect(isPdf(await DocumentPdf.build(doc: clearance)), isTrue);
      final statement = PrintDoc(
        title: 'كشف حساب مالية — سالم',
        headers: const ['التاريخ', 'النوع', 'البيان', 'المدين (−)', 'الدائن (+)', 'العملة'],
        columnFlex: const [2, 2, 7, 2, 2, 2],
        rows: [for (var i = 0; i < 90; i++) ['1/10/2026', 'فائض', 'إخلاء $i', '', '${i + 1}', i.isEven ? 'سعودي' : 'يمني']],
        footerNote: 'الرصيد: +4,095 ر.س · +4,050 ر.ي',
      );
      expect(pages(await DocumentPdf.build(doc: statement)), greaterThan(1));
    });
  });

  group('تصدير Excel', () {
    test('الصفوف والأعمدة متساوية، والأرقام أرقام، والنص الذي يشبه الصيغة يبقى نصًّا', () {
      final bytes = ExcelExport.build(
        sheetName: 'الإخلاءات',
        headers: const ['م', 'الرقم', 'المخصص', 'الفرق', 'ملاحظات'],
        rows: [
          ['1', 'إخلاء-ABCD-202610-00001', '1,000', '-٤٠٠', '=HYPERLINK("http://x","اضغط")'],
          ['2', '٠٠٠٧٣', '', '', '+SUM(A1:A9)'],
        ],
        numericColumns: const {0, 2, 3},
      );
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(2)), 'PK', reason: 'xlsx = zip');
    });
  });
}
