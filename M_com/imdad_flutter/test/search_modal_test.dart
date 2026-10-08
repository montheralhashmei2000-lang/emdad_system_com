import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/search/search_modal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// لوحة البحث العام: الكتابة تبحث بعد مهلة، والسهمان وEnter يفتحان النتيجة،
/// وEsc يغلق. الفتح يُعيد **معرّف صفحة** النتيجة إلى الشل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;
  late List<String> opened;

  /// عقدةُ تركيزٍ **خارج** مسار الحوار — تحاكي ما يحدث فعلًا على ويندوز: غلاف
  /// `Focus(autofocus: true)` في `main.dart` فوق الـNavigator يملك التركيز،
  /// فلا يمرّ مفتاحٌ بشجرة الحوار إطلاقًا.
  final outside = FocusNode(debugLabel: 'outside-dialog');


  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    await auth.createAdmin(username: 'admin', password: 'Test@12345');
    await auth.login('admin', 'Test@12345');
    opened = [];
    await db.into(db.items).insert(ItemsCompanion.insert(
          id: 'i1',
          name: 'طحين فاخر',
          code: const Value('ITM-1'),
        ));
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: 's1', name: 'شركة الطحين'));
  });

  tearDown(() => db.close());
  tearDownAll(outside.dispose);

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Column(children: [
                Focus(focusNode: outside, child: const SizedBox(height: 8, width: 8)),
                Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => showSearchModal(ctx, onOpenPage: opened.add),
                    child: const Text('افتح'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  /// يفتح اللوحة ويكتب [q]، ثم يتجاوز مهلة الكتابة (300ms) وينتظر الاستعلام.
  Future<void> open(WidgetTester tester, {String? q}) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    if (q == null) return;
    await tester.enterText(find.byType(TextField), q);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('تفتح بحقلٍ مركَّزٍ ورسالةٍ قبل الكتابة', (tester) async {
    await open(tester);
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);
    expect(find.textContaining('ابحث في الأصناف'), findsOneWidget);
    expect(find.textContaining('اكتب حرفين'), findsOneWidget);
  });

  testWidgets('حرفٌ واحد لا يبحث', (tester) async {
    await open(tester, q: 'ط');
    expect(find.text('طحين فاخر'), findsNothing);
    expect(find.textContaining('اكتب حرفين'), findsOneWidget);
  });

  testWidgets('الكتابة تعرض النتائج مصنَّفةً بعناوين أنواعها', (tester) async {
    await open(tester, q: 'طحين');
    expect(find.text('طحين فاخر'), findsOneWidget);
    expect(find.text('شركة الطحين'), findsOneWidget);
    expect(find.textContaining('الأصناف'), findsWidgets);
    expect(find.textContaining('الموردون'), findsWidgets);
    expect(find.textContaining('نتائج: 2'), findsOneWidget);
  });

  testWidgets('الضغط على نتيجة يغلق اللوحة ويفتح صفحتها', (tester) async {
    await open(tester, q: 'طحين');
    await tester.tap(find.text('طحين فاخر'));
    await tester.pumpAndSettle();
    expect(opened, ['items']);
    expect(find.byType(TextField), findsNothing, reason: 'اللوحة أُغلقت');
  });

  testWidgets('Enter يفتح أول نتيجة، والسهم لأسفل ينقل إلى التالية', (tester) async {
    await open(tester, q: 'طحين');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['items'], reason: 'المختار أولًا هو أول نتيجة');

    await open(tester, q: 'طحين');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened.last, 'suppliers', reason: 'النتيجة الثانية مورد');
  });

  testWidgets('السهم لأعلى من الأولى يلتفّ إلى الأخيرة', (tester) async {
    await open(tester, q: 'طحين');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['suppliers']);
  });

  testWidgets('Esc يغلق بلا فتح شيء', (tester) async {
    await open(tester, q: 'طحين');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('Esc يغلق وإن فُقد التركيز من الحقل', (tester) async {
    await open(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'Esc يغلق مهما كان التركيز');
  });

  testWidgets('Esc يغلق بعد الكتابة وفقدان التركيز', (tester) async {
    await open(tester, q: 'طحين');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('Esc يغلق وإن كان التركيز خارج شجرة الحوار', (tester) async {
    await open(tester, q: 'طحين');
    outside.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, outside, reason: 'التركيز خارج الحوار');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'Esc يغلق مهما كان التركيز');
    expect(opened, isEmpty);
  });

  testWidgets('مدخلٌ بلا نتائج يعرض رسالةً تذكر المدخل', (tester) async {
    await open(tester, q: 'زعفران');
    // «زعفران» يظهر أيضًا في الحقل نفسه، فيُطابَق نصّ الرسالة كاملًا.
    expect(find.text('لم أجد نتائج لـ«زعفران»'), findsOneWidget);
  });

  testWidgets('الاستعلام لا يُنفَّذ قبل انقضاء المهلة', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'طحين');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('طحين فاخر'), findsNothing, reason: 'المهلة لم تنقضِ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('طحين فاخر'), findsOneWidget);
  });

  testWidgets('إغلاق اللوحة بعد الكتابة لا يترك مؤقّتًا يرتدّ', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'طحين');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
