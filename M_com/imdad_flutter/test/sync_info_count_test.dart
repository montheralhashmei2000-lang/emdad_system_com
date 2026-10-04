import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';

/// `GET /info` كان يصدّر القاعدة كلها (`toMap`) ليعدّ سجلاتها. صار `COUNT(*)`
/// لكل جدول: الرقم نفسه، بلا بناء الحمولة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> viaToMap() async {
    final map = await DataExporter(db).toMap();
    return map.entries.where((e) => e.value is List).fold<int>(0, (s, e) => s + (e.value as List).length);
  }

  test('قاعدة فارغة: العدّان متطابقان', () async {
    expect(await DataExporter(db).countRecords(), await viaToMap());
  });

  test('قاعدة ممتلئة: الرقم مطابق لعدّ toMap، والعدّ أسرع منه', () async {
    const n = 4000;
    await db.batch((b) {
      b.insertAll(db.categories, [
        for (var i = 0; i < 50; i++) CategoriesCompanion.insert(id: 'c$i', name: 'تصنيف $i'),
      ]);
      b.insertAll(db.items, [
        for (var i = 0; i < n; i++) ItemsCompanion.insert(id: 'i$i', code: Value('C$i'), name: 'صنف $i'),
      ]);
      b.insertAll(db.auditLogs, [
        for (var i = 0; i < n; i++) AuditLogsCompanion.insert(id: 'a$i', action: 'x', summary: Value('s$i')),
      ]);
    });
    // مفتاح محلي لا يُحسب في الحالتين.
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: 'device', value: const Value('{}')));
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: 'org', value: const Value('{}')));

    final swOld = Stopwatch()..start();
    final old = await viaToMap();
    swOld.stop();
    final swNew = Stopwatch()..start();
    final fresh = await DataExporter(db).countRecords();
    swNew.stop();

    // ignore: avoid_print
    print('بعدّ toMap: ${swOld.elapsedMilliseconds}ms ($old سجلًا) · COUNT(*): ${swNew.elapsedMilliseconds}ms ($fresh سجلًا)');
    expect(fresh, old);
    expect(fresh, greaterThan(2 * n));
    expect(swNew.elapsedMilliseconds, lessThan(swOld.elapsedMilliseconds));
  });
}
