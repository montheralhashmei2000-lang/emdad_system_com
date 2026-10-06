import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ids.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/audit_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';

/// دمج جهازين صرف كلٌّ منهما الرصيد نفسه قبل المزامنة يُنتج رصيدًا سالبًا؛ يُسجَّل
/// الانتقال إلى السالب مرةً واحدة بخطورة عالية، ولا يتكرر عند مزامنة بلا تغيير.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String itemId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    itemId = await CatalogRepo(db).saveItem(
      code: 'S1',
      name: 'سكر',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await db.into(db.openingBalances).insert(OpeningBalancesCompanion.insert(
          id: Ids.next('ob'),
          itemId: itemId,
          warehouse: const Value('الرئيسي'),
          qty: const Value(10),
        ));
    // صرفُ هذا الجهاز: 8 من 10.
    await db.into(db.issues).insert(IssuesCompanion.insert(
          id: 'local-issue',
          warehouse: const Value('الرئيسي'),
          itemId: Value(itemId),
          qty: const Value(8),
          baseQty: const Value(8),
        ));
  });
  tearDown(() => db.close());

  Map<String, dynamic> payload({required String issueId, double qty = 8}) => {
        'issues': [
          {
            'id': issueId,
            'warehouse': 'الرئيسي',
            'itemId': itemId,
            'qty': qty,
            'baseQty': qty,
            'factor': 1,
            'status': 'COMPLETED',
          },
        ],
      };

  Future<List<AuditLog>> negativeLogs() async =>
      (await db.select(db.auditLogs).get()).where((l) => l.action == 'sync.negative_stock').toList();

  test('الانتقال إلى سالب يُسجَّل مرة بخطورة عالية وبكل التفاصيل', () async {
    await LegacyImporter(db).importJson(payload(issueId: 'remote-issue'), source: 'جهاز AB12CD34 (10.0.0.7)');

    final logs = await negativeLogs();
    expect(logs, hasLength(1));
    expect(logs.single.risk, AuditRepo.riskHigh);
    final d = jsonDecode(logs.single.details) as Map<String, dynamic>;
    expect(d['warehouse'], 'الرئيسي');
    expect(d['itemCode'], 'S1');
    expect(d['itemName'], 'سكر');
    expect(d['balance'], -6);
    expect(d['source'], 'جهاز AB12CD34 (10.0.0.7)');
    expect(d['at'], isNotEmpty);
  });

  test('مزامنة بلا تغيير لا تكرر السطر', () async {
    final importer = LegacyImporter(db);
    await importer.importJson(payload(issueId: 'remote-issue'));
    await importer.importJson(payload(issueId: 'remote-issue')); // الحمولة نفسها
    expect(await negativeLogs(), hasLength(1));
  });

  test('رصيد سالب قائم من قبل لا يُسجَّل من جديد عند مزامنة أخرى', () async {
    final importer = LegacyImporter(db);
    await importer.importJson(payload(issueId: 'remote-1'));
    await importer.importJson(payload(issueId: 'remote-2', qty: 1)); // يزيده سوءًا فقط
    expect(await negativeLogs(), hasLength(1), reason: 'يُسجَّل الانتقال لا كل تعميق');
  });

  test('دمج لا ينزل بالرصيد تحت الصفر لا يكتب شيئًا', () async {
    await LegacyImporter(db).importJson(payload(issueId: 'remote-issue', qty: 1));
    expect(await negativeLogs(), isEmpty);
  });
}
