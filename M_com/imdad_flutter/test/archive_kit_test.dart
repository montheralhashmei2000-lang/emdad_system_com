import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/cable_print.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/archive_auto.dart';
import 'package:imdad/data/repos/archive_repo.dart';
import 'package:imdad/data/repos/cable_repo.dart';

/// الأرشفة (يدويّة وتلقائية عند الطباعة) ونموذج البرقية المطبوع.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('archive_kit_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    await db.close();
    await tmp.delete(recursive: true);
  });

  final pdf = List<int>.generate(2048, (i) => i % 251);

  group('الأرشفة التلقائية عند الطباعة', () {
    test('معطّلة افتراضيًّا: لا تُؤرشف شيئًا', () async {
      final ok = await ArchiveAuto(db).onDocumentPrinted(op: 'issue', title: 'سند', docRef: 'ص-1', pdfBytes: pdf);
      expect(ok, isFalse);
      expect(await db.select(db.archiveFiles).get(), isEmpty);
    });

    test('الرئيسي مفعّل دون العملية: لا تُؤرشف (تفعيل مزدوج)', () async {
      final auto = ArchiveAuto(db);
      await auto.save(const ArchiveAutoSettings(enabled: true));
      expect(await auto.onDocumentPrinted(op: 'issue', title: 'سند', pdfBytes: pdf), isFalse);
    });

    test('تُؤرشف نسخة مطابقة بالبايتات والبصمة ثم لا تتكرر عند إعادة الطباعة', () async {
      final auto = ArchiveAuto(db);
      await auto.save(const ArchiveAutoSettings(enabled: true, ops: {'issue': true}));

      expect(await auto.onDocumentPrinted(op: 'issue', title: 'سند صرف', docRef: 'ص-1', pdfBytes: pdf), isTrue);
      var rows = await db.select(db.archiveFiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.source, 'auto');
      expect(rows.single.opType, 'issue');
      expect(rows.single.docRef, 'ص-1');
      expect(await File(rows.single.storedPath).readAsBytes(), pdf);
      expect(await ArchiveRepo(db).verifyIntegrity(rows.single), isTrue);

      // إعادة طباعة السند نفسه تحدّث النسخة ولا تضيف أخرى.
      final pdf2 = [...pdf, 1, 2, 3];
      await auto.onDocumentPrinted(op: 'issue', title: 'سند صرف', docRef: 'ص-1', pdfBytes: pdf2);
      rows = await db.select(db.archiveFiles).get();
      expect(rows, hasLength(1));
      expect(await File(rows.single.storedPath).readAsBytes(), pdf2);

      // عملية أخرى غير مفعّلة لا تُؤرشف.
      expect(await auto.onDocumentPrinted(op: 'receipt', title: 'سند', docRef: 'ص-1', pdfBytes: pdf), isFalse);
    });

    test('نموذج البرقية المطبوع يُؤرشف تلقائيًّا عند تفعيل «البرقيات»', () async {
      await ArchiveAuto(db).save(const ArchiveAutoSettings(enabled: true, ops: {'cable': true}));
      expect(kArchiveOps.map((e) => e.$1), contains('cable'));
      final ok = await ArchiveAuto(db).onDocumentPrinted(
          op: 'cable', title: 'برقية 00001-ص', docRef: '00001-ص', pdfBytes: pdf);
      expect(ok, isTrue);
    });
  });

  group('الأرشفة اليدوية', () {
    test('أرشفة ملف ثم كشف التلاعب بالبصمة', () async {
      final src = File('${tmp.path}/contract.pdf')..writeAsBytesSync(pdf);
      final repo = ArchiveRepo(db);
      final f = await repo.archive(sourcePath: src.path, title: 'عقد', category: 'عقود');
      expect(f.source, isNot('auto'));
      expect(await repo.verifyIntegrity(f), isTrue);

      File(f.storedPath).writeAsBytesSync([...pdf, 9]);
      expect(await repo.verifyIntegrity(f), isFalse, reason: 'تغيّر المحتوى فتتغير البصمة');
    });
  });

  group('البرقيات', () {
    test('الترقيم التلقائي بصيغة النموذج 00024-ص', () async {
      final repo = CableRepo(db);
      expect(await repo.nextCableNo(CableDirection.outgoing), '00001-ص');
      await repo.insert(CablesCompanion.insert(id: 'a', subject: 'x', cableNo: const Value('00023-ص'), direction: const Value('out')));
      expect(await repo.nextCableNo(CableDirection.outgoing), '00024-ص');
      expect(await repo.nextCableNo(CableDirection.incoming), '00001-و', reason: 'ترقيم الواردة مستقل');
    });

    test('جدول المرسَل إليهم يُحفظ ويُقرأ ويُسقط الصفوف الفارغة', () {
      final json = CableRecipient.encode(const [
        CableRecipient(name: 'أحمد', unit: 'شعبة نظم المعلومات', note: 'للعلم'),
        CableRecipient(),
      ]);
      final back = CableRecipient.decode(json);
      expect(back, hasLength(1));
      expect(back.single.unit, 'شعبة نظم المعلومات');
      expect(CableRecipient.decode('ليس json'), isEmpty);
    });

    test('الحقول المتغيرة تُقترح مما سبق كتابته', () async {
      final repo = CableRepo(db);
      await repo.insert(CablesCompanion.insert(
        id: 'a',
        subject: 'x',
        toParty: const Value('قيادة المنطقة'),
        recipientsJson: Value(CableRecipient.encode(const [CableRecipient(unit: 'شعبة الإمداد')])),
      ));
      expect(await repo.suggestions('to'), ['قيادة المنطقة']);
      expect(await repo.suggestions('unit'), ['شعبة الإمداد']);
    });

    test('النموذج المطبوع يولّد PDF صالحًا بكل الحقول', () async {
      final repo = CableRepo(db);
      await repo.insert(CablesCompanion.insert(
        id: 'c1',
        subject: 'رفع تقرير الإمداد',
        direction: const Value('out'),
        cableNo: const Value('00024-ص'),
        cableDate: const Value('2026-10-03'),
        cableTime: const Value('20:55'),
        toParty: const Value('قيادة الفرقة'),
        fromParty: const Value('شعبة الإمداد'),
        ccParty: const Value('الأركان\nالعمليات'),
        classification: const Value('secret'),
        priority: const Value('immediate'),
        body: const Value('إشارة إلى الموضوع أعلاه، تم الرفع إليكم حسب النظام.'),
        recipientsJson: Value(CableRecipient.encode(const [CableRecipient(name: 'س', unit: 'شعبة نظم المعلومات')])),
        editorName: const Value('محمد'),
        editorRank: const Value('رائد'),
      ));
      final bytes = await CablePrint.build(db, (await repo.byId('c1'))!);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
    });
  });
}
