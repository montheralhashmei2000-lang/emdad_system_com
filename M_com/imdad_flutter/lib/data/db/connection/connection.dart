import 'package:drift/drift.dart';

export 'connection_native.dart' if (dart.library.js_interop) 'connection_web.dart';

/// واجهة موحّدة لفتح قاعدة البيانات: ملف SQLite على الأجهزة،
/// وقاعدة داخل المتصفح عند التجربة في كروم.
typedef DatabaseOpener = QueryExecutor Function();
