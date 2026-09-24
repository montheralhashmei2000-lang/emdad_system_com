import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';

/// اختبارات أمن المزامنة: تثبت أن المنفذ المفتوح على الشبكة لا يسلّم بيانات
/// ولا يقبلها إلا من جهاز يحمل رمز الاقتران المعروض على شاشة المستقبِل.

/// منفذان خاصّان بهذا الملف (انظر التعليق في `sync_excel_test.dart`).
const int _port = 8793;
const int _discoveryPort = 8794;

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
      expect(body.keys.toSet(), {'app', 'v', 'device', 'id', 'salt', 'needsCode', 'now'});
      expect((body['salt'] as String).isNotEmpty, isTrue);
      expect((body['id'] as String).length, 8);
    });

    test('رمز اقتران خاطئ لا يفتح جلسة', () async {
      final r = await receiver();
      final wrong = r.session!.code == '000000' ? '111111' : '000000';
      final pairing = await LanSync(source).pair('127.0.0.1', wrong, port: _port);

      expect(pairing.ok, isFalse);
      expect(pairing.peer, isNull);
      expect(pairing.message, contains('غير صحيح'));
    });

    test('رمز بغير ستة أرقام يُرفض قبل أي اتصال', () async {
      await receiver();
      final pairing = await LanSync(source).pair('127.0.0.1', '12ab', port: _port);
      expect(pairing.ok, isFalse);
      expect(pairing.message, contains('ستة أرقام'));
    });

    test('إعادة إرسال طلب موقَّع سليم لا تُقبل مرتين', () async {
      final r = await receiver();
      final session = SyncSession.fromCode(r.session!.code, r.session!.saltB64);
      final headers = session.signHeaders('GET', '/info', const []);

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
      final a = SyncSession.create();
      final b = SyncSession.fromCode(a.code, a.saltB64);
      final other = SyncSession.create();

      final sealed = a.sealJson({'x': 'سرّ'});
      expect(b.openJson(sealed)['x'], 'سرّ');
      expect(() => other.openJson(sealed), throwsA(isA<SyncCryptoError>()));
    });

    test('العبث ببايت واحد يُكتشف ولا يُفكّ التشفير', () {
      final s = SyncSession.create();
      final sealed = s.sealJson({'qty': 10});
      sealed[sealed.length - 1] ^= 0xFF;

      expect(() => s.openJson(sealed), throwsA(isA<SyncCryptoError>()));
    });

    test('الرمز نفسه مع ملح مختلف يعطي مفتاحًا مختلفًا', () {
      final a = SyncSession.create();
      final b = SyncSession.create();
      final impostor = SyncSession.fromCode(a.code, b.saltB64);

      expect(impostor.fingerprint, isNot(a.fingerprint));
    });

    test('التوقيع مرتبط بالمسار والفعل والجسم', () {
      final s = SyncSession.create();
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
      final s = SyncSession.create();
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
}
