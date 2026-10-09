import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';

/// قالب الأصناف: التصدير ثم الاستيراد، والكشف، والتحقق صفًّا صفًّا، والدمج
/// والاستبدال وحدودهما (الأصناف ذات الحركات لا تُحذف ولا تُبدَّل وحداتها).
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late ExcelTemplates xt;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    xt = ExcelTemplates(db);
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) => Uint8List.fromList(TemplateWriter.build(TemplateSpec.items, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
  }) =>
      xt.run(file(rows), mode: mode, dryRun: dryRun, allowDelete: allowDelete, actor: 'tester');

  Future<void> sampleItem(String code, String name, {bool movements = false}) async {
    final id = await catalog.saveItem(
      code: code,
      name: name,
      categoryName: 'حبوب',
      baseUnit: 'حبة',
      units: const [
        ItemUnit(name: 'حبة', factor: 1, isBase: true),
        ItemUnit(name: 'علبة', factor: 12),
        ItemUnit(name: 'كرتون', factor: 144),
      ],
      minQty: 5,
      barcode: 'BC$code',
      reportUnit: 'كرتون',
    );
    if (movements) {
      final item = (await catalog.itemById(id))!;
      await catalog.setOpeningBalance(item, 'المخزن', 10, 'tester');
    }
  }

  group('التصدير والاستيراد', () {
    test('صنف بثلاث وحدات ووحدة افتراضية يعود كما كان', () async {
      await sampleItem('1001', 'زيت');
      final out = await xt.export(TemplateKind.items);
      expect(out.warnings, isEmpty);

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final report = await ExcelTemplates(other).run(
        Uint8List.fromList(out.bytes),
        mode: ImportMode.merge,
        dryRun: false,
        allowDelete: false,
      );
      expect(report.created, 1);
      expect(report.failedCount, 0);

      final item = (await CatalogRepo(other).itemByCode('1001'))!;
      final units = CatalogRepo(other).unitsOf(item);
      expect(units.map((u) => u.name), ['حبة', 'علبة', 'كرتون']);
      expect(units.map((u) => u.factor), [1, 12, 144]);
      expect(units.first.isBase, isTrue);
      expect(item.reportUnit, 'كرتون');
      expect(item.categoryName, 'حبوب');
      expect((await CatalogRepo(other).categories()).map((c) => c.name), ['حبوب']);
    });

    test('الملف المصدَّر ورقتان: البيانات والتعليمات، والبيانات أرقامها لاتينية', () async {
      await sampleItem('1001', 'زيت');
      final out = await xt.export(TemplateKind.items);
      final book = Excel.decodeBytes(out.bytes);
      expect(book.tables.keys, containsAll([TemplateSpec.dataSheet, TemplateSpec.instructionsSheet]));
      final help = book.tables[TemplateSpec.instructionsSheet]!;
      final firstCol = help.rows.map((r) => r.first?.value.toString() ?? '').join('\n');
      // التعليمات بأرقام عربية، والبيانات بلاتينية.
      expect(firstCol, contains('٣'));
      expect(firstCol, isNot(contains('3')));
      final data = book.tables[TemplateSpec.dataSheet]!;
      expect(data.rows.first.map((c) => c?.value.toString()), TemplateSpec.items.headers);
    });

    test('أكثر من ثلاث وحدات: تُصدَّر ثلاث وتُنبَّه', () async {
      await catalog.saveItem(
        code: '5',
        name: 'x',
        baseUnit: 'a',
        units: const [
          ItemUnit(name: 'a', factor: 1, isBase: true),
          ItemUnit(name: 'b', factor: 2),
          ItemUnit(name: 'c', factor: 4),
          ItemUnit(name: 'd', factor: 8),
        ],
      );
      final out = await xt.export(TemplateKind.items);
      expect(out.warnings.single, contains('ثلاث'));
    });
  });

  group('الكشف', () {
    test('يُعرف قالب الأصناف', () {
      expect(ExcelTemplates.detect(file(const [])), TemplateKind.items);
    });

    test('ملف بعناوين لا تطابق أي قالب يُرفض', () async {
      final book = Excel.createExcel();
      final s = book['البيانات'];
      s.appendRow([TextCellValue('أ'), TextCellValue('ب')]);
      final bytes = Uint8List.fromList(book.encode()!);
      expect(ExcelTemplates.detect(bytes), isNull);
      expect(
        () => xt.run(bytes, mode: ImportMode.merge, dryRun: true, allowDelete: false),
        throwsA(isA<FormatException>()),
      );
    });

    test('ملف ليس xlsx يُرفض برسالة عربية', () {
      expect(
        () => ExcelTemplates.detect(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('xlsx'))),
      );
    });
  });

  group('التحقق صفًّا صفًّا', () {
    test('صف فاشل لا يوقف الملف، وكل سبب يُذكر برقم صفه', () async {
      final report = await import([
        ['1', 'سليم', 'حبوب', 'حبة', null, 'علبة', 12, null, null, 2], // 2 ✔
        ['x9', 'كود حروف', null, 'حبة', null, null, null, null, null, null], // 3 ✘
        ['3', null, null, 'حبة', null, null, null, null, null, null], // 4 ✘ بلا اسم
        ['4', 'بلا وحدة', null, null, null, null, null, null, null, null], // 5 ✘
        ['5', 'معامل ٢', null, 'حبة', 2, null, null, null, null, null], // 6 ✘ E=2
        ['6', 'معامل 1.00', null, 'حبة', 1.0, null, null, null, null, null], // 7 ✔
        ['7', 'وحدة بلا معامل', null, 'حبة', null, 'علبة', null, null, null, null], // 8 ✘
        ['8', 'معامل بلا وحدة', null, 'حبة', null, null, 12, null, null, null], // 9 ✘
        ['9', 'افتراضية ٣ بلا وحدة', null, 'حبة', null, null, null, null, null, 3], // 10 ✘
        ['10', 'افتراضية 7', null, 'حبة', null, null, null, null, null, 7], // 11 ✘
        ['1', 'مكرر', null, 'حبة', null, null, null, null, null, null], // 12 ✘ كود 1 مكرر
        ['11', 'وحدتان متشابهتان', null, 'حبة', null, 'حبة', 3, null, null, null], // 13 ✘
        ['12', 'معامل صفر', null, 'حبة', null, 'علبة', 0, null, null, null], // 14 ✘
      ]);
      expect(report.ok, 2);
      expect(report.failedCount, 11);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('أرقامًا فقط'));
      expect(byRow[4], contains('اسم الصنف مطلوب'));
      expect(byRow[5], contains('وحدة 1 مطلوبة'));
      expect(byRow[6], contains('يجب أن يساوي 1'));
      expect(byRow[8], contains('معامل 2 مطلوب'));
      expect(byRow[9], contains('بلا وحدة 2'));
      expect(byRow[10], contains('وحدة غير مكتوبة'));
      expect(byRow[11], contains('1 أو 2 أو 3'));
      expect(byRow[12], contains('مكرر'));
      expect(byRow[13], contains('مكررة'));
      expect(byRow[14], contains('أكبر من صفر'));
      // السليمان حُفظا فعلًا.
      expect((await catalog.itemByCode('1'))!.reportUnit, 'علبة');
      expect(await catalog.itemByCode('6'), isNotNull);
      expect(await catalog.itemByCode('3'), isNull);
    });

    test('كودٌ رقمٌ في الخلية يُقرأ كودًا، والأرقام الهندية تُقبل', () async {
      final report = await import([
        [1001, 'رقم', null, 'حبة', null, null, null, null, null, null],
        ['٢٠٠٢', 'هندي', null, 'حبة', null, null, null, null, null, null],
      ]);
      expect(report.ok, 2);
      expect(await catalog.itemByCode('1001'), isNotNull);
      expect(await catalog.itemByCode('2002'), isNotNull);
    });
  });

  group('الدمج', () {
    test('تقرير تجريبي لا يكتب شيئًا ولا يسجّل في التدقيق', () async {
      final report = await import([
        ['1', 'جديد', null, 'حبة', null, null, null, null, null, null],
      ], dryRun: true);
      expect(report.created, 1);
      expect(report.dryRun, isTrue);
      expect(await catalog.items(), isEmpty);
      expect((await AuditRepo(db).allLogs()).where((l) => l.action == 'excel.template.import'), isEmpty);
    });

    test('يحدّث الموجود ويحفظ ما لا يحمله القالب (الحد والباركود)', () async {
      await sampleItem('1001', 'اسم قديم');
      final report = await import([
        ['1001', 'اسم جديد', 'تصنيف آخر', 'حبة', null, null, null, null, null, null],
      ]);
      expect(report.updated, 1);
      final item = (await catalog.itemByCode('1001'))!;
      expect(item.name, 'اسم جديد');
      expect(item.categoryName, 'تصنيف آخر');
      expect(item.minQty, 5);
      expect(item.barcode, 'BC1001');
      expect(item.reportUnit, 'كرتون', reason: 'عمود J فارغ ⇒ لا يُمحى');
      expect(catalog.unitsOf(item).map((u) => u.name), ['حبة']);
    });

    test('صنف له حركات: وحداته لا تتغير ويُنبَّه إلى ذلك', () async {
      await sampleItem('1001', 'زيت', movements: true);
      final report = await import([
        ['1001', 'زيت', null, 'لتر', null, null, null, null, null, null],
      ]);
      expect(report.updated, 1);
      expect(report.warnings.single, contains('حركات'));
      final item = (await catalog.itemByCode('1001'))!;
      expect(catalog.unitsOf(item).map((u) => u.name), ['حبة', 'علبة', 'كرتون']);
    });

    test('التدقيق يسجّل الاستيراد بمستوى عادي', () async {
      await import([
        ['1', 'x', null, 'حبة', null, null, null, null, null, null],
      ]);
      final log = (await AuditRepo(db).allLogs()).firstWhere((l) => l.action == 'excel.template.import');
      expect(log.risk, AuditRepo.riskNormal);
      expect(log.actorEmail, 'tester');
    });
  });

  group('الاستبدال', () {
    final one = [
      ['1', 'باقٍ', null, 'حبة', null, null, null, null, null, null],
    ];

    test('يحذف ما ليس في الملف إن جاز، ويُبقي ذا الحركات، ويسجّل high', () async {
      await sampleItem('1', 'في الملف');
      await sampleItem('2', 'بلا حركات');
      await sampleItem('3', 'له حركات', movements: true);

      final preview = await import(one, mode: ImportMode.replace, dryRun: true);
      expect((preview.deleted, preview.kept, preview.updated), (1, 1, 1));
      expect(await catalog.itemByCode('2'), isNotNull, reason: 'التجريبي لا يحذف');

      final report = await import(one, mode: ImportMode.replace);
      expect((report.deleted, report.kept, report.updated), (1, 1, 1));
      expect(await catalog.itemByCode('2'), isNull);
      expect(await catalog.itemByCode('3'), isNotNull);
      expect(report.summary, contains('حُذف 1'));
      expect(report.summary, contains('بقي 1'));

      final log = (await AuditRepo(db).allLogs()).firstWhere((l) => l.action == 'excel.template.import');
      expect(log.risk, AuditRepo.riskHigh);
    });

    test('بلا صلاحية الحذف يُرفض', () async {
      expect(
        () => import(one, mode: ImportMode.replace, allowDelete: false),
        throwsA(isA<StateError>()),
      );
    });

    test('ملف بلا صف صالح لا يحذف شيئًا', () async {
      await sampleItem('2', 'بلا حركات');
      final report = await import([
        ['x', 'كود خاطئ', null, 'حبة', null, null, null, null, null, null],
      ], mode: ImportMode.replace);
      expect(report.deleted, 0);
      expect(report.warnings.single, contains('لم يُحذف شيء'));
      expect(await catalog.itemByCode('2'), isNotNull);
    });

    test('صفٌّ فاشل يحمي صنفه من الحذف (خطأ كتابة لا يمحو صنفًا)', () async {
      await sampleItem('2', 'بلا حركات');
      final report = await import([
        ['1', 'سليم', null, 'حبة', null, null, null, null, null, null],
        ['2', null, null, 'حبة', null, null, null, null, null, null], // بلا اسم
      ], mode: ImportMode.replace);
      expect(report.failedCount, 1);
      expect(report.deleted, 0);
      expect(await catalog.itemByCode('2'), isNotNull);
    });
  });
}
