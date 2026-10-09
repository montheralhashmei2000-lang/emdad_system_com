import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/stocktake_repo.dart';

/// قالب العد الفعلي: يمرّ كل سطرٍ بـ`StocktakeRepo.saveCount` نفسه وبقواعد شاشة
/// الجرد، دمجًا فقط، ولا يمسّ الأرصدة.
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late StocktakeRepo repo;
  late ExcelTemplates xt;
  late Item rice, salt, four;
  late String order;

  const wh = 'المخزن الرئيسي';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    repo = StocktakeRepo(db);
    xt = ExcelTemplates(db);
    await catalog.saveWarehouse(code: 'W1', name: wh, manager: '', location: '', feedsAllCamps: true, campIds: const []);
    await catalog.saveItem(
      code: '1001',
      name: 'أرز',
      baseUnit: 'حبة',
      units: const [
        ItemUnit(name: 'حبة', factor: 1, isBase: true),
        ItemUnit(name: 'علبة', factor: 12),
        ItemUnit(name: 'كرتون', factor: 144),
      ],
    );
    await catalog.saveItem(
        code: '1002', name: 'ملح', baseUnit: 'كجم', units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)]);
    await catalog.saveItem(
      code: '1003',
      name: 'أربع وحدات',
      baseUnit: 'a',
      units: const [
        ItemUnit(name: 'a', factor: 1, isBase: true),
        ItemUnit(name: 'b', factor: 2),
        ItemUnit(name: 'c', factor: 4),
        ItemUnit(name: 'd', factor: 8),
      ],
    );
    rice = (await catalog.itemByCode('1001'))!;
    salt = (await catalog.itemByCode('1002'))!;
    four = (await catalog.itemByCode('1003'))!;
    // رصيد دفتري للأرز: افتتاحي 100 حبة.
    await catalog.setOpeningBalance(rice, wh, 100, 'seed');
    order = await repo.createOrder(warehouse: wh, date: '2026-10-01', createdBy: 'seed');
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) =>
      Uint8List.fromList(TemplateWriter.build(TemplateSpec.stocktakeCount, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool canEdit = true,
    String? sessionId,
  }) =>
      xt.run(file(rows),
          mode: mode,
          dryRun: dryRun,
          allowDelete: false,
          actor: 'tester',
          expected: TemplateKind.stocktakeCount,
          sessionId: sessionId ?? order,
          canEditCounted: canEdit);

  Future<StocktakeLine> line(Item item) async =>
      (await repo.lines(order)).firstWhere((l) => l.itemId == item.id);

  group('الحفظ كما تحفظ الشاشة', () {
    test('العد يُحوَّل لوحدة الأساس ويُحسب الفرق عن الدفتري، والأرصدة لا تتغير', () async {
      final report = await import([
        ['1001', 'أرز', 'كرتون', 1, 'علبة', 2, 'حبة', 5],
      ]);
      expect((report.created, report.updated, report.failedCount), (1, 0, 0));

      final l = await line(rice);
      expect(l.systemQty, 100);
      expect(l.countedQty, 173);
      expect(l.variance, 73);
      expect(l.status, 'COUNTED');
      expect(jsonDecode(l.counts), {'كرتون': 1, 'علبة': 2, 'حبة': 5});

      // العد لا يستبدل الرصيد: لا تسوية ولا تعديل لافتتاحي حتى يُعتمد الجرد.
      expect(await db.select(db.adjustments).get(), isEmpty);
      expect((await db.select(db.openingBalances).get()).single.qty, 100);
    });

    test('يستبدل عدّ السطر السابق لا يضيف إليه، ولا يمسّ الأسطر غير الواردة', () async {
      await import([
        ['1001', 'أرز', 'حبة', 10, null, null, null, null],
        ['1002', 'ملح', 'كجم', 3, null, null, null, null],
      ]);
      final report = await import([
        ['1001', 'أرز', 'حبة', 40, null, null, null, null],
      ]);
      expect((report.created, report.updated), (0, 1));
      expect((await line(rice)).countedQty, 40);
      expect((await line(salt)).countedQty, 3);
    });

    test('عدّ مطابق لما سُجّل لا يُكتب (كالشاشة) ويُحصى «بلا تغيير»', () async {
      final rows = <List<Object?>>[
        ['1001', 'أرز', 'علبة', 2, null, null, null, null],
      ];
      await import(rows);
      final report = await import(rows);
      expect((report.ok, report.unchanged, report.failedCount), (0, 1, 0));
      expect(report.summary, contains('بلا تغيير 1'));
    });

    test('التقرير التجريبي لا يكتب ولا يدقّق', () async {
      final report = await import([
        ['1001', 'أرز', 'حبة', 10, null, null, null, null],
      ], dryRun: true);
      expect(report.created, 1);
      expect((await line(rice)).countedQty, isNull);
      expect(await AuditRepo(db).allLogs(), isEmpty);
    });

    test('تدقيق الاستيراد يحمل الأمر', () async {
      await import([
        ['1001', 'أرز', 'حبة', 10, null, null, null, null],
      ]);
      final log = (await AuditRepo(db).allLogs()).singleWhere((l) => l.action == 'excel.template.import');
      expect(jsonDecode(log.details)['sessionId'], order);
      expect(jsonDecode(log.details)['kind'], 'stocktakeCount');
    });
  });

  group('قواعد الشاشة', () {
    test('الصنف غير المدرج في الأمر يُرفض (يُضاف من الشاشة بفعلٍ صريح)', () async {
      await catalog.saveItem(
          code: '1004', name: 'جديد', baseUnit: 'حبة', units: const [ItemUnit(name: 'حبة', factor: 1, isBase: true)]);
      final report = await import([
        ['1004', 'جديد', 'حبة', 5, null, null, null, null],
        ['1002', 'ملح', 'كجم', 1, null, null, null, null],
      ]);
      expect(report.ok, 1);
      expect(report.failed.single.reason, contains('غير مدرج في أمر الجرد'));
      expect((await repo.lines(order)).length, 3, reason: 'لم يُضَف سطر مكتشف');
    });

    test('الأمر المغلق أو قيد المراجعة أو الملغى أو المجهول يُرفض كله', () async {
      expect(() => import(const [], sessionId: 'nope'), throwsA(isA<FormatException>()));
      await repo.moveToReview(order);
      expect(
        () => import(const []),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('ليس مفتوحًا'))),
      );
    });

    test('أكبر ثلاث وحدات فقط كما تعرضها الشاشة', () async {
      final report = await import([
        ['1003', 'أربع وحدات', 'a', 5, null, null, null, null], // a أصغر الأربع: غير معروضة ⇒ ✘
        ['1003', 'أربع وحدات', 'd', 1, 'c', 1, 'b', 1], // 8+4+2 = 14 ✔ (الفاشل لا يحجز الصنف)
      ]);
      expect((report.ok, report.failedCount), (1, 1));
      expect(report.failed.single.reason, contains('ليست من وحدات الصنف'));
      expect((await line(four)).countedQty, 14);
    });

    test('سطر معدود سابقًا: تصحيحه يتطلب صلاحية التعديل، والأول لا يتطلبها', () async {
      final first = await import([
        ['1001', 'أرز', 'حبة', 10, null, null, null, null],
      ], canEdit: false);
      expect(first.created, 1, reason: 'سطر غير معدود ⇒ الإضافة تكفي');

      final denied = await import([
        ['1001', 'أرز', 'حبة', 99, null, null, null, null],
      ], canEdit: false);
      expect((denied.ok, denied.failedCount), (0, 1));
      expect(denied.failed.single.reason, contains('صلاحية التعديل'));
      expect((await line(rice)).countedQty, 10);

      final allowed = await import([
        ['1001', 'أرز', 'حبة', 99, null, null, null, null],
      ], canEdit: true);
      expect(allowed.updated, 1);
      expect((await line(rice)).countedQty, 99);
    });

    test('الاستبدال غير مدعوم', () async {
      expect(() => import(const [], mode: ImportMode.replace), throwsA(isA<StateError>()));
    });

    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['1001', 'أرز', 'علبة', 2, null, null, null, null], // 2 ✔
        ['9999', 'مجهول', 'حبة', 1, null, null, null, null], // 3 ✘
        ['1002', 'سكر', 'كجم', 1, null, null, null, null], // 4 ✘ اسم
        ['1002', 'ملح', 'علبة', 1, null, null, null, null], // 5 ✘ وحدة غريبة
        ['1002', 'ملح', 'كجم', null, null, null, null, null], // 6 ✘ بلا كمية
        ['1002', 'ملح', 'كجم', -2, null, null, null, null], // 7 ✘
        ['1002', 'ملح', 'كجم', 4, null, null, null, null], // 8 ✔
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('لا يوجد صنف'));
      expect(byRow[4], contains('لا يطابق'));
      expect(byRow[5], contains('ليست من وحدات الصنف'));
      expect(byRow[6], contains('كمية وحدة 1 مطلوبة'));
      expect(byRow[7], contains('صفرًا أو أكثر'));
    });
  });

  group('التصدير', () {
    test('المعدود بكمياته وغير المعدود بكمية فارغة، وإعادة استيراده ترفض الفارغ وتقبل المعدود', () async {
      await import([
        ['1001', 'أرز', 'كرتون', 1, 'علبة', 2, 'حبة', 5],
      ]);
      final out = await xt.export(TemplateKind.stocktakeCount, sessionId: order);
      expect(out.warnings.single, contains('لم يُعدّ بعد'));

      // نعيد الملف نفسه: الأرز مطابقٌ لما سُجّل فلا يُكتب، والباقي بلا كمية فيُرفض.
      final report = await xt.run(Uint8List.fromList(out.bytes),
          mode: ImportMode.merge,
          dryRun: false,
          allowDelete: false,
          expected: TemplateKind.stocktakeCount,
          sessionId: order,
          canEditCounted: true);
      expect(report.unchanged, 1);
      expect(report.failedCount, 2);
      expect(report.failed.every((f) => f.reason.contains('كمية وحدة 1 مطلوبة')), isTrue);
    });

    test('أمر مجهول يُرفض', () async {
      expect(() => xt.export(TemplateKind.stocktakeCount, sessionId: 'nope'), throwsA(isA<StateError>()));
      expect(() => xt.export(TemplateKind.stocktakeCount), throwsA(isA<StateError>()));
    });
  });
}
