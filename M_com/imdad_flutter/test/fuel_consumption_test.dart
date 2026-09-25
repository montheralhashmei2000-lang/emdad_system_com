import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/fuel.dart';

/// تجميع تقرير الاستهلاك.
///
/// التقرير يُقرأ ليُعرف **من يشرب أكثر** — فترتيبه وتجميعه هما التقرير نفسه،
/// لا زينةً فوقه.
void main() {
  FuelConsumptionMove move({
    String date = '2026-06-10',
    String type = FuelType.diesel,
    String warehouse = 'الرئيسي',
    double liters = 100,
    String beneficiary = 'الكتيبة الأولى',
    String chassis = 'SH-1',
    String vehicle = 'شاص',
  }) =>
      FuelConsumptionMove(
        date: date,
        fuelType: type,
        warehouse: warehouse,
        liters: liters,
        beneficiary: beneficiary,
        chassisNo: chassis,
        vehicleType: vehicle,
      );

  group('الترشيح', () {
    final moves = [
      move(date: '2026-06-01'),
      move(date: '2026-06-15'),
      move(date: '2026-06-30'),
      move(date: '2026-07-01'),
    ];

    test('المدى شاملٌ طرفيه', () {
      // من يكتب «من ١ إلى ٣٠» يقصد الشهر كاملًا بيوميه.
      final out = FuelConsumption.filter(moves,
          from: '2026-06-01', to: '2026-06-30');
      expect(out, hasLength(3));
    });

    test('بلا مدى تمرّ الحركات كلها', () {
      expect(FuelConsumption.filter(moves), hasLength(4));
    });

    test('الترشيح بالمستودع وبالنوع', () {
      final mixed = [
        move(warehouse: 'الرئيسي', type: FuelType.diesel),
        move(warehouse: 'الفرعي', type: FuelType.diesel),
        move(warehouse: 'الرئيسي', type: FuelType.petrol),
      ];
      expect(FuelConsumption.filter(mixed, warehouse: 'الرئيسي'), hasLength(2));
      expect(
          FuelConsumption.filter(mixed, fuelType: FuelType.petrol), hasLength(1));
      expect(
        FuelConsumption.filter(mixed,
            warehouse: 'الرئيسي', fuelType: FuelType.petrol),
        hasLength(1),
      );
    });
  });

  group('التجميع', () {
    test('بالجهة المستفيدة، والأكبر أولًا', () {
      final rows = FuelConsumption.group([
        move(beneficiary: 'الأولى', liters: 100),
        move(beneficiary: 'الثانية', liters: 400),
        move(beneficiary: 'الأولى', liters: 50),
      ], FuelGroupBy.unit);

      expect(rows.first.label, 'الثانية',
          reason: 'التقرير يُقرأ ليُعرف من يشرب أكثر');
      expect(rows.first.liters, 400);
      expect(rows.last.liters, 150);
      expect(rows.last.count, 2);
    });

    test('بالمركبة: الشاصي يجمع نوع مركبته معه', () {
      final rows = FuelConsumption.group([
        move(chassis: 'SH-9', vehicle: 'شاص', liters: 80),
        move(chassis: 'SH-9', vehicle: 'شاص', liters: 20),
      ], FuelGroupBy.vehicle);
      expect(rows, hasLength(1));
      expect(rows.single.label, contains('SH-9'));
      expect(rows.single.label, contains('شاص'));
      expect(rows.single.liters, 100);
    });

    test('الصرف بلا شاصي يُجمع تحت سطرٍ يُقال فيه ذلك', () {
      final rows = FuelConsumption.group(
          [move(chassis: ''), move(chassis: '  ')], FuelGroupBy.vehicle);
      expect(rows.single.label, 'بلا رقم شاصي',
          reason: 'إخفاؤه يجعل الإجمالي لا يطابق مجموع السطور');
      expect(rows.single.count, 2);
    });

    test('النوعان يُفصلان داخل السطر الواحد', () {
      final rows = FuelConsumption.group([
        move(beneficiary: 'الأولى', type: FuelType.diesel, liters: 300),
        move(beneficiary: 'الأولى', type: FuelType.petrol, liters: 200),
      ], FuelGroupBy.unit);
      expect(rows.single.liters, 500);
      expect(rows.single.diesel, 300);
      expect(rows.single.petrol, 200);
    });

    test('بالمستودع وبالنوع', () {
      final moves = [
        move(warehouse: 'أ', type: FuelType.diesel, liters: 100),
        move(warehouse: 'ب', type: FuelType.petrol, liters: 300),
      ];
      expect(FuelConsumption.group(moves, FuelGroupBy.warehouse).first.label, 'ب');
      final byType = FuelConsumption.group(moves, FuelGroupBy.fuelType);
      expect(byType.first.label, 'بترول');
    });

    test('الحصّة من الإجمالي', () {
      final rows = FuelConsumption.group([
        move(beneficiary: 'أ', liters: 750),
        move(beneficiary: 'ب', liters: 250),
      ], FuelGroupBy.unit);
      expect(rows.first.shareOf(1000), 0.75);
      expect(rows.first.shareOf(0), 0, reason: 'قسمة على صفر');
    });

    test('بلا حركات لا سطور', () {
      expect(FuelConsumption.group(const [], FuelGroupBy.unit), isEmpty);
    });
  });

  group('الإجماليات', () {
    final moves = [
      move(type: FuelType.diesel, liters: 300),
      move(type: FuelType.petrol, liters: 200),
    ];

    test('الإجمالي وإجمالي كل نوع', () {
      expect(FuelConsumption.total(moves), 500);
      expect(FuelConsumption.totalOf(moves, FuelType.diesel), 300);
      expect(FuelConsumption.totalOf(moves, FuelType.petrol), 200);
    });

    test('المتوسط اليومي يُقاس بأيام المدى لا بأيام الصرف', () {
      // ألف لتر في يومٍ واحد من ثلاثين ليست ألفًا يوميًّا.
      final one = [move(date: '2026-06-01', liters: 1000)];
      expect(
        FuelConsumption.dailyAverage(one, from: '2026-06-01', to: '2026-06-30'),
        closeTo(33.333, 0.01),
      );
    });

    test('مدى يومٍ واحد لا يقسم على صفر', () {
      expect(
        FuelConsumption.dailyAverage([move(liters: 90)],
            from: '2026-06-10', to: '2026-06-10'),
        90,
      );
    });

    test('مدى غير صالح يعيد صفرًا لا يسقط', () {
      expect(
        FuelConsumption.dailyAverage([move()], from: '', to: ''),
        0,
      );
    });
  });
}
