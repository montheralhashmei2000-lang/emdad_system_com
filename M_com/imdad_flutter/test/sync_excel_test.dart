import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/excel_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/sync/lan_sync.dart';

/// قالب Excel في مجلد مؤقت خاص بكل اختبار، حتى لا تتصادم الاختبارات
/// حين تُشغَّل ملفاتها بالتوازي.
(Directory, File) _templateFile() {
  final dir = Directory.systemTemp.createTempSync('imdad-xls-');
  final file = File('${dir.path}${Platform.pathSeparator}template.xlsx')
    ..writeAsBytesSync(ExcelImporter.template(), flush: true);
  return (dir, file);
}

/// منفذان خاصّان بهذا الملف: ملفات الاختبار تُشغَّل بالتوازي، ومنفذ واحد
/// مشترك بينها يجعل الطلبات تصل إلى الخادم الخطأ.
const int _port = 8791;
const int _discoveryPort = 8792;

LanSync _sync(AppDatabase db) =>
    LanSync(db, port: _port, discoveryPort: _discoveryPort);

/// يقترن بالجهاز المستقبِل بالرمز المعروض عليه ويعيد النظير الصالح.
Future<SyncPeer> _pairWith(LanSync sender, LanSync receiver) async {
  final pairing = await sender.pair('127.0.0.1', receiver.session!.code, port: _port);
  expect(pairing.ok, isTrue, reason: pairing.message);
  return pairing.peer!;
}

