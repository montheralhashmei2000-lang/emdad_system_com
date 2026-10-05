import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/domain/app_space.dart';
import 'package:imdad/domain/menu_doors.dart';
import 'package:imdad/domain/perm_catalog.dart';

void main() {
  const knownActions = {
    PermAction.view,
    PermAction.create,
    PermAction.edit,
    PermAction.delete,
    PermAction.approve,
    PermAction.print,
    PermAction.export,
    PermAction.import,
  };

  group('كتالوج الصلاحيات', () {
    test('المفاتيح فريدة ولكل مدخلٍ اسمٌ وإجراءاتٌ معروفة تبدأ بالعرض', () {
      final seen = <String>{};
      for (final e in PermCatalog.entries) {
        expect(seen.add(e.key), isTrue, reason: 'مفتاح مكرر: ${e.key}');
        expect(e.label.trim(), isNotEmpty, reason: e.key);
        expect(PermSection.all, contains(e.section), reason: e.key);
        expect(e.actions, contains(PermAction.view), reason: e.key);
        expect(e.actions.toSet().length, e.actions.length, reason: 'إجراء مكرر في ${e.key}');
        for (final a in e.actions) {
          expect(knownActions, contains(a), reason: '${e.key}: $a');
        }
      }
    });

    test('صفحات كل مساحة عمل لها مدخلات في الكتالوج (أو أبواب)', () {
      for (final entry in AppSpace.pages.entries) {
        for (final p in entry.value) {
          expect(PermCatalog.byKey.containsKey(p) || kMenuDoors.containsKey(p), isTrue,
              reason: '${entry.key}: $p بلا مدخلٍ في الكتالوج');
        }
      }
    });

    test('كل إجراءٍ تمنحه قوالب الأدوار موجودٌ في مدخله بالكتالوج', () {
      // وإلا مُنحت صلاحيةٌ لا يستطيع المالك رؤيتها ولا سحبها من الشاشة.
      // الاستثناء: منحٌ شاملٌ قديم في القوالب لإجراءٍ لا وجود له على تلك
      // الشاشة (لا تصدير Excel ولا طباعة فيها) — خاملٌ لا أثر له، ولا يُسحب
      // من أحد. أي منحٍ جديدٌ خارج الكتالوج يفشل هنا.
      const inertGrants = {
        'campDashboard.create', 'campDashboard.edit', 'campDashboard.export', 'campDashboard.print',
        'fuelAllocations.export', 'fuelConsumption.export', 'fuelDashboard.export', 'fuelDashboard.print',
        'fuelMoves.export', 'fuelReports.export', 'fuelSettings.export', 'fuelSettings.print',
        'fuelStocktake.export', 'fuelUnits.export', 'fuelUnits.print', 'fuelVehicles.export',
        'fuelVehicles.print', 'fuelWarehouses.export', 'fuelWarehouses.print', 'rationOrders.export',
      };
      final offenders = <String>{};
      for (final role in AccessControl.roles.values) {
        role.permissions.forEach((page, actions) {
          final entry = PermCatalog.byKey[page];
          expect(entry, isNotNull, reason: '${role.id} يمنح «$page» وهو خارج الكتالوج');
          actions.forEach((a, on) {
            if (on && !entry!.actions.contains(a) && !inertGrants.contains('$page.$a')) {
              offenders.add('${role.id}: $page.$a');
            }
          });
        });
      }
      expect(offenders, isEmpty);
    });

    test('كل مفتاحٍ يُفحص في الكود موجودٌ في الكتالوج (لا صلاحية تُستعمل ولا تُمنح)', () {
      // نمطٌ على نصوص lib: has/guard/writable/manage/can('key' …) و perm: 'key'.
      final call = RegExp(r"""(?:\bhas|\bguard|\bwritable|\bmanage|\bcan)\((?:context, )?'(\w+)'""");
      final perm = RegExp(r"""\bperm:\s*'(\w+)'""");
      final allowed = {
        ...PermCatalog.byKey.keys,
        ...kMenuDoors.keys,
        ...PermCatalog.aliasLabels.keys,
      };
      final missing = <String>{};
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in [...call.allMatches(src), ...perm.allMatches(src)]) {
          final key = m.group(1)!;
          if (!allowed.contains(key)) missing.add('$key  (${f.path})');
        }
      }
      expect(missing, isEmpty, reason: 'مفاتيح مفحوصة بلا مدخلٍ في الكتالوج:\n${missing.join('\n')}');
    });
  });

  group('«import» إجراءٌ مستقل', () {
    test('بلا مفتاح import صريح يرث «إضافة» (لا يفقد أحدٌ ما كان له)', () {
      expect(AccessControl.allows({'create': true}, PermAction.import), isTrue);
      expect(AccessControl.allows({'view': true}, PermAction.import), isFalse);
    });

    test('المفتاح الصريح هو الحكم: false يمنع ولو ملك «إضافة»', () {
      expect(AccessControl.allows({'create': true, 'import': false}, PermAction.import), isFalse);
      expect(AccessControl.allows({'import': true}, PermAction.import), isTrue);
    });

    test('الوراثة خاصةٌ بالاستيراد: بقية الإجراءات كما هي', () {
      expect(AccessControl.allows({'create': true}, PermAction.export), isFalse);
      expect(AccessControl.allows({'edit': true}, PermAction.edit), isTrue);
      expect(AccessControl.allows(null, PermAction.view), isFalse);
    });

    test('المدير يتجاوز عبر can()', () {
      expect(AccessControl.can(isAdmin: true, permissions: const {}, page: 'items', action: PermAction.import), isTrue);
      expect(
          AccessControl.can(
              isAdmin: false,
              permissions: const {'items': {'create': true}},
              page: 'items',
              action: PermAction.import),
          isTrue);
    });
  });
}
