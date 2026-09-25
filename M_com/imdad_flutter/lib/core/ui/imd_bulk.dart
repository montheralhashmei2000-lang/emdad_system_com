import 'package:flutter/material.dart';

import 'imd_form.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// عمود في شبكة الإدخال الجماعي.
///
/// [width] يثبّت العرض (للحقول الرقمية والقوائم)، و[flex] يوزّع ما بقي.
class ImdBulkCol {
  const ImdBulkCol(this.label, {this.width, this.flex = 1, this.hint = ''});

  final String label;
  final double? width;
  final int flex;

  /// سطرٌ صغير تحت العنوان يشرح ما يُكتب — أرخص من تدريب المستخدم.
  final String hint;
}

/// سطرٌ في الشبكة: خلاياه، وخطؤه إن وُجد.
class ImdBulkRow {
  const ImdBulkRow({required this.cells, this.error = '', this.badge});

  final List<Widget> cells;

  /// خطأ هذا السطر وحده — يُعرض تحته بلا أن يُخفي ما كُتب.
  final String error;

  /// شارة تُعرض بجوار رقم السطر (حالة، وحدة، تنبيه).
  final Widget? badge;
}

/// شبكة إدخال جماعي: سطورٌ متكررة بأعمدة ثابتة، مع ترقيم وتكرار وحذف.
///
/// **لماذا شبكة لا نموذجٌ يُعاد فتحه لكل سطر؟** إدخال خمسين أصلًا أو عشرين
/// حدًّا نموذجًا نموذجًا عملُ ساعة، والمستخدم لا يرى ما أدخله قبل قليل فيكرره
/// أو يتناقض معه. الشبكة تُبقي الدفعة كلها أمام عينه حتى لحظة الحفظ.
///
/// وثلاث تفصيلات تجعلها تُحتمل فعلًا:
/// * **الترقيم** — «السطر ٧ خطأ» لا معنى له بلا رقم ظاهر.
/// * **التكرار** — أكثر سطور الدفعة تتشابه في كل شيء إلا حقلًا واحدًا.
/// * **الخطأ تحت سطره** — لا رسالة واحدة أعلى الشاشة تُخفي أيّ سطر تعني.
///
/// وعلى الشاشات الضيّقة تنقلب الشبكة إلى بطاقات: صفٌّ من ستة حقول على عرض
/// ٤٠٠ بكسل لا يُقرأ ولا يُكتب فيه.
class ImdBulkGrid extends StatelessWidget {
  const ImdBulkGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.onAdd,
    required this.onRemove,
    this.onDuplicate,
    this.addLabel = 'إضافة سطر',
    this.empty = 'لم يُضف سطر بعد',
    this.summary = const [],
    this.actions = const [],
  });

  final List<ImdBulkCol> columns;
  final List<ImdBulkRow> rows;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  /// تكرار السطر بكل قيمه — يُخفى إن لم يُمرَّر.
  final ValueChanged<int>? onDuplicate;

  final String addLabel;
  final String empty;

  /// رقائق الملخّص أسفل الشبكة (عدد السطور، الإجمالي، التحذيرات).
  final List<Widget> summary;

  /// أزرار إضافية بجوار «إضافة سطر».
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final narrow = ImdBp.of(context).tablet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isEmpty)
          ImdEmptyBox(empty)
        else if (narrow)
          ...[
            for (var i = 0; i < rows.length; i++) _card(context, i),
          ]
        else ...[
          _header(context),
          for (var i = 0; i < rows.length; i++) _row(context, i),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ImdButton.outline(
              label: addLabel, icon: 'plus-square', small: true, onPressed: onAdd),
          ...actions,
          if (summary.isNotEmpty) ...[
            Container(width: 1, height: 22, color: c.line),
            ...summary,
          ],
        ]),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: c.tableHead,
        border: Border(bottom: BorderSide(color: c.lineStrong)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(children: [
        const SizedBox(width: 34),
        for (final col in columns) Expanded(flex: col.flex, child: _headCell(context, col)),
        const SizedBox(width: 76),
      ]),
    );
  }

  Widget _headCell(BuildContext context, ImdBulkCol col) {
    final c = context.imd;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(col.label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
                color: c.text2)),
        if (col.hint.isNotEmpty)
          Text(col.hint,
              style: TextStyle(fontSize: 10.5, color: c.muted, height: 1.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: col.width == null ? body : SizedBox(width: col.width, child: body),
    );
  }

  Widget _row(BuildContext context, int i) {
    final c = context.imd;
    final row = rows[i];
    final bad = row.error.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        // شريطٌ أحمر على حافة السطر الخاطئ: يُرى قبل قراءة أي نص.
        border: Border(
          bottom: BorderSide(color: c.line),
          right: BorderSide(color: bad ? c.danger : Colors.transparent, width: 3),
        ),
        color: bad ? c.dangerSoft.withValues(alpha: .35) : (i.isOdd ? c.subtle : null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: 34, child: _index(context, i, row.badge)),
            for (var k = 0; k < columns.length; k++)
              Expanded(
                flex: columns[k].flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: k < row.cells.length ? row.cells[k] : const SizedBox.shrink(),
                ),
              ),
            SizedBox(width: 76, child: _rowActions(context, i)),
          ]),
          if (bad)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 38),
              child: Text('✖ ${row.error}',
                  style: TextStyle(
                      fontSize: 11.5, color: c.danger, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  /// بطاقة السطر على الشاشات الضيّقة.
  Widget _card(BuildContext context, int i) {
    final c = context.imd;
    final row = rows[i];
    final bad = row.error.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: bad ? c.danger : c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _index(context, i, row.badge),
          const Spacer(),
          _rowActions(context, i),
        ]),
        const SizedBox(height: 8),
        for (var k = 0; k < columns.length && k < row.cells.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ImdLabeled(columns[k].label, row.cells[k], size: 11),
          ),
        if (bad)
          Text('✖ ${row.error}',
              style: TextStyle(
                  fontSize: 11.5, color: c.danger, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _index(BuildContext context, int i, Widget? badge) {
    final c = context.imd;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.subtle,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('${i + 1}',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: c.text2)),
      ),
      if (badge != null) ...[const SizedBox(width: 6), badge],
    ]);
  }

  Widget _rowActions(BuildContext context, int i) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDuplicate != null)
            ImdIconButton(
                icon: 'plus',
                tooltip: 'تكرار السطر',
                onPressed: () => onDuplicate!(i)),
          ImdIconButton(
              icon: 'trash', tooltip: 'حذف السطر', onPressed: () => onRemove(i)),
        ],
      );
}
