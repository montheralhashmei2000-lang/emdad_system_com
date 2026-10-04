import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/linkage_repo.dart';
import 'package:imdad/features/linkages/link_finances.dart';
import 'package:imdad/main.dart' show ImdTheme;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة «المالية» ببيانات حقيقية في تبويباتها الأربعة: لا فيض ولا خطأ بناء،
/// وأعمدة الجداول تطابق خلاياها، على مقاسات سطح المكتب والجوال.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seed(AppDatabase db) async {
    final repo = LinkageRepo(db);
    await repo.insertCustody(const LinkFinCustodiesCompanion(
      id: Value('a'), title: Value('شراء مواد غذائية'), amount: Value(1000), currency: Value('sar'),
      giverName: Value('المالية'), receiverName: Value('سالم'), custodyDate: Value('2026-10-01'), dueDate: Value('2026-12-01'),
    ));
    await repo.insertCustody(const LinkFinCustodiesCompanion(
      id: Value('b'), title: Value('عهدة يمنية'), amount: Value(500000), currency: Value('yer'), exchangeRate: Value(400),
      kind: Value('delivered'), giverName: Value('أنا'), receiverName: Value('أحمد'), custodyDate: Value('2026-10-02'),
    ));
    await repo.insertContract(const LinkPurchaseContractsCompanion(
      id: Value('k'), title: Value('بهارات'), supplier: Value('الوكيل'), contractNo: Value('K-1'), invoiceNo: Value('INV-1'),
      listDate: Value('2026-10-03'), amount: Value(300), custodyId: Value('a'),
    ));
    await repo.saveCustodySheet(
      sheetNo: 'عهدة-00001', title: 'سالم', defaultRate: 400, notes: '', custodyId: 'a', currency: 'sar', holderName: 'سالم',
      rows: const [
        LinkCustodySheetRowsCompanion(date: Value('2026-10-03'), grantSar: Value(1000), spentSar: Value(300), invoiceNo: Value('INV-1')),
      ],
    );
    // إخلاء مسودة لعهدة a، ومُعتمد لعهدة ثالثة.
    await repo.saveCustodyClearance(custodyId: 'a', clearanceDate: '2026-10-05', workflow: LinkageRepo.wfDraft);
    await repo.insertCustody(const LinkFinCustodiesCompanion(
        id: Value('c'), title: Value('مُخلَّاة'), amount: Value(100), receiverName: Value('خالد')));
    await repo.saveCustodyClearance(custodyId: 'c', clearanceDate: '2026-10-06');
  }

  for (final size in const [Size(1280, 800), Size(800, 1280), Size(360, 740), Size(320, 568)]) {
    testWidgets('المالية بالتبويبات الأربعة ببيانات حقيقية ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final auth = AuthService(db);
      await tester.runAsync(() async {
        await auth.createAdmin(username: 'admin', password: 'Test@12345');
        await auth.login('admin', 'Test@12345');
        await seed(db);
      });
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
            child: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(child: LinkFinancesTab(repo: LinkageRepo(db), perm: Perm(auth))),
              ),
            ),
          ),
        ),
      ));

      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 80));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
      }

      await settle();
      expect(tester.takeException(), isNull, reason: 'العهد');
      // الفلتر الافتراضي «قيد الإخلاء»: عهدتان قائمتان (a, b)، والمُخلَّاة c مخفية.
      expect(find.text('شراء مواد غذائية'), findsWidgets);
      expect(find.text('مُخلَّاة'), findsNothing);

      for (final tab in ['الإخلاءات', 'عقود الشراء', 'مسير العهدة', 'العهد']) {
        await tester.ensureVisible(find.text(tab).first);
        await tester.pump();
        await tester.tap(find.text(tab).first);
        await settle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      // عاد إلى العهد؛ كشف الحساب يفتح بلا خطأ.
      await tester.tap(find.text('كشف حساب مالية'));
      await settle();
      expect(tester.takeException(), isNull, reason: 'كشف الحساب');
    });
  }
}
