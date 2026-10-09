import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';

/// قالب الأرصدة الافتتاحية: Σ(كمية × معامل) بوحدة الأساس، والتثبيت يستبدل ولا
/// يضيف، والاستبدال لا يحذف افتتاحي صنفٍ له حركات في المستودع نفسه.
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late ExcelTemplates xt;
  late Item rice, salt;

  const wh = 'المخزن الرئيسي';
  const other = 'مخزن الفرع';
  const day = '2026-10-01';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    xt = ExcelTemplates(db);
    await catalog.saveWarehouse(code: 'W1', name: wh, manager: '', location: '', feedsAllCamps: true, campIds: const []);
    await catalog.saveWarehouse(code: 'W2', name: other, manager: '', location: '', feedsAllCamps: true, campIds: const []);
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
    rice = (await catalog.itemByCode('1001'))!;
    salt = (await catalog.itemByCode('1002'))!;
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) =>
      Uint8List.fromList(TemplateWriter.build(TemplateSpec.openingBalances, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
    String warehouse = wh,
    String date = day,
  }) =>
      xt.run(file(rows),
          mode: mode,
          dryRun: dryRun,
          allowDelete: allowDelete,
          actor: 'tester',
          expected: TemplateKind.openingBalances,
          warehouse: warehouse,
          date: date);

  Future<List<OpeningBalance>> opens([String warehouse = wh]) =>
      (db.select(db.openingBalances)..where((t) => t.warehouse.equals(warehouse))).get();

  Future<void> sql(String s, List<Object?> args) => db.customStatement(s, args);

  group('الكشف', () {
    test('ملف الافتتاحي ليس ملف أصناف، وعناوينه تلتبس بالعد الفعلي فتحسمهما الشاشة', () {
      final bytes = file(const []);
      expect(ExcelTemplates.detectAll(bytes), [TemplateKind.openingBalances, TemplateKind.stocktakeCount]);
      expect(ExcelTemplates.detect(bytes), isNull);
      expect(
        () => xt.run(bytes, mode: ImportMode.merge, dryRun: true, allowDelete: false),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('أكثر من قالب'))),
      );
    });

    test('ملف الأصناف يبقى أصنافًا', () {
      final items = Uint8List.fromList(TemplateWriter.build(TemplateSpec.items, const []));
      expect(ExcelTemplates.detectAll(items), [TemplateKind.items]);
    });
  });

  group('الحساب والحفظ', () {
    test('كرتون + علبتان + 5 حبات = 173 بوحدة الأساس، والمستودع والتاريخ من النافذة', () async {
      final report = await import([
        ['1001', 'أرز', 'كرتون', 1, 'علبة', 2, 'حبة', 5],
      ]);
      expect((report.created, report.failedCount), (1, 0));
      final o = (await opens()).single;
      expect((o.itemId, o.qty, o.warehouse, o.date, o.setBy), (rice.id, 173, wh, day, 'tester'));
    });

    test('وحدة واحدة بمعامل 1، وكسور تُقرَّب لثلاث خانات', () async {
      await import([
        ['1002', 'ملح', 'كجم', 2.5, null, null, null, null],
        ['1001', 'أرز', 'علبة', 0.3333, null, null, null, null],
      ]);
      final byItem = {for (final o in await opens()) o.itemId: o.qty};
      expect(byItem[salt.id], 2.5);
      expect(byItem[rice.id], 4.0, reason: '0.3333 × 12 = 3.9996 ⇒ 4.000');
    });

    test('التثبيت يستبدل الرصيد السابق ولا يضيف إليه، ولا يمسّ مستودعًا آخر', () async {
      await import([
        ['1001', 'أرز', 'حبة', 100, null, null, null, null],
      ]);
      await import([
        ['1001', 'أرز', 'حبة', 7, null, null, null, null],
      ], warehouse: other);
      final report = await import([
        ['1001', 'أرز', 'حبة', 40, null, null, null, null],
      ]);
      expect((report.created, report.updated), (0, 1));
      expect((await opens()).single.qty, 40);
      expect((await opens(other)).single.qty, 7);
    });

    test('الصفر مقبول ويُثبَّت', () async {
      await import([
        ['1001', 'أرز', 'حبة', 0, null, null, null, null],
      ]);
      expect((await opens()).single.qty, 0);
    });

    test('تقرير تجريبي لا يكتب ولا يدقّق', () async {
      final report = await import([
        ['1001', 'أرز', 'حبة', 5, null, null, null, null],
      ], dryRun: true);
      expect(report.created, 1);
      expect(await opens(), isEmpty);
      expect(await AuditRepo(db).allLogs(), isEmpty);
    });

    test('تدقيق critical لكل صنف + تدقيق الاستيراد بمستواه', () async {
      await import([
        ['1001', 'أرز', 'كرتون', 1, null, null, null, null],
        ['1002', 'ملح', 'كجم', 3, null, null, null, null],
      ]);
      final logs = await AuditRepo(db).allLogs();
      final perItem = logs.where((l) => l.action == 'OPENING_BALANCE_SET').toList();
      expect(perItem.length, 2);
      expect(perItem.every((l) => l.risk == 'critical'), isTrue);
      final summary = logs.singleWhere((l) => l.action == 'excel.template.import');
      expect(summary.risk, AuditRepo.riskNormal);
      expect(summary.details, contains(wh));
    });
  });

  group('التحقق صفًّا صفًّا', () {
    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['1001', 'أرز', 'علبة', 2, null, null, null, null], // 2 ✔
        ['9999', 'مجهول', 'حبة', 1, null, null, null, null], // 3 ✘ كود
        ['', 'بلا كود', 'حبة', 1, null, null, null, null], // 4 ✘
        ['1002', 'سكر', 'كجم', 1, null, null, null, null], // 5 ✘ اسم
        ['1002', '', 'كجم', 1, null, null, null, null], // 6 ✘ بلا اسم
        ['1002', 'ملح', null, 1, null, null, null, null], // 7 ✘ بلا وحدة 1
        ['1002', 'ملح', 'علبة', 1, null, null, null, null], // 8 ✘ وحدة ليست للصنف
        ['1002', 'ملح', 'كجم', null, null, null, null, null], // 9 ✘ بلا كمية
        ['1002', 'ملح', 'كجم', 'كثير', null, null, null, null], // 10 ✘
        ['1002', 'ملح', 'كجم', -1, null, null, null, null], // 11 ✘
        ['1001', 'أرز', 'حبة', 1, 'علبة', null, null, null], // 12 ✘ كمية 2 مطلوبة
        ['1001', 'أرز', 'حبة', 1, null, 5, null, null], // 13 ✘ كمية بلا وحدة
        ['1001', 'أرز', 'حبة', 1, 'حبة', 1, null, null], // 14 ✘ وحدة مكررة
        ['1001', 'أرز', 'حبة', 1, 'علبة', 1, 'صندوق', 1], // 15 ✘ وحدة 3 ليست للصنف
        ['1001', 'أرز', 'حبة', 9, null, null, null, null], // 16 ✘ مكرر
        ['1002', 'ملح', 'كجم', 4, null, null, null, null], // 17 ✔
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('لا يوجد صنف'));
      expect(byRow[4], contains('كود الصنف مطلوب'));
      expect(byRow[5], contains('لا يطابق'));
      expect(byRow[6], contains('اسم الصنف مطلوب'));
      expect(byRow[7], contains('وحدة 1 مطلوبة'));
      expect(byRow[8], contains('ليست من وحدات الصنف'));
      expect(byRow[9], contains('كمية وحدة 1 مطلوبة'));
      expect(byRow[10], contains('ليست رقمًا'));
      expect(byRow[11], contains('صفرًا أو أكثر'));
      expect(byRow[12], contains('كمية وحدة 2 مطلوبة'));
      expect(byRow[13], contains('بلا وحدة 2'));
      expect(byRow[14], contains('مكررة'));
      expect(byRow[15], contains('ليست من وحدات الصنف'));
      expect(byRow[16], contains('مكرر في الملف'));
      expect((await opens()).length, 2);
      expect((await opens()).firstWhere((o) => o.itemId == rice.id).qty, 24, reason: 'المكرر لم يغلب الأول');
    });

    test('مستودع أو تاريخ غير صالح يُرفض قبل أي كتابة', () async {
      expect(() => import(const [], warehouse: 'غير موجود'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026-13-45'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026-02-30'), throwsA(isA<FormatException>()));
      expect(
        () => xt.run(file(const []),
            mode: ImportMode.merge, dryRun: true, allowDelete: false, expected: TemplateKind.openingBalances),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('التصدير', () {
    test('التصدير ثم الاستيراد يعيد الأرصدة بوحدة الأساس', () async {
      await import([
        ['1001', 'أرز', 'كرتون', 1, 'علبة', 2, 'حبة', 5],
        ['1002', 'ملح', 'كجم', 3.5, null, null, null, null],
      ]);
      final out = await xt.export(TemplateKind.openingBalances, warehouse: wh);
      expect(out.warnings, isEmpty);

      final copy = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(copy.close);
      final c = CatalogRepo(copy);
      await c.saveWarehouse(code: 'W1', name: wh, manager: '', location: '', feedsAllCamps: true, campIds: const []);
      for (final i in await catalog.items()) {
        await c.saveItem(code: i.code, name: i.name, baseUnit: i.baseUnit, units: catalog.unitsOf(i));
      }
      final report = await ExcelTemplates(copy).run(
        Uint8List.fromList(out.bytes),
        mode: ImportMode.merge,
        dryRun: false,
        allowDelete: false,
        expected: TemplateKind.openingBalances,
        warehouse: wh,
        date: day,
      );
      expect((report.created, report.failedCount), (2, 0));
      final got = {
        for (final o in await (copy.select(copy.openingBalances)).get()) o.itemCode: o.qty,
      };
      expect(got, {'1001': 173.0, '1002': 3.5});
    });

    test('مستودع بلا أرصدة: ملف فارغ وتنبيه', () async {
      final out = await xt.export(TemplateKind.openingBalances, warehouse: other);
      expect(out.warnings.single, contains('لا أرصدة'));
    });
  });

  group('الاستبدال', () {
    final onlySalt = <List<Object?>>[
      ['1002', 'ملح', 'كجم', 9, null, null, null, null],
    ];

    Future<void> seed() async {
      await catalog.setOpeningBalances(wh, 'seed', [(item: rice, qty: 50.0), (item: salt, qty: 1.0)], date: day);
    }

    test('يحذف افتتاحي غير الوارد إن لم تكن له حركات في المستودع، ويسجّل high', () async {
      await seed();
      final preview = await import(onlySalt, mode: ImportMode.replace, dryRun: true);
      expect((preview.updated, preview.deleted, preview.kept), (1, 1, 0));
      expect((await opens()).length, 2, reason: 'التجريبي لا يحذف');

      final report = await import(onlySalt, mode: ImportMode.replace);
      expect((report.updated, report.deleted, report.kept), (1, 1, 0));
      expect((await opens()).single.itemId, salt.id);
      final logs = await AuditRepo(db).allLogs();
      expect(logs.singleWhere((l) => l.action == 'excel.template.import').risk, AuditRepo.riskHigh);
      expect(logs.where((l) => l.action == 'OPENING_BALANCE_CLEARED').length, 1);
    });

    test('صنف له وارد أو صرف أو تحويل في المستودع يبقى', () async {
      for (final table in ['receipts', 'issues', 'returns', 'adjustments']) {
        await db.customStatement('DELETE FROM opening_balances');
        await seed();
        await sql("INSERT INTO $table (id, item_id, warehouse, status) VALUES (?, ?, ?, 'COMPLETED')",
            ['m-$table', rice.id, wh]);
        final report = await import(onlySalt, mode: ImportMode.replace);
        expect((report.deleted, report.kept), (0, 1), reason: table);
        expect((await opens()).length, 2, reason: table);
        await sql('DELETE FROM $table', const []);
      }
    });

    test('تحويلٌ إلى المستودع أو منه يحمي الصنف أيضًا', () async {
      await seed();
      await sql("INSERT INTO transfers (id, item_id, warehouse, dest_warehouse, status) VALUES ('t1', ?, ?, ?, 'COMPLETED')",
          [rice.id, other, wh]);
      final report = await import(onlySalt, mode: ImportMode.replace);
      expect((report.deleted, report.kept), (0, 1));
    });

    test('حركات مستودعٍ آخر أو مسودة أو ملغاة لا تحمي الصنف', () async {
      await seed();
      await sql("INSERT INTO receipts (id, item_id, warehouse, status) VALUES ('r1', ?, ?, 'COMPLETED')", [rice.id, other]);
      await sql("INSERT INTO issues (id, item_id, warehouse, status) VALUES ('i1', ?, ?, 'DRAFT')", [rice.id, wh]);
      await sql("INSERT INTO issues (id, item_id, warehouse, status) VALUES ('i2', ?, ?, 'CANCELLED')", [rice.id, wh]);
      final report = await import(onlySalt, mode: ImportMode.replace);
      expect((report.deleted, report.kept), (1, 0));
    });

    test('بلا صلاحية الحذف يُرفض، وبلا صف صالح لا يُحذف شيء، والفاشل يحمي صنفه', () async {
      await seed();
      expect(() => import(onlySalt, mode: ImportMode.replace, allowDelete: false), throwsA(isA<StateError>()));

      final none = await import([
        ['9999', 'x', 'حبة', 1, null, null, null, null],
      ], mode: ImportMode.replace);
      expect(none.deleted, 0);
      expect(none.warnings.single, contains('لم يُحذف شيء'));

      final guarded = await import([
        ['1002', 'ملح', 'كجم', 9, null, null, null, null],
        ['1001', 'أرز', 'صندوق', 1, null, null, null, null], // يفشل ⇒ يحمي أرزه
      ], mode: ImportMode.replace);
      expect((guarded.failedCount, guarded.deleted), (1, 0));
      expect((await opens()).length, 2);
    });

    test('الاستبدال في مستودع لا يمسّ مستودعًا آخر', () async {
      await seed();
      await catalog.setOpeningBalances(other, 'seed', [(item: rice, qty: 3.0)], date: day);
      await import(onlySalt, mode: ImportMode.replace);
      expect((await opens(other)).single.qty, 3);
    });
  });
}
