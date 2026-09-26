/// تقرير الحركة اليومية للمحروقات.
///
/// **دفترٌ لا لقطة.** البرقية تقول ما جرى في يوم؛ وهذا يقول ما جرى في أيام
/// متتابعة ويحمل رصيد كل يومٍ إلى تاليه: الافتتاحي في أول يومٍ وحده، ثم
/// «المتبقي من اليوم السابق» بعده — فتُقرأ سلسلة الأيام ولا ينقطع خيط الرصيد.
///
/// والبناء منطقٌ خالص يُختبر بلا قاعدة ولا واجهة، لأن الخطأ فيه رقمٌ خاطئ
/// أمام القيادة لا خللُ عرض.
library;

import 'fuel_report.dart' show FuelDateRange;

/// بابُ الحركة — به تُرشَّح الجداول وتُبنى الأعمدة.
class FuelMoveKind {
  /// توريدٌ من خارج الفرقة.
  static const String incoming = 'incoming';

  /// صرفٌ على سند لجهةٍ مستفيدة.
  static const String issued = 'issued';

  /// تحويلٌ بين معسكرين — بالاتجاهين.
  static const String transfer = 'transfer';

  static const List<String> all = [incoming, issued, transfer];

  static const Map<String, String> labels = {
    incoming: 'الوارد',
    issued: 'المنصرف',
    transfer: 'التحويل',
  };

  static String label(String v) => labels[v] ?? v;
}

/// سطرٌ في أحد جداول اليوم.
class FuelDailyMove {
  const FuelDailyMove({
    required this.date,
    required this.refNo,
    required this.fuelType,
    required this.qty,
    required this.party,
    this.vehicleType = '',
    this.driver = '',
    this.authority = '',
    this.purpose = '',
    this.notes = '',
    this.outbound = false,
  });

  final String date;
  final String refNo;
  final String fuelType;
  final double qty;

  /// جهة التوريد، أو الجهة المستفيدة، أو المعسكر الآخر في التحويل.
  final String party;

  final String vehicleType;
  final String driver;
  final String authority;
  final String purpose;
  final String notes;

  /// للتحويل وحده: هل خرج من هذا المعسكر أم دخله؟
  final bool outbound;
}

/// رصيدُ نوعِ وقودٍ في معسكرٍ في يوم.
class FuelDailyBalance {
  const FuelDailyBalance({
    required this.warehouse,
    required this.fuelType,
    required this.opening,
    required this.incoming,
    required this.issued,
    required this.transferIn,
    required this.transferOut,
    required this.adjustment,
  });

  final String warehouse;
  final String fuelType;

  /// الافتتاحي في أول يوم، والمتبقي من السابق فيما بعده.
  final double opening;

  final double incoming;
  final double issued;
  final double transferIn;
  final double transferOut;

  /// فرق جردٍ مرحَّل — لا يظهر عمودًا إلا إن وقع.
  final double adjustment;

  /// صافي التحويل بإشارته: موجبٌ إن دخل أكثر مما خرج.
  double get transferNet => _r(transferIn - transferOut);

  double get closing =>
      _r(opening + incoming - issued + transferNet + adjustment);

  bool get moved =>
      incoming != 0 || issued != 0 || transferIn != 0 || transferOut != 0;
}

/// معسكرٌ في يومٍ واحد: جداوله الثلاثة وأرصدته.
class FuelDailyCamp {
  const FuelDailyCamp({
    required this.warehouse,
    required this.incoming,
    required this.issued,
    required this.transfers,
    required this.balances,
  });

  final String warehouse;
  final List<FuelDailyMove> incoming;
  final List<FuelDailyMove> issued;
  final List<FuelDailyMove> transfers;

  /// سطرٌ لكل نوع وقود.
  final List<FuelDailyBalance> balances;

  double get incomingTotal => _sum(incoming);
  double get issuedTotal => _sum(issued);
  double get transferTotal => _sum(transfers);

  /// التحويل يُطبع إن وُجد فقط — جدولٌ فارغ يشغل ورقةً بلا خبر.
  bool get hasTransfers => transfers.isNotEmpty;

  bool get hasAny =>
      incoming.isNotEmpty || issued.isNotEmpty || transfers.isNotEmpty;

