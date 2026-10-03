/// كلمةٌ قرأها OCR مع موضعها في الصورة. الموضع هو ما يعيد بناء **صفوف الجدول**:
/// Tesseract يفصل أحيانًا عمود الأسماء عن عمود الأرقام (في الجداول العربية)، فلا
/// يصحّ الاعتماد على ترتيب النص، بل على التقاء الكلمات في الارتفاع نفسه.
class OcrWord {
  const OcrWord(this.text, this.x0, this.y0, this.x1, this.y1);

  final String text;
  final double x0, y0, x1, y1;

  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  double get height => y1 - y0;
}

/// يقرأ مخرجات hOCR (من Tesseract) إلى كلمات بمواضعها.
List<OcrWord> parseHocr(String hocr) {
  final out = <OcrWord>[];
  final word = RegExp(r'''<span[^>]*class=["']ocrx_word["'][^>]*title=["']bbox (\d+) (\d+) (\d+) (\d+)[^"']*["'][^>]*>(.*?)</span>''', dotAll: true);
  for (final m in word.allMatches(hocr)) {
    final text = _unescape(m[5]!.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
    if (text.isEmpty) continue;
    out.add(OcrWord(text, double.parse(m[1]!), double.parse(m[2]!), double.parse(m[3]!), double.parse(m[4]!)));
  }
  return out;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");

bool _isArabicWord(String t) => RegExp(r'[\u0600-\u06FF]').hasMatch(t);

int _letters(String t) => RegExp(r'[\u0600-\u06FFA-Za-z]').allMatches(t).length;

/// مقطعٌ من سطر: كلماتٌ متجاورة (خلية جدول أو عبارة)، تفصله عن غيره فجوةٌ أكبر من المسافة المعتادة.
class _Segment {
  _Segment(this.words);
  final List<OcrWord> words;

  double get cx => words.fold<double>(0, (s, w) => s + w.cx) / words.length;

  /// كلمات المقطع بحسب لغته: أغلبه عربي ⇒ من اليمين لليسار، وإلا من اليسار لليمين.
  String get text {
    final arabic = words.where((w) => _isArabicWord(w.text)).length;
    final ordered = [...words]..sort((a, b) => arabic * 2 >= words.length ? b.cx.compareTo(a.cx) : a.cx.compareTo(b.cx));
    return ordered.map((w) => w.text).join(' ');
  }

  int get letters => words.fold<int>(0, (s, w) => s + _letters(w.text));
}

/// يجمع الكلمات في **أسطر** بحسب التقائها في الارتفاع، ثم يبني كل سطرٍ من مقاطع
/// (خلايا) مرتبةً بحيث يخرج صفّ الجدول **بالترتيب المنطقي: الاسم، الوحدة، الكمية،
/// السعر، الإجمالي** سواء رُسم الجدول من اليمين (العربي المعتاد) أو من اليسار،
/// وسواء قسّم OCR أعمدته إلى كتل منفصلة. اتجاه الترتيب يُستنتج من موضع خلية
/// الاسم (أطول نصٍّ حرفيٍّ في السطر) بالنسبة لبقية الخلايا، وتصوّت الأسطر لاتجاه
/// الصفحة فيتبعه سطرٌ لم يُقرأ اسمه.
List<String> wordsToLines(List<OcrWord> words) {
  if (words.isEmpty) return const [];
  final heights = [for (final w in words) w.height]..sort();
  final med = heights[heights.length ~/ 2];
  final sorted = [...words]..sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<OcrWord>>[];
  var mean = 0.0;
  for (final w in sorted) {
    final tol = 0.55 * (med > w.height ? med : w.height);
    if (rows.isNotEmpty && (w.cy - mean).abs() <= tol) {
      rows.last.add(w);
      mean = rows.last.fold<double>(0, (s, e) => s + e.cy) / rows.last.length;
    } else {
      rows.add([w]);
      mean = w.cy;
    }
  }

  // 1) المقاطع لكل سطر.
  final segsPerRow = <List<_Segment>>[];
  for (final row in rows) {
    final byX = [...row]..sort((a, b) => a.x0.compareTo(b.x0));
    final lineH = row.fold<double>(0, (s, w) => s + w.height) / row.length;
    final gap = (lineH * 0.9).clamp(14.0, 1000.0);
    final segs = <_Segment>[];
    var cur = <OcrWord>[byX.first];
    for (var i = 1; i < byX.length; i++) {
      // الفجوة بين أقرب حدّين (المقاطع قد تتداخل قليلًا).
      if (byX[i].x0 - cur.map((w) => w.x1).reduce((a, b) => a > b ? a : b) > gap) {
        segs.add(_Segment(cur));
        cur = [byX[i]];
      } else {
        cur.add(byX[i]);
      }
    }
    segs.add(_Segment(cur));
    segsPerRow.add(segs);
  }

  // 2) تصويت الاتجاه: +1 (تصاعدي: الاسم عند اليسار) / -1 (تنازلي: الاسم عند اليمين).
  final votes = <int?>[];
  var asc = 0, desc = 0;
  for (final segs in segsPerRow) {
    int? v;
    if (segs.length >= 3) {
      var best = 0;
      for (var i = 1; i < segs.length; i++) {
        if (segs[i].letters > segs[best].letters) best = i;
      }
      if (segs[best].letters >= 2) {
        final left = best, right = segs.length - 1 - best;
        if (right > left) v = 1;
        if (left > right) v = -1;
      }
    }
    votes.add(v);
    if (v == 1) asc++;
    if (v == -1) desc++;
  }
  final arabicWords = words.where((w) => _isArabicWord(w.text)).length;
  final pageDefault = asc != desc ? (asc > desc ? 1 : -1) : (arabicWords * 2 > words.length ? -1 : 1);

  return [
    for (var r = 0; r < segsPerRow.length; r++)
      (() {
        final dir = votes[r] ?? pageDefault;
        final ordered = [...segsPerRow[r]]..sort((a, b) => dir == 1 ? a.cx.compareTo(b.cx) : b.cx.compareTo(a.cx));
        return ordered.map((s) => s.text).join(' ');
      })(),
  ];
}
