// أداة لقطات بصرية للمقارنة مع لقطات نسخة الويب — ليست ضمن اختبارات `flutter test` العادية.
// التشغيل:  flutter test test_visual/shots_test.dart --dart-define=PAGES=dash,items
// الناتج:   build/shots/<page>.png  (عرض 1280 بكثافة 1 كما في لقطات الويب)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/auth_service.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/movements_repo.dart';
import 'package:imdad/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadAppFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('IBMPlexSansArabic', [
    'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    'assets/fonts/IBMPlexSansArabic-Medium.ttf',
    'assets/fonts/IBMPlexSansArabic-SemiBold.ttf',
    'assets/fonts/IBMPlexSansArabic-Bold.ttf',
  ]);
}

/// يلتقط الشجرة الحالية إلى ملف PNG.
Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot-root')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/shots/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// ينتظر العمليات غير المتزامنة الحقيقية (قاعدة البيانات، تحميل SVG) ثم يرسم.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

class ShotHarness {
  late AppDatabase db;
  late AuthService auth;

  Future<void> setUp() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db);
  }

  /// بيانات تجريبية صغيرة (--dart-define=SEED=true) لرؤية الجداول والشجرة بصفوف فعلية.
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final repo = CatalogRepo(db);
      final c1 = await repo.saveUnit(code: '1', name: 'معسكر الصمود', type: 'camp', category: 'مشاة');
      await repo.saveUnit(code: '1-1', name: 'الكتيبة الأولى', parentId: c1, parentName: 'معسكر الصمود', category: 'مشاة');
      await repo.saveUnit(code: '1-2', name: 'سرية الإسناد', parentId: c1, parentName: 'معسكر الصمود');
      await repo.saveUnit(code: '2', name: 'معسكر النصر', type: 'camp');
      await repo.saveWarehouse(code: 'W1', name: 'المستودع الرئيسي', manager: 'أحمد', location: 'عدن');
      await repo.saveWarehouse(code: 'W2', name: 'مستودع الفرع', feedsAllCamps: false, campIds: [c1]);
      await repo.saveSupplier(name: 'مؤسسة الخير', contact: 'علي', phone: '777123456', city: 'عدن');
      await repo.saveItem(code: '1', name: 'أرز', units: const [ItemUnit(name: 'كيس', factor: 1, isBase: true)], minQty: 10, barcode: '104123456789');
      await repo.saveItem(code: '2', name: 'زيت طبخ', units: const [ItemUnit(name: 'لتر', factor: 1, isBase: true), ItemUnit(name: 'كرتون', factor: 12)]);
      await repo.saveFacility(name: 'مطبخ المعسكر', capacity: 400, warehouse: 'المستودع الرئيسي');

      // سندات محفوظة — تحتاجها شاشات سجل المستندات والأرصدة والتقارير.
      final items = await repo.items();
      final rice = items.firstWhere((i) => i.name == 'أرز');
      final oil = items.firstWhere((i) => i.name == 'زيت طبخ');
      DocLineInput line(Item it, String unit, double factor, double qty) => DocLineInput(
            itemId: it.id,
            itemCode: it.code,
            itemName: it.name,
            unitName: unit,
            factor: factor,
            qty: qty,
          );
      final mv = MovementsRepo(db);
      await mv.saveReceipt(
        warehouse: 'المستودع الرئيسي',
        supplier: 'مؤسسة الخير',
        date: '2026-09-10',
        invoiceNo: '3391',
        createdBy: 'admin',
        lines: [line(rice, 'كيس', 1, 120), line(oil, 'كرتون', 12, 20)],
      );
      await mv.saveIssue(
        warehouse: 'المستودع الرئيسي',
        recipientDisplay: 'الكتيبة الأولى',
        date: '2026-09-12',
        soldierCount: 180,
        createdBy: 'admin',
        lines: [line(rice, 'كيس', 1, 30)],
      );
      await mv.saveTransfer(
        fromWarehouse: 'المستودع الرئيسي',
        toWarehouse: 'مستودع الفرع',
        date: '2026-09-13',
        createdBy: 'admin',
        lines: [line(oil, 'لتر', 1, 40)],
      );
      await mv.saveReturn(
        warehouse: 'المستودع الرئيسي',
        party: 'سرية الإسناد',
        date: '2026-09-14',
        createdBy: 'admin',
        lines: [line(rice, 'كيس', 1, 5)],
      );
    });
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.runAsync(() => auth.createAdmin(username: 'admin', password: 'Test@12345', name: 'admin'));
  }

  Widget app({required bool signedIn, bool dark = false}) => RepaintBoundary(
        key: const ValueKey('shot-root'),
        child: ImdadApp(
          db: db,
          auth: auth,
          signedIn: signedIn,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        ),
      );
}

void setViewport(WidgetTester tester, {double width = 1280, double height = 900}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
}
