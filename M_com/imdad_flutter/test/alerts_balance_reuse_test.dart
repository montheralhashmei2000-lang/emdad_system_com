import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/alerts_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// تقاسُم تجميع الأرصدة لا يغيّر النتيجة.
///
/// الفحوص الثلاثة في شاشة التنبيهات كانت تحسب الأرصدة كلٌّ لنفسه — ثلاث عمليات
/// `SUM/GROUP BY` على كل جداول الحركات لتحميلٍ واحد. وصارت تتقاسم تجميعًا
/// واحدًا، فهذا الاختبار يثبّت أن المختصَر يطابق الأصل حرفًا بحرف: تحسينُ أداءٍ
/// يغيّر رقمًا واحدًا في تنبيهٍ أسوأُ من بطءٍ معلوم.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());

    for (final (id, name, minQty) in [('i1', 'رز', 50.0), ('i2', 'سكر', 10.0), ('i3', 'شاي', 0.0)]) {
      await db.into(db.items).insert(ItemsCompanion.insert(
            id: id,
            code: Value(id.toUpperCase()),
            name: name,
            baseUnit: const Value('كجم'),
            minQty: Value(minQty),
          ));
    }

    var n = 0;
    Future<void> receipt(String wh, String item, double qty, {String expiry = ''}) async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r${n++}',
            refNo: Value('و-$n'),
            date: const Value('2026-09-01'),
            warehouse: Value(wh),
            itemId: Value(item),
            itemName: Value(item),
            qty: Value(qty),
            baseQty: Value(qty),
            factor: const Value(1),
            status: const Value('COMPLETED'),
            expiryDate: Value(expiry),
          ));
    }

    Future<void> issue(String wh, String item, double qty) async {
      await db.into(db.issues).insert(IssuesCompanion.insert(
            id: 's${n++}',
            refNo: Value('ص-$n'),
            date: const Value('2026-09-20'),
            warehouse: Value(wh),
            itemId: Value(item),
            itemName: Value(item),
            qty: Value(qty),
            baseQty: Value(qty),
            factor: const Value(1),
            status: const Value('COMPLETED'),
          ));
    }

    // مستودعان، صنفٌ تحت حدّه، ودفعةٌ مؤرَّخة، وصرفٌ يُغذّي التوقّع.
    await receipt('م1', 'i1', 100, expiry: '2026-10-20');
    await receipt('م1', 'i2', 5);
    await receipt('م2', 'i1', 30, expiry: '2026-12-31');
    await receipt('م2', 'i3', 7);
    await issue('م1', 'i1', 80);
    await issue('م2', 'i1', 4);
  });

  tearDown(() => db.close());

  test('balanceViews يطابق balances و balancesByWarehouse', () async {
    final moves = MovementsRepo(db);

    for (final scope in [null, ['م1'], ['م1', 'م2'], <String>[]]) {
      final views = await moves.balanceViews(scope: scope);
      expect(views.total, await moves.balances(scope: scope), reason: 'الإجمالي اختلف عند $scope');
      expect(views.byWarehouse, await moves.balancesByWarehouse(scope: scope),
          reason: 'المفصَّل اختلف عند $scope');
    }
  });

  test('all() يطابق النداءات الثلاثة المنفصلة', () async {
    final repo = AlertsRepo(db);
    final today = DateTime(2026, 10, 8);

    for (final scope in [null, ['م1']]) {
      final combined = await repo.all(scope: scope, withinDays: 30, today: today);
      final low = await repo.lowStock(scope: scope);
      final expiry = await repo.expiring(scope: scope, withinDays: 30, today: today);
      final forecast = await repo.forecast(scope: scope, today: today);

      expect(combined.low.map((e) => (e.itemId, e.balance)), low.map((e) => (e.itemId, e.balance)),
          reason: 'الحد الأدنى اختلف عند $scope');
      expect(combined.expiry.map((e) => (e.lot.itemId, e.lot.refNo, e.remainingQty, e.daysLeft)),
          expiry.map((e) => (e.lot.itemId, e.lot.refNo, e.remainingQty, e.daysLeft)),
          reason: 'انتهاء الصلاحية اختلف عند $scope');
      expect(combined.forecast.map((e) => (e.itemId, e.balance, e.daysLeft)),
          forecast.map((e) => (e.itemId, e.balance, e.daysLeft)),
          reason: 'التوقّع اختلف عند $scope');
    }
  });

  test('دفعُ التصفية إلى SQL يعطي ما تعطيه التصفية في Dart', () async {
    final moves = MovementsRepo(db);
    final all = await moves.balances();

    // صنفٌ واحد: `balanceOf` يجمع في القاعدة على ذلك الصنف وحده.
    for (final id in ['i1', 'i2', 'i3', 'لا-وجود-له']) {
      expect(await moves.balanceOf(id), all[id] ?? 0, reason: 'رصيد $id اختلف');
    }

    // ومع مستودع، ومع نطاق، وبنطاقٍ فارغ.
    for (final wh in ['م1', 'م2', 'مجهول']) {
      final scoped = await moves.balances(warehouse: wh);
      for (final id in ['i1', 'i2', 'i3']) {
        expect(await moves.balanceOf(id, warehouse: wh), scoped[id] ?? 0,
            reason: 'رصيد $id في $wh اختلف');
      }
    }
    expect(await moves.balances(scope: const []), isEmpty, reason: 'نطاقٌ فارغ يجب أن يُفرغ');
    expect(await moves.balances(scope: const ['م1', 'م2']), all,
        reason: 'نطاقٌ يضمّ كل المستودعات يجب أن يطابق الكل');

    // المستودع المحدَّد يُقدَّم على النطاق — كما كان قبل الدفع.
    expect(await moves.balances(warehouse: 'م1', scope: const ['م2']),
        await moves.balances(warehouse: 'م1'));
  });

  test('الأرصدة الممرَّرة هي المستعملة فعلًا (لا تُعاد الحسبة)', () async {
    // أرصدةٌ مُفتعلة لا تشبه القاعدة: لو تجاهلها الفحصُ وحسب لنفسه لظهر الفرق.
    final low = await AlertsRepo(db).lowStock(balances: {'i1': 0, 'i2': 999});
    final ids = low.map((e) => e.itemId).toList();
    expect(ids, contains('i1'), reason: 'الرصيد الممرَّر (صفر) لم يُستعمل');
    expect(ids, isNot(contains('i2')), reason: 'الرصيد الممرَّر (٩٩٩) لم يُستعمل');
  });
}
