import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_templates/excel_templates.dart';
import 'package:imdad/data/migration/excel_templates/template_writer.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/fuel_repo.dart';
import 'package:imdad/data/repos/stocktake_repo.dart';
import 'package:imdad/features/excel_templates/excel_templates_dialog.dart';

/// نافذة تقرير الاستيراد: القالب المكتشَف، والتقرير قبل الكتابة، وحجب الاستبدال
/// عمّن لا يملك الحذف، والتنفيذ الفعلي.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Uint8List items(List<List<Object?>> rows) => Uint8List.fromList(TemplateWriter.build(TemplateSpec.items, rows));

  /// يعرض النافذة داخل مسار يُرجِع نتيجتها، ويترك للقاعدة فرصتها خارج الزمن الوهمي.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ValueNotifier<TemplateReport?>> pump(
    WidgetTester tester, {
    required Uint8List bytes,
    TemplateKind kind = TemplateKind.items,
    bool canDelete = true,
    List<BeneficiaryUnit> camps = const [],
    String campId = '',
    List<String> warehouses = const [],
    List<Stocktake> orders = const [],
    String orderId = '',
    bool canEditCounted = false,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final result = ValueNotifier<TemplateReport?>(null);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  result.value = await Navigator.of(ctx).push<TemplateReport>(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: SingleChildScrollView(
                        child: ExcelImportPreview(
                          db: db,
                          bytes: bytes,
                          fileName: 'ملف.xlsx',
                          kind: kind,
                          camps: camps,
                          initialCampId: campId,
                          initialDate: '2026-10-01',
                          canDelete: canDelete,
                          actor: 'tester',
                          warehouses: warehouses,
                          initialWarehouse: warehouses.isEmpty ? '' : warehouses.first,
                          orders: orders,
                          initialOrderId: orderId,
                          canEditCounted: canEditCounted,
                        ),
                      ),
                    ),
                  ));
                },
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    await settle(tester);
    return result;
  }

  testWidgets('يعرض القالب المكتشَف وتقريرًا بالناجح والفاشل وسببه قبل أي كتابة', (tester) async {
    await pump(tester, bytes: items([
      ['1', 'سليم', null, 'حبة', null, null, null, null, null, null],
      ['x9', 'كود حروف', null, 'حبة', null, null, null, null, null, null],
    ]));

    expect(find.text('القالب المكتشَف: الأصناف'), findsOneWidget);
    // الشارتان بأرقام الشاشة (هندية افتراضيًا): ناجح ١، فاشل ١.
    expect(find.text('ناجح ١'), findsOneWidget);
    expect(find.text('فاشل ١'), findsOneWidget);
    expect(find.text('الصفوف الفاشلة'), findsOneWidget);
    expect(find.textContaining('صف 3'), findsOneWidget);
    expect(find.textContaining('أرقامًا فقط'), findsOneWidget);
    expect(await CatalogRepo(db).items(), isEmpty, reason: 'التقرير لا يكتب');
  });

  testWidgets('«تنفيذ الاستيراد» يكتب فعلًا ويُرجع التقرير', (tester) async {
    final result = await pump(tester, bytes: items([
      ['1', 'سليم', null, 'حبة', null, null, null, null, null, null],
    ]));

    await tester.tap(find.text('تنفيذ الاستيراد'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(result.value?.created, 1);
    expect(result.value?.dryRun, isFalse);
    expect(await CatalogRepo(db).itemByCode('1'), isNotNull);
  });

  testWidgets('بلا صلاحية الحذف لا يُعرض الاستبدال ويُشرح السبب', (tester) async {
    await pump(tester, canDelete: false, bytes: items([
      ['1', 'سليم', null, 'حبة', null, null, null, null, null, null],
    ]));

    expect(find.textContaining('الاستبدال يحتاج صلاحية الحذف'), findsOneWidget);
    await tester.tap(find.text('دمج (إضافة/تحديث الموجود)'));
    await tester.pumpAndSettle();
    expect(find.text('استبدال الموجود كلياً'), findsNothing);
  });

  testWidgets('مع صلاحية الحذف يُعرض الاستبدال ويُحدَّث التقرير بحذفه', (tester) async {
    final cat = CatalogRepo(db);
    await cat.saveItem(code: '2', name: 'قديم', baseUnit: 'حبة');
    await pump(tester, bytes: items([
      ['1', 'سليم', null, 'حبة', null, null, null, null, null, null],
    ]));
    expect(find.textContaining('حُذف'), findsNothing, reason: 'الدمج لا يحذف');

    await tester.tap(find.text('دمج (إضافة/تحديث الموجود)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استبدال الموجود كلياً'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(find.textContaining('حُذف'), findsOneWidget);
    expect(find.text('تنفيذ الاستبدال'), findsOneWidget);
    expect(await cat.itemByCode('2'), isNotNull, reason: 'التقرير لم يحذف بعد');
  });

  testWidgets('التفريدة: المعسكر والتاريخ يظهران في النافذة ويُفحص الملف عليهما', (tester) async {
    final cat = CatalogRepo(db);
    final camp = await cat.saveUnit(code: '1', name: 'المعسكر الأول', type: 'camp', category: 'معسكر');
    await cat.saveUnit(code: '1-1', name: 'الكتيبة', parentId: camp, parentName: 'المعسكر الأول');
    final camps = [for (final u in await cat.units()) if (u.isCamp) u];
    final bytes = Uint8List.fromList(TemplateWriter.build(TemplateSpec.strength, [
      ['الكتيبة', 100, 10, null],
    ]));

    await pump(tester, bytes: bytes, kind: TemplateKind.strength, camps: camps, campId: camp);

    expect(find.text('القالب المكتشَف: تفريدة المعسكر'), findsOneWidget);
    expect(find.text('المعسكر'), findsWidgets);
    expect(find.text('تاريخ التفريدة'), findsOneWidget);
    expect(find.textContaining('ناجح'), findsOneWidget);
    expect(find.textContaining('فاشل'), findsOneWidget);
  });

  testWidgets('الأرصدة الافتتاحية: المستودع والتاريخ في النافذة ويُفحص الملف عليهما', (tester) async {
    final cat = CatalogRepo(db);
    await cat.saveWarehouse(code: 'W', name: 'المخزن', manager: '', location: '', feedsAllCamps: true, campIds: const []);
    await cat.saveItem(code: '1', name: 'أرز', baseUnit: 'حبة', units: const [ItemUnit(name: 'حبة', factor: 1, isBase: true)]);
    final bytes = Uint8List.fromList(TemplateWriter.build(TemplateSpec.openingBalances, [
      ['1', 'أرز', 'حبة', 5, null, null, null, null],
    ]));

    final result = await pump(tester, bytes: bytes, kind: TemplateKind.openingBalances, warehouses: const ['المخزن']);

    expect(find.text('القالب المكتشَف: الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.text('المستودع'), findsOneWidget);
    expect(find.text('تاريخ الرصيد الافتتاحي'), findsOneWidget);
    expect(find.text('ناجح ١'), findsOneWidget);
    expect((await (db.select(db.openingBalances)).get()), isEmpty, reason: 'التقرير لا يكتب');

    await tester.tap(find.text('تنفيذ الاستيراد'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(result.value?.created, 1);
    expect((await db.select(db.openingBalances).get()).single.qty, 5);
  });

  testWidgets('العد الفعلي: اختيار الأمر، ودمجٌ فقط بلا اختيار نمط', (tester) async {
    final cat = CatalogRepo(db);
    await cat.saveWarehouse(code: 'W', name: 'المخزن', manager: '', location: '', feedsAllCamps: true, campIds: const []);
    await cat.saveItem(code: '1', name: 'أرز', baseUnit: 'حبة', units: const [ItemUnit(name: 'حبة', factor: 1, isBase: true)]);
    final id = await StocktakeRepo(db).createOrder(warehouse: 'المخزن', date: '2026-10-01');
    final orders = await StocktakeRepo(db).sessions(status: StocktakeRepo.counting);
    final bytes = Uint8List.fromList(TemplateWriter.build(TemplateSpec.stocktakeCount, [
      ['1', 'أرز', 'حبة', 5, null, null, null, null],
    ]));

    final result = await pump(
      tester,
      bytes: bytes,
      kind: TemplateKind.stocktakeCount,
      orders: orders,
      orderId: id,
      canEditCounted: true,
    );

    expect(find.text('القالب المكتشَف: العد الفعلي للجرد'), findsOneWidget);
    expect(find.text('أمر الجرد (المفتوح للعد)'), findsOneWidget);
    expect(find.text('نمط الاستيراد'), findsNothing, reason: 'لا استبدال في الجرد');
    expect(find.textContaining('دمجٌ فقط'), findsOneWidget);
    expect(find.text('ناجح ١'), findsOneWidget);

    await tester.tap(find.text('تنفيذ الاستيراد'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(result.value?.created, 1);
    expect((await StocktakeRepo(db).lines(id)).single.countedQty, 5);
  });

  testWidgets('تفريدة المحروقات: نوع الوقود وتاريخ البداية في النافذة', (tester) async {
    await FuelRepo(db).saveUnit(name: 'وحدة أ', code: 'U1');
    final bytes = Uint8List.fromList(TemplateWriter.build(TemplateSpec.fuelAllocations, [
      ['U1', 'وحدة أ', 'الشمال', 100, null],
    ]));

    final result = await pump(tester, bytes: bytes, kind: TemplateKind.fuelAllocations);

    expect(find.text('القالب المكتشَف: تفريدة المحروقات'), findsOneWidget);
    expect(find.text('نوع الوقود'), findsOneWidget);
    expect(find.text('تاريخ بداية التفريدة (للجديدة فقط)'), findsOneWidget);
    expect(find.text('ناجح ١'), findsOneWidget);

    await tester.tap(find.text('تنفيذ الاستيراد'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(result.value?.created, 1);
    final a = (await FuelRepo(db).allocations()).single.allocation;
    expect((a.fuelType, a.startDate, a.monthlyLiters), ('petrol', '2026-10-01', 400));
  });
}
