import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';
import 'package:imdad/data/sync/sync_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هوية الجهاز في `POST /trust`.
///
/// المعرّف كان يُقرأ من **جسم الطلب وحده**، والمفتاح الممنوح يُشتق منه
/// (`trustKeyFor(peerId)`) ويُحفظ تحته. فمن يملك رمز الاقتران يضع فيه معرّف
/// جهاز الإدارة، فيُكتب فوق سطر ثقته مفتاحٌ يعرفه — فينتحله، ويفقد جهاز
/// الإدارة الحقيقي مفتاحه فتتوقف مزامنته بصمت لأن توقيعه لم يعد يُقبل.
const int _port = 8831;
const int _discoveryPort = 8832;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase master;
  late AppDatabase branch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    master = AppDatabase.forTesting(NativeDatabase.memory());
    branch = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await master.close();
    await branch.close();
  });

  /// جلسةُ اقترانٍ صحيحة بين الفرع (عميل) والإدارة (مستقبِل).
  Future<({LanSync server, LanSync client, SyncPeer peer})> paired() async {
    final server = LanSync(master, port: _port, discoveryPort: _discoveryPort);
    await server.startReceiving();
    addTearDown(server.stopReceiving);
    final client = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
    final pairing = await client.pair('127.0.0.1', server.session!.code, port: _port);
    expect(pairing.ok, isTrue, reason: pairing.message);
    return (server: server, client: client, peer: pairing.peer!);
  }

  /// طلب ثقةٍ مصنوعٌ باليد: المعرّف في الترويسة والجسم يُحدَّدان على حدة.
  Future<int> postTrust(SyncSession session, {required String headerId, required String bodyId}) async {
    final body = session.sealJson({'device': bodyId, 'name': 'منتحل'});
    final http = HttpClient();
    try {
      final req = await http.openUrl('POST', Uri.parse('http://127.0.0.1:$_port/trust'));
      session.signHeaders('POST', '/trust', body).forEach(req.headers.set);
      req.headers.set(SyncSession.headerDevice, headerId);
      req.headers.set(SyncSession.headerPairKey, session.pairingEpk!);
      req.headers.contentType = ContentType.binary;
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      http.close();
    }
  }

  test('المعرّف في الجسم يخالف الترويسة ⇒ يُرفض ولا تُمنح ثقة', () async {
    final p = await paired();
    final status = await postTrust(p.peer.session, headerId: await p.client.deviceId(), bodyId: 'HQ000001');
    expect(status, HttpStatus.unauthorized);
    expect(await SyncTrust(master).accepted(), isEmpty);
    expect(await SyncTrust(master).peers(), isEmpty);
  });

  test('المعرّفان متفقان ⇒ تُمنح الثقة كما كان (لا كسر للمسار السليم)', () async {
    final p = await paired();
    final id = await p.client.deviceId();
    expect(await postTrust(p.peer.session, headerId: id, bodyId: id), HttpStatus.ok);
    expect((await SyncTrust(master).accepted()).keys, [id]);
  });

  group('لا يُكتب فوق مفتاح قرينٍ قائم', () {
    test('انتحال معرّفٍ موثوقٍ سلفًا ⇒ 409 والمفتاح الأصلي سليم', () async {
      // الإدارة تثق بجهازٍ ثالث (معرّفه معلوم للمهاجم: يسافر صريحًا في الترويسة).
      const victim = 'HQ000001';
      final original = _fakeKey(9);
      await SyncTrust(master).accept(TrustedPeer(deviceId: victim, key: original));

      final p = await paired();
      final status = await postTrust(p.peer.session, headerId: victim, bodyId: victim);

      expect(status, HttpStatus.conflict);
      final after = (await SyncTrust(master).accepted())[victim];
      expect(after, isNotNull, reason: 'سطر الضحية حُذف');
      expect(after!.key, original, reason: 'مفتاح الضحية استُبدل بمفتاحٍ يعرفه المهاجم');
      final audits = await (master.select(master.auditLogs)
            ..where((t) => t.action.equals('sync.trust_rejected')))
          .get();
      expect(audits, hasLength(1));
    });

    test('إعادة اقتران الجهاز نفسه بمفتاحٍ جديد ⇒ تُرفض حتى يُنسى أولًا', () async {
      final first = await paired();
      expect(await first.client.trust(first.peer), isNotNull);
      final granted = (await SyncTrust(master).accepted()).values.single.key;

      // جلسةٌ جديدة ⇒ مفتاحُ ثقةٍ جديد على المعرّف نفسه.
      await first.server.stopReceiving();
      final again = await paired();
      expect(await again.client.trust(again.peer), isNull, reason: 'استُبدل المفتاح بطلبٍ من الشبكة');
      expect((await SyncTrust(master).accepted()).values.single.key, granted);

      // وبعد النسيان يُقترن من جديد.
      await again.server.stopReceiving();
      await SyncTrust(master).forget(await again.client.deviceId());
      final third = await paired();
      expect(await third.client.trust(third.peer), isNotNull);
      expect((await SyncTrust(master).accepted()).values.single.key, isNot(granted));
    });

    test('المفتاح نفسه يُمنح مرتين بلا رفض (إعادة إرسالٍ لا تعثّر)', () async {
      final p = await paired();
      final id = await p.client.deviceId();
      expect(await postTrust(p.peer.session, headerId: id, bodyId: id), HttpStatus.ok);
      expect(await postTrust(p.peer.session, headerId: id, bodyId: id), HttpStatus.ok);
      expect((await SyncTrust(master).accepted()).keys, [id]);
    });
  });
}

/// مفتاحٌ وهميٌّ من بايتٍ مكرَّر.
Uint8List _fakeKey(int b) => Uint8List.fromList(List.filled(32, b));
