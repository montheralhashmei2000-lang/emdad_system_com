import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
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
      child: MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: const Scaffold(body: FormsDesignerScreen()),
        ),
      ),
    ));
    // تحميل التخطيط يجري خارج الإطار.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  /// أيقونات الشاشة رسوم SVG، فيُعثر على الأزرار عبر تلميحاتها.
  Finder buttonsByTip(String tip) => find.byTooltip(tip);

  Future<PrintLayout> saved() => SettingsRepo(db).printLayout();

  testWidgets('تحريك سطر الترويسة لأسفل يغيّر ترتيبه المحفوظ', (tester) async {
    await pumpScreen(tester);
    final before = (await saved()).right.map((l) => l.text).toList();
    expect(before.length, greaterThan(1));

    // أول زر «تحريك لأسفل» يخص السطر الأول من الترويسة.
    await tester.tap(buttonsByTip('تحريك لأسفل').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التخطيط').first);
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
    await tester.tap(find.text('حفظ التخطيط').first);
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
    await tester.tap(find.text('حفظ التخطيط').first);
    await tester.pumpAndSettle();

    expect((await saved()).table.headBold, isNot(before));
  });

  testWidgets('«تغييرات غير محفوظة» تظهر بالتعديل وتختفي بعد الحفظ', (tester) async {
    await pumpScreen(tester);
    expect(find.text('تغييرات غير محفوظة'), findsNothing);

    await tester.tap(buttonsByTip('إخفاء').first);
    await tester.pumpAndSettle();
    expect(find.text('تغييرات غير محفوظة'), findsWidgets);

    await tester.tap(find.text('حفظ التخطيط').first);
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
