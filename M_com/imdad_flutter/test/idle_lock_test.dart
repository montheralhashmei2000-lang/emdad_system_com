import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/idle_lock.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/features/auth/idle_lock_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// القفل التلقائي بعد الخمول: المنطق (ساعة مُحاكاة) والغطاء (كلمة المرور).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  var now = DateTime(2026, 10, 4, 9);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime(2026, 10, 4, 9);
  });
  tearDown(() => db.close());

  IdleLock make() => IdleLock(db, clock: () => now, tick: const Duration(hours: 1));

  group('المنطق', () {
    test('الافتراضي ١٥ دقيقة، ولا قفل قبل المهلة', () {
      final lock = make()..activate();
      addTearDown(lock.dispose);
      expect(lock.minutes, IdleLock.defaultMinutes);

      now = now.add(const Duration(minutes: 14, seconds: 59));
      expect(lock.checkNow(), isFalse);
      expect(lock.locked, isFalse);
    });

    test('يُقفل عند انقضاء المهلة، والنشاط يؤجّله', () {
      final lock = make()..activate();
      addTearDown(lock.dispose);

      now = now.add(const Duration(minutes: 10));
      lock.touch(); // نشاط
      now = now.add(const Duration(minutes: 10));
      expect(lock.checkNow(), isFalse, reason: '١٠ دقائق فقط منذ آخر نشاط');

      now = now.add(const Duration(minutes: 5));
      expect(lock.checkNow(), isTrue);
      expect(lock.locked, isTrue);
    });

    test('أثناء القفل لا يفتحه النشاط، والفتح يعيد ضبط المهلة', () {
      final lock = make()..activate();
      addTearDown(lock.dispose);
      lock.lockNow();

      lock.touch();
      expect(lock.locked, isTrue);

      lock.unlock();
      expect(lock.locked, isFalse);
      now = now.add(const Duration(minutes: 14));
      expect(lock.checkNow(), isFalse);
    });

    test('المعطَّل (٠) لا يقفل أبدًا، والإعداد يُحفظ في القاعدة ويُقرأ', () async {
      final lock = make();
      await lock.setMinutes(0);
      lock.activate();
      addTearDown(lock.dispose);
      now = now.add(const Duration(days: 2));
      expect(lock.checkNow(), isFalse);

      await lock.setMinutes(5);
      expect((await SettingsRepo(db).read('security'))['idleLockMinutes'], 5);

      final other = make();
      await other.load();
      expect(other.minutes, 5);
      expect(SettingsRepo.localOnlyKeys, contains('security'), reason: 'إعداد الجهاز لا يسافر');
    });

    test('غير نشط (قبل الدخول أو بعد الخروج) لا يقفل، والخروج يُزيل القفل', () {
      final lock = make();
      now = now.add(const Duration(hours: 3));
      expect(lock.checkNow(), isFalse);
      lock.lockNow();
      expect(lock.locked, isFalse);

      lock.activate();
      lock.lockNow();
      expect(lock.locked, isTrue);
      lock.deactivate();
      expect(lock.locked, isFalse);
      lock.dispose();
    });
  });

  group('الغطاء', () {
    testWidgets('يعرض الغطاء، يرفض كلمة خاطئة، ويفتح بالصحيحة، ويخرج بزر الخروج', (tester) async {
      // مستخدم ببصمة سريعة (١٠٠٠ دورة): التحقق فوريّ، أما الترقية بعد النجاح فتأخذ وقتها.
      const salt = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'u1',
            username: 'sara',
            name: const Value('سارة'),
            saltHex: const Value(salt),
            hashHex: Value(Pbkdf2.deriveHex('right-pass-1', salt, iterations: 1000)),
            iterations: const Value(1000),
          ));
      await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
            key: 'authSession',
            value: Value('{"userId":"u1","startedAt":${DateTime.now().millisecondsSinceEpoch}}'),
          ));
      final auth = AuthService(db);
      expect((await auth.restoreSession())?.username, 'sara');

      final lock = IdleLock(db)..activate();
      var signedOut = 0;

      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: IdleLockHost(
            lock: lock,
            auth: auth,
            onSignOut: () async => signedOut++,
            child: Scaffold(body: Center(child: TextButton(onPressed: () => taps++, child: const Text('المحتوى')))),
          ),
        ),
      ));

      await tester.tap(find.text('المحتوى'));
      expect(taps, 1, reason: 'غير مقفل: المحتوى يستجيب');
      expect(find.text('الشاشة مقفلة'), findsNothing);

      lock.lockNow();
      await tester.pump();
      expect(find.text('الشاشة مقفلة'), findsOneWidget);
      expect(find.textContaining('سارة'), findsOneWidget);
      // المحتوى خلف الغطاء معزول عن اللمس.
      await tester.tap(find.text('المحتوى'), warnIfMissed: false);
      expect(taps, 1);

      // كلمة خاطئة.
      await tester.enterText(find.byType(TextField), 'wrong-pass');
      await tester.tap(find.text('فتح'));
      await tester.pump();
      for (var i = 0; i < 100 && find.textContaining('غير صحيحة').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(lock.locked, isTrue);
      expect(find.textContaining('غير صحيحة'), findsOneWidget);

      // زر الخروج.
      await tester.tap(find.text('تسجيل الخروج'));
      await tester.pump();
      expect(signedOut, 1);

      // كلمة صحيحة (تشمل ترقية البصمة إلى العدد الحالي من الدورات فتطول).
      await tester.enterText(find.byType(TextField), 'right-pass-1');
      await tester.tap(find.text('فتح'));
      await tester.pump();
      // الإنجاز يُمرَّر عبر مصنع الزمن المحاكى: ننتظر حقيقيًّا ثم نضخّ.
      for (var i = 0; i < 200 && lock.locked; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(lock.locked, isFalse);
      expect(find.text('الشاشة مقفلة'), findsNothing);
      await tester.tap(find.text('المحتوى'));
      expect(taps, 2, reason: 'بعد الفتح يعمل المحتوى من جديد بحالته');
      // المؤقّت الدوري يُلغى قبل نهاية الاختبار (يتحقق الإطار من عدم بقاء مؤقّتات).
      lock.deactivate();
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
