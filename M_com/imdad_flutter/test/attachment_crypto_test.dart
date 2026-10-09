import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/files/attachment_crypto.dart';
import 'package:imdad/data/repos/archive_repo.dart';
import 'package:imdad/data/repos/cable_repo.dart';
import 'package:imdad/data/repos/finance_files.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';
import 'package:path/path.dart' as p;

/// تشفير المرفقات على القرص.
///
/// القاعدة مشفَّرة (SQLCipher) وكانت مرفقاتها تُكتب صريحةً بجوارها: الأرشيف،
/// والبرقيات **المصنَّفة**، ومرفقات العهد. فمن نسخ مجلد البيانات قرأها بعارضٍ
/// عادي. والشرط المرافق: الملفات الصريحة القديمة تبقى مقروءة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('imdad_attach');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    AttachmentCrypto.debugKeyHex = 'ab' * 32;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    AttachmentCrypto.debugKeyHex = null;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // يبقى مقفلًا أحيانًا على ويندوز.
    }
  });

  final plain = Uint8List.fromList(utf8.encode('برقية مصنَّفة: تحرّك السرية الثالثة'));

  File at(String name) => File(p.join(dir.path, name));

  group('الصيغة', () {
    test('الملف المكتوب لا يحمل النص الصريح ويبدأ ببادئة معلومة', () async {
      final f = at('a.bin');
      await AttachmentCrypto.write(f, plain);
      final raw = await f.readAsBytes();

      expect(AttachmentCrypto.isEncrypted(raw), isTrue);
      expect(raw.sublist(0, 6), AttachmentCrypto.magic);
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains('مصنَّفة')),
          reason: 'النص الصريح باقٍ في الملف');
      expect(await AttachmentCrypto.read(f), plain);
    });

    test('كل كتابةٍ بمتجه تهيئةٍ جديد (نصٌّ واحد ⇒ ملفان مختلفان)', () async {
      await AttachmentCrypto.write(at('x.bin'), plain);
      await AttachmentCrypto.write(at('y.bin'), plain);
      expect(await at('x.bin').readAsBytes(), isNot(await at('y.bin').readAsBytes()));
    });

    test('ملفٌّ صريحٌ قديم يُقرأ كما هو (توافق خلفي)', () async {
      final f = at('old.pdf');
      await f.writeAsBytes(plain, flush: true);
      expect(AttachmentCrypto.isEncrypted(await f.readAsBytes()), isFalse);
      expect(await AttachmentCrypto.read(f), plain);
    });

    test('ملفٌّ فارغ أو قصير يُعدّ صريحًا ولا يُسقط القراءة', () async {
      final f = at('empty.bin');
      await f.writeAsBytes(const [], flush: true);
      expect(await AttachmentCrypto.read(f), isEmpty);
    });

    test('العبث بالبايتات يُكشف ولا يُعاد محتوًى مغلوط', () async {
      final f = at('t.bin');
      await AttachmentCrypto.write(f, plain);
      final raw = await f.readAsBytes();
      raw[raw.length - 1] ^= 0xff;
      await f.writeAsBytes(raw, flush: true);
      await expectLater(AttachmentCrypto.read(f), throwsA(isA<AttachmentCryptoError>()));
    });

    test('مفتاحٌ آخر (ملفٌّ من جهازٍ غير هذا) ⇒ خطأٌ صريح لا بايتات مشوّهة', () async {
      final f = at('other.bin');
      await AttachmentCrypto.write(f, plain);

      AttachmentCrypto.debugKeyHex = 'cd' * 32;
      await expectLater(AttachmentCrypto.read(f), throwsA(isA<AttachmentCryptoError>()));
    });

    test('المفتاح مشتقٌّ (HKDF) لا هو مفتاح القاعدة نفسه', () async {
      final f = at('k.bin');
      await AttachmentCrypto.write(f, plain);
      final raw = await f.readAsBytes();

      // فكُّ الحمولة بمفتاح القاعدة مباشرةً يجب أن يفشل: لو كان هو المستعمل
      // لنجح. (مفتاح القاعدة في هذا الاختبار `ab` مكرَّرة ٣٢ مرة.)
      final dbKey = Uint8List.fromList(List.filled(32, 0xab));
      final iv = Uint8List.fromList(raw.sublist(6, 18));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(dbKey), 128, iv, Uint8List(0)));
      expect(
        () => cipher.process(Uint8List.fromList(raw.sublist(18))),
        throwsA(isA<InvalidCipherTextException>()),
        reason: 'المرفق مشفَّر بمفتاح القاعدة نفسه لا بمشتقٍّ منه',
      );
    });
  });

  group('المستودعات', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('الأرشيف: الملف المؤرشف مشفَّر، ويُقرأ صريحًا، وبصمته تُطابق', () async {
      final src = at('src.pdf')..writeAsBytesSync(plain);
      final repo = ArchiveRepo(db);
      final f = await repo.archive(sourcePath: src.path, title: 'سند');

      final stored = File(f.storedPath);
      expect(AttachmentCrypto.isEncrypted(await stored.readAsBytes()), isTrue);
      expect(await repo.bytesOf(f), plain);
      expect(f.sha256, sha256.convert(plain).toString(), reason: 'البصمة على الأصل الصريح');
      expect(await repo.verifyIntegrity(f), isTrue);
    });

    test('الأرشيف: ملفٌّ صريحٌ أُرشف قبل التشفير يُقرأ ويُتحقَّق منه', () async {
      final repo = ArchiveRepo(db);
      final legacy = File(p.join((await repo.storageDir()).path, 'old.pdf'));
      await legacy.writeAsBytes(plain, flush: true);
      await db.into(db.archiveFiles).insert(ArchiveFilesCompanion.insert(
            id: 'ar-old',
            title: 'قديم',
            fileName: 'old.pdf',
            storedPath: legacy.path,
            sizeBytes: plain.length,
            sha256: Value(sha256.convert(plain).toString()),
          ));
      final f = (await repo.list()).single;

      expect(await repo.bytesOf(f), plain);
      expect(await repo.verifyIntegrity(f), isTrue, reason: 'الصريح القديم فشل تحققه');
    });

    test('الأرشيف: العبث بملفٍ مشفَّر يُسقط فحص النزاهة ولا يرمي', () async {
      final src = at('s2.pdf')..writeAsBytesSync(plain);
      final repo = ArchiveRepo(db);
      final f = await repo.archive(sourcePath: src.path, title: 'سند');
      final stored = File(f.storedPath);
      final raw = await stored.readAsBytes();
      raw[raw.length - 2] ^= 0x01;
      await stored.writeAsBytes(raw, flush: true);

      expect(await repo.verifyIntegrity(f), isFalse);
    });

    test('البرقيات: المرفق مشفَّر، ويُقرأ صريحًا، وتحققه يمرّ', () async {
      final src = at('cable.pdf')..writeAsBytesSync(plain);
      final repo = CableRepo(db);
      await repo.insert(CablesCompanion.insert(id: 'c1', subject: 'برقية مصنَّفة'));
      final withFile = await repo.attachPdf((await repo.byId('c1'))!, sourcePath: src.path);

      expect(AttachmentCrypto.isEncrypted(await File(withFile.attachPath).readAsBytes()), isTrue);
      expect(await repo.attachmentBytes(withFile), plain);
      expect(await repo.verifyAttachment(withFile), isTrue);
    });

    test('المالية: المرفق مشفَّر، وحجمه وبصمته للأصل الصريح', () async {
      final src = at('inv.pdf')..writeAsBytesSync(plain);
      final a = await FinanceFiles.save(src.path, prefix: 'cus');

      expect(AttachmentCrypto.isEncrypted(await File(a.path).readAsBytes()), isTrue);
      expect(await FinanceFiles.bytesOf(a), plain);
      expect(a.size, plain.length);
      expect(a.sha256, sha256.convert(plain).toString());
    });
  });
}

