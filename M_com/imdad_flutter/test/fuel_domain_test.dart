import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/fuel.dart';

/// منطق المحروقات الخالص.
///
/// الخطر هنا **حساب الفترات**: تفريدةٌ يومية تُحسب بيومٍ ناقص تُعطي الوحدة
/// أقل من حقها كل يوم، وبيومٍ زائد تصرف من العدم. ولا يظهر أيّهما في الشاشة.
void main() {
  FuelAllocationCalc alloc({
    String period = FuelPeriod.monthly,
    double qty = 1000,
    String start = '2026-01-01',
    String end = '',
    double total = 0,
    bool active = true,
    bool disbursable = true,
  }) =>
      FuelAllocationCalc(
        periodType: period,
        quantityPerPeriod: qty,
        startDate: start,
        endDate: end,
        totalQuantity: total,
        active: active,
        disbursable: disbursable,
      );

  group('عدد الفترات المنقضية', () {
    test('اليوم الأول فترةٌ كاملة لا كسرٌ منها', () {
      // تفريدة بدأت اليوم تستحق حصة اليوم، لا صفرًا حتى ينتصف الليل.
      expect(
        Fuel.periodsElapsed(
            alloc(period: FuelPeriod.daily), DateTime(2026, 1, 1)),
        1,
      );
    });

    test('اليومية تزيد فترةً كل يوم', () {
      final a = alloc(period: FuelPeriod.daily);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 10)), 10);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 2, 1)), 32);
    });

    test('الأسبوعية تزيد فترةً كل سبعة أيام', () {
      final a = alloc(period: FuelPeriod.weekly);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 7)), 1);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 8)), 2);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 15)), 3);
    });

    test('الشهرية تعتمد اليوم من الشهر لا عدد الأيام', () {
      final a = alloc(start: '2026-01-15');
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 20)), 1);
      // لم يبلغ الخامس عشر بعد، فالشهر الثاني لم يبدأ.
      expect(Fuel.periodsElapsed(a, DateTime(2026, 2, 14)), 1);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 2, 15)), 2);
      expect(Fuel.periodsElapsed(a, DateTime(2026, 4, 15)), 4);
    });

    test('ما قبل البداية صفر', () {
      expect(
        Fuel.periodsElapsed(alloc(start: '2026-06-01'), DateTime(2026, 1, 1)),
        0,
      );
    });

    test('النهاية تقطع التراكم', () {
      final a = alloc(period: FuelPeriod.daily, end: '2026-01-05');
      expect(Fuel.periodsElapsed(a, DateTime(2026, 1, 31)), 5,
          reason: 'تفريدة منتهية ظلّت تتراكم بعد نهايتها');
    });

    test('تاريخ بداية غير صالح لا يُسقط الحساب', () {
      expect(Fuel.periodsElapsed(alloc(start: ''), DateTime(2026, 1, 1)), 0);
    });
  });

  group('الاستحقاق المتراكم', () {
    test('الشهرية: ثلاثة أشهر × ألف لتر', () {
      expect(
        Fuel.entitledLiters(alloc(), DateTime(2026, 3, 1)),
        3000,
      );
    });

    test('الموقوفة لا تستحق شيئًا', () {
      expect(
        Fuel.entitledLiters(alloc(active: false), DateTime(2026, 3, 1)),
        0,
      );
    });

    test('الفترة المحددة استحقاقها إجماليها لا تراكمها', () {
      final a = alloc(period: FuelPeriod.custom, total: 750);
      expect(Fuel.entitledLiters(a, DateTime(2026, 1, 1)), 750);
      expect(Fuel.entitledLiters(a, DateTime(2027, 1, 1)), 750,
          reason: 'الفترة المحددة تراكمت مع الزمن');
    });
  });

  group('المتبقي ومانع الصرف', () {
    test('المتبقي = المستحق − المصروف', () {
      expect(
        Fuel.remainingLiters(
            allocation: alloc(), issued: 1200, asOf: DateTime(2026, 3, 1)),
        1800,
      );
    });

    test('الصرف ضمن المتبقي يجوز', () {
      expect(
        Fuel.issueBlock(
          allocation: alloc(),
          date: '2026-03-01',
          qty: 500,
          alreadyIssued: 1200,
        ),
        isNull,
      );
    });

    test('الصرف فوق المتبقي يُمنع ويُقال كم بقي', () {
      final block = Fuel.issueBlock(
        allocation: alloc(),
        date: '2026-03-01',
        qty: 5000,
        alreadyIssued: 1200,
      );
      expect(block, contains('1800'));
    });

    test('الموقوفة تُمنع', () {
      expect(
        Fuel.issueBlock(
            allocation: alloc(active: false),
            date: '2026-03-01',
            qty: 1,
            alreadyIssued: 0),
        contains('موقوفة'),
      );
    });

    test('غير القابلة للصرف تُمنع ولو كانت سارية', () {
      // سارية ومحسوبة، لكنها لا تُصرف حتى يأذن القائد.
      expect(
        Fuel.issueBlock(
            allocation: alloc(disbursable: false),
            date: '2026-03-01',
            qty: 1,
            alreadyIssued: 0),
        contains('القائد'),
      );
    });

    test('الصرف قبل البداية أو بعد النهاية يُمنع', () {
      expect(
        Fuel.issueBlock(
            allocation: alloc(start: '2026-05-01'),
            date: '2026-01-01',
            qty: 1,
            alreadyIssued: 0),
        contains('قبل بداية'),
      );
      expect(
        Fuel.issueBlock(
            allocation: alloc(end: '2026-02-01'),
            date: '2026-03-01',
            qty: 1,
            alreadyIssued: 0),
        contains('بعد نهاية'),
      );
    });

    test('المساواة للمتبقي بالضبط تجوز', () {
      expect(
        Fuel.issueBlock(
          allocation: alloc(),
          date: '2026-01-01',
          qty: 1000,
          alreadyIssued: 0,
        ),
        isNull,
        reason: 'كسور الفاصلة منعت صرف آخر لتر مستحق',
      );
    });
  });

  group('المعادل الأسبوعي والشهري', () {
    test('اليومية × ٧ أسبوعيًّا و× ٣٠ شهريًّا', () {
      final a = alloc(period: FuelPeriod.daily, qty: 100);
      expect(Fuel.weeklyOf(a), 700);
      expect(Fuel.monthlyOf(a), 3000);
    });

    test('الشهرية ÷ ٤ أسبوعيًّا', () {
      expect(Fuel.weeklyOf(alloc(qty: 4000)), 1000);
    });
  });

  group('رصيد المستودع', () {
    FuelStock stock({
      double opening = 0,
      double supplied = 0,
      double issued = 0,
      double inn = 0,
      double out = 0,
      double adj = 0,
      double cap = 0,
    }) =>
        FuelStock(
          warehouse: 'الرئيسي',
          fuelType: FuelType.diesel,
          opening: opening,
          supplied: supplied,
          issued: issued,
          transferredIn: inn,
          transferredOut: out,
          adjustments: adj,
          capacityLiters: cap,
        );

    test('الافتتاحي + الوارد + المحوَّل إليه − المصروف − المحوَّل منه', () {
      expect(
        stock(opening: 1000, supplied: 500, issued: 300, inn: 200, out: 100)
            .stock,
        1300,
      );
    });

    test('فرق الجرد يدخل الرصيد', () {
      expect(stock(opening: 1000, adj: -50).stock, 950);
    });

    test('نسبة الإشغال، وبلا سعة لا نسبة', () {
      expect(stock(opening: 5000, cap: 20000).occupancy, 25);
      expect(stock(opening: 5000).occupancy, 0);
    });

    test('الرصيد الصفري يُعدّ نفادًا', () {
      expect(stock().empty, isTrue);
      expect(stock(opening: 1).empty, isFalse);
    });
  });

  group('التحويل', () {
    test('المستودع الواحد لا يُحوَّل إلى نفسه', () {
      expect(
        Fuel.validateTransfer(
            from: 'أ', to: 'أ', qty: 10, available: 100),
        contains('واحد'),
      );
    });

    test('التحويل فوق الرصيد يُمنع', () {
      expect(
        Fuel.validateTransfer(from: 'أ', to: 'ب', qty: 500, available: 100),
        contains('100'),
        reason: 'تحويلٌ بلا رصيد يصنع لترات من العدم',
      );
    });

    test('التحويل السليم يمرّ', () {
      expect(
        Fuel.validateTransfer(from: 'أ', to: 'ب', qty: 100, available: 100),
        isNull,
      );
    });
  });

  group('مراحل الجرد', () {
    test('السلسلة: مفتوح ← عدّ ← تحليل ← مرحّل', () {
      expect(FuelStocktakeStatus.next(FuelStocktakeStatus.open),
          FuelStocktakeStatus.counting);
      expect(FuelStocktakeStatus.next(FuelStocktakeStatus.counting),
          FuelStocktakeStatus.analysis);
      expect(FuelStocktakeStatus.next(FuelStocktakeStatus.analysis),
          FuelStocktakeStatus.posted);
      expect(FuelStocktakeStatus.next(FuelStocktakeStatus.posted), isNull);
    });

    test('المرحّل لا يُعدَّل', () {
      expect(FuelStocktakeStatus.editable(FuelStocktakeStatus.analysis), isTrue);
      expect(FuelStocktakeStatus.editable(FuelStocktakeStatus.posted), isFalse,
          reason: 'أرقام الجرد المرحّل صارت جزءًا من الرصيد');
    });
  });

  group('التنبيهات', () {
    test('النفاد يُنبَّه عليه لكل نوع', () {
      final alerts = FuelAlerts.forStocks([
        const FuelStock(
            warehouse: 'الرئيسي',
            fuelType: FuelType.diesel,
            capacityLiters: 10000),
        const FuelStock(
            warehouse: 'الرئيسي',
            fuelType: FuelType.petrol,
            opening: 5000,
            capacityLiters: 10000),
      ]);
      expect(alerts.any((a) => a.title.contains('نفاد ديزل')), isTrue);
      expect(alerts.any((a) => a.title.contains('نفاد بترول')), isFalse);
    });

    test('الانخفاض بالنسبة لا بالكمية', () {
      // ٥٠٠ لتر في خزّان سعته ٢٠ ألفًا = ٢٫٥٪ — انخفاض.
      final alerts = FuelAlerts.forStocks([
        const FuelStock(
            warehouse: 'الرئيسي',
            fuelType: FuelType.diesel,
            opening: 500,
            capacityLiters: 20000),
      ]);
      expect(alerts.any((a) => a.title.contains('رصيد منخفض')), isTrue);
    });

    test('الامتلاء المرتفع يُنبَّه عليه', () {
      final alerts = FuelAlerts.forStocks([
        const FuelStock(
            warehouse: 'الرئيسي',
            fuelType: FuelType.diesel,
            opening: 9500,
            capacityLiters: 10000),
      ]);
      expect(alerts.any((a) => a.title.contains('إشغال مرتفع')), isTrue);
    });

    test('بلا سعة معلومة لا تنبيه نسبة', () {
      final alerts = FuelAlerts.forStocks([
        const FuelStock(
            warehouse: 'الرئيسي', fuelType: FuelType.diesel, opening: 10),
      ]);
      expect(alerts.where((a) => a.id.startsWith('low-')), isEmpty);
    });

    test('قرب نفاد التفريدة يُنبَّه عنده', () {
      expect(
        FuelAlerts.forAllocation(code: 'ت-1', entitled: 1000, remaining: 50)
            ?.tone,
        'warn',
      );
      expect(
        FuelAlerts.forAllocation(code: 'ت-1', entitled: 1000, remaining: 0)
            ?.tone,
        'danger',
      );
      expect(
        FuelAlerts.forAllocation(code: 'ت-1', entitled: 1000, remaining: 500),
        isNull,
      );
    });
  });
}
