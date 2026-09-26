import '../../core/print/document_pdf.dart';
import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/fuel.dart';
import '../../domain/fuel_daily_report.dart';
import '../../domain/fuel_report.dart';
import 'fuel_plan_row.dart';

/// أوراق تقارير المحروقات المطبوعة.
///
/// **بقالب النظام لا بقالبٍ خاص.** كانت البرقية والدفتر اليومي يُبنيان بورقٍ
/// مرسومٍ باليد، فخرجا بجداول مقلوبة الاتجاه وهيئةٍ غير هيئة بقية السندات.
/// وصارا الآن [PrintDoc] بأقسام: الترويسة والتواقيع من إعدادات المحروقات،
/// وكل ما عداهما — عكسُ الأعمدة والخط والحدود والذيل — من قالب النظام.
class FuelReportDocs {
  const FuelReportDocs._();

  static List<String> _headerLines(FuelSettingsRow s) => [
        for (final l in [
          s.parentOrg,
          s.agencyTitle,
          s.commandTitle,
          s.branchTitle,
        ])
          if (l.trim().isNotEmpty) l.trim(),
      ];

  static List<String> _signatures(FuelSettingsRow s) => [
        for (final p in [
          (s.roleOfficer, s.signOfficer),
          (s.roleSupply, s.signSupply),
          (s.roleChief, s.signChief),
        ])
          '${p.$1.trim().isEmpty ? '—' : p.$1.trim()}\n'
              '${p.$2.trim().isEmpty ? '—' : p.$2.trim()}',
      ];

  // ───────────────────────── البرقية الرسمية

  static Future<void> printOfficial(
    AppDatabase db, {
    required FuelOfficialReport report,
    required FuelSettingsRow settings,
  }) async =>
      DocumentPdf.printDoc(
        layout: await SettingsRepo(db).printLayout(),
        doc: official(report, settings),
      );

