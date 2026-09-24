import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
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

  test('مفتاح القاعدة يُولَّد بطول ٣٢ بايت وثابت بين القراءتين', () async {
    // مخزن الاعتمادات غير متاح في بيئة الاختبار، فيُتحقق من شكل المفتاح فقط
    // عبر الدالة نفسها إن عملت، وإلا فالاختبار يوثّق سبب التخطي.
    try {
      final first = await DbCipher.loadKey();
      final second = await DbCipher.loadKey();
      expect(first.length, 64, reason: 'المفتاح ٣٢ بايت بصيغة hex');
      expect(second, first, reason: 'لا يُعاد توليد المفتاح فتضيع القاعدة');
    } on MissingPluginException {
      markTestSkipped('مخزن اعتمادات النظام غير متاح خارج التطبيق');
    }
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
}
