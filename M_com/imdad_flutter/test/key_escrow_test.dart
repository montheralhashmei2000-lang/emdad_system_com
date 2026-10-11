import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/backup/key_escrow.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/backup_crypto.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:path/path.dart' as p;

/// البند H-2 في تدقيق 2026-10-10، وقرار المالك في 2026-10-11: ملف استرداد
/// مفتاح القاعدة على USB، بكلمة مرورٍ يختارها المالك، يُحدَّث دوريًّا.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final key = 'c3' * 32;

  test('يُختم ويُفتح بكلمة مروره، ويحمل معرّف الجهاز', () {
    final bytes = KeyEscrow.seal(keyHex: key, deviceId: 'K7QX2M9P', password: 'safe-pass-1');
    final opened = KeyEscrow.open(bytes, 'safe-pass-1');
    expect(opened.keyHex, key);
    expect(opened.deviceId, 'K7QX2M9P');
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(key)), reason: 'المفتاح صريحٌ في الملف');
  });

  test('كلمة مرورٍ خاطئة أو قصيرة تُرفض برسالة', () {
    final bytes = KeyEscrow.seal(keyHex: key, deviceId: 'D', password: 'safe-pass-1');
    expect(() => KeyEscrow.open(bytes, 'wrong-pass'), throwsA(isA<BackupError>()));
    expect(() => KeyEscrow.seal(keyHex: key, deviceId: 'D', password: 'short'), throwsA(isA<BackupError>()));
  });

  test('نسخةٌ احتياطية عادية ليست ملف استرداد، وملف الاسترداد ليس نسخةً تُستعاد', () async {
    final backup = BackupCrypto.seal(jsonEncode({'items': []}), 'safe-pass-1');
    expect(() => KeyEscrow.open(backup, 'safe-pass-1'), throwsA(isA<BackupError>()));

    final dir = Directory.systemTemp.createTempSync('imdad-escrow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'k.imdkey'))
      ..writeAsBytesSync(KeyEscrow.seal(keyHex: key, deviceId: 'D', password: 'safe-pass-1'));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      LegacyImporter(db).importFile(file, password: 'safe-pass-1'),
      throwsA(isA<BackupError>().having((e) => e.message, 'message', contains('استرداد'))),
    );
  });

  test('التذكير بالتحديث بعد ٩٠ يومًا، والتاريخ محليٌّ لا يُزامَن', () async {
    final now = DateTime(2026, 10, 11);
    expect(KeyEscrow.isDue(null, now: now), isTrue);
    expect(KeyEscrow.isDue(now.subtract(const Duration(days: 10)), now: now), isFalse);
    expect(KeyEscrow.isDue(now.subtract(const Duration(days: 91)), now: now), isTrue);
    expect(SettingsRepo.localOnlyKeys, contains(KeyEscrow.settingsKey));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await KeyEscrow.markSaved(db, now: now);
    expect(await KeyEscrow.lastSaved(db), now);
  });
}
