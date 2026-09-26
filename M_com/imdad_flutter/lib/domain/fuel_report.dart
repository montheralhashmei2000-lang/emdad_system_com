/// البرقية الرسمية للمحروقات — نموذج التقرير اليومي والأسبوعي والشهري.
///
/// **التقرير هو الورقة التي تُرفع، لا شاشةٌ تُقرأ.** فبناؤه منطقٌ خالص يُختبر
/// بلا قاعدة ولا واجهة: من حركاتٍ وتواريخ إلى أقسام معسكرات وإجماليات. والشاشة
/// تعرضه كما سيُطبع حرفًا بحرف، فلا يفاجئ الورقُ من قرأ الشاشة.
library;

/// نوع فترة البرقية.
class FuelReportPeriod {
  static const String daily = 'daily';
  static const String weekly = 'weekly';
  static const String monthly = 'monthly';
  static const String custom = 'custom';

  static const List<String> all = [daily, weekly, monthly, custom];

  static const Map<String, String> labels = {
    daily: 'تقرير يومي',
    weekly: 'تقرير أسبوعي',
    monthly: 'تقرير شهري',
    custom: 'فترة محددة',
  };

  /// الوصف الذي يدخل في عنوان البرقية: «تقرير الحركة **اليومية**».
  static const Map<String, String> titles = {
    daily: 'اليومية',
    weekly: 'الأسبوعية',
    monthly: 'الشهرية',
    custom: 'للفترة المحددة',
  };

  static String label(String v) => labels[v] ?? v;

  static String title(String v) => titles[v] ?? '';

  /// تسمية حقل التاريخ المفرد لكل نوع — «اليوم» غير «نهاية الأسبوع».
  static String dateLabel(String v) => switch (v) {
        weekly => 'نهاية الأسبوع',
        monthly => 'شهر التقرير',
        _ => 'اليوم',
      };
}

/// مدى تاريخيّ مغلق الطرفين.
class FuelDateRange {
  const FuelDateRange(this.from, this.to);

  final String from;
  final String to;

  /// الأسبوع **ينتهي** باليوم المختار ويبدأ قبله بستة أيام: التقرير الأسبوعي
  /// يُرفع في نهاية الأسبوع عن الأيام السبعة الماضية، لا عن أسبوعٍ تقويمي.
  static FuelDateRange week(String iso) => FuelDateRange(_shift(iso, -6), iso);

  /// الشهر التقويمي كاملًا مهما كان اليوم المختار فيه.
  static FuelDateRange month(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return FuelDateRange(iso, iso);
    final first = DateTime(d.year, d.month, 1);
    final last = DateTime(d.year, d.month + 1, 0);
    return FuelDateRange(_iso(first), _iso(last));
  }

  static FuelDateRange of(
    String period, {
    required String date,
    required String from,
    required String to,
  }) =>
      switch (period) {
        FuelReportPeriod.weekly => week(date),
        FuelReportPeriod.monthly => month(date),
        FuelReportPeriod.custom => FuelDateRange(from, to),
        _ => FuelDateRange(date, date),
      };

  bool covers(String date) =>
      date.isNotEmpty && date.compareTo(from) >= 0 && date.compareTo(to) <= 0;

  /// «٢٠٢٦/٠٦/٢١» ليومٍ واحد، و«من — إلى» لما زاد.
  String get label =>
      from == to ? slash(from) : '${slash(from)} — ${slash(to)}';

  static String slash(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[0]}/${p[1]}/${p[2]}' : iso;
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  static String _shift(String iso, int days) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : _iso(d.add(Duration(days: days)));
  }
}

/// سطر صادرٍ في البرقية — كما يظهر في الجدول تمامًا.
class FuelOfficialIssueRow {
  const FuelOfficialIssueRow({
    required this.n,
    required this.beneficiary,
    required this.vehicleType,
    required this.qty,
    required this.authority,
    required this.purpose,
    required this.notes,
  });

  final int n;
  final String beneficiary;
  final String vehicleType;
  final double qty;
  final String authority;
  final String purpose;
  final String notes;
}

/// سطر واردٍ في البرقية.
class FuelOfficialSupplyRow {
  const FuelOfficialSupplyRow({
    required this.n,
    required this.supplier,
    required this.vehicleType,
    required this.fuelType,
    required this.qty,
    required this.notes,
  });

  final int n;
  final String supplier;
  final String vehicleType;
  final String fuelType;
  final double qty;
  final String notes;
}

/// قسم معسكرٍ واحد في البرقية: وارده وصادره من كل مادة.
class FuelCampSection {
  const FuelCampSection({
    required this.warehouse,
    required this.incoming,
    required this.petrol,
    required this.diesel,
  });

  final String warehouse;
  final List<FuelOfficialSupplyRow> incoming;
  final List<FuelOfficialIssueRow> petrol;
  final List<FuelOfficialIssueRow> diesel;

  double get petrolTotal => petrol.fold<double>(0, (s, r) => s + r.qty);
  double get dieselTotal => diesel.fold<double>(0, (s, r) => s + r.qty);
  double get total => petrolTotal + dieselTotal;
  double get incomingTotal => incoming.fold<double>(0, (s, r) => s + r.qty);
}

