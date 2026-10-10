import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/barcode_labels.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/domain/item_barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('صيغة الباركود النظامي', () {
    test('١٢ رقمًا: السنة + يوم-ساعة-دقيقة + تسلسل', () {
      final h = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 30), const []);
      final first = h.take();
      expect(first, '202610143001');
      expect(first.length, ItemBarcode.length);
      expect(h.take(), '202610143002');
    });

    test('السنة من الساعة لا ثابتة', () {
      final g = ItemBarcode.startingAt(DateTime(2027, 10, 10, 14, 30), const []);
      expect(g.take(), '202710143001');
    });

    test('يبدأ بعد أكبر تسلسل مستعمل في الدقيقة', () {
      final g = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 30), const [1, 7, 3]);
      expect(g.take(), '202610143008');
    });

    test('بعد 99 ينتقل إلى الدقيقة التالية', () {
      final g = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 30), const [98]);
      expect(g.take(), '202610143099');
      expect(g.take(), '202610143101');
      final full = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 59), const [99]);
      expect(full.take(), '202610150001');
    });

    test('seqOf يتعرّف على الصيغة ويتجاهل غيرها', () {
      expect(ItemBarcode.seqOf('202610143042', '2026101430'), 42);
      expect(ItemBarcode.seqOf('104123456789', '2026101430'), isNull);
      expect(ItemBarcode.seqOf('20261014304', '2026101430'), isNull);
    });

    test('يتخطى المستعمل ويستسلم بعد 10 محاولات', () async {
      final g = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 30), const []);
      expect(await g.nextFree((bc) async => bc.endsWith('01') || bc.endsWith('02')), '202610143003');
      final all = ItemBarcode.startingAt(DateTime(2026, 10, 10, 14, 30), const []);
      var tries = 0;
      await expectLater(all.nextFree((_) async {
        tries++;
        return true;
      }), throwsStateError);
      expect(tries, ItemBarcode.maxAttempts);
    });
  });

  group('توليد من القاعدة', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('لا يكرر باركودًا محفوظًا، ولا يمسّ القديم', () async {
      final repo = CatalogRepo(db);
      final now = DateTime(2026, 10, 10, 14, 30);
      final a = await repo.saveItem(code: 'A', name: 'أ', barcode: '202610143001');
      final b = await repo.saveItem(code: 'B', name: 'ب', barcode: '104000000001');
      final gen = await repo.barcodeGenerator(now);
      final bc = await repo.newItemBarcode(generator: gen);
      expect(bc, '202610143002');
      expect((await repo.itemById(a))!.barcode, '202610143001');
      expect((await repo.itemById(b))!.barcode, '104000000001');
      expect(await repo.barcodeTaken('202610143001'), isTrue);
      expect(await repo.barcodeTaken(bc), isFalse);
    });
  });

  group('حجم ملصق الباركود', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('الافتراضي 35×25 ويُحفظ محليًا', () async {
      expect(await LabelSize.load(), LabelSize.defaults);
      await LabelSize.save(const LabelSize(60, 40));
      expect(await LabelSize.load(), const LabelSize(60, 40));
      await LabelSize.save(const LabelSize(42.5, 28));
      final s = await LabelSize.load();
      expect(s, const LabelSize(42.5, 28));
      expect(s.isPreset, isFalse);
    });

    test('قيمة تالفة أو خارج الحدود ⇒ الافتراضي', () async {
      SharedPreferences.setMockInitialValues({LabelSize.prefsKey: '5x900'});
      expect(await LabelSize.load(), LabelSize.defaults);
      SharedPreferences.setMockInitialValues({LabelSize.prefsKey: 'abc'});
      expect(await LabelSize.load(), LabelSize.defaults);
    });

    test('PDF: صفحة لكل ملصق بحجمه', () async {
      const labels = [
        (name: 'أرز', code: 'A1', barcode: '202610143001'),
        (name: 'سكر', code: 'A2', barcode: '202610143002'),
        (name: 'شاي', code: 'A3', barcode: '202610143003'),
      ];
      final bytes = await BarcodeLabelsSheet.buildPdf(labels, size: const LabelSize(35, 25));
      final text = latin1.decode(bytes);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 3);
      const w = 35 * PdfPageFormat.mm, h = 25 * PdfPageFormat.mm;
      final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)').firstMatch(text)!;
      expect(double.parse(box.group(1)!), closeTo(w, 0.1));
      expect(double.parse(box.group(2)!), closeTo(h, 0.1));
    });
  });
}
