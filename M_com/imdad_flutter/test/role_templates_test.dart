import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/repos/users_repo.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/domain/perm_catalog.dart';

PermissionMap _of(String id) => AccessControl.roles[id]!.permissions;

bool _has(PermissionMap p, String page, String action) => p[page]?[action] == true;

/// الصفحات التي يمنح القالب عليها أي إجراء فعلًا.
Set<String> _pages(PermissionMap p) =>
    {for (final e in p.entries) if (e.value.values.any((v) => v)) e.key};

void main() {
  group('أمين المحروقات (fuel_keeper)', () {
    final p = _of('fuel_keeper');

    test('كل صفحاته في قسم المحروقات — ولا شيء من الإمداد أو الإدارة', () {
      for (final page in _pages(p)) {
        expect(PermCatalog.byKey[page]?.section, PermSection.fuel, reason: page);
      }
    });

    test('يغطي كل صفحات المحروقات بالعرض على الأقل', () {
      for (final e in PermCatalog.entries.where((e) => e.section == PermSection.fuel)) {
        expect(_has(p, e.key, PermAction.view), isTrue, reason: e.key);
      }
    });

    test('يضع التفريدة ويصرف ويطبع ويعتمد الجرد، ويعدّل إعدادات القسم', () {
      expect(_has(p, 'fuelMoves', PermAction.create), isTrue);
      expect(_has(p, 'fuelMoves', PermAction.print), isTrue);
      expect(_has(p, 'fuelAllocations', PermAction.edit), isTrue);
      expect(_has(p, 'fuelStocktake', PermAction.approve), isTrue);
      expect(_has(p, 'fuelSettings', PermAction.edit), isTrue);
      expect(_has(p, 'fuelReports', PermAction.print), isTrue);
    });

    test('لا يملك صفحة إمدادٍ ولا إدارة', () {
      for (final page in ['items', 'receive', 'issue', 'reports', 'linkages', 'settings', 'usersAccess']) {
        expect(p.containsKey(page), isFalse, reason: page);
      }
    });
  });

  group('المالية (finance)', () {
    final p = _of('finance');

    test('الارتباطات والقوة البشرية وحدهما', () {
      expect(_pages(p), {'linkages', 'personnel'});
    });

    test('كامل دورة المالية: إضافة وتعديل واعتماد وطباعة وتصدير واستيراد', () {
      for (final a in [
        PermAction.view, PermAction.create, PermAction.edit, PermAction.delete,
        PermAction.approve, PermAction.print, PermAction.export, PermAction.import,
      ]) {
        expect(_has(p, 'linkages', a), isTrue, reason: 'linkages.$a');
      }
      for (final a in [PermAction.view, PermAction.create, PermAction.edit, PermAction.print, PermAction.export]) {
        expect(_has(p, 'personnel', a), isTrue, reason: 'personnel.$a');
      }
    });

    test('كل إجراءاته معروفة في الكتالوج (يراها المالك ويسحبها من الشاشة)', () {
      p.forEach((page, actions) {
        for (final a in actions.keys) {
          expect(PermCatalog.byKey[page]!.actions, contains(a), reason: '$page.$a');
        }
      });
    });
  });

  group('مدخل البيانات (data_entry) — إضافة فقط', () {
    final p = _of('data_entry');

    test('لا حذف ولا اعتماد ولا اعتماد على أي صفحة', () {
      p.forEach((page, actions) {
        for (final a in [PermAction.delete, PermAction.approve, PermAction.import]) {
          expect(actions[a] == true, isFalse, reason: '$page.$a');
        }
      });
    });

    test('بلا «تعديل» على التفريدة وسجل التشغيل وخطط الوجبات، وله «إضافة»', () {
      for (final page in ['feeding', 'kitchenLog', 'mealPlans']) {
        expect(_has(p, page, PermAction.create), isTrue, reason: '$page.create');
        expect(_has(p, page, PermAction.edit), isFalse, reason: '$page.edit');
      }
    });

    test('لا «تعديل» على أي صفحة — والجرد يُعدّ بـ«إضافة»', () {
      final withEdit = {for (final e in p.entries) if (e.value['edit'] == true) e.key};
      expect(withEdit, isEmpty);
      expect(_has(p, 'stocktake', PermAction.create), isTrue);
    });

    test('ما زال يضيف السندات', () {
      for (final page in AccessControl.opsPages) {
        expect(_has(p, page, PermAction.create), isTrue, reason: page);
      }
    });
  });

  group('أمين المخزن (storekeeper) — موسَّع لا مقلَّص', () {
    final p = _of('storekeeper');

    test('احتفظ بكل ما كان له', () {
      for (final page in AccessControl.opsPages) {
        for (final a in [
          PermAction.view, PermAction.create, PermAction.edit, PermAction.approve, PermAction.print,
        ]) {
          expect(_has(p, page, a), isTrue, reason: '$page.$a');
        }
      }
      expect(_has(p, 'opening', PermAction.create), isTrue);
      expect(_has(p, 'stocktake', PermAction.print), isTrue);
      expect(_has(p, 'documents', PermAction.edit), isTrue);
      expect(_has(p, 'balances', PermAction.export), isTrue);
      expect(_has(p, 'reports', PermAction.print), isTrue);
      expect(_has(p, 'rationOrders', PermAction.approve), isTrue);
      expect(_has(p, 'fuelStocktake', PermAction.approve), isTrue);
      for (final page in AccessControl.basicPages) {
        expect(_has(p, page, PermAction.view), isTrue, reason: page);
      }
    });

    test('الجديد: إدارة الكتالوج + تصدير التقارير', () {
      expect(_has(p, 'items', PermAction.create), isTrue);
      expect(_has(p, 'items', PermAction.edit), isTrue);
      expect(_has(p, 'items', PermAction.import), isTrue);
      expect(_has(p, 'items', PermAction.export), isTrue);
      expect(_has(p, 'suppliers', PermAction.create), isTrue);
      expect(_has(p, 'units', PermAction.print), isTrue);
      expect(_has(p, 'assets', PermAction.edit), isTrue);
      expect(_has(p, 'reports', PermAction.export), isTrue);
    });

    test('الكتالوج بلا حذف، والمستودعات نفسها للعرض فقط', () {
      for (final page in ['items', 'suppliers', 'units', 'kitchens', 'assets']) {
        expect(_has(p, page, PermAction.delete), isFalse, reason: page);
      }
      expect(_has(p, 'stores', PermAction.create), isFalse);
      expect(_has(p, 'stores', PermAction.view), isTrue);
    });
  });

  group('القوالب عمومًا', () {
    test('كل قالبٍ جديد/معدَّل يمنح مفاتيح معروفة في الكتالوج', () {
      for (final id in ['fuel_keeper', 'finance', 'data_entry', 'storekeeper']) {
        for (final page in _of(id).keys) {
          expect(PermCatalog.byKey.containsKey(page), isTrue, reason: '$id: $page');
        }
      }
    });

    test('تطبيق القالب لقطةٌ عند الإنشاء: لا يتغيّر مستخدمٌ قائم بتغيّر القالب', () {
      // permissionsForRoles تُحسب وتُخزَّن في سجل المستخدم وقت الإنشاء ولا تُعاد
      // قراءتها من القوالب لاحقًا؛ فتعديل القوالب لا يسحب شيئًا من أحد.
      final a = UsersRepo.permissionsForRoles(['data_entry']);
      final b = UsersRepo.permissionsForRoles(['data_entry']);
      expect(a, b);
      expect(identical(a, _of('data_entry')), isFalse);
    });

    test('جمع قالبين اتحاد صلاحياتهما', () {
      final merged = UsersRepo.permissionsForRoles(['fuel_keeper', 'finance']);
      expect(_has(merged, 'fuelMoves', PermAction.create), isTrue);
      expect(_has(merged, 'linkages', PermAction.import), isTrue);
    });
  });
}
