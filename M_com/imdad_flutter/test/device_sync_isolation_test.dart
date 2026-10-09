import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
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

  group('مفتاح التوقيع الإلكتروني الخاص', () {
    test('مفتاح الإعدادات معلَنٌ محليًّا (يربط ESign بالقائمة)', () {
      expect(SettingsRepo.localOnlyKeys, contains(ESign.settingsKey),
          reason: 'المفتاح مكتوبٌ حرفًا في localOnlyKeys لتفادي حلقة استيراد — هذا ما يربطهما');
    });

    test('لا يخرج في التصدير ولا في النسخة الاحتياطية', () async {
      final esign = ESign(master);
      await esign.ensureKey();
      final priv = '${((await SettingsRepo(master).read(ESign.settingsKey))['commander'] as Map)['priv']}';
      expect(priv, hasLength(64), reason: 'المفتاح الحقيقي لم يُهيَّأ — الاختبار لا يختبر شيئًا');

      for (final includeUsers in [false, true]) {
        final out = await DataExporter(master).toMap(includeUsers: includeUsers);
        final keys = [for (final s in out['settings'] as List) (s as Map)['key']];
        expect(keys, isNot(contains(ESign.settingsKey)));
        expect(jsonEncode(out), isNot(contains(priv)), reason: 'المفتاح الخاص للقائد غادر الجهاز');
      }
    });

    test('حمولةٌ قديمة تحمل esign لا تكتب فوق المفتاح المحلي', () async {
      await ESign(branch).ensureKey();
      final before = await SettingsRepo(branch).read(ESign.settingsKey);

      await LegacyImporter(branch).importJson({
        'settings': {
          ESign.settingsKey: {
            'commander': {'priv': 'ab' * 32, 'pub': 'غريب', 'kid': 'XXXX'},
          },
        },
        // ختمٌ بعيد في المستقبل: لولاه لرفض «الأحدث يفوز» الصفَّ قبل حارس المحلي.
        'syncMarks': [
          {'entity': 'app_settings', 'rowId': ESign.settingsKey, 'updatedAt': 4000000000000},
        ],
      });

      expect(await SettingsRepo(branch).read(ESign.settingsKey), before);
    });
  });

  test('إلغاء جهاز يصل بالمزامنة ويُمحى برفعه', () async {
    // مفتاحٌ حقيقي ومُستورَد: القرار لا ينتشر إلا موقَّعًا من المالك
    // (`device_revocation_guard_test`)، وكان الاختبار يمرّر مفتاحًا صوريًّا.
    final pair = ESign.generateKeyPair();
    final adminAct = DeviceActivation(master, ownerPublicKey: pair.publicB64);
    final branchAct = DeviceActivation(branch, ownerPublicKey: pair.publicB64);
    expect(await adminAct.importPrivateKey(pair.privateHex), isTrue);

    // المستورد يتحقق من توقيع الإلغاء بمفتاحه هو، فيُحقَن مفتاح الاختبار.
    final importer = LegacyImporter(branch, ownerPublicKey: pair.publicB64);

    await adminAct.setRevoked('ABCD2345', true);
    await importer.importJson(await DataExporter(master).toMap());
    expect(await branchAct.isRevoked('ABCD2345'), isTrue);

    await adminAct.setRevoked('ABCD2345', false);
    await importer.importJson(await DataExporter(master).toMap());
    expect(await branchAct.isRevoked('ABCD2345'), isFalse);
  });
}
