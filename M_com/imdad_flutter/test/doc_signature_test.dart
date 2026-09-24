import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/documents_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/repos/signatures_repo.dart';

/// توقيع السندات من طرفه إلى طرفه: يُوقَّع السند المحفوظ، ويُطبع رمزه، ثم
/// يُتحقق منه بمقابلة السجل — وتسقط المطابقة إن تغيّر السند بعد التوقيع.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MovementsRepo mv;
  late SignaturesRepo signatures;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mv = MovementsRepo(db);
    signatures = SignaturesRepo(db);
    await ESign(db).ensureKey();
  });

  tearDown(() => db.close());

  /// سند توريد محفوظ فعلًا، ويعيد مرجعه.
  Future<String> aReceipt({double qty = 10}) async {
    final id = await CatalogRepo(db).saveItem(
      code: '1001',
      name: 'أرز أبيض',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await CatalogRepo(db).saveWarehouse(code: 'W1', name: 'المستودع الرئيسي');
    final res = await mv.saveReceipt(
      warehouse: 'المستودع الرئيسي',
      supplier: 'مؤسسة التموين',
      date: '2026-09-19',
      lines: [
        DocLineInput(
          itemId: id,
          itemCode: '1001',
          itemName: 'أرز أبيض',
          unitName: 'كجم',
          factor: 1,
          qty: qty,
        ),
      ],
    );
    expect(res.ok, isTrue, reason: res.error);
    return res.refNo;
  }

  Future<String> signStored(String ref) async {
    final payload = await signatures.payloadOfStored(ref);
    expect(payload, isNotNull, reason: 'السند المحفوظ يجب أن يُقرأ للتوقيع');
    final token = await signatures.signOnce(docRef: ref, payload: payload!);
    expect(token, isNotNull);
    return token!;
  }

  test('السند الموقَّع يُتحقق منه بمقابلة السجل المحفوظ', () async {
    final ref = await aReceipt();
    final token = await signStored(ref);

    final check = await ESign(db).verify(
      token,
      payload: await signatures.payloadOfStored(ref),
    );

    expect(check.ok, isTrue, reason: check.reason);
    expect(check.docRef, ref);
    expect(check.digestMatched, isTrue);
  });

  test('إعادة الطباعة تُخرج الرمز نفسه فلا تتعدد تواقيع السند الواحد', () async {
    final ref = await aReceipt();
    final first = await signStored(ref);

    final again = await signatures.signOnce(
      docRef: ref,
      payload: await signatures.payloadOfStored(ref) ?? const {},
    );

    expect(again, first);
    expect(await signatures.tokenFor(ref), first);
  });

  test('تعديل كمية السند بعد توقيعه يُسقط التحقق', () async {
    final ref = await aReceipt();
    final token = await signStored(ref);

    // تعديل السند من سجل المستندات بعد اعتماده وتوقيعه.
    final lines = await DocumentsRepo(db).lines(DocKind.receipt, ref);
    await (db.update(db.receipts)..where((t) => t.id.equals(lines.first.id)))
        .write(const ReceiptsCompanion(qty: Value(99), baseQty: Value(99)));

    final check = await ESign(db).verify(
      token,
      payload: await signatures.payloadOfStored(ref),
    );

    expect(check.ok, isFalse);
    expect(check.reason, contains('لا يطابق'));
  });

  test('سند غير موجود في هذا الجهاز: يُتحقق من التوقيع وحده', () async {
    final ref = await aReceipt();
    final token = await signStored(ref);

    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    // نقل المفتاح العام وحده إلى الجهاز الآخر ليتمكن من التحقق.
    expect(await SignaturesRepo(other).payloadOfStored(ref), isNull);

    final check = await ESign(db).verify(token);
    expect(check.ok, isTrue, reason: check.reason);
    expect(check.digestMatched, isFalse);
  });

  test('بلا مفتاح توقيع يُطبع السند بلا رمز بدل أن تفشل الطباعة', () async {
    await ESign(db).removeKey();
    final ref = await aReceipt();

    final token = await signatures.signOnce(
      docRef: ref,
      payload: await signatures.payloadOfStored(ref) ?? const {},
    );

    expect(token, isNull);
  });
}
