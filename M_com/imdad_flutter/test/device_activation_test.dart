import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/data/db/app_database.dart';

/// تفعيل الأجهزة برمز موقَّع بمفتاح المالك **المدفون في التطبيق**.
///
/// جوهر الحماية: لو قُرئ المفتاح العام من قاعدة البيانات لاستطاع من يثبّت نسخة
/// جديدة أن يولّد مفتاحه ويصير هو الإدارة. هذه الاختبارات تحرس ذلك.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase admin;
  late AppDatabase branch;
  late DeviceActivation adminAct;
  late DeviceActivation branchAct;

  /// مفتاح المالك في الاختبارات — يقابل ما يُدفن في `OwnerKey.publicKey`.
  late ({String privateHex, String publicB64}) ownerPair;

  setUp(() {
    admin = AppDatabase.forTesting(NativeDatabase.memory());
    branch = AppDatabase.forTesting(NativeDatabase.memory());
    ownerPair = ESign.generateKeyPair();
    // مفتاح اختبار محقون: المفتاح المدفون في الإصدار حقيقي ولا يملك الاختبار خاصّه.
    adminAct = DeviceActivation(admin, ownerPublicKey: ownerPair.publicB64);
    branchAct = DeviceActivation(branch, ownerPublicKey: ownerPair.publicB64);
  });

  tearDown(() async {
    await admin.close();
    await branch.close();
  });

  Future<String> issue(
    DeviceActivation target, {
    DeviceRole role = DeviceRole.branch,
    Duration valid = const Duration(days: 365),
    String? privateKey,
    bool compact = true,
  }) async {
    await adminAct.importPrivateKey(privateKey ?? ownerPair.privateHex);
    final token = await adminAct.issue(
      deviceId: await target.deviceId(),
      branch: 'اللواء الأول',
      role: role,
      expiresAt: DateTime.now().add(valid),
      compact: compact,
    );
    expect(token, isNotNull, reason: 'الإصدار يحتاج مفتاح المالك');
    return token!;
  }

  group('هوية الجهاز', () {
    test('المعرّف ثمانية أحرف وثابت بين القراءات', () async {
      final first = await branchAct.deviceId();
      expect(first.length, 8);
      expect(await branchAct.deviceId(), first, reason: 'تغيّره يفقد الجهاز تفعيله');
    });

    test('جهازان مختلفان لهما معرّفان مختلفان', () async {
      expect(await adminAct.deviceId(), isNot(await branchAct.deviceId()));
    });

    test('بذرة المعرّفات مشتقة من معرّف الجهاز', () async {
      final id = await branchAct.deviceId();
      expect(await branchAct.idSeed(), id.substring(0, 4).toLowerCase());
    });

    test('بصمة المعرّف ثلاثة أرقام تؤكد التلاوة الهاتفية', () {
      expect(DeviceActivation.checksum('ABCD2345').length, 3);
      expect(DeviceActivation.checksum('ABCD2345'),
          isNot(DeviceActivation.checksum('ABCD2346')));
    });
  });

  group('مفتاح الإصدار', () {
    test('بلا مفتاح لا يمكن إصدار أي رمز', () async {
      expect(await adminAct.canIssue(), isFalse);
      final token = await adminAct.issue(
        deviceId: 'ABCD2345',
        branch: 'فرع',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(token, isNull);
    });

    test('مفتاح مشوّه يُرفض استيراده', () async {
      expect(await adminAct.importPrivateKey('ليس مفتاحًا'), isFalse);
      expect(await adminAct.importPrivateKey('abc'), isFalse);
      expect(await adminAct.canIssue(), isFalse);
    });

    /// الحلقة المغلقة: جهاز الإدارة يحتاج رمزًا، والرمز يحتاج المفتاح. فيجب أن
    /// يُستورد المفتاح على جهاز **غير مفعَّل** وإلا استحال تفعيل الجهاز الأول.
    test('المفتاح يُستورد على جهاز غير مفعَّل — فتنفكّ الحلقة', () async {
      expect(await adminAct.isActivated(), isFalse, reason: 'لم يُفعَّل بعد');
      expect(await adminAct.isMaster(), isFalse);

      expect(await adminAct.importPrivateKey(ownerPair.privateHex), isTrue);
      expect(await adminAct.canIssue(), isTrue, reason: 'الإصدار ممكن قبل التفعيل');

      // ومنه يُصدر لنفسه رمز إدارة ويفعّل به جهازه.
      final token = await adminAct.issue(
        deviceId: await adminAct.deviceId(),
        branch: 'الإدارة',
        role: DeviceRole.master,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      final state = await adminAct.activate(token!);

      expect(state.ok, isTrue, reason: state.reason);
      expect(await adminAct.isMaster(), isTrue);
    });

    test('المفتاح الصحيح يُستورد ويُمكّن الإصدار ثم يُزال', () async {
      expect(await adminAct.importPrivateKey(ownerPair.privateHex), isTrue);
      expect(await adminAct.canIssue(), isTrue);

      await adminAct.forgetPrivateKey();
      expect(await adminAct.canIssue(), isFalse);
    });
  });

  group('التفعيل', () {
    test('رمز صحيح يفعّل الجهاز بدور الفرع', () async {
      final state = await branchAct.activate(await issue(branchAct));

      expect(state.ok, isTrue, reason: state.reason);
      expect(state.branch, 'اللواء الأول');
      expect(state.role, DeviceRole.branch);
    });

    test('رمز بدور الإدارة يمنح صلاحية إنشاء الحساب', () async {
      await branchAct.activate(await issue(branchAct, role: DeviceRole.master));

      final state = await branchAct.current();
      expect(state!.role, DeviceRole.master);
    });

    test('جهاز الفرع ليس جهاز إدارة', () async {
      await branchAct.activate(await issue(branchAct));
      final state = await branchAct.current();
      expect(state!.role, DeviceRole.branch);
    });

    test('رمز صادر لجهاز آخر يُرفض', () async {
      final token = await issue(adminAct);
      final state = await branchAct.activate(token);

      expect(state.ok, isFalse);
      expect(state.reason, contains('جهاز آخر'));
    });

    test('ترقية الدور في الرمز تُسقط التوقيع', () async {
      final token = await issue(branchAct, compact: false);
      final parts = token.split('|')..[4] = DeviceRole.master.name;

      final state = await branchAct.verify(
        parts.join('|'),
        expectDeviceId: await branchAct.deviceId(),
      );
      expect(state.ok, isFalse, reason: 'رفع الصلاحية يجب أن يُكشف');
    });

    test('تمديد تاريخ الانتهاء يُسقط التوقيع', () async {
      final token = await issue(branchAct, compact: false);
      final parts = token.split('|');
      parts[5] = '${int.parse(parts[5]) + 31536000000}';

      final digestOk = ESign.verifyRawWithKey(
        publicKeyB64: ownerPair.publicB64,
        digest: _digestOf(parts),
        rawSignature: _sigOf(parts),
      );
      expect(digestOk, isFalse, reason: 'التوقيع يشمل تاريخ الانتهاء');
    });

    test('استيراد مفتاح لا يطابق المدفون يُرفض', () async {
      final impostor = ESign.generateKeyPair();
      expect(await adminAct.importPrivateKey(impostor.privateHex), isFalse);
      expect(await adminAct.canIssue(), isFalse, reason: 'لا إصدار بمفتاح دخيل');
    });

    test('رمز مزوَّر بمفتاح آخر يُرفض عند التفعيل', () async {
      // يُبنى الرمز يدويًا بمفتاح دخيل، تخطّيًا لرفض الاستيراد.
      final impostor = ESign.generateKeyPair();
      final device = await branchAct.deviceId();
      final branchB64 = base64Url.encode(utf8.encode('اللواء الأول'));
      final expiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
      final sig = ESign.signRawWithKey(
        privateHex: impostor.privateHex,
        digest: _digest(device, branchB64, DeviceRole.branch.name, expiry),
      );
      final forged = [
        DeviceActivation.prefix,
        ESign.keyIdOf(ownerPair.publicB64),
        device,
        branchB64,
        DeviceRole.branch.name,
        '$expiry',
        base64Url.encode(sig),
      ].join('|');

      final state = await branchAct.activate(forged);

      expect(state.ok, isFalse);
      expect(state.reason, contains('غير صادر عن إدارة النظام'));
      expect(await branchAct.isActivated(), isFalse);
    });

    test('رمز منتهي الصلاحية يُرفض برسالة تطلب رمزًا جديدًا', () async {
      final expired = await issue(branchAct, valid: const Duration(days: -1));

      final state = await branchAct.verify(expired, expectDeviceId: await branchAct.deviceId());

      expect(state.ok, isFalse);
      expect(state.reason, contains('انتهت صلاحية'));
      expect(state.branch, 'اللواء الأول', reason: 'البيانات تُقرأ رغم الانتهاء');
    });

    test('رمز مشوّه لا يرمي استثناء بل يعيد سبب الرفض', () async {
      for (final bad in ['', 'نص', 'IMDACT1|a|b', 'IMDACT1|a|b|c|d|e|f|g']) {
        final state = await branchAct.verify(bad, expectDeviceId: 'ABCD2345');
        expect(state.ok, isFalse, reason: bad);
        expect(state.reason, isNotEmpty);
      }
    });

    test('إلغاء التفعيل يمحو الرمز المحفوظ', () async {
      await branchAct.activate(await issue(branchAct));
      expect(await branchAct.current(), isNotNull);

      await branchAct.deactivate();

      expect(await branchAct.current(), isNull);
    });

    test('الرمز كله ASCII فلا يتوقف على ترميز الماسح', () async {
      final token = await issue(branchAct);
      expect(token.codeUnits.every((c) => c < 128), isTrue, reason: token);
    });
  });

  group('الرمز المضغوط IMDACT2', () {
    test('يُصدَر مضغوطًا ويفعّل الجهاز كالقديم تمامًا', () async {
      final token = await issue(branchAct);
      expect(token, startsWith('IMDACT2.'));

      final state = await branchAct.activate(token);
      expect(state.ok, isTrue, reason: state.reason);
      expect(state.branch, 'اللواء الأول');
      expect(state.role, DeviceRole.branch);
      expect(state.deviceId, await branchAct.deviceId());
    });

    test('أقصر من القديم', () async {
      final compact = await issue(branchAct);
      final legacy = await issue(branchAct, compact: false);
      expect(legacy, startsWith('IMDACT1|'));
      // التوقيع (٦٤ بايتًا ⇒ ٨٦ حرفًا) هو الحدّ الأدنى؛ والباقي هو ما يُضغط.
      expect(compact.length, lessThan(legacy.length * 0.9),
          reason: '${compact.length} مقابل ${legacy.length}');
    });

    test('الرمز القديم يبقى مقبولًا', () async {
      final legacy = await issue(branchAct, compact: false);
      expect((await branchAct.activate(legacy)).ok, isTrue);
    });

    test('دور الإدارة والانتهاء يصلان كما صدرا', () async {
      final token = await issue(branchAct, role: DeviceRole.master, valid: const Duration(days: 90));
      final state = await branchAct.verify(token, expectDeviceId: await branchAct.deviceId());
      expect(state.ok, isTrue, reason: state.reason);
      expect(state.role, DeviceRole.master);
      final days = state.expiresAt!.difference(DateTime.now()).inDays;
      expect(days, inInclusiveRange(88, 90));
    });

    test('العبث ببايت واحد يُسقطه: لا يُقبل ولا يرمي', () async {
      final token = await issue(branchAct);
      final body = token.substring('IMDACT2.'.length);
      // نقلب حرفًا في منتصف الحمولة (الدور أو الانتهاء أو الفرع أو التوقيع).
      for (final i in [2, 9, 12, body.length ~/ 2, body.length - 3]) {
        final flipped = body.substring(0, i) +
            (body[i] == 'A' ? 'B' : 'A') +
            body.substring(i + 1);
        final state = await branchAct.verify('IMDACT2.$flipped',
            expectDeviceId: await branchAct.deviceId());
        expect(state.ok, isFalse, reason: 'الموضع $i');
      }
    });

    test('رمزٌ مبتور أو بحمولة فارغة يعيد سبب الرفض', () async {
      for (final bad in ['IMDACT2.', 'IMDACT2.AAAA', 'IMDACT2.!!!!', 'IMDACT2']) {
        final state = await branchAct.verify(bad, expectDeviceId: 'ABCD2345');
        expect(state.ok, isFalse, reason: bad);
        expect(state.reason, isNotEmpty);
      }
    });

    test('رمزٌ صادر لجهاز آخر يُرفض بالصيغة المضغوطة أيضًا', () async {
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherAct = DeviceActivation(other, ownerPublicKey: ownerPair.publicB64);
      final token = await issue(otherAct);

      final state = await branchAct.verify(token, expectDeviceId: await branchAct.deviceId());
      expect(state.ok, isFalse);
      expect(state.reason, contains('جهاز آخر'));
    });

    test('فرعٌ بحروف عربية طويلة يُصدَر ويُقرأ سليمًا', () async {
      await adminAct.importPrivateKey(ownerPair.privateHex);
      const branchName = 'اللواء الأول مشاة — الكتيبة الثالثة / السرية الرابعة';
      final token = await adminAct.issue(
        deviceId: await branchAct.deviceId(),
        branch: branchName,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      final state = await branchAct.verify(token!, expectDeviceId: await branchAct.deviceId());
      expect(state.ok, isTrue, reason: state.reason);
      expect(state.branch, branchName);
    });
  });

  group('سجلّ الأجهزة والإلغاء', () {
    setUp(() async => adminAct.importPrivateKey(ownerPair.privateHex));

    Future<void> issueNamed(String id, String name) => adminAct.issue(
          deviceId: id,
          name: name,
          branch: 'الفرع',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );

    test('كل إصدارٍ يُسجَّل بالاسم والفرع والانتهاء', () async {
      await issueNamed('ABCD2345', 'حاسوب المخزن');
      await issueNamed('WXYZ6789', 'هاتف المشرف');

      final list = await adminAct.registry();
      expect(list.length, 2);
      expect(list.map((d) => d.name), containsAll(['حاسوب المخزن', 'هاتف المشرف']));
      expect(list.every((d) => d.status == IssuedStatus.active), isTrue);
    });

    test('إعادة الإصدار لجهاز مسجَّل لا تكرّره وتحفظ اسمه', () async {
      await issueNamed('ABCD2345', 'حاسوب المخزن');
      await issueNamed('ABCD2345', '');

      final list = await adminAct.registry();
      expect(list.length, 1);
      expect(list.single.name, 'حاسوب المخزن');
    });

    test('إعادة التسمية والحذف', () async {
      await issueNamed('ABCD2345', 'قديم');
      await adminAct.renameIssued('ABCD2345', '  جديد  ');
      expect((await adminAct.registry()).single.name, 'جديد');

      await adminAct.removeIssued('ABCD2345');
      expect(await adminAct.registry(), isEmpty);
    });

    test('الإلغاء يظهر حالةً ويُعاد بإعادة التفعيل', () async {
      await issueNamed('ABCD2345', 'جهاز');
      await adminAct.setRevoked('ABCD2345', true);
      expect((await adminAct.registry()).single.status, IssuedStatus.revoked);

      await adminAct.setRevoked('ABCD2345', false);
      expect((await adminAct.registry()).single.status, IssuedStatus.active);
    });

    test('حذف السطر لا يرفع الإلغاء', () async {
      await issueNamed('ABCD2345', 'جهاز');
      await adminAct.setRevoked('ABCD2345', true);
      await adminAct.removeIssued('ABCD2345');
      expect(await adminAct.isRevoked('ABCD2345'), isTrue);
    });

    test('جهاز مفعَّل يتوقف حين يصله إلغاؤه بالمزامنة ويعود حين يُرفع', () async {
      final token = await issue(branchAct);
      await branchAct.activate(token);
      expect(await branchAct.isActivated(), isTrue);
      final id = await branchAct.deviceId();

      await adminAct.setRevoked(id, true);
      await branchAct.mergeRevocations(await adminAct.revocationsForSync());

      expect(await branchAct.isActivated(), isFalse);
      expect((await branchAct.current())?.reason, contains('أُلغي'));

      await adminAct.setRevoked(id, false);
      await branchAct.mergeRevocations(await adminAct.revocationsForSync());
      expect(await branchAct.isActivated(), isTrue);
    });

    test('الدمج يأخذ الأحدث ختمًا ولا يتراجع إلى أقدم', () async {
      // القرارات موقَّعةٌ من المالك: الوارد بلا توقيع يُرفض (`revocation_guard`).
      String sig(String id, bool revoked, int at) => base64Url.encode(ESign.signRawWithKey(
            privateHex: ownerPair.privateHex,
            digest: DeviceActivation.revocationDigest(deviceId: id, revoked: revoked, atMs: at),
          ));

      await branchAct.mergeRevocations({
        'AAAA2222': {'revoked': true, 'at': 2000, 'sig': sig('AAAA2222', true, 2000)},
      });
      final changed = await branchAct.mergeRevocations({
        // أقدم: يُهمَل قبل أن يُنظر في توقيعه.
        'AAAA2222': {'revoked': false, 'at': 1000, 'sig': sig('AAAA2222', false, 1000)},
        'BBBB3333': {'revoked': true, 'at': 500, 'sig': sig('BBBB3333', true, 500)},
      });
      expect(changed, 1);
      expect(await branchAct.isRevoked('AAAA2222'), isTrue);
      expect(await branchAct.isRevoked('BBBB3333'), isTrue);
    });

    test('حمولة إلغاء مشوّهة لا تسقط', () async {
      expect(await branchAct.mergeRevocations('نص'), 0);
      expect(await branchAct.mergeRevocations({'X': 5, 'Y': {'at': 'z'}}), isA<int>());
    });
  });
}

/// يعيد بناء البصمة من أجزاء الرمز، لفحص التوقيع في الاختبارات.
Uint8List _digestOf(List<String> parts) => _digest(parts[2], parts[3], parts[4], int.parse(parts[5]));

Uint8List _sigOf(List<String> parts) => base64Url.decode(parts[6]);

Uint8List _digest(String device, String branchB64, String role, int expiry) =>
    Uint8List.fromList(sha256.convert(utf8.encode('ACT1:$device:$branchB64:$role:$expiry')).bytes);
