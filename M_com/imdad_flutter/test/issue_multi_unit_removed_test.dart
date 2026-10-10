import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/domain/issue_rules.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/features/inventory/doc_kit/imd_form_layout.dart';
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «صرف لوحدات متعددة» حُذف من شاشة الصرف (التبويب الرابع `_type == 3`).
///
/// الحذف في الواجهة وحدها: سنداتٌ محفوظة بـ`targetType = 3` يقرؤها دفتر
/// المعسكر والأسطوانات وإعادة الطباعة، فـ[IssueTarget.multiUnit] باقٍ.
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
    await catalog.saveUnit(code: 'U1', name: 'السرية الأولى');
  });

  tearDown(() => db.close());

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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  testWidgets('أنواع التوجيه ثلاثة: لا «وحدات متعددة»', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    final pills = tester.widget<ImdTargetPills<int>>(find.byType(ImdTargetPills<int>));
    expect([for (final t in pills.tabs) t.label], ['وحدة مستفيدة', 'مطبخ / فرن', 'استثنائي / مخصص']);
    expect(find.text('وحدات متعددة'), findsNothing);
    expect(find.text('الوحدة المستفيدة'), findsNothing, reason: 'عمود الوحدة لكل سطر كان للتبويب المحذوف');
  });

  testWidgets('مسودةٌ محفوظة على «وحدات متعددة» تعود إلى «وحدة مستفيدة»', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'imdad.issue.recovery.${auth.currentUser!.id}',
      jsonEncode({
        'type': 3,
        'warehouse': '',
        'date': '2026-09-02',
        'rows': [
          {'item': '', 'unit': '', 'qty': '7', 'notes': 'مسودة_قديمة', 'beneficiary': 'x'},
        ],
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('مسودة_قديمة'), findsOneWidget, reason: 'المسودة نفسها تُستعاد');
    final pills = tester.widget<ImdTargetPills<int>>(find.byType(ImdTargetPills<int>));
    expect(pills.value, 0);
  });

  test('IssueTarget.multiUnit باقٍ للسندات المحفوظة', () {
    expect(IssueTarget.of(3), IssueTarget.multiUnit);
  });
}
