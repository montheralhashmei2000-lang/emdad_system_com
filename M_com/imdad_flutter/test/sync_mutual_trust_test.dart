import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الثقة في الاتجاهين، وتنحّي المنفذ.
///
/// السؤال الذي تجيب عنه: جهازان اقترنا مرة — أيستطيع **كلٌّ منهما** أن يبدأ
/// دورةً، وهل يبقى الجهاز مسموعًا وشاشةُ المزامنة مفتوحة عليه؟
///
/// الحالة التي كسرت هذا: `POST /trust` كان يكتب `accepted` وحدها، فجهاز
/// الإدارة لا يملك قرينًا يطرق بابه وزرُّ «زامن الآن» عنده مُعطَّل؛ و`pause()`
/// كانت تُغلق منفذ الاستقبال، فمشغّلٌ يفتح الشاشة على الجهازين ليضغط الزر
/// يُسكِت الجهازين معًا.
const int _port = 8821;
const int _discoveryPort = 8822;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase branch;
  late AppDatabase master;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    branch = AppDatabase.forTesting(NativeDatabase.memory());
    master = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await branch.close();
    await master.close();
  });

  Future<({LanSync client, LanSync server})> bond() async {
    final server = LanSync(master, port: _port, discoveryPort: _discoveryPort);
    await server.startReceiving();
    addTearDown(server.stopReceiving);
    final client = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
    final pairing = await client.pair('127.0.0.1', server.session!.code, port: _port);
    expect(pairing.ok, isTrue, reason: pairing.message);
    expect(await client.trust(pairing.peer!), isNotNull);
    return (client: client, server: server);
  }

  group('الثقة في الاتجاهين', () {
    test('الاقتران يكتب القرين في القائمتين على الجهازين', () async {
      final b = await bond();
      final clientId = await b.client.deviceId();
      final serverId = await b.server.deviceId();

      expect((await SyncTrust(branch).peers()).single.deviceId, serverId);
      expect((await SyncTrust(branch).accepted()).keys, contains(serverId));
      expect((await SyncTrust(master).accepted()).keys, contains(clientId));
      expect(
        (await SyncTrust(master).peers()).map((p) => p.deviceId),
        contains(clientId),
        reason: 'جهاز الإدارة بلا قرين: زرُّ «زامن الآن» عنده مُعطَّل',
      );
    });

    test('جهاز الإدارة يبدأ دورةً نحو الفرع فتصل بياناته', () async {
      final b = await bond();
      await CatalogRepo(branch).saveItem(
        code: 'B1',
        name: 'عدس',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      // الآن ينقلب الدور: الفرع يستقبل من الموثوقين، والإدارة تطرق بابه.
      await b.server.stopReceiving();
      final listener = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
      await listener.startReceiving(trustedOnly: true);
      addTearDown(listener.stopReceiving);

      final res = await b.server.autoSync();
      expect(res.ok, isTrue, reason: res.message);
      expect((await CatalogRepo(master).items()).map((i) => i.code), contains('B1'));
    });

    test('mirror يرمّم علاقةً قديمة من سطر واحد', () async {
      final store = SyncTrust(master);
      await store.accept(TrustedPeer(
        deviceId: 'AAAA1111',
        key: Uint8List.fromList(List<int>.filled(32, 7)),
        name: 'فرع',
        host: '192.168.1.9',
      ));
      expect(await store.peers(), isEmpty);

      expect(await store.mirror(), 1);
      final peer = (await store.peers()).single;
      expect(peer.deviceId, 'AAAA1111');
      expect(peer.host, '192.168.1.9');
      expect(peer.pulledUpTo, 0, reason: 'علامات الماء لا تُنقل بين الاتجاهين');
      // مرةً أخرى بلا أثر — الترميم يُنادى عند كل إقلاع.
      expect(await store.mirror(), 0);
    });

    test('الترميم لا يستدعي كتابةً حين تكون القائمتان متطابقتين', () async {
      final store = SyncTrust(master);
      expect(await store.mirror(), 0);
      expect(await SettingsRepo(master).read(SyncTrust.settingsKey), isEmpty);
    });
  });

  group('المنفذ وشاشة المزامنة', () {
    test('pause توقف الدورات ويبقى المنفذ مفتوحًا، وreleasePort تُغلقه', () async {
      final store = SyncTrust(master);
      await store.setAuto(true);
      await store.accept(TrustedPeer(
        deviceId: 'BBBB2222',
        key: Uint8List.fromList(List<int>.filled(32, 3)),
        name: 'فرع',
      ));
      final lan = LanSync(master, port: _port, discoveryPort: _discoveryPort);
      final service = AutoSyncService(master, sync: lan);
      addTearDown(service.shutdown);

      await service.refresh();
      expect(service.listening, isTrue, reason: 'المنفذ لم يُفتح لقرينٍ موثوق');

      await service.pause();
      expect(service.listening, isTrue, reason: 'شاشةُ المزامنة أسكتت الجهاز');

      await service.releasePort();
      expect(service.listening, isFalse, reason: 'الاقتران اليدوي يحتاج المنفذ');

      await service.reclaimPort();
      expect(service.listening, isTrue);
    });

    test('قرينٌ في peers وحدها يكفي لفتح المنفذ', () async {
      final store = SyncTrust(master);
      await store.setAuto(true);
      await store.remember(TrustedPeer(
        deviceId: 'CCCC3333',
        key: Uint8List.fromList(List<int>.filled(32, 5)),
      ));
      final service = AutoSyncService(
        master,
        sync: LanSync(master, port: _port, discoveryPort: _discoveryPort),
      );
      addTearDown(service.shutdown);
      await service.refresh();
      expect(service.listening, isTrue);
    });

    test('بلا جهاز موثوق لا يُفتح منفذ', () async {
      await SyncTrust(master).setAuto(true);
      final service = AutoSyncService(
        master,
        sync: LanSync(master, port: _port, discoveryPort: _discoveryPort),
      );
      addTearDown(service.shutdown);
      await service.refresh();
      expect(service.listening, isFalse);
    });
  });
}
