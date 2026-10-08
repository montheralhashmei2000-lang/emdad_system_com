import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart' show ImdIconButton, ImdButton;
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/features/catalog/items_screen.dart';
import 'package:imdad/features/catalog/kitchens_screen.dart';
import 'package:imdad/features/catalog/suppliers_screen.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// زرُّ الحذف يتبع صلاحية الحذف وحدها — لا «قابليةَ الكتابة».
///
/// [Perm.writable] يصدق بأيِّ إجراءٍ من الأربعة (إضافة/تعديل/حذف/اعتماد). وكانت
/// شاشات الكتالوج والتشغيل اليومي والمحروقات تُظهر زرَّ الحذف به، وبعضُ دوالِّ
/// الحذف بلا حارسٍ داخلي. وقالب «أمين مخزن» يمنح الأصناف والموردين والوحدات
/// والمطابخ والأصول **إضافةً وتعديلًا بلا حذف** صراحةً (انظر وصفَ القالب في
/// `AccessControl.roles`) — فكان أمينُ المخزن يرى الزرَّ ويحذف ما لا يملك حذفه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppDatabase? db;
  late AuthService auth;

  tearDown(() async {
    await db?.close();
    db = null;
  });

  /// يُسجِّل مستخدمًا بقوالب [roleIds] ويُدخله.
  Future<void> loginAs(WidgetTester tester, List<String> roleIds) async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db!);
    await tester.runAsync(() async {
      await UsersRepo(db!).createUser(
        username: 'keeper',
        password: 'Test@12345',
        name: 'أمين',
        permissions: AccessControl.permissionsForRoles(roleIds),
      );
      await auth.login('keeper', 'Test@12345');
    });
  }

  Future<void> seed() async {
    final repo = CatalogRepo(db!);
    await repo.saveCategory(name: 'بقوليات');
    await repo.saveItem(code: 'I1', name: 'أرز', categoryName: 'بقوليات');
    await repo.saveSupplier(name: 'مورد');
    await repo.saveFacility(name: 'مطبخ أ', fType: 'KITCHEN');
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db!),
        Provider<AuthService>.value(value: auth),
        ChangeNotifierProvider<ImdTheme>.value(value: ImdTheme(ThemeMode.light)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: screen)),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
  }

  Finder trash() => find.byWidgetPredicate((w) =>
      (w is ImdIconButton && w.icon == 'trash') ||
      (w is ImdButton && w.icon == 'trash'));

  group('قالب أمين المخزن: تعديلٌ بلا حذف', () {
    test('القالب نفسه يمنح التعديل ويمنع الحذف في الكتالوج', () async {
      final perms = AccessControl.permissionsForRoles(['storekeeper']);
      for (final page in ['items', 'suppliers', 'units', 'kitchens', 'assets']) {
        expect(AccessControl.can(isAdmin: false, permissions: perms, page: page, action: PermAction.edit), isTrue,
            reason: '$page: القالب يمنح التعديل');
        expect(AccessControl.can(isAdmin: false, permissions: perms, page: page, action: PermAction.delete), isFalse,
            reason: '$page: القالب لا يمنح الحذف');
      }
    });

    testWidgets('الأصناف: لا زرَّ حذفٍ لمن لا يملك الحذف', (tester) async {
      await loginAs(tester, ['storekeeper']);
      await tester.runAsync(seed);
      expect(Perm(auth).writable('items'), isTrue, reason: 'يملك التعديل فهو «قابل للكتابة»');
      expect(Perm(auth).canDelete('items'), isFalse);
      await show(tester, const ItemsScreen());
      expect(trash(), findsNothing, reason: 'زرُّ الحذف ظهر لمن لا يملك الحذف');
      expect(tester.takeException(), isNull);
    });

    testWidgets('الموردون: لا زرَّ حذف', (tester) async {
      await loginAs(tester, ['storekeeper']);
      await tester.runAsync(seed);
      await show(tester, const SuppliersScreen());
      expect(trash(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('المطابخ: لا زرَّ حذف', (tester) async {
      await loginAs(tester, ['storekeeper']);
      await tester.runAsync(seed);
      await show(tester, const KitchensScreen());
      expect(trash(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('من يملك الحذف يراه', () {
    testWidgets('الأصناف: المدير يرى زرَّ الحذف', (tester) async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      auth = AuthService(db!);
      await tester.runAsync(() async {
        await auth.createAdmin(username: 'admin', password: 'Test@12345');
        await auth.login('admin', 'Test@12345');
        await seed();
      });
      expect(Perm(auth).canDelete('items'), isTrue);
      await show(tester, const ItemsScreen());
      expect(trash(), findsWidgets, reason: 'المدير يملك كل الإجراءات');
      expect(tester.takeException(), isNull);
    });
  });

  group('حارسٌ داخليٌّ لا يُكتفى بإخفاء الزر', () {
    test('Perm.canDelete لا يتأثر بالإضافة أو التعديل أو الاعتماد', () async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      auth = AuthService(db!);
      await UsersRepo(db!).createUser(
        username: 'partial',
        password: 'Test@12345',
        name: 'جزئي',
        permissions: {
          'items': {
            PermAction.view: true,
            PermAction.create: true,
            PermAction.edit: true,
            PermAction.approve: true,
          },
        },
      );
      await auth.login('partial', 'Test@12345');
      final perm = Perm(auth);
      expect(perm.writable('items'), isTrue);
      expect(perm.canDelete('items'), isFalse,
          reason: 'ثلاثة إجراءاتٍ لا تصنع إذنَ حذف');
    });
  });
}
