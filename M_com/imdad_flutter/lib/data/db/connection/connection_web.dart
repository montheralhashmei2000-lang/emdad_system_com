import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// قاعدة البيانات داخل المتصفح (للتجربة في بيئة التطوير فقط):
/// SQLite مترجَمة إلى WebAssembly، وتُحفظ في تخزين المتصفح.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'imdad',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
