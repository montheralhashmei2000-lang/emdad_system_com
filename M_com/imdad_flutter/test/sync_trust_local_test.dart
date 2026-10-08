import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/data/sync/sync_trust.dart';

/// مفاتيح الثقة الدائمة للمزامنة لا تغادر الجهاز، وإعداداتُها لا تُدهَس بوارد.
///
/// **لماذا هذا الاختبار مقلوبُ المنطق:** كان `device_sync_isolation_test` يدور
/// على `localOnlyKeys` ويتأكد أن كلَّ عضوٍ فيها لا يخرج — فلا يرى مفتاحًا
/// **نُسي إعلانه**. وهذا بالضبط ما وقع: صفُّ `sync` بمفاتيح كل الأجهزة كان
/// يُصدَّر منذ أول إصدار ولم يَفشل اختبارٌ واحد. فهنا لا نعدّ ما أعلنّاه، بل
/// نبحث في الحمولة عمّا يشبه **سرًّا** مهما كان مفتاحه.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// مفتاحٌ دائمٌ وهميّ مميَّزٌ يسهل تتبّعه في الحمولة.
  Uint8List keyOf(int seed) => Uint8List.fromList(List.generate(32, (i) => (seed * 31 + i) & 0xff));

  Future<void> seedTrust() async {
    final trust = SyncTrust(db);
    await trust.setAuto(true);
    await trust.accept(TrustedPeer(deviceId: 'BRANCH01', key: keyOf(1), name: 'فرع ١'));
    await trust.remember(TrustedPeer(
      deviceId: 'BRANCH02',
      key: keyOf(2),
      name: 'فرع ٢',
      pulledUpTo: 1700000000000,
      pushedUpTo: 1700000000001,
    ));
  }

  test('مفتاح إعدادات المزامنة معلَنٌ محليًّا (يربط SyncTrust بالقائمة)', () {
    expect(SettingsRepo.localOnlyKeys, contains(SyncTrust.settingsKey),
        reason: 'المفتاح مكتوبٌ حرفًا في localOnlyKeys لتفادي حلقة استيراد — هذا ما يربطهما');
  });

  test('التصدير لا يحمل أي مفتاح ثقة دائم', () async {
    await seedTrust();

    final out = await DataExporter(db).toMap();
    final text = jsonEncode(out);

    // الصفّ نفسه غائب…
    final keys = [for (final s in out['settings'] as List) (s as Map)['key']];
    expect(keys, isNot(contains(SyncTrust.settingsKey)));

    // …ولا أثر لأي مفتاحٍ بعينه، أيًّا كان المفتاح الذي حمله.
    for (final seed in [1, 2]) {
      expect(text, isNot(contains(_hex(keyOf(seed)))), reason: 'مفتاح الجهاز $seed غادر الجهاز');
    }
  });

  test('لا سرَّ بطول مفتاحٍ كامل في حمولة التصدير إطلاقًا', () async {
    await seedTrust();

    final text = jsonEncode(await DataExporter(db).toMap());
    // ٦٤ محرفًا hex متّصلة = مفتاح ٢٥٦ بت. لا شيء في حمولة المزامنة يحتاج ذلك:
    // البصمات والمعرّفات أقصر، والتوقيعات base64 لا hex. فأي مطابقة سرٌّ تسرّب.
    final secret = RegExp(r'[0-9a-f]{64}');
    final hit = secret.firstMatch(text);
    expect(hit, isNull, reason: 'سلسلةٌ بطول مفتاحٍ كامل في الحمولة: ${hit?.group(0)}');
  });

  test('النسخة الاحتياطية غير المشفّرة كذلك لا تحمل المفاتيح', () async {
    await seedTrust();
    // `writeToFile` بلا كلمة مرور يكتب JSON صريحًا؛ الحمولة هي هي.
    final text = jsonEncode(await DataExporter(db).toMap(includeUsers: true));
    expect(text, isNot(contains(_hex(keyOf(1)))));
  });

  test('الوارد لا يدهس إعدادات المزامنة ولا علامات الماء ولا قائمة الأقران', () async {
    await seedTrust();

    // حمولةٌ من قرينٍ تحمل صفَّ `sync` خاصَّته: أقرانٌ آخرون وعلاماتٌ أخرى.
    //
    // ومعها علامةُ تغييرٍ بختمٍ بعيدٍ في المستقبل: بلا ذلك يرفض حارسُ «الأحدث
    // يفوز» (`_accept`) الصفَّ قبل أن يبلغ حارسَ المفاتيح المحلية، فيمرّ
    // الاختبار وإن كان العيب قائمًا. الختم يضمن أن الحمايةَ المُختبَرة هي
    // `localOnlyKeys` لا ترتيبُ الأختام.
    await LegacyImporter(db).importJson({
      'settings': {
        SyncTrust.settingsKey: {
          'auto': false,
          'intervalMinutes': 99,
          'accepted': {
            'INTRUDER': {'key': _hex(keyOf(9)), 'name': 'دخيل'},
          },
          'peers': {
            'BRANCH02': {'key': _hex(keyOf(2)), 'pulledUpTo': 9999999999999, 'pushedUpTo': 0},
          },
        },
      },
      'syncMarks': [
        {'entity': 'app_settings', 'rowId': SyncTrust.settingsKey, 'updatedAt': 4000000000000},
      ],
    });

    final trust = SyncTrust(db);

    // التفويض المحلي باقٍ.
    expect(await trust.isAuto(), isTrue, reason: 'الوارد عطّل المزامنة التلقائية محليًّا');
    expect((await trust.interval()).inMinutes, isNot(99));

    // لا ثقةٌ تُمنَح بالمزامنة: الثقة تُمنح باقترانٍ برمز لا بحمولة.
    expect((await trust.accepted()).keys, ['BRANCH01']);
    expect((await trust.accepted()).containsKey('INTRUDER'), isFalse,
        reason: 'حمولةٌ واردة منحت ثقةً لجهاز لم يقترن');

    // علامات الماء المحلية سليمة: لا تقفز للأمام (فتُسقط سجلات) ولا تُصفَّر.
    final peers = await trust.peers();
    expect(peers.single.deviceId, 'BRANCH02');
    expect(peers.single.pulledUpTo, 1700000000000, reason: 'علامة السحب دُهست بعلامة قرين');
    expect(peers.single.pushedUpTo, 1700000000001, reason: 'علامة الدفع دُهست بعلامة قرين');
  });

  test('بقية الإعدادات ما زالت تُزامَن (الحجب مقصورٌ على المحلي)', () async {
    await SettingsRepo(db).write('org', {'name': 'الوحدة'});
    await seedTrust();

    final out = await DataExporter(db).toMap();
    final keys = [for (final s in out['settings'] as List) (s as Map)['key']];
    expect(keys, contains('org'), reason: 'الحجب ابتلع إعدادًا يجب أن يسافر');
  });
}

String _hex(Uint8List b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
