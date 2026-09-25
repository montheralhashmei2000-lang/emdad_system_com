/// قسم المحروقات — أنواعه وفتراته وحساب استحقاقه ورصيده.
///
/// **لماذا قسمٌ مستقل عن المخزون؟** الوقود يُقاس باللتر لا بوحدات الأصناف،
/// ويُصرف لمركبةٍ بسائقها ورقم شاصيها لا لوحدةٍ في الهواء، واستحقاقه مخصَّصٌ
/// للوحدة في كل فترة لا مقرَّرٌ للفرد يُضرب في القوة. وخلطُ لتراته بأرصدة
/// الإعاشة يُفسد تقرير الأرصدة وسجل المعسكرات معًا — رقمٌ واحد بمعنيين.
///
/// أما المستودعات والوحدات المستفيدة فتُشارَك: المستودع مكانٌ وبعضه يحمل
/// وقودًا، ودليلان للمكان الواحد يعنيان صيانته مرتين واختلافهما بعد أول تعديل.
library;

class FuelType {
  static const String petrol = 'petrol';
  static const String diesel = 'diesel';

  static const List<String> all = [petrol, diesel];

  static const Map<String, String> labels = {
    petrol: 'بترول',
    diesel: 'ديزل',
  };

  static String label(String v) => labels[v] ?? v;
}

class FuelPeriod {
  static const String daily = 'daily';
  static const String weekly = 'weekly';
  static const String monthly = 'monthly';
  static const String custom = 'custom';

  static const List<String> all = [daily, weekly, monthly, custom];

  static const Map<String, String> labels = {
    daily: 'يومي',
    weekly: 'أسبوعي',
    monthly: 'شهري',
    custom: 'فترة محددة',
  };

  static String label(String v) => labels[v] ?? v;
}

class FuelSource {
  /// صرفٌ ضمن تفريدة قائمة — يُخصم من استحقاقها.
  static const String allocation = 'allocation';

  /// أمرٌ استثنائي خارج التفريدة — يلزمه مبرر وجهةُ أمر.
  static const String exceptional = 'exceptional';

  static const List<String> all = [allocation, exceptional];

  static const Map<String, String> labels = {
    allocation: 'من تفريدة',
    exceptional: 'أمر استثنائي',
  };

  static String label(String v) => labels[v] ?? v;
}

class FuelStocktakeStatus {
  static const String open = 'open';
  static const String counting = 'counting';
  static const String analysis = 'analysis';
  static const String posted = 'posted';

  static const List<String> all = [open, counting, analysis, posted];

  static const Map<String, String> labels = {
    open: 'أمر مفتوح',
    counting: 'العد الفعلي',
    analysis: 'تحليل الفروقات',
    posted: 'مرحّل',
  };

  static String label(String v) => labels[v] ?? v;

  /// المرحلة التالية، أو `null` عند نهاية السلسلة.
  static String? next(String current) => switch (current) {
        open => counting,
        counting => analysis,
        analysis => posted,
        _ => null,
      };

  /// المرحّل لا يُعدَّل: أرقامه صارت جزءًا من الرصيد.
  static bool editable(String status) => status != posted;
}

/// تفريدة كما يراها الحساب — بلا ارتباط بجدول، فتُختبر وحدها.
class FuelAllocationCalc {
  const FuelAllocationCalc({
    required this.periodType,
    required this.quantityPerPeriod,
    required this.startDate,
    this.totalQuantity = 0,
    this.endDate = '',
    this.active = true,
    this.disbursable = true,
    this.weeklyLiters = 0,
    this.monthlyLiters = 0,
  });

  final String periodType;
  final double quantityPerPeriod;
  final double totalQuantity;
  final String startDate;
  final String endDate;
  final bool active;
  final bool disbursable;
  final double weeklyLiters;
  final double monthlyLiters;
}

class Fuel {
  const Fuel._();

  static const String unit = 'لتر';

  /// جهات الأمر المعتادة — تُقترح ولا تُلزم.
  static const List<String> orderAuthorities = [
    'استحقاق',
    'استحقاق أسبوعي',
    'مكتب القائد',
    'رئيس شعبة الإمداد والتموين',
    'المحروقات',
  ];

  static double round(double v) => (v * 1000).round() / 1000;

  static DateTime? _parse(String date) => DateTime.tryParse(date.trim());

