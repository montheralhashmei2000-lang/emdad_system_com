import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/web_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';

/// الرصيد يُخزَّن دائمًا بالوحدة الأساسية، لكن أمين المستودع يعدّ بالأكياس.
/// «وحدة العرض» في بطاقة الصنف تغيّر ما يُعرض فقط — في التقارير وفي رصيد شاشات
/// الإدخال — ولا تمسّ المخزَّن إطلاقًا.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CatalogRepo catalog;
  late MovementsRepo mv;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepo(db);
    mv = MovementsRepo(db);
  });

  tearDown(() => db.close());

  Future<Item> saveRice({String reportUnit = ''}) async {
    final id = await catalog.saveItem(
      code: '1001',
      name: 'أرز أبيض',
      baseUnit: 'كجم',
      units: const [
        ItemUnit(name: 'كجم', factor: 1, isBase: true),
        ItemUnit(name: 'كيس', factor: 40),
      ],
      reportUnit: reportUnit,
    );
    return (await catalog.items()).firstWhere((i) => i.id == id);
  }

  group('وحدة العرض في بطاقة الصنف', () {
    test('بلا وحدة عرض يظهر الرصيد بالوحدة الأساسية', () async {
      final item = await saveRice();
      final shown = displayBalance(item, 1100);

      expect(shown.qty, 1100);
      expect(shown.unit, 'كجم');
    });

    test('وحدة عرض «كيس» تحوّل ١١٠٠ كجم إلى ٢٧٫٥ كيسًا', () async {
      final item = await saveRice(reportUnit: 'كيس');
      final shown = displayBalance(item, 1100);

      expect(shown.qty, 27.5);
      expect(shown.unit, 'كيس');
    });

    test('اختيار الوحدة الأساسية نفسها لا يحوّل شيئًا', () async {
      final item = await saveRice(reportUnit: 'كجم');
      final shown = displayBalance(item, 1100);

      expect(shown.qty, 1100);
      expect(shown.unit, 'كجم');
    });

    test('وحدة عرض غير معرّفة في الصنف تسقط إلى الأساسية بلا خطأ', () async {
      final item = await saveRice(reportUnit: 'طبلية');
      final shown = displayBalance(item, 1100);

      expect(shown.qty, 1100);
      expect(shown.unit, 'كجم');
    });

    test('العرض لا يغيّر الرصيد المخزَّن إطلاقًا', () async {
      final item = await saveRice(reportUnit: 'كيس');
      await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
      await mv.saveReceipt(
        warehouse: 'الرئيسي',
        supplier: 'مؤسسة',
        date: '2026-09-20',
        lines: [
          DocLineInput(
            itemId: item.id,
            itemCode: '1001',
            itemName: 'أرز أبيض',
            unitName: 'كيس',
            factor: 40,
            qty: 10,
          ),
        ],
      );

      // ١٠ أكياس = ٤٠٠ كجم مخزَّنة، وتُعرض ١٠ أكياس.
      final stored = (await mv.balances(warehouse: 'الرئيسي'))[item.id];
      expect(stored, 400, reason: 'المخزَّن يبقى بالوحدة الأساسية');
      expect(displayBalance(item, stored!).qty, 10);
      expect(displayBalance(item, stored).unit, 'كيس');
    });

    test('وحدة العرض تنجو من التصدير والاستيراد', () async {
      final item = await saveRice(reportUnit: 'كيس');
      final payload = await DataExporter(db).toMap();

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      await WebImporter(other).importJson(payload);

      final copied = (await CatalogRepo(other).items()).firstWhere((i) => i.id == item.id);
      expect(copied.reportUnit, 'كيس');
      expect(displayBalance(copied, 1100).qty, 27.5);
    });

    test('التغيير في بطاقة الصنف ينعكس على العرض فورًا', () async {
      var item = await saveRice();
      expect(displayBalance(item, 800).unit, 'كجم');

      await catalog.saveItem(
        id: item.id,
        code: '1001',
        name: 'أرز أبيض',
        baseUnit: 'كجم',
        units: const [
          ItemUnit(name: 'كجم', factor: 1, isBase: true),
          ItemUnit(name: 'كيس', factor: 40),
        ],
        reportUnit: 'كيس',
      );
      item = (await catalog.items()).firstWhere((i) => i.id == item.id);

      expect(displayBalance(item, 800).qty, 20);
      expect(displayBalance(item, 800).unit, 'كيس');
    });
  });
}
