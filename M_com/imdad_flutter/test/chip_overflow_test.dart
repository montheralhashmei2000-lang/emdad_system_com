import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// الشارة لا ترسم نفسها خارج أبيها.
///
/// [ImdChip] يلفّ نصه بـ`IntrinsicWidth` كي لا يضغطه عمودُ جدولٍ إلى ما دون
/// عرض نصه. لكن حين يضيق أبوه فعلًا — شارةٌ طويلة في صندوقٍ ثابت العرض —
/// كان الصفّ الداخلي يفيض بفارق العرض بالضبط، فيُرسم النص فوق ما بجواره
/// ويظهر شريط الفيض المخطّط في وضع التطوير.
///
/// وهذا ما كان يُفيض شاشة الإعدادات ٣٦ بكسل في قسم «نظرة عامة»: شارة
/// «ما زال هناك تحسين مطلوب» داخل عمودٍ عرضه ٢٦٠.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('شارة أطول من أبيها تُقصّ ولا تفيض', (tester) async {
    await tester.pumpWidget(host(const SizedBox(
      width: 120,
      child: ImdChip('نصٌّ طويل جدًّا لا يتّسع له هذا الصندوق الضيّق أبدًا'),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'الشارة رسمت نفسها خارج أبيها');

    final box = tester.getSize(find.byType(ImdChip));
    expect(box.width, lessThanOrEqualTo(120),
        reason: 'عرض الشارة تجاوز ما أُعطيت');
  });

  testWidgets('شارة تتّسع تبقى بعرض نصها كاملًا', (tester) async {
    // هذا ما يحرسه IntrinsicWidth أصلًا: ألّا يضغطها عمودُ جدول دون نصها.
    await tester.pumpWidget(host(const SizedBox(
      width: 400,
      child: Align(alignment: Alignment.centerRight, child: ImdChip('قصير')),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final box = tester.getSize(find.byType(ImdChip));
    expect(box.width, lessThan(200),
        reason: 'الشارة القصيرة تمدّدت لعرض أبيها بدل عرض نصها');
    expect(box.width, greaterThan(20));
  });

  testWidgets('شارة بأيقونة ونص طويل تُقصّ ولا تفيض', (tester) async {
    await tester.pumpWidget(host(const SizedBox(
      width: 100,
      child: ImdChip('تحذير طويل يحتاج مساحة أكبر بكثير', icon: 'alert'),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // تغطية شاشة الإعدادات نفسها في `ration_transfer_pull_test.dart`: هناك
  // تُفتح الشاشة ويُتحقَّق من خلوّها من الفيض. ولا تُكرَّر هنا لأن
  // `pumpAndSettle` عليها لا يستقرّ في هذا الملف — وهو عطلٌ ثانٍ مستقلّ عن
  // الفيض، ظهر قبل هذا الإصلاح وبقي بعده.
}
