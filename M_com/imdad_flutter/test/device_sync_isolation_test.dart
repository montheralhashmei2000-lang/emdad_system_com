import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/settings_repo.dart';

/// هوية الجهاز لا تسافر بالمزامنة، والإلغاء وحده يسافر.
///
/// التصدير كان يحمل كل مفاتيح الإعدادات ومنها `device` (رمز تفعيل هذا الجهاز
/// ومعرّفه، وعلى جهاز الإدارة مفتاح المالك الخاص) إلى أي جهازٍ مقترن.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase master;
  late AppDatabase branch;

  setUp(() {
    master = AppDatabase.forTesting(NativeDatabase.memory());
    branch = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await master.close();
    await branch.close();
  });

  test('التصدير لا يحمل مفاتيح الجهاز الخاصة، ويحمل غيرها', () async {
    final repo = SettingsRepo(master);
    await repo.write('device', {'id': 'ABCD2345', 'token': 'سرّي', 'owner': 'مفتاح-خاص'});
    await repo.write('devices', {'list': []});
    await repo.write('org', {'name': 'الوحدة'});

    final out = await DataExporter(master).toMap();
    final keys = [for (final s in out['settings'] as List) (s as Map)['key']];

    expect(keys, contains('org'));
    for (final k in SettingsRepo.localOnlyKeys) {
      expect(keys, isNot(contains(k)), reason: 'المفتاح $k يغادر الجهاز');
    }
    expect(out.toString(), isNot(contains('مفتاح-خاص')));
  });

  test('الدمج لا يكتب فوق هوية الجهاز المحلية', () async {
    await SettingsRepo(branch).write('device', {'id': 'LOCAL234'});

    await LegacyImporter(branch).importJson({
      'settings': {
        'device': {'id': 'OTHER567', 'token': 'غريب'},
      },
    });

    expect((await SettingsRepo(branch).read('device'))['id'], 'LOCAL234');
  });

  test('إلغاء جهاز يصل بالمزامنة ويُمحى برفعه', () async {
    final adminAct = DeviceActivation(master, ownerPublicKey: 'x');
    final branchAct = DeviceActivation(branch, ownerPublicKey: 'x');

    await adminAct.setRevoked('ABCD2345', true);
    await LegacyImporter(branch).importJson(await DataExporter(master).toMap());
    expect(await branchAct.isRevoked('ABCD2345'), isTrue);

    await adminAct.setRevoked('ABCD2345', false);
    await LegacyImporter(branch).importJson(await DataExporter(master).toMap());
    expect(await branchAct.isRevoked('ABCD2345'), isFalse);
  });
}
