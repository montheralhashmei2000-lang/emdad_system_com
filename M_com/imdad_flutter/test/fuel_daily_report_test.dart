import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/fuel_daily_report.dart';
import 'package:imdad/domain/fuel_report.dart';

/// تقرير الحركة اليومية.
///
/// **خيط الرصيد هو التقرير.** يومٌ يفتح بما أغلق به سابقُه؛ فإن انقطع الخيط
/// صار التقرير أرقامًا متجاورة لا دفترًا، وأول من يكتشف ذلك هو من يوقّع عليه.
void main() {
  const petrol = 'petrol';
  const diesel = 'diesel';

  FuelDailyReport build({
    String from = '2026-06-21',
    String to = '2026-06-21',
    List<String> camps = const ['معسكر الخشعة'],
    List<String> types = const [petrol, diesel],
    List<FuelDailyOpening> openings = const [],
    List<FuelDailySupply> supplies = const [],
    List<FuelDailyIssue> issues = const [],
    List<FuelDailyTransfer> transfers = const [],
    List<FuelDailyAdjustment> adjustments = const [],
    List<String> kinds = FuelMoveKind.all,
  }) =>
      FuelDailyReportBuilder.build(
        range: FuelDateRange(from, to),
        warehouses: camps,
        fuelTypes: types,
        openings: openings,
        supplies: supplies,
        issues: issues,
        transfers: transfers,
        adjustments: adjustments,
        kinds: kinds,
      );

  FuelDailyBalance balanceOf(FuelDailyReport r, String day, String type,
          [String camp = 'معسكر الخشعة']) =>
      r.days
          .firstWhere((d) => d.date == day)
          .balances
          .firstWhere((b) => b.warehouse == camp && b.fuelType == type);

  group('سلسلة الأيام', () {
    test('المدى يُفرد يومًا يومًا ولو خلا من حركة', () {
      final r = build(from: '2026-06-21', to: '2026-06-24');
      expect(r.days.map((d) => d.date),
          ['2026-06-21', '2026-06-22', '2026-06-23', '2026-06-24']);
      expect(r.isEmpty, isTrue);
    });

    test('الافتتاحي في أول يومٍ وحده، ثم المتبقي من السابق', () {
      final r = build(
        from: '2026-06-01',
        to: '2026-06-03',
        openings: const [
          FuelDailyOpening(
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            date: '2026-06-01',
            liters: 10000,
          ),
        ],
        issues: const [
          FuelDailyIssue(
            date: '2026-06-01',
            refNo: 'ص-1',
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            qty: 1000,
          ),
          FuelDailyIssue(
            date: '2026-06-02',
            refNo: 'ص-2',
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            qty: 500,
          ),
        ],
      );

      final d1 = balanceOf(r, '2026-06-01', petrol);
      final d2 = balanceOf(r, '2026-06-02', petrol);
      final d3 = balanceOf(r, '2026-06-03', petrol);

      expect(d1.opening, 10000, reason: 'الافتتاحي في يومه');
      expect(d1.closing, 9000);
      expect(d2.opening, 9000, reason: 'اليوم الثاني يفتح بما أغلق به الأول');
      expect(d2.closing, 8500);
      expect(d3.opening, 8500);
      expect(d3.closing, 8500, reason: 'يومٌ بلا حركة لا يغيّر الرصيد');
    });

    test('ما وقع قبل المدى يُرحَّل ولا يُعرض سطرًا', () {
      final r = build(
        from: '2026-06-10',
        to: '2026-06-10',
        openings: const [
          FuelDailyOpening(
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            date: '2026-06-01',
            liters: 5000,
          ),
        ],
        supplies: const [
          FuelDailySupply(
            date: '2026-06-05',
            refNo: 'ت-1',
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            qty: 2000,
          ),
        ],
      );
      final b = balanceOf(r, '2026-06-10', petrol);
      expect(b.opening, 7000, reason: 'الافتتاحي والتوريد السابقان مُرحَّلان');
      expect(b.incoming, 0);
      expect(r.days.single.camps.single.incoming, isEmpty);
    });
  });

  group('أبواب الحركة', () {
    const supplies = [
      FuelDailySupply(
        date: '2026-06-21',
        refNo: 'ت-1',
        warehouse: 'معسكر الخشعة',
        fuelType: petrol,
        qty: 8000,
        supplier: 'شركة التوريد الوطنية',
      ),
    ];
    const issues = [
      FuelDailyIssue(
        date: '2026-06-21',
        refNo: 'ص-1',
        warehouse: 'معسكر الخشعة',
        fuelType: petrol,
        qty: 300,
        beneficiary: 'شعبة الإمداد',
      ),
      FuelDailyIssue(
        date: '2026-06-21',
        refNo: 'ص-2',
        warehouse: 'معسكر الخشعة',
        fuelType: diesel,
        qty: 200,
        beneficiary: 'مولد المعسكر',
      ),
    ];
    const transfers = [
      FuelDailyTransfer(
        date: '2026-06-21',
        refNo: 'ح-1',
        fromWarehouse: 'معسكر الخشعة',
        toWarehouse: 'معسكر الثنية',
        fuelType: petrol,
        qty: 1000,
      ),
    ];

    test('كل بابٍ في جدوله، وإجماليه في ذيله', () {
      final r = build(
          supplies: supplies, issues: issues, transfers: transfers);
      final c = r.days.single.camps.single;
      expect(c.incoming, hasLength(1));
      expect(c.incomingTotal, 8000);
      expect(c.issued, hasLength(2));
      expect(c.issuedTotal, 500, reason: 'المنصرف يشمل البترول والديزل');
      expect(c.transfers, hasLength(1));
      expect(c.transferTotal, 1000);
    });

    test('ترشيح نوع الحركة يُسقط جدوله ولا يمسّ الرصيد', () {
      final r = build(
        supplies: supplies,
        issues: issues,
        transfers: transfers,
        kinds: const [FuelMoveKind.issued],
      );
      final c = r.days.single.camps.single;
      expect(c.incoming, isEmpty);
      expect(c.transfers, isEmpty);
      expect(c.issued, hasLength(2));
      // الرصيد حقيقةٌ لا تتبع ما اختار القارئ أن يراه.
      expect(balanceOf(r, '2026-06-21', petrol).incoming, 8000);
      expect(balanceOf(r, '2026-06-21', petrol).transferOut, 1000);
    });

    test('التحويل لا يُطبع إن لم يوجد', () {
      final plain = build(supplies: supplies, issues: issues);
      expect(plain.days.single.camps.single.hasTransfers, isFalse);
      final withT = build(transfers: transfers);
      expect(withT.days.single.camps.single.hasTransfers, isTrue);
    });

    test('التحويل يخرج من معسكرٍ ويدخل آخر في اليوم نفسه', () {
      final r = build(
        camps: const ['معسكر الخشعة', 'معسكر الثنية'],
        transfers: transfers,
      );
      final from = balanceOf(r, '2026-06-21', petrol, 'معسكر الخشعة');
      final to = balanceOf(r, '2026-06-21', petrol, 'معسكر الثنية');
      expect(from.transferOut, 1000);
      expect(from.transferNet, -1000);
      expect(from.closing, -1000, reason: 'خرج من خزّانٍ فارغ فبان بالسالب');
      expect(to.transferIn, 1000);
      expect(to.closing, 1000);
      // على مستوى الفرقة لا يزيد الوقود ولا ينقص.
      expect(r.totalOf((b) => b.transferNet), 0);
    });

    test('سطر التحويل يعرف اتجاهه وطرفه', () {
      final r = build(
          camps: const ['معسكر الخشعة', 'معسكر الثنية'], transfers: transfers);
      final out = r.days.single.camps.first.transfers.single;
      final inn = r.days.single.camps.last.transfers.single;
      expect(out.outbound, isTrue);
      expect(out.party, 'معسكر الثنية');
      expect(inn.outbound, isFalse);
      expect(inn.party, 'معسكر الخشعة');
    });
  });

  group('الجرد والعنوان', () {
    test('فرق الجرد يدخل رصيد يومه ولا يُفرد عمودًا إن لم يقع', () {
      final plain = build();
      expect(plain.hasAdjustments, isFalse);

      final r = build(
        openings: const [
          FuelDailyOpening(
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            date: '2026-06-21',
            liters: 1000,
          ),
        ],
        adjustments: const [
          FuelDailyAdjustment(
            date: '2026-06-21',
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            delta: -50,
          ),
        ],
      );
      expect(r.hasAdjustments, isTrue);
      expect(balanceOf(r, '2026-06-21', petrol).closing, 950,
          reason: 'لولا إدخاله لانحرف الرصيد عن الواقع');
    });

    test('العنوان يسمّي المعسكر إن كان واحدًا ويُجمل إن تعدّد', () {
      expect(build().title, contains('معسكر الخشعة'));
      expect(build(camps: const ['أ', 'ب']).title,
          contains('جميع المعسكرات والمحطات'));
    });

    test('المنصرف يحمل جهة الأمر والغرض والشاصي', () {
      final r = build(
        issues: const [
          FuelDailyIssue(
            date: '2026-06-21',
            refNo: 'ص-9',
            warehouse: 'معسكر الخشعة',
            fuelType: petrol,
            qty: 40,
            beneficiary: 'الدوريات',
            authority: 'مكتب القائد',
            purpose: 'تعزيز المقر',
            chassisNo: 'SH-7',
          ),
        ],
      );
      final m = r.days.single.camps.single.issued.single;
      expect(m.authority, 'مكتب القائد');
      expect(m.purpose, 'تعزيز المقر');
      expect(m.notes, contains('SH-7'));
    });
  });
}
