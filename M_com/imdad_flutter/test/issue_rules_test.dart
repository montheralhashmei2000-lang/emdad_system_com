import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/issue_rules.dart';

void main() {
  final today = DateTime(2026, 9, 20);

  IssueHeader header({
    IssueTarget target = IssueTarget.unit,
    String warehouse = 'الرئيسي',
    String date = '2026-09-20',
    String unitId = 'u1',
    String facilityId = '',
    String custom = '',
  }) =>
      IssueHeader(
        target: target,
        warehouse: warehouse,
        date: date,
        unitId: unitId,
        unitName: 'السرية الأولى',
        facilityId: facilityId,
        facilityLabel: 'المطبخ المركزي (مطبخ)',
        customRecipient: custom,
      );

  group('رأس السند', () {
    test('سند مكتمل بلا ملاحظات', () {
      expect(IssueRules.headerProblems(header(), today: today), isEmpty);
    });

    test('ترتيب الرسائل كما في زر التنفيذ: المستودع ثم التاريخ ثم الجهة', () {
      final p = IssueRules.headerProblems(header(warehouse: '', date: '2026-09-21', unitId: ''), today: today);
      expect([for (final x in p) x.message], [
        '✖ اختر المستودع',
        '✖ تاريخ الصرف لا يمكن أن يكون في المستقبل',
        '✖ اختر الوحدة المستفيدة',
      ]);
      expect(p[1].isError, isTrue);
      expect(p[0].isError, isFalse, reason: 'تنبيه في لوحة التحقق، لكنه يمنع التنفيذ');
    });

    test('كل نوع توجيه يطلب جهته ويعطي اسم المستلم', () {
      expect(IssueRules.headerProblems(header(target: IssueTarget.facility), today: today).single.message,
          '✖ اختر المطبخ أو الفرن');
      expect(IssueRules.headerProblems(header(target: IssueTarget.custom, custom: '  '), today: today).single.message,
          '✖ اكتب اسم المستلم');
      expect(header(target: IssueTarget.custom, custom: ' أحمد ').recipient, 'أحمد');
      expect(header(target: IssueTarget.facility, facilityId: 'f1').recipient, 'المطبخ المركزي (مطبخ)');
      expect(header(target: IssueTarget.multiUnit).recipient, 'صرف لوحدات متعددة');
      expect(IssueRules.headerProblems(header(target: IssueTarget.multiUnit, unitId: ''), today: today), isEmpty);
    });
  });

  group('كفاية الرصيد', () {
    test('يُجمع الخصم لكل صنف قبل المقارنة', () {
      final bal = {'rice': 10.0};
      expect(IssueRules.shortage([('rice', 6)], bal), isNull);
      final s = IssueRules.shortage([('rice', 6), ('rice', 6)], bal)!;
      expect((s.itemId, s.available, s.requested), ('rice', 10.0, 12.0));
    });

    test('الصنف بلا رصيد في المستودع رصيده صفر', () {
      expect(IssueRules.shortage([('oil', 1)], const {})!.available, 0);
    });
  });

  group('الاستحقاق', () {
    test('(المقرر الشهري ÷ ٣٠) × القوة × الأيام بوحدة السطر', () {
      // ٣ كجم شهريًا للفرد، ١٢٠ فردًا، ٥ أيام = ٦٠ كجم = ١٫٢ كيس (٥٠ كجم)
      expect(
        IssueRules.entitledQty(monthlyPerPerson: 3, measureFactor: 1, strength: 120, days: 5, lineFactor: 50),
        1.2,
      );
    });

    test('بلا قوة أو بلا مقرر لا احتساب', () {
      expect(IssueRules.entitledQty(monthlyPerPerson: 3, measureFactor: 1, strength: 0, days: 5, lineFactor: 1), isNull);
      expect(IssueRules.entitledQty(monthlyPerPerson: 0, measureFactor: 1, strength: 9, days: 5, lineFactor: 1), isNull);
    });
  });

  group('موعد الصرف القادم', () {
    test('بلا صرف سابق', () {
      expect(IssueRules.nextDue(const [], today).hasHistory, isFalse);
    });

    test('أبعد نهاية تغطية بين الصرفيات', () {
      final due = IssueRules.nextDue(const [
        (date: '2026-09-18', durationDays: 3), // حتى 21
        (date: '2026-09-10', durationDays: 15), // حتى 25
      ], today);
      expect(due.date, DateTime(2026, 9, 25));
      expect(due.daysLeft, 5);
      expect(due.overdue, isFalse);
    });

    test('متأخر واليوم', () {
      expect(IssueRules.nextDue(const [(date: '2026-09-15', durationDays: 2)], today).overdue, isTrue);
      expect(IssueRules.nextDue(const [(date: '2026-09-19', durationDays: 1)], today).dueToday, isTrue);
    });
  });
}
