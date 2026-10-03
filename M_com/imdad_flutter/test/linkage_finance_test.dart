import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';

/// مالية الإمداد: العهد والإخلاءات والعقود **بلا ارتباطٍ بالأفراد**.
void main() {
  late AppDatabase db;
  late LinkageRepo repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LinkageRepo(db);
  });
  tearDown(() => db.close());

  Future<void> custody(String id, {String due = '', String holder = 'المطبخ'}) => repo.insertCustody(
        LinkFinCustodiesCompanion(
          id: Value(id),
          title: Value('عهدة $id'),
          holder: Value(holder),
          valueAmount: const Value(500),
          dueDate: Value(due),
        ),
      );

  test('إخلاء عهدة يغلقها، وحذف الإخلاء يعيد فتحها', () async {
    await custody('c1');
    await repo.addClearance(
        kind: LinkClearanceKind.custody, refId: 'c1', clearanceNo: 'خ-1', clearanceDate: '2026-10-03', amount: 500);

    var c = (await repo.custodies()).single;
    expect(c.cleared, isTrue);
    expect(c.clearedDate, '2026-10-03');
    final cl = (await repo.clearances()).single;
    expect(cl.partyName, 'المطبخ', reason: 'الجهة تُؤخذ من العهدة إن لم تُكتب');
    expect(cl.refTitle, 'عهدة c1');

    await repo.deleteClearance(cl);
    c = (await repo.custodies()).single;
    expect(c.cleared, isFalse);
    expect(c.clearedDate, isEmpty);
    expect(await repo.clearances(), isEmpty);
  });

  test('إخلاء عقد ينفّذه، وحذفه يعيده قيد التنفيذ', () async {
    await repo.insertContract(LinkPurchaseContractsCompanion(
        id: const Value('k1'), title: const Value('توريد أرز'), supplier: const Value('مورد'), amount: const Value(9000)));
    await repo.addClearance(kind: LinkClearanceKind.contract, refId: 'k1', clearanceDate: '2026-10-03');
    expect((await repo.contracts()).single.status, LinkContractStatus.done);

    await repo.deleteClearance((await repo.clearances()).single);
    expect((await repo.contracts()).single.status, LinkContractStatus.open);
  });

  test('إخلاء حر بلا مرجع، وحذف العهدة يحذف إخلاءاتها', () async {
    await repo.addClearance(
        kind: LinkClearanceKind.other, clearanceDate: '2026-10-03', refTitle: 'تسوية متفرقة', partyName: 'جهة', amount: 10);
    expect((await repo.clearances(kind: LinkClearanceKind.other)), hasLength(1));

    await custody('c2');
    await repo.addClearance(kind: LinkClearanceKind.custody, refId: 'c2', clearanceDate: '2026-10-04');
    await repo.deleteCustody((await repo.custodies()).single);
    expect(await repo.custodies(), isEmpty);
    expect(await repo.clearances(kind: LinkClearanceKind.custody), isEmpty);
  });

  test('تنبيهات المالية تذكر الجهة لا الفرد، وتتوقف بالإخلاء', () async {
    await custody('c3', due: '2020-01-01', holder: 'الفرن');
    await repo.insertContract(const LinkPurchaseContractsCompanion(
        id: Value('k2'), title: Value('صيانة'), endDate: Value('2020-01-01')));

    var alerts = await repo.getAlerts();
    final overdue = alerts.firstWhere((a) => a.type == LinkAlertType.custodyOverdue);
    expect(overdue.body, contains('الفرن'));
    expect(overdue.personId, isEmpty, reason: 'لا ارتباط بالأفراد');
    expect(alerts.any((a) => a.type == LinkAlertType.contractExpired), isTrue);

    await repo.addClearance(kind: LinkClearanceKind.custody, refId: 'c3', clearanceDate: '2026-10-03');
    await repo.addClearance(kind: LinkClearanceKind.contract, refId: 'k2', clearanceDate: '2026-10-03');
    alerts = await repo.getAlerts();
    expect(alerts.where((a) => a.type == LinkAlertType.custodyOverdue || a.type == LinkAlertType.contractExpired), isEmpty);
  });

  test('جهات العهد تُحفظ في دليل المسميات للاقتراح', () async {
    await custody('c4', holder: 'الورشة الجديدة');
    expect((await repo.terms('holder')).map((t) => t.name), contains('الورشة الجديدة'));
  });

  test('ملف الفرد يعرض التسليح فقط', () async {
    final rec = await repo.linkedRecords('nobody');
    expect(rec.armaments, isEmpty);
  });
}
