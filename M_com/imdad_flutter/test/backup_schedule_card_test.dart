import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/data/backup/backup_scheduler.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/settings/backup_schedule_card.dart';
import 'package:provider/provider.dart';

/// بطاقة الجدولة تُبنى بلا فيض على الجوال وسطح المكتب، وتعكس حالة الإعداد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [320.0, 360.0, 900.0]) {
    testWidgets('تُبنى بلا فيض عند عرض ${width.toInt()}', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = MemoryBackupSecretStore();
      final scheduler = BackupScheduler(db, secrets: secrets, defaultDirectory: () async => 'C:/backups');
      addTearDown(scheduler.dispose);

      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(ChangeNotifierProvider<BackupScheduler>.value(
        value: scheduler,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: BackupScheduleCard())),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      expect(find.text('النسخ الاحتياطي التلقائي المشفّر'), findsOneWidget);
      expect(find.text('كلمة المرور غير مضبوطة'), findsOneWidget);
      expect(find.text('ضبط كلمة المرور'), findsOneWidget);
      expect(find.text('C:/backups'), findsOneWidget, reason: 'المجلد الافتراضي ظاهر');
    });
  }
}
