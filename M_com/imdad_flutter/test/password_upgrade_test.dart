import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/users_repo.dart';

/// ترقية بصمات كلمات المرور: الحسابات القديمة (45,000 دورة) تبقى تعمل، وتُعاد
/// تجزئتها بالعدد الحالي عند أول دخول ناجح، والحسابات الجديدة تُحفظ بعددها صراحة.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<User> row(String id) => (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();

  test('حساب قديم يدخل ثم تُرقّى بصمته ويبقى يدخل بعدها', () async {
    const salt = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    await db.into(db.users).insert(UsersCompanion.insert(
          id: 'web-1',
          username: 'keeper',
          saltHex: const Value(salt),
          hashHex: Value(Pbkdf2.deriveHex('Admin#12345', salt, iterations: Pbkdf2.legacyIterations)),
          iterations: const Value(Pbkdf2.legacyIterations),
        ));
    final auth = AuthService(db);

    final first = await auth.login('keeper', 'Admin#12345');
    expect(first.isOk, isTrue);
    final upgraded = await row('web-1');
    expect(upgraded.iterations, Pbkdf2.iterations);
    expect(upgraded.saltHex, isNot(salt), reason: 'ملح جديد مع البصمة الجديدة');
    expect(upgraded.updatedAt, isNotNull, reason: 'حتى تلتقطه المزامنة');

    await auth.logout();
    expect((await auth.login('keeper', 'Admin#12345')).isOk, isTrue);
    expect((await auth.login('keeper', 'wrong-pass')).isOk, isFalse);
  });

  test('الدخول الفاشل لا يغيّر البصمة', () async {
    const salt = '00112233445566778899aabbccddeeff';
    final hash = Pbkdf2.deriveHex('secret-1', salt, iterations: Pbkdf2.legacyIterations);
    await db.into(db.users).insert(UsersCompanion.insert(
          id: 'web-2',
          username: 'clerk',
          saltHex: const Value(salt),
          hashHex: Value(hash),
          iterations: const Value(Pbkdf2.legacyIterations),
        ));

    await AuthService(db).login('clerk', 'nope');

    final r = await row('web-2');
    expect(r.hashHex, hash);
    expect(r.iterations, Pbkdf2.legacyIterations);
  });

  test('المدير الأول والمستخدم الجديد يُحفظان بالعدد الحالي صراحة', () async {
    final admin = await AuthService(db).createAdmin(username: 'admin', password: 'correct-horse');
    expect(admin.iterations, Pbkdf2.iterations);

    final id = await UsersRepo(db).createUser(username: 'clerk', password: 'clerk-pass-1', name: 'كاتب');
    expect((await row(id)).iterations, Pbkdf2.iterations);
  });

  test('إعادة تعيين كلمة مرور حساب مُرحَّل بعدد مختلف تكتب العدد الجديد معها', () async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: 'web-3',
          username: 'storekeeper',
          saltHex: const Value('00112233445566778899aabbccddeeff'),
          hashHex: const Value('00'),
          iterations: const Value(100000),
        ));

    await UsersRepo(db).resetPassword(id: 'web-3', password: 'new-pass-123');

    expect((await row('web-3')).iterations, Pbkdf2.iterations);
    expect((await AuthService(db).login('storekeeper', 'new-pass-123')).isOk, isTrue);
  });
}
