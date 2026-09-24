import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/web_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';

/// دمج الأجهزة كان يكتب بالمعرّف فقط: الحذف لا ينتقل، وآخر من يزامن يفوز ولو
/// كانت بياناته أقدم. هذه الاختبارات تثبت أن سجل التغييرات عالج الحالتين.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<String> addItem(AppDatabase db, String code, String name) =>
      CatalogRepo(db).saveItem(
        code: code,
        name: name,
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

  /// ينقل بيانات [from] إلى [to] كما تفعل المزامنة.
  Future<void> sync(AppDatabase from, AppDatabase to) async {
    await WebImporter(to).importJson(await DataExporter(from).toMap());
  }

  Future<List<String>> names(AppDatabase db) async =>
      (await CatalogRepo(db).items()).map((i) => i.name).toList()..sort();

  /// يضبط ختم سجل يدويًا لمحاكاة «عُدِّل قبل/بعد» بلا انتظار حقيقي.
  Future<void> stamp(AppDatabase db, String entity, String id, DateTime at,
      {DateTime? deletedAt}) async {
    await SyncMarks(db).put(SyncMark(
      entity: entity,
      rowId: id,
      updatedAt: at.millisecondsSinceEpoch,
      deletedAt: deletedAt?.millisecondsSinceEpoch,
    ));
  }

  group('انتقال الحذف', () {
    test('صنف حُذف في جهاز يُحذف في الآخر بعد المزامنة', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);
      expect(await names(b), ['أرز']);

      await CatalogRepo(a).deleteItem(id);
      await sync(a, b);

      expect(await names(b), isEmpty, reason: 'الحذف يجب أن ينتقل');
    });

    test('المحذوف لا يعود من الجهاز الآخر في المزامنة العكسية', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);
      await CatalogRepo(a).deleteItem(id);
      await sync(a, b);

      // الجهاز «ب» يرسل الآن ما عنده إلى «أ» — يجب ألّا يُحيي المحذوف.
      await sync(b, a);

      expect(await names(a), isEmpty);
      expect(await names(b), isEmpty);
    });

    test('تعديل بعد الحذف يُعيد الصنف — الأحدث يفوز', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);

      // «أ» حذفه أمس، و«ب» عدّله اليوم.
      await CatalogRepo(a).deleteItem(id);
      await stamp(a, 'items', id, DateTime(2026, 9, 1),
          deletedAt: DateTime(2026, 9, 1, 8));
      await stamp(b, 'items', id, DateTime(2026, 9, 2));

      await sync(b, a);

      expect(await names(a), ['أرز'], reason: 'التعديل الأحدث يغلب الحذف الأقدم');
    });
  });

  group('حل التعارض بالأحدث', () {
    test('التعديل الأقدم لا يدهس الأحدث', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);

      // «ب» عدّل الاسم اليوم، و«أ» عدّله أمس ثم زامن متأخرًا.
      await CatalogRepo(b).saveItem(
        id: id,
        code: '1001',
        name: 'أرز بسمتي',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await stamp(b, 'items', id, DateTime(2026, 9, 2));
      await stamp(a, 'items', id, DateTime(2026, 9, 1));

      await sync(a, b);

      expect(await names(b), ['أرز بسمتي'], reason: 'الأقدم لا يدهس الأحدث');
    });

    test('التعديل الأحدث ينتقل ويكتب فوق الأقدم', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);

      await CatalogRepo(a).saveItem(
        id: id,
        code: '1001',
        name: 'أرز مصري',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await stamp(a, 'items', id, DateTime(2026, 9, 3));
      await stamp(b, 'items', id, DateTime(2026, 9, 1));

      await sync(a, b);

      expect(await names(b), ['أرز مصري']);
    });

    test('الجهازان يصلان إلى العلامات نفسها فلا تتأرجح المزامنة', () async {
      final id = await addItem(a, '1001', 'أرز');
      await sync(a, b);

      final markA = (await SyncMarks(a).snapshot())['items/$id'];
      final markB = (await SyncMarks(b).snapshot())['items/$id'];

      expect(markB, isNotNull);
      expect(markB!.updatedAt, markA!.updatedAt,
          reason: 'ختم المستورد يجب أن يساوي ختم المصدر بعد تثبيت العلامات');
    });
  });

  group('التوافق مع البيانات القديمة', () {
    test('حمولة بلا سجل تغييرات تُدمج كما كانت', () async {
      await addItem(a, '1001', 'أرز');
      final payload = await DataExporter(a).toMap()..remove('syncMarks');

      await WebImporter(b).importJson(payload);

      expect(await names(b), ['أرز']);
    });

    test('شواهد الحذف القديمة تُنظَّف', () async {
      final id = await addItem(a, '1001', 'أرز');
      await CatalogRepo(a).deleteItem(id);
      await stamp(a, 'items', id, DateTime(2020, 1, 1), deletedAt: DateTime(2020, 1, 1));

      await SyncMarks(a).pruneTombstones();

      expect((await SyncMarks(a).snapshot())['items/$id'], isNull);
    });
  });
}
