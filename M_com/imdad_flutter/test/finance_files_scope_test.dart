import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/repos/finance_files.dart';
import 'package:path/path.dart' as p;

/// حذف المرفقات المالية محصورٌ في مجلد المرفقات.
///
/// `attachmentsJson` في العهد و`attachPath` في الإخلاءات عمودان **مزامَنان**،
/// فالمسار الذي يُطلب حذفه قد يكون كتبه جهازٌ آخر. وكان الحذف يُنفَّذ على أي
/// مسار، فقرينٌ مخترَق يضع مسار أي ملفٍّ على قرص المستقبِل ويمحوه له أولُ
/// مشغّلٍ يُزيل المرفق من النموذج.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fin_scope_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    await tmp.delete(recursive: true);
  });

  /// ملفٌّ خارج مجلد المرفقات، كأنه مستندُ المستخدم الخاص.
  Future<File> outsider(String name) async {
    final f = File(p.join(tmp.path, name));
    await f.writeAsString('مستندٌ مهم لا يجوز حذفه');
    return f;
  }

  test('مرفقٌ داخل المجلد يُحذف', () async {
    final inside = File(p.join((await FinanceFiles.dir()).path, 'custody_1.pdf'));
    await inside.writeAsString('مرفق');
    expect(await inside.exists(), isTrue);

    await FinanceFiles.delete(inside.path);
    expect(await inside.exists(), isFalse);
  });

  test('ملفٌّ خارج المجلد لا يُحذف', () async {
    final victim = await outsider('اعتماد_الميزانية.docx');

    await FinanceFiles.delete(victim.path);

    expect(await victim.exists(), isTrue, reason: 'حُذف ملفٌّ خارج مجلد المرفقات');
  });

  test('الخروج بـ«..» لا يَخدع الحارس', () async {
    final victim = await outsider('سرّي.pdf');
    final root = (await FinanceFiles.dir()).path;
    // مسارٌ يبدأ بالمجلد نصًّا ويخرج عنه فعلًا — ولهذا تُسوّى المسارات لا تُقارن نصًّا.
    final sneaky = p.join(root, '..', 'سرّي.pdf');

    await FinanceFiles.delete(sneaky);

    expect(await victim.exists(), isTrue, reason: 'تجاوز الحارس بمسارٍ نسبي');
  });

  test('المجلد نفسه لا يُحذف', () async {
    final root = await FinanceFiles.dir();

    await FinanceFiles.delete(root.path);

    expect(await root.exists(), isTrue);
  });

  test('مسارٌ فارغ أو مجهول يمرّ بلا خطأ', () async {
    await FinanceFiles.delete('');
    await FinanceFiles.delete(p.join((await FinanceFiles.dir()).path, 'لا-وجود-له.pdf'));
  });

  test('ما يحفظه save يُحذف بـdelete (الدورة كاملة)', () async {
    final src = File(p.join(tmp.path, 'فاتورة.pdf'));
    await src.writeAsBytes(List<int>.generate(64, (i) => i));

    final a = await FinanceFiles.save(src.path, prefix: 'custody');
    expect(await File(a.path).exists(), isTrue);

    await FinanceFiles.delete(a.path);
    expect(await File(a.path).exists(), isFalse);
    // الأصل الذي اختاره المستخدم لا يُمَس: المحفوظ نسخةٌ.
    expect(await src.exists(), isTrue);
  });
}
