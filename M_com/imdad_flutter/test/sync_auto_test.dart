import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/web_import.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_crypto.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/data/sync/sync_trust.dart';

/// اختبارات الاقتران الدائم والمزامنة التلقائية.
///
/// السؤال الذي تجيب عنه: هل يزامن جهازٌ نفسه بلا إنسان يكتب رمزًا — **وهل
/// يبقى الباب مغلقًا** في وجه من لم يُمنح ذلك المفتاح؟

/// منفذان خاصّان بهذا الملف حتى لا يقتسم خادمان طلبات منفذ واحد.
const int _port = 8795;
const int _discoveryPort = 8796;

Future<void> _until(bool Function() condition, {Duration limit = const Duration(seconds: 3)}) async {
  final deadline = DateTime.now().add(limit);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase branch; // الجهاز الذي يطلب
  late AppDatabase master; // الجهاز المستقبِل

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    branch = AppDatabase.forTesting(NativeDatabase.memory());
    master = AppDatabase.forTesting(NativeDatabase.memory());
    await CatalogRepo(master).saveItem(
      code: 'X1',
      name: 'دقيق',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() async {
    await branch.close();
    await master.close();
  });

  /// اقتران يدوي كامل ينتهي بمنح ثقة دائمة — الخطوة التي يحضرها إنسان مرة.
  Future<({LanSync client, LanSync server, TrustedPeer peer})> bond() async {
    final server = LanSync(master, port: _port, discoveryPort: _discoveryPort);
    await server.startReceiving();
    addTearDown(server.stopReceiving);

    final client = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
    final pairing = await client.pair('127.0.0.1', server.session!.code, port: _port);
    expect(pairing.ok, isTrue, reason: pairing.message);

    final granted = await client.trust(pairing.peer!);
    expect(granted, isNotNull, reason: 'الجهاز المستقبِل رفض منح الثقة');
    return (client: client, server: server, peer: granted!);
  }

  group('الاقتران الدائم', () {
    test('المنح يحفظ الطرفين: مفتاحًا هنا وقبولًا هناك', () async {
      final b = await bond();

      final mine = await SyncTrust(branch).peers();
      final theirs = await SyncTrust(master).accepted();
      expect(mine.single.deviceId, await b.server.deviceId());
      expect(theirs.keys.single, await b.client.deviceId());
      // المفتاح نفسه على الجهازين، وإلا لما نجح أي طلب بعد اليوم.
      expect(mine.single.key, theirs.values.single.key);
    });

    test('الجهاز الموثوق يزامن بعد إعادة فتح المنفذ بلا رمز جديد', () async {
      final b = await bond();

      // الرمز القديم يموت مع الجلسة: هذه هي الحالة التي تفشل فيها كل مزامنة
      // «تلقائية» مبنية على رمز محفوظ.
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);

      final res = await b.client.autoSync();
      expect(res.ok, isTrue, reason: res.message);
      final items = await CatalogRepo(branch).items();
      expect(items.map((i) => i.code), contains('X1'));
    });

    test('استقبال الموثوقين لا يفتح بابًا لغير الموثوق', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);

      // جهاز ثالث لم يقترن قط: قاعدته فارغة فمعرّفه غير مقبول، ولا رمز يُشتق منه.
      final stranger = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(stranger.close);
      final intruder = LanSync(stranger, port: _port, discoveryPort: _discoveryPort);
      final res = await intruder.autoSync();

      expect(res.ok, isFalse);
      final leaked = await CatalogRepo(stranger).items();
      expect(leaked, isEmpty, reason: 'تسرّبت بيانات إلى جهاز غير موثوق');
    });

    test('محاولات فاشلة كثيرة لا تُغلق استقبال الموثوقين', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);

      // الإغلاق التلقائي حارسٌ لرمز الأرقام الستة. هنا لا رمز، فلو أُغلق المنفذ
      // لصار تعطيل مزامنة الوحدة كلها بخمسة طلبات فارغة.
      final client = HttpClient();
      for (var i = 0; i < LanSync.maxAuthFailures + 2; i++) {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$_port/info'));
        final res = await req.close();
        await res.drain<void>();
        expect(res.statusCode, HttpStatus.forbidden);
      }
      client.close();

      expect(b.server.isReceiving, isTrue);
    });

    test('النسيان يقطع الثقة فتتوقف المزامنة التلقائية', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      await SyncTrust(master).forget(await b.client.deviceId());

      final res = await b.client.autoSync();
      expect(res.ok, isFalse);
    });

    test('اقتران يدوي جديد ينجح رغم وجود مفتاح ثقة قديم', () async {
      // الجهاز يوقّع بمفتاح الرمز بينما يعرفه المستقبِل بمفتاح الثقة: لو جُرّب
      // مفتاح واحد لرُفض كل إعادة اقتران بعد الأولى.
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving();

      final again = await b.client.pair('127.0.0.1', b.server.session!.code, port: _port);
      expect(again.ok, isTrue, reason: again.message);
    });
  });

  group('إعدادات المزامنة التلقائية', () {
    test('المفتاح والدورة يُحفظان ويُقرآن', () async {
      final store = SyncTrust(branch);
      expect(await store.isAuto(), isFalse);
      expect(await store.interval(), SyncTrust.defaultInterval);

      await store.setAuto(true);
      await store.setInterval(const Duration(minutes: 5));

      expect(await store.isAuto(), isTrue);
      expect(await store.interval(), const Duration(minutes: 5));
    });

    test('بلا جهاز موثوق تقول المزامنة ذلك ولا تتظاهر بالنجاح', () async {
      final res = await LanSync(branch, port: _port).autoSync();
      expect(res.ok, isFalse);
      expect(res.message, contains('اقترن'));
    });
  });

  group('المزامنة التفاضلية', () {
    test('أول سحبة كاملة، والتي بعدها لا تحمل إلا ما تغيّر', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);

      final first = await b.client.autoSync();
      expect(first.ok, isTrue, reason: first.message);
      expect(await CatalogRepo(branch).items(), isNotEmpty);

      // دورة ثانية بلا تغيير: الدمج بالمعرّف لا بالإضافة، فلا يتضاعف شيء.
      // (حجم الحمولة نفسه تقيسه اختبارات التصدير التفاضلي أدناه — قاعدة
      // الاختبار أصغر من أن يُقاس عليها توفير البايتات.)
      final idle = await b.client.autoSync();
      expect(idle.ok, isTrue, reason: idle.message);
      expect((await CatalogRepo(branch).items()).length, 1, reason: 'تضاعفت السجلات');

      // صنف جديد عند الإدارة ⇒ يصل وحده.
      await CatalogRepo(master).saveItem(
        code: 'X2',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final third = await b.client.autoSync();
      expect(third.ok, isTrue, reason: third.message);
      expect((await CatalogRepo(branch).items()).map((i) => i.code), containsAll(['X1', 'X2']));
    });

    test('التصدير التفاضلي لا يحمل إلا ما تغيّر بعد الختم', () async {
      final marks = SyncMarks(master);
      final before = await marks.maxStamp();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await CatalogRepo(master).saveItem(
        code: 'X9',
        name: 'سكر',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

      final delta = await DataExporter(master).toMap(since: before);
      final full = await DataExporter(master).toMap();

      expect((delta['items'] as List).length, 1, reason: 'خرج أكثر مما تغيّر');
      expect((full['items'] as List).length, greaterThan(1));
      expect((delta['items'] as List).single['code'], 'X9');
      // الجداول التي لم تتغيّر تخرج فارغة لا محذوفة، فالدمج لا يظنّها حذفًا.
      expect(delta['warehouses'], isEmpty);
    });

    test('الحذف ينتقل في الحمولة التفاضلية كما ينتقل التعديل', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      await b.client.autoSync();
      expect((await CatalogRepo(branch).items()).map((i) => i.code), contains('X1'));

      final doomed = (await CatalogRepo(master).items()).firstWhere((i) => i.code == 'X1');
      await CatalogRepo(master).deleteItem(doomed.id);

      final res = await b.client.autoSync();
      expect(res.ok, isTrue, reason: res.message);
      expect(
        (await CatalogRepo(branch).items()).map((i) => i.code),
        isNot(contains('X1')),
        reason: 'بقي المحذوف في الفرع — شاهد الحذف لم يعبر الحمولة الجزئية',
      );
    });

    test('علامة الماء تُحفظ بعد الدورة فلا تُعاد من الصفر', () async {
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);

      expect((await SyncTrust(branch).peers()).single.pulledUpTo, 0);
      await b.client.autoSync();
      final after = (await SyncTrust(branch).peers()).single;
      expect(after.pulledUpTo, greaterThan(0));
      expect(after.pushedUpTo, greaterThanOrEqualTo(0));
    });
  });

  group('اكتمال البيانات في الجهاز الجديد', () {
    test('أول مزامنة تشمل الجرد والتدقيق لا الحركات وحدها', () async {
      // جلسة جرد وسطر تدقيق عند الإدارة قبل أن يُعتمد الفرع أصلًا — هذا هو
      // حال فرعٍ يُضاف بعد شهور من عمل البقية.
      await master.into(master.stocktakes).insert(StocktakesCompanion.insert(
            id: 'st-1',
            orderNo: const Value('ج/١'),
            warehouse: const Value('الرئيسي'),
            status: const Value('CLOSED'),
          ));
      await master.into(master.stocktakeLines).insert(StocktakeLinesCompanion.insert(
            id: 'stl-1',
            sessionId: 'st-1',
            itemId: 'i-1',
            itemName: const Value('دقيق'),
            systemQty: const Value(10),
          ));
      await AuditRepo(master).log(
        action: 'test.write',
        entityType: 'اختبار',
        summary: 'سطر تدقيق سابق لاعتماد الفرع',
      );

      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      final res = await b.client.autoSync();
      expect(res.ok, isTrue, reason: res.message);

      expect(await branch.select(branch.stocktakes).get(), hasLength(1));
      expect(await branch.select(branch.stocktakeLines).get(), hasLength(1));
      expect(
        await branch.select(branch.auditLogs).get(),
        isNotEmpty,
        reason: 'سجل التدقيق لم يصل الجهاز الجديد',
      );
    });

    test('سطر كُتب قبل تركيب المحفِّزات يُملأ له ختم فيُزامَن', () async {
      // الجداول الأربعة أُضيفت إلى المزامنة بعد أن عملت الأجهزة شهورًا، ولا
      // علامة لسطورها القديمة. بلا الملء الرجعي تبقى غائبة عن كل جهاز تجاوز
      // مزامنته الأولى.
      await master.customStatement(
        "DELETE FROM ${SyncMarks.table} WHERE entity = 'stocktakes'",
      );
      await master.into(master.stocktakes).insert(
            StocktakesCompanion.insert(id: 'st-old', orderNo: const Value('قديم')),
          );
      await master.customStatement(
        "DELETE FROM ${SyncMarks.table} WHERE entity = 'stocktakes'",
      );
      expect(await SyncMarks(master).changedSince(0), isNot(contains(
        predicate<SyncMark>((m) => m.entity == 'stocktakes'),
      )));

      await SyncMarks.install(master);

      final marked = await SyncMarks(master).changedSince(0);
      expect(
        marked.where((m) => m.entity == 'stocktakes').map((m) => m.rowId),
        contains('st-old'),
      );
    });
  });

  group('الحسابات تصل صالحة للدخول', () {
    test('حساب المدير يُدخل به في الفرع بكلمة مروره نفسها', () async {
      // هذا هو الاختبار الذي كان ناقصًا: كانت الحسابات تصل فعلًا، وتُعدّ
      // المزامنة ناجحة، ثم يستحيل الدخول بأيٍّ منها — لأن الملح والبصمة
      // يخرجان في التصدير ولا يقرؤهما الاستيراد.
      await AuthService(master).createAdmin(username: 'admin', password: 'Test@12345');

      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      expect((await b.client.autoSync()).ok, isTrue);

      final res = await AuthService(branch).login('admin', 'Test@12345');
      expect(res.isOk, isTrue, reason: 'وصل الحساب ولم يُقبل الدخول به: ${res.message}');
      expect(res.user!.role, 'admin');
    });

    test('كلمة مرور خاطئة تُرفض في الفرع كما تُرفض في الأصل', () async {
      await AuthService(master).createAdmin(username: 'admin', password: 'Test@12345');
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      await b.client.autoSync();

      final res = await AuthService(branch).login('admin', 'wrong-password');
      expect(res.isOk, isFalse, reason: 'قُبلت كلمة مرور خاطئة');
    });

    test('حمولة بلا بصمات لا تمحو كلمة مرور قائمة', () async {
      // نسخة ويب قديمة لا تحمل salt/hash: الاستيراد منها كان سيُفرغ كلمات
      // المرور على هذا الجهاز، فيقفل الجميع خارج النظام بلا سبب ظاهر.
      await AuthService(branch).createAdmin(username: 'admin', password: 'Test@12345');
      await WebImporter(branch).importJson({
        'users': [
          {'id': 'local-admin', 'username': 'admin', 'name': 'admin', 'role': 'admin'},
        ],
      });

      final res = await AuthService(branch).login('admin', 'Test@12345');
      expect(res.isOk, isTrue, reason: 'مُحيت كلمة المرور القائمة: ${res.message}');
    });
  });

  group('إعادة التعيين المحلي لا تتعدّى جهازها', () {
    test('مسح حسابات الفرع لا يحذف حساب المدير على جهاز الإدارة', () async {
      // السيناريو الذي أوقع النظام: مسؤول فرعٍ نسي كلمة مروره فضغط «إعادة
      // تعيين محلي»، فسافر شاهد الحذف إلى الإدارة وحذف حساب المدير هناك.
      await AuthService(master).createAdmin(username: 'admin', password: 'Test@12345');
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      await b.client.autoSync();
      expect(await AuthService(branch).hasAnyUser(), isTrue);

      await AuthService(branch).localReset();
      expect(await AuthService(branch).hasAnyUser(), isFalse, reason: 'لم تُمسح محليًا');

      await b.client.autoSync();

      expect(
        await AuthService(master).hasAnyUser(),
        isTrue,
        reason: 'حُذف حساب المدير على جهاز الإدارة بسبب إعادة تعيين في فرع',
      );
      expect(await AuthService(master).needsBootstrap(), isFalse,
          reason: 'عادت شاشة تهيئة حساب المدير على جهاز الإدارة');
    });

    test('وتعود الحسابات إلى الفرع في أول مزامنة بعدها', () async {
      await AuthService(master).createAdmin(username: 'admin', password: 'Test@12345');
      final b = await bond();
      await b.server.stopReceiving();
      await b.server.startReceiving(trustedOnly: true);
      await b.client.autoSync();

      await AuthService(branch).localReset();
      await b.client.autoSync();

      // بلا تصفير علامة السحب يظن الجهاز أنه استلمها فلا يطلبها مرة أخرى.
      final res = await AuthService(branch).login('admin', 'Test@12345');
      expect(res.isOk, isTrue, reason: 'لم تعد الحسابات بعد إعادة التعيين: ${res.message}');
    });
  });

  group('انحراف الساعات لا يوقف المزامنة', () {
    test('جهاز ساعته متأخرة ساعة كاملة يُرفض، وبضبط الفرق يُقبل', () async {
      final session = SyncSession.create();
      const hour = 3600 * 1000;

      // جهاز ميدانيّ بلا إنترنت تأخّرت ساعته ساعة: يوقّع بساعته فيُرفض.
      final late = session.signHeaders('GET', '/info', const [], skewMs: -hour);
      expect(
        session.verify(
          method: 'GET',
          path: '/info',
          ts: late[SyncSession.headerTs],
          nonce: late[SyncSession.headerNonce],
          mac: late[SyncSession.headerMac],
          body: const [],
          seenNonces: <String>{},
        ),
        contains('فارق التوقيت'),
      );

      // وبعد أن يقرأ ساعة المستقبِل من الترحيب يوقّع بها فيُقبل.
      final corrected = session.signHeaders('GET', '/info', const [], skewMs: 0);
      expect(
        session.verify(
          method: 'GET',
          path: '/info',
          ts: corrected[SyncSession.headerTs],
          nonce: corrected[SyncSession.headerNonce],
          mac: corrected[SyncSession.headerMac],
          body: const [],
          seenNonces: <String>{},
        ),
        isNull,
      );
    });

    test('الترحيب يعلن ساعة الجهاز فيُقاس عليها الفرق', () async {
      final server = LanSync(master, port: _port, discoveryPort: _discoveryPort);
      await server.startReceiving();
      addTearDown(server.stopReceiving);

      final client = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
      expect(client.clockOffsetFor('127.0.0.1'), 0, reason: 'لم يُسأل بعد');

      await client.hello('127.0.0.1');
      // الساعة نفسها في الاختبار، فالفرق ثوانٍ لا أكثر — المهم أنه قُرئ.
      expect(client.clockOffsetFor('127.0.0.1').abs(), lessThan(5000));
    });

    test('النافذة تبقى ضيّقة بمقياس المستقبِل', () {
      // الضبط يزيح ختم المرسِل إلى ساعة المستقبِل، ولا يوسّع النافذة: طلب
      // قديم بمقياس المستقبِل يُرفض كما كان.
      expect(SyncSession.maxSkew, const Duration(minutes: 5));
    });
  });

  group('الاكتشاف يحمل المعرّف', () {
    test('الجهاز المستقبِل يعلن معرّفه الثابت لا اسمه وحده', () async {
      final server = LanSync(master, port: _port, discoveryPort: _discoveryPort);
      await server.startReceiving();
      addTearDown(server.stopReceiving);

      final client = LanSync(branch, port: _port, discoveryPort: _discoveryPort);
      final card = await client.hello('127.0.0.1');
      expect(card, isNotNull);
      expect(card!.id, await server.deviceId());

      // نداء اكتشاف موجَّه إلى 127.0.0.1 بدل البث العام: البث لا يعود إلى
      // الجهاز نفسه في كل بيئة (جدار ناري، شبكة معزولة)، والمقصود هنا فحص
      // ما يحمله الردّ لا فحص شبكة الاختبار.
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      Map<String, dynamic>? beacon;
      probe.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = probe.receive();
        if (packet == null) return;
        beacon = jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>;
      });
      probe.send(
        utf8.encode('IMDAD-SYNC-WHO'),
        InternetAddress('127.0.0.1'),
        _discoveryPort,
      );
      await _until(() => beacon != null);
      probe.close();

      expect(beacon, isNotNull, reason: 'لم يردّ منفذ الاكتشاف');
      expect(beacon!['id'], card.id);
    });
  });
}
