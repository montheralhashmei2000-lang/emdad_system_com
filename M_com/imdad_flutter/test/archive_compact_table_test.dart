import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/archive/electronic_archive_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الأرشيف الإلكتروني: جدولٌ واحد مضغوط.
///
/// كان للعرض وجهان («جدول» و«بطاقات» بمعاينةٍ مصوّرة) يعرضان البيانات
/// والإجراءات نفسها؛ وصفّ الجدول نفسه كان سطرين بخمسة أزرار. الآن صفٌّ من
/// سطرٍ واحد بزرَّي «عرض» و«تنزيل» و«⋯» للباقي، وبطاقاتٌ نصية على الجوال.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUpAll(() async {
    final loader = FontLoader('IBMPlexSansArabic');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    for (var i = 1; i <= 3; i++) {
      await db.into(db.archiveFiles).insert(ArchiveFilesCompanion.insert(
            id: 'a$i',
            title: 'سند استلام رقم $i بعنوانٍ طويلٍ يكفي ليلتفّ في سطرين لو سُمح له',
            fileName: 'f$i.pdf',
            storedPath: 'x/f$i.pdf',
            sizeBytes: 1024 * i,
            category: const Value('استلامات'),
            tags: const Value('["عاجل","2026","مراجعة"]'),
            source: Value(i == 1 ? 'auto' : 'manual'),
            pinned: Value(i == 2),
          ));
    }
  });

  tearDown(() => db.close());

  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<AuthService>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: ElectronicArchiveScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  testWidgets('سطح المكتب: جدولٌ واحد بلا مفتاح «بطاقات»، وصفوفٌ من سطرٍ واحد', (tester) async {
    await show(tester, const Size(1600, 1000));
    expect(tester.takeException(), isNull);
    expect(find.text('بطاقات'), findsNothing);
    expect(find.byType(ImdTable), findsOneWidget);

    // صفّ الجدول: ارتفاع زرّ «عرض» المضغوط (٢٨) + حشوة ٤×٢ — لا سطران ولا خمسة أزرار.
    final view = find.byWidgetPredicate((w) => w is ImdIconButton && w.tooltip == 'عرض');
    expect(view, findsNWidgets(3));
    expect(find.byWidgetPredicate((w) => w is ImdIconButton && w.tooltip == 'تعديل البيانات'), findsNothing,
        reason: 'التعديل والحذف والتثبيت في «⋯» لا ظاهرةً في الصف');
    final rowH = tester.getSize(find.ancestor(of: view.first, matching: find.byType(TableCell)).first).height;
    expect(rowH, lessThanOrEqualTo(40), reason: 'ارتفاع الصف $rowH');

    // الوسوم: شارةٌ واحدة و«+ن».
    expect(find.text('+٢'), findsNWidgets(3));
  });

  testWidgets('«⋯» تفتح التثبيت والتعديل والحذف', (tester) async {
    await show(tester, const Size(1600, 1000));
    final more = find.byWidgetPredicate((w) => w is ImdIconButton && w.tooltip == 'إجراءات أخرى');
    expect(more, findsNWidgets(3));
    await tester.tap(more.first);
    await tester.pumpAndSettle();
    expect(find.text('تعديل البيانات'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
  });

  testWidgets('الجوال: بطاقاتٌ نصية بلا فيض', (tester) async {
    await show(tester, const Size(360, 740));
    expect(tester.takeException(), isNull);
    expect(find.text('بطاقات'), findsNothing);
  });
}
