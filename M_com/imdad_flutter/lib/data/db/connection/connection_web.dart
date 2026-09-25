import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// قاعدة البيانات داخل المتصفح: SQLite مترجَمة إلى WebAssembly تُحفظ في تخزين
/// المتصفح — **بلا تشفير**، إذ لا SQLCipher في WebAssembly.
///
/// ولذلك هي أداةُ تجربةٍ في التطوير لا هدفُ إصدار: نسختا ويندوز وأندرويد
/// تحفظان القاعدة مشفَّرةً بمفتاحٍ في مخزن اعتمادات النظام، أما هذه فتضع
/// بيانات الوحدة كاملةً — القوة والأرصدة والمستخدمين — على قرصٍ يقرؤه كلُّ
/// من بلغ الجهاز أو المتصفح. فتُمنع في الإصدار صراحةً بدل أن يُنتجها أحدٌ
/// بـ`flutter build web` ظانًّا أنها كبقية النسخ.
QueryExecutor openConnection() {
  if (!kDebugMode) {
    throw UnsupportedError(
      'نسخة الويب تحفظ البيانات بلا تشفير ولا تصلح للاستخدام الفعلي. '
      'استعمل نسخة ويندوز أو أندرويد.',
    );
  }
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'imdad',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
