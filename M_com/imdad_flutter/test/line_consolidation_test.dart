import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/line_consolidation.dart';

/// تكرار الصنف بوحدات مختلفة كان يبقى سطورًا منفصلة لا تُجمع. هذه الاختبارات
/// تثبت أن الكميات تُردّ إلى الوحدة الأساسية ثم تُوزَّع: الأكبر أولًا والباقي
/// على الأصغر.
void main() {
  LineQty line(String item, String unit, double factor, double qty) =>
      LineQty(groupKey: item, unitName: unit, factor: factor, qty: qty);

  group('إعادة التوزيع على الوحدات', () {
    test('المثال المرجعي: ٥٠ كيس + ٩٠ كجم ⇒ ٥٢ كيس + ١٠ كجم', () {
      final out = consolidateLines([
        line('rice', 'كيس', 40, 50),
        line('rice', 'كجم', 1, 90),
      ]);

      expect(out.length, 2);
      expect(out[0].unitName, 'كيس');
      expect(out[0].qty, 52);
      expect(out[1].unitName, 'كجم');
      expect(out[1].qty, 10);
    });

    test('الإجمالي بالوحدة الأساسية لا يتغيّر', () {
      final input = [
        line('oil', 'كرتون', 12, 7),
        line('oil', 'لتر', 1, 30),
        line('oil', 'كرتون', 12, 2),
      ];
      final before = input.fold<double>(0, (s, l) => s + l.baseQty);
      final after = consolidateLines(input).fold<double>(0, (s, l) => s + l.baseQty);

      expect(after, before);
    });

    test('وحدة واحدة فقط ⇒ جمع بسيط في سطر واحد', () {
      final out = consolidateLines([
        line('sugar', 'كجم', 1, 5),
        line('sugar', 'كجم', 1, 7.5),
      ]);

      expect(out.length, 1);
      expect(out.single.qty, 12.5);
    });

    test('أقل من الوحدة الكبرى ⇒ لا يظهر سطر بصفر', () {
      final out = consolidateLines([
        line('rice', 'كيس', 40, 0),
        line('rice', 'كجم', 1, 30),
      ]);

      expect(out.length, 1);
      expect(out.single.unitName, 'كجم');
      expect(out.single.qty, 30);
    });

    test('الكمية مضاعفة تمامًا للوحدة الكبرى ⇒ لا بقية', () {
      final out = consolidateLines([
        line('rice', 'كيس', 40, 3),
        line('rice', 'كجم', 1, 40),
      ]);

      expect(out.length, 1);
      expect(out.single.unitName, 'كيس');
      expect(out.single.qty, 4);
    });

    test('ثلاث وحدات تتدرّج من الأكبر إلى الأصغر', () {
      // ٢ طبلية (٤٨٠) + ١ كرتون (١٢) + ٥ لتر = ٤٩٧ لترًا
      // ⇒ ٢ طبلية (٤٨٠) + ١ كرتون (١٢) + ٥ لتر
      final out = consolidateLines([
        line('oil', 'طبلية', 240, 1),
        line('oil', 'كرتون', 12, 20),
        line('oil', 'لتر', 1, 17),
      ]);

      expect(out.map((l) => l.unitName).toList(), ['طبلية', 'كرتون', 'لتر']);
      expect(out[0].qty, 2);
      expect(out[1].qty, 1);
      expect(out[2].qty, 5);
      expect(out.fold<double>(0, (s, l) => s + l.baseQty), 497);
    });

    test('أصناف مختلفة لا تختلط ويبقى ترتيب ظهورها', () {
      final out = consolidateLines([
        line('rice', 'كيس', 40, 1),
        line('oil', 'لتر', 1, 5),
        line('rice', 'كجم', 1, 40),
      ]);

      expect(out.map((l) => l.groupKey).toList(), ['rice', 'oil']);
      expect(out[0].qty, 2);
      expect(out[1].qty, 5);
    });

    test('مفتاح المجموعة يفصل ما لا يصح خلطه (عملية الأسطوانات)', () {
      final out = consolidateLines([
        line('gas|EXCHANGE', 'أسطوانة', 1, 3),
        line('gas|ISSUE_FULL', 'أسطوانة', 1, 2),
      ]);

      expect(out.length, 2);
      expect(out.map((l) => l.qty).toList(), [3, 2]);
    });

    test('الكسور العائمة لا تُسقط وحدة كاملة', () {
      // ٤٩٫٩٩٩٩٩٩٩٩ كيسًا × ٤٠ تقارب ٢٠٠٠ — يجب أن تُقرأ ٥٠ كيسًا لا ٤٩.
      final out = consolidateLines([
        line('rice', 'كيس', 40, 49.9999999999),
        line('rice', 'كجم', 1, 0),
      ]);

      expect(out.single.unitName, 'كيس');
      expect(out.single.qty, 50);
    });

    test('المثال المرجعي للتحويل: ١١٠٠ كجم ⇒ ٢٧٫٥ كيسًا', () {
      expect(convertQty(1100, 1, 40), 27.5);
    });

    test('التحويل في الاتجاه المعاكس يعيد الأصل', () {
      final toBags = convertQty(1100, 1, 40);
      expect(convertQty(toBags, 40, 1), 1100);
    });

    test('التحويل بين وحدتين كبيرتين', () {
      // ٣ طبليات (٢٤٠ لترًا لكل واحدة) ⇒ كراتين (١٢ لترًا) = ٦٠ كرتونًا.
      expect(convertQty(3, 240, 12), 60);
    });

    test('معامل صفري أو سالب يُعامل كواحد فلا تنفجر القسمة', () {
      expect(convertQty(10, 0, 0), 10);
      expect(convertQty(10, -5, 1), 10);
    });

    test('قائمة فارغة تعطي قائمة فارغة', () {
      expect(consolidateLines(const []), isEmpty);
    });

    test('المجموعة الصفرية تبقى سطرًا واحدًا بالصفر لا تختفي', () {
      final out = consolidateLines([
        line('rice', 'كيس', 40, 0),
        line('rice', 'كجم', 1, 0),
      ]);

      expect(out.length, 1);
      expect(out.single.qty, 0);
    });
  });
}
