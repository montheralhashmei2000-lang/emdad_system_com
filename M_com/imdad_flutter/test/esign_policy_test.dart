import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/data/repos/signatures_repo.dart';
import 'package:imdad/domain/esign_policy.dart';
import 'package:imdad/domain/perm_catalog.dart';

/// البند H-5 في تدقيق 2026-10-10، وقرار المالك في 2026-10-11: التوقيع على
/// السند المحفوظ وحده وبحالةٍ نهائية؛ تلقائي أو يدوي يعتمده القائد أو معطَّل.
///
/// كان كل نموذجٍ يُطبع يُوقَّع تلقائيًّا — ومنه ما لم يُحفظ برقمٍ محجوزٍ لا
/// مُستهلَك — فتخرج ورقةٌ رسمية موقَّعة لسندٍ لا وجود له في النظام.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SignaturesRepo signatures;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    signatures = SignaturesRepo(db);
    await ESign(db).ensureKey();
  });

  tearDown(() => db.close());

  Future<String> receipt({bool draft = false}) async {
    final id = await CatalogRepo(db).saveItem(
      code: '1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    final res = await MovementsRepo(db).saveReceipt(
      warehouse: 'الرئيسي',
      supplier: 'م',
      date: '2026-09-19',
      draft: draft,
      lines: [DocLineInput(itemId: id, itemCode: '1', itemName: 'أرز', unitName: 'كجم', factor: 1, qty: 10)],
    );
    return res.refNo;
  }

  Future<String?> printToken(String ref, ESignMode mode) async {
    final status = (await signatures.statusOfStored(ref))!;
    return signatures.tokenForPrint(
      docRef: ref,
      status: status,
      mode: mode,
      payload: (await signatures.payloadOfStored(ref))!,
    );
  }

  test('الوضع الافتراضي تلقائي، ويُحفظ ويُقرأ', () async {
    expect(await SettingsRepo(db).esignMode(), ESignMode.auto);
    await SettingsRepo(db).saveEsignMode(ESignMode.manual);
    expect(await SettingsRepo(db).esignMode(), ESignMode.manual);
  });

  test('المسودة والأمر المعلّق والملغى لا تُوقَّع أبدًا', () async {
    for (final s in ['DRAFT', 'ORDER', 'CANCELLED', 'REJECTED', '']) {
      expect(ESignPolicy.signable(s), isFalse, reason: s);
    }
    final ref = await receipt(draft: true);
    expect(await printToken(ref, ESignMode.auto), isNull);
    expect(() => signatures.signManually(
          docRef: ref,
          status: 'DRAFT',
          payload: const {},
          actorEmail: 'x',
        ), throwsStateError);
  });

  test('تلقائي: السند المحفوظ يُوقَّع، وإعادة طباعته تُخرج الرمز نفسه', () async {
    final ref = await receipt();
    final first = await printToken(ref, ESignMode.auto);
    expect(first, isNotNull);
    expect(await printToken(ref, ESignMode.auto), first);
  });

  test('تعديل السند بعد توقيعه: التلقائي يعيد التوقيع على المحتوى الجديد', () async {
    final ref = await receipt();
    final first = await printToken(ref, ESignMode.auto);
    await (db.update(db.receipts)..where((t) => t.refNo.equals(ref)))
        .write(const ReceiptsCompanion(qty: Value(12), baseQty: Value(12)));
    final second = await printToken(ref, ESignMode.auto);
    expect(second, isNotNull);
    expect(second, isNot(first), reason: 'طُبع رمزٌ قديم على محتوى جديد');
    final check = await ESign(db).verify(second!, payload: await signatures.payloadOfStored(ref));
    expect(check.ok, isTrue);
  });

  test('يدوي: لا يُوقَّع عند الطباعة حتى يوقّعه صاحب الصلاحية، ثم يُطبع رمزه', () async {
    final ref = await receipt();
    expect(await printToken(ref, ESignMode.manual), isNull);
    final token = await signatures.signManually(
      docRef: ref,
      status: 'COMPLETED',
      payload: (await signatures.payloadOfStored(ref))!,
      actorEmail: 'commander@imdad.local',
    );
    expect(await printToken(ref, ESignMode.manual), token);
    final audits = await (db.select(db.auditLogs)..where((t) => t.action.equals('esign.signed'))).get();
    expect(audits.single.risk, 'high');

    // تعديلٌ بعد التوقيع اليدوي يُسقطه: لا يُطبع رمزٌ لا يطابق المحتوى.
    await (db.update(db.receipts)..where((t) => t.refNo.equals(ref)))
        .write(const ReceiptsCompanion(qty: Value(13), baseQty: Value(13)));
    expect(await printToken(ref, ESignMode.manual), isNull);
  });

  test('معطَّل: لا رمز ولو كان السند موقَّعًا من قبل', () async {
    final ref = await receipt();
    expect(await printToken(ref, ESignMode.auto), isNotNull);
    expect(await printToken(ref, ESignMode.off), isNull);
  });

  test('صلاحية التوقيع اليدوي: المالك أو من مُنحها صراحةً — لا يرثها المدير', () {
    expect(ESignPolicy.canSign(role: 'owner', permissions: const {}), isTrue);
    expect(ESignPolicy.canSign(role: 'admin', permissions: const {}), isFalse);
    expect(
      ESignPolicy.canSign(role: 'user', permissions: const {
        'esign': {'view': true, 'approve': true},
      }),
      isTrue,
    );
    expect(PermCatalog.byKey['esign']!.actions, contains('approve'));
  });
}
