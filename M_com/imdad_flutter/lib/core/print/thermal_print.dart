import 'package:pdf/pdf.dart';
import 'print_preview.dart';

import '../../domain/print_layout.dart';
import 'document_pdf.dart';

/// الطباعة على الطابعات الحرارية (رول 80مم أو 58مم).
///
/// يُبنى السند بنفس تخطيط المستندات لكن بعرض الرول ومقاس خط أصغر، ثم يُرسل
/// إلى الطابعة عبر تعريف النظام — وهو المسار الذي يطبع العربية متصلة صحيحة،
/// لأن أوامر ESC/POS النصية لا تدعم العربية في أغلب الطابعات الحرارية.
class ThermalPrint {
  static const PdfPageFormat roll80 = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  );

  static const PdfPageFormat roll58 = PdfPageFormat(
    58 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 3 * PdfPageFormat.mm,
  );

  /// تخطيط مبسّط للرول: بلا شعار، بخط أصغر، وبتوقيع واحد.
  static PrintLayout compact(PrintLayout base) => base.copyWith(
        showLogo: false,
        titleSize: 11,
        baseSize: 8,
        right: base.right.map((l) => l.copyWith(size: 8)).toList(),
        left: base.left.map((f) => f.copyWith(size: 8)).toList(),
        info: base.info.map((f) => f.copyWith(size: 8)).toList(),
        table: TableStyle(
          headAlign: base.table.headAlign,
          cellAlign: base.table.cellAlign,
          firstColAlign: base.table.firstColAlign,
          numAlign: base.table.numAlign,
          size: 7.5,
          headBold: base.table.headBold,
        ),
        signatures: base.signatures.take(1).map((l) => l.copyWith(size: 8)).toList(),
        footer: base.footer.map((l) => l.copyWith(size: 7)).toList(),
      );

  static Future<void> printRoll({
    required PrintDoc doc,
    PrintLayout layout = PrintLayout.defaults,
    bool narrow = false,
  }) async {
    final bytes = await DocumentPdf.build(
      doc: doc,
      layout: compact(layout),
      format: narrow ? roll58 : roll80,
    );
    await showPrintPreview(bytes, name: doc.title);
  }
}