  /// بناء البرقية — مفصولٌ عن طباعتها ليُختبر بلا واجهة.
  static PrintDoc official(
      FuelOfficialReport report, FuelSettingsRow settings) {
    final sections = <PrintSection>[];

    for (final c in report.sections) {
      sections.add(PrintSection(
        title: report.sections.length > 1
            ? 'محطة الوقود في ${c.warehouse}'
            : 'الوارد',
        note: report.sections.length > 1 ? 'الوارد' : '',
        headers: const [
          'م',
          'جهة التوريد / المصدر',
          'نوع الحركة',
          'الوسيلة',
          'الصنف',
          'الكمية',
        ],
        columnFlex: const [1, 6, 3, 3, 2, 3],
        emptyText: 'لا يوجد وارد',
        rows: [
          for (final r in c.incoming)
            [
              '${r.n}',
              r.supplier,
              r.isTransfer ? 'تحويل داخلي' : 'توريد',
              r.vehicleType,
              FuelType.label(r.fuelType),
              nf(r.qty),
            ],
        ],
        totalRow: c.incoming.isEmpty
            ? null
            : [
                '',
                'الإجمالي — توريد ${nf(c.suppliedTotal)} · '
                    'تحويل ${nf(c.transferredInTotal)}',
                '',
                '',
                '',
                '${nf(c.incomingTotal)} ${Fuel.unit}',
              ],
      ));

      for (final pair in [
        ('الصادر من مادة البترول', c.petrol, c.petrolTotal),
        ('الصادر من مادة الديزل', c.diesel, c.dieselTotal),
      ]) {
        sections.add(PrintSection(
          title: '${pair.$1} — المنصرف ${report.range.label} م',
          headers: const [
            'م',
            'الجهة المستفيدة',
            'نوع الوسيلة',
            'جهة الأمر',
            'الغرض',
            'ملاحظة',
            'الكمية',
          ],
          columnFlex: const [1, 6, 3, 4, 4, 3, 3],
          emptyText: 'لا توجد حركات',
          rows: [
            for (final r in pair.$2)
              [
                '${r.n}',
                r.beneficiary,
                r.vehicleType,
                r.authority,
                r.purpose,
                r.notes,
                nf(r.qty),
              ],
          ],
          totalRow: [
            '',
            'الإجمالي',
            '',
            '',
            '',
            '',
            '${nf(pair.$3)} ${Fuel.unit}',
          ],
        ));
      }

      // التحويل يُطبع إن وُجد فقط — جدولٌ فارغ يشغل ورقةً بلا خبر.
      if (c.outgoing.isNotEmpty) {
        sections.add(PrintSection(
          title: 'المحوَّل إلى المعسكرات',
          headers: const [
            'م',
            'إلى معسكر',
            'الصنف',
            'الوسيلة',
            'السائق',
            'ملاحظة',
            'الكمية',
          ],
          columnFlex: const [1, 6, 2, 3, 3, 3, 3],
          rows: [
            for (final r in c.outgoing)
              [
                '${r.n}',
                r.toCamp,
                FuelType.label(r.fuelType),
                r.vehicleType,
                r.driver,
                r.notes,
                nf(r.qty),
              ],
          ],
          totalRow: [
            '',
            'الإجمالي',
            '',
            '',
            '',
            '',
            '${nf(c.transferredOutTotal)} ${Fuel.unit}',
          ],
        ));
      }
    }

    if (report.showSummary) {
      sections.add(PrintSection(
        title: 'خلاصة جميع المعسكرات',
        headers: const [
          'المعسكر',
          'وارد توريدًا',
          'وارد تحويلًا',
          'صادر بترول',
          'صادر ديزل',
          'محوَّل إلى معسكر',
          'إجمالي الصادر',
        ],
        columnFlex: const [5, 3, 3, 3, 3, 3, 3],
        rows: [
          for (final c in report.sections)
            [
              c.warehouse,
              nf(c.suppliedTotal),
              nf(c.transferredInTotal),
              nf(c.petrolTotal),
              nf(c.dieselTotal),
              nf(c.transferredOutTotal),
              nf(c.outTotal),
            ],
        ],
        totalRow: [
          'الإجمالي',
          nf(report.grandSupplied),
          nf(report.grandTransferredIn),
          nf(report.grandPetrol),
          nf(report.grandDiesel),
          nf(report.grandTransferredOut),
          nf(report.grandTotal + report.grandTransferredOut),
        ],
      ));
    }

    return PrintDoc(
      title: '${report.title} ${report.range.label} م',
      landscape: true,
      sections: sections,
      headerLines: _headerLines(settings),
      signatureLines: _signatures(settings),
      leftValues: {'date': report.range.to, 'refNo': 'برقية'},
      fieldValues: {'party': 'إلى: ${settings.branchTitle}'},
      footerNote: 'المحوَّل بين المعسكرات يظهر واردًا في معسكرٍ وصادرًا في '
          'آخر، فلا يزيد وقود الفرقة ولا ينقصه — الداخل توريدًا '
          '${nf(report.grandSupplied)} ${Fuel.unit}، والخارج صرفًا '
          '${nf(report.grandTotal)} ${Fuel.unit}.',
    );
  }

  // ───────────────────────── الحركة اليومية

  static Future<void> printDaily(
    AppDatabase db, {
    required FuelDailyReport report,
    required FuelSettingsRow settings,
  }) async =>
      DocumentPdf.printDoc(
        layout: await SettingsRepo(db).printLayout(),
        doc: daily(report, settings),
      );

  static const List<String> _ordinals = [
    'أولًا',
    'ثانيًا',
    'ثالثًا',
    'رابعًا',
    'خامسًا',
    'سادسًا',
    'سابعًا',
    'ثامنًا',
    'تاسعًا',
    'عاشرًا',
  ];

  static String _ordinal(int i) =>
      i < _ordinals.length ? _ordinals[i] : '${i + 1}';

  static String _signed(double v) =>
      v == 0 ? '—' : (v > 0 ? '+${nf(v)}' : '−${nf(-v)}');

