import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/print_layout.dart';

void main() {
  group('تخطيط المستندات المطبوعة', () {
    test('الحقل العربي: العنوان يمينًا والقيمة يسارًا افتراضيًا', () {
      const f = PrintField(key: 'warehouse', label: 'المستودع');
      expect(f.labelAlign, PrintAlign.right);
      expect(f.valueAlign, PrintAlign.left);
    });

    test('أعمدة الجدول: التسلسل والأرقام وسطًا والنص يمينًا', () {
      const t = TableStyle();
      expect(t.alignFor(0, '1'), PrintAlign.center);
      expect(t.alignFor(3, '250'), PrintAlign.center);
      expect(t.alignFor(3, '١٢٥'), PrintAlign.center);
      expect(t.alignFor(1, 'أرز أبيض'), PrintAlign.right);
      expect(t.alignFor(2, 'كيس'), PrintAlign.right);
    });

    test('محاذاة مخصصة تُطبَّق على الأعمدة الرقمية', () {
      const t = TableStyle(numAlign: PrintAlign.left, cellAlign: PrintAlign.center);
      expect(t.alignFor(3, '40'), PrintAlign.left);
      expect(t.alignFor(1, 'سكر'), PrintAlign.center);
    });

    test('الحفظ والاسترجاع بصيغة JSON يبقي الإعدادات كما هي', () {
      final layout = PrintLayout.defaults.copyWith(
        titleSize: 18,
        right: [
          const PrintLine(text: 'الجمهورية اليمنية', bold: true, size: 13),
          const PrintLine(text: 'قيادة اللواء الأول', align: PrintAlign.center),
        ],
        table: const TableStyle(cellAlign: PrintAlign.center, size: 9),
      );
      final back = PrintLayout.fromJson(layout.toJson());
      expect(back.titleSize, 18);
      expect(back.right.length, 2);
      expect(back.right.first.bold, isTrue);
      expect(back.right[1].align, PrintAlign.center);
      expect(back.table.cellAlign, PrintAlign.center);
      expect(back.table.size, 9);
      expect(back.info.length, PrintLayout.defaults.info.length);
    });

    test('إخفاء سطر أو حقل لا يحذفه من الإعدادات', () {
      final layout = PrintLayout.defaults.copyWith(
        left: PrintLayout.defaults.left
            .map((f) => f.key == 'entryNo' ? f.copyWith(show: false) : f)
            .toList(),
      );
      final visible = layout.left.where((f) => f.show).map((f) => f.key).toList();
      expect(visible, isNot(contains('entryNo')));
      expect(layout.left.length, PrintLayout.defaults.left.length);
    });

    test('نص فارغ لا يُعد رقمًا', () {
      expect(TableStyle.isNumeric(''), isFalse);
      expect(TableStyle.isNumeric('  '), isFalse);
      expect(TableStyle.isNumeric('12.5'), isTrue);
      expect(TableStyle.isNumeric('-3'), isTrue);
    });
  });
}
