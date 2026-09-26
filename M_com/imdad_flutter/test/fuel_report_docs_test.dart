import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/document_pdf.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/domain/fuel_daily_report.dart';
import 'package:imdad/domain/fuel_report.dart';
import 'package:imdad/features/fuel/fuel_plan_row.dart';
import 'package:imdad/features/fuel/fuel_report_docs.dart';

/// أوراق تقارير المحروقات المطبوعة.
///
/// **الورقة تُرفع وتُوقَّع.** فهذه الاختبارات تحرس أن ما يُطبع يحمل ترويسة
/// الجهة وتواقيعها من الإعدادات، وأن الأقسام والإجماليات في مواضعها، وأن
/// الملف يُبنى فعلًا بالخط العربي لا يسقط عنده.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FuelRepo repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FuelRepo(db);
  });

  tearDown(() => db.close());

  Future<FuelSettingsRow> settings() async {
    await repo.saveSettings(
      lowStockPercent: 20,
      defaultDailyLiters: 200,
      defaultWeeklyLiters: 1000,
      defaultMonthlyLiters: 4000,
      parentOrg: 'قيادة القوات المشتركة',
      agencyTitle: 'هيئة إدارة القوات اليمنية',
      commandTitle: 'قيادة الفرقة الأولى',
      branchTitle: 'شعبة الإمداد والتموين',
      roleOfficer: 'مسؤول محروقات المعسكر',
      signOfficer: 'الخشعة / الثنية',
      roleSupply: 'ركن إمداد الفرقة الأولى',
      signSupply: 'عقيد / عبدالمجيد العميري',
      roleChief: 'رئيس شعبة الإمداد والتموين',
      signChief: 'عميد / علي الشامي',
    );
    return repo.settings();
  }

  FuelOfficialReport official() => FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة', 'معسكر الثنية'],
        issues: const [
          FuelReportIssue(
            date: '2026-06-21',
            fuelType: 'petrol',
            warehouse: 'معسكر الخشعة',
            qty: 27,
            beneficiary: 'يوسف نشوان',
            vehicleType: 'شاص',
            orderAuthority: 'استحقاق',
          ),
        ],
        supplies: const [
          FuelReportSupply(
            date: '2026-06-21',
            fuelType: 'diesel',
            warehouse: 'معسكر الخشعة',
            qty: 8000,
            supplier: 'شركة التوريد الوطنية',
            vehicleType: 'صهريج',
          ),
        ],
        transfers: const [
          FuelReportTransfer(
            date: '2026-06-21',
            fuelType: 'petrol',
            fromWarehouse: 'معسكر الخشعة',
            toWarehouse: 'معسكر الثنية',
            qty: 2000,
          ),
        ],
      );

  FuelDailyReport daily() => FuelDailyReportBuilder.build(
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        fuelTypes: const ['petrol', 'diesel'],
        openings: const [
          FuelDailyOpening(
            warehouse: 'معسكر الخشعة',
            fuelType: 'petrol',
            date: '2026-06-21',
            liters: 10000,
          ),
        ],
        issues: const [
          FuelDailyIssue(
            date: '2026-06-21',
            refNo: 'ص-000001',
            warehouse: 'معسكر الخشعة',
            fuelType: 'petrol',
            qty: 300,
            beneficiary: 'شعبة الإمداد',
            authority: 'استحقاق',
          ),
        ],
      );

  group('البرقية الرسمية', () {
    test('ترويستها وتواقيعها من الإعدادات لا من الكود', () async {
      final doc = FuelReportDocs.official(official(), await settings());
      expect(doc.headerLines, contains('قيادة الفرقة الأولى'));
      expect(doc.signatureLines, hasLength(3));
      // عملُ الموقّع فوق اسمه في السطر نفسه.
      expect(doc.signatureLines.first, contains('مسؤول محروقات المعسكر'));
      expect(doc.signatureLines.first, contains('الخشعة / الثنية'));
    });

    test('أقسامها بترتيب الورقة: وارد فصادرٌ من كل مادة فتحويل', () async {
      final doc = FuelReportDocs.official(official(), await settings());
      final titles = doc.sections.map((s) => s.title).toList();
      expect(titles.first, contains('معسكر الخشعة'));
      expect(titles.any((t) => t.contains('الصادر من مادة البترول')), isTrue);
      expect(titles.any((t) => t.contains('الصادر من مادة الديزل')), isTrue);
      expect(titles.any((t) => t.contains('المحوَّل إلى المعسكرات')), isTrue);
      expect(titles.last, 'خلاصة جميع المعسكرات');
    });

    test('عمود «نوع الحركة» يفصل التوريد عن التحويل', () async {
      final doc = FuelReportDocs.official(official(), await settings());
      final incoming = doc.sections.first;
      expect(incoming.headers, contains('نوع الحركة'));
      expect(incoming.rows.single, contains('توريد'));
      // ومعسكر الثنية يرى التحويل الوارد إليه «تحويل داخلي».
      final other = doc.sections.firstWhere(
          (s) => s.rows.any((r) => r.contains('تحويل داخلي')));
      expect(other.rows.any((r) => r.contains('تحويل داخلي')), isTrue);
    });

    test('لكل قسمٍ سطر إجماليّ في ذيله', () async {
      final doc = FuelReportDocs.official(official(), await settings());
      for (final s in doc.sections) {
        expect(s.totalRow, isNotNull, reason: 'قسم «${s.title}» بلا إجمالي');
        expect(s.totalRow!.length, s.headers.length,
            reason: 'سطر الإجمالي لا يطابق أعمدة «${s.title}»');
      }
    });

    test('تُبنى ورقةً فعلية بالخط العربي', () async {
      final bytes = await DocumentPdf.build(
          doc: FuelReportDocs.official(official(), await settings()));
      expect(bytes.lengthInBytes, greaterThan(1000));
    });
  });

  group('الحركة اليومية', () {
    test('الملخّص أولًا ثم تفصيل المعسكر', () async {
      final doc = FuelReportDocs.daily(daily(), await settings());
      expect(doc.sections.first.title, 'ملخّص الحركة اليومية');
      expect(doc.sections.any((s) => s.note.contains('الوارد')), isTrue);
      expect(doc.sections.any((s) => s.note == 'المنصرف'), isTrue);
    });

    test('المنصرف يحمل إجماليه، والتحويل يغيب إن لم يوجد', () async {
      final doc = FuelReportDocs.daily(daily(), await settings());
      final issued = doc.sections.firstWhere((s) => s.note == 'المنصرف');
      // الأرقام هندية، وفاصل الآلاف فاصلةٌ عادية لا العلامة المرتفعة.
      expect(issued.totalRow!.last, contains('٣٠٠'));
      expect(doc.sections.any((s) => s.note == 'التحويل'), isFalse);
    });

    test('كل سطرٍ يطابق أعمدة قسمه', () async {
      final doc = FuelReportDocs.daily(daily(), await settings());
      for (final s in doc.sections) {
        for (final r in s.rows) {
          expect(r.length, s.headers.length,
              reason: 'سطرٌ في «${s.title}${s.note}» لا يطابق أعمدته');
        }
      }
    });

    test('تُبنى ورقةً فعلية', () async {
      final bytes = await DocumentPdf.build(
          doc: FuelReportDocs.daily(daily(), await settings()));
      expect(bytes.lengthInBytes, greaterThan(1000));
    });
  });

  group('خطة التفريدة', () {
    test('جدولان بإجماليهما، وقواعد الصرف في الذيل', () async {
      final doc = FuelReportDocs.plan(
        settings: await settings(),
        petrol: const [
          FuelPlanRow(
            n: 1,
            unit: 'شعبة الإمداد',
            location: 'جميع المعسكرات',
            weekly: 500,
            monthly: 2000,
            notes: '',
          ),
        ],
        diesel: const [],
        rules: const ['الاحتياط لا يصرف إلا بتوجيه القائد'],
      );
      expect(doc.sections, hasLength(2));
      expect(doc.sections.first.totalRow, contains('٢,٠٠٠'));
      expect(doc.footerNote, contains('الاحتياط'));
      expect(doc.headerLines, isNotEmpty);
    });
  });
}