  double openingOf(String fuelType) => _balanceOf(fuelType).opening;
  double closingOf(String fuelType) => _balanceOf(fuelType).closing;

  FuelDailyBalance _balanceOf(String fuelType) => balances.firstWhere(
        (b) => b.fuelType == fuelType,
        orElse: () => FuelDailyBalance(
          warehouse: warehouse,
          fuelType: fuelType,
          opening: 0,
          incoming: 0,
          issued: 0,
          transferIn: 0,
          transferOut: 0,
          adjustment: 0,
        ),
      );

  static double _sum(List<FuelDailyMove> l) =>
      _r(l.fold<double>(0, (s, m) => s + m.qty));
}

/// يومٌ واحد في التقرير.
class FuelDailyDay {
  const FuelDailyDay({required this.date, required this.camps});

  final String date;
  final List<FuelDailyCamp> camps;

  List<FuelDailyBalance> get balances =>
      [for (final c in camps) ...c.balances];

  bool get hasAny => camps.any((c) => c.hasAny);
}

/// التقرير كاملًا.
class FuelDailyReport {
  const FuelDailyReport({
    required this.range,
    required this.warehouses,
    required this.days,
  });

  final FuelDateRange range;
  final List<String> warehouses;
  final List<FuelDailyDay> days;

  /// عنوان الورقة — معسكرٌ يُسمّى، والجميع يُجمَل.
  String get title => warehouses.length == 1
      ? 'تقرير الحركة اليومية للمحروقات — ${warehouses.single}'
      : 'تقرير الحركة اليومية للمحروقات — جميع المعسكرات والمحطات';

  bool get isEmpty => days.every((d) => !d.hasAny);

  /// هل وقع فرقُ جردٍ في المدى؟ إن لم يقع فلا يُفرد له عمود.
  bool get hasAdjustments =>
      days.any((d) => d.balances.any((b) => b.adjustment != 0));

  /// إجمالي بندٍ على المدى كله.
  double totalOf(double Function(FuelDailyBalance) of) => _r(days.fold<double>(
      0, (s, d) => s + d.balances.fold<double>(0, (x, b) => x + of(b))));
}

// ───────────────────────── مُدخلات البناء

class FuelDailyOpening {
  const FuelDailyOpening({
    required this.warehouse,
    required this.fuelType,
    required this.date,
    required this.liters,
  });

  final String warehouse;
  final String fuelType;
  final String date;
  final double liters;
}

class FuelDailySupply {
  const FuelDailySupply({
    required this.date,
    required this.refNo,
    required this.warehouse,
    required this.fuelType,
    required this.qty,
    this.supplier = '',
    this.vehicleType = '',
    this.driver = '',
    this.notes = '',
  });

  final String date;
  final String refNo;
  final String warehouse;
  final String fuelType;
  final double qty;
  final String supplier;
  final String vehicleType;
  final String driver;
  final String notes;
}

class FuelDailyIssue {
  const FuelDailyIssue({
    required this.date,
    required this.refNo,
    required this.warehouse,
    required this.fuelType,
    required this.qty,
    this.beneficiary = '',
    this.vehicleType = '',
    this.driver = '',
    this.chassisNo = '',
    this.authority = '',
    this.purpose = '',
    this.notes = '',
  });

  final String date;
  final String refNo;
  final String warehouse;
  final String fuelType;
  final double qty;
  final String beneficiary;
  final String vehicleType;
  final String driver;
  final String chassisNo;
  final String authority;
  final String purpose;
  final String notes;
}

class FuelDailyTransfer {
  const FuelDailyTransfer({
    required this.date,
    required this.refNo,
    required this.fromWarehouse,
    required this.toWarehouse,
    required this.fuelType,
    required this.qty,
    this.vehicleType = '',
    this.driver = '',
    this.notes = '',
  });

  final String date;
  final String refNo;
  final String fromWarehouse;
  final String toWarehouse;
  final String fuelType;
  final double qty;
  final String vehicleType;
  final String driver;
  final String notes;
}

class FuelDailyAdjustment {
  const FuelDailyAdjustment({
    required this.date,
    required this.warehouse,
    required this.fuelType,
    required this.delta,
  });

  final String date;
  final String warehouse;
  final String fuelType;
  final double delta;
}

// ───────────────────────── البانِي