/// البرقية كاملةً.
class FuelOfficialReport {
  const FuelOfficialReport({
    required this.period,
    required this.range,
    required this.title,
    required this.sections,
  });

  final String period;
  final FuelDateRange range;
  final String title;
  final List<FuelCampSection> sections;

  double get grandPetrol =>
      sections.fold<double>(0, (s, c) => s + c.petrolTotal);
  double get grandDiesel =>
      sections.fold<double>(0, (s, c) => s + c.dieselTotal);
  double get grandTotal => grandPetrol + grandDiesel;
  double get incomingTotal =>
      sections.fold<double>(0, (s, c) => s + c.incomingTotal);

  /// الخلاصة لا تُطبع لمعسكرٍ واحد: جدولٌ بسطرٍ وحيد يكرّر ما فوقه.
  bool get showSummary => sections.length > 1;

  bool get isEmpty => grandTotal == 0 && incomingTotal == 0;
}

/// حركةُ صرفٍ كما تدخل البرقية — مجرّدةٌ عن صفوف القاعدة ليُختبر البناء.
class FuelReportIssue {
  const FuelReportIssue({
    required this.date,
    required this.fuelType,
    required this.warehouse,
    required this.qty,
    this.beneficiary = '',
    this.driver = '',
    this.vehicleType = '',
    this.orderAuthority = '',
    this.purpose = '',
    this.justification = '',
    this.notes = '',
    this.source = 'allocation',
  });

  final String date;
  final String fuelType;
  final String warehouse;
  final double qty;
  final String beneficiary;
  final String driver;
  final String vehicleType;
  final String orderAuthority;
  final String purpose;
  final String justification;
  final String notes;
  final String source;
}

/// حركةُ توريدٍ كما تدخل البرقية.
class FuelReportSupply {
  const FuelReportSupply({
    required this.date,
    required this.fuelType,
    required this.warehouse,
    required this.qty,
    this.supplier = '',
    this.vehicleType = '',
    this.notes = '',
  });

  final String date;
  final String fuelType;
  final String warehouse;
  final double qty;
  final String supplier;
  final String vehicleType;
  final String notes;
}

/// بانِي البرقية.
class FuelReportBuilder {
  static const String _dash = '—';

  static FuelOfficialReport build({
    required String period,
    required FuelDateRange range,
    required List<String> warehouses,
    required List<FuelReportIssue> issues,
    required List<FuelReportSupply> supplies,
  }) {
    final inRange = issues.where((i) => range.covers(i.date)).toList();
    final suppliesIn = supplies.where((s) => range.covers(s.date)).toList();

    final sections = [
      for (final w in warehouses)
        FuelCampSection(
          warehouse: w,
          incoming:
              _supplyRows(suppliesIn.where((s) => s.warehouse == w).toList()),
          petrol: _issueRows(
              inRange.where((i) => i.warehouse == w).toList(), 'petrol'),
          diesel: _issueRows(
              inRange.where((i) => i.warehouse == w).toList(), 'diesel'),
        ),
    ];

    // معسكرٌ واحد يُسمّى في العنوان، والجميع يُجمَل — كما في البرقية الورقية.
    final title = warehouses.length == 1
        ? 'تقرير الحركة ${FuelReportPeriod.title(period)} في محطة الوقود في '
            '${warehouses.single}'
        : 'تقرير الحركة ${FuelReportPeriod.title(period)} للمحروقات — '
            'جميع المعسكرات';

    return FuelOfficialReport(
      period: period,
      range: range,
      title: title,
      sections: sections,
    );
  }

  static List<FuelOfficialIssueRow> _issueRows(
      List<FuelReportIssue> list, String fuelType) {
    final rows = list.where((i) => i.fuelType == fuelType).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    var n = 0;
    return [
      for (final i in rows)
        FuelOfficialIssueRow(
          n: ++n,
          // الجهة المستفيدة اسمٌ مكتوب، فإن خلا فالسائق، فإن خلا فشرطة —
          // ولا يُترك الحقل فارغًا في ورقةٍ تُرفع.
          beneficiary: _first([i.beneficiary, i.driver]) ?? _dash,
          vehicleType: _first([i.vehicleType]) ?? _dash,
          qty: i.qty,
          authority: _first([i.orderAuthority]) ??
              (i.source == 'exceptional' ? 'أمر استثنائي' : 'استحقاق'),
          purpose: _first([i.purpose, i.justification]) ?? '',
          notes: i.notes.trim(),
        ),
    ];
  }

  static List<FuelOfficialSupplyRow> _supplyRows(List<FuelReportSupply> list) {
    final rows = [...list]..sort((a, b) => a.date.compareTo(b.date));
    var n = 0;
    return [
      for (final s in rows)
        FuelOfficialSupplyRow(
          n: ++n,
          supplier: _first([s.supplier]) ?? _dash,
          vehicleType: _first([s.vehicleType]) ?? _dash,
          fuelType: s.fuelType,
          qty: s.qty,
          notes: s.notes.trim(),
        ),
    ];
  }

  static String? _first(List<String> candidates) {
    for (final c in candidates) {
      if (c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}