  /// عدد الفترات المنقضية من بداية التفريدة إلى [asOf].
  ///
  /// اليوم الأول فترةٌ كاملة لا كسرٌ منها: تفريدةٌ يومية بدأت اليوم تستحق
  /// حصة اليوم، لا صفرًا حتى ينتصف الليل.
  static int periodsElapsed(FuelAllocationCalc a, DateTime asOf) {
    final start = _parse(a.startDate);
    if (start == null) return 0;
    final end = _parse(a.endDate);
    final limit = (end != null && end.isBefore(asOf)) ? end : asOf;

    final startDay = DateTime(start.year, start.month, start.day);
    final limitDay = DateTime(limit.year, limit.month, limit.day);
    if (limitDay.isBefore(startDay)) return 0;
    final days = limitDay.difference(startDay).inDays;

    return switch (a.periodType) {
      FuelPeriod.daily => days + 1,
      FuelPeriod.weekly => (days ~/ 7) + 1,
      FuelPeriod.monthly => () {
          final months = (limitDay.year - startDay.year) * 12 +
              (limitDay.month - startDay.month);
          return limitDay.day >= startDay.day ? months + 1 : months;
        }(),
      _ => 1,
    };
  }

  /// الاستحقاق المتراكم حتى [asOf].
  static double entitledLiters(FuelAllocationCalc a, DateTime asOf) {
    if (!a.active) return 0;
    if (a.periodType == FuelPeriod.custom) return round(a.totalQuantity);
    return round(periodsElapsed(a, asOf) * a.quantityPerPeriod);
  }

  static double remainingLiters({
    required FuelAllocationCalc allocation,
    required double issued,
    required DateTime asOf,
  }) =>
      round(entitledLiters(allocation, asOf) - issued);

  /// ما يعادله أسبوعيًّا — للمقارنة بين تفريدات مختلفة الفترات.
  static double weeklyOf(FuelAllocationCalc a) {
    if (a.weeklyLiters > 0) return a.weeklyLiters;
    return switch (a.periodType) {
      FuelPeriod.weekly => a.quantityPerPeriod,
      FuelPeriod.monthly => round(a.quantityPerPeriod / 4),
      FuelPeriod.daily => round(a.quantityPerPeriod * 7),
      _ => a.totalQuantity,
    };
  }

  static double monthlyOf(FuelAllocationCalc a) {
    if (a.monthlyLiters > 0) return a.monthlyLiters;
    return switch (a.periodType) {
      FuelPeriod.monthly => a.quantityPerPeriod,
      FuelPeriod.weekly => round(a.quantityPerPeriod * 4),
      FuelPeriod.daily => round(a.quantityPerPeriod * 30),
      _ => a.totalQuantity,
    };
  }

  /// مانع الصرف من تفريدة، أو `null` إن جاز.
  ///
  /// الفحص هنا لا في الشاشة: الصرف يقع من شاشةٍ ومن استيرادٍ ومن مزامنة،
  /// وقاعدةٌ في شاشةٍ واحدة تُلتفّ من الأبواب الأخرى.
  static String? issueBlock({
    required FuelAllocationCalc allocation,
    required String date,
    required double qty,
    required double alreadyIssued,
  }) {
    if (!allocation.active) return 'التفريدة موقوفة';
    if (!allocation.disbursable) {
      return 'هذه التفريدة لا تُصرف إلا بتوجيه من القائد';
    }
    final d = date.trim();
    if (allocation.startDate.isNotEmpty && d.compareTo(allocation.startDate) < 0) {
      return 'تاريخ الصرف قبل بداية التفريدة';
    }
    if (allocation.endDate.isNotEmpty && d.compareTo(allocation.endDate) > 0) {
      return 'تاريخ الصرف بعد نهاية التفريدة';
    }
    final asOf = _parse(d) ?? DateTime.now();
    final remaining = remainingLiters(
      allocation: allocation,
      issued: alreadyIssued,
      asOf: asOf,
    );
    if (qty > remaining + 1e-9) {
      return 'الكمية أكبر من المتبقي من الاستحقاق (${round(remaining)} $unit)';
    }
    return null;
  }

  /// تحقّق عام من سند محروقات.
  static String? validateQty(double qty) {
    if (qty <= 0) return 'الكمية أكبر من صفر';
    return null;
  }

  static String? validateTransfer({
    required String from,
    required String to,
    required double qty,
    required double available,
  }) {
    if (from.trim().isEmpty) return 'اختر المستودع المصدر';
    if (to.trim().isEmpty) return 'اختر المستودع الهدف';
    if (from.trim() == to.trim()) return 'المستودعان واحد — اختر غيره';
    final q = validateQty(qty);
    if (q != null) return q;
    // الوقود لا يُنقل من فراغ: تحويلٌ بلا رصيد يصنع لترات من العدم.
    if (qty > available + 1e-9) {
      return 'الرصيد المتاح ${round(available)} $unit فقط';
    }
    return null;
  }

