/// العد بالمسح في الجرد: كل مسحة لباركود صنف = قطعة واحدة بأصغر وحداته.
library;

/// نتيجة مطابقة باركود ممسوح مع أصناف النظام وسطور أمر الجرد.
sealed class ScanResult {
  const ScanResult();
}

/// الصنف مدرج في أمر الجرد.
class ScanCounted extends ScanResult {
  const ScanCounted(this.itemId, this.lineId);
  final String itemId;
  final String lineId;
}

/// الصنف معروف لكنه غير مدرج في الأمر (صنف مكتشف).
class ScanNotInOrder extends ScanResult {
  const ScanNotInOrder(this.itemId);
  final String itemId;
}

/// لا صنف بهذا الباركود ولا بهذا الكود.
class ScanUnknown extends ScanResult {
  const ScanUnknown(this.code);
  final String code;
}

class StocktakeScan {
  const StocktakeScan._();

  /// يطابق الباركود أولًا ثم كود الصنف (قارئ USB أو إدخال يدوي للكود).
  static ScanResult resolve(
    String raw,
    Iterable<({String id, String code, String barcode})> items,
    Map<String, String> lineByItem,
  ) {
    final code = raw.trim();
    if (code.isEmpty) return ScanUnknown(code);
    String? itemId;
    for (final it in items) {
      if (it.barcode.isNotEmpty && it.barcode == code) {
        itemId = it.id;
        break;
      }
    }
    if (itemId == null) {
      final lower = code.toLowerCase();
      for (final it in items) {
        if (it.code.isNotEmpty && it.code.toLowerCase() == lower) {
          itemId = it.id;
          break;
        }
      }
    }
    if (itemId == null) return ScanUnknown(code);
    final line = lineByItem[itemId];
    return line == null ? ScanNotInOrder(itemId) : ScanCounted(itemId, line);
  }

  /// العدّ بعد مسحة واحدة: +1 في أصغر وحدة ([smallestUnit])، وبقية الوحدات كما هي.
  static Map<String, double> increment(Map<String, double> counts, String smallestUnit) =>
      {...counts, smallestUnit: (counts[smallestUnit] ?? 0) + 1};
}

/// يمنع احتساب مسحة واحدة مرتين: الكاميرا تقرأ الباركود نفسه عدة مرات في
/// الثانية ما دام أمامها. التكرار خلال [window] يُتجاهل، وبعدها يُعدّ قطعة جديدة.
class ScanDebouncer {
  ScanDebouncer({this.window = const Duration(milliseconds: 1200), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;
  String _last = '';
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// هل تُحتسب هذه القراءة؟
  bool accept(String code) {
    final now = _clock();
    if (code == _last && now.difference(_at) < window) {
      _at = now; // ما دام الباركود أمام الكاميرا تمتد المهلة.
      return false;
    }
    _last = code;
    _at = now;
    return true;
  }
}
