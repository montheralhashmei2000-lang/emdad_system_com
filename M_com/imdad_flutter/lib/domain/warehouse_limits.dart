/// حدود مخزون الصنف في مستودع — التحويل بين الوحدات وحساب الحالة.
///
/// **المشكلة التي يحلّها هذا الملف كلّه: وحدتان لرقم واحد.**
/// الرصيد محفوظ بوحدة الأساس (حبة، كجم)، والمستخدم يفكّر بوحدة التعامل
/// (كرتون، شوال). فلو خُزّن الحد كما كُتب لقُورن كرتونٌ بحبة وظهر مخزونٌ
/// كافٍ وهو نافد، أو العكس. ولو خُزّن بالأساس وحده لعاد إلى من كتبه رقمًا
/// لا يعرفه.
///
/// فالحلّ: يُخزَّن الحدّ **بالأساس** ويُحفظ معه **معامل وحدة الإدخال**،
/// فتُقارن الأرقام بلغةٍ واحدة وتُعرض بلغة صاحبها.
library;

/// حالة الصنف أمام حدوده.
enum LimitStatus {
  /// لا حدّ مضبوط — لا حكم.
  none,

  /// تحت الحد الأدنى.
  low,

  /// فوق الحد الأعلى — مالٌ مجمَّد ومساحةٌ مشغولة.
  over,

  /// ضمن الحدين.
  ok,
}

extension LimitStatusLabel on LimitStatus {
  String get label => switch (this) {
        LimitStatus.none => 'بلا حدود',
        LimitStatus.low => 'تحت الأدنى',
        LimitStatus.over => 'فوق الأعلى',
        LimitStatus.ok => 'ضمن الحدود',
      };

  /// نغمة الشارة في الجداول: err | pend | ok | off.
  String get tone => switch (this) {
        LimitStatus.none => 'off',
        LimitStatus.low => 'err',
        LimitStatus.over => 'pend',
        LimitStatus.ok => 'ok',
      };
}

class WarehouseLimits {
  const WarehouseLimits._();

  /// معاملٌ صالح: غير الموجب يُعامَل ١ فلا تُقسم كميةٌ على صفر.
  static double safeFactor(double factor) => factor > 0 ? factor : 1.0;

  /// من وحدة الإدخال إلى وحدة الأساس.
  static double toBase(double qty, double factor) =>
      round(qty * safeFactor(factor));

  /// من وحدة الأساس إلى وحدة العرض.
  static double fromBase(double base, double factor) =>
      round(base / safeFactor(factor));

  /// ثلاث منازل تكفي أي وحدة تعامل، وتمنع ذيل الكسور العشرية من الظهور.
  static double round(double v) => (v * 1000).round() / 1000;

  /// حالة الرصيد أمام حدّيه — الثلاثة **بوحدة الأساس**.
  ///
  /// الحد صفرٌ يعني «غير مضبوط» لا «صفر قطعة»: مستودعٌ بلا حدّ أدنى لا يُنبَّه
  /// عليه كلما فرغ صنفٌ لا يعني أحدًا.
  static LimitStatus statusOf({
    required double balance,
    required double minStock,
    required double maxStock,
  }) {
    final hasMin = minStock > 0;
    final hasMax = maxStock > 0;
    if (!hasMin && !hasMax) return LimitStatus.none;
    if (hasMin && balance < minStock) return LimitStatus.low;
    if (hasMax && balance > maxStock) return LimitStatus.over;
    return LimitStatus.ok;
  }

  /// كم ينقص لبلوغ الحد الأدنى — صفرٌ إن لم ينقص شيء.
  static double shortfall({required double balance, required double minStock}) {
    if (minStock <= 0 || balance >= minStock) return 0;
    return round(minStock - balance);
  }

  /// كم يزيد عن الحد الأعلى.
  static double surplus({required double balance, required double maxStock}) {
    if (maxStock <= 0 || balance <= maxStock) return 0;
    return round(balance - maxStock);
  }

  /// نسبة الامتلاء إلى الحد الأعلى (0..1 فأكثر)، أو `null` بلا حد أعلى.
  ///
  /// منها يُرسم الشريط: رقمٌ وحده لا يُري الفرق بين «قارب الامتلاء» و«تجاوز».
  static double? fillRatio({required double balance, required double maxStock}) {
    if (maxStock <= 0) return null;
    return balance <= 0 ? 0 : round(balance / maxStock);
  }

  /// تحقّق من سطر حدود قبل حفظه — الأرقام **بوحدة الإدخال**.
  ///
  /// يعيد رسالة الخطأ، أو `null` إن صحّ السطر.
  static String? validate({
    required String itemId,
    required double min,
    required double max,
  }) {
    if (itemId.trim().isEmpty) return 'اختر الصنف';
    if (min < 0 || max < 0) return 'الحدود لا تكون سالبة';
    if (min == 0 && max == 0) {
      return 'اضبط حدًّا واحدًا على الأقل — أو احذف السطر';
    }
    // الأعلى دون الأدنى يجعل الصنف «تحت الأدنى وفوق الأعلى» معًا، فلا يُفهم
    // منه قرار.
    if (min > 0 && max > 0 && max < min) {
      return 'الحد الأعلى أقل من الأدنى';
    }
    return null;
  }

  /// تحقّق من دفعة سطور: التكرار يُفسد الحفظ الجماعي صامتًا.
  ///
  /// آخر سطرٍ لصنفٍ مكرر يدهس ما قبله، فيظن المستخدم أنه ضبط حدّين وقد ضبط
  /// واحدًا — ولا يعلم أيّهما بقي.
  static String? validateBatch(List<({String itemId, double min, double max})> rows) {
    if (rows.isEmpty) return 'أضف سطرًا واحدًا على الأقل';
    for (final r in rows) {
      final error = validate(itemId: r.itemId, min: r.min, max: r.max);
      if (error != null) return error;
    }
    final ids = <String>{};
    for (final r in rows) {
      if (!ids.add(r.itemId.trim())) {
        return 'صنف مكرر في الدفعة — ادمج سطريه في سطر واحد';
      }
    }
    return null;
  }
}
