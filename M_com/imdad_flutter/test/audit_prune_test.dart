import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/audit_repo.dart';

/// تقليم سجل التدقيق.
///
/// الخط الفاصل: العادي يُقلَّم، وعاليُ الخطورة **لا يُمسّ مهما طال عمره** —
/// هو أثرُ المساءلة وسببُ وجود الجدول.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> entry(String risk, DateTime at) =>
      db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
            id: Ids.next('aud'),
            action: 'test',
            risk: Value(risk),
            createdAt: Value(at),
          ));

  final now = DateTime(2026, 9, 25);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  Future<int> count() async => (await db.select(db.auditLogs).get()).length;

  test('الحدث العادي القديم يُقلَّم', () async {
    await entry(AuditRepo.riskNormal, ago(800));
    expect(await AuditRepo(db).prune(now: now), 1);
    expect(await count(), 0);
  });

  test('الحدث العادي الحديث يبقى', () async {
    await entry(AuditRepo.riskNormal, ago(400));
    expect(await AuditRepo(db).prune(now: now), 0);
    expect(await count(), 1);
  });

  test('الحدث عالي الخطورة لا يُحذف مهما قدُم', () async {
    await entry(AuditRepo.riskHigh, ago(5000));
    expect(await AuditRepo(db).prune(now: now), 0,
        reason: 'تغيير الصلاحيات وإلغاء السندات أثرٌ دائم');
    expect(await count(), 1);
  });

  test('التقليم يقف عند حدّ الدفعة فيتوزّع على إقلاعات', () async {
    await db.batch((b) {
      for (var i = 0; i < AuditRepo.pruneBatch + 50; i++) {
        b.insert(
          db.auditLogs,
          AuditLogsCompanion.insert(
            id: Ids.next('aud'),
            action: 'test',
            createdAt: Value(ago(900 + i)),
          ),
        );
      }
    });
    expect(await AuditRepo(db).prune(now: now), AuditRepo.pruneBatch);
    expect(await count(), 50);
    expect(await AuditRepo(db).prune(now: now), 50);
    expect(await count(), 0);
  });

  test('الأقدم يُحذف أولًا', () async {
    await entry(AuditRepo.riskNormal, ago(2000));
    await entry(AuditRepo.riskNormal, ago(750));
    final repo = AuditRepo(db);
    // دفعةٌ بحجم واحد عبر تقليمين متتاليين: الأقدم يخرج في الأول.
    await repo.prune(now: now);
    expect(await count(), 0, reason: 'كلاهما تجاوز المدة');

    await entry(AuditRepo.riskNormal, ago(2000));
    await entry(AuditRepo.riskNormal, ago(100));
    await repo.prune(now: now);
    final left = await db.select(db.auditLogs).get();
    expect(left, hasLength(1));
    expect(left.single.createdAt.isAfter(ago(200)), isTrue,
        reason: 'الباقي هو الحديث');
  });

  test('الحذف يترك شاهدًا فينتقل إلى النظراء', () async {
    await entry(AuditRepo.riskNormal, ago(900));
    await AuditRepo(db).prune(now: now);
    final marks = await db.customSelect(
      "SELECT COUNT(*) c FROM sync_marks WHERE entity='audit_logs' AND deleted_at IS NOT NULL",
    ).getSingle();
    expect(marks.data['c'], 1,
        reason: 'بلا شاهدٍ يعود السطر المحذوف من أول مزامنة');
  });
}
