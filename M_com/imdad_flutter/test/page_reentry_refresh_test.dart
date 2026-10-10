import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_form.dart';
import 'package:imdad/core/ui/imd_page_dirty.dart';
import 'package:imdad/core/ui/imd_page_tabs.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/features/catalog/items_screen.dart';
import 'package:imdad/features/home/home_shell.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// العودة إلى صفحةٍ مخفيّة تغيّرت بياناتها.
///
/// كان يظهر شريط «تغيّرت بيانات النظام من صفحةٍ أخرى» وزرّ تحديثٍ يدوي. الآن
/// تُعاد بناءً صامتًا عند العودة — إلا إن عدّل المستخدم فيها شيئًا: إعادة
/// البناء تمحو سندًا نصف مملوء، فتبقى المعدَّلة كما هي بنقطةٍ على تبويبها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('علامة التعديل في الحقول', () {
    testWidgets('كتابة المستخدم ترفعها، والتعبئة البرمجية لا', (tester) async {
      final flag = ImdDirtyFlag();
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ImdPageDirty(flag: flag, child: ImdFld(controller: ctrl))),
      ));
      ctrl.text = 'تعبئة برمجية';
      await tester.pump();
      expect(flag.dirty, isFalse);
      await tester.enterText(find.byType(TextField), 'كتابة المستخدم');
      expect(flag.dirty, isTrue);
    });
  });

  group('القشرة', () {
    late AppDatabase db;
    late AuthService auth;
    late AutoSyncService autoSync;
    late ImdTheme imdTheme;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      autoSync = AutoSyncService(db);
      imdTheme = ImdTheme(ThemeMode.light);
      auth = AuthService(db);
      await auth.createAdmin(username: 'admin', password: 'Test@12345');
      await auth.login('admin', 'Test@12345');
      SharedPreferences.setMockInitialValues({
        'imdad.space.${auth.currentUser!.id}': AppSpace.supply,
      });
    });

    tearDown(() => db.close());

    Widget host() => MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            Provider<AuthService>.value(value: auth),
            ChangeNotifierProvider<AutoSyncService>.value(value: autoSync),
            ChangeNotifierProvider<ImdTheme>.value(value: imdTheme),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: HomeShell(onSignOut: () async {}),
            ),
          ),
        );

    Future<void> pump(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();
    }

    /// يفتح «الأصناف» ثم يعود إلى الرئيسية، ويكتب في القاعدة والأصناف مخفيّة.
    Future<(ImdNav, State)> openItemsThenChangeData(WidgetTester tester, {bool edit = false}) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await pump(tester);
      final nav = ImdNav.of(tester.element(find.byType(ImdPageTabs)));
      nav.go('items');
      await pump(tester);
      final first = tester.state(find.byType(ItemsScreen, skipOffstage: false));
      // ما يفعله كل حقلٍ من حقول البيت عند تعديل المستخدم.
      if (edit) ImdPageDirty.mark(tester.element(find.byType(ItemsScreen, skipOffstage: false)));
      nav.go('dash');
      await pump(tester);
      await tester.runAsync(() => CatalogRepo(db).saveWarehouse(code: 'W9', name: 'مستودع جديد'));
      await pump(tester);
      final tab = tester.widget<ImdPageTabs>(find.byType(ImdPageTabs)).pages.firstWhere((p) => p.id == 'items');
      expect(tab.stale, isTrue, reason: 'الكتابة والصفحة مخفيّة تعلّمها');
      return (nav, first);
    }

    bool itemsStale(WidgetTester tester) =>
        tester.widget<ImdPageTabs>(find.byType(ImdPageTabs)).pages.firstWhere((p) => p.id == 'items').stale;

    testWidgets('صفحة نظيفة: تُعاد بناءً صامتًا عند العودة، بلا شريط', (tester) async {
      final (nav, first) = await openItemsThenChangeData(tester);
      nav.go('items');
      await pump(tester);
      expect(tester.takeException(), isNull);
      final second = tester.state(find.byType(ItemsScreen));
      expect(identical(first, second), isFalse, reason: 'الصفحة لم تُبنَ من جديد');
      expect(itemsStale(tester), isFalse);
      expect(find.textContaining('تغيّرت بيانات النظام'), findsNothing);
      expect(find.text('تحديث الصفحة'), findsNothing);
    });

    testWidgets('صفحة معدَّلة: لا تُمسّ، وتبقى نقطتها', (tester) async {
      final (nav, first) = await openItemsThenChangeData(tester, edit: true);
      nav.go('items');
      await pump(tester);
      expect(tester.takeException(), isNull);
      final second = tester.state(find.byType(ItemsScreen));
      expect(identical(first, second), isTrue, reason: 'أُعيد بناء صفحةٍ فيها تعديلٌ لم يُحفظ');
      expect(itemsStale(tester), isTrue);
      expect(find.textContaining('تغيّرت بيانات النظام'), findsNothing);
    });
  });
}
