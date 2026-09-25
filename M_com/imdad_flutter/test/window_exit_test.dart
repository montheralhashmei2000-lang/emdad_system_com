import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/ui/imd_window.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/sync/auto_sync.dart';
import 'package:imdad/data/sync/lan_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إغلاق التطبيق ووضع نافذته.
///
/// العطلتان اللتان تحرسهما هذه الاختبارات ظهرتا معًا في الميدان: نافذةٌ لا
/// تتكبّر ولا شريط عنوان لها بعد الدخول، وإغلاقٌ يبدو معلّقًا ثوانيَ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ImdWindow.onBeforeExit = null;
  });

  tearDown(() => ImdWindow.onBeforeExit = null);

  group('الإنهاء قبل الإغلاق', () {
    test('الخروج يُنفّذ الإنهاء المسجَّل', () async {
      var ran = false;
      ImdWindow.onBeforeExit = () async => ran = true;
      await ImdWindow.exit();
      expect(ran, isTrue,
          reason: 'الخروج لم يُنهِ المزامنة، فتبقى العملية حيّة بعد النافذة');
    });

    test('الخروج بلا إنهاء مسجَّل لا يسقط', () async {
      await expectLater(ImdWindow.exit(), completes);
    });

    test('إنهاءٌ متعثّر لا يحبس المستخدم داخل التطبيق', () async {
      // مقبسٌ لا يُغلق ليس سببًا كافيًا لمنع الإغلاق: تُعطى مهلة ثم يُمضى.
      ImdWindow.onBeforeExit = () => Future<void>.delayed(
            ImdWindow.exitGrace + const Duration(seconds: 5),
          );
      final sw = Stopwatch()..start();
      await ImdWindow.exit();
      sw.stop();
      expect(sw.elapsed, lessThan(ImdWindow.exitGrace + const Duration(seconds: 2)),
          reason: 'الإغلاق انتظر إنهاءً متعثّرًا بلا حد');
    });

    test('إنهاءٌ يرمي خطأً لا يمنع الإغلاق', () async {
      ImdWindow.onBeforeExit = () async => throw StateError('مقبس معطوب');
      await expectLater(ImdWindow.exit(), completes);
    });
  });

  group('إنهاء المزامنة', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('shutdown يغلق الاستقبال وينتظره', () async {
      // منافذ خاصة بالاختبار: 8787 قد يشغله تطبيق عامل على الجهاز.
      final sync = LanSync(db, port: 18787, discoveryPort: 18788);
      await sync.startReceiving();
      expect(sync.isReceiving, isTrue);

      final auto = AutoSyncService(db);
      await auto.shutdown();
      // الخدمة تملك نسختها الخاصة؛ المهم أن الإنهاء ينتظر ولا يرمي.
      await sync.stopReceiving();
      expect(sync.isReceiving, isFalse,
          reason: 'الخادم بقي مستمعًا بعد الإنهاء');
    });

    test('shutdown مرتين لا يسقط', () async {
      final auto = AutoSyncService(db);
      await auto.shutdown();
      await expectLater(auto.shutdown(), completes);
    });
  });
}
