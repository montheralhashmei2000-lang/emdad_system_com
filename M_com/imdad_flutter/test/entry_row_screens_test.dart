import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/features/inventory/doc_kit.dart' show ImdEntryRowGrid;
import 'package:imdad/features/inventory/issue_screen.dart';
import 'package:imdad/features/inventory/receive_screen.dart';
import 'package:imdad/features/inventory/returns_screen.dart';
import 'package:imdad/features/inventory/transfer_screen.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشات السندات الأربع تمرّ كلّها من [ImdEntryRowGrid].
///
/// كان لكلٍّ منها نسخةٌ يدويّةٌ من التخطيط نفسه — أربع نسخٍ متطابقة تقريبًا —
/// تضع «الصنف والوحدة» في صفّ و«الكمية» وحدها تحتهما. فمن أصلح واحدةً نسي
/// البقية. والآن مصدرٌ واحد: إصلاحه يصلح الأربع.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    final repo = CatalogRepo(db);
    // التحويل يلزمه مستودعان (مصدرٌ وهدف) وإلا لم يُرسم جدول أسطره.
    await repo.saveWarehouse(name: 'المخزن الرئيسي', code: 'W1');
    await repo.saveWarehouse(name: 'مخزن المعسكر', code: 'W2');
    await repo.saveItem(code: 'I1', name: 'أرز', baseUnit: 'كجم');
    await repo.saveUnit(code: 'U1', name: 'وحدة أولى');
  });

  tearDown(() => db.close());

  Future<void> show(WidgetTester tester, Widget screen) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
        ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: screen),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    debugDefaultTargetPlatformOverride = null;
  }

  final screens = <String, Widget>{
    'الصرف': const IssueScreen(),
    'الاستلام': const ReceiveScreen(),
    'التحويل': const TransferScreen(),
    'المرتجعات': const ReturnsScreen(),
  };

  screens.forEach((name, screen) {
    testWidgets('$name: سطر الصنف يمرّ من الشبكة المشتركة بلا فيض', (tester) async {
      await show(tester, screen);
      expect(find.byType(ImdEntryRowGrid), findsWidgets,
          reason: '$name ما زالت على تخطيطها اليدوي');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('الوحدة والكمية في صفٍّ واحد على هاتف ٣٦٠', (tester) async {
    await show(tester, const ReceiveScreen());
    final unit = find.text('الوحدة');
    final qty = find.text('الكمية');
    expect(unit, findsWidgets);
    expect(qty, findsWidgets);
    // عنوانا الحقلين على ارتفاعٍ واحد ⇒ حقلاهما في صفٍّ واحد.
    expect(tester.getCenter(unit.first).dy,
        closeTo(tester.getCenter(qty.first).dy, 1),
        reason: 'الكمية ما زالت في صفٍّ تحت الوحدة');
  });
}
