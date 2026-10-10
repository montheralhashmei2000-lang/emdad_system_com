/// الباركود النظامي للأصناف: ١٢ رقمًا = السنة (٤) + يوم-ساعة-دقيقة (٦) + تسلسل (٢).
///
/// مثال: `202610143001` ⇐ سنة 2026، يوم 10، الساعة 14، الدقيقة 30، تسلسل 01.
/// السنة تُؤخذ من الساعة لا من ثابت. التسلسل 01–99 داخل الدقيقة؛ بعد 99
/// ينتقل إلى الدقيقة التالية ويعود إلى 01. الباركودات القديمة (`104…`) لا تُمسّ.
class ItemBarcode {
  ItemBarcode._(this._at, this._seq);

  /// يبدأ من [now] بعد أكبر تسلسل مستعمل في دقيقته ([usedSeqs]: تسلسلات
  /// الباركودات المحفوظة ببادئة تلك الدقيقة، انظر [prefixOf]).
  factory ItemBarcode.startingAt(DateTime now, Iterable<int> usedSeqs) {
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final top = usedSeqs.fold<int>(0, (a, b) => b > a ? b : a);
    final g = ItemBarcode._(at, 1);
    if (top >= maxSeq) {
      g._at = at.add(const Duration(minutes: 1));
    } else {
      g._seq = top + 1;
    }
    return g;
  }

  static const int length = 12;
  static const int maxSeq = 99;

  /// عدد المرشّحين المفحوصين قبل الاستسلام.
  static const int maxAttempts = 10;

  DateTime _at;
  int _seq;

  static String _p2(int v) => v.toString().padLeft(2, '0');

  /// البادئة (١٠ أرقام) لدقيقة [t].
  static String prefixOf(DateTime t) => '${t.year}${_p2(t.day)}${_p2(t.hour)}${_p2(t.minute)}';

  static String format(DateTime t, int seq) => '${prefixOf(t)}${_p2(seq)}';

  /// تسلسل باركودٍ بصيغة النظام ببادئة [prefix]، أو `null` لغيره.
  static int? seqOf(String barcode, String prefix) {
    if (barcode.length != length || !barcode.startsWith(prefix)) return null;
    return int.tryParse(barcode.substring(prefix.length));
  }

  /// المرشّح التالي، ثم يتقدّم المؤشر.
  String take() {
    final out = format(_at, _seq);
    if (_seq >= maxSeq) {
      _seq = 1;
      _at = _at.add(const Duration(minutes: 1));
    } else {
      _seq++;
    }
    return out;
  }

  /// أول مرشّح غير مستعمل خلال [maxAttempts] محاولة؛ وإلا `StateError`.
  Future<String> nextFree(Future<bool> Function(String barcode) taken) async {
    for (var i = 0; i < maxAttempts; i++) {
      final bc = take();
      if (!await taken(bc)) return bc;
    }
    throw StateError('تعذّر توليد باركود غير مكرر بعد $maxAttempts محاولات');
  }
}
