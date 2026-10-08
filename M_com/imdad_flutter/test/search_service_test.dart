import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/search/search_service.dart';

/// البحث العام: يمسح جداول النظام بمدخلٍ واحد، ويُقاس بصلاحية الصفحة ونطاق
/// المستودعات — لا يُظهر ما لا يراه المستخدم في شاشته.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SearchService svc;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = SearchService(db);
    await db.into(db.items).insert(ItemsCompanion.insert(
          id: 'i1',
          name: 'طحين فاخر',
          code: const Value('ITM-1'),
          categoryName: const Value('مواد جافة'),
          baseUnit: const Value('كجم'),
        ));
    await db.into(db.items).insert(ItemsCompanion.insert(
          id: 'i2',
          name: 'أرز بسمتي',
          code: const Value('ITM-2'),
          barcode: const Value('99887766'),
        ));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          id: 'w1',
          name: 'مستودع الطحين الرئيسي',
          code: const Value('WH-1'),
          manager: const Value('أحمد'),
        ));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(id: 'w2', name: 'مستودع فرعي'));
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: 's1', name: 'شركة الطحين'));
    for (final (id, ref, wh, status) in [
      ('r1', 'REC-100', 'مستودع الطحين الرئيسي', 'COMPLETED'),
      ('r2', 'REC-101', 'مستودع فرعي', 'COMPLETED'),
      ('r3', 'REC-102', 'مستودع الطحين الرئيسي', 'CANCELLED'),
    ]) {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: id,
            refNo: Value(ref),
            warehouse: Value(wh),
            itemName: const Value('طحين فاخر'),
            date: Value('2026-10-0${id.substring(1)}'),
            status: Value(status),
          ));
    }
    await db.into(db.transfers).insert(TransfersCompanion.insert(
          id: 't1',
          refNo: const Value('TRF-9'),
          warehouse: const Value('مستودع الطحين الرئيسي'),
          destWarehouse: const Value('مستودع فرعي'),
          itemName: const Value('طحين فاخر'),
        ));
    await db.into(db.linkPersons).insert(LinkPersonsCompanion.insert(
          id: 'p1',
          fullName: 'طحين عبدالله',
          militaryNo: const Value('55443'),
          rank: const Value('رقيب'),
        ));
  });

  tearDown(() => db.close());

  test('مدخلٌ أقصر من حرفين لا يُستعلم به', () async {
    for (final q in ['', ' ', 'ط']) {
      final hits = await svc.search(q, access: SearchAccess.all);
      expect(hits.isEmpty, isTrue, reason: 'المدخل «$q»');
      expect(hits.byType, isEmpty);
    }
  });

  test('يجد الصنف باسمه وبكوده وبباركوده، مصنَّفًا بنوعه', () async {
    final byName = await svc.search('طحين', access: SearchAccess.all);
    expect(byName.byType['الأصناف']!.map((h) => h.title), ['طحين فاخر']);
    expect(byName.byType['الأصناف']!.single.page, 'items');
    expect(byName.byType['الأصناف']!.single.subtitle, contains('ITM-1'));

    expect((await svc.search('ITM-2', access: SearchAccess.all)).byType['الأصناف']!.single.title,
        'أرز بسمتي');
    expect((await svc.search('99887', access: SearchAccess.all)).byType['الأصناف']!.single.title,
        'أرز بسمتي');
  });

  test('المدخل الواحد يجمع أنواعًا عدة ويحمل كلٌّ منها صفحتها', () async {
    final hits = await svc.search('طحين', access: SearchAccess.all);
    expect(hits.byType.keys,
        containsAll(['الأصناف', 'المستودعات', 'الموردون', 'سندات الاستلام', 'الأفراد']));
    expect(hits.byType['المستودعات']!.single.page, 'stores');
    expect(hits.byType['الموردون']!.single.page, 'suppliers');
    expect(hits.byType['الأفراد']!.single.page, 'personnel');
    expect(hits.total, hits.byType.values.fold<int>(0, (a, b) => a + b.length));
  });

  test('صلاحية الصفحة تُسقط جدولها كاملًا', () async {
    final hits = await svc.search(
      'طحين',
      access: SearchAccess(canView: (p) => p != 'items' && p != 'stores', scope: null),
    );
    expect(hits.byType.containsKey('الأصناف'), isFalse);
    expect(hits.byType.containsKey('المستودعات'), isFalse);
    expect(hits.byType.containsKey('الموردون'), isTrue, reason: 'الموردون مسموحون فلا يتأثرون');
  });

  test('نطاق المستودعات يُصفّي المستودعات والسندات', () async {
    final hits = await svc.search(
      'مستودع',
      access: SearchAccess(canView: (_) => true, scope: const ['مستودع فرعي']),
    );
    expect(hits.byType['المستودعات']!.map((h) => h.title), ['مستودع فرعي']);

    final recs = await svc.search(
      'REC',
      access: SearchAccess(canView: (_) => true, scope: const ['مستودع فرعي']),
    );
    expect(recs.byType['سندات الاستلام']!.map((h) => h.title), ['REC-101']);
  });

  test('التحويل يلزمه المستودعان في النطاق', () async {
    SearchAccess at(List<String> s) => SearchAccess(canView: (_) => true, scope: s);
    expect(
      (await svc.search('TRF', access: at(const ['مستودع الطحين الرئيسي', 'مستودع فرعي'])))
          .byType['سندات التحويل']!
          .single
          .title,
      'TRF-9',
    );
    expect(
      (await svc.search('TRF', access: at(const ['مستودع فرعي']))).byType.containsKey('سندات التحويل'),
      isFalse,
      reason: 'مستودع المصدر خارج النطاق',
    );
  });

  test('نطاقٌ فارغ (قيمةٌ تالفة) لا يُظهر شيئًا من الجداول ذات المستودع', () async {
    final hits = await svc.search(
      'طحين',
      access: SearchAccess(canView: (_) => true, scope: const []),
    );
    expect(hits.byType.containsKey('المستودعات'), isFalse);
    expect(hits.byType.containsKey('سندات الاستلام'), isFalse);
    expect(hits.byType.containsKey('الأصناف'), isTrue, reason: 'الأصناف بلا مستودع فلا يحجبها النطاق');
  });

  test('السندات الملغاة والمرفوضة لا تظهر', () async {
    final hits = await svc.search('REC', access: SearchAccess.all);
    expect(hits.byType['سندات الاستلام']!.map((h) => h.title), isNot(contains('REC-102')));
    expect(hits.byType['سندات الاستلام']!.map((h) => h.title), containsAll(['REC-100', 'REC-101']));
  });

  test('حدُّ النتائج لكل نوع يُحترم', () async {
    for (var i = 0; i < 9; i++) {
      await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: 'sx$i', name: 'مورد طحين $i'));
    }
    expect((await svc.search('طحين', access: SearchAccess.all)).byType['الموردون']!.length, 5);
    expect(
      (await svc.search('طحين', access: SearchAccess.all, perType: 2)).byType['الموردون']!.length,
      2,
    );
  });

  test('محارف LIKE الخاصة تُبحث كأحرفٍ عادية لا كأنماط', () async {
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: 's9', name: 'شركة 100% حلال'));
    final literal = await svc.search('100%', access: SearchAccess.all);
    expect(literal.byType['الموردون']!.map((h) => h.title), ['شركة 100% حلال']);

    // `%%` نمطٌ يطابق كل شيء لو مُرِّر كما هو؛ بالتحييد لا يطابق شيئًا.
    expect((await svc.search('%%', access: SearchAccess.all)).isEmpty, isTrue);
    expect((await svc.search('__', access: SearchAccess.all)).isEmpty, isTrue);
  });

  test('اسم مستودعٍ فيه علامة اقتباس لا يُفسد الاستعلام', () async {
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(id: 'w9', name: "مستودع 'س'"));
    final hits = await svc.search(
      'مستودع',
      access: SearchAccess(canView: (_) => true, scope: const ["مستودع 'س'"]),
    );
    expect(hits.byType['المستودعات']!.map((h) => h.title), ["مستودع 'س'"]);
  });

  test('لا نتائج لمدخلٍ غير موجود', () async {
    final hits = await svc.search('زعفران', access: SearchAccess.all);
    expect(hits.isEmpty, isTrue);
    expect(hits.total, 0);
  });
}
