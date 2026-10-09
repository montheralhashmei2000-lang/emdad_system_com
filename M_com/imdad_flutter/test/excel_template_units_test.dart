import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';

/// قالب الوحدات المستفيدة: الشجرة من الكود وحده، ومستويان، والاختصاص من خمسة.
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

  Uint8List file(List<List<Object?>> rows) => Uint8List.fromList(TemplateWriter.build(TemplateSpec.units, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
  }) =>
      xt.run(file(rows), mode: mode, dryRun: dryRun, allowDelete: allowDelete, actor: 'tester');

  Future<BeneficiaryUnit> byCode(String code) async =>
      (await catalog.unitsUnsorted()).firstWhere((u) => u.code == code);

  const tree = <List<Object?>>[
    // الفروع قبل جذورها عمدًا: ترتيب الملف لا يهم.
    ['1-1', 'الكتيبة الأولى', null],
    ['1-2', 'الكتيبة الثانية', 'وحدة'],
    ['1', 'المعسكر الأول', 'معسكر'],
    ['2', 'المعسكر الثاني', 'معسكر'],
    ['4-1', 'نقطة الشمال', null],
    ['4', 'النقاط', 'نقاط'],
  ];

  group('البناء الهرمي', () {
    test('الجذر بلا شرطة معسكر، والفرع بشرطة ابنٌ لجذره مهما كان ترتيب الملف', () async {
      final report = await import(tree);
      expect(report.created, 6);
      expect(report.failedCount, 0);

      final c1 = await byCode('1');
      expect((c1.type, c1.isCamp, c1.parentId, c1.category), ('camp', true, '', 'معسكر'));
      final k = await byCode('1-1');
      expect((k.type, k.isCamp, k.parentId, k.parentName), ('unit', false, c1.id, 'المعسكر الأول'));
      expect(k.category, 'وحدة', reason: 'الاختصاص الفارغ ⇒ وحدة');
      final points = await byCode('4');
      expect((points.type, points.category), ('camp', 'نقاط'));
      expect((await byCode('4-1')).parentId, points.id);
      expect((await byCode('2')).parentId, '');
    });

    test('فرع بجذرٍ قائم في القاعدة وليس في الملف', () async {
      await catalog.saveUnit(code: '1', name: 'قائم', type: 'camp', category: 'معسكر');
      final report = await import([
        ['1-3', 'فرع جديد', null],
      ]);
      expect(report.created, 1);
      expect((await byCode('1-3')).parentName, 'قائم');
    });

    test('شرطات وأرقام عربية تُقبل', () async {
      final report = await import([
        ['١', 'جذر', 'معسكر'],
        ['١–٢', 'فرع بشرطة طويلة', null],
      ]);
      expect(report.failedCount, 0);
      expect((await byCode('1-2')).parentName, 'جذر');
    });
  });

  group('التحقق صفًّا صفًّا', () {
    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['1', 'سليم', 'معسكر'], // 2 ✔
        ['1-1-1', 'ثلاثة مستويات', null], // 3 ✘
        ['', 'بلا كود', null], // 4 ✘
        ['2', '', null], // 5 ✘
        ['3', 'اختصاص غريب', 'مشاة'], // 6 ✘
        ['9-1', 'يتيم', null], // 7 ✘ جذره 9 غير موجود
        ['1-', 'شرطة معلّقة', null], // 8 ✘
        ['1', 'مكرر', null], // 9 ✘
        ['1-5', 'فرع سليم', 'نقاط'], // 10 ✔
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('مستويين'));
      expect(byRow[4], contains('الكود مطلوب'));
      expect(byRow[5], contains('الاسم مطلوب'));
      expect(byRow[6], contains('ليس من الخمسة'));
      expect(byRow[7], contains('غير موجود'));
      expect(byRow[8], contains('غير صالح'));
      expect(byRow[9], contains('مكرر'));
      expect((await byCode('1-5')).category, 'نقاط');
    });
  });

  group('الدمج', () {
    test('التصدير ثم الاستيراد في قاعدة أخرى يعيد الشجرة نفسها', () async {
      await import(tree);
      final out = await xt.export(TemplateKind.units);
      expect(out.warnings, isEmpty);

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final report = await ExcelTemplates(other).run(
        Uint8List.fromList(out.bytes),
        mode: ImportMode.merge,
        dryRun: false,
        allowDelete: false,
      );
      expect(report.created, 6);
      final units = await CatalogRepo(other).unitsUnsorted();
      final c1 = units.firstWhere((u) => u.code == '1');
      expect(units.firstWhere((u) => u.code == '1-2').parentId, c1.id);
      expect(units.where((u) => u.isCamp).map((u) => u.code).toSet(), {'1', '2', '4'});
    });

    test('تسمية الجذر تُجرى على فروعه القائمة غير الواردة في الملف', () async {
      await import(tree);
      await import([
        ['1', 'اسم جديد', 'معسكر'],
      ]);
      expect((await byCode('1-1')).parentName, 'اسم جديد');
    });

    test('اختصاص فارغ في الملف لا يمحو اختصاص الموجود', () async {
      await catalog.saveUnit(code: '7', name: 'قديم', type: 'camp', category: 'الشعبة الفنية');
      await import([
        ['7', 'قديم معدّل', null],
      ]);
      final u = await byCode('7');
      expect((u.name, u.category), ('قديم معدّل', 'الشعبة الفنية'));
    });

    test('تحويل فرعٍ قائم إلى جذر يُنبَّه إليه', () async {
      await import(tree);
      await catalog.saveUnit(
          code: 'U1', name: 'فرع قديم', parentId: (await byCode('1')).id, parentName: 'المعسكر الأول');
      final report = await import([
        ['U1', 'صار جذرًا', 'معسكر'],
      ]);
      expect(report.warnings.single, contains('كانت فرعًا'));
      expect((await byCode('U1')).parentId, '');
    });

    test('التقرير التجريبي لا يكتب', () async {
      final report = await import(tree, dryRun: true);
      expect(report.created, 6);
      expect(await catalog.unitsUnsorted(), isEmpty);
    });

    test('تحذيرات التصدير: ترميز لا يطابق الشجرة واختصاص خارج الخمسة', () async {
      final root = await catalog.saveUnit(code: 'C1', name: 'قديم', type: 'camp', category: 'مشاة');
      await catalog.saveUnit(code: 'U1', name: 'فرع', parentId: root, parentName: 'قديم');
      final out = await xt.export(TemplateKind.units);
      expect(out.warnings.length, 2);
      expect(out.warnings.join(' '), contains('ترميز الشجرة'));
      expect(out.warnings.join(' '), contains('خارج الخمسة'));
    });
  });

  group('الاستبدال', () {
    final keep = <List<Object?>>[
      ['1', 'المعسكر الأول', 'معسكر'],
      ['1-1', 'الكتيبة', null],
    ];

    test('يحذف غير الوارد بلا ارتباطات، ويُبقي ذا التفريدة وجذرَه، ويسجّل high', () async {
      await import(tree);
      // 4-1 له تفريدة ⇒ يبقى ويُبقي جذره 4. و2 و1-2 بلا ارتباط ⇒ يُحذفان.
      final withStrength = await byCode('4-1');
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 'st-1',
            unitId: withStrength.id,
            strengthDate: '2026-10-01',
            soldierCount: const Value(10),
          ));

      final preview = await import(keep, mode: ImportMode.replace, dryRun: true);
      expect(preview.deleted, 2, reason: 'المعسكر 2 و1-2');
      expect(preview.kept, 2, reason: '4-1 له تفريدة و4 له فرعٌ باقٍ');
      expect(await byCode('2'), isA<BeneficiaryUnit>(), reason: 'التجريبي لا يحذف');

      final report = await import(keep, mode: ImportMode.replace);
      expect((report.deleted, report.kept), (2, 2));
      final left = (await catalog.unitsUnsorted()).map((u) => u.code).toSet();
      expect(left, {'1', '1-1', '4', '4-1'});
      expect(report.summary, contains('حُذف 2'));

      // سجلّان: دمج البذرة (عادي) ثم الاستبدال (high). التجريبي لا يسجّل.
      final logs = (await AuditRepo(db).allLogs()).where((l) => l.action == 'excel.template.import').toList();
      expect(logs.length, 2);
      expect(logs.where((l) => l.risk == AuditRepo.riskHigh).length, 1);
    });

    test('وحدة مذكورة في سند صرف تبقى', () async {
      await import(tree);
      final two = await byCode('2');
      await db.customStatement(
        'INSERT INTO issues (id, beneficiary_unit_id) VALUES (?, ?)',
        ['iss-1', two.id],
      );
      final report = await import(keep, mode: ImportMode.replace);
      expect(await byCode('2'), isA<BeneficiaryUnit>());
      expect(report.kept, greaterThanOrEqualTo(1));
    });

    test('بلا صلاحية الحذف يُرفض، وبلا صفوف صالحة لا يُحذف شيء', () async {
      await import(tree);
      expect(() => import(keep, mode: ImportMode.replace, allowDelete: false), throwsA(isA<StateError>()));
      final report = await import([
        ['1-1-1', 'سيّئ', null],
      ], mode: ImportMode.replace);
      expect(report.deleted, 0);
      expect(report.warnings.single, contains('لم يُحذف شيء'));
      expect((await catalog.unitsUnsorted()).length, 6);
    });

    test('صفٌّ فاشل يحمي وحدته من الحذف', () async {
      await import(tree);
      final report = await import([
        ['1', 'المعسكر الأول', 'معسكر'],
        ['2', '', null], // بلا اسم
      ], mode: ImportMode.replace);
      expect(report.failedCount, 1);
      expect(await byCode('2'), isA<BeneficiaryUnit>());
    });
  });
}
