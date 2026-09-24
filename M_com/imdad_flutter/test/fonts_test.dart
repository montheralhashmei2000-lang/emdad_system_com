import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ui/imd_fonts.dart';

/// خط الواجهة صار خيارًا في الإعدادات. القيمة القادمة من قاعدة بيانات قديمة أو
/// من ملف مزامنة من إصدار آخر قد تكون مجهولة — ويجب ألّا تكسر الواجهة.
void main() {
  test('الخطوط المطروحة كلها بأسماء وأوصاف', () {
    expect(ImdFonts.all.length, 4);
    for (final f in ImdFonts.all) {
      expect(f.family.isNotEmpty, isTrue);
      expect(f.label.isNotEmpty, isTrue);
      expect(f.note.isNotEmpty, isTrue);
    }
  });

  test('الافتراضي ضمن المطروح', () {
    expect(ImdFonts.all.map((f) => f.family), contains(ImdFonts.defaultFamily));
  });

  test('قيمة مجهولة تسقط إلى الافتراضي بلا خطأ', () {
    expect(ImdFonts.normalize('خط غير موجود'), ImdFonts.defaultFamily);
    expect(ImdFonts.normalize(''), ImdFonts.defaultFamily);
    expect(ImdFonts.normalize(null), ImdFonts.defaultFamily);
  });

  test('القيمة المعروفة تبقى كما هي', () {
    for (final f in ImdFonts.all) {
      expect(ImdFonts.normalize(f.family), f.family);
    }
  });

  test('Amiri ليس خيار واجهة — يبقى للطباعة وحدها', () {
    expect(ImdFonts.all.map((f) => f.family), isNot(contains('Amiri')));
    expect(ImdFonts.normalize('Amiri'), ImdFonts.defaultFamily);
  });

  group('خطوط الطباعة', () {
    test('كل خط طباعة له ملفان بوزنين مختلفين', () {
      for (final f in ImdPrintFonts.all) {
        expect(f.regular.endsWith('.ttf'), isTrue, reason: f.family);
        expect(f.bold.endsWith('.ttf'), isTrue, reason: f.family);
        expect(f.regular, isNot(f.bold), reason: '${f.family}: العريض غير العادي');
      }
    });

    test('المجهول يسقط إلى الافتراضي فلا تفشل الطباعة', () {
      expect(ImdPrintFonts.normalize('Traditional Arabic'), ImdPrintFonts.defaultFamily);
      expect(ImdPrintFonts.normalize(null), ImdPrintFonts.defaultFamily);
      expect(ImdPrintFonts.of('خط مجهول').family, ImdPrintFonts.defaultFamily);
    });

    test('Amiri خيار طباعة رغم استبعاده من الواجهة', () {
      expect(ImdPrintFonts.all.map((f) => f.family), contains('Amiri'));
      expect(ImdFonts.all.map((f) => f.family), isNot(contains('Amiri')));
    });

    test('الخطوط الملكية غير مطروحة (ترخيص)', () {
      final families = ImdPrintFonts.all.map((f) => f.family).toList();
      for (final owned in const ['Traditional Arabic', 'Simplified Arabic', 'Arial']) {
        expect(families, isNot(contains(owned)));
      }
    });
  });
}
