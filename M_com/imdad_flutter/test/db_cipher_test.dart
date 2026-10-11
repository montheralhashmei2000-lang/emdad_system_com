import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/db/db_cipher.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:path/path.dart' as p;

/// قاعدة البيانات صارت تُفتح في خيط منفصل مع تهيئة تُرسل إليه: دالة توجّه
/// المكتبة، وأخرى تمرّر المفتاح. إن تعذّر إرسال أيٍّ منهما انهار التطبيق عند
/// الإقلاع على كل المنصات — ولا يظهر ذلك في اختبار يستعمل قاعدة في الذاكرة.
/// هذه الاختبارات تسلك المسار الحقيقي نفسه على ملف على القرص.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('imdad-cipher-'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File dbFile([String name = 'imdad.sqlite']) => File(p.join(dir.path, name));

  test('القاعدة تُفتح في خيط منفصل مع تهيئة المفتاح وتعمل فعلًا', () async {
    final key = 'a' * 64;
    final file = dbFile();

    final db = AppDatabase.forTesting(NativeDatabase.createInBackground(
      file,
      isolateSetup: DbCipher.setupIsolate,
      setup: (raw) => DbCipher.applyKey(raw, key),
    ));
    addTearDown(db.close);

    // كتابة وقراءة حقيقيتان: لو سقطت التهيئة في الخيط لفشل هذا السطر.
    final id = await CatalogRepo(db).saveItem(
      code: '1001',
      name: 'أرز أبيض',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    final items = await CatalogRepo(db).items();

    expect(items.single.id, id);
    expect(file.existsSync(), isTrue);
  });

  group('مفتاح القاعدة', () {
    // مخزن في الذاكرة بدل إضافة النظام (غير متاحة خارج التطبيق) فيعمل الاختبار في كل بيئة.
    test('يُولَّد بطول ٣٢ بايت hex ويُحفظ، وثابت بين القراءتين', () async {
      final store = _MemoryKeyStore();
      final first = await DbCipher.loadKey(store: store);
      final second = await DbCipher.loadKey(store: store);

      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')), reason: 'المفتاح ٣٢ بايت بصيغة hex');
      expect(second, first, reason: 'لا يُعاد توليد المفتاح فتضيع القاعدة');
      expect(store.writes, 1, reason: 'يُكتب مرة واحدة فقط');
    });

    test('مفتاح محفوظ سلفًا يُعاد كما هو ولا يُكتب فوقه', () async {
      final existing = 'ab' * 32;
      final store = _MemoryKeyStore({'imdad.db.key': existing});

      expect(await DbCipher.loadKey(store: store), existing);
      expect(store.writes, 0);
    });

    test('قيمة تالفة لا يُكتب فوقها: خطأ صريح بدل توليد صامت', () async {
      for (final bad in ['abc', 'z' * 64, 'a' * 63, 'a' * 65]) {
        final store = _MemoryKeyStore({'imdad.db.key': bad});
        await expectLater(DbCipher.loadKey(store: store), throwsA(isA<StateError>()), reason: bad);
        expect(store.writes, 0, reason: 'المفتاح التالف يبقى كما هو: $bad');
      }
    });

    test('قيمة فارغة تُعامل كغياب فيُولَّد مفتاح', () async {
      final store = _MemoryKeyStore({'imdad.db.key': ''});
      expect(await DbCipher.loadKey(store: store), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.writes, 1);
    });

    test('جهازان يولّدان مفتاحين مختلفين', () async {
      final a = await DbCipher.loadKey(store: _MemoryKeyStore());
      final b = await DbCipher.loadKey(store: _MemoryKeyStore());
      expect(a, isNot(b));
    });
  });

  group('ترحيل قاعدة غير مشفّرة', () {
    test('ملف SQLite عادي يُتعرَّف عليه بترويسته', () async {
      final file = dbFile('plain.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();

      final head = String.fromCharCodes(file.readAsBytesSync().sublist(0, 15));
      expect(head, 'SQLite format 3');
    });

    test('فحص الترويسة لا يترك الملف مقفولًا', () async {
      // مقبض مفتوح على ويندوز يمنع إعادة التسمية بالخطأ ٣٢، فيسقط الترحيل
      // **بعد** نجاح التصدير — وهو ما حدث فعلًا عند أول تشغيل حقيقي.
      final file = dbFile('plain.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();

      await DbCipher.migratePlainFile(file, 'd' * 64);

      // لو بقي المقبض مفتوحًا لرمى هذا السطر PathAccessException.
      final moved = File('${file.path}.moved');
      file.renameSync(moved.path);
      expect(moved.existsSync(), isTrue);
    });

    test('ملف غير موجود لا يُرحَّل ولا يرمي استثناء', () async {
      final moved = await DbCipher.migratePlainFile(dbFile('none.sqlite'), 'b' * 64);
      expect(moved, isFalse);
    });

    test('بلا SQLCipher لا يجري ترحيل ولا يُمسّ الملف الأصلي', () async {
      final file = dbFile('plain.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await CatalogRepo(db).saveItem(
        code: '1',
        name: 'صنف',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await db.close();
      final sizeBefore = file.lengthSync();

      final moved = await DbCipher.migratePlainFile(file, 'c' * 64);

      // في بيئة الاختبار المكتبة ليست SQLCipher، فالسلوك الصحيح: لا ترحيل
      // ولا حذف ولا إعادة تسمية — البيانات أهم من إتمام العملية.
      expect(moved, isFalse);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), sizeBefore);
      expect(File('${file.path}.plain.bak').existsSync(), isFalse);
    });
  });

  group('تنظيف النسخ غير المشفّرة القديمة', () {
    test('لا تُحذف إن لم تثبت سلامة القاعدة المشفّرة (قد تكون النسخة الوحيدة)', () async {
      final file = dbFile('imdad.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close(); // قاعدة عادية غير مشفّرة
      final bak = File('${file.path}${DbCipher.plainBackupSuffix}')..writeAsStringSync('old');

      expect(DbCipher.removeStalePlainBackups(file, 'e' * 64), isEmpty);
      expect(bak.existsSync(), isTrue);
    });

    test('بلا ملف قاعدة أو بلا نسخ قديمة لا يحدث شيء ولا استثناء', () {
      expect(DbCipher.removeStalePlainBackups(dbFile('none.sqlite'), 'e' * 64), isEmpty);
      final file = dbFile('imdad.sqlite')..writeAsStringSync('x');
      expect(DbCipher.removeStalePlainBackups(file, 'e' * 64), isEmpty);
    });
  });

  group('H-2: مفتاحٌ غائب والقاعدة مشفّرة لا يُستبدل بمفتاحٍ جديد', () {
    test('قاعدةٌ مشفّرة موجودة ومفتاحها غائب ⇒ DbKeyMissing ولا يُكتب مفتاح', () async {
      final file = dbFile()..writeAsBytesSync(List.generate(4096, (i) => (i * 37) % 256));
      final store = _MemoryKeyStore();
      await expectLater(DbCipher.loadKey(store: store, dbFile: file), throwsA(isA<DbKeyMissing>()));
      expect(store.writes, 0, reason: 'وُلّد مفتاحٌ جديد يقفل القاعدة القائمة للأبد');
    });

    test('مخزنٌ لا يُقرأ ⇒ DbKeyMissing (لا يُولَّد ولا يُمسح شيء)', () async {
      final store = _BrokenKeyStore();
      final e = await DbCipher.loadKey(store: store, dbFile: dbFile()).then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<DbKeyMissing>());
      expect((e as DbKeyMissing).unreadable, isTrue);
      expect(store.writes, 0);
    });

    test('بلا قاعدة (تثبيتٌ جديد) أو بقاعدةٍ صريحة قديمة يُولَّد المفتاح كما كان', () async {
      expect(await DbCipher.loadKey(store: _MemoryKeyStore(), dbFile: dbFile('fresh.sqlite')), hasLength(64));
      final plain = dbFile('plain.sqlite')..writeAsStringSync('SQLite format 3\u0000 legacy');
      expect(await DbCipher.loadKey(store: _MemoryKeyStore(), dbFile: plain), hasLength(64));
    });

    test('بدء قاعدة جديدة يُنحّي القديمة ولا يحذفها', () {
      final file = dbFile()..writeAsStringSync('old');
      File('${file.path}-wal').writeAsStringSync('wal');
      final aside = DbCipher.setAsideLocked(file);
      expect(file.existsSync(), isFalse);
      expect(aside.readAsStringSync(), 'old');
      expect(File('${aside.path}-wal').existsSync(), isTrue);
    });

    test('المفتاح المستردّ يُحفظ ويُقرأ', () async {
      final store = _MemoryKeyStore();
      await DbCipher.storeKey('AB' * 32, store: store);
      expect(await DbCipher.loadKey(store: store), 'ab' * 32);
      expect(() => DbCipher.storeKey('xyz', store: store), throwsArgumentError);
    });
  });

}

class _MemoryKeyStore implements KeyStore {
  _MemoryKeyStore([Map<String, String>? initial]) : _data = {...?initial};

  final Map<String, String> _data;
  int writes = 0;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// مخزنٌ يرمي عند القراءة — كمخزن أسرارٍ تعطّل فكّه بعد تحديث نظام.
class _BrokenKeyStore implements KeyStore {
  int writes = 0;

  @override
  Future<String?> read(String key) async => throw StateError('BadPaddingException');

  @override
  Future<void> write(String key, String value) async => writes++;

  @override
  Future<void> delete(String key) async {}
}
