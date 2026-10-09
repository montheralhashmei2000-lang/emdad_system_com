import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/domain/print_forms.dart';
import 'package:imdad/domain/print_layout.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/settings/forms_designer_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة «مصمم النماذج المطبوعة»: إصلاحات إعادة الترتيب والحذف والإضافة وحارس
/// المغادرة ومفتاح عناوين الجدول. كلها سلوك واجهة لا يظهر خلله في اختبار وحدة،
/// ولذلك تُختبر بضغط الأزرار فعلًا وقراءة ما يُحفظ في `SettingsRepo`.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// صفحة التنقّل الأخيرة التي طُلبت — يقرؤها اختبار حارس المغادرة.
  final navigated = <String>[];

  /// يركّب الشاشة داخل بيئة كاملة: قاعدة، ومدير مسجَّل الدخول (وإلا اختفت
  /// أزرار التحرير كلها)، ومزوّد التنقّل الذي يستعمله زر الرجوع.
  Future<void> pumpScreen(WidgetTester tester) async {
    // نافذة اختبار واسعة: الشاشة طويلة وأزرارها في شريط ثابت، وبالمقاس
    // الافتراضي (800×600) تقع أغلب العناصر خارج الإطار فلا تُلمس.
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = AuthService(db);
    // التجزئة تعمل في Isolate حقيقي، والوقت داخل testWidgets وهمي حتى runAsync.
    await tester.runAsync(() => auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin'));

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        Provider<ImdNav>.value(
          value: ImdNav(navigated.add, () => 'formsDesigner'),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: FormsDesignerScreen()),
        ),
      ),
    ));
    // تحميل التخطيط يجري خارج الإطار.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  /// أيقونات الشاشة رسوم SVG، فيُعثر على الأزرار بحقل `tooltip` في
  /// `ImdIconButton` أو بتسمية `Semantics` (Tooltip حُذف من الاثنين).
  Finder buttonsByTip(String tip) => find.byWidgetPredicate((w) =>
      (w is ImdIconButton && w.tooltip == tip) ||
      (w is Semantics && w.properties.label == tip));

  Future<PrintLayout> saved() => SettingsRepo(db).printLayout();

  testWidgets('تحريك سطر الترويسة لأسفل يغيّر ترتيبه المحفوظ', (tester) async {
    await pumpScreen(tester);
    final before = (await saved()).right.map((l) => l.text).toList();
    expect(before.length, greaterThan(1));

    // أول زر «تحريك لأسفل» يخص السطر الأول من الترويسة.
    await tester.tap(buttonsByTip('تحريك لأسفل').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الافتراضي العام').first);
    await tester.pumpAndSettle();

    final after = (await saved()).right.map((l) => l.text).toList();
    expect(after[0], before[1]);
    expect(after[1], before[0]);
  });

  testWidgets('سهم التحريك عند طرف القائمة لا يحرّك شيئًا', (tester) async {
    await pumpScreen(tester);
    final before = (await saved()).right.map((l) => l.text).toList();

    // أول «تحريك لأعلى» يخص السطر الأول، فهو معطّل: ضغطه لا يغيّر الترتيب
    // ولا يرمي استثناء، ولا تظهر معه علامة «تغييرات غير محفوظة».
    await tester.tap(buttonsByTip('تحريك لأعلى').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('تغييرات غير محفوظة'), findsNothing);
    expect((await saved()).right.map((l) => l.text).toList(), before);
  });

  testWidgets('حذف حقل من بيانات السند يُنقص القائمة المحفوظة', (tester) async {
    await pumpScreen(tester);
    final before = (await saved()).info.length;
    expect(before, greaterThan(0));

    // أزرار الحذف مرتبة: الترويسة ثم الحقول — نحذف آخر حقل في الشاشة.
    await tester.tap(buttonsByTip('حذف').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الافتراضي العام').first);
    await tester.pumpAndSettle();

    final after = await saved();
    expect(after.right.length + after.left.length + after.info.length +
        after.signatures.length + after.footer.length,
        lessThan(
          PrintLayout.defaults.right.length +
              PrintLayout.defaults.left.length +
              PrintLayout.defaults.info.length +
              PrintLayout.defaults.signatures.length +
              PrintLayout.defaults.footer.length,
        ));
  });

  testWidgets('مفتاح «عناوين عريضة» يُحفظ فعلًا في تنسيق الجدول', (tester) async {
    await pumpScreen(tester);
    final before = (await saved()).table.headBold;

    await tester.tap(find.text('عناوين عريضة'));
    await tester.pumpAndSettle();
    // الضغط على التسمية لا يبدّل؛ المفتاح نفسه هو زر التبديل بجوارها.
    await tester.tap(find.ancestor(
      of: find.text('عناوين عريضة'),
      matching: find.byType(Column),
    ).first);
    await tester.pumpAndSettle();

    // التبديل الفعلي عبر أيقونة «عريض» الأخيرة (مفتاح الجدول).
    await tester.tap(buttonsByTip('عريض').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الافتراضي العام').first);
    await tester.pumpAndSettle();

    expect((await saved()).table.headBold, isNot(before));
  });

  testWidgets('«تغييرات غير محفوظة» تظهر بالتعديل وتختفي بعد الحفظ', (tester) async {
    await pumpScreen(tester);
    expect(find.text('تغييرات غير محفوظة'), findsNothing);

    await tester.tap(buttonsByTip('إخفاء').first);
    await tester.pumpAndSettle();
    expect(find.text('تغييرات غير محفوظة'), findsWidgets);

    await tester.tap(find.text('حفظ الافتراضي العام').first);
    await tester.pumpAndSettle();
    expect(find.text('تغييرات غير محفوظة'), findsNothing);
  });

  testWidgets('حارس المغادرة يعترض الرجوع عند وجود تغييرات', (tester) async {
    await pumpScreen(tester);

    await tester.tap(buttonsByTip('إخفاء').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('رجوع إلى الإعدادات').first);
    await tester.pumpAndSettle();

    // يظهر تأكيد بدل المغادرة الصامتة، ولا تنتقل الشاشة قبل الإجابة.
    expect(find.text('الخروج بلا حفظ'), findsOneWidget);
    expect(navigated, isEmpty);
  });

  group('تفريد المطبوعات', () {
    /// الفهرس كله في منتقٍ واحد، والحفظ يسري على المطبوعة المختارة وحدها بعد
    /// إفرادها. كان المصمم يحرّر تخطيطًا واحدًا للنظام كله، ومنتقي شريطه لا
    /// يبدّل إلا بياناتِ المعاينة.
    /// منتقي المطبوعة بعينه: الشاشة فيها منتقٍ آخر (خط الطباعة).
    final formPicker = find.byWidgetPredicate(
        (w) => w is ImdSelect<String> && w.title == 'المطبوعة');

    Future<void> openForm(WidgetTester tester, String label) async {
      await tester.tap(formPicker);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(ImdPickerBody<String>),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, label);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('المنتقي يحمل مطبوعات القسمين والبرقيات والارتباطات', (tester) async {
      await pumpScreen(tester);
      await tester.tap(formPicker);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(ImdPickerBody<String>),
        matching: find.byType(TextField),
      );
      for (final label in ['سجل البرقيات', 'كشف القوة البشرية', 'سند صرف محروقات', 'أمر صرف']) {
        await tester.enterText(search, label);
        await tester.pumpAndSettle();
        expect(find.textContaining(label), findsWidgets, reason: label);
      }
    });

    testWidgets('إفراد «سجل البرقيات» يحفظ تصميمه وحده', (tester) async {
      await pumpScreen(tester);
      // التخطيط العام أولًا بقيمةٍ مميزة.
      await tester.enterText(find.byType(TextField).at(1), '19');
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ الافتراضي العام').first);
      await tester.pumpAndSettle();

      await openForm(tester, 'سجل البرقيات');
      // غير مُفردة بعد: الشريط يعرض الإفراد ويقول إنها تتبع العام.
      expect(find.text('إفراد هذه المطبوعة بتصميم'), findsOneWidget);
      expect(find.textContaining('تتبع الافتراضي العام'), findsWidgets);

      await tester.tap(find.text('إفراد هذه المطبوعة بتصميم'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '7');
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ تصميم المطبوعة').first);
      await tester.pumpAndSettle();

      // المطبوعة أُفردت، والعام لم يُمسّ.
      final repo = SettingsRepo(db);
      expect(await repo.customizedPrintForms(), contains(PrintForms.cableLog));
      expect((await repo.printLayoutFor(PrintForms.cableLog)).right.first.size, 7);
      expect((await repo.printLayout()).right.first.size, 19);
      expect((await repo.printLayoutFor(PrintForms.receipt)).right.first.size, 19);
    });

    testWidgets('«إعادتها إلى العام» تحذف التصميم الخاص', (tester) async {
      await tester.runAsync(() => SettingsRepo(db)
          .savePrintLayoutFor(PrintForms.roster, PrintLayout.defaults.copyWith(titleSize: 8)));
      await pumpScreen(tester);
      await openForm(tester, 'كشف القوة البشرية');

      expect(find.text('إعادتها إلى العام'), findsOneWidget);
      await tester.tap(find.text('إعادتها إلى العام'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعادة إلى العام').last);
      await tester.pumpAndSettle();

      expect(await SettingsRepo(db).customizedPrintForms(), isEmpty);
    });
  });

  testWidgets('«استعادة الافتراضي» تحدّث حقول الأرقام المعروضة', (tester) async {
    await pumpScreen(tester);

    // تغيير حجم أول سطر إلى قيمة مميزة.
    final sizeField = find.byType(TextField).at(1);
    await tester.enterText(sizeField, '33');
    await tester.pumpAndSettle();
    expect(find.text('33'), findsWidgets);

    await tester.tap(find.text('استعادة الافتراضي').first);
    await tester.pumpAndSettle();

    // بدون didUpdateWidget في _NumField يبقى «33» ظاهرًا رغم استعادة التخطيط.
    expect(find.text('33'), findsNothing);
  });
}
