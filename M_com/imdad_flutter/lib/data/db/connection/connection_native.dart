import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db_cipher.dart';

/// قاعدة البيانات على أندرويد وويندوز: ملف SQLite **مشفَّر** (SQLCipher) في
/// مجلد بيانات التطبيق، مفتاحه في مخزن اعتمادات النظام (انظر [DbCipher]).
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'imdad.sqlite'));

    final key = await DbCipher.loadKey();
    // الترحيل يجري على هذا الخيط، فيحتاج توجيه المكتبة هنا أيضًا.
    DbCipher.setupIsolate();
    await DbCipher.migratePlainFile(file, key);

    return NativeDatabase.createInBackground(
      file,
      isolateSetup: DbCipher.setupIsolate,
      // المفتاح أول ما يُنفَّذ على الاتصال، قبل أي قراءة.
      setup: (db) => DbCipher.applyKey(db, key),
    );
  });
}