class FuelDailyReportBuilder {
  const FuelDailyReportBuilder._();

  static const String _dash = '—';

  static FuelDailyReport build({
    required FuelDateRange range,
    required List<String> warehouses,
    required List<String> fuelTypes,
    List<FuelDailyOpening> openings = const [],
    List<FuelDailySupply> supplies = const [],
    List<FuelDailyIssue> issues = const [],
    List<FuelDailyTransfer> transfers = const [],
    List<FuelDailyAdjustment> adjustments = const [],
    List<String> kinds = FuelMoveKind.all,
  }) {
    final dates = _daysOf(range);

    // رصيدٌ يمشي مع الأيام: يُفتح بما استقرّ قبل المدى، ثم يُسلَّم كلُّ يومٍ
    // متبقّيه إلى تاليه. وهذا هو التقرير — لا جمعُ يومٍ بمعزل عن جيرانه.
    final running = <String, double>{};
    for (final w in warehouses) {
      for (final t in fuelTypes) {
        running['$w|$t'] = _before(
          range.from,
          warehouse: w,
          fuelType: t,
          openings: openings,
          supplies: supplies,
          issues: issues,
          transfers: transfers,
          adjustments: adjustments,
        );
      }
    }

    final days = <FuelDailyDay>[];
    for (final date in dates) {
      final camps = <FuelDailyCamp>[];
      for (final w in warehouses) {
        final daySupplies = [
          for (final s in supplies)
            if (s.warehouse == w && s.date == date && _wanted(s.fuelType, fuelTypes))
              s,
        ]..sort((a, b) => a.refNo.compareTo(b.refNo));
        final dayIssues = [
          for (final i in issues)
            if (i.warehouse == w && i.date == date && _wanted(i.fuelType, fuelTypes))
              i,
        ]..sort((a, b) => a.refNo.compareTo(b.refNo));
        final dayTransfers = [
          for (final t in transfers)
            if (t.date == date &&
                _wanted(t.fuelType, fuelTypes) &&
                (t.fromWarehouse == w || t.toWarehouse == w))
              t,
        ]..sort((a, b) => a.refNo.compareTo(b.refNo));

        final balances = <FuelDailyBalance>[];
        for (final type in fuelTypes) {
          final key = '$w|$type';
          // رصيدٌ افتتاحيّ مؤرَّخٌ بهذا اليوم هو **افتتاحيُّ اليوم** لا وارده:
          // هو ما كان في الخزّان قبل أن يبدأ النظام، لا شيءٌ ورد إليه.
          final seeded = _r(openings
              .where((o) =>
                  o.warehouse == w && o.fuelType == type && o.date == date)
              .fold<double>(0, (x, o) => x + o.liters));
          final opening = _r((running[key] ?? 0) + seeded);
          final inn = _r(daySupplies
              .where((s) => s.fuelType == type)
              .fold<double>(0, (x, s) => x + s.qty));
          final out = _r(dayIssues
              .where((i) => i.fuelType == type)
              .fold<double>(0, (x, i) => x + i.qty));
          final tIn = _r(dayTransfers
              .where((t) => t.fuelType == type && t.toWarehouse == w)
              .fold<double>(0, (x, t) => x + t.qty));
          final tOut = _r(dayTransfers
              .where((t) => t.fuelType == type && t.fromWarehouse == w)
              .fold<double>(0, (x, t) => x + t.qty));
          final adj = _r(adjustments
              .where((a) =>
                  a.warehouse == w && a.fuelType == type && a.date == date)
              .fold<double>(0, (x, a) => x + a.delta));

          final b = FuelDailyBalance(
            warehouse: w,
            fuelType: type,
            opening: opening,
            incoming: inn,
            issued: out,
            transferIn: tIn,
            transferOut: tOut,
            adjustment: adj,
          );
          balances.add(b);
          running[key] = b.closing;
        }

        camps.add(FuelDailyCamp(
          warehouse: w,
          incoming: kinds.contains(FuelMoveKind.incoming)
              ? [for (final s in daySupplies) _supplyMove(s)]
              : const [],
          issued: kinds.contains(FuelMoveKind.issued)
              ? [for (final i in dayIssues) _issueMove(i)]
              : const [],
          transfers: kinds.contains(FuelMoveKind.transfer)
              ? [for (final t in dayTransfers) _transferMove(t, w)]
              : const [],
          balances: balances,
        ));
      }
      days.add(FuelDailyDay(date: date, camps: camps));
    }

    return FuelDailyReport(
        range: range, warehouses: warehouses, days: days);
  }

