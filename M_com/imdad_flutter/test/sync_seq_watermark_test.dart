import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:imdad/data/sync/sync_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// البند C-1 في تدقيق 2026-10-10: علامة الماء كانت أكبرَ ختمٍ زمني في جدول
/// العلامات، وهو خليطٌ من ساعات كل الأجهزة (الدمج يثبّت ختم المرسِل). فسقطت
/// سجلاتٌ من المزامنة التفاضلية بصمت ونهائيًّا في حالتين واقعيتين:
///
/// • **العبور عبر وسيط**: فرعٌ كتب سجلًّا، فوصل الإدارة متأخرًا بختمه القديم،
///   وقد تجاوزت علامةُ فرعٍ آخر ذلك الختمَ — فلا يطلبه أبدًا.
/// • **ساعةٌ متقدّمة**: الإدارة متقدّمة دقائق، فترتفع علامة دفع الفرع فوق
///   ختوم تعديلاته هو — فلا تُرسل أبدًا.
///
/// والإصلاح رقم تسلسلٍ محليٌّ لكل جهاز (`SyncMarks.seq`) تُبنى عليه التفاضلية.

const int _port = 8841;
const int _discoveryPort = 8842;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase master;
  late AppDatabase branch1;
  late AppDatabase branch2;
  late String ownerPub;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ownerPub = ESign.generateKeyPair().publicB64;
    master = AppDatabase.forTesting(NativeDatabase.memory());
    branch1 = AppDatabase.forTesting(NativeDatabase.memory());
    branch2 = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await master.close();
    await branch1.close();
    await branch2.close();
  });

  Future<String> item(AppDatabase db, String code) => CatalogRepo(db).saveItem(
        code: code,
        name: 'صنف $code',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

  Future<Set<String>> codes(AppDatabase db) async =>
      {for (final i in await CatalogRepo(db).items()) i.code};

  /// يغيّر ختم علامة سجلٍّ (ساعة كاتبه) دون أن يمسّ رقم تسلسلها.
  Future<void> stampAt(AppDatabase db, String id, int ms) => db.customStatement(
        "UPDATE ${SyncMarks.table} SET updated_at = ? WHERE entity = 'items' AND row_id = ?",
        [ms, id],
      );

  /// الإدارة مستقبِلةٌ موثوقة، والفرعان مقترنان بها اقترانًا دائمًا.
  Future<({LanSync b1, LanSync b2})> hub() async {
    final server = LanSync(master, port: _port, discoveryPort: _discoveryPort, ownerPublicKey: ownerPub);
    await server.startReceiving();
    addTearDown(server.stopReceiving);
    final b1 = LanSync(branch1, port: _port, discoveryPort: _discoveryPort, ownerPublicKey: ownerPub);
    final b2 = LanSync(branch2, port: _port, discoveryPort: _discoveryPort, ownerPublicKey: ownerPub);
    for (final c in [b1, b2]) {
      final paired = await c.pair('127.0.0.1', server.session!.code, port: _port);
      expect(paired.ok, isTrue, reason: paired.message);
      expect(await c.trust(paired.peer!), isNotNull);
    }
    await server.stopReceiving();
    await server.startReceiving(trustedOnly: true);
    return (b1: b1, b2: b2);
  }

  group('المزامنة التفاضلية برقم التسلسل', () {
    test('سجلٌّ يعبر الإدارة بختمٍ قديم يصل الفرع الآخر', () async {
      final h = await hub();
      final now = DateTime.now().millisecondsSinceEpoch;

      // الفرع الأول كتب سجلًّا قبل عشر دقائق ولم يزامن بعد.
      final late = await item(branch1, 'R');
      await stampAt(branch1, late, now - 10 * 60 * 1000);
      // والإدارة كتبت بعده، فزامن الفرع الثاني: علامته الآن فوق ختم R.
      await item(master, 'M');
      expect((await h.b2.autoSync()).ok, isTrue);
      expect(await codes(branch2), contains('M'));

      // يصل R الإدارةَ بختمه القديم، ثم يزامن الفرع الثاني.
      expect((await h.b1.autoSync()).ok, isTrue);
      expect(await codes(master), contains('R'));
      expect((await h.b2.autoSync()).ok, isTrue);

      expect(await codes(branch2), contains('R'),
          reason: 'سقط سجلٌّ عبر الإدارة بختمٍ أقدم من علامة الفرع الثاني');
    });

    test('ساعة الإدارة المتقدّمة لا تحجب تعديلات الفرع', () async {
      final h = await hub();
      final now = DateTime.now().millisecondsSinceEpoch;

      final x = await item(master, 'X');
      await stampAt(master, x, now + 10 * 60 * 1000); // الإدارة متقدّمة عشر دقائق
      expect((await h.b1.autoSync()).ok, isTrue);
      expect(await codes(branch1), contains('X'));

      // الفرع يكتب بساعته الصحيحة — أقدم من ختم X المستورد.
      await item(branch1, 'Y');
      expect((await h.b1.autoSync()).ok, isTrue);

      expect(await codes(master), contains('Y'),
          reason: 'لم يُرسَل تعديل الفرع: علامة الدفع ارتفعت فوقه بساعة الإدارة');
    });

    test('السجل لا يُتقاذف بين الجهازين في كل دورة', () async {
      final h = await hub();
      await item(master, 'A');
      await item(branch1, 'B');
      for (var i = 0; i < 3; i++) {
        expect((await h.b1.autoSync()).ok, isTrue);
      }
      final peer = (await SyncTrust(branch1).peers()).single;
      expect(peer.pulledSeq, greaterThan(0));
      expect(peer.pushedSeq, greaterThan(0));

      final again = await SyncMarks(master).changedSinceSeq(peer.pulledSeq);
      expect(again.where((m) => m.entity == 'items'), isEmpty,
          reason: 'الإدارة تعيد إرسال أصنافٍ لم تتغيّر');
      final back = await SyncMarks(branch1).changedSinceSeq(peer.pushedSeq);
      expect(back.where((m) => m.entity == 'items'), isEmpty,
          reason: 'الفرع يعيد إرسال أصنافٍ لم تتغيّر');
    });

    test('الحذف ينتقل برقم التسلسل كما ينتقل التعديل', () async {
      final h = await hub();
      final doomed = await item(master, 'D');
      expect((await h.b1.autoSync()).ok, isTrue);
      expect(await codes(branch1), contains('D'));

      await CatalogRepo(master).deleteItem(doomed);
      expect((await h.b1.autoSync()).ok, isTrue);
      expect(await codes(branch1), isNot(contains('D')));
    });
  });

  group('العدّاد والعلامات', () {
    test('كل كتابة تأخذ رقمًا أكبر، والتصدير التفاضلي يحمل ما بعده وحده', () async {
      await item(master, 'P1');
      final before = await SyncMarks(master).maxSeq();
      await item(master, 'P2');
      expect(await SyncMarks(master).maxSeq(), greaterThan(before));

      final delta = await DataExporter(master).toMap(sinceSeq: before);
      expect([for (final i in delta['items'] as List) i['code']], ['P2']);
      expect((delta['meta'] as Map)['maxSeq'], await SyncMarks(master).maxSeq());
      // رقم التسلسل لا يغادر الجهاز.
      for (final m in delta['syncMarks'] as List) {
        expect((m as Map).containsKey('seq'), isFalse);
      }
    });

    test('العدّاد لا ينقص بتقليم الشواهد', () async {
      final id = await item(master, 'T');
      await CatalogRepo(master).deleteItem(id);
      final high = await SyncMarks(master).maxSeq();
      await SyncMarks(master).pruneTombstones(now: DateTime.now().add(const Duration(days: 365)));
      await item(master, 'T2');
      expect(await SyncMarks(master).maxSeq(), greaterThan(high));
    });

    test('عدّاد قرينٍ عاد إلى الوراء يصفّر العلامة فتكون الدورة القادمة كاملة', () {
      expect(LanSync.nextWatermark(50, 80), 80);
      expect(LanSync.nextWatermark(50, 50), 50);
      expect(LanSync.nextWatermark(50, 20), 0);
    });
  });

  group('الترقية من قاعدةٍ أقدم', () {
    test('جدول علامات بلا عمود seq يُرقّى ويبدأ العدّاد من أكبر رقم', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute('CREATE TABLE sync_marks (entity TEXT NOT NULL, row_id TEXT NOT NULL, '
            'updated_at INTEGER NOT NULL, deleted_at INTEGER, PRIMARY KEY (entity, row_id))');
        raw.execute("INSERT INTO sync_marks VALUES ('items', 'old-1', 5, NULL)");
      }));
      addTearDown(db.close);

      final marks = await SyncMarks(db).snapshot();
      expect(marks['items/old-1']!.seq, 0);
      final id = await item(db, 'NEW');
      final fresh = (await SyncMarks(db).snapshot())['items/$id']!;
      expect(fresh.seq, greaterThan(0));
    });

    test('محفِّزٌ من إصدارٍ أقدم يُستبدل عند الفتح', () async {
      await item(master, 'warm'); // يفتح القاعدة
      await master.customStatement('DROP TRIGGER tg_items_insert_mark');
      await master.customStatement('''
        CREATE TRIGGER tg_items_insert_mark AFTER INSERT ON items BEGIN
          INSERT INTO sync_marks (entity, row_id, updated_at, deleted_at)
          VALUES ('items', NEW.id, 1, NULL)
          ON CONFLICT (entity, row_id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = NULL;
        END
      ''');
      await SyncMarks.install(master);

      final sql = (await master
              .customSelect("SELECT sql FROM sqlite_master WHERE name = 'tg_items_insert_mark'")
              .getSingle())
          .data['sql'] as String;
      expect(sql, contains(SyncMarks.seqTable));
      final before = await SyncMarks(master).maxSeq();
      final id = await item(master, 'after');
      expect((await SyncMarks(master).snapshot())['items/$id']!.seq, greaterThan(before));
    });

    test('علامات الماء الزمنية القديمة لا تُستعمل: الدورة الأولى بعد الترقية كاملة', () async {
      await SyncTrust(branch1).remember(TrustedPeer(
        deviceId: 'MASTER01',
        key: Uint8List.fromList(List.generate(32, (i) => i)),
        pulledUpTo: 9999999999999,
        pushedUpTo: 9999999999999,
      ));
      final peer = (await SyncTrust(branch1).peers()).single;
      expect(peer.pulledSeq, 0);
      expect(peer.pushedSeq, 0);
    });
  });
}
