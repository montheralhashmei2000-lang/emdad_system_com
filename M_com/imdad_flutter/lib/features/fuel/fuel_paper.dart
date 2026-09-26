import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/ui/imd_format.dart';
import '../../data/db/app_database.dart';

/// ورقُ المحروقات الرسميّ على الشاشة.
///
/// **الشاشة ورقةٌ لا لوحة.** يرى الضابط التقرير كما سيخرج من الطابعة —
/// الترويسة نفسها والجداول نفسها والتواقيع في مواضعها — فلا يُطبع شيءٌ
/// يفاجئه. ولذلك تخرج هذه الشاشات وحدها عن ألوان القسم الداكنة إلى بياض
/// الورق: ورقُ الوحدة ليس داكنًا ولو كانت الشاشة داكنة.
class FuelPaper extends StatelessWidget {
  const FuelPaper({
    super.key,
    required this.child,
    this.minWidth = 760,
    this.margin = const EdgeInsets.only(bottom: 20),
  });

  static const Color paper = Color(0xFFF7F1E6);
  static const Color line = Color(0xFFB9AC91);
  static const Color head = Color(0xFFEDE4D2);
  static const Color total = Color(0xFFE3C75B);
  static const Color title = Color(0xFF9B2C1F);
  static const Color text = Color(0xFF2B2620);
  static const Color muted = Color(0xFF6B6455);

  final Widget child;
  final double minWidth;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      // الورقة لا تضيق عن عرضٍ تُقرأ فيه جداولها؛ فإن ضاقت الشاشة زحفت
      // أفقيًّا كما يُزحلق الورق على الطاولة، ولا تُكسر الأعمدة.
      child: LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth.isFinite && box.maxWidth > minWidth
            ? box.maxWidth
            : minWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(18),
              // **خطّ الورقة خطُّ النظام.** `DefaultTextStyle` يستبدل النمط
              // كله، فنمطٌ مكتوبٌ من الصفر يسقط عائلة الخط ويطبع الورقة
              // بخطٍّ لاتينيّ لا يصل الحروف.
              child: DefaultTextStyle(
                style:
                    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(color: text, fontSize: 12, height: 1.5),
                child: child,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// عنوانٌ أحمر فوق كل جدولٍ في الورقة.
class FuelPaperHeading extends StatelessWidget {
  const FuelPaperHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text,
            style: const TextStyle(
                color: FuelPaper.title,
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
      );
}

/// ترويسة الورقة: أسطر الجهة وشعارها.
class FuelPaperLetterhead extends StatelessWidget {
  const FuelPaperLetterhead({super.key, required this.settings, this.logo});

  final FuelSettingsRow settings;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final lines = [s.parentOrg, s.agencyTitle, s.commandTitle, s.branchTitle]
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final seal = s.sealLines
        .split(RegExp('[\n·،]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lines.isEmpty)
                const Text('— لم تُضبط ترويسة التقارير بعد —',
                    style: TextStyle(color: FuelPaper.muted, fontSize: 11)),
              for (final l in lines)
                Text(l,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
        ),
        if (logo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Image.memory(logo!, width: 96, height: 96),
          )
        else if (seal.isNotEmpty)
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: FuelPaper.text, width: 3),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final l in seal)
                  Text(l,
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

/// سطر «إلى … / تاريخها …».
class FuelPaperAddressee extends StatelessWidget {
  const FuelPaperAddressee(
      {super.key, required this.settings, required this.span});

  final FuelSettingsRow settings;
  final String span;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _box('إلى : ${settings.branchTitle}')),
          Expanded(child: _box('تاريخها: $span')),
        ],
      );

  Widget _box(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: FuelPaper.line)),
        child: Text(text, style: const TextStyle(fontSize: 11.5)),
      );
}

/// التواقيع الثلاثة — عملُ كلٍّ واسمه من الإعدادات.
class FuelPaperSignatures extends StatelessWidget {
  const FuelPaperSignatures({super.key, required this.settings});

  final FuelSettingsRow settings;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sign(settings.roleOfficer, settings.signOfficer),
          _sign(settings.roleSupply, settings.signSupply),
          _sign(settings.roleChief, settings.signChief),
        ],
      );

  Widget _sign(String role, String name) => Expanded(
        child: Column(children: [
          Text(role.trim().isEmpty ? '—' : role,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(name.trim().isEmpty ? '—' : name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// جدول الورقة: شبكةٌ بحدودٍ كاملة كما تُرسم في البرقية.
class FuelPaperTable extends StatelessWidget {
  const FuelPaperTable({
    super.key,
    required this.headers,
    required this.flex,
    required this.rows,
    this.totalRow,
    this.emptyText = '',
  });

  final List<String> headers;
  final List<int> flex;
  final List<List<String>> rows;
  final List<String>? totalRow;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < flex.length; i++)
        i: FlexColumnWidth(flex[i].toDouble()),
    };
    return Table(
      columnWidths: widths,
      border: TableBorder.all(color: FuelPaper.line, width: 0.8),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: FuelPaper.head),
          children: [for (final h in headers) _cell(h, bold: true)],
        ),
        if (rows.isEmpty && emptyText.isNotEmpty)
          TableRow(children: [
            for (var i = 0; i < headers.length; i++)
              _cell(i == 1 ? emptyText : ''),
          ]),
        for (final r in rows)
          TableRow(children: [for (final v in r) _cell(v)]),
        if (totalRow != null)
          TableRow(
            decoration: const BoxDecoration(color: FuelPaper.total),
            children: [for (final v in totalRow!) _cell(v, bold: true)],
          ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Text(
          text.isEmpty ? '' : arDigits(text),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: FuelPaper.text,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
}
