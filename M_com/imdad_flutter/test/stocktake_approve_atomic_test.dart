import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/repos/stocktake_repo.dart';

/// البند M-3 في تدقيق 2026-10-10: اعتماد الجرد كان يكتب كل تسويةٍ وحدها ثم
/// يُغلق الأمر. انقطاعٌ في المنتصف يترك تسوياتٍ جزئية والمستودع مجمَّدًا، وإعادة
/// الاعتماد تفشل لأن معرّف التسوية حتميٌّ والإدراج عادي — فيعلق المستودع.
void main() {
  late AppDatabase db;
  late StocktakeRepo repo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = StocktakeRepo(db);
    final catalog = CatalogRepo(db);
    for (final c in ['A', 'B']) {
      await catalog.saveItem(
        code: c,
        name: 'صنف $c',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
    }
    sessionId = await repo.createOrder(warehouse: 'الرئيسي', date: '2026-10-01');
    for (final l in await repo.lines(sessionId)) {
      await repo.saveCount(lineId: l.id, countsByUnit: const {'كجم': 7}, factors: const {'كجم': 1});
    }
  });

  tearDown(() => db.close());

  Future<int> adjustments() async => (await db.select(db.adjustments).get()).length;

  test('انقطاعٌ في منتصف الاعتماد لا يترك تسويةً جزئية ولا أمرًا معلّقًا، والإعادة تنجح', () async {
    final lines = await repo.lines(sessionId);
    // يُفشل كتابة التسوية الثانية كما يفشلها انقطاعٌ أو قيدٌ غير متوقَّع.
    await db.customStatement('''
      CREATE TEMP TRIGGER tg_fail_second BEFORE INSERT ON adjustments
      WHEN NEW.id = 'adj-${lines.last.id}'
      BEGIN SELECT RAISE(ABORT, 'انقطاع'); END
    ''');
    await expectLater(repo.approve(sessionId: sessionId), throwsA(anything));
    expect(await adjustments(), 0, reason: 'بقيت تسويةٌ جزئية');
    expect((await repo.sessionById(sessionId))!.status, isNot(StocktakeRepo.closed));

    await db.customStatement('DROP TRIGGER tg_fail_second');
    expect(await repo.approve(sessionId: sessionId), 2);
    expect(await adjustments(), 2);
    final s = (await repo.sessionById(sessionId))!;
    expect((s.status, s.freeze), (StocktakeRepo.closed, false));
    final bal = await MovementsRepo(db).balances(warehouse: 'الرئيسي');
    expect(bal.values, everyElement(7));
  });

  test('الأمر المغلق لا يُعتمد ثانيةً ولا تتكرر تسوياته', () async {
    expect(await repo.approve(sessionId: sessionId), 2);
    expect(await repo.approve(sessionId: sessionId), 0);
    expect(await adjustments(), 2);
  });
}
