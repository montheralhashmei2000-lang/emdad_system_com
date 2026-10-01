import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';
import 'package:imdad/core/ui/imd_context_menu.dart';
import 'package:imdad/core/ui/imd_drop_zone.dart';
import 'package:imdad/core/ui/imd_tokens.dart';
import 'package:imdad/core/ui/imd_widgets.dart';

/// الإحساس الأصلي على سطح المكتب: سهمٌ لا يدُ إصبع، بلا تموّج Material،
/// وقائمة سياقٍ للصفوف، وإفلات الملفات.
void main() {
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('مؤشر الفأرة', () {
    test('ImdCursor.click سهمٌ لا يد إصبع', () {
      expect(ImdCursor.click, SystemMouseCursors.basic);
    });

    test('الرابط النصّي الحقيقي وحده يحتفظ باليد', () {
      expect(ImdCursor.link, SystemMouseCursors.click);
    });
  });

  group('التموّج وشريط التمرير', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('لا تموّج Material على ويندوز', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      for (final t in [AppTheme.light(), AppTheme.dark(), AppTheme.fuel()]) {
        expect(t.splashFactory, same(NoSplash.splashFactory));
      }
    });

    test('التموّج يبقى على أندرويد (اللمس)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AppTheme.light().splashFactory, isNot(same(NoSplash.splashFactory)));
    });
  });

  group('قائمة سياق الصفوف', () {
    testWidgets('كليك يمين على صفٍّ يفتح بنوده، واختيار بندٍ ينفّذه بفهرس الصفّ', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(host(SizedBox(
        width: 700,
        child: ImdTable(
          columns: const [ImdCol('الاسم')],
          rows: const [
            [Text('أول')],
            [Text('ثان')],
          ],
          cards: false,
          rowMenu: (i) => [
            ImdMenuItem(label: 'تعديل', icon: 'edit', onTap: () => calls.add('edit$i')),
            ImdMenuItem(label: 'حذف', icon: 'trash', danger: true, onTap: () => calls.add('del$i')),
          ],
        ),
      )));

      await tester.tap(find.text('ثان'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('حذف'), findsOneWidget);

      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(calls, ['del1']);
      expect(find.text('تعديل'), findsNothing, reason: 'القائمة تُغلق بعد الاختيار');
    });

    testWidgets('ضغطةٌ مطوّلة تفتحها على اللمس', (tester) async {
      var edits = 0;
      await tester.pumpWidget(host(SizedBox(
        width: 700,
        child: ImdTable(
          columns: const [ImdCol('الاسم')],
          rows: const [
            [Text('أول')],
          ],
          cards: false,
          rowMenu: (i) => [ImdMenuItem(label: 'تعديل', onTap: () => edits++)],
        ),
      )));

      await tester.longPress(find.text('أول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تعديل'));
      await tester.pumpAndSettle();
      expect(edits, 1);
    });

    testWidgets('بلا rowMenu لا تظهر قائمة', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 700,
        child: ImdTable(
          columns: [ImdCol('الاسم')],
          rows: [
            [Text('أول')],
          ],
          cards: false,
        ),
      )));
      await tester.tap(find.text('أول'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<int>), findsNothing);
    });

    testWidgets('قائمةٌ فارغة لا تُفتح', (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 700,
        child: ImdTable(
          columns: const [ImdCol('الاسم')],
          rows: const [
            [Text('أول')],
          ],
          cards: false,
          rowMenu: (_) => const [],
        ),
      )));
      await tester.tap(find.text('أول'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<int>), findsNothing);
    });
  });

  group('إفلات الملفات', () {
    test('الامتداد بأحرف صغيرة وبلا نقطة، ويقرأ مسارات ويندوز ولينكس', () {
      expect(ImdDropZone.extensionOf(r'C:\بيانات\نسخة.IMDBK'), 'imdbk');
      expect(ImdDropZone.extensionOf('/home/u/a.b.xlsx'), 'xlsx');
      expect(ImdDropZone.extensionOf('README'), '');
      expect(ImdDropZone.extensionOf(r'C:\dir.v2\README'), '');
    });

    test('يُختار أول ملفٍ بامتدادٍ مقبول ويُهمَل غيره', () {
      const exts = ['xlsx', 'json'];
      expect(ImdDropZone.firstMatching(['a.png', 'b.JSON', 'c.xlsx'], exts), 'b.JSON');
      expect(ImdDropZone.firstMatching(['a.png', 'b.txt'], exts), isNull);
      expect(ImdDropZone.firstMatching(const [], exts), isNull);
    });

    testWidgets('خارج ويندوز تُرجع الابن كما هو بلا غلاف', (tester) async {
      await tester.pumpWidget(host(const ImdDropZone(
        extensions: ['xlsx'],
        onFile: _ignore,
        child: Text('محتوى'),
      )));
      expect(find.text('محتوى'), findsOneWidget);
      expect(find.byType(DropTarget), findsNothing);
    });
  });
}

void _ignore(String _) {}
