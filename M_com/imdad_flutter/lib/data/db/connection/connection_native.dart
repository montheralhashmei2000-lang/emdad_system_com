import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db_cipher.dart';
import '../pre_migration_backup.dart';

/// قاعدة البيانات على أندرويد وويندوز: ملف SQLite **مشفَّر** (SQLCipher) في
/// مجلد بيانات التطبيق، مفتاحه في مخزن اعتمادات النظام (انظر [DbCipher]).
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, DbCipher.fileName));

    final key = await DbCipher.loadKey();
    // الترحيل يجري على هذا الخيط، فيحتاج توجيه المكتبة هنا أيضًا.
    DbCipher.setupIsolate();
    await DbCipher.migratePlainFile(file, key);

    return NativeDatabase.createInBackground(
      file,
      isolateSetup: DbCipher.setupIsolate,
      setup: (db) {
        // المفتاح أول ما يُنفَّذ على الاتصال، قبل أي قراءة.
        DbCipher.applyKey(db, key);
        // نسخة كاملة من الملف قبل أن يُرحِّله drift؛ فشلها يمنع الفتح والترحيل معًا.
        PreMigrationBackup.createIfNeeded(db, file);
      },
    );
  });
}
