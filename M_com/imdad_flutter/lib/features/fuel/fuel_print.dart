import '../../core/print/document_pdf.dart';
import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/fuel_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/print_layout.dart';
import '../../domain/fuel.dart';

/// سندات المحروقات المطبوعة.
///
/// **السائق لا يأخذ الوقود بلا ورقة موقَّعة بيده.** سندٌ في قاعدة بيانات لا
/// يُسلَّم ولا يُوقَّع عليه ولا يُحفظ في ملف الوحدة، فقسمٌ بلا طباعة قسمٌ لا
/// يعمل في الميدان مهما صحّت أرقامه.
///
/// والتخطيط مشترك مع بقية سندات النظام (الترويسة والتواقيع والشعار من
/// [SettingsRepo.printLayout])، فتخرج أوراق المحروقات بهيئة أوراق الإعاشة
/// نفسها — لا نظامان في مظهرٍ واحد.
class FuelPrint {
  const FuelPrint._();

  static Future<PrintLayout> _layout(AppDatabase db) =>
      SettingsRepo(db).printLayout();

  /// سند صرف محروقات — يُسلَّم للسائق.
  ///
  /// [allocation] يُمرَّر ليُطبع الاستحقاق والمتبقي وقت الصرف؛ وبدونه يُطبع
  /// السند بلا هذا السطر (كالأمر الاستثنائي، فلا تفريدة له أصلًا).
  static Future<void> issueVoucher(
    AppDatabase db,
    FuelIssue issue, {
    FuelAllocationRow? allocation,
  }) async =>
      DocumentPdf.printDoc(
        layout: await _layout(db),
        doc: issueDoc(issue, allocation: allocation),
      );

  /// بناء سند الصرف — مفصولٌ عن طباعته ليُختبر بلا واجهة.
  static PrintDoc issueDoc(FuelIssue issue, {FuelAllocationRow? allocation}) {
    final exceptional = issue.source == FuelSource.exceptional;
    return PrintDoc(
        title: 'سند صرف محروقات',
        headers: const [
          'نوع الوقود',
          'الكمية',
          'الوحدة',
          'اسم السائق',
          'نوع المركبة',
          'رقم الشاصي',
        ],
        columnFlex: const [3, 2, 2, 4, 3, 3],
        rows: [
          [
            FuelType.label(issue.fuelType),
            nf(issue.quantityLiters),
            Fuel.unit,
            _or(issue.driverName),
            _or(issue.vehicleType),
            _or(issue.chassisNo),
          ],
        ],
        leftValues: {'date': issue.date, 'refNo': issue.refNo},
        fieldValues: {
          'warehouse': issue.warehouse,
          'party': _or(issue.beneficiaryName),
          'notes': issue.notes,
        },
        footerNote: [
          'المصدر: ${FuelSource.label(issue.source)}',
          if (!exceptional && allocation != null)
            'الاستحقاق ${nf(allocation.entitled)} ${Fuel.unit} — '
                'المتبقي بعد هذا السند ${nf(allocation.remaining)}',
          if (exceptional && issue.orderAuthority.isNotEmpty)
            'جهة الأمر: ${issue.orderAuthority}',
          if (exceptional && issue.justification.isNotEmpty)
            'المبرر: ${issue.justification}',
          if (issue.purpose.isNotEmpty) 'الغرض: ${issue.purpose}',
      ].join(' · '),
    );
  }

  /// سند توريد محروقات.
  static Future<void> supplyVoucher(AppDatabase db, FuelSupply supply) async =>
      DocumentPdf.printDoc(
          layout: await _layout(db), doc: supplyDoc(supply));

  static PrintDoc supplyDoc(FuelSupply supply) {
    return PrintDoc(
        title: 'سند توريد محروقات',
        headers: const [
          'نوع الوقود',
          'الكمية',
          'الوحدة',
          'مركبة النقل',
          'اسم السائق',
        ],
        columnFlex: const [3, 2, 2, 3, 4],
        rows: [
          [
            FuelType.label(supply.fuelType),
            nf(supply.quantityLiters),
            Fuel.unit,
            _or(supply.transportVehicleType),
            _or(supply.driverName),
          ],
        ],
        leftValues: {'date': supply.date, 'refNo': supply.refNo},
        fieldValues: {
          'warehouse': supply.warehouse,
          'party': _or(supply.supplierName),
        'notes': supply.notes,
      },
    );
  }

  /// سند تحويل محروقات بين مستودعين.
  static Future<void> transferVoucher(
          AppDatabase db, FuelTransfer transfer) async =>
      DocumentPdf.printDoc(
          layout: await _layout(db), doc: transferDoc(transfer));

  static PrintDoc transferDoc(FuelTransfer transfer) {
    return PrintDoc(
        title: 'سند تحويل محروقات',
        headers: const [
          'نوع الوقود',
          'الكمية',
          'الوحدة',
          'مركبة النقل',
          'اسم السائق',
        ],
        columnFlex: const [3, 2, 2, 3, 4],
        rows: [
          [
            FuelType.label(transfer.fuelType),
            nf(transfer.quantityLiters),
            Fuel.unit,
            _or(transfer.transportVehicleType),
            _or(transfer.driverName),
          ],
        ],
        leftValues: {'date': transfer.date, 'refNo': transfer.refNo},
        fieldValues: {
          'warehouse': transfer.fromWarehouse,
          'party': 'إلى: ${transfer.toWarehouse}',
        'notes': transfer.notes,
      },
    );
  }

