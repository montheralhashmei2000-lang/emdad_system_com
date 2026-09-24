import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/entitlements.dart';
import 'package:imdad/domain/rules_engine.dart';
import 'package:imdad/domain/strength.dart';
import 'package:imdad/domain/unit_carry.dart';

void main() {
  group('ترحيل الكميات إلى الوحدة الأكبر', () {
    test('4 كيس (×40) + 50 كجم = 5 كيس + 10 كجم', () {
      final out = UnitCarry.normalize([
        UnitLine(unitName: 'كيس', factor: 40, qty: 4),
        UnitLine(unitName: 'كجم', factor: 1, qty: 50),
      ]);
      expect(out.map((l) => '${l.qty.toInt()} ${l.unitName}').toList(), ['5 كيس', '10 كجم']);
    });

    test('يحذف الوحدة الصغرى عند انطباق المعامل تمامًا', () {
      final out = UnitCarry.normalize([
        UnitLine(unitName: 'كيس', factor: 40, qty: 4),
        UnitLine(unitName: 'كجم', factor: 1, qty: 40),
      ]);
      expect(out.length, 1);
      expect(out.first.qty, 5);
    });

    test('ثلاث وحدات: 1 كرتون + 13 علبة + 30 حبة = 2 كرتون + 3 علبة + 6 حبة', () {
      final out = UnitCarry.normalize([
        UnitLine(unitName: 'كرتون', factor: 144, qty: 1),
        UnitLine(unitName: 'علبة', factor: 12, qty: 13),
        UnitLine(unitName: 'حبة', factor: 1, qty: 30),
      ]);
      expect(out.map((l) => '${l.qty.toInt()} ${l.unitName}').toList(),
          ['2 كرتون', '3 علبة', '6 حبة']);
    });

    test('وحدة واحدة فقط لا تُرحَّل', () {
      final out = UnitCarry.normalize([UnitLine(unitName: 'كجم', factor: 1, qty: 120)]);
      expect(out.single.qty, 120);
    });

    test('يدمج السطور ذات الوحدة نفسها', () {
      final out = UnitCarry.normalize([
        UnitLine(unitName: 'كيس', factor: 40, qty: 1),
        UnitLine(unitName: 'كجم', factor: 1, qty: 40),
        UnitLine(unitName: 'كجم', factor: 1, qty: 20),
      ]);
      expect(out.map((l) => '${l.qty.toInt()} ${l.unitName}').toList(), ['2 كيس', '20 كجم']);
    });
  });

  group('نسب الاستحقاق', () {
    const rice = Entitlement(
      itemId: 'rice',
      qtyPerPerson: 30, // 30 كجم شهريًا للفرد
      measureUnitName: 'كجم',
      measureFactor: 1,
    );

    test('المعدل اليومي = الشهري ÷ 30', () {
      expect(rice.dailyBaseRate, 1);
    });

    test('الاستحقاق = المعدل × الأفراد × الأيام', () {
      final r = EntitlementEngine.compute(entitlement: rice, persons: 660, days: 1);
      expect(r.totalBaseQty, 660);
      final r3 = EntitlementEngine.compute(entitlement: rice, persons: 660, days: 3);
      expect(r3.totalBaseQty, 1980);
    });

    test('وحدة قياس أكبر تُحوَّل إلى وحدة الأساس', () {
      const sacks = Entitlement(
        itemId: 'rice',
        qtyPerPerson: 1, // كيس واحد شهريًا للفرد
        measureUnitName: 'كيس',
        measureFactor: 40,
      );
      expect(sacks.monthlyBaseQty, 40);
      final r = EntitlementEngine.compute(entitlement: sacks, persons: 30, days: 30);
      expect(r.totalBaseQty, 1200); // (40/30) × 30 × 30
    });

    test('فحص كفاية الرصيد', () {
      final check = EntitlementEngine.assess(
        entitlement: rice,
        persons: 100,
        days: 2,
        availableBaseQty: 150,
      );
      expect(check.due, 200);
      expect(check.shortage, 50);
      expect(check.isEnough, isFalse);
    });
  });

  group('حساب القوة ليوم محدد', () {
    final calc = StrengthCalculator(
      units: const [
        UnitNode(id: 'camp', isCamp: true, facilityIds: ['kitchen'], name: 'معسكر الثنية'),
        UnitNode(id: 'u1', parentId: 'camp', facilityIds: ['kitchen']),
        UnitNode(id: 'u2', parentId: 'camp', facilityIds: ['kitchen']),
      ],
      records: const [
        StrengthRecord(unitId: 'u1', campId: 'camp', date: '2026-09-15', total: 400),
        StrengthRecord(unitId: 'u2', campId: 'camp', date: '2026-09-15', total: 260),
        StrengthRecord(unitId: 'camp', campId: 'camp', date: '2026-09-14', total: 5940, mode: 'camp'),
      ],
    );

    test('قوة المطبخ = 660 يوم 15 و5940 يوم 14 وصفر يوم 13 (لا تُجمع الأيام)', () {
      expect(calc.facilityStrengthOn('kitchen', '2026-09-15'), 660);
      expect(calc.facilityStrengthOn('kitchen', '2026-09-14'), 5940);
      expect(calc.facilityStrengthOn('kitchen', '2026-09-13'), 0);
    });

    test('قوة المعسكر: مجموع وحداته يوم 15، وسجله المباشر يوم 14', () {
      expect(calc.campStrengthOn('camp', '2026-09-15').total, 660);
      expect(calc.campStrengthOn('camp', '2026-09-15').source, StrengthSource.unitsSum);
      expect(calc.campStrengthOn('camp', '2026-09-14').total, 5940);
      expect(calc.campStrengthOn('camp', '2026-09-14').source, StrengthSource.campRecord);
    });

    test('قوة وحدة: سجلها يوم 15، وحصتها من المعسكر يوم 14، وصفر يوم 13', () {
      expect(calc.unitStrengthOn('u1', '2026-09-15'), 400);
      expect(calc.unitStrengthOn('u1', '2026-09-14'), 3600); // 5940 × (400/660)
      expect(calc.unitStrengthOn('u1', '2026-09-13'), 0);
    });
  });

  group('محرك القواعد', () {
    final engine = RulesEngine();

    test('تحليل قاعدة وتنفيذها عند تحقق الشرط', () {
      final res = engine.run(
        "IF stock('rice') < 100 THEN notify('الرصيد منخفض')",
        {
          'stockMap': {'rice': 40}
        },
      );
      expect(res.fired.length, 1);
      expect(res.notifications.single, 'الرصيد منخفض');
      expect(res.blocked, isFalse);
    });

    test('لا تُنفَّذ عند عدم تحقق الشرط', () {
      final res = engine.run(
        "IF stock('rice') < 100 THEN notify('الرصيد منخفض')",
        {
          'stockMap': {'rice': 400}
        },
      );
      expect(res.fired, isEmpty);
    });

    test('شرطان بـ AND وإجراء حظر', () {
      final res = engine.run(
        "IF stock('rice') <= 50 AND daysLeft('') < 3 THEN notify('حرج'); block('')",
        {
          'stockMap': {'rice': 50},
          'daysLeft': 2,
        },
      );
      expect(res.notifications.single, 'حرج');
      expect(res.blocked, isTrue);
    });

    test('تتجاهل الأسطر الفارغة والتعليقات والصياغة غير الصحيحة', () {
      final rules = engine.parse('# تعليق\n\nسطر خاطئ\nIF qty() > 1 THEN notify(\'ok\')');
      expect(rules.length, 1);
      expect(rules.single.actions.single.action, 'notify');
    });
  });
}
