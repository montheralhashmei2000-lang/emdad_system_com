import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/ocr/invoice_models.dart';
import 'package:imdad/data/ocr/invoice_scanner.dart';
import 'package:imdad/data/ocr/invoice_text_parser.dart';
import 'package:imdad/data/ocr/ocr_engine.dart';
import 'package:imdad/data/ocr/ocr_words.dart';
import 'package:imdad/data/migration/custody_sheet_import.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/domain/custody_sheet.dart';
import 'package:imdad/domain/invoice_merge.dart';

/// استيراد مسير العهدة من Excel، ومسح الفواتير (طلب الخدمة وتحليل ردّها)،
/// وتوزيع المسحوب على أماكنه من العقد. لا شبكة: النقل مُحاكى.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('استيراد Excel', () {
    /// يبني xlsx صغيرًا بيدٍ، بخصائص ملفات Excel العربية الواقعية التي ترميها حزمة
    /// excel: تنسيق أرقام مخصص بمعرّف ٤٣ (< ١٦٤)، وتاريخ بتنسيق ١٤، ومعادلة.
    Uint8List workbook() {
      String s(String ref, String v) => '<c r="$ref" t="inlineStr"><is><t>$v</t></is></c>';
      String n(String ref, num v, {int style = 0}) => '<c r="$ref" s="$style"><v>$v</v></c>';
      String f(String ref, String formula) => '<c r="$ref"><f>$formula</f></c>';
      final head1 = '<row r="1">${s('A1', 'التاريخ')}${s('B1', 'مبلغ العهدة')}${s('C1', 'مرتجع')}${s('E1', 'المبلغ المنصرف')}'
          '${s('G1', 'سعر الصرف')}${s('H1', 'الاســــــــم')}${s('I1', 'البيــــــان')}${s('J1', 'الفئة')}${s('K1', 'رقم القيد')}'
          '${s('L1', 'رقم الفاتورة')}${s('M1', 'اسم المحل')}${s('N1', 'ملاحظات')}</row>';
      final head2 = '<row r="2">${s('B2', 'سعودي')}${s('C2', 'سعودي')}${s('D2', 'يمني')}${s('E2', 'سعودي')}${s('F2', 'يمني')}</row>';
      // 46158 = 2026-05-15
      final r3 = '<row r="3">${n('A3', 46157, style: 1)}${n('B3', 30000)}${n('E3', 3905)}${n('G3', 410)}${s('I3', 'أدوات شبكة')}'
          '${s('J3', 'أصول ثابتة')}${n('L3', 47)}${s('M3', 'محلات الوفي')}</row>';
      final r4 = '<row r="4">${n('A4', 46200, style: 1)}${f('E4', 'F4/410')}${n('F4', 135000)}${n('G4', 410)}${s('H4', 'زكريا')}'
          '${s('I4', 'صيانة')}${s('L4', 'سند استلام')}</row>';
      final r5 = '<row r="5">${s('A5', '28/05/2026')}${n('E5', 343)}${s('I5', 'إنترنت')}${s('L5', 'سند استلام')}</row>';
      final r6 = '<row r="6">${s('I6', 'اجمالي العهدة بالريال السعودي')}</row>';
      final r7 = '<row r="7">${s('J7', 'متبقي لكم من العهدة التشغيلية رقم (٢) مبلغ وقدره')}</row>';
      final sheet = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>$head1$head2$r3$r4$r5$r6$r7</sheetData></worksheet>';
      const styles = '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<numFmts count="1"><numFmt numFmtId="43" formatCode="_(* #,##0.00_)"/></numFmts>'
          '<cellXfs count="2"><xf numFmtId="43"/><xf numFmtId="14"/></cellXfs></styleSheet>';
      const wb = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="ورقة1" sheetId="1" r:id="rId1"/></sheets></workbook>';
      const rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>';
      final a = Archive()
        ..addFile(ArchiveFile('xl/workbook.xml', utf8.encode(wb).length, utf8.encode(wb)))
        ..addFile(ArchiveFile('xl/_rels/workbook.xml.rels', utf8.encode(rels).length, utf8.encode(rels)))
        ..addFile(ArchiveFile('xl/styles.xml', utf8.encode(styles).length, utf8.encode(styles)))
        ..addFile(ArchiveFile('xl/worksheets/sheet1.xml', utf8.encode(sheet).length, utf8.encode(sheet)));
      return Uint8List.fromList(ZipEncoder().encode(a)!);
    }

    test('يقرأ الأعمدة بعناوينها ذات المستويين والتطويل، ويتجاوز الإجماليات', () {
      final r = CustodySheetImporter.parse(workbook());
      expect(r.rows, hasLength(3), reason: 'سطر الإجماليات والجملة لا يُعدّان بيانات');
      expect(r.sheetNo, '2', reason: 'من جملة المتبقي، والرقم الهندي يتحول');
      final a = r.rows[0];
      expect(a.date, '2026-05-15');
      expect(a.grantSar, 30000);
      expect(a.spentSar, 3905);
      expect(a.statement, 'أدوات شبكة');
      expect(a.category, 'أصول ثابتة');
      expect(a.invoiceNo, '47');
      expect(a.shop, 'محلات الوفي');
    });

    test('المنصرف اليمني يُقرأ ومعادلة السعودي تُهمل فيُشتق بسعر الصرف', () {
      final b = CustodySheetImporter.parse(workbook()).rows[1];
      expect(b.spentYer, 135000);
      expect(b.spentSar, 0);
      expect(b.person, 'زكريا');
      expect(CustodyRowValues(spentYer: b.spentYer, spentSar: b.spentSar, rate: b.rate).spentInSar, closeTo(329.27, 0.01));
    });

    test('التاريخ النصي dd/mm/yyyy يُقرأ، وتكرار الفاتورة يُكتشف', () {
      final r = CustodySheetImporter.parse(workbook());
      expect(r.rows[2].date, '2026-05-28');
      expect(duplicateInvoiceNos([for (final x in r.rows) x.invoiceNo]), {'سند استلام'});
    });

    test('ملف غير xlsx أو بلا ترويسة المسير يُرفض برسالة عربية', () {
      expect(() => CustodySheetImporter.parse(Uint8List.fromList([1, 2, 3])), throwsA(isA<FormatException>()));
    });
  });

  group('قراءة الفواتير (OCR محلي)', () {
    List<ScannedInvoice> fromHocr(String name) =>
        InvoiceTextParser.parse(wordsToLines(parseHocr(File('test/fixtures/ocr/$name.hocr').readAsStringSync())).join('\n'));

    test('فاتورة عربية: الجدول المقسوم إلى كتل يعود صفوفًا بالترتيب المنطقي', () {
      final inv = fromHocr('invoice_ar').single;
      expect(inv.merchant, 'مؤسسة النور للتجارة');
      expect(inv.invoiceNo, '5821');
      expect(inv.date, '2026-08-12');
      expect(inv.currency, 'sar');
      expect(inv.printedTotal, 1770);
      expect(inv.items, hasLength(4), reason: 'الصف الرابع لم يُقرأ اسمه لكن أرقامه متسقة فيبقى');
      expect(inv.items[0].name, 'أرزبسمتي');
      expect((inv.items[0].unit, inv.items[0].qty, inv.items[0].unitPrice, inv.items[0].lineTotal), ('كيس', 10, 85, 850));
      expect(inv.items[1].name, 'سكر أبيض', reason: 'كلمات الاسم تُقرأ من اليمين');
      expect((inv.items[1].qty, inv.items[1].unitPrice, inv.items[1].lineTotal), (4, 120.5, 482));
      expect(inv.items[2].name, 'زيت طبخ');
      expect(inv.items[3].name, isEmpty);
      expect(inv.items[3].lineTotal, 186);
      // مجموع الأصناف يطابق الإجمالي المطبوع قبل الضريبة؟ 850+482+252+186 = 1770.
      expect(inv.items.fold<double>(0, (s, e) => s + e.lineTotal), 1770);
    });

    test('فاتورة إنجليزية بالريال اليمني', () {
      final inv = fromHocr('invoice_en').single;
      expect(inv.merchant, 'AL-AMAL TRADING CO.');
      expect(inv.invoiceNo, 'INV-2044');
      expect(inv.date, '2026-07-03');
      expect(inv.currency, 'yer');
      expect(inv.printedTotal, 667500);
      expect(inv.items.map((e) => e.name), ['Flour 50kg', 'Cooking Oil', 'Salt'], reason: 'رقم السطر لا يدخل الاسم');
      expect(inv.items.map((e) => e.unit), ['Bag', 'Box', 'KG']);
      expect(inv.items.map((e) => e.lineTotal), [480000, 157500, 30000]);
    });

    test('الأرقام الهندية والفواصل العربية تُقرأ، والترتيب المعكوس للأعمدة يُحَلّ بالتحقق الحسابي', () {
      const text = 'رقم الفاتورة: ٧٧٤\nالتاريخ: ٠٣/٠٩/٢٠٢٦\n'
          'سكر ناعم كيس ٥ ١٢٠٫٥ ٦٠٢٫٥\n'
          '١٢٠٠ ٤٠٠ ٣ علبة شاي الكبوس\n' // الأعمدة معكوسة: إجمالي، سعر، كمية، وحدة، اسم
          'الإجمالي ١٨٠٢٫٥ ريال سعودي';
      final inv = InvoiceTextParser.parse(text).single;
      expect(inv.invoiceNo, '774');
      expect(inv.date, '2026-09-03');
      expect(inv.items, hasLength(2));
      expect((inv.items[0].qty, inv.items[0].unitPrice, inv.items[0].lineTotal), (5, 120.5, 602.5));
      expect(inv.items[1].name, 'شاي الكبوس');
      expect((inv.items[1].qty, inv.items[1].unitPrice, inv.items[1].lineTotal), (3, 400, 1200));
      expect(inv.printedTotal, 1802.5);
    });

    test('سطور الإجمالي والضريبة والخصم والهاتف والترويسة لا تُعدّ أصنافًا', () {
      const text = 'مؤسسة الأمل للتجارة\nهاتف: 0551234567\nالصنف الكمية السعر الإجمالي\n'
          'أرز 2 10 20\nالإجمالي 20\nضريبة 15% 3\nخصم 5\nالمبلغ المطلوب 18\nتوقيع المستلم 3';
      final inv = InvoiceTextParser.parse(text).single;
      expect(inv.items.map((e) => e.name), ['أرز']);
    });

    test('ما لا يُقرأ يبقى فارغًا ولا يُخمَّن', () {
      final inv = InvoiceTextParser.parse('سكر 2 10 20').single;
      expect(inv.invoiceNo, isEmpty);
      expect(inv.date, isEmpty);
      expect(inv.currency, isEmpty);
      expect(inv.merchant, isEmpty);
      expect(InvoiceTextParser.parse('   \n  '), isEmpty);
    });

    test('إعادة بناء الصفوف من المواضع: جدول يساري واتجاه الاسم يُستنتج', () {
      OcrWord w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 30);
      // اسم عند اليسار وأرقام عند اليمين (جدول مرسوم من اليسار بكلمات عربية).
      final ltr = wordsToLines([
        w('سكر', 400, 100), w('أبيض', 330, 100), w('كيس', 580, 100), w('4', 760, 100), w('120', 940, 100), w('480', 1120, 100),
        w('زيت', 400, 200), w('طبخ', 330, 200), w('جالون', 580, 200), w('6', 760, 200), w('42', 940, 200), w('252', 1120, 200),
        w('ملح', 330, 300), w('كيس', 580, 300), w('2', 760, 300), w('5', 940, 300), w('10', 1120, 300),
      ]);
      expect(ltr, ['سكر أبيض كيس 4 120 480', 'زيت طبخ جالون 6 42 252', 'ملح كيس 2 5 10']);
      // اسم عند اليمين (جدول عربي معتاد).
      final rtl = wordsToLines([
        w('سكر', 1100, 100), w('أبيض', 1030, 100), w('كيس', 880, 100), w('4', 700, 100), w('120', 520, 100), w('480', 340, 100),
        w('زيت', 1100, 200), w('طبخ', 1030, 200), w('جالون', 880, 200), w('6', 700, 200), w('42', 520, 200), w('252', 340, 200),
      ]);
      expect(rtl, ['سكر أبيض كيس 4 120 480', 'زيت طبخ جالون 6 42 252']);
    });

    test('مخرجات hOCR: الكيانات والوسوم الداخلية', () {
      const h = "<span class='ocrx_word' id='w1' title='bbox 10 20 70 50; x_wconf 90'>A&amp;B</span>"
          "<span class='ocrx_word' id='w2' title='bbox 80 20 140 50; x_wconf 90'><strong>٥٠</strong></span>";
      final words = parseHocr(h);
      expect(words.map((e) => e.text), ['A&B', '٥٠']);
      expect(words.first.x0, 10);
    });

    test('نوع الملف يُعرف من بصمته لا امتداده', () {
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 minimal test document bytes'));
      expect(InvoiceScanner.mediaTypeOf(pdf), 'application/pdf');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])), 'image/jpeg');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0])), 'image/png');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList(List.filled(20, 7))), isNull);
    });

    test('مفتاح مسار Tesseract محلي لا يُزامَن، ولا مفاتيح خدمات خارجية', () {
      expect(SettingsRepo.localOnlyKeys, contains(OcrSettings.key));
      expect(SettingsRepo.localOnlyKeys, isNot(contains('invoiceAi')));
    });

    testWidgets('الصورة الكبيرة تُصغَّر والصغيرة تُكبَّر لتناسب القراءة', (tester) async {
      Future<Uint8List> png(int w, int h) async {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF336699));
        final img = await rec.endRecording().toImage(w, h);
        return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      }

      Future<int> longest(Uint8List b) async {
        final c = await ui.instantiateImageCodec(b);
        final f = await c.getNextFrame();
        return f.image.width > f.image.height ? f.image.width : f.image.height;
      }

      await tester.runAsync(() async {
        final ok = await png(2400, 1600);
        expect(await InvoiceScanner.fitForOcr(ok), ok, reason: 'ضمن الحدود: كما هي');
        expect(await longest(await InvoiceScanner.fitForOcr(await png(5200, 3400))), 3000);
        expect(await longest(await InvoiceScanner.fitForOcr(await png(600, 400))), 1800);
      });
    });

    testWidgets('الخط الكامل بمحرك مُحاكى: صورة ← كلمات ← صفوف ← فاتورة', (tester) async {
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 2000, 1400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final img = await rec.endRecording().toImage(2000, 1400);
        final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        final engine = _FakeOcr(parseHocr(File('test/fixtures/ocr/invoice_en.hocr').readAsStringSync()));
        final out = await InvoiceScanner(engine).scan(bytes);
        expect(out.single.items, hasLength(3));
        expect(engine.paths, hasLength(1));
        expect(File(engine.paths.single).existsSync(), isFalse, reason: 'الملف المؤقت يُحذف بعد القراءة');
        await expectLater(InvoiceScanner(engine).scan(Uint8List.fromList(List.filled(40, 9))), throwsA(isA<InvoiceScanException>()));
        await expectLater(InvoiceScanner(_FakeOcr(const [])).scan(bytes), throwsA(isA<InvoiceScanException>()));
      });
    });

    // اختبار حقيقي لمحرك سطح المكتب ببرنامج Tesseract إن وُجد على الجهاز (يُتخطّى بدونه).
    test('Tesseract الحقيقي: صورة فاتورة عربية وإنجليزية تُقرآن دون إنترنت', () async {
      final exe = await DesktopTesseractOcr.locate();
      if (exe == null) {
        markTestSkipped('Tesseract غير مثبّت على هذا الجهاز');
        return;
      }
      final tmp = await Directory.systemTemp.createTemp('ocr_real');
      addTearDown(() => tmp.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      final engine = DesktopTesseractOcr(exe);
      final en = InvoiceTextParser.parse(wordsToLines(await engine.recognize('test/fixtures/ocr/invoice_en.png')).join('\n')).single;
      expect(en.items.map((e) => e.lineTotal), [480000, 157500, 30000]);
      final ar = InvoiceTextParser.parse(wordsToLines(await engine.recognize('test/fixtures/ocr/invoice_ar.png')).join('\n')).single;
      expect(ar.items.map((e) => e.lineTotal), [850, 482, 252, 186]);
      expect(ar.invoiceNo, '5821');
    });
  });


  group('توزيع المسحوب على العقد', () {
    const inv = ScannedInvoice(
      merchant: 'محلات الوفي',
      invoiceNo: '274',
      date: '2026-08-12',
      currency: 'yer',
      printedTotal: 4400,
      items: [ScannedItem(name: 'رز', unit: 'كيس', qty: 2, unitPrice: 2200, lineTotal: 4400)],
    );

    ContractScanMerge merge({String supplier = '', String date = '', String cur = 'sar', double rate = 0, bool has = false, List<ScannedInvoice> list = const [inv]}) =>
        mergeScansIntoContract(supplier: supplier, listDate: date, currency: cur, exchangeRate: rate, hasExistingItems: has, invoices: list);

    test('كل صنف يحمل رقم فاتورته وتاريخها، ويُملأ الفارغ من الرأس', () {
      final m = merge();
      expect(m.items.single.invoiceNo, '274');
      expect(m.items.single.date, '2026-08-12');
      expect(m.items.single.total, 4400);
      expect(m.supplier, 'محلات الوفي');
      expect(m.listDate, '2026-08-12');
      expect(m.currency, 'yer', reason: 'عقد بلا أصناف يتبع عملة الفاتورة');
      expect(m.warnings, isEmpty);
    });

    test('لا يُكتب فوق ما أدخله المستخدم ويُنبَّه إلى الاختلاف', () {
      final m = merge(supplier: 'تاجر آخر', date: '2026-01-01');
      expect(m.supplier, 'تاجر آخر');
      expect(m.listDate, '2026-01-01');
      expect(m.warnings.any((w) => w.contains('يخالف المُدخل')), isTrue);
    });

    test('عملة مخالفة في عقدٍ فيه أصناف: تعارض بلا تحويل تلقائي', () {
      final m = merge(has: true);
      expect(m.currencyConflict, isTrue);
      expect(m.currency, 'sar');
    });

    test('سعر الصرف المطبوع يملأ الفارغ فقط', () {
      final withRate = ScannedInvoice(currency: 'yer', exchangeRate: 410, items: inv.items);
      expect(merge(list: [withRate]).exchangeRate, 410);
      expect(merge(list: [withRate], rate: 395, cur: 'yer', has: true).exchangeRate, 395);
    });

    test('سعر الوحدة والإجمالي الغائبان يُشتقان، والتناقض يُحذَّر منه ولا يُصحَّح', () {
      const noPrice = ScannedInvoice(items: [ScannedItem(name: 'سكر', qty: 4, lineTotal: 800)]);
      final a = merge(list: [noPrice]).items.single;
      expect(a.price, 200);
      const noTotal = ScannedInvoice(items: [ScannedItem(name: 'ملح', qty: 3, unitPrice: 10)]);
      expect(merge(list: [noTotal]).items.single.total, 30);
      const bad = ScannedInvoice(items: [ScannedItem(name: 'شاي', qty: 2, unitPrice: 100, lineTotal: 500)]);
      final m = merge(list: [bad]);
      expect(m.items.single.total, 500, reason: 'القيمة المطبوعة لا تُغيَّر');
      expect(m.warnings.any((w) => w.contains('شاي')), isTrue);
    });

    test('إجمالي الفاتورة المطبوع المخالف لمجموع الأصناف يُحذَّر منه', () {
      const off = ScannedInvoice(printedTotal: 5000, items: [ScannedItem(name: 'رز', qty: 1, unitPrice: 4400, lineTotal: 4400)]);
      expect(merge(list: [off]).warnings.any((w) => w.contains('إجماليها المطبوع')), isTrue);
    });

    test('عدة فواتير بعملتين، وملف بلا أصناف', () {
      const sar = ScannedInvoice(currency: 'sar', items: [ScannedItem(name: 'أ', qty: 1, unitPrice: 1, lineTotal: 1)]);
      expect(merge(list: [inv, sar]).warnings.any((w) => w.contains('بعملتين')), isTrue);
      expect(merge(list: const [ScannedInvoice()]).warnings.any((w) => w.contains('لم يُستخرج')), isTrue);
    });

    test('أصناف الفاتورة تتحول إلى أسطر العقد بلا ربط بأصناف النظام', () {
      final m = merge(list: [inv, inv]);
      expect(m.items, hasLength(2));
      expect(ContractItem.sum(m.items), 8800);
    });
  });
}

/// محرك OCR مُحاكى يعيد كلماتٍ جاهزة، ويسجّل مسارات الصور التي طُلبت قراءتها.
class _FakeOcr implements OcrEngine {
  _FakeOcr(this.words);
  final List<OcrWord> words;
  final paths = <String>[];

  @override
  Future<List<OcrWord>> recognize(String imagePath) async {
    paths.add(imagePath);
    return words;
  }
}
