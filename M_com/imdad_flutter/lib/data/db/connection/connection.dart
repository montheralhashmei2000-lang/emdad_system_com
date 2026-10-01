import 'package:drift/drift.dart';

export 'connection_native.dart';

/// واجهة موحّدة لفتح قاعدة البيانات: ملف SQLite مشفَّر على ويندوز وأندرويد.
typedef DatabaseOpener = QueryExecutor Function();
