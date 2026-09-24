// مولّد مفتاح المالك — يُشغَّل مرة واحدة على جهازك أنت:
//
//   dart run tool/make_owner_key.dart
//
// يطبع المفتاح العام لتضعه في `lib/core/security/owner_key.dart`، ويحفظ
// المفتاح الخاص في ملف **خارج المستودع**. لا تضع المفتاح الخاص في الكود ولا
// في git: من يملكه يستطيع تفعيل أي جهاز.
import 'dart:io';

import 'package:imdad/core/security/esign.dart';

void main(List<String> args) {
  final pair = ESign.generateKeyPair();
  final keyId = ESign.keyIdOf(pair.publicB64);

  final target = args.isNotEmpty ? args.first : r'D:\Emdad_Repository\imdad_keystore';
  final dir = Directory(target)..createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}owner-private-key.txt');

  if (file.existsSync()) {
    stderr.writeln('✖ يوجد مفتاح مالك بالفعل في ${file.path}');
    stderr.writeln('  استبداله يُبطل تفعيل كل الأجهزة القائمة. احذفه يدويًا إن كنت متأكدًا.');
    exitCode = 1;
    return;
  }

  file.writeAsStringSync(
    'IMDAD OWNER PRIVATE KEY\n'
    'keyId: $keyId\n'
    'created: ${DateTime.now().toIso8601String()}\n'
    'private: ${pair.privateHex}\n'
    'public: ${pair.publicB64}\n',
    flush: true,
  );

  stdout.writeln('✔ أُنشئ مفتاح المالك.');
  stdout.writeln('');
  stdout.writeln('المفتاح الخاص حُفظ في:');
  stdout.writeln('  ${file.path}');
  stdout.writeln('  ⚠ انسخه إلى مكان آمن خارج هذا الجهاز. ضياعه = لا تفعيل لأي جهاز جديد.');
  stdout.writeln('');
  stdout.writeln('ضع هذا في lib/core/security/owner_key.dart ثم أعد البناء:');
  stdout.writeln('');
  stdout.writeln("  static const String publicKey = '${pair.publicB64}';");
  stdout.writeln('');
  stdout.writeln('معرّف المفتاح: $keyId');
}
