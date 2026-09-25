import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/meal_plan_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/domain/meal_plan.dart';

/// خطط الوجبات: المدى، والاحتياج من القوة اليومية، والمقارنة.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('مدى الخطة', () {
    test('الأسبوعية سبعة أيام لا ثمانية', () {
      final span = MealPlanRules.spanOf(MealPlanType.weekly, '2026-03-01');
      expect(span.end, '2026-03-07');
      expect(span.days, 7);
    });

    test('نصف الشهرية أربعة عشر يومًا', () {
      expect(MealPlanRules.spanOf(MealPlanType.biweekly, '2026-03-01').days, 14);
    });

    test('الشهرية تنتهي بآخر الشهر لا بعد ثلاثين يومًا', () {
      // فبراير ٢٠٢٦ ثمانية وعشرون يومًا: حساب «+٣٠ يومًا» يمتد إلى مارس
      // فيتداخل مع خطته.
      final span = MealPlanRules.spanOf(MealPlanType.monthly, '2026-02-01');
      expect(span.end, '2026-02-28');
      expect(span.days, 28);
    });

    test('المدى المقلوب مرفوض', () {
      expect(MealPlanRules.validateSpan(const DateSpan('2026-03-10', '2026-03-01')), isNotNull);
      expect(MealPlanRules.validateSpan(const DateSpan('2026-03-01', '2026-03-07')), isNull);
    });

    test('التقاطع يُكشف في الطرفين', () {
      const a = DateSpan('2026-03-01', '2026-03-07');
      expect(a.overlaps(const DateSpan('2026-03-07', '2026-03-14')), isTrue);
      expect(a.overlaps(const DateSpan('2026-03-08', '2026-03-14')), isFalse);
    });
  });

  group('حساب الاحتياج', () {
    test('يُضرب في قوة كل يوم لا في متوسط الفترة', () {
      // يومان بقوة مختلفة: ١٠٠ ثم ٢٠٠، والكمية ٠٫٥ للفرد.
      // الصواب ٥٠+١٠٠ = ١٥٠. والمتوسط (١٥٠×٠٫٥×٢) يعطي ١٥٠ أيضًا هنا،
      // فيُميَّز بيوم بلا وجبة: الخطة تذكر اليوم الأول وحده.
      final entries = [
        const MealEntry(
          entryDate: '2026-03-01',
          mealType: MealType.lunch,
          itemId: 'i1',
          qtyPerPerson: 0.5,
        ),
      ];
      final needs = MealPlanCalc.requirements(
        entries: entries,
        personsByDay: {'2026-03-01': 100, '2026-03-02': 200},
      );
      expect(needs.single.baseQty, 50,
          reason: 'حُسبت قوة يوم لا وجبة فيه');
    });

    test('يوم بلا تفريدة يُحسب صفرًا لا يُقدَّر', () {
      final needs = MealPlanCalc.requirements(
        entries: [
          const MealEntry(
            entryDate: '2026-03-02',
            mealType: MealType.lunch,
            itemId: 'i1',
            qtyPerPerson: 2,
          ),
        ],
        personsByDay: const {'2026-03-01': 100},
      );
      expect(needs.single.baseQty, 0, reason: 'قُدِّرت قوة يوم غير مسجّل');
    });

    test('المعامل يحوّل إلى وحدة الأساس', () {
      final needs = MealPlanCalc.requirements(
        entries: [
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.lunch,
            itemId: 'i1',
            qtyPerPerson: 2,
            factor: 40, // كيسان × ٤٠ كجم
          ),
        ],
        personsByDay: const {'2026-03-01': 10},
      );
      expect(needs.single.baseQty, 800);
    });

    test('الأصناف تُجمَّع عبر الوجبات والأيام', () {
      final needs = MealPlanCalc.requirements(
        entries: [
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.breakfast,
            itemId: 'i1',
            qtyPerPerson: 1,
          ),
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.dinner,
            itemId: 'i1',
            qtyPerPerson: 2,
          ),
          const MealEntry(
            entryDate: '2026-03-02',
            mealType: MealType.lunch,
            itemId: 'i1',
            qtyPerPerson: 1,
          ),
        ],
        personsByDay: const {'2026-03-01': 10, '2026-03-02': 10},
      );
      expect(needs.single.baseQty, 40);
      expect(needs.single.days, 2, reason: 'أيام الظهور لا عدد السطور');
    });
  });

  group('مقارنة خطتين', () {
    test('تقيس الكمية للفرد لا الإجمالي', () {
      final diffs = MealPlanCalc.compare(
        a: [
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.lunch,
            itemId: 'رز',
            qtyPerPerson: 0.2,
            itemName: 'رز',
          ),
        ],
        b: [
          const MealEntry(
            entryDate: '2026-04-01',
            mealType: MealType.lunch,
            itemId: 'رز',
            qtyPerPerson: 0.3,
            itemName: 'رز',
          ),
        ],
      );
      final rice = diffs.firstWhere((d) => d.itemId == 'رز');
      expect(rice.delta, closeTo(0.1, 0.0001));
      expect(rice.pct, closeTo(50, 0.01));
    });

    test('الصنف الجديد والصنف المُسقَط يُميَّزان', () {
      final diffs = MealPlanCalc.compare(
        a: [
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.lunch,
            itemId: 'old',
            qtyPerPerson: 1,
          ),
        ],
        b: [
          const MealEntry(
            entryDate: '2026-03-01',
            mealType: MealType.lunch,
            itemId: 'new',
            qtyPerPerson: 1,
          ),
        ],
      );
      expect(diffs.firstWhere((d) => d.itemId == 'old').onlyInA, isTrue);
      expect(diffs.firstWhere((d) => d.itemId == 'new').onlyInB, isTrue);
    });
  });

  group('دورة الخطة', () {
    Future<String> plan({String start = '2026-03-01'}) async {
      final res = await MealPlanRepo(db).savePlan(
        name: 'خطة الأسبوع',
        planType: MealPlanType.weekly,
        span: MealPlanRules.spanOf(MealPlanType.weekly, start),
      );
      expect(res.ok, isTrue, reason: res.error);
      return res.planId;
    }

    Future<void> addLunch(String id, String date) async {
      final res = await MealPlanRepo(db).addEntry(
        planId: id,
        entryDate: date,
        mealType: MealType.lunch,
        itemId: 'i1',
        itemCode: 'X1',
        itemName: 'رز',
        unitName: 'كجم',
        factor: 1,
        qtyPerPerson: 0.25,
      );
      expect(res.ok, isTrue, reason: res.error);
    }

    test('لا تُنشَّط خطة بلا وجبات', () async {
      final id = await plan();
      final res = await MealPlanRepo(db).activate(id);
      expect(res.ok, isFalse);
      expect(res.error, contains('بلا وجبات'));
    });

    test('لا خطتان نشطتان على المدى نفسه', () async {
      final repo = MealPlanRepo(db);
      final a = await plan();
      await addLunch(a, '2026-03-01');
      expect((await repo.activate(a)).ok, isTrue);

      final b = await plan(start: '2026-03-04');
      await addLunch(b, '2026-03-04');
      final res = await repo.activate(b);
      expect(res.ok, isFalse, reason: 'نُشّطت خطتان تتقاطعان على المطبخ نفسه');
    });

    test('مدخل خارج المدى مرفوض', () async {
      final id = await plan();
      final res = await MealPlanRepo(db).addEntry(
        planId: id,
        entryDate: '2026-04-01',
        mealType: MealType.lunch,
        itemId: 'i1',
        itemCode: '',
        itemName: 'رز',
        unitName: 'كجم',
        factor: 1,
        qtyPerPerson: 1,
      );
      expect(res.ok, isFalse);
      expect(res.error, contains('خارج مدى'));
    });

    test('الصنف نفسه في الوجبة نفسها يُجمَّع لا يُكرَّر', () async {
      final repo = MealPlanRepo(db);
      final id = await plan();
      await addLunch(id, '2026-03-01');
      await addLunch(id, '2026-03-01');
      final full = await repo.byId(id);
      expect(full!.entries, hasLength(1));
      expect(full.entries.single.qtyPerPerson, 0.5);
    });

    test('تضييق المدى يحذف المدخلات التي خرجت منه', () async {
      final repo = MealPlanRepo(db);
      final id = await plan();
      await addLunch(id, '2026-03-06');
      expect((await repo.byId(id))!.entries, hasLength(1));

      await repo.savePlan(
        id: id,
        name: 'خطة الأسبوع',
        planType: MealPlanType.custom,
        span: const DateSpan('2026-03-01', '2026-03-03'),
      );
      expect((await repo.byId(id))!.entries, isEmpty,
          reason: 'بقي مدخل في يوم لا تعرضه الشاشة');
    });

    test('الاستنساخ يزيح التواريخ ويبقي الترتيب', () async {
      final repo = MealPlanRepo(db);
      final id = await plan();
      await addLunch(id, '2026-03-01');
      await addLunch(id, '2026-03-03');

      final copy = await repo.duplicate(
        sourceId: id,
        newName: 'نسخة',
        newStart: '2026-03-08',
      );
      expect(copy.ok, isTrue, reason: copy.error);
      final full = await repo.byId(copy.planId);
      expect(full!.plan.startDate, '2026-03-08');
      expect(full.entries.map((e) => e.entryDate), containsAll(['2026-03-08', '2026-03-10']));
    });

    test('لا تُحذف خطة نشطة', () async {
      final repo = MealPlanRepo(db);
      final id = await plan();
      await addLunch(id, '2026-03-01');
      await repo.activate(id);
      expect((await repo.delete(id)).ok, isFalse);
      await repo.archive(id);
      expect((await repo.delete(id)).ok, isTrue);
    });
  });

  group('القوة اليومية من التفريدة', () {
    test('سطور المعسكر لا تُجمع مع تفصيل وحداته', () async {
      // لو جُمع الاثنان لتضاعف العدد ولتضاعف الاحتياج معه.
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 's1',
            unitId: 'u1',
            strengthDate: '2026-03-01',
            total: const Value(60),
            mode: const Value('detail'),
          ));
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 's2',
            unitId: 'u2',
            strengthDate: '2026-03-01',
            total: const Value(40),
            mode: const Value('detail'),
          ));
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 's3',
            unitId: 'camp',
            strengthDate: '2026-03-01',
            total: const Value(100),
            mode: const Value('camp'),
          ));

      final persons = await MealPlanRepo(db)
          .personsByDay(const DateSpan('2026-03-01', '2026-03-01'));
      expect(persons['2026-03-01'], 100, reason: 'جُمع المعسكر مع تفصيله');
    });

    test('تفريدة بوضع المعسكر وحدها تُقرأ ولا تُهمَل', () async {
      await db.into(db.strengths).insert(StrengthsCompanion.insert(
            id: 's1',
            unitId: 'camp',
            strengthDate: '2026-03-01',
            total: const Value(80),
            mode: const Value('camp'),
          ));
      final persons = await MealPlanRepo(db)
          .personsByDay(const DateSpan('2026-03-01', '2026-03-01'));
      expect(persons['2026-03-01'], 80);
    });
  });

  group('المزامنة', () {
    test('جدولا الخطة مسجّلان', () {
      expect(SyncMarks.entities.containsKey('meal_plans'), isTrue);
      expect(SyncMarks.entities.containsKey('meal_plan_entries'), isTrue);
    });
  });
}