  static PrintDoc daily(FuelDailyReport report, FuelSettingsRow settings) {
    final adj = report.hasAdjustments;
    final many = report.days.length > 1;
    final sections = <PrintSection>[];

    // **الملخّص قبل التفصيل**: من يقرأ يسأل أولًا «كم بقي وأين».
    sections.add(PrintSection(
      title: 'ملخّص الحركة اليومية',
      headers: [
        if (many) 'اليوم',
        'المعسكر / المحطة',
        'الوقود',
        'الافتتاحي / المتبقي من السابق',
        'الوارد',
        'المنصرف',
        'التحويل',
        if (adj) 'تسوية جرد',
        'المتبقي',
      ],
      columnFlex: [
        if (many) 3,
        5,
        2,
        5,
        3,
        3,
        3,
        if (adj) 3,
        3,
      ],
      rows: [
        for (final day in report.days)
          for (final b in day.balances)
            [
              if (many) FuelDateRange.slash(day.date),
              b.warehouse,
              FuelType.label(b.fuelType),
              nf(b.opening),
              nf(b.incoming),
              nf(b.issued),
              _signed(b.transferNet),
              if (adj) _signed(b.adjustment),
              nf(b.closing),
            ],
      ],
      totalRow: [
        if (many) '',
        'الإجمالي',
        '',
        nf(report.totalOf((b) => b.opening)),
        nf(report.totalOf((b) => b.incoming)),
        nf(report.totalOf((b) => b.issued)),
        _signed(report.totalOf((b) => b.transferNet)),
        if (adj) _signed(report.totalOf((b) => b.adjustment)),
        nf(report.totalOf((b) => b.closing)),
      ],
    ));

    for (final day in report.days) {
      final camps = day.camps.where((c) => c.hasAny).toList();
      if (camps.isEmpty) continue;
      for (var i = 0; i < camps.length; i++) {
        final c = camps[i];
        final head = many
            ? '${_ordinal(i)}: الحركة اليومية بـ${c.warehouse} — '
                '${FuelDateRange.slash(day.date)} م'
            : '${_ordinal(i)}: تقرير الحركة اليومية للمحروقات بـ${c.warehouse}';
        final balance = 'الرصيد أول اليوم: ${_line(c, opening: true)} — '
            'والمتبقي آخره: ${_line(c, opening: false)}';

        sections.add(PrintSection(
          title: head,
          note: '$balance\nالوارد',
          headers: const [
            'م',
            'السند',
            'جهة التوريد',
            'الوسيلة',
            'السائق',
            'الصنف',
            'ملاحظة',
            'الكمية',
          ],
          columnFlex: const [1, 3, 6, 3, 3, 2, 3, 3],
          emptyText: 'لا يوجد وارد',
          rows: [
            for (var n = 0; n < c.incoming.length; n++)
              [
                '${n + 1}',
                c.incoming[n].refNo,
                c.incoming[n].party,
                c.incoming[n].vehicleType,
                c.incoming[n].driver,
                FuelType.label(c.incoming[n].fuelType),
                c.incoming[n].notes,
                nf(c.incoming[n].qty),
              ],
          ],
          totalRow: [
            '',
            'إجمالي الوارد',
            '',
            '',
            '',
            '',
            '',
            '${nf(c.incomingTotal)} ${Fuel.unit}',
          ],
        ));

        sections.add(PrintSection(
          title: '',
          note: 'المنصرف',
          headers: const [
            'م',
            'السند',
            'الجهة المستفيدة',
            'نوع الوسيلة',
            'جهة الأمر',
            'الغرض',
            'الصنف',
            'ملاحظة',
            'الكمية',
          ],
          columnFlex: const [1, 3, 6, 3, 4, 4, 2, 4, 3],
          emptyText: 'لا يوجد منصرف',
          rows: [
            for (var n = 0; n < c.issued.length; n++)
              [
                '${n + 1}',
                c.issued[n].refNo,
                c.issued[n].party,
                c.issued[n].vehicleType,
                c.issued[n].authority,
                c.issued[n].purpose,
                FuelType.label(c.issued[n].fuelType),
                c.issued[n].notes,
                nf(c.issued[n].qty),
              ],
          ],
          totalRow: [
            '',
            'إجمالي المنصرف',
            '',
            '',
            '',
            '',
            '',
            '',
            '${nf(c.issuedTotal)} ${Fuel.unit}',
          ],
        ));

        if (c.hasTransfers) {
          sections.add(PrintSection(
            title: '',
            note: 'التحويل',
            headers: const [
              'م',
              'السند',
              'الاتجاه',
              'الطرف الآخر',
              'الوسيلة',
              'السائق',
              'الصنف',
              'الكمية',
            ],
            columnFlex: const [1, 3, 3, 6, 3, 3, 2, 3],
            rows: [
              for (var n = 0; n < c.transfers.length; n++)
                [
                  '${n + 1}',
                  c.transfers[n].refNo,
                  c.transfers[n].outbound ? 'محوَّل منه' : 'محوَّل إليه',
                  c.transfers[n].outbound
                      ? 'إلى ${c.transfers[n].party}'
                      : 'من ${c.transfers[n].party}',
                  c.transfers[n].vehicleType,
                  c.transfers[n].driver,
                  FuelType.label(c.transfers[n].fuelType),
                  nf(c.transfers[n].qty),
                ],
            ],
            totalRow: [
              '',
              'إجمالي التحويل',
              '',
              '',
              '',
              '',
              '',
              '${nf(c.transferTotal)} ${Fuel.unit}',
            ],
          ));
        }
      }
    }

    return PrintDoc(
      title: '${report.title} — ${report.range.label} م',
      landscape: true,
      sections: sections,
      headerLines: _headerLines(settings),
      signatureLines: _signatures(settings),
      leftValues: {'date': report.range.to, 'refNo': 'حركة يومية'},
      fieldValues: {'party': 'إلى: ${settings.branchTitle}'},
    );
  }

