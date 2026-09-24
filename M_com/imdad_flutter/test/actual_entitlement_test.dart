import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/date_span.dart';
import 'package:imdad/domain/entitlement_actual.dart';
import 'package:imdad/domain/entitlements.dart';

/// حساب الاستحقاق الفعلي: الفترات، وخصم المرتجع، ومصدرا الاستحقاق.

void main() {
  group('حلّ الفترة', () {
    test('اليومي يوم واحد', () {
      expect(PeriodKind.resolve(PeriodKind.daily, '2026-03-15').days, 1);
    });

    test('الأسبوعي يبدأ السبت لا الاثنين', () {
      // ٢٠٢٦-٠٣-١٥ يوم أحد. أسبوع العمل هنا سبت–جمعة، فبدؤه بالاثنين يقسم
      // الأسبوع الميداني على تقريرين.
      final span = PeriodKind.resolve(PeriodKind.weekly, '2026-03-15');
      expect(DateTime.parse(span.start).weekday, DateTime.saturday);
      expect(span.days, 7);
      expect(span.contains('2026-03-15'), isTrue);
    });

    test('السبت نفسه يبدأ أسبوعه لا الذي قبله', () {
      final span = PeriodKind.resolve(PeriodKind.weekly, '2026-03-14');
      expect(span.start, '2026-03-14');
    });

    test('الشهري يغطي الشهر كاملًا', () {
      final span = PeriodKind.resolve(PeriodKind.monthly, '2026-02-15');
      expect(span.start, '2026-02-01');
      expect(span.end, '2026-02-28');
      expect(span.days, 28);
    });

    test('المخصص يستعمل التاريخين المعطَيين', () {
      final span = PeriodKind.resolve(
        PeriodKind.custom,
        '2026-03-01',
        customStart: '2026-03-10',
        customEnd: '2026-03-20',
      );
      expect(span.days, 11);
    });
  });

  group('المصروف والمرتجع', () {
    List<ConsumptionMove> moves(List<(String, String, double)> raw, {bool active = true}) => [
          for (final (id, type, qty) in raw)
            ConsumptionMove(itemId: id, type: type, baseQty: qty, active: active),
        ];

    test('المرتجع يُخصم من المصروف', () {
      // وحدة أخذت ١٠٠ وردّت ٣٠: استهلكت ٧٠ لا ١٠٠. حصرُ الحساب في الصرف يحرمها
      // من استحقاقها في الشهر التالي.
      final rows = ActualEntitlement.compute(
        entitled: const {'i1': 100},
        moves: moves([('i1', 'OUT', 100), ('i1', 'RETURN_IN', 30)]),
      );
      expect(rows.single.consumed, 70);
      expect(rows.single.balance, 30);
    });

    test('الوارد والتحويل والافتتاحي ليست استهلاكًا', () {
      final rows = ActualEntitlement.compute(
        entitled: const {'i1': 100},
        moves: moves([
          ('i1', 'IN', 500),
          ('i1', 'TRANSFER', 200),
          ('i1', 'OPENING', 900),
          ('i1', 'OUT', 40),
        ]),
      );
      expect(rows.single.consumed, 40, reason: 'حُسبت حركة مستودع استهلاكًا');
    });

    test('السند غير الفعّال لا يدخل الحساب', () {
      final rows = ActualEntitlement.compute(
        entitled: const {'i1': 100},
        moves: moves([('i1', 'OUT', 100)], active: false),
      );
      expect(rows.single.consumed, 0, reason: 'حُسبت مسودة أو سند ملغى');
    });

    test('صنف صُرف بلا استحقاق يُعلَّم', () {
      final rows = ActualEntitlement.compute(
        entitled: const {},
        moves: moves([('i9', 'OUT', 10)]),
      );
      expect(rows.single.unentitled, isTrue);
      expect(rows.single.ratio, 0, reason: 'قسمة على صفر');
    });

    test('الترتيب بأبعد انحراف لا بأكبر كمية', () {
      final rows = ActualEntitlement.compute(
        entitled: const {'كبير': 1000, 'منحرف': 10},
        moves: moves([('كبير', 'OUT', 995), ('منحرف', 'OUT', 400)]),
      );
      expect(rows.first.itemId, 'منحرف');
    });

    test('الإجماليات تجمع الصافي لا المصروف وحده', () {
      final rows = ActualEntitlement.compute(
        entitled: const {'i1': 100, 'i2': 50},
        moves: moves([
          ('i1', 'OUT', 80),
          ('i1', 'RETURN_IN', 10),
          ('i2', 'OUT', 60),
        ]),
      );
      final t = ActualEntitlement.totals(rows);
      expect(t.entitled, 150);
      expect(t.consumed, 130);
      expect(t.balance, 20);
    });
  });

  group('المستحق من نسب المقرر', () {
    const scale = Entitlement(
      itemId: 'i1',
      qtyPerPerson: 30, // ٣٠ كجم شهريًا للفرد ⇒ ١ كجم يوميًا
      measureFactor: 1,
    );

    test('المعدل اليومي × متوسط القوة × الأيام', () {
      final out = ActualEntitlement.fromScale(
        scales: const [scale],
        personsByDay: const {'2026-03-01': 100, '2026-03-02': 100},
        days: 2,
      );
      expect(out['i1'], 200);
    });

    test('اليوم غير المسجّل لا يخفض المتوسط', () {
      // يومان مسجّلان بقوة ١٠٠ ويوم ثالث بلا تفريدة: المتوسط ١٠٠ لا ٦٦٫٦.
      // اعتبار اليوم صفرًا يخفض استحقاق الوحدة بسبب إهمال إداري لا بسبب نقص
      // في قوتها.
      final out = ActualEntitlement.fromScale(
        scales: const [scale],
        personsByDay: const {'2026-03-01': 100, '2026-03-02': 100, '2026-03-03': 0},
        days: 3,
      );
      expect(out['i1'], 300);
    });

    test('بلا تفريدة إطلاقًا ⇒ صفر لا انهيار', () {
      final out = ActualEntitlement.fromScale(
        scales: const [scale],
        personsByDay: const {},
        days: 30,
      );
      expect(out['i1'], 0);
    });

    test('وحدة القياس تُحوَّل إلى وحدة الأساس', () {
      // كيسان شهريًا للفرد، والكيس ٤٠ كجم ⇒ ٨٠ كجم شهريًا.
      const bags = Entitlement(itemId: 'i2', qtyPerPerson: 2, measureFactor: 40);
      final out = ActualEntitlement.fromScale(
        scales: const [bags],
        personsByDay: const {'2026-03-01': 30},
        days: 30,
      );
      expect(out['i2'], closeTo(80 * 30, 0.01));
    });
  });

  group('مدى التواريخ', () {
    test('المقارنة النصية ترتيبها ترتيب الزمن', () {
      const span = DateSpan('2026-03-01', '2026-03-31');
      expect(span.contains('2026-03-15'), isTrue);
      expect(span.contains('2026-04-01'), isFalse);
      expect(span.contains('2026-02-28'), isFalse);
    });

    test('المدى المقلوب صفر أيام ولا يرمي', () {
      const span = DateSpan('2026-03-10', '2026-03-01');
      expect(span.days, 0);
      expect(span.isValid, isFalse);
      expect(span.dates, isEmpty);
    });
  });
}