  /// محضر جرد محروقات — الدفتري والمعدود والفرق.
  static Future<void> stocktakeReport(
    AppDatabase db,
    FuelStocktake take,
    List<FuelStocktakeLine> lines,
  ) async =>
      DocumentPdf.printDoc(
          layout: await _layout(db), doc: stocktakeDoc(take, lines));

  static PrintDoc stocktakeDoc(
      FuelStocktake take, List<FuelStocktakeLine> lines) {
    return PrintDoc(
        title: 'محضر جرد محروقات — ${FuelStocktakeStatus.label(take.status)}',
        headers: const [
          'نوع الوقود',
          'الرصيد الدفتري',
          'المعدود فعلًا',
          'الفرق',
          'الحالة',
        ],
        columnFlex: const [3, 3, 3, 3, 3],
        rows: [
          for (final l in lines)
            [
              FuelType.label(l.fuelType),
              '${nf(l.bookLiters)} ${Fuel.unit}',
              l.counted ? '${nf(l.countedLiters)} ${Fuel.unit}' : '—',
              l.counted
                  ? _signed(Fuel.round(l.countedLiters - l.bookLiters))
                  : '—',
              l.counted ? 'عُدَّ' : 'لم يُعدّ',
            ],
        ],
        leftValues: {'date': take.date, 'refNo': take.refNo},
        fieldValues: {
          'warehouse': take.warehouse,
          'party': take.committee.isEmpty ? 'لجنة الجرد' : take.committee,
          'notes': take.notes,
        },
        footerNote: [
          'نوع الجرد: ${take.kind == 'full' ? 'كامل' : 'جزئي'}',
          // المرحلة تُطبع صراحةً: محضرٌ غير مرحّل لا يُحتجّ به على أحد.
          if (take.status != FuelStocktakeStatus.posted)
            'هذا المحضر لم يُرحَّل بعد — الفروقات لم تدخل الرصيد',
      ].join(' · '),
    );
  }

  /// كشف صرف محروقات لفترة — لا سند واحد.
  static Future<void> issuesReport(
    AppDatabase db,
    List<FuelIssue> issues, {
    String from = '',
    String to = '',
  }) async =>
      DocumentPdf.printDoc(
          layout: await _layout(db),
          doc: issuesDoc(issues, from: from, to: to));

  static PrintDoc issuesDoc(List<FuelIssue> issues,
      {String from = '', String to = ''}) {
    var i = 1;
    final total = issues.fold<double>(0, (s, x) => s + x.quantityLiters);
    return PrintDoc(
        title: 'كشف صرف المحروقات',
        headers: const [
          'م',
          'رقم السند',
          'التاريخ',
          'النوع',
          'المستفيد',
          'الشاصي',
          'الكمية',
        ],
        columnFlex: const [1, 3, 3, 2, 5, 3, 2],
        rows: [
          for (final x in issues)
            [
              '${i++}',
              x.refNo,
              x.date,
              FuelType.label(x.fuelType),
              _or(x.beneficiaryName),
              _or(x.chassisNo),
              nf(x.quantityLiters),
            ],
        ],
        leftValues: {
          'date': to.isEmpty ? _today() : to,
          'refNo': 'كشف',
        },
        fieldValues: {
          'warehouse': 'كافة المستودعات',
          'party': from.isEmpty && to.isEmpty
              ? 'كافة الفترات'
              : 'من $from إلى $to',
        },
        footerNote: 'إجمالي المصروف: ${nf(total)} ${Fuel.unit} '
          'في ${nf(issues.length)} سندًا',
    );
  }

  /// كشف أرصدة المحروقات في المستودعات.
  static Future<void> stocksReport(
          AppDatabase db, List<FuelStock> stocks) async =>
      DocumentPdf.printDoc(
          layout: await _layout(db), doc: stocksDoc(stocks));

  static PrintDoc stocksDoc(List<FuelStock> stocks) {
    return PrintDoc(
        title: 'كشف أرصدة المحروقات',
        headers: const [
          'المستودع',
          'النوع',
          'افتتاحي',
          'وارد',
          'محوَّل إليه',
          'محوَّل منه',
          'مصروف',
          'فرق جرد',
          'الرصيد',
        ],
        columnFlex: const [4, 2, 2, 2, 2, 2, 2, 2, 3],
        rows: [
          for (final s in stocks)
            [
              s.warehouse,
              FuelType.label(s.fuelType),
              nf(s.opening),
              nf(s.supplied),
              nf(s.transferredIn),
              nf(s.transferredOut),
              nf(s.issued),
              s.adjustments == 0 ? '—' : _signed(s.adjustments),
              nf(s.stock),
            ],
        ],
        leftValues: {'date': _today(), 'refNo': 'أرصدة'},
        fieldValues: const {
          'warehouse': 'كافة المستودعات',
          'party': 'قسم المحروقات',
        },
        footerNote: 'الكميات كلها بـ${Fuel.unit}. '
            'والرصيد = الافتتاحي + الوارد + المحوَّل إليه − المحوَّل منه '
          '− المصروف ± فرق الجرد المرحَّل.',
    );
  }

  static String _or(String v) => v.trim().isEmpty ? '—' : v.trim();

  static String _signed(double v) => '${v > 0 ? '+' : ''}${nf(v)}';

  static String _today() =>
      DateTime.now().toIso8601String().substring(0, 10);
}
