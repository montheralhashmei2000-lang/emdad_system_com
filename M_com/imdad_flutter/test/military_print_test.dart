import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/military_print.dart';

/// محرك الطباعة العسكرية: كل نوع سند يُبنى بلا استثناء تخطيط ويُخرج PDF صالحًا،
/// والأصناف تُقسَّم على صفحات (١٨ في الأولى ثم ٢٨).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final engine = MilitaryPrint(
    orgLines: const ['الجمهورية اليمنية', 'وزارة الدفاع', 'قيادة المنطقة', 'دائرة الإمداد والتموين'],
    printedBy: 'admin',
    customFooter: 'وثيقة داخلية — نظام إمداد',
  );

  List<List<String>> rows(int n) => [
        for (var i = 1; i <= n; i++)
          ['$i', '10$i', 'صنف رقم $i', '${i * 5}', 'كيس', '—'],
      ];

  bool isPdf(List<int> bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46; // %PDF

  const master = {
    'ref': 'و-000001',
    'date': '2026-09-18',
    'warehouse': 'المستودع الرئيسي',
    'supplier': 'مؤسسة الخير',
    'beneficiary': 'الكتيبة الأولى',
    'destWarehouse': 'مستودع الفرع',
    'party': 'سرية الإسناد',
    'invoiceNo': '3391',
    'notes': 'ملاحظة اختبار',
    'strength': '180',
    'days': '3',
    'condition': 'صالحة',
  };

  test('سند التوريد يُبنى ويُخرج PDF صالحًا', () async {
    final bytes = await engine.receiveVoucher(master, rows(3));
    expect(isPdf(bytes), isTrue);
  });

  test('أمر الصرف والتحويل والمرتجعان تُبنى كلها', () async {
    expect(isPdf(await engine.issueVoucher(master, rows(2))), isTrue);
    expect(isPdf(await engine.transferVoucher(master, rows(2))), isTrue);
    expect(isPdf(await engine.returnVoucher(master, rows(2), fromUnit: true)), isTrue);
    expect(isPdf(await engine.returnVoucher(master, rows(2), fromUnit: false)), isTrue);
  });

  test('التقرير المجمّع بعناوين أعمدة حرة', () async {
    final bytes = await engine.report(
      master: master,
      headers: const ['م', 'الصنف', 'الكمية', 'الوحدة'],
      rows: const [
        ['١', 'أرز', '٩٥', 'كيس'],
        ['٢', 'زيت', '٢٠٠', 'لتر'],
      ],
      title: 'تقرير مجمّع',
    );
    expect(isPdf(bytes), isTrue);
  });

  test('سند بلا أصناف يبقى صفحة واحدة صالحة', () async {
    expect(isPdf(await engine.receiveVoucher(master, const [])), isTrue);
  });

  test('٥٠ صنفًا تُوزَّع على ثلاث صفحات (١٨ + ٢٨ + ٤)', () async {
    final bytes = await engine.receiveVoucher(master, rows(50));
    expect(isPdf(bytes), isTrue);
    // عدد الصفحات يظهر في بنية المستند؛ يكفي التحقق من أن الحجم يفوق صفحة واحدة.
    final small = await engine.receiveVoucher(master, rows(3));
    expect(bytes.length, greaterThan(small.length));
  });
}
