import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/reports_repo.dart';

/// النافذة الزمنية لـ[ReportsRepo.load] — تُطبَّق في SQLite لا في الذاكرة.
///
/// الغرض من هذه الاختبارات أن تبقى النافذة **صحيحة** لا سريعة فحسب: أسرعُ
/// تحميلٍ لا ينفع إن أسقط سندًا كان يجب أن يظهر.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> issueOn(String date) => db.into(db.issues).insert(
        IssuesCompanion.insert(
          id: Ids.next('is'),
          refNo: Value('ص-$date'),
          date: Value(date),
          warehouse: const Value('الرئيسي'),
          itemId: const Value('it1'),
          itemName: const Value('رز'),
          qty: const Value(5),
          baseQty: const Value(5),
        ),
      );

  test('بلا نافذة تُقرأ الحركات كلها', () async {
    await issueOn('2025-01-01');
    await issueOn('2026-06-15');
    final d = await ReportsRepo(db).load();
    expect(d.moves.length, 2);
    expect(d.from, isEmpty);
    expect(d.to, isEmpty);
  });

  test('النافذة تُسقط ما خارجها وتُبقي ما داخلها', () async {
    await issueOn('2026-05-31');
    await issueOn('2026-06-01');
    await issueOn('2026-06-30');
    await issueOn('2026-07-01');

    final d = await ReportsRepo(db).load(from: '2026-06-01', to: '2026-06-30');
    expect(d.moves.map((m) => m.date).toSet(), {'2026-06-01', '2026-06-30'});
  });

  test('سطرُ اليوم الأخير لا يسقط وإن حمل وقتًا بعد تاريخه', () async {
    // الحدّ الأعلى حصريّ (< اليوم التالي) لا شاملًا (<= اليوم الأخير)، وإلا
    // سقط كل سند خُتم بوقت في آخر يوم من المدى.
    await issueOn('2026-06-30T08:30:00');
    final d = await ReportsRepo(db).load(from: '2026-06-01', to: '2026-06-30');
    expect(d.moves, hasLength(1),
        reason: 'سند آخرِ يومٍ بوقتٍ يجب أن يبقى داخل المدى');
    expect(d.moves.single.date, '2026-06-30');
  });

  test('الحركات بلا تاريخ تخرج من أي نافذة وتبقى بلا نافذة', () async {
    await issueOn('');
    expect((await ReportsRepo(db).load()).moves, hasLength(1));
    final windowed =
        await ReportsRepo(db).load(from: '2026-06-01', to: '2026-06-30');
    expect(windowed.moves, isEmpty);
  });

  test('النافذة تشمل كل جداول الحركة لا الصرف وحده', () async {
    await db.into(db.receipts).insert(ReceiptsCompanion.insert(
        id: Ids.next('rc'), date: const Value('2026-01-05'), baseQty: const Value(1)));
    await db.into(db.transfers).insert(TransfersCompanion.insert(
        id: Ids.next('tr'), date: const Value('2026-01-05'), baseQty: const Value(1)));
    await db.into(db.returns).insert(ReturnsCompanion.insert(
        id: Ids.next('rt'), date: const Value('2026-01-05'), baseQty: const Value(1)));
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
        id: Ids.next('ob'), itemId: 'it1', date: const Value('2026-01-05')));
    await issueOn('2026-01-05');

    expect((await ReportsRepo(db).load()).moves, hasLength(5));
    final out =
        await ReportsRepo(db).load(from: '2026-02-01', to: '2026-02-28');
    expect(out.moves, isEmpty, reason: 'النافذة تُطبَّق على الجداول الخمسة');
  });

  group('covers — هل تكفي البيانات المحمَّلة المدى المطلوب؟', () {
    test('تحميلٌ كامل يكفي كل مدى', () async {
      final d = await ReportsRepo(db).load();
      expect(d.covers('2026-06-01', '2026-06-30'), isTrue);
      expect(d.covers('', ''), isTrue);
    });

    test('نافذةٌ لا تكفي مدى أوسع منها', () async {
      final d = await ReportsRepo(db).load(from: '2026-06-01', to: '2026-06-30');
      expect(d.covers('2026-05-01', '2026-06-30'), isFalse);
      expect(d.covers('', ''), isFalse,
          reason: 'المدى المفتوح يعني كل التاريخ، ولا تكفيه نافذة');
    });

    test('نافذةٌ تكفي ما بداخلها', () async {
      final d = await ReportsRepo(db).load(from: '2026-06-01', to: '2026-06-30');
      expect(d.covers('2026-06-10', '2026-06-20'), isTrue);
      expect(d.covers('2026-06-01', '2026-06-30'), isTrue);
    });
  });
}
