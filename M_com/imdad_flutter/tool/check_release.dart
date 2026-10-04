// فحص ما قبل بناء نسخة التوزيع — يفشل البناء برسالة واضحة إن كان غير آمن:
//
//   dart run tool/check_release.dart
//
// • مفتاح المالك في `lib/core/security/owner_key.dart` فارغ ⇒ وضع التطوير:
//   التفعيل معطّل والتطبيق يعمل بلا قيد على أي جهاز.
// • `android/key.properties` غائب ⇒ يُوقَّع الـ APK بمفتاح debug.
//
// شغّله قبل `flutter build apk` و`flutter build windows`.
import 'dart:io';

void main() {
  final problems = <String>[];

  final ownerKey = File('lib/core/security/owner_key.dart');
  if (!ownerKey.existsSync()) {
    problems.add('تعذّر العثور على ${ownerKey.path} — شغّل الأمر من جذر المشروع.');
  } else {
    final m = RegExp(r"static const String publicKey\s*=\s*'([^']*)'")
        .firstMatch(ownerKey.readAsStringSync());
    if (m == null) {
      problems.add('تعذّر قراءة OwnerKey.publicKey من owner_key.dart.');
    } else if (m.group(1)!.trim().isEmpty) {
      problems.add('OwnerKey.publicKey فارغ (وضع التطوير: بلا تفعيل). '
          'ولّد مفتاحًا بـ `dart run tool/make_owner_key.dart` وضعه في owner_key.dart.');
    }
  }

  if (!File('android/key.properties').existsSync()) {
    problems.add('android/key.properties غائب: سيُوقَّع الـ APK بمفتاح debug.');
  }

  if (problems.isEmpty) {
    stdout.writeln('✔ فحص الإصدار سليم.');
    return;
  }
  stderr.writeln('✖ فحص الإصدار فشل — لا تبنِ نسخة توزيع:');
  for (final p in problems) {
    stderr.writeln('  • $p');
  }
  exitCode = 1;
}
