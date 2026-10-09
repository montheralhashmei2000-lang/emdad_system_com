import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../data/repos/cable_repo.dart';
import '../../domain/free_table.dart';
import '../ui/imd_format.dart';
import 'military_print.dart';
import 'print_format.dart';
import 'voucher_print.dart';
import '../../core/error_log.dart';
import '../../domain/print_forms.dart';

/// طباعة نموذج «برقية صادرة/واردة» المعتمد.
///
/// الحقول المتغيرة (إلى، من، نسخة إلى، الموضوع، المرسَل إليهم، بيانات المركز)
/// تُملأ من إدخال المستخدم، وجسم البرقية نصٌّ حرّ يُكتب يدويًّا. أمّا الرقم
/// والتاريخ والساعة فتأتي من السجل نفسه.
class CablePrint {
  CablePrint._();

  static const _line = PdfColor.fromInt(0xFF222222);
  static const _label = PdfColor.fromInt(0xFFEDEDED);

  static String _slashDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return printDate(iso);
  }

  /// `15:07` ⇒ `3:07 م`؛ ما لا يُفهم يُعاد كما هو.
  static String _time12(String hm) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(hm);
    if (m == null) return hm;
    final h = int.parse(m.group(1)!);
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.group(2)} ${h < 12 ? 'ص' : 'م'}';
  }

  static const _red = PdfColors.red700;

  /// يقصّ نصًّا إلى [max] حرفًا بعلامة حذف — لخاناتٍ ثابتة لا تتجزأ على الصفحات.
  static String _cap(String t, int max) => t.length <= max ? t : '${t.substring(0, max)}…';

  /// يقسم فقرةً طويلة إلى قطعٍ ≤ [max] حرفًا عند المسافات، فيستطيع المحرّك فصل
  /// الصفحات بين القطع. الودجة الواحدة الأطول من الصفحة تُسقط الطباعة كلها.
  static List<String> _chunks(String t, int max) {
    if (t.length <= max) return [t];
    final out = <String>[];
    var cur = StringBuffer();
    for (final w in t.split(RegExp(r'\s+'))) {
      if (cur.length + w.length + 1 > max && cur.isNotEmpty) {
        out.add(cur.toString());
        cur = StringBuffer();
      }
      if (cur.isNotEmpty) cur.write(' ');
      cur.write(w.length > max ? w.substring(0, max) : w);
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }
  static const _pad = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3);
  static const double _headH = 96;
  static const double _margin = 24;

  /// خانة بإطار؛ [flex] يوزّع العرض كالنموذج المعتمد.
  static pw.Widget _box(String text,
      {int flex = 1,
      bool bold = false,
      bool shaded = false,
      double size = 11,
      double? height,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.center,
      pw.Alignment alignment = pw.Alignment.center,
      pw.Widget? child}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        height: height,
        alignment: alignment,
        padding: _pad,
        decoration: pw.BoxDecoration(color: shaded ? _label : null, border: pw.Border.all(color: _line, width: 0.8)),
        child: child ??
            pw.Text(text,
                textAlign: align,
                style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  /// ترويسة الجهة: أسطر الجهة يمينًا، الشعار وسطًا، بيانات البرقية يسارًا.
  static pw.Widget _letterhead(MilitaryPrint engine, Uint8List? logo, Cable c, String kindLabel, String cls, String prio) {
    pw.Widget small(String t) => pw.Text(t, style: const pw.TextStyle(fontSize: 9));
    return pw.SizedBox(
      height: _headH,
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 4,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            for (final l in engine.orgLines)
              if (l.trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text(l, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                ),
          ]),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Column(children: [
            if (logo != null) pw.SizedBox(width: 66, height: 66, child: pw.Image(pw.MemoryImage(logo))) else pw.SizedBox(height: 66),
            pw.SizedBox(height: 2),
            pw.Text('برقية خطية/سري للغاية/عاجل جدا',
                style: const pw.TextStyle(fontSize: 6.5, color: _red, decoration: pw.TextDecoration.underline)),
          ]),
        ),
        pw.Expanded(
          flex: 4,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              small('$kindLabel برقم ${c.cableNo}'),
              pw.SizedBox(height: 3),
              small('درجة السرية: $cls'),
              pw.SizedBox(height: 3),
              small('درجة الاسبقية: $prio'),
            ]),
          ),
        ),
      ]),
    );
  }

  /// يبني ملف PDF للبرقية بترويسة الجهة والشعار من إعدادات الهوية، على النموذج المعتمد.
  static Future<Uint8List> build(AppDatabase db, Cable c) async {
    final engine = await VoucherPrint.engineOf(db, form: PrintForms.cableForm);
    // شعار الهوية المحفوظ في الإعدادات، وإلا الشعار المضمَّن مع التطبيق.
    Uint8List? logo = engine.logoBytes;
    if (logo == null) {
      try {
        logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
      } catch (err, stack) {
        ErrorLogger.log('print.cable.logo', err, stack);
      }
    }
    final theme = await engine.pdfTheme();
    final pdf = pw.Document(theme: theme);
    final free = FreeTable.decode(c.recipientsJson);
    final freeRows = free.filledRows;
    final out = c.direction == CableDirection.outgoing;
    final kindLabel = out ? 'برقية صادرة' : 'برقية واردة';
    final cls = CableClass.label(c.classification);
    final prio = CablePriority.label(c.priority);

    const h = 24.0;
    // إلى/من: ثلاثة أعمدة (قيمة عريضة | تسمية | قيمة).
    pw.Widget infoRow(String left, String label, String value) => pw.Row(children: [
          _box(left, flex: 5, bold: true, height: h, alignment: pw.Alignment.centerRight, align: pw.TextAlign.right),
          _box(label, flex: 2, height: h),
          _box(value, flex: 2, height: h, size: 12),
        ]);

    final ccLines = c.ccParty.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final info = pw.Column(children: [
      infoRow('الى : ${c.toParty}', 'رقم البرقية', c.cableNo),
      infoRow('من: ${c.fromParty}', 'تاريخها', _slashDate(c.cableDate)),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _box('',
            flex: 5,
            height: h * 3,
            alignment: pw.Alignment.topRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('نسخة إلى:', style: const pw.TextStyle(fontSize: 10.5)),
              for (final l in ccLines) pw.Text('-   ${l.trim()}', style: const pw.TextStyle(fontSize: 9.5)),
            ])),
        pw.Expanded(
          flex: 4,
          child: pw.Column(children: [
            pw.Row(children: [_box('سعت الإنشاء', flex: 2, height: h), _box(_time12(c.cableTime), flex: 2, height: h, size: 12)]),
            pw.Row(children: [_box('درجة السرية', flex: 2, height: h), _box(cls, flex: 2, height: h, color: _red, bold: true)]),
            pw.Row(children: [_box('درجة الاسبقية', flex: 2, height: h), _box(prio, flex: 2, height: h, color: _red, bold: true)]),
          ]),
        ),
      ]),
    ]);

    // جسم البرقية: كل سطرٍ ببادئة «-» ما لم يبدأ بها، والنص حرٌّ يكتبه المستخدم بيده.
    final bodyLines = <String>[
      for (final l in c.body.split('\n').where((l) => l.trim().isNotEmpty))
        ...() {
          final t = l.trim();
          final parts = _chunks(t, 700);
          return [for (final (i, p) in parts.indexed) i == 0 && !t.startsWith('-') ? '-   $p' : p];
        }(),
    ];

    // الموقِّع كتلةٌ واحدة لا تتجزأ: سطورها وعددها محدودان.
    final signer = [for (final l in c.signerText.split('\n').where((l) => l.trim().isNotEmpty).take(8)) _cap(l.trim(), 120)];

    // الجدول الحر اختياري: لا يُطبع إن لم يُكتب فيه شيء. الأعمدة وأسماؤها وأعراضها من المستخدم.
    final recTable = freeRows.isEmpty
        ? null
        : pw.Column(children: [
            if (free.title.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(free.title.trim(),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
              ),
            pw.Row(children: [
              _box('م', flex: 10, bold: true, size: 12),
              for (final col in free.cols) _box(col.title, flex: (col.weight * 10).round(), bold: true, size: 12),
            ]),
            for (final (i, r) in freeRows.indexed)
              pw.Row(children: [
                _box(nf(i + 1), flex: 10, bold: true, height: h),
                for (var k = 0; k < free.cols.length; k++) _box(r[k], flex: (free.cols[k].weight * 10).round(), height: h),
              ]),
          ]);

    // «لاستعمال المركز / المكتب»: ثلاث مجموعات (الإرسال | الاستقبال | المحرر).
    const rh = 20.0;
    final editor = [c.editorRank, c.editorName].where((e) => e.trim().isNotEmpty).join(' / ');
    // «مختص» وظيفة المحرر وهي متغيرة؛ حقل المختص القديم احتياطٌ للبرقيات المحفوظة قبلًا.
    final job = c.editorJob.trim().isNotEmpty ? c.editorJob.trim() : c.specialist.trim();
    pw.Widget group(String title, List<(String, String)> rows) => pw.Expanded(
          child: pw.Column(children: [
            pw.Row(children: [_box(title, flex: 1, bold: true, shaded: true, height: rh)]),
            for (final r in rows)
              pw.Row(children: [
                _box(r.$1, flex: 5, height: rh, size: 9.5, alignment: pw.Alignment.centerRight, align: pw.TextAlign.right),
                _box(r.$2, flex: 6, height: rh, size: 9.5),
              ]),
          ]),
        );
    final centerBox = pw.Column(children: [
      pw.Row(children: [_box('لاستعمال المركز / المكتب', flex: 1, bold: true, shaded: true, height: rh, size: 11)]),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        group('الإرسال', [
          ('تسلسل / نرس', c.serialNo),
          ('الوقت والتاريخ', c.sendDateTime),
          ('وسيلة الإرسال', c.sendMethod),
          ('التوقيع', ''),
        ]),
        group('الاستقبال', [
          ('وقت الاستلام', c.receiveTime),
          ('اسم المأمور', c.receiverName),
          ('', ''),
          ('التوقيع', ''),
        ]),
        group('محرر البرقية / الرتبة', [
          ('الاسم', editor),
          ('الوظيفة', job),
          ('', ''),
          ('التوقيع', ''),
        ]),
      ]),
    ]);

    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: theme,
        margin: const pw.EdgeInsets.all(_margin),
        // إطار الصفحة: يبدأ تحت الترويسة في الأولى، ومن أعلى الصفحة فيما بعدها.
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(_margin, ctx.pageNumber == 1 ? _margin + _headH + 6 : _margin, _margin, _margin),
            child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 1.4))),
          ),
        ),
      ),
      // «لاستعمال المركز / المكتب» ثابتٌ أسفل الإطار في كل صفحة.
      footer: (ctx) => centerBox,
      build: (ctx) => [
        _letterhead(engine, logo, c, kindLabel, cls, prio),
        pw.SizedBox(height: 6),
        info,
        pw.SizedBox(height: 14),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Center(
              child: pw.Text('م/ ${_cap(c.subject, 400)}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
            ),
            if (recTable != null) ...[pw.SizedBox(height: 10), recTable],
            pw.SizedBox(height: 16),
            for (final l in bodyLines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(l, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, lineSpacing: 4)),
              ),
            if (signer.isNotEmpty) ...[
              pw.SizedBox(height: 40),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 30),
                  child: pw.Column(children: [
                    for (final l in signer) pw.Text(l, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
              ),
            ],
            pw.SizedBox(height: 24),
          ]),
        ),
      ],
    ));
    return pdf.save();
  }

  /// يعرض معاينة الطباعة ثم يُؤرشف النسخة تلقائيًّا إن مُكِّنت الأرشفة للبرقيات.
  static Future<void> print(AppDatabase db, Cable c) async {
    final bytes = await build(db, c);
    await MilitaryPrint.show(bytes, name: 'برقية ${c.cableNo}');
    // فشل الأرشفة لا يمنع طباعةً تمّت، كبقية المطبوعات.
    try {
      await ArchiveAuto(db).onDocumentPrinted(
        op: 'cable',
        title: 'برقية ${c.cableNo} — ${c.subject}',
        docRef: c.cableNo,
        docDate: c.cableDate,
        pdfBytes: bytes,
        fileName: 'برقية-${c.cableNo}.pdf',
      );
    } catch (err, stack) {
      ErrorLogger.critical('archive.cable', err, stack: stack, userMessage: 'طُبعت البرقية لكن تعذّرت أرشفتها تلقائيًّا');
    }
  }
}