  // ───────────────────────── خطة التفريدة

  static Future<void> printPlan(
    AppDatabase db, {
    required FuelSettingsRow settings,
    required List<FuelPlanRow> petrol,
    required List<FuelPlanRow> diesel,
    List<String> rules = const [],
  }) async =>
      DocumentPdf.printDoc(
        layout: await SettingsRepo(db).printLayout(),
        doc: plan(
            settings: settings, petrol: petrol, diesel: diesel, rules: rules),
      );

  static PrintDoc plan({
    required FuelSettingsRow settings,
    required List<FuelPlanRow> petrol,
    required List<FuelPlanRow> diesel,
    List<String> rules = const [],
  }) {
    PrintSection table(String title, List<FuelPlanRow> rows) {
      final weekly = rows.fold<double>(0, (s, r) => s + r.weekly);
      final monthly = rows.fold<double>(0, (s, r) => s + r.monthly);
      return PrintSection(
        title: title,
        headers: const [
          'م',
          'الوحدة',
          'مكان الصرف',
          'الاستحقاق الأسبوعي',
          'الاستحقاق الشهري',
          'ملاحظات',
        ],
        columnFlex: const [1, 6, 4, 3, 3, 4],
        emptyText: 'لا توجد بنود لهذا الصنف',
        rows: [
          for (final r in rows)
            [
              '${r.n}',
              r.unit,
              r.location,
              nf(r.weekly),
              nf(r.monthly),
              r.notes,
            ],
        ],
        totalRow: [
          '',
          'الإجمالي',
          '',
          nf(weekly),
          nf(monthly),
          '',
        ],
      );
    }

    return PrintDoc(
      title: 'مقترح خطة توزيع الاستحقاق الشهري للمحروقات',
      sections: [
        table('تفريدة البترول — جميع الوحدات المستفيدة', petrol),
        table('تفريدة الديزل — جميع الوحدات المستفيدة', diesel),
      ],
      headerLines: _headerLines(settings),
      signatureLines: _signatures(settings),
      footerNote: rules.isEmpty ? '' : 'قواعد الصرف: ${rules.join(' · ')}',
    );
  }

  static String _line(FuelDailyCamp c, {required bool opening}) => [
        for (final t in FuelType.all)
          '${FuelType.label(t)} '
              '${nf(opening ? c.openingOf(t) : c.closingOf(t))}',
      ].join(' · ');
}
