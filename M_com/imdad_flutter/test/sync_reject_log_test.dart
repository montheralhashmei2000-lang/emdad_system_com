import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';
import 'package:imdad/data/sync/sync_trust.dart';

/// خمدُ شواهد الرفض المتكررة في سجل التدقيق.
///
/// صفوف `sensitive` لا تُقلَّم أبدًا (`AuditRepo.protectedRisks`)، واستقبالُ
/// الموثوقين لا يُغلق بعد محاولاتٍ فاشلة — وذاك صواب: الإغلاق حينها سلاحٌ بيد
/// المهاجم. فكان من يَصِل الشبكةَ يكتب صفًّا دائمًا لكل طلبٍ مرفوض بلا حدّ،
/// فينفخ القاعدةَ المشفّرة حتى يملأ القرص.
///
/// والخمدُ لا يجوز أن يُخفي الخبر: أولُ رفضٍ يُسجَّل كاملًا دائمًا، وما خُمد
/// يُعَدّ ويُعلَن عند انقضاء النافذة.
void main() {
  var now = DateTime(2026, 10, 8, 12);
  RejectLog make() => RejectLog(clock: () => now);

  test('أول رفضٍ يُسجَّل كاملًا', () {
    expect(make().hit('10.0.0.5|bad_code'), isNull);
  });

  test('المتكرر في النافذة يُخمَد', () {
    final log = make();
    expect(log.hit('10.0.0.5|bad_code'), isNull, reason: 'الأول يُسجَّل');
    for (var i = 0; i < 1000; i++) {
      expect(log.hit('10.0.0.5|bad_code'), 0, reason: 'الطلب ${i + 2} كُتب شاهدًا');
    }
  });

  test('انقضاء النافذة يُخرج ملخَّصًا بعدد ما خُمد', () {
    final log = make();
    log.hit('10.0.0.5|bad_code');
    for (var i = 0; i < 7; i++) {
      log.hit('10.0.0.5|bad_code');
    }

    now = now.add(RejectLog.window + const Duration(seconds: 1));
    expect(log.hit('10.0.0.5|bad_code'), 7, reason: 'عدد ما خُمد لم يُعلَن');

    // والنافذة الجديدة تبدأ من جديد: لا ملخَّصٌ بلا خمد.
    now = now.add(RejectLog.window + const Duration(seconds: 1));
    expect(log.hit('10.0.0.5|bad_code'), 0, reason: 'ملخَّصٌ بلا شيءٍ خُمد');
  });

  test('كل مصدرٍ وسببٍ على حدة — خمدُ أحدهما لا يُخفي غيره', () {
    final log = make();
    expect(log.hit('10.0.0.5|bad_code'), isNull);
    expect(log.hit('10.0.0.5|bad_code'), 0);
    // عنوانٌ آخر: شاهدٌ كامل رغم خمد الأول.
    expect(log.hit('10.0.0.9|bad_code'), isNull, reason: 'مصدرٌ جديد خُمد بغيره');
    // سببٌ آخر من العنوان نفسه: كذلك.
    expect(log.hit('10.0.0.5|v2_rejected'), isNull, reason: 'سببٌ جديد خُمد بغيره');
  });

  test('تبديلُ العنوان في كل طلب لا يُنمي الخريطة بلا حدّ', () {
    final log = make();
    for (var i = 0; i < RejectLog.maxKeys * 3; i++) {
      log.hit('10.0.$i.1|bad_code');
    }
    expect(log.length, lessThanOrEqualTo(RejectLog.maxKeys));
  });

  test('النافذة قصيرةٌ بما يكفي ألّا تُخفي هجومًا', () {
    // دقائقُ لا ساعات: هجومٌ مستمر يترك أثرًا كل نافذة، فيُرى في السجل.
    expect(RejectLog.window.inMinutes, lessThanOrEqualTo(5));
    expect(RejectLog.window.inSeconds, greaterThanOrEqualTo(30));
  });

  group('على الخادم فعلًا', () {
    const port = 8829;
    const peerId = 'PEER0001';
    late AppDatabase db;
    late LanSync server;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      server = LanSync(db, port: port, discoveryPort: port + 1);
    });

    tearDown(() async {
      await server.stopReceiving();
      await db.close();
    });

    /// عددُ شواهد التدقيق بهذا الإجراء.
    Future<int> rows(String action) async =>
        (await AuditRepo(db).recent(limit: 500)).where((l) => l.action == action).length;

    /// جهازٌ موثوقٌ مسجَّل — بلا هذا لا يبلغ الطلبُ مسارَ التوقيع أصلًا:
    /// معرّفٌ مجهول يُرفض في [LanSync] قبله بـ«جهاز غير موثوق» **بلا شاهد**،
    /// فلا تضخّمَ من جهازٍ لم يُعرف قط. التضخّم يحتاج معرّفَ قرينٍ موثوق —
    /// وهو يُرسَل صريحًا على HTTP عادي، فمتنصّتٌ سلبي يقرؤه.
    Future<void> trustPeer(String deviceId) => SyncTrust(db).accept(TrustedPeer(
          deviceId: deviceId,
          key: Uint8List.fromList(List.generate(32, (i) => i)),
          name: 'قرين',
        ));

    /// طلبٌ خامٌ يحمل معرّفَ جهازٍ موثوقٍ بتوقيعٍ فاسد: يبلغ مسارَ التوقيع ويسقط فيه.
    Future<void> flood(int n) async {
      final client = HttpClient();
      for (var i = 0; i < n; i++) {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/info'));
        req.headers.set(SyncSession.headerDevice, peerId);
        req.headers.set(SyncSession.headerTs, '${DateTime.now().millisecondsSinceEpoch}');
        req.headers.set(SyncSession.headerNonce, 'n$i');
        req.headers.set(SyncSession.headerMac, 'bm90LWEtbWFj');
        final res = await req.close();
        await res.drain<void>();
      }
      client.close();
    }

    test('إغراقُ وضع الموثوقين لا يُضخّم سجل التدقيق', () async {
      await trustPeer(peerId);
      await server.startReceiving(trustedOnly: true);
      await flood(60);

      // بلا خمدٍ كان كلُّ طلبٍ صفًّا دائمًا (`sensitive` لا يُقلَّم).
      final n = await rows('sync.reject') + await rows('sync.pair.failed');
      expect(n, lessThan(10), reason: 'سجل التدقيق تضخّم بـ$n صفًّا من ٦٠ طلبًا مرفوضًا');
      // والمنفذ باقٍ: الخمد ليس إغلاقًا.
      expect(server.isReceiving, isTrue);
    });

    test('وضعُ الاقتران يُسجّل كل محاولة (محدودٌ أصلًا بالإغلاق)', () async {
      await trustPeer(peerId);
      await server.startReceiving();
      await flood(LanSync.maxAuthFailures);

      // محاولاتُ تخمينِ رمز الاقتران أنفسُ ما في السجل، وسقفُها الإغلاق لا الخمد.
      expect(await rows('sync.pair.failed'), greaterThanOrEqualTo(LanSync.maxAuthFailures),
          reason: 'خُمدت محاولاتُ تخمين الرمز — وهي ما يجب أن يُسجَّل كاملًا');
    });
  });
}
