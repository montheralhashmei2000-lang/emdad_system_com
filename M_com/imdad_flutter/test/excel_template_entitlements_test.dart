import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/daily_repo.dart';

/// قالب الاستحقاق: الصنف بكوده، والاسم للتحقق، والوحدة من وحدات الصنف.
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late DailyRepo daily;
  late ExcelTemplates xt;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    daily = DailyRepo(db);
    xt = ExcelTemplates(db);
    await catalog.saveItem(
      code: '1001',
      name: 'أرز',
      baseUnit: 'جرام',
      units: const [
        ItemUnit(name: 'جرام', factor: 1, isBase: true),
        ItemUnit(name: 'كيس', factor: 40000),
      ],
    );
    await catalog.saveItem(
      code: '1002',
      name: 'سكر',
      baseUnit: 'جرام',
      units: const [ItemUnit(name: 'جرام', factor: 1, isBase: true)],
    );
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) => Uint8List.fromList(TemplateWriter.build(TemplateSpec.entitlements, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
  }) =>
      xt.run(file(rows), mode: mode, dryRun: dryRun, allowDelete: allowDelete, actor: 'tester');

  Future<Entitlement?> ent(String code) async {
    final item = (await catalog.itemByCode(code))!;
    return (await daily.entitlements()).where((e) => e.itemId == item.id).firstOrNull;
  }

  group('الاستيراد', () {
    test('صف سليم يحفظ الكمية ووحدتها ومعاملها', () async {
      final report = await import([
        ['1001', 'أرز', 'كيس', 0.5],
      ]);
      expect(report.created, 1);
      final e = (await ent('1001'))!;
      expect((e.qtyPerPerson, e.measureUnitName, e.measureFactor), (0.5, 'كيس', 40000));
      expect(e.itemName, 'أرز');
    });

    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['1001', 'أرز', 'جرام', 3000], // 2 ✔
        ['9999', 'غير موجود', 'جرام', 1], // 3 ✘
        ['', 'بلا كود', 'جرام', 1], // 4 ✘
        ['1002', 'ملح', 'جرام', 1], // 5 ✘ اسم لا يطابق
        ['1002', '', 'جرام', 1], // 6 ✘ بلا اسم
        ['1002', 'سكر', 'كيس', 1], // 7 ✘ وحدة ليست للصنف
        ['1002', 'سكر', '', 1], // 8 ✘ بلا وحدة
        ['1002', 'سكر', 'جرام', null], // 9 ✘ بلا كمية
        ['1002', 'سكر', 'جرام', 'كثير'], // 10 ✘ ليست رقمًا
        ['1002', 'سكر', 'جرام', -1], // 11 ✘ سالبة
        ['1001', 'أرز', 'كيس', 1], // 12 ✘ مكرر
        ['1002', 'سكر', 'جرام', 0], // 13 ✔ صفر مقبول
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('لا يوجد صنف'));
      expect(byRow[4], contains('كود الصنف مطلوب'));
      expect(byRow[5], contains('لا يطابق'));
      expect(byRow[6], contains('اسم الصنف مطلوب'));
      expect(byRow[7], contains('ليست من وحدات الصنف'));
      expect(byRow[8], contains('وحدة الاستحقاق مطلوبة'));
      expect(byRow[9], contains('الكمية'));
      expect(byRow[10], contains('ليست رقمًا'));
      expect(byRow[11], contains('صفرًا أو أكثر'));
      expect(byRow[12], contains('مكرر'));
      expect((await ent('1001'))!.qtyPerPerson, 3000, reason: 'المكرر لم يغلب الأول');
      expect((await ent('1002'))!.qtyPerPerson, 0);
    });

    test('أرقام عربية في الكود والكمية تُقرأ', () async {
      final report = await import([
        ['١٠٠١', 'أرز', 'جرام', '٢٫٥'],
      ]);
      expect(report.ok, 1);
      expect((await ent('1001'))!.qtyPerPerson, 2.5);
    });

    test('التحديث يحفظ ملاحظة المقرر التي لا يحملها القالب', () async {
      final item = (await catalog.itemByCode('1001'))!;
      await daily.saveEntitlement(
          itemId: item.id, itemName: 'أرز', qtyPerPerson: 1, measureUnitName: 'جرام', measureFactor: 1, notes: 'للمرضى');
      final report = await import([
        ['1001', 'أرز', 'جرام', 9],
      ]);
      expect(report.updated, 1);
      expect((await ent('1001'))!.notes, 'للمرضى');
    });

    test('التقرير التجريبي لا يكتب', () async {
      final report = await import([
        ['1001', 'أرز', 'جرام', 3],
      ], dryRun: true);
      expect(report.created, 1);
      expect(await daily.entitlements(), isEmpty);
    });
  });

  group('التصدير', () {
    test('التصدير ثم الاستيراد يعيد النسب', () async {
      await import([
        ['1001', 'أرز', 'كيس', 0.25],
        ['1002', 'سكر', 'جرام', 1500],
      ]);
      final out = await xt.export(TemplateKind.entitlements);
      expect(out.warnings, isEmpty);

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final c = CatalogRepo(other);
      for (final i in await catalog.items()) {
        await c.saveItem(code: i.code, name: i.name, baseUnit: i.baseUnit, units: catalog.unitsOf(i));
      }
      final report = await ExcelTemplates(other).run(
        Uint8List.fromList(out.bytes),
        mode: ImportMode.merge,
        dryRun: false,
        allowDelete: false,
      );
      expect((report.created, report.failedCount), (2, 0));
      final got = {for (final e in await DailyRepo(other).entitlements()) e.itemName: (e.qtyPerPerson, e.measureUnitName)};
      expect(got, {'أرز': (0.25, 'كيس'), 'سكر': (1500.0, 'جرام')});
    });
  });

  group('الاستبدال', () {
    test('يحذف النسب غير الواردة ويسجّل high، ولا يلمس الأصناف', () async {
      await import([
        ['1001', 'أرز', 'جرام', 1],
        ['1002', 'سكر', 'جرام', 2],
      ]);
      final preview = await import([
        ['1001', 'أرز', 'جرام', 5],
      ], mode: ImportMode.replace, dryRun: true);
      expect((preview.updated, preview.deleted), (1, 1));
      expect(await ent('1002'), isNotNull);

      final report = await import([
        ['1001', 'أرز', 'جرام', 5],
      ], mode: ImportMode.replace);
      expect((report.updated, report.deleted, report.kept), (1, 1, 0));
      expect(await ent('1002'), isNull);
      expect(await catalog.itemByCode('1002'), isNotNull);
      final logs = (await AuditRepo(db).allLogs()).where((l) => l.action == 'excel.template.import');
      expect(logs.where((l) => l.risk == AuditRepo.riskHigh).length, 1);
    });

    test('بلا صلاحية الحذف يُرفض، وبلا صف صالح لا يُحذف شيء، والفاشل يحمي صنفه', () async {
      await import([
        ['1001', 'أرز', 'جرام', 1],
        ['1002', 'سكر', 'جرام', 2],
      ]);
      expect(
        () => import([
          ['1001', 'أرز', 'جرام', 5],
        ], mode: ImportMode.replace, allowDelete: false),
        throwsA(isA<StateError>()),
      );
      final none = await import([
        ['9999', 'x', 'جرام', 1],
      ], mode: ImportMode.replace);
      expect(none.deleted, 0);
      expect(none.warnings.single, contains('لم يُحذف شيء'));

      final protectedRun = await import([
        ['1001', 'أرز', 'جرام', 5],
        ['1002', 'سكر', 'كيس', 2], // وحدة خاطئة ⇒ يفشل ويحمي استحقاقه
      ], mode: ImportMode.replace);
      expect(protectedRun.failedCount, 1);
      expect(protectedRun.deleted, 0);
      expect(await ent('1002'), isNotNull);
    });
  });
}
