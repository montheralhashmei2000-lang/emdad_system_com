import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';

/// التوقيع الإلكتروني صار ECDSA حقيقيًا بمفتاحين: خاصٍّ يوقّع وعامٍّ يتحقق.
/// هذه الاختبارات تثبت أن التحقق يسقط عند أي تغيير في المستند أو الرمز.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ESign esign;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    esign = ESign(db);
  });

  tearDown(() => db.close());

  Map<String, dynamic> doc({double qty = 100}) => {
        'warehouse': 'المستودع الرئيسي',
        'lines': [
          {'item': 'أرز أبيض', 'qty': qty, 'unit': 'كيس'},
        ],
      };

  group('المفاتيح', () {
    test('لا مفتاح قبل التهيئة، ولا توقيع بلا مفتاح', () async {
      expect(await esign.hasKey(), isFalse);
      expect(await esign.sign(docRef: 'و-000001', payload: doc()), isNull);
    });

    test('التهيئة تنشئ مفتاحًا عامًا ومعرّفًا مشتقًّا منه', () async {
      await esign.ensureKey();

      final pub = await esign.publicKey();
      expect(await esign.hasKey(), isTrue);
      expect(pub, isNotEmpty);
      expect(await esign.keyId(), ESign.keyIdOf(pub));
    });

    test('إعادة التهيئة لا تستبدل المفتاح فلا تُبطل التواقيع السابقة', () async {
      await esign.ensureKey();
      final first = await esign.publicKey();

      await esign.ensureKey();

      expect(await esign.publicKey(), first);
    });

    test('حذف المفتاح يمنع التوقيع', () async {
      await esign.ensureKey();
      await esign.removeKey();

      expect(await esign.hasKey(), isFalse);
      expect(await esign.sign(docRef: 'و-000001', payload: doc()), isNull);
    });
  });

  group('التوقيع والتحقق', () {
    test('توقيع سليم يُقبل مع مطابقة محتوى المستند', () async {
      await esign.ensureKey();
      final token = await esign.sign(docRef: 'و-000001', payload: doc());

      final check = await esign.verify(token!, payload: doc());

      expect(check.ok, isTrue, reason: check.reason);
      expect(check.docRef, 'و-000001');
      expect(check.signer, 'commander');
      expect(check.digestMatched, isTrue);
      expect(check.keyId, await esign.keyId());
    });

    test('تغيير كمية واحدة يُسقط التحقق', () async {
      await esign.ensureKey();
      final token = await esign.sign(docRef: 'و-000001', payload: doc());

      final check = await esign.verify(token!, payload: doc(qty: 101));

      expect(check.ok, isFalse);
      expect(check.reason, contains('لا يطابق'));
    });

    test('العبث ببايت في التوقيع يُسقط التحقق', () async {
      await esign.ensureKey();
      final token = (await esign.sign(docRef: 'و-000001', payload: doc()))!;
      final parts = token.split('|');
      // قلب حرف واحد في التوقيع نفسه.
      final sig = parts[5];
      parts[5] = (sig[0] == 'A' ? 'B' : 'A') + sig.substring(1);

      final check = await esign.verify(parts.join('|'), payload: doc());

      expect(check.ok, isFalse);
    });

    test('رمز بمعرّف مفتاح مجهول يُرفض ولا يُقبل على أنه سليم', () async {
      await esign.ensureKey();
      final token = (await esign.sign(docRef: 'و-000001', payload: doc()))!;
      final parts = token.split('|')..[1] = 'DEADBEEF';

      final check = await esign.verify(parts.join('|'), payload: doc());

      expect(check.ok, isFalse);
      expect(check.reason, contains('لا يوجد مفتاح'));
    });

    test('الرمز كله ASCII فلا يتوقف على ترميز الماسح', () async {
      await esign.ensureKey();
      final token = (await esign.sign(docRef: 'و-000123', payload: doc()))!;

      expect(token.codeUnits.every((c) => c < 128), isTrue, reason: token);
      expect(ESign.refOf(token), 'و-000123');
    });

    test('رمز مشوّه لا يرمي استثناء بل يعيد سبب الرفض', () async {
      await esign.ensureKey();

      for (final bad in ['', 'نص عادي', 'IMD1|a|b', 'IMD9|a|b|1|c|d']) {
        final check = await esign.verify(bad);
        expect(check.ok, isFalse, reason: bad);
        expect(check.reason, isNotEmpty);
      }
    });

    test('التوقيع حتمي: المستند نفسه واللحظة نفسها تعطي الرمز نفسه', () async {
      await esign.ensureKey();
      final at = DateTime(2026, 9, 19, 10);

      final first = await esign.sign(docRef: 'و-000001', payload: doc(), at: at);
      final second = await esign.sign(docRef: 'و-000001', payload: doc(), at: at);

      expect(first, second);
    });

    test('ترتيب حقول المستند لا يغيّر البصمة', () async {
      await esign.ensureKey();
      final at = DateTime(2026, 9, 19, 10);

      final a = await esign.sign(
        docRef: 'و-1',
        payload: {'b': 2, 'a': 1},
        at: at,
      );
      final b = await esign.sign(
        docRef: 'و-1',
        payload: {'a': 1, 'b': 2},
        at: at,
      );

      expect(a, b);
    });

    test('التحقق بلا محتوى يثبت التوقيع وحده ويعلن أنه لم يقارن المستند', () async {
      await esign.ensureKey();
      final token = (await esign.sign(docRef: 'و-000001', payload: doc()))!;

      final check = await esign.verify(token);

      expect(check.ok, isTrue, reason: check.reason);
      expect(check.digestMatched, isFalse);
    });

    test('مفتاح جهاز آخر لا يتحقق من توقيع هذا الجهاز', () async {
      await esign.ensureKey();
      final token = (await esign.sign(docRef: 'و-000001', payload: doc()))!;

      // جهاز آخر بمفتاح مختلف، لكن بمعرّف المفتاح نفسه (محاولة انتحال).
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherSign = ESign(other);
      await otherSign.ensureKey();
      final spoofed = token.split('|')..[1] = await otherSign.keyId();

      final check = await otherSign.verify(spoofed.join('|'), payload: doc());

      expect(check.ok, isFalse);
    });
  });
}
