import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';

/// مسودة الصرف تُحفظ في القاعدة المشفّرة لكل مستخدم، ولا تغادر الجهاز بالمزامنة.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('كتابة وقراءة ومسح مسودة كل مستخدم على حدة', () async {
    final repo = SettingsRepo(db);
    expect(await repo.readIssueRecovery('u1'), isNull);

    await repo.writeIssueRecovery('u1', {'rows': [], 'notes': 'ا'});
    await repo.writeIssueRecovery('u2', {'notes': 'ب'});
    expect((await repo.readIssueRecovery('u1'))!['notes'], 'ا');
    expect((await repo.readIssueRecovery('u2'))!['notes'], 'ب');

    await repo.clearIssueRecovery('u1');
    expect(await repo.readIssueRecovery('u1'), isNull);
    expect(await repo.readIssueRecovery('u2'), isNotNull, reason: 'مسح مستخدمٍ لا يمسّ غيره');
  });

  test('المفتاح محلي للجهاز: لا يُصدَّر بالمزامنة', () {
    expect(SettingsRepo.localOnlyKeys, contains(SettingsRepo.issueRecoveryKey));
  });
}
