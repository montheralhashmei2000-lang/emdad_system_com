import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/core/security/device_activation.dart';
import 'package:imdad/core/security/esign.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_qr.dart';
import 'package:imdad/core/ui/imd_widgets.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/features/settings/device_activation_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة التفعيل على جهاز الإدارة: QR للرمز الصادر، وسجلّ الأجهزة وإجراءاته.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
    // الجهاز يحمل مفتاح المالك الخاص فتظهر لوحتا الإصدار والسجلّ. المفتاح المدفون
    // في الإصدار حقيقي، فيُستخدم هنا وضع التطوير (بلا مفتاح مدفون) بنسخةٍ
    // مبنيّةٍ على مفتاحٍ مولَّد.
    final pair = ESign.generateKeyPair();
    final act = DeviceActivation(db, ownerPublicKey: pair.publicB64);
    await act.importPrivateKey(pair.privateHex);
    await act.issue(
      deviceId: 'ABCD2345',
      name: 'حاسوب المخزن',
      branch: 'اللواء الأول',
      expiresAt: DateTime.now().add(const Duration(days: 60)),
    );
  });

  tearDown(() => db.close());

  Widget host() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          Provider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: DeviceActivationScreen(standalone: true)),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  Finder iconBtn(String tooltip) =>
      find.byWidgetPredicate((w) => w is ImdIconButton && w.tooltip == tooltip);

  testWidgets('السجلّ يعرض الجهاز المُصدَر له باسمه وحالته', (tester) async {
    await pump(tester);
    expect(find.textContaining('الأجهزة المُصدَر لها (1)'), findsOneWidget);
    expect(find.text('حاسوب المخزن'), findsOneWidget);
    expect(find.descendant(of: find.byType(ImdTable), matching: find.text('ABCD2345')), findsOneWidget);
    expect(find.text('مفعَّل'), findsOneWidget);
  });

  testWidgets('إلغاء التفعيل ثم إعادته', (tester) async {
    await pump(tester);
    await tester.ensureVisible(iconBtn('إلغاء التفعيل'));
    await tester.tap(iconBtn('إلغاء التفعيل'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('إلغاء التفعيل').last);
    await pump(tester);

    expect(find.text('ملغى'), findsOneWidget);
    expect(await DeviceActivation(db).isRevoked('ABCD2345'), isTrue);
    expect(iconBtn('إعادة التفعيل'), findsOneWidget);
  });

  testWidgets('إعادة تسمية الجهاز', (tester) async {
    await pump(tester);
    await tester.ensureVisible(iconBtn('تعديل الاسم'));
    await tester.tap(iconBtn('تعديل الاسم'));
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(field, 'هاتف المشرف');
    await tester.tap(find.text('حفظ'));
    await pump(tester);

    expect(find.text('هاتف المشرف'), findsOneWidget);
    expect((await DeviceActivation(db).registry()).single.name, 'هاتف المشرف');
  });

  testWidgets('الحذف من السجل يطلب تأكيدًا ولا يرفع الإلغاء', (tester) async {
    await pump(tester);
    await DeviceActivation(db).setRevoked('ABCD2345', true);

    await tester.ensureVisible(iconBtn('حذف من السجل'));
    await tester.tap(iconBtn('حذف من السجل'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('حذف من السجل').last);
    await pump(tester);

    expect(find.text('حاسوب المخزن'), findsNothing);
    expect(await DeviceActivation(db).registry(), isEmpty);
    expect(await DeviceActivation(db).isRevoked('ABCD2345'), isTrue);
  });

  testWidgets('ImdQr يُبنى بحجمه المطلوب', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: ImdQr('IMDACT2.test', size: 200))));
    expect(tester.getSize(find.byType(ImdQr)), const Size(200, 200));
  });
}
