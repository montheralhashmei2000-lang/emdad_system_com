import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/access_control.dart';
import 'package:imdad/domain/stock_ledger.dart';

void main() {
  group('الأدوار ونطاق المستودعات', () {
    test('قالب أمين المخزن: اعتماد نعم، حذف لا', () {
      final perms = AccessControl.permissionsForRoles(['storekeeper']);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'receive', action: PermAction.approve), isTrue);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'receive', action: PermAction.delete), isFalse);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'usersAccess'), isFalse);
    });

    test('قالب المطّلع: مشاهدة فقط في المستندات', () {
      final perms = AccessControl.permissionsForRoles(['viewer']);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'documents'), isTrue);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'documents', action: PermAction.print), isFalse);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'documents', action: PermAction.edit), isFalse);
    });

    test('جمع دورين يوحّد صلاحياتهما', () {
      final perms = AccessControl.permissionsForRoles(['data_entry', 'supply_officer']);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'issue', action: PermAction.create), isTrue);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'issue', action: PermAction.approve), isTrue);
      expect(AccessControl.can(isAdmin: false, permissions: perms, page: 'ratios', action: PermAction.edit), isTrue);
    });

    test('مدير النظام يملك كل شيء بلا نطاق', () {
      const empty = <String, Map<String, bool>>{};
      expect(AccessControl.can(isAdmin: true, permissions: empty, page: 'usersAccess', action: PermAction.edit), isTrue);
      expect(AccessControl.canUseWarehouse(isAdmin: true, scope: const ['أ'], warehouse: 'ب'), isTrue);
    });

    test('نطاق المستودعات يحصر الإدخال والقوائم', () {
      const scope = ['مخزن المعسكر'];
      expect(AccessControl.canUseWarehouse(isAdmin: false, scope: scope, warehouse: 'مخزن المعسكر'), isTrue);
      expect(AccessControl.canUseWarehouse(isAdmin: false, scope: scope, warehouse: 'المخزن الرئيسي'), isFalse);
      expect(
        AccessControl.filterWarehouses(isAdmin: false, scope: scope, all: const ['المخزن الرئيسي', 'مخزن المعسكر']),
        ['مخزن المعسكر'],
      );
      // null ⇒ كل المستودعات
      expect(AccessControl.canUseWarehouse(isAdmin: false, scope: null, warehouse: 'أي مخزن'), isTrue);
    });

    test('canManage يكشف صلاحيات الإدارة', () {
      final entry = AccessControl.permissionsForRoles(['data_entry']);
      final viewer = AccessControl.permissionsForRoles(['viewer']);
      expect(AccessControl.canManage(isAdmin: false, permissions: entry, page: 'receive'), isTrue);
      expect(AccessControl.canManage(isAdmin: false, permissions: viewer, page: 'receive'), isFalse);
    });
  });

  group('رصيد كل مستودع على حدة', () {
    const w1 = 'المخزن الرئيسي';
    const w2 = 'مخزن المعسكر';
    const rice = 'rice';

    final ledger = StockLedger(const [
      MovementRecord(kind: MovementKind.opening, warehouse: w1, itemId: rice, baseQty: 200),
      MovementRecord(kind: MovementKind.receipt, warehouse: w1, itemId: rice, baseQty: 100),
      MovementRecord(kind: MovementKind.receipt, warehouse: w2, itemId: rice, baseQty: 60),
      MovementRecord(kind: MovementKind.receipt, warehouse: w2, itemId: rice, baseQty: 999, status: 'DRAFT'),
      MovementRecord(kind: MovementKind.issue, warehouse: w1, itemId: rice, baseQty: 50),
      MovementRecord(kind: MovementKind.transferOut, warehouse: w1, destWarehouse: w2, itemId: rice, baseQty: 30, status: 'RECEIVED'),
      MovementRecord(kind: MovementKind.transferOut, warehouse: w1, destWarehouse: w2, itemId: rice, baseQty: 20, status: 'PENDING'),
      MovementRecord(kind: MovementKind.returnFromUnit, warehouse: w2, itemId: rice, baseQty: 10),
      MovementRecord(kind: MovementKind.returnFromUnit, warehouse: w2, itemId: rice, baseQty: 7, condition: 'تالفة'),
    ]);

    test('الرصيد منفصل لكل مستودع، والإجمالي مجموعهما', () {
      // W1 = 200 + 100 − 50 − 30 − 20 = 200 · W2 = 60 + 30 + 10 = 100
      expect(ledger.balanceOf(rice, warehouse: w1), 200);
      expect(ledger.balanceOf(rice, warehouse: w2), 100);
      expect(ledger.balanceOf(rice), 300);
    });

    test('المسودات والتالف والتحويل المعلّق لا تُضاف للمستودع المستلم', () {
      final all = ledger.build();
      expect(all[w2]![rice], 100); // لا 999 ولا 7 ولا 20
    });

    test('الإجمالي يحترم نطاق المستخدم', () {
      expect(ledger.balances(scope: const [w2])[rice], 100);
    });

    test('فحص الكفاية يمنع الصرف فوق رصيد المستودع', () {
      final bad = ledger.check(warehouse: w2, requiredBaseQty: const {rice: 150});
      expect(bad.ok, isFalse);
      expect(bad.available, 100);
      final good = ledger.check(warehouse: w2, requiredBaseQty: const {rice: 80});
      expect(good.ok, isTrue);
    });

    test('المرتجع إلى المورد يخصم من المستودع', () {
      final l = StockLedger(const [
        MovementRecord(kind: MovementKind.receipt, warehouse: w1, itemId: rice, baseQty: 100),
        MovementRecord(kind: MovementKind.returnToSupplier, warehouse: w1, itemId: rice, baseQty: 15),
      ]);
      expect(l.balanceOf(rice, warehouse: w1), 85);
    });
  });
  
  group('تسوية الجرد في دفتر الأرصدة', () {
    test('الفرق الموجب يزيد رصيد المستودع والسالب ينقصه', () {
      final ledger = StockLedger([
        const MovementRecord(
          kind: MovementKind.opening,
          warehouse: 'الرئيسي',
          itemId: 'rice',
          baseQty: 100,
        ),
        const MovementRecord(
          kind: MovementKind.adjustment,
          warehouse: 'الرئيسي',
          itemId: 'rice',
          baseQty: -15,
        ),
        const MovementRecord(
          kind: MovementKind.adjustment,
          warehouse: 'الرئيسي',
          itemId: 'sugar',
          baseQty: 8,
        ),
      ]);
      final balances = ledger.balances(warehouse: 'الرئيسي');
      expect(balances['rice'], 85);
      expect(balances['sugar'], 8);
    });

    test('تسوية ملغاة لا تمس الرصيد', () {
      final ledger = StockLedger([
        const MovementRecord(
          kind: MovementKind.opening,
          warehouse: 'الرئيسي',
          itemId: 'rice',
          baseQty: 50,
        ),
        const MovementRecord(
          kind: MovementKind.adjustment,
          warehouse: 'الرئيسي',
          itemId: 'rice',
          baseQty: -20,
          status: 'CANCELLED',
        ),
      ]);
      expect(ledger.balances(warehouse: 'الرئيسي')['rice'], 50);
    });
  });
}
