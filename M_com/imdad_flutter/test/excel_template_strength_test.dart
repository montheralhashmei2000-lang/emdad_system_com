import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as zip_lib;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/daily_repo.dart';

/// قالب تفريدة المعسكر: معادلات الإجمالي، وقراءة القيمة المخزَّنة أو حسابها،
/// والمعسكر واليوم يُختاران عند الاستيراد.
void main() {
  late AppDatabase db;
  late CatalogRepo catalog;
  late DailyRepo daily;
  late ExcelTemplates xt;
  late String camp, camp2, u1, u2;

  const day = '2026-10-01';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    daily = DailyRepo(db);
    xt = ExcelTemplates(db);
    camp = await catalog.saveUnit(code: '1', name: 'المعسكر الأول', type: 'camp', category: 'معسكر');
    u1 = await catalog.saveUnit(
        code: '1-1', name: 'الكتيبة الأولى', parentId: camp, parentName: 'المعسكر الأول', category: 'وحدة');
    u2 = await catalog.saveUnit(
        code: '1-2', name: 'الكتيبة الثانية', parentId: camp, parentName: 'المعسكر الأول', category: 'وحدة');
    camp2 = await catalog.saveUnit(code: '2', name: 'المعسكر الثاني', type: 'camp', category: 'معسكر');
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) => Uint8List.fromList(TemplateWriter.build(TemplateSpec.strength, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
    String? campId,
    String date = day,
  }) =>
      xt.run(file(rows),
          mode: mode, dryRun: dryRun, allowDelete: allowDelete, actor: 'tester', campId: campId ?? camp, date: date);

  Future<Strength?> rowOf(String unitId, {String date = day}) async =>
      (await daily.strengths(date: date)).where((s) => s.unitId == unitId).firstOrNull;

  group('الاستيراد', () {
    test('B وC وD: يُحفظ B+C، والنسبة المئوية تُشتق من الزيادة', () async {
      final report = await import([
        ['الكتيبة الأولى', 200, 20, 220],
        ['الكتيبة الثانية', 100, 10, null], // D فارغ ⇒ يُحسب
      ]);
      expect((report.created, report.failedCount), (2, 0));
      final a = (await rowOf(u1))!;
      expect((a.soldierCount, a.officerCount, a.total, a.pct), (200, 20, 220, 10));
      expect(a.campId, camp);
      expect(a.campName, 'المعسكر الأول');
      expect(a.mode, 'detail');
      expect((await rowOf(u2))!.total, 110);
    });

    test('نسبة الزيادة الفارغة صفر، وصف الإجمالي الأخير يُتخطّى بلا فشل', () async {
      final report = await import([
        ['الكتيبة الأولى', 50, null, null],
        ['الإجمالي', 50, 0, 50],
      ]);
      expect((report.created, report.failedCount), (1, 0));
      expect((await rowOf(u1))!.officerCount, 0);
    });

    test('الإجمالي المخالف لـB+C تحذير لا رفض، والمعتمد B+C', () async {
      final report = await import([
        ['الكتيبة الأولى', 10, 1, 99],
        ['الكتيبة الثانية', 10, 1, 11],
      ]);
      expect(report.failedCount, 0);
      expect(report.warnings.single, contains('صف 2'));
      expect(report.warnings.single, contains('99'));
      expect((await rowOf(u1))!.total, 11);
    });

    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['الكتيبة الأولى', 10, 1, 11], // 2 ✔
        ['وحدة من معسكر آخر', 5, 0, 5], // 3 ✘
        ['', 5, 0, 5], // 4 ✘
        ['الكتيبة الثانية', -1, 0, -1], // 5 ✘ سالبة
        ['الكتيبة الثانية', 2.5, 0, 2.5], // 6 ✘ كسر
        ['الكتيبة الثانية', 'كثير', 0, null], // 7 ✘
        ['الكتيبة الثانية', null, 0, null], // 8 ✘ بلا قوة
        ['الكتيبة الثانية', 5, -2, 3], // 9 ✘ زيادة سالبة
        ['الكتيبة الأولى', 7, 0, 7], // 10 ✘ مكرر
        ['الكتيبة الثانية', 4, 0, 4], // 11 ✔
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('ليست من وحدات المعسكر'));
      expect(byRow[4], contains('اسم الوحدة مطلوب'));
      expect(byRow[5], contains('عددًا صحيحًا'));
      expect(byRow[6], contains('عددًا صحيحًا'));
      expect(byRow[7], contains('ليست رقمًا'));
      expect(byRow[8], contains('مطلوبة'));
      expect(byRow[9], contains('سالبة'));
      expect(byRow[10], contains('مكررة'));
      expect((await rowOf(u1))!.soldierCount, 10, reason: 'المكرر لم يغلب الأول');
      expect((await rowOf(u2))!.soldierCount, 4);
    });

    test('الأرقام العربية تُقرأ', () async {
      await import([
        ['الكتيبة الأولى', '١٠٠', '١٠', null],
      ]);
      expect((await rowOf(u1))!.total, 110);
    });

    test('معسكر أو تاريخ غير صالح يُرفض قبل أي كتابة', () async {
      expect(() => import(const [], campId: u1), throwsA(isA<FormatException>()),
          reason: 'الوحدة الفرعية ليست معسكرًا');
      expect(() => import(const [], campId: 'nope'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026/10/01'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026-13-45'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026-02-30'), throwsA(isA<FormatException>()));
    });

    test('بلا معسكر وتاريخ يرفض الواجهة الموحّدة', () async {
      expect(
        () => xt.run(file(const []), mode: ImportMode.merge, dryRun: true, allowDelete: false),
        throwsA(isA<StateError>()),
      );
    });

    test('صف المعسكر نفسه يُقبل وحده بوضع camp، ولا يُخلط بالوحدات', () async {
      final only = await import([
        ['المعسكر الأول', 500, 50, 550],
      ]);
      expect(only.created, 1);
      final c = (await rowOf(camp))!;
      expect((c.mode, c.total), ('camp', 550));

      final mixed = await import([
        ['المعسكر الأول', 500, 50, 550],
        ['الكتيبة الأولى', 10, 1, 11],
      ]);
      expect(mixed.failedCount, 1);
      expect(mixed.failed.single.reason, contains('لا يُخلط'));
      expect(mixed.ok, 1);
    });
  });

  group('الدمج', () {
    test('يحدّث الوحدة الواردة ويُبقي بقية وحدات اليوم، ولا يمسّ يومًا آخر ولا معسكرًا آخر', () async {
      await daily.saveStrength(
          unitId: u1, unitName: 'الكتيبة الأولى', campId: camp, campName: 'م', date: day, soldierCount: 1);
      await daily.saveStrength(
          unitId: u2, unitName: 'الكتيبة الثانية', campId: camp, campName: 'م', date: day, soldierCount: 2);
      await daily.saveStrength(
          unitId: u1, unitName: 'الكتيبة الأولى', campId: camp, campName: 'م', date: '2026-09-30', soldierCount: 3);

      final report = await import([
        ['الكتيبة الأولى', 9, 1, 10],
      ]);
      expect((report.updated, report.created, report.deleted), (1, 0, 0));
      expect((await rowOf(u1))!.soldierCount, 9);
      expect((await rowOf(u2))!.soldierCount, 2, reason: 'غير واردة ⇒ تبقى');
      expect((await rowOf(u1, date: '2026-09-30'))!.soldierCount, 3);
      expect((await daily.strengths(date: day)).length, 2, reason: 'لا سجل ثانٍ للوحدة نفسها');
    });

    test('التقرير التجريبي لا يكتب', () async {
      final report = await import([
        ['الكتيبة الأولى', 9, 1, 10],
      ], dryRun: true);
      expect(report.created, 1);
      expect(await daily.strengths(), isEmpty);
    });

    test('سجل بالوضع الآخر يُحذف بتحذير، لئلا يُحصى اليوم مرتين', () async {
      await daily.saveStrength(
          unitId: camp, unitName: 'المعسكر الأول', campId: camp, campName: 'م', date: day, soldierCount: 500, mode: 'camp');
      final report = await import([
        ['الكتيبة الأولى', 9, 1, 10],
      ]);
      expect(report.deleted, 1);
      expect(report.warnings.single, contains('الوضع الآخر'));
      expect((await daily.strengths(date: day)).map((s) => s.mode).toSet(), {'detail'});
    });
  });

  group('الاستبدال', () {
    test('يستبدل تفريدة المعسكر واليوم وحدهما ويسجّل high', () async {
      await daily.saveStrength(
          unitId: u1, unitName: 'الكتيبة الأولى', campId: camp, campName: 'م', date: day, soldierCount: 1);
      await daily.saveStrength(
          unitId: u2, unitName: 'الكتيبة الثانية', campId: camp, campName: 'م', date: day, soldierCount: 2);
      await daily.saveStrength(
          unitId: camp2, unitName: 'المعسكر الثاني', campId: camp2, campName: 'م٢', date: day, soldierCount: 7, mode: 'camp');

      final preview = await import([
        ['الكتيبة الأولى', 9, 0, 9],
      ], mode: ImportMode.replace, dryRun: true);
      expect((preview.updated, preview.deleted), (1, 1));
      expect(await rowOf(u2), isNotNull);

      final report = await import([
        ['الكتيبة الأولى', 9, 0, 9],
      ], mode: ImportMode.replace);
      expect((report.updated, report.deleted, report.kept), (1, 1, 0));
      expect(await rowOf(u2), isNull);
      expect((await rowOf(u1))!.soldierCount, 9);
      expect((await rowOf(camp2))!.soldierCount, 7, reason: 'معسكر آخر لا يُمسّ');
      final logs = (await AuditRepo(db).allLogs()).where((l) => l.action == 'excel.template.import').toList();
      expect(logs.single.risk, AuditRepo.riskHigh);
      expect(jsonDecode(logs.single.details)['campId'], camp);
      expect(jsonDecode(logs.single.details)['date'], day);
    });

    test('بلا صلاحية الحذف يُرفض، وبلا صف صالح لا يُحذف شيء', () async {
      await daily.saveStrength(
          unitId: u2, unitName: 'الكتيبة الثانية', campId: camp, campName: 'م', date: day, soldierCount: 2);
      expect(
        () => import([
          ['الكتيبة الأولى', 9, 0, 9],
        ], mode: ImportMode.replace, allowDelete: false),
        throwsA(isA<StateError>()),
      );
      final none = await import([
        ['غريبة', 9, 0, 9],
      ], mode: ImportMode.replace);
      expect(none.deleted, 0);
      expect(await rowOf(u2), isNotNull);
    });
  });

  group('التصدير والمعادلات', () {
    Future<void> seed() async {
      await daily.saveCampStrength(campId: camp, date: day, rows: const [
        StrengthEntry(
            unitId: 'x', unitName: 'x', campName: 'x', soldierCount: 0, officerCount: 0, pct: 0),
      ]);
      await daily.deleteCampStrength(campId: camp, date: day);
      await daily.saveStrength(
          unitId: u1, unitName: 'الكتيبة الأولى', campId: camp, campName: 'المعسكر الأول', date: day,
          soldierCount: 200, officerCount: 20, pct: 10);
      await daily.saveStrength(
          unitId: u2, unitName: 'الكتيبة الثانية', campId: camp, campName: 'المعسكر الأول', date: day,
          soldierCount: 100, officerCount: 10, pct: 10);
    }

    String sheetXml(List<int> bytes) {
      final zip = zip_lib.ZipDecoder().decodeBytes(bytes);
      final wb = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      final names = RegExp(r'<sheet [^>]*name="([^"]+)"').allMatches(wb).map((m) => m[1]!).toList();
      final i = names.indexOf(TemplateSpec.dataSheet);
      return utf8.decode(zip.findFile('xl/worksheets/sheet${i + 1}.xml')!.content as List<int>);
    }

    test('الإجمالي معادلة =B+C لكل صف، وآخر صف SUM لكل عمود، والزيادة رقم لا معادلة', () async {
      await seed();
      final out = await xt.export(TemplateKind.strength, campId: camp, date: day);
      final xml = sheetXml(out.bytes);
      expect(xml, contains('<f>B2+C2</f>'));
      expect(xml, contains('<f>B3+C3</f>'));
      expect(xml, contains('<f>SUM(B2:B3)</f>'));
      expect(xml, contains('<f>SUM(C2:C3)</f>'));
      expect(xml, contains('<f>SUM(D2:D3)</f>'));
      expect(RegExp(r'<f>').allMatches(xml).length, 5, reason: 'سطران + ثلاثة مجاميع، ولا معادلة في C');
      expect(xml, isNot(contains('<f>C')), reason: 'عمود الزيادة قيمة');
    });

    test('إعادة استيراد الملف المصدَّر (معادلات بلا قيمة مخزَّنة) تحسب B+C بلا تحذير', () async {
      await seed();
      final out = await xt.export(TemplateKind.strength, campId: camp, date: day);
      await daily.deleteCampStrength(campId: camp, date: day);

      final report = await xt.run(Uint8List.fromList(out.bytes),
          mode: ImportMode.merge, dryRun: false, allowDelete: false, campId: camp, date: day);
      expect((report.created, report.failedCount), (2, 0));
      expect(report.warnings, isEmpty);
      expect((await rowOf(u1))!.total, 220);
      expect((await rowOf(u2))!.total, 110);
    });

    test('معادلة بقيمة مخزَّنة (ملف Excel محسوب) تُقرأ قيمتها وتُقارَن', () async {
      await seed();
      final out = await xt.export(TemplateKind.strength, campId: camp, date: day);
      // يحاكي Excel بعد الحفظ: يضيف القيمة المحسوبة بعد كل معادلة. الأولى صحيحة
      // (220)، والثانية خاطئة عمدًا (999).
      final zip = zip_lib.ZipDecoder().decodeBytes(out.bytes);
      final wb = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      final names = RegExp(r'<sheet [^>]*name="([^"]+)"').allMatches(wb).map((m) => m[1]!).toList();
      final path = 'xl/worksheets/sheet${names.indexOf(TemplateSpec.dataSheet) + 1}.xml';
      var xml = utf8.decode(zip.findFile(path)!.content as List<int>);
      xml = xml.replaceFirst('<f>B2+C2</f>', '<f>B2+C2</f><v>220</v>').replaceFirst('<f>B3+C3</f>', '<f>B3+C3</f><v>999</v>');
      final patched = zip_lib.Archive();
      for (final f in zip) {
        patched.addFile(f.name == path ? zip_lib.ArchiveFile(f.name, utf8.encode(xml).length, utf8.encode(xml)) : f);
      }
      final bytes = Uint8List.fromList(zip_lib.ZipEncoder().encode(patched)!);
      await daily.deleteCampStrength(campId: camp, date: day);

      final report = await xt.run(bytes,
          mode: ImportMode.merge, dryRun: false, allowDelete: false, campId: camp, date: day);
      expect(report.failedCount, 0);
      expect(report.warnings.single, contains('999'), reason: 'المخالفة وحدها تُنبَّه');
      expect((await rowOf(u2))!.total, 110, reason: 'المعتمد B+C لا القيمة المخزَّنة');
    });

    test('لا تفريدة ⇒ ملف فارغ بلا صف مجاميع (SUM على نطاق فارغ خطأ) وتنبيه', () async {
      final out = await xt.export(TemplateKind.strength, campId: camp, date: day);
      expect(out.warnings.single, contains('لا تفريدة'));
      expect(sheetXml(out.bytes), isNot(contains('<f>')));
    });

    test('الملف ورقتان: البيانات والتعليمات، وتعليمات الزيادة تشرح أنها عدد', () async {
      final out = await xt.export(TemplateKind.strength, campId: camp, date: day);
      final zip = zip_lib.ZipDecoder().decodeBytes(out.bytes);
      final wb = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      expect(wb, contains(TemplateSpec.dataSheet));
      expect(wb, contains(TemplateSpec.instructionsSheet));
      expect(TemplateSpec.strength.instructions.join('\n'), contains('عدد أفراد الزيادة'));
    });
  });
}