  /// ما استقرّ في الخزّان قبل أول يومٍ في المدى.
  static double _before(
    String from, {
    required String warehouse,
    required String fuelType,
    required List<FuelDailyOpening> openings,
    required List<FuelDailySupply> supplies,
    required List<FuelDailyIssue> issues,
    required List<FuelDailyTransfer> transfers,
    required List<FuelDailyAdjustment> adjustments,
  }) {
    var v = 0.0;
    bool before(String d) => from.isEmpty || d.compareTo(from) < 0;

    for (final o in openings) {
      if (o.warehouse == warehouse &&
          o.fuelType == fuelType &&
          before(o.date)) {
        v += o.liters;
      }
    }
    for (final s in supplies) {
      if (s.warehouse == warehouse &&
          s.fuelType == fuelType &&
          before(s.date)) {
        v += s.qty;
      }
    }
    for (final i in issues) {
      if (i.warehouse == warehouse &&
          i.fuelType == fuelType &&
          before(i.date)) {
        v -= i.qty;
      }
    }
    for (final t in transfers) {
      if (t.fuelType != fuelType || !before(t.date)) continue;
      if (t.toWarehouse == warehouse) v += t.qty;
      if (t.fromWarehouse == warehouse) v -= t.qty;
    }
    for (final a in adjustments) {
      if (a.warehouse == warehouse &&
          a.fuelType == fuelType &&
          before(a.date)) {
        v += a.delta;
      }
    }
    return _r(v);
  }

  /// أيام المدى بترتيبها — حتى ما خلا منها من حركة، فالدفتر لا يقفز يومًا.
  static List<String> _daysOf(FuelDateRange range) {
    final from = DateTime.tryParse(range.from);
    final to = DateTime.tryParse(range.to);
    if (from == null || to == null || to.isBefore(from)) {
      return [if (range.from.isNotEmpty) range.from];
    }
    final out = <String>[];
    for (var d = from;
        !d.isAfter(to) && out.length < 400;
        d = d.add(const Duration(days: 1))) {
      out.add(d.toIso8601String().substring(0, 10));
    }
    return out;
  }

  static bool _wanted(String fuelType, List<String> types) =>
      types.isEmpty || types.contains(fuelType);

  static FuelDailyMove _supplyMove(FuelDailySupply s) => FuelDailyMove(
        date: s.date,
        refNo: s.refNo,
        fuelType: s.fuelType,
        qty: s.qty,
        party: _or(s.supplier),
        vehicleType: _or(s.vehicleType),
        driver: _or(s.driver),
        notes: s.notes.trim(),
      );

  static FuelDailyMove _issueMove(FuelDailyIssue i) => FuelDailyMove(
        date: i.date,
        refNo: i.refNo,
        fuelType: i.fuelType,
        qty: i.qty,
        party: _first([i.beneficiary, i.driver]) ?? _dash,
        vehicleType: _or(i.vehicleType),
        driver: _or(i.driver),
        authority: _or(i.authority),
        purpose: _first([i.purpose]) ?? '',
        notes: [
          if (i.chassisNo.trim().isNotEmpty) 'شاصي ${i.chassisNo.trim()}',
          if (i.notes.trim().isNotEmpty) i.notes.trim(),
        ].join(' · '),
      );

  static FuelDailyMove _transferMove(FuelDailyTransfer t, String camp) {
    final out = t.fromWarehouse == camp;
    return FuelDailyMove(
      date: t.date,
      refNo: t.refNo,
      fuelType: t.fuelType,
      qty: t.qty,
      party: out ? t.toWarehouse : t.fromWarehouse,
      vehicleType: _or(t.vehicleType),
      driver: _or(t.driver),
      notes: t.notes.trim(),
      outbound: out,
    );
  }

  static String _or(String v) => v.trim().isEmpty ? _dash : v.trim();

  static String? _first(List<String> candidates) {
    for (final c in candidates) {
      if (c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}

double _r(double v) => (v * 1000).round() / 1000;
