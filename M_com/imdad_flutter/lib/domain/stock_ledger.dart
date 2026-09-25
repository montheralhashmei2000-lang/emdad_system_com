/// رصيد كل مستودع على حدة — نقل مطابق لـ stock-ledger.js.
/// رصيد الصنف في مستودع = الرصيد الافتتاحي لذلك المستودع
///   + الوارد + المرتجع الصالح من الوحدات + التحويلات المستلمة إليه
///   − المنصرف − المرتجع إلى الموردين − التحويلات الصادرة منه.
/// المسودات والأوامر المعلقة والملغاة والمرفوضة لا تدخل في الحساب.
library;

import 'cylinders.dart';

enum MovementKind {
  opening,
  receipt,
  issue,
  transferOut,
  transferIn,
  returnFromUnit,
  returnToSupplier,
  adjustment,
}

class MovementRecord {
  const MovementRecord({
    required this.kind,
    required this.warehouse,
    required this.itemId,
    required this.baseQty,
    this.destWarehouse = '',
    this.status = 'COMPLETED',
    this.condition = 'صالحة',
    this.date = '',
    this.cylinderAction = '',
  });

  final MovementKind kind;
  final String warehouse;
  final String destWarehouse;
  final String itemId;
  final double baseQty;
  final String status;
  final String condition;
  final String date;

  /// عملية الأصناف القابلة للتعبئة (الأسطوانات) — فارغة لغيرها.
  final String cylinderAction;

  /// هل تُغيّر هذه الحركة **عدد** الأسطوانات في المستودع؟
  ///
  /// الأسطوانة أصل ثابت: تدخل جديدة مرة واحدة، وما بعدها تعبئة أو استبدال —
  /// الأسطوانة نفسها تخرج فارغة وتعود ممتلئة فلا يتغيّر عددها. كان النظام
  /// يضيف كل توريد إلى الرصيد فينتفخ عدد الأسطوانات مع كل تعبئة.
  ///
  /// والإرسال للتعبئة كذلك: الأسطوانة تبقى ملك المستودع وهي عند المورد (انظر `CylAction.countNeutral` و`CylinderPosition`).
  bool get changesCount => !CylAction.countNeutral.contains(cylinderAction);

  static const Set<String> inactiveStatuses = {'DRAFT', 'ORDER', 'CANCELLED', 'REJECTED'};

  bool get isActive => !inactiveStatuses.contains(status);
}

class StockLedger {
  StockLedger(this.movements);

  final List<MovementRecord> movements;

  /// خريطة: اسم المستودع ← (معرّف الصنف ← الرصيد)
  Map<String, Map<String, double>> build() {
    final map = <String, Map<String, double>>{};

    void add(String wh, String item, double qty) {
      if (wh.isEmpty || item.isEmpty || qty == 0) return;
      final byItem = map.putIfAbsent(wh, () => <String, double>{});
      byItem[item] = _round((byItem[item] ?? 0) + qty);
    }

    for (final m in movements) {
      switch (m.kind) {
        case MovementKind.opening:
          add(m.warehouse, m.itemId, m.baseQty);
          break;
        case MovementKind.receipt:
          if (m.isActive && m.changesCount) add(m.warehouse, m.itemId, m.baseQty);
          break;
        case MovementKind.issue:
          if (m.isActive && m.changesCount) add(m.warehouse, m.itemId, -m.baseQty);
          break;
        case MovementKind.returnFromUnit:
          if (m.isActive && m.condition != 'تالفة') add(m.warehouse, m.itemId, m.baseQty);
          break;
        case MovementKind.returnToSupplier:
          if (m.isActive) add(m.warehouse, m.itemId, -m.baseQty);
          break;
        // تسوية جرد معتمدة: الفرق موجب (زيادة) أو سالب (عجز).
        case MovementKind.adjustment:
          if (m.isActive) add(m.warehouse, m.itemId, m.baseQty);
          break;
        case MovementKind.transferOut:
        case MovementKind.transferIn:
          if (m.status == 'REJECTED' || m.status == 'CANCELLED') break;
          add(m.warehouse, m.itemId, -m.baseQty);
          if (m.status == 'RECEIVED') add(m.destWarehouse, m.itemId, m.baseQty);
          break;
      }
    }
    return map;
  }

  /// أرصدة مستودع واحد، أو الإجمالي عند تمرير null (مع إمكانية حصره بنطاق المستخدم).
  Map<String, double> balances({String? warehouse, List<String>? scope}) {
    final all = build();
    if (warehouse != null && warehouse.isNotEmpty) {
      return Map<String, double>.from(all[warehouse] ?? const <String, double>{});
    }
    final out = <String, double>{};
    all.forEach((wh, items) {
      if (scope != null && !scope.contains(wh)) return;
      items.forEach((item, qty) {
        out[item] = _round((out[item] ?? 0) + qty);
      });
    });
    return out;
  }

  double balanceOf(String itemId, {String? warehouse, List<String>? scope}) =>
      balances(warehouse: warehouse, scope: scope)[itemId] ?? 0;

  /// فحص كفاية الرصيد قبل الصرف أو التحويل أو الإرجاع للمورد.
  StockCheck check({
    required String warehouse,
    required Map<String, double> requiredBaseQty,
  }) {
    final bal = balances(warehouse: warehouse);
    for (final entry in requiredBaseQty.entries) {
      final have = bal[entry.key] ?? 0;
      if (entry.value > have + 1e-9) {
        return StockCheck(ok: false, itemId: entry.key, available: have, requested: entry.value);
      }
    }
    return const StockCheck(ok: true);
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}

class StockCheck {
  const StockCheck({required this.ok, this.itemId = '', this.available = 0, this.requested = 0});

  final bool ok;
  final String itemId;
  final double available;
  final double requested;
}
