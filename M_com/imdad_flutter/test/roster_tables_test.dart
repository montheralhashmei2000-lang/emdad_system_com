import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/document_pdf.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/features/linkages/roster_tables.dart';

/// طباعة كشف القوة البشرية بجداول يختارها المستخدم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<LinkPerson> persons;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LinkageRepo(db);
    Future<void> add(String id, String name, String status, String camp) => repo.insertPerson(LinkPersonsCompanion(
          id: Value(id),
          fullName: Value(name),
          status: Value(status),
          camp: Value(camp),
        ));
    await add('p1', 'أحمد', LinkStatus.present, 'أ');
    await add('p2', 'سالم', LinkStatus.present, 'أ');
    await add('p3', 'علي', LinkStatus.leave, '');
    persons = await repo.persons();
  });
  tearDown(() => db.close());

  test('الخيارات: الكشف + جدول لكل حالة موجودة + الملخصات', () {
    final keys = [for (final o in rosterOptions(persons)) o.key];
    expect(keys.first, rosterFullKey);
    expect(keys, containsAll(['status:present', 'status:leave', 'sum:status', 'sum:camp']));
    expect(keys, isNot(contains('status:mission')), reason: 'حالة بلا أفراد');
  });

  test('الأقسام تُبنى للمختار فقط وبترتيب ثابت', () {
    final secs = buildRosterSections(persons, {'sum:camp', 'status:leave'});
    expect(secs.map((s) => s.title), ['${LinkStatus.label('leave')} (١)', 'ملخص حسب المعسكر']);
    expect(secs.first.rows.single[1], 'علي');
    expect(buildRosterSections(persons, {rosterFullKey}).single.rows, hasLength(3));
    expect(buildRosterSections(persons, {}), isEmpty);
  });

  test('الملخص: أعداد ونسب وإجمالي، والفارغ «غير محدد»', () {
    final s = buildRosterSections(persons, {'sum:camp'}).single;
    expect(s.rows.map((r) => r[1]), ['أ', 'غير محدد']);
    expect(s.rows.first[2], '٢');
    expect(s.totalRow?[1], 'الإجمالي');
    expect(s.totalRow?[3], '100%');
  });

  test('الطباعة تُنتج PDF بالأقسام المختارة', () async {
    final bytes = await DocumentPdf.build(
      doc: PrintDoc(
        title: 'كشف',
        landscape: true,
        sections: buildRosterSections(persons, {rosterFullKey, 'sum:status'}),
      ),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