  /// نسبة إشغال الخزّان.
  static double occupancy({required double used, required double capacity}) {
    if (capacity <= 0) return 0;
    return round(used / capacity * 100);
  }
}

/// مكوّنات رصيد نوعٍ في مستودع.
class FuelStock {
  const FuelStock({
    required this.warehouse,
    required this.fuelType,
    this.opening = 0,
    this.supplied = 0,
    this.issued = 0,
    this.transferredIn = 0,
    this.transferredOut = 0,
    this.adjustments = 0,
    this.capacityLiters = 0,
  });

  final String warehouse;
  final String fuelType;
  final double opening;
  final double supplied;
  final double issued;
  final double transferredIn;
  final double transferredOut;

  /// فروقات الجرد **المرحَّل** وحدها.
  final double adjustments;
  final double capacityLiters;

  double get stock => Fuel.round(
      opening + supplied + transferredIn - transferredOut - issued + adjustments);

  double get occupancy =>
      Fuel.occupancy(used: stock, capacity: capacityLiters);

  bool get empty => stock <= 1e-9;
}

/// تنبيه تشغيلي في لوحة المحروقات.
class FuelAlert {
  const FuelAlert({
    required this.id,
    required this.tone,
    required this.title,
    required this.hint,
  });

  final String id;

  /// warn | danger
  final String tone;
  final String title;
  final String hint;
}

class FuelAlerts {
  const FuelAlerts._();

  /// حدّ الامتلاء الذي يُنبَّه عنده.
  static const double fullPercent = 90;

  /// تنبيهات المستودعات: النفاد أولًا، ثم الانخفاض، ثم الامتلاء.
  ///
  /// التنبيه بالنسبة لا بالكمية: «٥٠٠ لتر» لا تقول شيئًا عن خزّانٍ سعته
  /// عشرون ألفًا، و«٢٪ من السعة» تقول كل شيء.
  static List<FuelAlert> forStocks(
    List<FuelStock> stocks, {
    double lowPercent = 20,
  }) {
    final out = <FuelAlert>[];
    final byWarehouse = <String, List<FuelStock>>{};
    for (final s in stocks) {
      byWarehouse.putIfAbsent(s.warehouse, () => []).add(s);
    }
    for (final entry in byWarehouse.entries) {
      final rows = entry.value;
      for (final s in rows) {
        if (s.empty) {
          out.add(FuelAlert(
            id: 'empty-${s.warehouse}-${s.fuelType}',
            tone: 'danger',
            title: '${s.warehouse}: نفاد ${FuelType.label(s.fuelType)}',
            hint: 'لا رصيد متاحًا للصرف من هذا النوع.',
          ));
        }
      }
      final capacity = rows.first.capacityLiters;
      if (capacity <= 0) continue;
      final used = rows.fold<double>(0, (sum, r) => sum + r.stock);
      final pct = Fuel.occupancy(used: used, capacity: capacity);
      if (pct >= fullPercent) {
        out.add(FuelAlert(
          id: 'cap-${entry.key}',
          tone: 'warn',
          title: '${entry.key}: إشغال مرتفع',
          hint: 'السعة مشغولة بنسبة ${pct.round()}٪ — راجع التوريد أو حوّل منه.',
        ));
      } else if (pct <= lowPercent) {
        out.add(FuelAlert(
          id: 'low-${entry.key}',
          tone: 'danger',
          title: '${entry.key}: رصيد منخفض',
          hint: 'المتبقي ${pct.round()}٪ من السعة (حد التنبيه ${lowPercent.round()}٪).',
        ));
      }
    }
    return out;
  }

  /// تنبيه قرب نفاد استحقاق تفريدة — عند بلوغ عُشر الاستحقاق فأقل.
  static FuelAlert? forAllocation({
    required String code,
    required double entitled,
    required double remaining,
  }) {
    if (entitled <= 0) return null;
    if (remaining > entitled * 0.1) return null;
    return FuelAlert(
      id: 'alloc-$code',
      tone: remaining <= 0 ? 'danger' : 'warn',
      title: 'التفريدة $code: '
          '${remaining <= 0 ? 'استُنفد الاستحقاق' : 'قرب نفاد الاستحقاق'}',
      hint: 'المتبقي ${Fuel.round(remaining)} من أصل ${Fuel.round(entitled)} '
          '${Fuel.unit}.',
    );
  }
}
