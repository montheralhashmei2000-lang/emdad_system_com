import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/home/space_chooser_screen.dart';

/// مساحتا العمل: الإمداد والمحروقات.
///
/// القاعدة التي تحرسها هذه الاختبارات: **من يملك مساحةً واحدة لا يُسأل**.
/// شاشةُ اختيارٍ بخيارٍ واحد متاح ليست اختيارًا، بل نقرةٌ تُدفع كل يوم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ما يملكه المستخدم من مساحات', () {
    test('من له صفحات الإمداد وحدها يملك مساحةً واحدة', () {
      final spaces =
          AppSpace.availableFor((p) => AppSpace.pages[AppSpace.supply]!.contains(p));
      expect(spaces, [AppSpace.supply]);
    });

    test('من له صفحات المحروقات وحدها يملك مساحةً واحدة', () {
      final spaces =
          AppSpace.availableFor((p) => AppSpace.pages[AppSpace.fuel]!.contains(p));
      expect(spaces, [AppSpace.fuel]);
    });

    test('من له الاثنتان يملكهما', () {
      expect(AppSpace.availableFor((_) => true), AppSpace.all);
    });

    test('الإعدادات وحدها لا تمنح مساحة', () {
      // وإلا رأى مساحةً فارغة إلا من إعداداتٍ عامة.
      expect(AppSpace.availableFor((p) => p == 'settings'), isEmpty);
    });
  });

  group('أي مساحة تُفتح', () {
    test('صاحب مساحةٍ واحدة يدخلها بلا سؤال', () {
      expect(
        AppSpace.resolve(available: [AppSpace.fuel], saved: null),
        AppSpace.fuel,
      );
    });

    test('صاحب المساحتين بلا اختيار محفوظ يُسأل', () {
      expect(AppSpace.resolve(available: AppSpace.all, saved: null), isNull);
    });

    test('الاختيار المحفوظ يُحترم فلا يُسأل مرتين', () {
      expect(
        AppSpace.resolve(available: AppSpace.all, saved: AppSpace.fuel),
        AppSpace.fuel,
      );
    });

    test('محفوظٌ لم يعد متاحًا لا يحبس صاحبه', () {
      // تغيّرت صلاحياته فلم تبقَ له إلا الإمداد — لا يُفتح على المحروقات.
      expect(
        AppSpace.resolve(available: [AppSpace.supply], saved: AppSpace.fuel),
        AppSpace.supply,
      );
    });

    test('بلا مساحة أصلًا لا شيء يُفتح', () {
      expect(AppSpace.resolve(available: const [], saved: AppSpace.fuel), isNull);
    });
  });

  group('ترشيح البنود', () {
    test('المشترك يظهر في المساحتين', () {
      expect(AppSpace.shows(AppSpace.both, AppSpace.supply), isTrue);
      expect(AppSpace.shows(AppSpace.both, AppSpace.fuel), isTrue);
    });

    test('بند القسم لا يظهر في غيره', () {
      expect(AppSpace.shows(AppSpace.fuel, AppSpace.supply), isFalse);
      expect(AppSpace.shows(AppSpace.supply, AppSpace.fuel), isFalse);
    });
  });

  group('شاشة الاختيار', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(textDirection: TextDirection.rtl, child: child),
        );

    testWidgets('تعرض المساحتين بوصفيهما', (tester) async {
      await tester.pumpWidget(host(SpaceChooserScreen(
        spaces: AppSpace.all,
        userName: 'المنذر',
        onPick: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('الإمداد والتموين'), findsWidgets);
      expect(find.text('المحروقات'), findsWidgets);
      expect(find.textContaining('المنذر'), findsWidgets);
      expect(find.textContaining('تفريدة الوقود'), findsWidgets,
          reason: 'الوصف يُعرّف بالقسم قبل دخوله');
    });

    testWidgets('النقر يعيد المساحة المختارة', (tester) async {
      String? picked;
      await tester.pumpWidget(host(SpaceChooserScreen(
        spaces: AppSpace.all,
        userName: '',
        onPick: (v) => picked = v,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('المحروقات').first);
      await tester.pumpAndSettle();
      expect(picked, AppSpace.fuel);
    });

    testWidgets('تُبنى على عرض ضيّق بلا فيض', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(SpaceChooserScreen(
        spaces: AppSpace.all,
        userName: 'أمين',
        onPick: (_) {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
