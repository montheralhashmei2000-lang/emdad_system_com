import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';

/// تصليب المزامنة: تقليم الـnonce بالزمن، والتحقق من التوقيع قبل قراءة الجسم،
/// وحالة الفشل الصريحة، وعدم تصدير بصمات المديرين بالمزامنة.

const int _port = 8801;
const int _discoveryPort = 8802;

SyncSession _key([int seed = 1]) =>
    SyncSession.fromKey(Uint8List.fromList(List.generate(32, (i) => (seed * 31 + i) & 0xff)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  group('NonceCache — تقليم بالزمن', () {
    test('إعادة الإرسال تُرفض، وما تجاوز النافذة يُقلَّم فلا ينمو السجل', () {
      var now = DateTime(2026, 1, 1, 12);
      final cache = NonceCache(ttl: const Duration(minutes: 11), clock: () => now);

      expect(cache.add('a'), isTrue);
      expect(cache.add('a'), isFalse, reason: 'إعادة إرسال');
      for (var i = 0; i < 100; i++) {
        cache.add('n$i');
      }
      expect(cache.length, 101);

      now = now.add(const Duration(minutes: 12));
      expect(cache.add('fresh'), isTrue);
      expect(cache.length, 1, reason: 'كل ما أقدم من النافذة قُلِّم');
    });

    test('السقف الصلب: عند الامتلاء يُرفض الجديد (مغلق لا مفتوح)', () {
      final cache = NonceCache(maxEntries: 3);
      expect(cache.add('1') && cache.add('2') && cache.add('3'), isTrue);
      expect(cache.add('4'), isFalse);
      expect(cache.length, 3);
    });
  });

  group('التحقق قبل قراءة الجسم', () {
    test('verifyPreBody يقبل البصمة المعلنة الموقَّعة ويرفض غيرها', () {
      final s = _key();
      final body = utf8.encode('payload');
      final h = s.signHeaders('POST', '/import', body);
      String? check(String digest, {String? mac}) => s.verifyPreBody(
            method: 'POST',
            path: '/import',
            ts: h[SyncSession.headerTs],
            nonce: h[SyncSession.headerNonce],
            mac: mac ?? h[SyncSession.headerMac],
            claimedDigest: digest,
            seenNonces: <String>{},
          );

      expect(check(h[SyncSession.headerBodyDigest]!), isNull);
      expect(check('0' * 64), isNotNull, reason: 'بصمة لم يوقَّع عليها');
      expect(check(h[SyncSession.headerBodyDigest]!, mac: 'AAAA'), isNotNull);
      expect(SyncSession.digestMatches(body, h[SyncSession.headerBodyDigest]!), isTrue);
      expect(SyncSession.digestMatches(utf8.encode('tampered'), h[SyncSession.headerBodyDigest]!), isFalse);
    });

    test('verify القديم (على الجسم) ما زال يعمل', () {
      final s = _key();
      final h = s.signHeaders('GET', '/info', const []);
      expect(
        s.verify(
          method: 'GET',
          path: '/info',
          ts: h[SyncSession.headerTs],
          nonce: h[SyncSession.headerNonce],
          mac: h[SyncSession.headerMac],
          body: const [],
          seenNonces: <String>{},
        ),
        isNull,
      );
    });

    Future<String> rawPost(String path, int length) async {
      final epk = base64Encode(PairingKeys.newKeyPair().pub);
      final socket = await Socket.connect('127.0.0.1', _port);
      socket.write('POST $path HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Content-Length: $length\r\n'
          '${SyncSession.headerPairKey}: $epk\r\n\r\n');
      final reply = await utf8.decoder.bind(socket).join().timeout(const Duration(seconds: 5));
      await socket.close();
      return reply;
    }

    Future<void> startReceiver() async {
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final r = LanSync(target, port: _port, discoveryPort: _discoveryPort);
      await r.startReceiving();
      addTearDown(r.stopReceiving);
    }

    test('POST /import بلا بصمة الجسم يُرفض 401 ولا يُقرأ جسمه', () async {
      await startReceiver();
      expect(await rawPost('/import', 50000000), contains('401'));
    });

    test('جسم أكبر من سقف المسارات الصغيرة يُرفض 413', () async {
      await startReceiver();
      expect(await rawPost('/trust', LanSync.maxSmallBodyBytes + 1), contains('413'));
    });
  });

  group('حالة الفشل الصريحة', () {
    test('SyncResult.failed افتراضيًا عكس ok، ويمكن فصلهما', () {
      expect(const SyncResult(ok: true).failed, isFalse);
      expect(const SyncResult(ok: false, message: 'x').failed, isTrue);
      expect(const SyncResult(ok: false, failed: false, message: 'لا جهاز').failed, isFalse);
    });
  });

  group('بصمة المالك لا تُصدَّر بالمزامنة', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.users).insert(UsersCompanion.insert(
          id: 'o1', username: 'o1', role: const Value('owner'), saltHex: const Value('ss'), hashHex: const Value('hh')));
      await db.into(db.users).insert(UsersCompanion.insert(
          id: 'u1', username: 'u1', saltHex: const Value('s2'), hashHex: const Value('h2')));
      await db.into(db.users).insert(UsersCompanion.insert(
          id: 'a1', username: 'a1', role: const Value('admin'), saltHex: const Value('s3'), hashHex: const Value('h3')));
    });
    tearDown(() => db.close());

    Map<String, dynamic> userOf(Map<String, dynamic> m, String id) =>
        ((m['users'] as List).cast<Map<String, dynamic>>()).firstWhere((u) => u['id'] == id);

    test('المزامنة: المالك بلا ملح ولا بصمة، والمدير والمستخدم العادي بهما', () async {
      final map = await DataExporter(db).toMap(includeUsers: true, includeOwnerSecrets: false);
      expect(userOf(map, 'o1').containsKey('hashHex'), isFalse);
      expect(userOf(map, 'o1').containsKey('saltHex'), isFalse);
      expect(userOf(map, 'u1')['hashHex'], 'h2');
      expect(userOf(map, 'a1')['hashHex'], 'h3', reason: 'مدير الفرع يدخل بكلمته على جهازه');
    });

    test('النسخة الاحتياطية الافتراضية تُبقي الكل', () async {
      final map = await DataExporter(db).toMap(includeUsers: true);
      expect(userOf(map, 'o1')['hashHex'], 'hh');
    });

    test('الاستيراد يُبقي بصمة المالك القائمة حين تغيب من الحمولة ولا يُرفض الصف', () async {
      final map = await DataExporter(db).toMap(includeUsers: true, includeOwnerSecrets: false);
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      await other.into(other.users).insert(UsersCompanion.insert(
          id: 'o1', username: 'o1', role: const Value('owner'), saltHex: const Value('mine'), hashHex: const Value('mine')));
      final res = await LegacyImporter(other, ownerPublicKey: 'x').importJson({
        'users': map['users'],
        'syncMarks': [
          {'entity': 'users', 'rowId': 'o1', 'updatedAt': 99999999999999},
        ],
      });
      // المدير الجديد 'a1' بلا توقيع يُرفض (قاعدة الدور)؛ المالك القائم لا.
      expect(res.rejectedUsers.where((r) => r.id == 'o1'), isEmpty);
      final kept = await (other.select(other.users)..where((t) => t.id.equals('o1'))).getSingle();
      expect(kept.hashHex, 'mine');
    });
  });
}
