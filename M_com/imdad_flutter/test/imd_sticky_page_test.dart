import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/features/inventory/doc_kit/imd_sticky_page.dart';

/// `ImdStickyPage` بمحتوى بعد الشريط (`after`): المسافة التي تحجز مكان الشريط
/// العائم كانت تُدرج **بين** الشريط و`after`، فإذا انقلب التثبيت قفز ما بعده
/// بارتفاع الشريط — وزرٌّ مُرِّر إلى العرض لتوّه ينزلق خارجه فيضيع النقر.
void main() {
  testWidgets('ما بعد الشريط لا يقفز حين ينقلب التثبيت', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ImdStickyPage(
          sticky: const ImdStickyActions(children: [Text('حفظ')]),
          after: [
            TextButton(onPressed: () => taps++, child: const Text('بعد الشريط')),
            const SizedBox(height: 1500),
          ],
          children: const [SizedBox(height: 1500)],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final target = find.text('بعد الشريط');
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('بلا after: الحجز في آخر المحتوى كما كان', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: ImdStickyPage(
          sticky: ImdStickyActions(children: [Text('حفظ')]),
          children: [SizedBox(height: 1500), Text('آخر حقل')],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final last = find.text('آخر حقل');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    // في نهاية التمرير يظهر آخر حقل فوق الشريط العائم لا تحته.
    final bar = tester.getRect(find.text('حفظ').hitTestable());
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(bar.top));
  });
}
