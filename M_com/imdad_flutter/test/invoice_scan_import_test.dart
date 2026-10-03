import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/ai/invoice_scan.dart';
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

  group('مسح الفواتير', () {
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 minimal test document bytes'));

    test('بصمة الملف تحدد نوعه لا امتداده', () {
      expect(InvoiceScanner.mediaTypeOf(pdf), 'application/pdf');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])), 'image/jpeg');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0])), 'image/png');
      expect(InvoiceScanner.mediaTypeOf(Uint8List.fromList(List.filled(20, 7))), isNull);
    });

    test('جسم الطلب: مخطط منظَّم، بلا tool_choice/thinking/sampling، وPDF كوثيقة', () {
      final body = InvoiceScanner(apiKey: 'k').buildRequest(pdf, 'application/pdf');
      expect(body['model'], 'claude-opus-5-5');
      expect(body.containsKey('tool_choice'), isFalse, reason: 'forced tool use يُرفض على النماذج الحالية');
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
      final oc = body['output_config'] as Map;
      expect(oc['effort'], 'low');
      expect((oc['format'] as Map)['type'], 'json_schema');
      final content = ((body['messages'] as List).single as Map)['content'] as List;
      expect((content[0] as Map)['type'], 'document');
      expect(((content[0] as Map)['source'] as Map)['media_type'], 'application/pdf');
      expect(((content[0] as Map)['source'] as Map)['data'], base64Encode(pdf));
      expect((content[1] as Map)['type'], 'text');
      // صورة ⇒ كتلة image.
      final img = InvoiceScanner(apiKey: 'k', model: 'claude-sonnet-5-5').buildRequest(pdf, 'image/png');
      expect((((img['messages'] as List).single as Map)['content'] as List)[0] as Map, containsPair('type', 'image'));
      expect(img['model'], 'claude-sonnet-5-5');
    });

    test('المخطط: كل الحقول مطلوبة ولا حقول إضافية (شرط الإخراج المنظَّم)', () {
      void check(Map s) {
        if (s['type'] == 'object') {
          expect(s['additionalProperties'], isFalse);
          expect((s['required'] as List).toSet(), (s['properties'] as Map).keys.toSet());
          for (final v in (s['properties'] as Map).values) {
            check(v as Map);
          }
        } else if (s['type'] == 'array') {
          check(s['items'] as Map);
        }
      }

      check(InvoiceScanner.schema);
    });

    String reply(List<Map<String, Object?>> invoices, {String stop = 'end_turn'}) => jsonEncode({
          'stop_reason': stop,
          'content': [
            {'type': 'text', 'text': jsonEncode({'invoices': invoices})},
          ],
        });

    final sample = {
      'merchant': ' محلات الوفي ',
      'invoice_no': '274',
      'date': '12/08/2026',
      'currency': 'yer',
      'exchange_rate': 0,
      'printed_total': 4400,
      'notes': '',
      'items': [
        {'name': 'رز بسمتي', 'unit': 'كيس', 'qty': 2, 'unit_price': 2200, 'line_total': 4400},
        {'name': '', 'unit': '', 'qty': 0, 'unit_price': 0, 'line_total': 0},
      ],
    };

    test('يقرأ الردّ ويطبّع التاريخ والعملة ويُسقط الأسطر الفارغة', () {
      final inv = InvoiceScanner.parseResponse(200, reply([sample])).single;
      expect(inv.merchant, 'محلات الوفي');
      expect(inv.date, '2026-08-12');
      expect(inv.currency, 'yer');
      expect(inv.items, hasLength(1));
      expect(inv.items.single.unitPrice, 2200);
      // عملة غير معروفة ⇒ فارغة، وتاريخ هجري/غير مفهوم ⇒ فارغ.
      final u = InvoiceScanner.parseResponse(200, reply([{...sample, 'currency': 'unknown', 'date': '1448/02/10'}])).single;
      expect(u.currency, isEmpty);
      expect(u.date, isEmpty);
    });

    test('أخطاء الخدمة تُترجم لرسائل مفهومة', () {
      InvoiceScanException err(int status, [String body = '{"type":"error","error":{"message":"bad"}}']) {
        try {
          InvoiceScanner.parseResponse(status, body);
        } on InvoiceScanException catch (e) {
          return e;
        }
        fail('لم يُرمَ خطأ');
      }

      expect(err(401).message, contains('مفتاح'));
      expect(err(429).message, contains('حد الطلبات'));
      expect(err(400).message, contains('bad'));
      expect(() => InvoiceScanner.parseResponse(200, reply([], stop: 'refusal')), throwsA(isA<InvoiceScanException>()));
      expect(() => InvoiceScanner.parseResponse(200, reply([], stop: 'max_tokens')), throwsA(isA<InvoiceScanException>()));
      expect(() => InvoiceScanner.parseResponse(200, 'ليس json'), throwsA(isA<InvoiceScanException>()));
    });

    test('المسح كاملًا بنقل مُحاكى: العنوان والترويسات وجسم الطلب', () async {
      Uri? url;
      Map<String, String>? headers;
      String? sent;
      final scanner = InvoiceScanner(
        apiKey: 'sk-test',
        transport: (u, h, b) async {
          url = u;
          headers = h;
          sent = b;
          return (200, reply([sample]));
        },
      );
      final out = await scanner.scan(pdf);
      expect(out.single.invoiceNo, '274');
      expect(url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(headers!['x-api-key'], 'sk-test');
      expect(headers!['anthropic-version'], '2023-06-01');
      expect((jsonDecode(sent!) as Map)['model'], 'claude-opus-5-5');
    });

    test('بلا مفتاح أو بنوع غير مدعوم: خطأ قبل أي إرسال', () async {
      var called = false;
      Future<(int, String)> t(Uri u, Map<String, String> h, String b) async {
        called = true;
        return (200, '{}');
      }

      await expectLater(InvoiceScanner(apiKey: '', transport: t).scan(pdf), throwsA(isA<InvoiceScanException>()));
      await expectLater(InvoiceScanner(apiKey: 'k', transport: t).scan(Uint8List.fromList(List.filled(30, 3))), throwsA(isA<InvoiceScanException>()));
      expect(called, isFalse);
    });

    test('مفتاح الخدمة محلي لا يُزامَن', () {
      expect(SettingsRepo.localOnlyKeys, contains(InvoiceAiSettings.key));
    });
  });

  testWidgets('الصورة الكبيرة تُصغَّر قبل الإرسال والصغيرة تبقى كما هي', (tester) async {
    Future<Uint8List> png(int w, int h) async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF336699));
      final img = await rec.endRecording().toImage(w, h);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }

    await tester.runAsync(() async {
      final small = await png(400, 300);
      final (same, t1) = await InvoiceScanner.prepareImage(small, 'image/png');
      expect(same, small);
      expect(t1, 'image/png');

      final big = await png(3600, 2400);
      final (shrunk, t2) = await InvoiceScanner.prepareImage(big, 'image/png');
      expect(t2, 'image/png');
      final codec = await ui.instantiateImageCodec(shrunk);
      final f = await codec.getNextFrame();
      expect(f.image.width > f.image.height ? f.image.width : f.image.height, 1700);
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
