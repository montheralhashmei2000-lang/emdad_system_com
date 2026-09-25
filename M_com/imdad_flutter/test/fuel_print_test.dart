import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/document_pdf.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel.dart';
import 'package:imdad/features/fuel/fuel_print.dart';

/// سندات المحروقات المطبوعة.
///
/// **السائق لا يأخذ الوقود بلا ورقة موقَّعة بيده.** فهذه الاختبارات تحرس أن
/// ما يُطبع يحمل ما يلزم لتسليمه والتوقيع عليه: المرجع والكمية والشاصي
/// والمستفيد — وأن الملف يُبنى فعلًا بالخط العربي لا يسقط عنده.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FuelRepo repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FuelRepo(db);
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'wh1',
          name: 'مستودع الوقود',
          fuelCapacityLiters: const Value(20000),
        ));
    await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(id: 'wh2', name: 'الفرعي'));
    await db.into(db.beneficiaryUnits).insert(
        BeneficiaryUnitsCompanion.insert(id: 'u1', name: 'الكتيبة الأولى'));
    await repo.saveSupply(
      date: '2026-01-01',
      fuelType: FuelType.diesel,
      warehouse: 'مستودع الوقود',
      quantityLiters: 9000,
      supplierName: 'مورّد الوقود',
      driverName: 'ناقل',
    );
  });

  tearDown(() => db.close());

  Future<FuelIssue> anIssue({
    String source = FuelSource.allocation,
    double qty = 250,
  }) async {
    var allocationId = '';
    if (source == FuelSource.allocation) {
      // تفريدةٌ واحدة تكفي عدة سندات: إنشاؤها مرة لكل سند يصنع تفريدات مكرّرة.
      var rows = await repo.allocations();
      if (rows.isEmpty) {
        await repo.saveAllocation(
          unitId: 'u1',
          unitName: 'الكتيبة الأولى',
          fuelType: FuelType.diesel,
          periodType: FuelPeriod.monthly,
          quantityPerPeriod: 3000,
          startDate: '2026-01-01',
        );
        rows = await repo.allocations();
      }
      allocationId = rows.first.allocation.id;
    }
    final res = await repo.saveIssue(
      date: '2026-01-05',
      fuelType: FuelType.diesel,
      warehouse: 'مستودع الوقود',
      quantityLiters: qty,
      source: source,
      allocationId: allocationId,
      beneficiaryName: source == FuelSource.exceptional ? 'سرية الإسناد' : '',
      driverName: 'أحمد سالم',
      vehicleType: 'شاص',
      chassisNo: 'SH-4421',
      purpose: 'مهمة تموين',
      justification: source == FuelSource.exceptional ? 'تحرك عاجل' : '',
      orderAuthority: source == FuelSource.exceptional ? 'مكتب القائد' : '',
    );
    expect(res.ok, isTrue, reason: res.error);
    return (await repo.issues()).first;
  }

  String flat(PrintDoc doc) => [
        doc.title,
        ...doc.rows.expand((r) => r),
        ...doc.leftValues.values,
        ...doc.fieldValues.values,
        doc.footerNote,
      ].join(' | ');

  group('سند الصرف', () {
    test('يحمل ما يلزم لتسليمه والتوقيع عليه', () async {
      final issue = await anIssue();
      final doc = FuelPrint.issueDoc(issue);
      final text = flat(doc);

      expect(doc.title, contains('صرف محروقات'));
      expect(text, contains(issue.refNo), reason: 'بلا مرجع لا يُؤرشف السند');
      expect(text, contains('SH-4421'), reason: 'الشاصي هو ما يُحاسب عليه');
      expect(text, contains('أحمد سالم'));
      expect(text, contains('شاص'));
      expect(text, contains('مستودع الوقود'));
      expect(text, contains('ديزل'));
    });

    test('يطبع الاستحقاق والمتبقي حين تُمرَّر تفريدته', () async {
      final issue = await anIssue();
      final row = (await repo.allocations()).single;
      final text = flat(FuelPrint.issueDoc(issue, allocation: row));
      expect(text, contains('الاستحقاق'));
      expect(text, contains('المتبقي'));
    });

    test('الاستثنائي يطبع جهة الأمر والمبرر', () async {
      final issue = await anIssue(source: FuelSource.exceptional);
      final text = flat(FuelPrint.issueDoc(issue));
      expect(text, contains('مكتب القائد'),
          reason: 'صرفٌ خارج التفريدة بلا جهة أمر على الورقة لا يُسأل عنه أحد');
      expect(text, contains('تحرك عاجل'));
      expect(text, contains('سرية الإسناد'));
    });

    test('الحقول الفارغة تُطبع شرطةً لا فراغًا', () async {
      final issue = await anIssue();
      final bare = issue.copyWith(driverName: '', chassisNo: '');
      final row = FuelPrint.issueDoc(bare).rows.single;
      expect(row.where((v) => v.trim().isEmpty), isEmpty,
          reason: 'خانة فارغة في ورقة موقَّعة تُملأ بعد التوقيع');
      expect(row, contains('—'));
    });
  });

  group('بقية السندات', () {
    test('التوريد يحمل المورّد والكمية', () async {
      final supply = (await repo.supplies()).single;
      final text = flat(FuelPrint.supplyDoc(supply));
      expect(text, contains('مورّد الوقود'));
      expect(text, contains(supply.refNo));
    });

    test('التحويل يُظهر المستودعين', () async {
      await repo.saveTransfer(
        date: '2026-01-06',
        fuelType: FuelType.diesel,
        fromWarehouse: 'مستودع الوقود',
        toWarehouse: 'الفرعي',
        quantityLiters: 500,
      );
      final text = flat(FuelPrint.transferDoc((await repo.transfers()).single));
      expect(text, contains('مستودع الوقود'));
      expect(text, contains('الفرعي'));
    });

    test('محضر الجرد غير المرحّل يقول ذلك صراحةً', () async {
      await repo.openStocktake(
          date: '2026-02-01',
          warehouse: 'مستودع الوقود',
          committee: 'لجنة الجرد');
      final take = (await repo.stocktakes()).single;
      final lines = await repo.stocktakeLines(take.id);
      final text = flat(FuelPrint.stocktakeDoc(take, lines));
      expect(text, contains('لم يُرحَّل'),
          reason: 'محضرٌ غير مرحّل لا يُحتجّ به على أحد');
      expect(text, contains('لجنة الجرد'));
    });

    test('كشف الصرف يجمع الإجمالي', () async {
      await anIssue(qty: 250);
      final text = flat(FuelPrint.issuesDoc(await repo.issues()));
      expect(text, contains('إجمالي المصروف'));
      expect(text, contains('٢٥٠'));
    });

    test('كشف الأرصدة يشرح معادلته', () async {
      final text = flat(FuelPrint.stocksDoc(await repo.stocks()));
      expect(text, contains('الرصيد ='),
          reason: 'رقمٌ بلا معادلته يُجادَل فيه ولا يُراجَع');
    });
  });

  group('الملف يُبنى فعلًا', () {
    test('سند الصرف يخرج ملفًا غير فارغ بالخط العربي', () async {
      final issue = await anIssue();
      final bytes = await DocumentPdf.build(doc: FuelPrint.issueDoc(issue));
      expect(bytes.lengthInBytes, greaterThan(1000),
          reason: 'الطباعة تسقط عند الخط العربي فلا يُكتشف إلا في الميدان');
      // ترويسة ملف PDF.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('كشف بعدة سطور يخرج ملفًا', () async {
      await anIssue(qty: 100);
      await anIssue(qty: 120);
      final bytes =
          await DocumentPdf.build(doc: FuelPrint.issuesDoc(await repo.issues()));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
