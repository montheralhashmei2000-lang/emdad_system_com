import 'dart:math';

/// مولّد معرّفات فريد.
///
/// الاعتماد على الوقت وحده لا يكفي: ساعة ويندوز دقّتها نحو ملّي ثانية، فسجلّان
/// يُكتبان في اللحظة نفسها — كسطور السند في حلقة واحدة — يأخذان المعرّف نفسه
/// فيطمس أحدهما الآخر. لذلك يُضاف عدّاد تصاعدي وقيمة عشوائية.
class Ids {
  Ids._();

  static int _counter = 0;
  static final Random _random = Random();

  /// معرّف فريد بصيغة: البادئة-الوقت-العداد-عشوائي
  static String next(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = (_counter = (_counter + 1) & 0xFFFFFF).toRadixString(36);
    final rand = _random.nextInt(1 << 24).toRadixString(36);
    return '$prefix-$now-$seq$rand';
  }

  /// معرّفٌ **حتميّ** من مفتاحٍ طبيعي — لسجلٍّ هو «الشيء نفسه» أينما أُنشئ:
  /// سجل معسكرٍ لشهر، تصفية شهر، حدّ مخزون صنفٍ في مستودع، رصيدٌ افتتاحي.
  ///
  /// جهازان يُنشئان السجلَّ نفسه قبل أن يتزامنا يصلان إلى المعرّف نفسه، فيلتقي
  /// الصفّان بالدمج العادي (الأحدث يفوز) بدل أن يتصادم الفهرس الفريد ويُجهض
  /// المزامنة (H-1)، أو يبقى صفّان يُجمعان (H-7). الأجزاء تُرمَّز فلا يلتبس
  /// فاصلٌ داخل اسمٍ بحدٍّ بين جزأين.
  static String natural(String prefix, List<Object> parts) =>
      '$prefix:${parts.map((p) => Uri.encodeComponent('$p')).join(':')}';
}
