import 'package:flutter/material.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';


/// جدول إدخال الأصناف على سطح المكتب — الأسلوب البصري موحَّدٌ **بالبناء**:
/// كل شاشات السندات تمرّ من هنا، فلا تتفق على تمرير المعاملات نفسها بل
/// ترثها. ومن أراد تبديل الأسلوب بدّله هنا مرةً واحدة.
///
/// رأسٌ ثابتٌ بلون التمييز، خطوط شبكة، خطٌّ ١٢، وحشوةٌ ضيّقة. أمّا الحقول
/// نفسها فتُصغَّر تلقائيًّا: [ImdCompact] يعلنها فوق الجدول كلّه.
class ImdEntryTable extends StatelessWidget {
  const ImdEntryTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowKeys,
    this.empty = 'لم يُضف صنف بعد',
    this.pageSize,
    this.cards = false,
    this.minWidth,
  });

  final List<ImdCol> columns;
  final List<List<Widget>> rows;
  final List<LocalKey> rowKeys;
  final String empty;

  /// ترقيم الصفحات للجداول الطويلة (الأرصدة الافتتاحية، العدّ الفعلي).
  final int? pageSize;

  /// بطاقاتٌ على الجوال: سندات الإدخال لها عرض جوّالها الخاص فتتركها `false`؛
  /// أما شاشات القوائم الطويلة فتحتاجها.
  final bool cards;

  /// أقل عرضٍ للجدول — تمريرٌ أفقيٌّ إن ضاق عنه.
  final double? minWidth;

  /// ارتفاع صفّ الجدول = ارتفاع الحقل المدمج نفسه ([ImdSizes.compactField]):
  /// الحقل يملأ الصفّ كلّه فلا فراغ فوقه ولا تحته، ويلتصق الصفّ الثاني بالأول
  /// بخطّ الشبكة وحده. ثابتٌ فلا يتغيّر بتغيّر محتوى خليةٍ واحدة.
  static double get rowHeight => ImdSizes.compactField;

  /// خليةٌ بارتفاع الصفّ: ما فيها (حقلٌ نصّي أو قائمةٌ أو رصيدٌ أو أزرار) يأخذ
  /// الارتفاع كلّه — **لا يُتوسَّط بحجمه** — فيتساوى الجميع رأسيًّا.
  static Widget cell(Widget child) => SizedBox(height: rowHeight, child: child);

  /// خليةُ **نصٍّ أو شارة** (ما ليس حقلًا): تتوسّط الصفّ رأسيًّا ولا تتمدّد به،
  /// فيبقى بجوار الحقول على خطٍّ واحد.
  static Widget textCell(Widget child) => SizedBox(
        height: rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ImdSizes.compactPadH),
          child: Align(alignment: AlignmentDirectional.centerStart, child: child),
        ),
      );

  /// خليةُ أزرارٍ في آخر الصفّ: بجوار بعضها، كلٌّ بارتفاع الحقل (يرثه من
  /// [ImdCompact]).
  static Widget actions(List<Widget> buttons) => SizedBox(
        height: rowHeight,
        // أزرارٌ ملتصقة (بلا فجوة): الفاصل بينها خطّ الشبكة نفسه.
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // بطاقات الجوال ليست شبكة: حقولها بحدودها وزواياها المعتادة، والالتصاق للجدول وحده.
    final asCards = cards && ImdBp.of(context).mobile && rows.isNotEmpty;
    return ImdCompact(
      flush: !asCards,
      child: ImdTable(
        columns: columns,
        rows: rows,
        rowKeys: rowKeys,
        empty: empty,
        cards: cards,
        pageSize: pageSize,
        minWidth: minWidth,
        maxHeight: ImdSizes.tableMaxHeight(context),
        headerBackground: c.accent,
        headerForeground: c.onAccent,
        flushCells: !asCards,
        gridLines: true,
        cellFontSize: 12,
      ),
    );
  }
}


/// خلية «الرصيد» في جدول الإدخال — حقلُ قراءةٍ لا إدخال.
///
/// بشكل الحقول المجاورة نفسه (الحدّ والزوايا والارتفاع) بخلفيةٍ هادئة، فتبدو
/// حقلًا بين حقول لا نصًّا سائبًا بحجمٍ آخر. خطُّها ١١ لا ١٢ ولونها أهدأ: هي
/// سياقٌ يُطمئن قبل كتابة الكمية، لا رقمٌ يُنافس الحقول. وبلا صنفٍ مختار تبقى
/// شرطةً لا فراغًا، فيُعرف أن العمود موجودٌ وأن قيمته لم تُعرف بعد.
class ImdEntryBalanceCell extends StatelessWidget {
  const ImdEntryBalanceCell(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final empty = text.trim().isEmpty;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: ImdSizes.compactPadH),
      // ملتصقةٌ بحدود الخلية: بلا زوايا ولا حدٍّ — خطّ الشبكة يفصلها.
      decoration: BoxDecoration(color: c.bg),
      child: Text(
        empty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: empty ? c.faint : c.muted),
      ),
    );
  }
}
