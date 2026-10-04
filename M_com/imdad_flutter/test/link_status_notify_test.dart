import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/data/repos/notifications_repo.dart';
import 'package:imdad/domain/notification_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حالاتٌ مضافة من المستخدم، وتنبيهات الارتباطات في جرس التنبيهات.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('الحالة المضافة اسمها مفتاحها وهي ذات مدى', () {
    expect(LinkStatus.label('مريض مستشفى'), 'مريض مستشفى');
    expect(LinkStatus.isDated('مريض مستشفى'), isTrue);
    expect(LinkStatus.isDated(LinkStatus.present), isFalse);
    expect(LinkStatus.label(LinkStatus.mission), 'مهمة');
  });

  test('حالة جديدة تُحفظ في الدليل مرةً واحدة', () async {
    final repo = LinkageRepo(db);
    await repo.addTermIfNew('status', 'مريض مستشفى');
    await repo.addTermIfNew('status', 'مريض مستشفى');
    expect((await repo.terms('status')).map((t) => t.name), ['مريض مستشفى']);
  });

  test('فرد فارّ وحالةٌ منتهية تظهران في جرس التنبيهات', () async {
    final repo = LinkageRepo(db);
    await repo.insertPerson(const LinkPersonsCompanion(
      id: Value('p1'),
      fullName: Value('أحمد'),
      status: Value(LinkStatus.deserter),
    ));
    await repo.insertPerson(LinkPersonsCompanion(
      id: const Value('p2'),
      fullName: const Value('خالد'),
      status: const Value('مريض مستشفى'),
      statusTo: Value(DateTime.now().subtract(const Duration(days: 3)).toIso8601String().substring(0, 10)),
    ));
    final items = await NotificationsRepo(db).scan();
    final link = items.where((n) => n.kind == NotifyKind.linkPerson).toList();
    expect(link.length, 2);
    expect(link.any((n) => n.severity == NotifySeverity.danger), isTrue);
    expect(NotifyKind.linkPerson.route, 'personnel');

    // من لا يملك صفحة القوة البشرية لا يُنبَّه بها.
    final blocked = await NotificationsRepo(db).scan(allowed: {'items'});
    expect(blocked.any((n) => n.kind == NotifyKind.linkPerson), isFalse);
  });
}
