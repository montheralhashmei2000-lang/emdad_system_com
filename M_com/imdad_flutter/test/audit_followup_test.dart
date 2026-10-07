import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/password_hash.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// انحدارات مراجعة 2026-10-07: سقف الدورات، والنوافذ المحدودة للوحات الرقابة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verify يرفض عدد دورات يفوق المعيار الحالي (منع تجميد الدخول)', () async {
    final ok = await PasswordHash.verify('x', 'aa', 'bb', Pbkdf2.iterations + 1);
    expect(ok, isFalse);
  });

  test('الاستيراد يحصر iterations القادمة من نظير بين القديم والحالي', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    Map<String, dynamic> user(String id, int it) => {
          'id': id,
          'username': id,
          'role': 'user',
          'saltHex': 'aabbcc',
          'hashHex': 'ddeeff',
          'iterations': it,
          'active': true,
          'approved': true,
        };
    await LegacyImporter(db).importJson({
      'users': [user('weak', 1), user('huge', 2000000000), user('ok', Pbkdf2.iterations)],
    });
    final rows = {for (final u in await db.select(db.users).get()) u.id: u.iterations};
    expect(rows['weak'], Pbkdf2.legacyIterations);
    expect(rows['huge'], Pbkdf2.iterations);
    expect(rows['ok'], Pbkdf2.iterations);
  });

  group('نوافذ المخزون', () {
    late AppDatabase db;
    late MovementsRepo mv;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      mv = MovementsRepo(db);
    });
    tearDown(() => db.close());

    test('المسودة القديمة تُقرأ، والمعتمد القديم لا', () async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          id: 'a', refNo: const Value('R-1'), status: const Value('DRAFT'), date: const Value('2020-01-01')));
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          id: 'b', refNo: const Value('R-2'), status: const Value('APPROVED'), date: const Value('2020-01-01')));
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          id: 'c', refNo: const Value('R-3'), status: const Value('APPROVED'), date: const Value('2999-01-01')));
      final rows = await mv.receiptsPendingOrSince('2026-01-01');
      expect(rows.map((r) => r.id).toSet(), {'a', 'c'});
    });

    test('usageOf يعدّ ويقصّ المفتاح ويهمل الفارغ ويأخذ آخر تاريخ', () async {
      Future<void> r(String id, String sup, String date) => db.into(db.receipts).insert(
          ReceiptsCompanion.insert(id: id, supplier: Value(sup), date: Value(date)));
      await r('1', ' مورد أ ', '2026-01-01');
      await r('2', 'مورد أ', '2026-03-01');
      await r('3', '', '2026-05-01');
      final u = await mv.usageOf('receipts', 'supplier');
      expect(u.keys, ['مورد أ']);
      expect(u['مورد أ']!.count, 2);
      expect(u['مورد أ']!.lastDate, '2026-03-01');
    });

    test('usageOf للتحويل يقرأ عمود الوجهة بلا خطأ SQL', () async {
      expect(await mv.usageOf('transfers', 'dest_warehouse'), isEmpty);
      expect(await mv.usageOf('returns', 'party', where: "type = 'TO_SUPPLIER'"), isEmpty);
    });
  });
}
