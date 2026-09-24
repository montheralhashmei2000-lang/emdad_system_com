import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/access_control.dart';

void main() {
  group('تجميع صلاحيات الأدوار', () {
    test('مستخدم بدورَي مدخل بيانات وأمين مخزن يجمع صلاحيات الاثنين', () {
      final perms = AccessControl.merge([
        AccessControl.roles['data_entry']!.permissions,
        AccessControl.roles['storekeeper']!.permissions,
      ]);
      expect(perms['receive']?['create'], isTrue); // من مدخل البيانات
      expect(perms['receive']?['approve'], isTrue); // من أمين المخزن
      expect(perms['balances']?['view'], isTrue);
    });

    test('المطّلع لا يملك أي صلاحية إدخال أو تعديل', () {
      final viewer = AccessControl.roles['viewer']!.permissions;
      for (final page in viewer.keys) {
        expect(viewer[page]?['create'] ?? false, isFalse, reason: page);
        expect(viewer[page]?['edit'] ?? false, isFalse, reason: page);
        expect(viewer[page]?['delete'] ?? false, isFalse, reason: page);
      }
    });

    test('إدارة المستخدمين ليست ضمن أي دور جاهز — لمدير النظام وحده', () {
      for (final role in AccessControl.roles.values) {
        expect(role.permissions['usersAccess']?['edit'] ?? false, isFalse,
            reason: role.id);
      }
      expect(
        AccessControl.can(
          isAdmin: false,
          permissions: AccessControl.roles['office_manager']!.permissions,
          page: 'usersAccess',
          action: PermAction.edit,
        ),
        isFalse,
      );
      expect(
        AccessControl.can(
          isAdmin: true,
          permissions: const {},
          page: 'usersAccess',
          action: PermAction.edit,
        ),
        isTrue,
      );
    });

    test('نطاق المستودعات يمنع أمين مخزن من مستودع آخر', () {
      expect(
        AccessControl.canUseWarehouse(
          isAdmin: false,
          scope: const ['مخزن المعسكر'],
          warehouse: 'المخزن الرئيسي',
        ),
        isFalse,
      );
      expect(
        AccessControl.canUseWarehouse(
          isAdmin: false,
          scope: const ['مخزن المعسكر'],
          warehouse: 'مخزن المعسكر',
        ),
        isTrue,
      );
    });
  });
}
