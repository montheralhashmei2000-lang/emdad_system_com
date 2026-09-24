import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/backup_crypto.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/web_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:path/path.dart' as p;

/// ملف النسخة الاحتياطية كان JSON مقروءًا بالكامل رغم أن قاعدة البيانات مشفّرة
/// — باب خلفي مفتوح خلف باب أمامي محكم. هذه الاختبارات تحرس إغلاقه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('imdad-backup-');
    await CatalogRepo(db).saveItem(
      code: '1001',
      name: 'أرز أبيض',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
  });

  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String path(String name) => p.join(dir.path, name);

  group('تشفير الملف', () {
    test('ما يُشفَّر يُفكّ بالكلمة نفسها', () {
      final sealed = BackupCrypto.seal('{"a":1}', 'سر قوي');
      expect(BackupCrypto.open(sealed, 'سر قوي'), '{"a":1}');
    });

    test('كلمة مرور خاطئة ترمي رسالة صريحة لا بيانات مشوّهة', () {
      final sealed = BackupCrypto.seal('{"a":1}', 'الصحيحة');
      expect(
        () => BackupCrypto.open(sealed, 'الخاطئة'),
        throwsA(isA<BackupError>().having((e) => e.message, 'رسالة', contains('غير صحيحة'))),
      );
    });

    test('العبث ببايت واحد يُكتشف', () {
      final sealed = BackupCrypto.seal('{"a":1}', 'سر')..[40] ^= 0xFF;
      expect(() => BackupCrypto.open(sealed, 'سر'), throwsA(isA<BackupError>()));
    });

    test('التشفير مرتين يعطي ملفين مختلفين (ملح ومتجه جديدان)', () {
      final a = BackupCrypto.seal('{"a":1}', 'سر');
      final b = BackupCrypto.seal('{"a":1}', 'سر');
      expect(a, isNot(b));
      expect(BackupCrypto.open(b, 'سر'), '{"a":1}');
    });

    test('كلمة مرور فارغة ترفض التشفير بدل إنتاج ملف بلا حماية', () {
      expect(() => BackupCrypto.seal('{}', ''), throwsA(isA<BackupError>()));
    });

    test('يميّز المشفَّر عن JSON العادي', () {
      expect(BackupCrypto.isEncrypted(BackupCrypto.seal('{}', 'س')), isTrue);
      expect(BackupCrypto.isEncrypted(utf8.encode('{"items":[]}')), isFalse);
      expect(BackupCrypto.isEncrypted(const [1, 2]), isFalse);
    });
  });

  group('التصدير والاستعادة', () {
    test('النسخة المشفّرة لا تكشف أي اسم في الملف الخام', () async {
      final file = path('b.imdbk');
      final res = await DataExporter(db).writeToFile(file, password: 'سر قوي');

      expect(res.encrypted, isTrue);
      final raw = File(file).readAsBytesSync();
      // البحث عن اسم الصنف في البايتات الخام — يجب ألا يوجد.
      expect(utf8.decode(raw, allowMalformed: true).contains('أرز أبيض'), isFalse);
    });

    test('النسخة غير المشفّرة تبقى مقروءة كما كانت (توافق)', () async {
      final file = path('b.json');
      final res = await DataExporter(db).writeToFile(file);

      expect(res.encrypted, isFalse);
      expect(File(file).readAsStringSync().contains('أرز أبيض'), isTrue);
    });

    test('رحلة كاملة: تصدير مشفّر ثم استعادة في قاعدة أخرى', () async {
      final file = path('b.imdbk');
      await DataExporter(db).writeToFile(file, password: 'سر قوي');

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final result = await WebImporter(other).importFile(File(file), password: 'سر قوي');

      expect(result.total, greaterThan(0));
      expect((await CatalogRepo(other).items()).single.name, 'أرز أبيض');
    });

    test('الاستعادة بلا كلمة مرور ترفض ولا تستورد نصف ملف', () async {
      final file = path('b.imdbk');
      await DataExporter(db).writeToFile(file, password: 'سر قوي');

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);

      await expectLater(
        WebImporter(other).importFile(File(file)),
        throwsA(isA<BackupError>()),
      );
      expect(await CatalogRepo(other).items(), isEmpty, reason: 'لا يُستورد شيء عند الرفض');
    });

    test('الملف المشفَّر يُكتشف بالبادئة لا بالامتداد', () async {
      // اسم مضلِّل بامتداد json لكنه مشفَّر فعلًا.
      final file = path('misleading.json');
      await DataExporter(db).writeToFile(file, password: 'سر');

      expect(await WebImporter.isEncryptedFile(File(file)), isTrue);
    });
  });
}
