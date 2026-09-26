import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/fuel_report.dart';

/// بناء البرقية الرسمية.
///
/// الورقة تُرفع وتُوقَّع، فخطأٌ في مداها أو في ترقيم سطورها ليس خطأ عرض —
/// هو رقمٌ خاطئ أمام القيادة.
void main() {
  FuelReportIssue issue({
    String date = '2026-06-21',
    String type = 'petrol',
    String warehouse = 'معسكر الخشعة',
    double qty = 100,
    String beneficiary = 'شعبة الإمداد',
    String driver = '',
    String vehicle = 'شاص',
    String authority = '',
    String purpose = '',
    String justification = '',
    String notes = '',
    String source = 'allocation',
  }) =>
      FuelReportIssue(
        date: date,
        fuelType: type,
        warehouse: warehouse,
        qty: qty,
        beneficiary: beneficiary,
        driver: driver,
        vehicleType: vehicle,
        orderAuthority: authority,
        purpose: purpose,
        justification: justification,
        notes: notes,
        source: source,
      );

  FuelReportSupply supply({
    String date = '2026-06-21',
    String type = 'diesel',
    String warehouse = 'معسكر الخشعة',
    double qty = 8000,
    String supplier = 'شركة التوريد الوطنية',
    String vehicle = 'صهريج',
  }) =>
      FuelReportSupply(
        date: date,
        fuelType: type,
        warehouse: warehouse,
        qty: qty,
        supplier: supplier,
        vehicleType: vehicle,
      );

  group('مدى الفترة', () {
    test('اليومي يومٌ واحد', () {
      final r = FuelDateRange.of(FuelReportPeriod.daily,
          date: '2026-06-21', from: '', to: '');
      expect(r.from, '2026-06-21');
      expect(r.to, '2026-06-21');
      expect(r.label, '2026/06/21');
    });

    test('الأسبوعي ينتهي باليوم المختار ويبدأ قبله بستة', () {
      // التقرير الأسبوعي يُرفع في نهاية الأسبوع عن الأيام السبعة الماضية.
      final r = FuelDateRange.week('2026-06-21');
      expect(r.from, '2026-06-15');
      expect(r.to, '2026-06-21');
      expect(r.label, '2026/06/15 — 2026/06/21');
    });

    test('الشهري شهرٌ تقويميّ كامل مهما كان اليوم', () {
      final r = FuelDateRange.month('2026-06-21');
      expect(r.from, '2026-06-01');
      expect(r.to, '2026-06-30');
    });

    test('فبراير الكبيس يُحسب بأيامه لا بثلاثين', () {
      expect(FuelDateRange.month('2028-02-10').to, '2028-02-29');
    });

    test('المدى شاملٌ طرفيه', () {
      const r = FuelDateRange('2026-06-01', '2026-06-30');
      expect(r.covers('2026-06-01'), isTrue);
      expect(r.covers('2026-06-30'), isTrue);
      expect(r.covers('2026-05-31'), isFalse);
      expect(r.covers('2026-07-01'), isFalse);
      expect(r.covers(''), isFalse);
    });
  });

  group('بناء البرقية', () {
    test('يُفرز الصادر بالمعسكر وبالمادة', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة', 'معسكر الثنية'],
        issues: [
          issue(warehouse: 'معسكر الخشعة', type: 'petrol', qty: 100),
          issue(warehouse: 'معسكر الخشعة', type: 'diesel', qty: 50),
          issue(warehouse: 'معسكر الثنية', type: 'petrol', qty: 300),
        ],
        supplies: const [],
      );
      expect(r.sections, hasLength(2));
      expect(r.sections.first.petrolTotal, 100);
      expect(r.sections.first.dieselTotal, 50);
      expect(r.sections.last.petrolTotal, 300);
      expect(r.grandPetrol, 400);
      expect(r.grandDiesel, 50);
      expect(r.grandTotal, 450);
    });

    test('ما خرج عن المدى لا يدخل الورقة', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        issues: [
          issue(date: '2026-06-20', qty: 999),
          issue(date: '2026-06-21', qty: 100),
          issue(date: '2026-06-22', qty: 999),
        ],
        supplies: [supply(date: '2026-06-20')],
      );
      expect(r.grandPetrol, 100);
      expect(r.sections.single.incoming, isEmpty);
    });

    test('السطور تُرقَّم من واحدٍ داخل كل جدول', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        issues: [
          issue(type: 'petrol'),
          issue(type: 'petrol'),
          issue(type: 'diesel'),
        ],
        supplies: const [],
      );
      final s = r.sections.single;
      expect([for (final x in s.petrol) x.n], [1, 2]);
      expect([for (final x in s.diesel) x.n], [1],
          reason: 'ترقيم الديزل يبدأ من واحد لا من حيث انتهى البترول');
    });

    test('الجهة المستفيدة تُستبدل بالسائق ثم بشرطة', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        issues: [
          issue(beneficiary: '', driver: 'أبو سارة'),
          issue(beneficiary: '', driver: '', vehicle: ''),
        ],
        supplies: const [],
      );
      final rows = r.sections.single.petrol;
      expect(rows.first.beneficiary, 'أبو سارة');
      expect(rows.last.beneficiary, '—',
          reason: 'لا يُترك حقلٌ فارغًا في ورقةٍ تُرفع');
      expect(rows.last.vehicleType, '—');
    });

    test('جهة الأمر تُستنتج من المصدر إن لم تُكتب', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        issues: [
          issue(authority: '', source: 'allocation'),
          issue(authority: '', source: 'exceptional'),
          issue(authority: 'مكتب القائد', source: 'exceptional'),
        ],
        supplies: const [],
      );
      final rows = r.sections.single.petrol;
      expect(rows[0].authority, 'استحقاق');
      expect(rows[1].authority, 'أمر استثنائي');
      expect(rows[2].authority, 'مكتب القائد');
    });

    test('الغرض يسقط إلى المبرر عند خلوّه', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة'],
        issues: [issue(purpose: '', justification: 'تعزيز المقر')],
        supplies: const [],
      );
      expect(r.sections.single.petrol.single.purpose, 'تعزيز المقر');
    });

    test('العنوان يسمّي المعسكر إن كان واحدًا ويُجمل إن تعدّد', () {
      final one = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الثنية'],
        issues: const [],
        supplies: const [],
      );
      expect(one.title, contains('محطة الوقود في معسكر الثنية'));
      expect(one.title, contains('اليومية'));
      expect(one.showSummary, isFalse,
          reason: 'خلاصةٌ بسطرٍ واحد تكرّر ما فوقها');

      final many = FuelReportBuilder.build(
        period: FuelReportPeriod.monthly,
        range: const FuelDateRange('2026-06-01', '2026-06-30'),
        warehouses: const ['أ', 'ب'],
        issues: const [],
        supplies: const [],
      );
      expect(many.title, contains('جميع المعسكرات'));
      expect(many.title, contains('الشهرية'));
      expect(many.showSummary, isTrue);
    });

    test('الوارد يُفرز بمعسكره ويُجمع', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الخشعة', 'معسكر الثنية'],
        issues: const [],
        supplies: [
          supply(warehouse: 'معسكر الخشعة', qty: 8000),
          supply(warehouse: 'معسكر الثنية', qty: 12000, type: 'petrol'),
        ],
      );
      expect(r.sections.first.incoming.single.qty, 8000);
      expect(r.sections.last.incoming.single.fuelType, 'petrol');
      expect(r.incomingTotal, 20000);
    });

    test('التحويل يظهر واردًا هنا وصادرًا هناك', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر الثنية', 'مقر قيادة الفرقة'],
        issues: const [],
        supplies: const [],
        transfers: const [
          FuelReportTransfer(
            date: '2026-06-21',
            fuelType: 'petrol',
            fromWarehouse: 'معسكر الثنية',
            toWarehouse: 'مقر قيادة الفرقة',
            qty: 2000,
            driver: 'يوسف الشمري',
            vehicleType: 'صهريج',
          ),
        ],
      );
      final from = r.sections.first;
      final to = r.sections.last;

      expect(from.outgoing.single.toCamp, 'مقر قيادة الفرقة');
      expect(from.transferredOutTotal, 2000);
      expect(to.incoming.single.isTransfer, isTrue);
      expect(to.incoming.single.supplier, contains('معسكر الثنية'));
      expect(to.transferredInTotal, 2000);
    });

    test('التحويل لا يُحسب توريدًا ولا صرفًا', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['أ', 'ب'],
        issues: [issue(warehouse: 'أ', qty: 100)],
        supplies: [supply(warehouse: 'أ', qty: 8000)],
        transfers: const [
          FuelReportTransfer(
            date: '2026-06-21',
            fuelType: 'diesel',
            fromWarehouse: 'أ',
            toWarehouse: 'ب',
            qty: 500,
          ),
        ],
      );
      // ما دخل الفرقة توريدًا ثمانية آلاف، لا ثمانية آلاف وخمسمئة.
      expect(r.grandSupplied, 8000);
      expect(r.grandTransferredIn, 500);
      expect(r.grandTransferredOut, 500);
      // والمصروف على السندات مئة، والمحوَّل لا يدخله.
      expect(r.grandTotal, 100);
      expect(r.sections.first.outTotal, 600,
          reason: 'ما خرج من خزّان «أ» صرفًا وتحويلًا');
      expect(r.incomingTotal, 8500, reason: 'وارد الجدولين معًا');
    });

    test('تحويلٌ خارج المدى لا يدخل الورقة', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['أ', 'ب'],
        issues: const [],
        supplies: const [],
        transfers: const [
          FuelReportTransfer(
            date: '2026-06-20',
            fuelType: 'diesel',
            fromWarehouse: 'أ',
            toWarehouse: 'ب',
            qty: 500,
          ),
        ],
      );
      expect(r.sections.first.outgoing, isEmpty);
      expect(r.isEmpty, isTrue);
    });

    test('الوارد يُرتَّب بالتاريخ ويُرقَّم بعد الدمج', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.custom,
        range: const FuelDateRange('2026-06-01', '2026-06-30'),
        warehouses: const ['أ'],
        issues: const [],
        supplies: [supply(date: '2026-06-10', warehouse: 'أ')],
        transfers: const [
          FuelReportTransfer(
            date: '2026-06-05',
            fuelType: 'petrol',
            fromWarehouse: 'ب',
            toWarehouse: 'أ',
            qty: 300,
          ),
        ],
      );
      final rows = r.sections.single.incoming;
      expect(rows.map((x) => x.n), [1, 2]);
      expect(rows.first.isTransfer, isTrue,
          reason: 'الأسبق تاريخًا أولًا مهما كان بابه');
    });

    test('يومٌ بلا حركة يُبنى فارغًا لا يسقط', () {
      final r = FuelReportBuilder.build(
        period: FuelReportPeriod.daily,
        range: const FuelDateRange('2026-06-21', '2026-06-21'),
        warehouses: const ['معسكر العبر'],
        issues: const [],
        supplies: const [],
      );
      expect(r.isEmpty, isTrue);
      expect(r.sections.single.petrol, isEmpty);
      expect(r.sections.single.incomingTotal, 0);
    });
  });
}
