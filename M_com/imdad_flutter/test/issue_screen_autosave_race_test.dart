import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// استعادة مسودة الصرف التلقائية سباقٌ محتمل مع أول تفاعل للمستخدم:
/// `_restoreAutosave` قراءةٌ غير متزامنة (SharedPreferences ثم فكّ JSON)،
/// فقد يفتح المستخدم الشاشة ويختار صنفًا في الصفّ الافتراضي قبل اكتمالها.
///
/// كانت الاستعادة تستبدل كل الصفوف بلا تحقق، فتُسقط اختيار المستخدم فورًا
/// بمسودةٍ قديمة، وتهدم عنصر الصفّ (متحكّمه وعقدة تركيزه) وهو قيد
/// الاستخدام. الإصلاح: لا تُطبَّق الاستعادة إلا والنموذج ما يزال فارغًا
/// تمامًا (`_isPristine`).
void main() {
  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin');
    await auth.login('admin', 'Test@12345');
    final catalog = CatalogRepo(db);
    await catalog.saveWarehouse(code: 'W1', name: 'الرئيسي');
    await catalog.saveItem(
      code: 'R1',
      name: 'أرز',
      baseUnit: 'كجم',
      units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
    );
    await catalog.saveUnit(code: 'U1', name: 'السرية الأولى');
  });

  tearDown(() => db.close());

  Future<void> saveDraft({String note = 'ملاحظة_من_مسودةٍ_قديمة'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'imdad.issue.recovery.${auth.currentUser!.id}',
      jsonEncode({
        'type': 0,
        'warehouse': '',
        'date': '2026-09-02',
        'rows': [
          {'item': '', 'unit': '', 'qty': '7', 'notes': note},
        ],
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
          Provider<ImdNav>.value(value: ImdNav((_) {}, () => 'issue')),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: IssueScreen()),
          ),
        ),
      );

  testWidgets('بلا تفاعل: المسودة المحفوظة تُستعاد كاملة', (tester) async {
    await saveDraft();
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    // سلسلة التحميل غير المتزامنة كلّها تُستنفَد: لا تفاعل يسبقها.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    expect(find.textContaining('ملاحظة_من_مسودةٍ_قديمة'), findsOneWidget);
    expect(find.textContaining('استُعيدت مسودة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الحارس debugIsPristine يرصد أول تفاعلٍ فعلي من المستخدم',
      (tester) async {
    // بلا مسودة محفوظة هنا: هذا الاختبار عن الحارس نفسه لا عن الاستعادة.
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    final state = tester.state(find.byType(IssueScreen)) as dynamic;
    expect(state.debugIsPristine() as bool, isTrue,
        reason: 'صفٌّ افتراضيٌّ واحد فارغ — لا فرق عن حال initState.');

    // بالضبط ما يفعله المستخدم عند اختيار صنف: نقرٌ على الحقل، كتابة،
    // ونقرٌ على الاقتراح.
    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'أرز');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('أرز'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // هذه اللحظة بالضبط — بعد اختيار الصنف مباشرة — هي ما تحرسه
    // `_restoreAutosave`: لو وصلت قراءتها المؤجَّلة الآن، وجدت النموذج غير
    // فارغ فتخطّت الاستبدال، فلا يُهدم عنصر الصفّ ولا يضيع اختيار المستخدم.
    expect(state.debugIsPristine() as bool, isFalse,
        reason: 'اختيار صنفٍ يُخرج النموذج من حاله الفارغة فورًا.');
    expect(tester.takeException(), isNull);
  });
}