/// اختبارات تُشغّل قاعدة حقيقية في الذاكرة وخادم مزامنة حقيقيًا على المنفذ المحلي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // بيئة الاختبار تستبدل عميل HTTP بعميل وهمي يردّ 400 على كل طلب،
  // وهذه الاختبارات تفتح اتصالًا حقيقيًا على المنفذ المحلي، فتُعطَّل تلك البدائل.
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase source;
  late AppDatabase target;

  setUp(() {
    source = AppDatabase.forTesting(NativeDatabase.memory());
    target = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  group('مزامنة الأجهزة عبر الشبكة المحلية', () {
    test('الإرسال ينقل الأصناف والحركات إلى الجهاز المستقبِل', () async {
      final catalog = CatalogRepo(source);
      final itemId = await catalog.saveItem(
        code: '1001',
        name: 'أرز أبيض',
        baseUnit: 'كجم',
        units: const [
          ItemUnit(name: 'كجم', factor: 1, isBase: true),
          ItemUnit(name: 'كيس', factor: 40),
        ],
      );
      await catalog.saveWarehouse(code: 'W1', name: 'المخزن الرئيسي');
      await MovementsRepo(source).saveReceipt(
        warehouse: 'المخزن الرئيسي',
        supplier: 'مؤسسة التموين',
        date: '2026-09-17',
        lines: [
          DocLineInput(
            itemId: itemId,
            itemCode: '1001',
            itemName: 'أرز أبيض',
            unitName: 'كيس',
            factor: 40,
            qty: 10,
          ),
        ],
      );

      final receiver = _sync(target);
      await receiver.startReceiving();
      addTearDown(receiver.stopReceiving);

      final sender = _sync(source);
      final result = await sender.push(await _pairWith(sender, receiver));

      expect(result.ok, isTrue, reason: result.message);
      expect(result.records, greaterThan(0));

      final items = await CatalogRepo(target).items();
      expect(items.single.name, 'أرز أبيض');

      // الرصيد المنقول يُحتسب في المستودع نفسه: 10 أكياس × 40 = 400 كجم.
      final balances = await MovementsRepo(target).balances(warehouse: 'المخزن الرئيسي');
      expect(balances[itemId], 400);
    });

    test('السحب يجلب بيانات الجهاز الآخر دون حذف ما عندي', () async {
      await CatalogRepo(source).saveItem(
        code: 'S1',
        name: 'سكر',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      await CatalogRepo(target).saveItem(
        code: 'T1',
        name: 'شاي',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );

      final host = _sync(source);
      await host.startReceiving();
      addTearDown(host.stopReceiving);

      final sender = _sync(target);
      final result = await sender.pull(await _pairWith(sender, host));
      expect(result.ok, isTrue, reason: result.message);

      final names = (await CatalogRepo(target).items()).map((i) => i.name).toSet();
      expect(names, containsAll(<String>['شاي', 'سكر']));
    });

    test('إعادة الإرسال لا تُكرّر السجلات', () async {
      await CatalogRepo(source).saveItem(
        code: '2002',
        name: 'زيت',
        baseUnit: 'لتر',
        units: const [ItemUnit(name: 'لتر', factor: 1, isBase: true)],
      );

      final receiver = _sync(target);
      await receiver.startReceiving();
      addTearDown(receiver.stopReceiving);

      final sender = _sync(source);
      final session = await _pairWith(sender, receiver);
      await sender.push(session);
      await sender.push(session);

      final items = await CatalogRepo(target).items();
      expect(items.length, 1);
    });

    test('معلومات الجهاز تُقرأ قبل المزامنة', () async {
      final receiver = _sync(target);
      await receiver.startReceiving();
      addTearDown(receiver.stopReceiving);

      final sender = _sync(source);
      final pairing = await sender.pair('127.0.0.1', receiver.session!.code);
      expect(pairing.ok, isTrue, reason: pairing.message);
      expect(pairing.peer!.info.deviceName, isNotEmpty);
    });

    test('الاتصال بعنوان لا يستجيب يعيد فشلًا واضحًا لا استثناء', () async {
      final result = await _sync(source).pair('127.0.0.1', '123456', port: _port);
      expect(result.ok, isFalse);
      expect(result.message, contains('تعذّر الاتصال'));
    });
  });

  group('استيراد Excel', () {
    test('القالب يُقرأ ويستورد الأصناف والموردين والوحدات والأرصدة', () async {
      final (dir, file) = _templateFile();
      addTearDown(() => dir.deleteSync(recursive: true));

      final result = await ExcelImporter(target).importFile(file);

      expect(result.imported['الأصناف'], 1);
      expect(result.imported['الموردون'], 1);
      expect(result.imported['المستودعات'], 1);
      expect(result.imported['الوحدات'], 2);
      expect(result.imported['الأرصدة الافتتاحية'], 1);
      expect(result.imported['نسب الاستحقاق'], 1);

      final items = await CatalogRepo(target).items();
      expect(items.single.name, 'أرز أبيض');
      // وحدتان: كجم أساس، وكيس بمعامل 40.
      final units = CatalogRepo(target).unitsOf(items.single);
      expect(units.map((u) => u.name), containsAll(<String>['كجم', 'كيس']));
      expect(units.firstWhere((u) => u.name == 'كيس').factor, 40);

      // الرصيد الافتتاحي دخل رصيد المستودع المحدد وحده.
      final balances = await MovementsRepo(target).balances(warehouse: 'المخزن الرئيسي');
      expect(balances[items.single.id], 5000);
    });

    test('إعادة الاستيراد تُحدّث الصنف ولا تُنشئ نسخة ثانية', () async {
      final (dir, file) = _templateFile();
      addTearDown(() => dir.deleteSync(recursive: true));

      await ExcelImporter(target).importFile(file);
      await ExcelImporter(target).importFile(file, restart: true);

      final items = await CatalogRepo(target).items();
      expect(items.length, 1);
    });

    test('المعسكر والوحدة الفرعية يُربطان من عمود المعسكر', () async {
      final (dir, file) = _templateFile();
      addTearDown(() => dir.deleteSync(recursive: true));

      await ExcelImporter(target).importFile(file);
      final units = await CatalogRepo(target).units();
      final camp = units.firstWhere((u) => u.name == 'معسكر الوحدة');
      final child = units.firstWhere((u) => u.name == 'الكتيبة الأولى');
      expect(camp.isCamp, isTrue);
      expect(child.isCamp, isFalse);
      expect(child.parentId, camp.id);
    });
  });
}
