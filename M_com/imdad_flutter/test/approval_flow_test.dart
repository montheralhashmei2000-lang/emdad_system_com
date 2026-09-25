import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// اعتماد أوامر الصرف ومسوداته ومسودات الوارد، وأثر الحفظ في سجل التدقيق.
///
/// كانت شاشتا «أوامر التوريد المعلقة» و«مسودات الصرف» تفحصان الرصيد الإجمالي
/// لكل المستودعات، فيُعتمد صرف من مستودع فارغ برصيد مستودع آخر فيصير رصيده
/// سالبًا، ولا تفحصان تجميد الجرد. وكانت كل شاشة حركة تكتب حدث الحفظ في سجل
/// التدقيق مرة ثانية بعد أن كتبه المستودع، فتتضاعف إحصاءات النشاط.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late String rice;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    final catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    await catalog.saveWarehouse(code: 'W2', name: 'الفرعي');
    rice = await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() => db.close());

  DocLineInput line(double qty) => DocLineInput(
        itemId: rice,
        itemCode: 'R1',
        itemName: 'أرز',
        unitName: 'كجم',
        factor: 1,
        qty: qty,
      );

  Future<void> receive(String wh, double qty) async {
    final r = await mv.saveReceipt(warehouse: wh, supplier: 'المورد', date: '2026-09-20', lines: [line(qty)]);
    expect(r.ok, isTrue, reason: r.error);
  }

  Future<List<Issue>> pendingIssue(String wh, double qty, {String status = 'ORDER'}) async {
    final r = await mv.saveIssue(
      warehouse: wh,
      recipientDisplay: 'سرية الإسناد',
      date: '2026-09-20',
      lines: [line(qty)],
      status: status,
    );
    expect(r.ok, isTrue, reason: r.error);
    return (db.select(db.issues)..where((t) => t.refNo.equals(r.refNo))).get();
  }

  Future<void> freeze(String wh) => db.into(db.stocktakes).insert(
        StocktakesCompanion.insert(id: 'st-1', orderNo: const Value('ج-000001'), warehouse: Value(wh)),
      );

  Future<int> auditCount(String action) async =>
      (await (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get()).length;

  group('اعتماد أوامر الصرف ومسوداته', () {
    test('رصيد مستودع آخر لا يغطي أمر صرف من مستودع فارغ', () async {
      await receive('الفرعي', 100);
      final order = await pendingIssue('الرئيسي', 10);

      final res = await mv.approveIssues(order);

      expect(res.ok, isFalse);
      expect(res.error, contains('الرئيسي'));
      final rows = await db.select(db.issues).get();
      expect(rows.single.status, 'ORDER', reason: 'لا يُخصم شيء عند الرفض');
      expect(await mv.balanceOf(rice, warehouse: 'الرئيسي'), 0);
    });

    test('يُعتمد الأمر من رصيد مستودعه ويُسجَّل المعتمِد', () async {
      await receive('الرئيسي', 30);
      final draft = await pendingIssue('الرئيسي', 12, status: 'DRAFT');

      final res = await mv.approveIssues(draft, approvedBy: 'keeper@imdad.local');

      expect(res.ok, isTrue, reason: res.error);
      final row = (await db.select(db.issues).get()).single;
      expect(row.status, 'COMPLETED');
      expect(row.approvedBy, 'keeper@imdad.local');
      expect(await mv.balanceOf(rice, warehouse: 'الرئيسي'), 18);
      expect(await auditCount('ISSUE_DRAFT_APPROVED'), 1);
    });

    test('المستودع المجمّد بأمر جرد يرفض الاعتماد', () async {
      await receive('الرئيسي', 30);
      final order = await pendingIssue('الرئيسي', 5);
      await freeze('الرئيسي');

      final res = await mv.approveIssues(order);

      expect(res.ok, isFalse);
      expect(res.error, contains('مجمّد'));
      expect((await db.select(db.issues).get()).single.status, 'ORDER');
    });

    test('أمر اعتُمد من قبل لا يُعتمد ثانية ولا يُخصم مرتين', () async {
      await receive('الرئيسي', 30);
      final order = await pendingIssue('الرئيسي', 10);
      expect((await mv.approveIssues(order)).ok, isTrue);

      // الشاشة ما زالت تعرض النسخة القديمة من الأمر.
      final again = await mv.approveIssues(order);

      expect(again.ok, isFalse);
      expect(await mv.balanceOf(rice, warehouse: 'الرئيسي'), 20);
      expect(await auditCount('ISSUE_DRAFT_APPROVED'), 1);
    });

    test('approveIssueOrder بالمرجع يمر بالقواعد نفسها', () async {
      await receive('الفرعي', 100);
      final order = await pendingIssue('الرئيسي', 10);

      expect((await mv.approveIssueOrder(order.first.refNo)).ok, isFalse);
    });
  });

  group('اعتماد مسودة الوارد', () {
    test('يضيف الرصيد، ويُرفض على مستودع مجمّد', () async {
      final r = await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'المورد', date: '2026-09-20', lines: [line(40)], draft: true);
      final draft = await (db.select(db.receipts)..where((t) => t.refNo.equals(r.refNo))).get();
      await freeze('الرئيسي');

      final blocked = await mv.approveReceiptDraft(draft);
      expect(blocked.ok, isFalse);
      expect(await mv.balanceOf(rice, warehouse: 'الرئيسي'), 0);

      await db.delete(db.stocktakes).go();
      expect((await mv.approveReceiptDraft(draft)).ok, isTrue);
      expect(await mv.balanceOf(rice, warehouse: 'الرئيسي'), 40);
    });
  });

  group('سجل التدقيق', () {
    test('كل حفظ يُكتب مرة واحدة باسم منفّذه', () async {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'u1',
            username: 'keeper',
            name: const Value('أمين المستودع'),
            email: const Value('keeper@imdad.local'),
          ));
      final actor = await (db.select(db.users)..where((t) => t.id.equals('u1'))).getSingle();
      await mv.saveReceipt(
          warehouse: 'الرئيسي', supplier: 'المورد', date: '2026-09-20', lines: [line(10)], actor: actor);

      final logs = await (db.select(db.auditLogs)..where((t) => t.action.equals('RECEIPT_COMPLETED'))).get();
      expect(logs, hasLength(1));
      expect(logs.single.actorName, 'أمين المستودع');
    });
  });

  group('قفل الدخول', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('تغيير حالة أحرف الاسم لا يمنح محاولات جديدة', () async {
      final auth = AuthService(db);
      await auth.createAdmin(username: 'admin', password: 'correct-horse');
      await auth.logout();

      for (final name in ['admin', 'Admin', 'ADMIN', 'aDmin', 'adMin']) {
        await auth.login(name, 'wrong');
      }
      final res = await auth.login('ADMIn', 'correct-horse');

      expect(res.status, AuthStatus.locked);
    });
  });
}
