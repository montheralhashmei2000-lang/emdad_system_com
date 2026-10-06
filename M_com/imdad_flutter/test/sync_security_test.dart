import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';

/// اختبارات أمن المزامنة: تثبت أن المنفذ المفتوح على الشبكة لا يسلّم بيانات
/// ولا يقبلها إلا من جهاز يحمل رمز الاقتران المعروض على شاشة المستقبِل.
/// ومعها اختبارات الاقتران v3: ECDH مؤقت + رمز من ٨ أحرف، وتدقيق كل محاولة.

/// منفذان خاصّان بهذا الملف (انظر التعليق في `sync_excel_test.dart`).
const int _port = 8793;
const int _discoveryPort = 8794;

/// منفذ خادم v2 وهمي (انظر اختبار الرفض).
const int _legacyPort = 8799;

/// جلسة بمفتاح معلوم — بديل ما كان `SyncSession.create()` للاختبارات التي لا تعنيها آلية الاقتران.
SyncSession _key([int seed = 1]) =>
    SyncSession.fromKey(Uint8List.fromList(List.generate(32, (i) => (seed * 31 + i) & 0xff)));

/// تفاصيل سجلات التدقيق من نوع [action] في [db].
Future<List<Map<String, dynamic>>> _audit(AppDatabase db, String action) async {
  final rows = await (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get();
  return [for (final r in rows) jsonDecode(r.details) as Map<String, dynamic>];
}

/// ينتظر تحقّق شرط غير متزامن بدل افتراض حدوثه فور عودة الطلب.
Future<void> _until(bool Function() condition, {Duration limit = const Duration(seconds: 3)}) async {
  final deadline = DateTime.now().add(limit);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase source;
  late AppDatabase target;

  setUp(() async {
    source = AppDatabase.forTesting(NativeDatabase.memory());
    target = AppDatabase.forTesting(NativeDatabase.memory());
    // بيانات حقيقية في الجهاز المستقبِل حتى يكون للتسريب معنى.
    await CatalogRepo(target).saveItem(
      code: 'X1',
      name: 'دقيق',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<LanSync> receiver({Duration ttl = SyncSession.defaultTtl}) async {
    final r = LanSync(target, port: _port, discoveryPort: _discoveryPort);
    await r.startReceiving(ttl: ttl);
    addTearDown(r.stopReceiving);
    return r;
  }

  /// طلب خام بلا أي توقيع، كما يفعل مهاجم على الشبكة نفسها.
  Future<HttpClientResponse> raw(String path, {Map<String, String> headers = const {}}) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$_port$path'));
    headers.forEach(req.headers.set);
    final res = await req.close();
    await res.drain<void>();
    client.close();
    return res;
  }

  group('صدّ الطلبات غير المصرّح بها', () {
    test('طلب تصدير بلا توقيع يُرفض ولا يسلّم بيانات', () async {
      await receiver();
      final res = await raw('/export?users=1');
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('الترحيب مفتوح لكنه لا يحمل أي بيانات — التعريف والملح فقط', () async {
      await receiver();
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$_port/hello'));
      final res = await req.close();
      final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
      client.close();

      expect(res.statusCode, HttpStatus.ok);
      // المعرّف ليس سرًّا — هو نفسه ما يُتلى هاتفيًا لإصدار رمز التفعيل. وجوده
      // هنا ليعرف الجهاز الطالب أنه بلغ الجهاز الذي يقصده قبل أن يوقّع.
      expect(body.keys.toSet(), {'app', 'v', 'device', 'id', 'salt', 'pub', 'needsCode', 'now'});
      expect(body['v'], 3);
      expect((body['salt'] as String).isNotEmpty, isTrue);
      expect((body['pub'] as String).isNotEmpty, isTrue);
      expect((body['id'] as String).length, 8);
    });

    test('رمز اقتران خاطئ لا يفتح جلسة', () async {
      final r = await receiver();
      final wrong = r.session!.code == 'AAAAAAAA' ? 'BBBBBBBB' : 'AAAAAAAA';
      final pairing = await LanSync(source).pair('127.0.0.1', wrong, port: _port);

      expect(pairing.ok, isFalse);
      expect(pairing.peer, isNull);
      expect(pairing.message, contains('غير صحيح'));
    });

    test('رمز بصيغة غير صالحة يُرفض قبل أي اتصال', () async {
      await receiver();
      for (final bad in ['12ab', '123456', 'AAAAAAAO', 'AAAA-AAA0', '']) {
        final pairing = await LanSync(source).pair('127.0.0.1', bad, port: _port);
        expect(pairing.ok, isFalse, reason: bad);
        expect(pairing.message, contains('٨ أحرف'), reason: bad);
      }
      // لم يصل أي طلب إلى المستقبِل: لا محاولة مسجَّلة عليه.
      expect(await _audit(target, 'sync.pair.failed'), isEmpty);
    });

    test('إعادة إرسال طلب موقَّع سليم لا تُقبل مرتين', () async {
      final r = await receiver();
      final pairing = await LanSync(source).pair('127.0.0.1', r.session!.code, port: _port);
      expect(pairing.ok, isTrue, reason: pairing.message);
      final session = pairing.peer!.session;
      final headers = {
        ...session.signHeaders('GET', '/info', const []),
        SyncSession.headerPairKey: session.pairingEpk!,
      };

      final first = await raw('/info', headers: headers);
      final second = await raw('/info', headers: headers);

      expect(first.statusCode, HttpStatus.ok);
      expect(second.statusCode, HttpStatus.unauthorized);
    });

    test('خمس محاولات فاشلة تُغلق الاستقبال', () async {
      final r = await receiver();
      for (var i = 0; i < LanSync.maxAuthFailures; i++) {
        await raw('/info');
      }
      // الإغلاق يقع بعد إرسال الرفض، فيُنتظر بدل التحقق الفوري.
      await _until(() => !r.isReceiving);
      expect(r.isReceiving, isFalse);
    });

    test('انتهاء مدة الجلسة يغلق المنفذ وحده', () async {
      final r = await receiver(ttl: const Duration(milliseconds: 300));
      expect(r.isReceiving, isTrue);
      await _until(() => !r.isReceiving);
      expect(r.isReceiving, isFalse);
      expect(r.session, isNull);
    });
  });

  group('تشفير الحمولة', () {
    test('ما يُشفَّر يُفكّ بالمفتاح نفسه فقط', () {
      final a = _key();
      final b = _key();
      final other = _key(2);

      final sealed = a.sealJson({'x': 'سرّ'});
      expect(b.openJson(sealed)['x'], 'سرّ');
      expect(() => other.openJson(sealed), throwsA(isA<SyncCryptoError>()));
    });

    test('العبث ببايت واحد يُكتشف ولا يُفكّ التشفير', () {
      final s = _key();
      final sealed = s.sealJson({'qty': 10});
      sealed[sealed.length - 1] ^= 0xFF;

      expect(() => s.openJson(sealed), throwsA(isA<SyncCryptoError>()));
    });

    test('التوقيع مرتبط بالمسار والفعل والجسم', () {
      final s = _key();
      final seen = <String>{};
      final headers = s.signHeaders('GET', '/export', const []);

      // المسار نفسه ⇒ يُقبل.
      expect(
        s.verify(
          method: 'GET',
          path: '/export',
          ts: headers[SyncSession.headerTs],
          nonce: headers[SyncSession.headerNonce],
          mac: headers[SyncSession.headerMac],
          body: const [],
          seenNonces: seen,
        ),
        isNull,
      );

      // مسار آخر بالتوقيع نفسه ⇒ يُرفض (مع nonce جديد حتى لا يكون الرفض للتكرار).
      final other = s.signHeaders('GET', '/export', const []);
      expect(
        s.verify(
          method: 'POST',
          path: '/import',
          ts: other[SyncSession.headerTs],
          nonce: other[SyncSession.headerNonce],
          mac: other[SyncSession.headerMac],
          body: const [],
          seenNonces: seen,
        ),
        'توقيع غير مطابق',
      );
    });

    test('ختم زمني قديم يُرفض', () {
      final s = _key();
      final stale = (DateTime.now().subtract(const Duration(hours: 1)))
          .millisecondsSinceEpoch
          .toString();

      expect(
        s.verify(
          method: 'GET',
          path: '/info',
          ts: stale,
          nonce: 'n1',
          mac: 'anything',
          body: const [],
          seenNonces: <String>{},
        ),
        contains('فارق التوقيت'),
      );
    });
  });

  group('رمز الاقتران', () {
    test('٨ أحرف من الأبجدية الواضحة وبلا تكرار ثابت', () {
      final codes = {for (var i = 0; i < 50; i++) PairingCode.generate()};
      expect(codes.length, greaterThan(45));
      for (final c in codes) {
        expect(c.length, 8);
        expect(c.split('').every(PairingCode.alphabet.contains), isTrue, reason: c);
      }
      expect(PairingCode.alphabet.length, 32);
      for (final ch in ['I', 'O', '0', '1']) {
        expect(PairingCode.alphabet.contains(ch), isFalse);
      }
    });

    test('يُوحَّد ما يكتبه المشغّل ويُعرض XXXX-XXXX', () {
      expect(PairingCode.normalize('abcd-2345'), 'ABCD2345');
      expect(PairingCode.normalize(' ABCD 2345 '), 'ABCD2345');
      expect(PairingCode.normalize('ABCD2345'), 'ABCD2345');
      expect(PairingCode.normalize('ABCD234'), isNull);
      expect(PairingCode.normalize('ABCD23456'), isNull);
      expect(PairingCode.normalize('ABCD234O'), isNull);
      expect(PairingCode.normalize('١٢٣٤٥٦٧٨'), isNull);
      expect(PairingCode.format('ABCD2345'), 'ABCD-2345');
    });
  });

  group('الاقتران v3: ECDH + الرمز', () {
    test('الطرفان يشتقان المفتاح نفسه، ولكل اقتران مفتاح مختلف', () async {
      final r = await receiver();
      final first = await LanSync(source).pair('127.0.0.1', r.session!.code, port: _port);
      final second = await LanSync(source).pair('127.0.0.1', r.session!.code, port: _port);
      expect(first.ok && second.ok, isTrue, reason: first.message + second.message);

      final mine = first.peer!.session;
      final theirs = r.session!.sessionFor(mine.pairingEpk!);
      expect(theirs, isNotNull);
      expect(theirs!.key, mine.key);
      expect(theirs.fingerprint, mine.fingerprint);

      // المفتاح المؤقت يتبدّل في كل اقتران، فيتبدّل مفتاح الجلسة بالرمز نفسه.
      expect(second.peer!.session.fingerprint, isNot(mine.fingerprint));
    });

    test('من يعرف الرمز والملح والمفتاحين العامين وحدها لا يشتق المفتاح', () async {
      final r = await receiver();
      final real = (await LanSync(source).pair('127.0.0.1', r.session!.code, port: _port)).peer!.session;

      // المتنصّت رأى كل ما عبر الشبكة، وتخمّن الرمز الصحيح، لكنه لا يملك أيًّا
      // من المفتاحين الخاصين المؤقتين.
      final offer = r.session!;
      final stolen = PairingKeys.sessionKey(
        codeKey: PairingKeys.codeKey(offer.code, offer.salt),
        privHex: PairingKeys.newKeyPair().privHex,
        theirPub: offer.pub,
        receiverPub: offer.pub,
        senderPub: Uint8List.fromList(base64Decode(real.pairingEpk!)),
      );
      expect(stolen, isNot(real.key));
    });

    test('الرمز الخاطئ يعطي مفتاحًا مختلفًا حتى مع ECDH صحيح', () async {
      final r = await receiver();
      final offer = r.session!;
      final other = offer.code == 'AAAAAAAA' ? 'BBBBBBBB' : 'AAAAAAAA';
      final s = await SyncSession.fromPairing(other, offer.saltB64, offer.pubB64);
      final good = await SyncSession.fromPairing(offer.code, offer.saltB64, offer.pubB64);
      expect(s.pairingEpk, isNot(good.pairingEpk));
      expect(offer.sessionFor(s.pairingEpk!)!.key, isNot(s.key));
      expect(offer.sessionFor(good.pairingEpk!)!.key, good.key);
    });

    test('مفتاح عام ليس على المنحنى يُرفض عند الطرفين', () async {
      final r = await receiver();
      final junk = base64Encode([4, ...List.filled(64, 1)]);
      expect(r.session!.sessionFor(junk), isNull);
      expect(r.session!.sessionFor('not-base64!!'), isNull);
      expect(PairingKeys.isValidPublic(Uint8List.fromList([4, ...List.filled(64, 1)])), isFalse);
      await expectLater(
        SyncSession.fromPairing(r.session!.code, r.session!.saltB64, junk),
        throwsA(isA<SyncCryptoError>()),
      );

      final headers = {
        ..._key().signHeaders('GET', '/info', const []),
        SyncSession.headerPairKey: junk,
      };
      final res = await raw('/info', headers: headers);
      expect(res.statusCode, HttpStatus.unauthorized);
      final failed = await _audit(target, 'sync.pair.failed');
      expect(failed.map((d) => d['reason']), contains('bad_key'));
    });

    test('جهاز v2 يوقّع بلا مفتاح اقتران ⇒ يُرفض بوضوح ويُسجَّل', () async {
      await receiver();
      final res = await raw('/info', headers: _key().signHeaders('GET', '/info', const []));
      expect(res.statusCode, HttpStatus.unauthorized);

      final failed = await _audit(target, 'sync.pair.failed');
      expect(failed.map((d) => d['reason']), contains('v2_rejected'));
    });

    test('جهاز v3 يقترن بمستقبِل v2 ⇒ خطأ واضح بتحديث الجهاز الآخر', () async {
      final legacy = await HttpServer.bind(InternetAddress.loopbackIPv4, _legacyPort);
      addTearDown(() => legacy.close(force: true));
      legacy.listen((req) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'app': 'imdad-sync',
            'v': 2,
            'device': 'old',
            'id': 'AAAA1111',
            'salt': base64Encode(List.filled(16, 7)),
            'needsCode': true,
            'now': DateTime.now().millisecondsSinceEpoch,
          }));
        req.response.close();
      });

      final pairing = await LanSync(source).pair('127.0.0.1', 'ABCD2345', port: _legacyPort);
      expect(pairing.ok, isFalse);
      expect(pairing.message, 'يجب تحديث التطبيق على الجهاز الآخر أولاً');

      final failed = await _audit(source, 'sync.pair.failed');
      expect(failed.single['reason'], 'v2_rejected');
      expect(failed.single['role'], 'sender');
    });

    test('الرمز بحروف صغيرة وشرطة يُقبل', () async {
      final r = await receiver();
      final typed = PairingCode.format(r.session!.code).toLowerCase();
      final pairing = await LanSync(source).pair('127.0.0.1', typed, port: _port);
      expect(pairing.ok, isTrue, reason: pairing.message);
    });

    test('الجهاز المقترن سلفًا بمفتاح دائم لا يتأثر بالإصدار الجديد', () async {
      final r = LanSync(target, port: _port, discoveryPort: _discoveryPort);
      await r.startReceiving();
      addTearDown(r.stopReceiving);
      final sender = LanSync(source, port: _port, discoveryPort: _discoveryPort);
      final pairing = await sender.pair('127.0.0.1', r.session!.code);
      expect(pairing.ok, isTrue, reason: pairing.message);
      final granted = await sender.trust(pairing.peer!);
      expect(granted, isNotNull);

      // استقبال الموثوقين: لا رمز ولا مفتاح مؤقت، والتوقيع بالمفتاح الدائم وحده.
      await r.stopReceiving();
      await r.startReceiving(trustedOnly: true);
      final res = await sender.autoSync();
      expect(res.ok, isTrue, reason: res.message);
    });
  });

  group('تدقيق الاقتران', () {
    test('بدء ثم نجاح على الجهازين', () async {
      final r = await receiver();
      expect(await _audit(target, 'sync.pair.started'), hasLength(1));

      final pairing = await LanSync(source).pair('127.0.0.1', r.session!.code, port: _port);
      expect(pairing.ok, isTrue, reason: pairing.message);

      expect((await _audit(source, 'sync.pair.started')).single['role'], 'sender');
      expect((await _audit(source, 'sync.pair.success')).single['role'], 'sender');
      expect((await _audit(target, 'sync.pair.success')).single['role'], 'receiver');
      expect(await _audit(target, 'sync.pair.failed'), isEmpty);
    });

    test('رمز خاطئ يُسجَّل فشلًا بسببه عند الجهازين', () async {
      final r = await receiver();
      final wrong = r.session!.code == 'AAAAAAAA' ? 'BBBBBBBB' : 'AAAAAAAA';
      await LanSync(source).pair('127.0.0.1', wrong, port: _port);

      expect((await _audit(target, 'sync.pair.failed')).single['reason'], 'bad_code');
      expect((await _audit(source, 'sync.pair.failed')).single['reason'], 'bad_code');
      expect(await _audit(target, 'sync.pair.success'), isEmpty);
    });

    test('خمس محاولات فاشلة تُسجَّل ثم إغلاق الاستقبال بسبب «locked»', () async {
      final r = await receiver();
      for (var i = 0; i < LanSync.maxAuthFailures; i++) {
        await raw('/info');
      }
      await _until(() => !r.isReceiving);

      final reasons = (await _audit(target, 'sync.pair.failed')).map((d) => d['reason']).toList();
      expect(reasons.where((x) => x == 'v2_rejected'), hasLength(LanSync.maxAuthFailures));
      expect(reasons, contains('locked'));
    });
  });
}
