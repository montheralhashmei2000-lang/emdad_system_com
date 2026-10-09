import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/doc_numbering.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel.dart';

/// قالب تفريدة المحروقات: يمرّ بـ`FuelRepo.saveAllocation` نفسها، ونوع الوقود
/// وتاريخ البداية من النافذة، والشهري المكتوب مستقلٌّ عن الأسبوعي.
void main() {
  late AppDatabase db;
  late FuelRepo repo;
  late ExcelTemplates xt;
  late String uA, uB, uOff;

  const day = '2026-10-01';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FuelRepo(db);
    xt = ExcelTemplates(db);
    uA = (await repo.saveUnit(name: 'وحدة أ', code: 'U1')).refNo;
    uB = (await repo.saveUnit(name: 'وحدة ب', code: 'U2')).refNo;
    uOff = (await repo.saveUnit(name: 'وحدة معطلة', code: 'U9', active: false)).refNo;
    await repo.saveUnit(name: 'بلا كود'); // يُطابَق بالاسم
  });
  tearDown(() => db.close());

  Uint8List file(List<List<Object?>> rows) =>
      Uint8List.fromList(TemplateWriter.build(TemplateSpec.fuelAllocations, rows));

  Future<TemplateReport> import(
    List<List<Object?>> rows, {
    ImportMode mode = ImportMode.merge,
    bool dryRun = false,
    bool allowDelete = true,
    String fuelType = FuelType.petrol,
    String date = day,
  }) =>
      xt.run(file(rows),
          mode: mode,
          dryRun: dryRun,
          allowDelete: allowDelete,
          actor: 'tester',
          expected: TemplateKind.fuelAllocations,
          fuelType: fuelType,
          date: date);

  Future<List<FuelAllocation>> allocs({String? type}) async => [
        for (final r in await repo.allocations())
          if (type == null || r.allocation.fuelType == type) r.allocation,
      ];

  Future<FuelAllocation> seed(String unitId, String unitName, String type,
      {double monthly = 100, String start = '2026-01-01', String notes = ''}) async {
    await repo.saveAllocation(
      unitId: unitId,
      unitName: unitName,
      fuelType: type,
      periodType: FuelPeriod.monthly,
      quantityPerPeriod: monthly,
      monthlyLiters: monthly,
      weeklyLiters: monthly / 4,
      issueLocation: 'قديم',
      startDate: start,
      notes: notes,
    );
    return (await allocs()).last;
  }

  group('الكشف', () {
    test('ملف التفريدة قالبٌ وحده، ولا يلتبس بالوحدات ولا بالأصناف', () {
      expect(ExcelTemplates.detectAll(file(const [])), [TemplateKind.fuelAllocations]);
      expect(ExcelTemplates.detect(Uint8List.fromList(TemplateWriter.build(TemplateSpec.units, const []))),
          TemplateKind.units);
    });
  });

  group('الإنشاء', () {
    test('تفريدة جديدة بالحقول كما تحفظها الشاشة، ونوع الوقود والبداية من النافذة', () async {
      final report = await import([
        ['U1', 'وحدة أ', 'معسكر الشمال', 100, null],
      ]);
      expect((report.created, report.failedCount), (1, 0));
      final a = (await allocs()).single;
      expect(a.unitId, uA);
      expect(a.unitName, 'وحدة أ');
      expect(a.fuelType, FuelType.petrol);
      expect(a.periodType, FuelPeriod.monthly);
      expect((a.quantityPerPeriod, a.weeklyLiters, a.monthlyLiters), (400, 100, 400));
      expect(a.issueLocation, 'معسكر الشمال');
      expect(a.startDate, day);
      expect((a.active, a.disbursable), (true, true));
      expect(a.refNo, startsWith('تف-'));
    });

    test('الشهري المكتوب مستقلٌّ عن الأسبوعي، وفارغه أو صفره أسبوعي × 4', () async {
      await import([
        ['U1', 'وحدة أ', 'ش', 100, 450], // مستقل
        ['U2', 'وحدة ب', 'ش', 100, 0], // صفر ⇒ 400
        ['', 'بلا كود', 'ش', 25.5, null], // فارغ ⇒ 102
      ]);
      final byUnit = {for (final a in await allocs()) a.unitName: a};
      expect(byUnit['وحدة أ']!.monthlyLiters, 450);
      expect(byUnit['وحدة أ']!.weeklyLiters, 100);
      expect(byUnit['وحدة ب']!.monthlyLiters, 400);
      expect(byUnit['بلا كود']!.monthlyLiters, 102);
    });

    test('أسبوعي صفر مع شهري مكتوب مقبول', () async {
      final report = await import([
        ['U1', 'وحدة أ', 'ش', 0, 300],
      ]);
      expect(report.created, 1);
      expect((await allocs()).single.weeklyLiters, 0);
    });

    test('التدقيق كالشاشة لكل صف + تدقيق الاستيراد', () async {
      await import([
        ['U1', 'وحدة أ', 'ش', 100, null],
      ]);
      final actions = (await AuditRepo(db).allLogs()).map((l) => l.action).toList();
      expect(actions, containsAll(['fuel.allocation.create', 'excel.template.import']));
      final summary = (await AuditRepo(db).allLogs()).singleWhere((l) => l.action == 'excel.template.import');
      expect(jsonDecode(summary.details)['fuelType'], FuelType.petrol);
    });

    test('التقرير التجريبي لا يكتب ولا يدقّق ولا يستهلك رقمًا', () async {
      final numbering = DocNumbering(db);
      final nextBefore = await numbering.peek('fuel_allocations', 'تف-');
      final report = await import([
        ['U1', 'وحدة أ', 'ش', 100, null],
      ], dryRun: true);
      expect(report.created, 1);
      expect(await allocs(), isEmpty);
      // سجلات إنشاء الوحدات في setUp وحدها؛ لا تدقيق للتفريدة ولا للاستيراد.
      final actions = (await AuditRepo(db).allLogs()).map((l) => l.action).toSet();
      expect(actions, {'fuel.unit.create'});
      expect(await numbering.peek('fuel_allocations', 'تف-'), nextBefore, reason: 'لم يُستهلك رقم');
    });
  });

  group('التحقق صفًّا صفًّا', () {
    test('كل رفض بسببه ورقم صفه، والباقي يمضي', () async {
      final report = await import([
        ['U1', 'وحدة أ', 'ش', 100, null], // 2 ✔
        ['U7', 'مجهولة', 'ش', 100, null], // 3 ✘ كود
        ['U2', 'غير اسمها', 'ش', 100, null], // 4 ✘ كود موجود واسم مختلف
        ['', 'ليست موجودة', 'ش', 100, null], // 5 ✘ اسم بلا كود
        ['U9', 'وحدة معطلة', 'ش', 100, null], // 6 ✘ معطلة
        ['U2', 'وحدة ب', '', 100, null], // 7 ✘ بلا موقع
        ['U2', 'وحدة ب', 'ش', null, null], // 8 ✘ بلا أسبوعي
        ['U2', 'وحدة ب', 'ش', 'كثير', null], // 9 ✘
        ['U2', 'وحدة ب', 'ش', -1, null], // 10 ✘
        ['U2', 'وحدة ب', 'ش', 10, -5], // 11 ✘ شهري سالب
        ['U2', 'وحدة ب', 'ش', 0, 0], // 12 ✘ الاثنان صفر
        ['U2', 'وحدة ب', 'ش', 0, null], // 13 ✘ أسبوعي صفر وشهري فارغ
        ['U1', 'وحدة أ', 'ش', 5, null], // 14 ✘ مكرر
        ['U2', '', 'ش', 5, null], // 15 ✘ بلا اسم
        ['U2', 'وحدة ب', 'ش', 7, null], // 16 ✔
      ]);
      expect(report.ok, 2);
      final byRow = {for (final f in report.failed) f.row: f.reason};
      expect(byRow[3], contains('لا توجد وحدة محروقات بالكود'));
      expect(byRow[4], contains('لا يطابق'));
      expect(byRow[5], contains('باسم'));
      expect(byRow[6], contains('معطَّلة'));
      expect(byRow[7], contains('موقع الصرف مطلوب'));
      expect(byRow[8], contains('الأسبوعي مطلوب'));
      expect(byRow[9], contains('ليس رقمًا'));
      expect(byRow[10], contains('صفرًا أو أكثر'));
      expect(byRow[11], contains('الشهري'));
      expect(byRow[12], contains('صفر'));
      expect(byRow[13], contains('صفر'));
      expect(byRow[14], contains('مكررة'));
      expect(byRow[15], contains('الوحدة المستفيدة مطلوبة'));
      expect((await allocs()).length, 2);
      expect((await allocs()).firstWhere((a) => a.unitId == uA).weeklyLiters, 100, reason: 'المكرر لم يغلب الأول');
    });

    test('نوع وقود أو تاريخ غير صالح يُرفض قبل أي كتابة', () async {
      expect(() => import(const [], fuelType: 'kerosene'), throwsA(isA<FormatException>()));
      expect(() => import(const [], date: '2026-13-45'), throwsA(isA<FormatException>()));
      expect(
        () => xt.run(file(const []),
            mode: ImportMode.merge, dryRun: true, allowDelete: false, expected: TemplateKind.fuelAllocations),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('التحديث', () {
    test('يحدّث الأرقام والموقع ويُبقي الرقم والبداية والحالة والملاحظة', () async {
      final old = await seed(uA, 'وحدة أ', FuelType.petrol, start: '2026-01-01', notes: 'ملاحظة');
      final report = await import([
        ['U1', 'وحدة أ', 'موقع جديد', 80, 500],
      ]);
      expect((report.created, report.updated), (0, 1));
      final a = (await allocs()).single;
      expect(a.id, old.id);
      expect(a.refNo, old.refNo);
      expect(a.startDate, '2026-01-01', reason: 'تاريخ النافذة للجديدة فقط');
      expect(a.notes, 'ملاحظة');
      expect((a.weeklyLiters, a.monthlyLiters, a.quantityPerPeriod, a.issueLocation), (80, 500, 500, 'موقع جديد'));
    });

    test('تفريدة نوعٍ آخر للوحدة نفسها لا تُمسّ', () async {
      await seed(uA, 'وحدة أ', FuelType.diesel, monthly: 999);
      final report = await import([
        ['U1', 'وحدة أ', 'ش', 10, null],
      ]);
      expect((report.created, report.updated), (1, 0));
      expect((await allocs(type: FuelType.diesel)).single.monthlyLiters, 999);
      expect((await allocs(type: FuelType.petrol)).single.monthlyLiters, 40);
    });

    test('أكثر من تفريدة لوحدةٍ ونوعٍ يُرفض صفّها ولا يُعدَّل شيء', () async {
      await seed(uA, 'وحدة أ', FuelType.petrol, monthly: 100);
      await seed(uA, 'وحدة أ', FuelType.petrol, monthly: 200);
      final report = await import([
        ['U1', 'وحدة أ', 'ش', 10, null],
      ]);
      expect((report.ok, report.failedCount), (0, 1));
      expect(report.failed.single.reason, contains('2 تفريدات'));
      expect((await allocs()).map((a) => a.monthlyLiters).toSet(), {100.0, 200.0});
    });
  });

  group('الاستبدال', () {
    test('يحذف تفريدات النوع غير الواردة عبر deleteAllocation، ويُبقي ما صُرف عليه، ويسجّل high', () async {
      await seed(uA, 'وحدة أ', FuelType.petrol);
      final issued = await seed(uB, 'وحدة ب', FuelType.petrol);
      await seed(uOff, 'وحدة معطلة', FuelType.petrol);
      await seed(uA, 'وحدة أ', FuelType.diesel, monthly: 7);
      await db.customStatement('INSERT INTO fuel_issues (id, allocation_id) VALUES (?, ?)', ['fi-1', issued.id]);

      final rows = <List<Object?>>[
        ['U1', 'وحدة أ', 'ش', 10, null],
      ];
      final preview = await import(rows, mode: ImportMode.replace, dryRun: true);
      expect((preview.updated, preview.deleted, preview.kept), (1, 1, 1));
      expect((await allocs(type: FuelType.petrol)).length, 3, reason: 'التجريبي لا يحذف');

      final report = await import(rows, mode: ImportMode.replace);
      expect((report.updated, report.deleted, report.kept), (1, 1, 1));
      final left = (await allocs(type: FuelType.petrol)).map((a) => a.unitId).toSet();
      expect(left, {uA, uB});
      expect((await allocs(type: FuelType.diesel)).single.monthlyLiters, 7, reason: 'نوعٌ آخر لا يُمسّ');

      final logs = await AuditRepo(db).allLogs();
      expect(logs.singleWhere((l) => l.action == 'excel.template.import').risk, AuditRepo.riskHigh);
      expect(logs.where((l) => l.action == 'fuel.allocation.delete').length, 1);
    });

    test('بلا صلاحية الحذف يُرفض، وبلا صف صالح لا يُحذف شيء، والفاشل يحمي وحدته', () async {
      await seed(uA, 'وحدة أ', FuelType.petrol);
      await seed(uB, 'وحدة ب', FuelType.petrol);
      final rows = <List<Object?>>[
        ['U1', 'وحدة أ', 'ش', 10, null],
      ];
      expect(() => import(rows, mode: ImportMode.replace, allowDelete: false), throwsA(isA<StateError>()));

      final none = await import([
        ['U7', 'x', 'ش', 1, null],
      ], mode: ImportMode.replace);
      expect(none.deleted, 0);
      expect(none.warnings.single, contains('لم يُحذف شيء'));

      final guarded = await import([
        ['U1', 'وحدة أ', 'ش', 10, null],
        ['U2', 'وحدة ب', '', 10, null], // موقع فارغ ⇒ يفشل ويحمي تفريدة ب
      ], mode: ImportMode.replace);
      expect((guarded.failedCount, guarded.deleted), (1, 0));
      expect((await allocs(type: FuelType.petrol)).length, 2);
    });
  });

  group('التصدير', () {
    test('يُصدِّر أرقام الشاشة لنوعٍ واحد، وإعادة الاستيراد تعيدها', () async {
      await import([
        ['U1', 'وحدة أ', 'معسكر الشمال', 100, 450],
        ['', 'بلا كود', 'ش', 20, null],
      ]);
      await seed(uB, 'وحدة ب', FuelType.diesel, monthly: 9);
      final out = await xt.export(TemplateKind.fuelAllocations, fuelType: FuelType.petrol);
      expect(out.warnings, isEmpty);

      final copy = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(copy.close);
      final c = FuelRepo(copy);
      await c.saveUnit(name: 'وحدة أ', code: 'U1');
      await c.saveUnit(name: 'بلا كود');
      final report = await ExcelTemplates(copy).run(
        Uint8List.fromList(out.bytes),
        mode: ImportMode.merge,
        dryRun: false,
        allowDelete: false,
        expected: TemplateKind.fuelAllocations,
        fuelType: FuelType.petrol,
        date: day,
      );
      expect((report.created, report.failedCount), (2, 0));
      final got = {
        for (final r in await c.allocations()) r.allocation.unitName: (r.allocation.weeklyLiters, r.allocation.monthlyLiters)
      };
      expect(got, {'وحدة أ': (100.0, 450.0), 'بلا كود': (20.0, 80.0)});
    });

    test('نوع بلا تفريدات: ملف فارغ وتنبيه، وبلا نوع خطأ', () async {
      final out = await xt.export(TemplateKind.fuelAllocations, fuelType: FuelType.diesel);
      expect(out.warnings.single, contains('لا تفريدة'));
      expect(() => xt.export(TemplateKind.fuelAllocations), throwsA(isA<StateError>()));
    });
  });
}
