import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/sync_trust.dart';

/// إلغاء تفعيل الأجهزة: قرارٌ موقَّعٌ من المالك، ويقطع الثقة.
///
/// كان يُقبل بلا توقيع والختم بيد المرسِل، فأيُّ قرينٍ مقترن يستطيع أن **يُلغي
/// تفعيل جهاز الإدارة** بختمٍ من المستقبل فلا يُنقَض، أو أن **يُحيي جهازًا
/// مسروقًا** أُلغي تفعيله. وكان الإلغاء لا يُسقط الثقة، فيبقى الجهاز الملغى
/// قرينًا يُفتح له المنفذ ويُقبل منه السحب والدفع.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String ownerPub;
  late String ownerPriv;

  const branchId = 'BRANCH01';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final pair = ESign.generateKeyPair();
    ownerPub = pair.publicB64;
    ownerPriv = pair.privateHex;
  });

  tearDown(() => db.close());

  DeviceActivation act([AppDatabase? on]) =>
      DeviceActivation(on ?? db, ownerPublicKey: ownerPub);

  /// توقيعُ مالكٍ صحيح على قرارٍ بعينه.
  String sign(String deviceId, bool revoked, int atMs) => base64Url.encode(ESign.signRawWithKey(
        privateHex: ownerPriv,
        digest: DeviceActivation.revocationDigest(deviceId: deviceId, revoked: revoked, atMs: atMs),
      ));

  Map<String, Object?> incoming(String deviceId, bool revoked, int atMs, {String? sig}) => {
        deviceId: {'revoked': revoked, 'at': atMs, if (sig != null) 'sig': sig},
      };

  Future<List<AuditLog>> rejections() => (db.select(db.auditLogs)
        ..where((t) => t.action.equals('sync.revocation_rejected')))
      .get();

  Future<void> trustBranch() =>
      SyncTrust(db).accept(TrustedPeer(deviceId: branchId, key: Uint8List.fromList(List.filled(32, 7))));

  group('الوارد بالمزامنة', () {
    test('إلغاء غير موقَّع ⇒ يُرفض ويُدقَّق', () async {
      final at = DateTime.now().millisecondsSinceEpoch;
      expect(await act().mergeRevocations(incoming('HQ000001', true, at)), 0);
      expect(await act().isRevoked('HQ000001'), isFalse);
      expect(await rejections(), hasLength(1));
    });

    test('إلغاء موقَّع ⇒ يُقبل', () async {
      final at = DateTime.now().millisecondsSinceEpoch;
      expect(await act().mergeRevocations(incoming(branchId, true, at, sig: sign(branchId, true, at))), 1);
      expect(await act().isRevoked(branchId), isTrue);
      expect(await rejections(), isEmpty);
    });

    test('الإلغاء الموقَّع الوارد يقطع الثقة بالقرين', () async {
      await trustBranch();
      final at = DateTime.now().millisecondsSinceEpoch;
      await act().mergeRevocations(incoming(branchId, true, at, sig: sign(branchId, true, at)));
      expect(await SyncTrust(db).accepted(), isEmpty, reason: 'الجهاز الملغى بقي قرينًا موثوقًا');
      expect(await SyncTrust(db).peers(), isEmpty);
    });

    test('توقيعٌ منقولٌ من قرارٍ آخر ⇒ يُرفض', () async {
      final at = DateTime.now().millisecondsSinceEpoch;
      // توقيعُ «أُلغي» يُقدَّم مع «أُعيد»، وتوقيعُ جهازٍ يُقدَّم لجهازٍ آخر،
      // وتوقيعٌ صحيحٌ بختمٍ غير ختمه.
      expect(await act().mergeRevocations(incoming(branchId, false, at, sig: sign(branchId, true, at))), 0);
      expect(await act().mergeRevocations(incoming('OTHER999', true, at, sig: sign(branchId, true, at))), 0);
      expect(await act().mergeRevocations(incoming(branchId, true, at + 1, sig: sign(branchId, true, at))), 0);
      expect(await rejections(), hasLength(3));
    });

    test('إحياء جهازٍ ملغى بختمٍ من المستقبل بلا توقيع ⇒ يُرفض ويبقى ملغى', () async {
      final at = DateTime.now().millisecondsSinceEpoch;
      await act().mergeRevocations(incoming(branchId, true, at, sig: sign(branchId, true, at)));
      const future = 4000000000000;
      expect(await act().mergeRevocations(incoming(branchId, false, future)), 0);
      expect(await act().isRevoked(branchId), isTrue, reason: 'أُحيي جهازٌ ملغى بلا توقيع');
    });

    test('ختمٌ أقدم من المحلي يُهمَل ولا يُدقَّق رفضًا', () async {
      final at = DateTime.now().millisecondsSinceEpoch;
      await act().mergeRevocations(incoming(branchId, true, at, sig: sign(branchId, true, at)));
      expect(await act().mergeRevocations(incoming(branchId, false, at - 1000)), 0);
      expect(await rejections(), isEmpty, reason: 'قرارٌ بائتٌ ليس هجومًا');
    });

    test('بلا مفتاح مالكٍ مضبوط (وضع التطوير) لا يُفرض التوقيع', () async {
      final dev = DeviceActivation(db, ownerPublicKey: '');
      final at = DateTime.now().millisecondsSinceEpoch;
      expect(await dev.mergeRevocations(incoming(branchId, true, at)), 1);
      expect(await dev.isRevoked(branchId), isTrue);
    });

    test('حمولةٌ مشوّهة لا تُسقط الدمج', () async {
      expect(await act().mergeRevocations('ليست خريطة'), 0);
      expect(await act().mergeRevocations({'X': 'ليس صفًّا'}), 0);
      expect(await act().mergeRevocations({'X': {'revoked': true}}), 0);
    });
  });

  group('القرار المحلي', () {
    test('على جهاز المالك: يُوقَّع فينتشر، ويقطع الثقة', () async {
      final a = act();
      expect(await a.importPrivateKey(ownerPriv), isTrue);
      await trustBranch();

      expect(await a.setRevoked(branchId, true), isTrue, reason: 'لم يُوقَّع والمفتاح موجود');
      expect(await a.isRevoked(branchId), isTrue);
      expect(await SyncTrust(db).accepted(), isEmpty);

      // ويعبر إلى جهازٍ آخر لأنه موقَّع.
      final branchDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(branchDb.close);
      expect(await act(branchDb).mergeRevocations(await a.revocationsForSync()), 1);
      expect(await act(branchDb).isRevoked(branchId), isTrue);
    });

    test('على جهازٍ بلا مفتاح المالك: يُطبَّق محليًّا ولا ينتشر', () async {
      final a = act();
      expect(await a.setRevoked(branchId, true), isFalse, reason: 'ادّعى التوقيع بلا مفتاح');
      expect(await a.isRevoked(branchId), isTrue, reason: 'لم يُطبَّق محليًّا');

      final branchDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(branchDb.close);
      expect(await act(branchDb).mergeRevocations(await a.revocationsForSync()), 0);
      expect(await act(branchDb).isRevoked(branchId), isFalse);
    });

    test('إعادة التفعيل لا تُعيد الثقة (الاقتران اليدوي وحده يمنحها)', () async {
      final a = act();
      await a.importPrivateKey(ownerPriv);
      await trustBranch();
      await a.setRevoked(branchId, true);
      expect(await a.setRevoked(branchId, false), isTrue);
      expect(await SyncTrust(db).accepted(), isEmpty);
    });
  });
}
