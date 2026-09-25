/// قواعد الأصول الثابتة — التحقق والتسميات وحساب العمر.
///
/// منطق خالص بلا قاعدة بيانات ولا واجهة، فيُختبر وحده كما تُختبر [StockLedger]
/// و[AccessControl]: القاعدة التي لا تُختبر تُخرق.
library;

class AssetType {
  static const String kitchen = 'kitchen';
  static const String oven = 'oven';
  static const String warehouse = 'warehouse';
  static const String equipment = 'equipment';
  static const String vehicle = 'vehicle';

  static const List<String> all = [kitchen, oven, warehouse, equipment, vehicle];

  static const Map<String, String> labels = {
    kitchen: 'مطبخ',
    oven: 'فرن',
    warehouse: 'مستودع',
    equipment: 'معدات',
    vehicle: 'آلية',
  };

  /// أيقونة من مكتبة النظام لكل نوع.
  static const Map<String, String> icons = {
    kitchen: 'utensils',
    oven: 'flame',
    warehouse: 'warehouse',
    equipment: 'wrench',
    vehicle: 'truck',
  };

  static String label(String v) => labels[v] ?? v;
}

class AssetStatus {
  static const String isNew = 'NEW';
  static const String used = 'USED';
  static const String maintenance = 'MAINTENANCE';
  static const String damaged = 'DAMAGED';
  static const String consumed = 'CONSUMED';

  static const List<String> all = [isNew, used, maintenance, damaged, consumed];

  static const Map<String, String> labels = {
    isNew: 'جديد',
    used: 'مستعمل',
    maintenance: 'تحت الصيانة',
    damaged: 'تالف',
    consumed: 'مستهلك',
  };

  /// الحالات التي يخرج بها الأصل من الخدمة — لا يُسلَّم عهدةً وهو كذلك.
  static const List<String> outOfService = [damaged, consumed];

  static String label(String v) => labels[v] ?? v;
}

/// حالة عمر الأصل مقارنةً بعمره الافتراضي.
enum AssetLife {
  /// لا تاريخ اقتناء أو لا عمر افتراضي — لا حكم.
  unknown,

  /// في نصف عمره الأول.
  healthy,

  /// بقي أقل من [AssetRules.warnWithin].
  nearingEnd,

  /// انقضى عمره الافتراضي.
  expired,
}

class AssetRules {
  const AssetRules._();

  /// يُنبَّه على الأصل قبل انقضاء عمره بشهر: مدةٌ تكفي لطلب بديل واستلامه،
  /// ولا تطول فيصير التنبيه ضجيجًا يُتجاهل.
  static const Duration warnWithin = Duration(days: 30);

  // ───────────────────────── التحقق

  static String? validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'اسم الأصل مطلوب';
    if (v.length < 3) return 'اسم الأصل ثلاثة أحرف على الأقل';
    return null;
  }

  static String? validateType(String? value) {
    if (value == null || value.isEmpty) return 'نوع الأصل مطلوب';
    if (!AssetType.all.contains(value)) return 'نوع الأصل غير معروف';
    return null;
  }

  static String? validateValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final d = double.tryParse(v);
    if (d == null) return 'القيمة يجب أن تكون رقمًا';
    if (d < 0) return 'القيمة لا تكون سالبة';
    return null;
  }

  static String? validateLifespan(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null) return 'العمر الافتراضي يجب أن يكون عدد أشهر';
    if (n <= 0) return 'العمر الافتراضي أكبر من صفر';
    if (n > 1200) return 'العمر الافتراضي لا يتجاوز مئة سنة';
    return null;
  }

  /// [date] بصيغة yyyy-MM-dd. الفراغ مقبول، والمستقبل مرفوض.
  static String? validateAcquisitionDate(String? date, {DateTime? now}) {
    final v = (date ?? '').trim();
    if (v.isEmpty) return null;
    final parsed = DateTime.tryParse(v);
    if (parsed == null) return 'تاريخ الاقتناء غير صالح';
    final today = now ?? DateTime.now();
    if (parsed.isAfter(DateTime(today.year, today.month, today.day))) {
      return 'تاريخ الاقتناء لا يكون في المستقبل';
    }
    return null;
  }

  /// الأصل يقف في مكان: مرفق أو وحدة مستفيدة أو مستودع. أصلٌ بلا موضع لا
  /// يُجرد ولا يُسأل عنه أحد.
  static String? validatePlacement({
    String facilityId = '',
    String beneficiaryUnitId = '',
    String warehouse = '',
  }) {
    if (facilityId.trim().isEmpty &&
        beneficiaryUnitId.trim().isEmpty &&
        warehouse.trim().isEmpty) {
      return 'حدّد موضع الأصل: مرفق أو وحدة مستفيدة أو مستودع';
    }
    return null;
  }

  // ───────────────────────── العمر

  /// تاريخ انتهاء العمر الافتراضي، أو `null` إن لم يكن محسوبًا.
  static DateTime? expiryOf({required String acquisitionDate, required int lifespanMonths}) {
    if (lifespanMonths <= 0) return null;
    final start = DateTime.tryParse(acquisitionDate.trim());
    if (start == null) return null;
    // الشهور تُضاف بالبناء لا بالأيام: `DateTime` يعالج تجاوز الشهر والسنة،
    // وإضافة ٣٠ يومًا لكل شهر تنحرف أسبوعًا كاملًا في السنة الواحدة.
    return DateTime(start.year, start.month + lifespanMonths, start.day);
  }

  static AssetLife lifeOf({
    required String acquisitionDate,
    required int lifespanMonths,
    DateTime? now,
  }) {
    final expiry = expiryOf(
      acquisitionDate: acquisitionDate,
      lifespanMonths: lifespanMonths,
    );
    if (expiry == null) return AssetLife.unknown;
    final today = now ?? DateTime.now();
    if (!expiry.isAfter(today)) return AssetLife.expired;
    if (expiry.difference(today) <= warnWithin) return AssetLife.nearingEnd;
    return AssetLife.healthy;
  }

  /// الأيام المتبقية على انقضاء العمر — سالبة إن انقضى، و`null` إن لم يُحسب.
  static int? daysLeft({
    required String acquisitionDate,
    required int lifespanMonths,
    DateTime? now,
  }) {
    final expiry = expiryOf(
      acquisitionDate: acquisitionDate,
      lifespanMonths: lifespanMonths,
    );
    if (expiry == null) return null;
    final today = now ?? DateTime.now();
    return expiry.difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  /// الباركود المطبوع على الأصل: رقمه التسلسلي إن وُجد، وإلا معرّف مشتقّ ثابت.
  ///
  /// لا يُترك بلا رمز: أصلٌ بلا باركود لا يُجرد بالماسح، وإدخال اسمه يدويًا في
  /// جردٍ ميداني هو ما يجعل الجرد يستغرق يومًا بدل ساعة.
  static String barcodeOf({required String id, required String serialNumber}) {
    final serial = serialNumber.trim();
    if (serial.isNotEmpty) return serial;
    // المعرّف الداخلي طويل؛ يُختصر بآخر ثمانية محارف وهي الأكثر تمايزًا.
    final tail = id.length <= 8 ? id : id.substring(id.length - 8);
    return 'AST-${tail.toUpperCase()}';
  }
}
