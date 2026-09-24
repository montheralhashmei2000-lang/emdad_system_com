import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/assets.dart';
import '../../domain/camp_ledger.dart';
import '../../domain/meal_plan.dart';
import '../../domain/notification_item.dart';
import '../../domain/ration_order.dart';
import '../../domain/stock_alert.dart';
import '../db/app_database.dart';
import 'assets_repo.dart';
import 'camp_ledger_repo.dart';
import 'meal_plan_repo.dart';
import 'ration_repo.dart';

/// يفحص حالة النظام ويبني تنبيهاته.
///
/// **حالة القراءة وحدها تُحفظ**، في تفضيلات الجهاز لا في قاعدة البيانات: ما
/// قرأه مسؤول الفرع على هاتفه لا يعني أن المدير قرأه على حاسبه. ولو زُومنت
/// لاختفى التنبيه عن أحدهما لأن الآخر فتحه.
class NotificationsRepo {
  NotificationsRepo(this.db);

  final AppDatabase db;

  static const String _readKey = 'imdad.notify.read';

  /// يفحص كل مصادر التنبيه ويعيدها مرتّبة، محمّلةً بحالة القراءة.
  ///
  /// [allowed] الصفحات التي يراها المستخدم — من لا يرى شاشة لا يُنبَّه بما
  /// فيها، وإلا سرّب الجرسُ ما حجبته الصلاحيات.
  Future<List<AppNotification>> scan({Set<String>? allowed}) async {
    final found = <AppNotification>[];
    bool can(NotifyKind k) => allowed == null || allowed.contains(k.page);

    if (can(NotifyKind.campStockLow)) found.addAll(await _campStock());
    if (can(NotifyKind.stockNegative)) found.addAll(await _negativeStock());
    if (can(NotifyKind.assetExpiring)) found.addAll(await _assets());
    if (can(NotifyKind.rationPending)) found.addAll(await _ration());
    if (can(NotifyKind.mealPlanEnding)) found.addAll(await _mealPlans());
    if (can(NotifyKind.settlementDue)) found.addAll(await _settlement());

    final read = await _readIds();
    return NotifyRules.cap([
      for (final n in found) n.copyWith(read: read.contains(n.id)),
    ]);
  }

  // ───────────────────────── المصادر

  Future<List<AppNotification>> _campStock() async {
    final alerts = await CampLedgerRepo(db).alerts();
    return [
      for (final a in alerts)
        if (a.shouldAlert)
          AppNotification(
            id: 'camp.stock.${a.campId}.${a.itemId}',
            kind: NotifyKind.campStockLow,
            severity: switch (a.level) {
              AlertLevel.critical || AlertLevel.high => NotifySeverity.danger,
              AlertLevel.medium => NotifySeverity.warning,
              _ => NotifySeverity.info,
            },
            title: '${a.itemName} — ${a.campName}',
            body: a.daysLeft == null
                ? 'بلغ الحد الأدنى (${_n(a.current)} ${a.unitName})'
                : a.daysLeft == 0
                    ? 'بلغ الحد الأدنى — المقترح تحويل ${_n(a.suggestedTransfer)}'
                    : 'يكفي ${_n(a.daysLeft!)} يوم — المقترح تحويل '
                        '${_n(a.suggestedTransfer)} ${a.unitName}',
          ),
    ];
  }

  /// رصيد مخزون سالب: استهلاكٌ سُجّل بلا استلام. خطأ إدخال لا نقص بضاعة،
  /// ولذلك تنبيهه من نوع آخر ويفتح السجل لا اللوحة.
  Future<List<AppNotification>> _negativeStock() async {
    final now = DateTime.now();
    final rows = await CampLedgerRepo(db).ledgers(year: now.year, month: now.month);
    return [
      for (final r in rows)
        if (r.amounts.stockImpossible)
          AppNotification(
            id: 'camp.negative.${r.ledger.campId}.${r.ledger.itemId}',
            kind: NotifyKind.stockNegative,
            severity: NotifySeverity.warning,
            title: 'رصيد سالب: ${r.ledger.itemName} — ${r.ledger.campName}',
            body: 'المستهلك أكثر من المستلم بـ${_n(-r.amounts.stockBalance)} '
                '${r.ledger.unitName} — راجع سندات الاستلام أو سجل الطهي',
          ),
    ];
  }

  Future<List<AppNotification>> _assets() async {
    final assets = await AssetsRepo(db).assets();
    final out = <AppNotification>[];
    for (final a in assets) {
      if (AssetStatus.outOfService.contains(a.status)) continue;
      final life = AssetRules.lifeOf(
        acquisitionDate: a.acquisitionDate,
        lifespanMonths: a.lifespanMonths,
      );
      final left = AssetRules.daysLeft(
        acquisitionDate: a.acquisitionDate,
        lifespanMonths: a.lifespanMonths,
      );
      if (life == AssetLife.expired) {
        out.add(AppNotification(
          id: 'asset.expired.${a.id}',
          kind: NotifyKind.assetExpired,
          severity: NotifySeverity.warning,
          title: 'انقضى عمر: ${a.name}',
          body: 'مضى ${_n(-(left ?? 0))} يومًا على انقضاء عمره الافتراضي — '
              'يلزم استبداله أو تحديث حالته',
        ));
      } else if (life == AssetLife.nearingEnd) {
        out.add(AppNotification(
          id: 'asset.expiring.${a.id}',
          kind: NotifyKind.assetExpiring,
          severity: NotifySeverity.info,
          title: 'يقارب الانتهاء: ${a.name}',
          body: 'يتبقى ${_n(left ?? 0)} يوم على انقضاء عمره الافتراضي',
        ));
      }
    }
    return out;
  }

  Future<List<AppNotification>> _ration() async {
    final orders = await RationRepo(db).orders();
    final now = DateTime.now();
    final out = <AppNotification>[];
    for (final o in orders) {
      if (o.status != RationStatus.pending && o.status != RationStatus.approved) {
        continue;
      }
      final age = now.difference(o.createdAt).inDays;
      // ثلاثة أيام: أقل منها ضجيج على طلبية أُرسلت اليوم.
      if (age < 3) continue;
      out.add(AppNotification(
        id: 'ration.pending.${o.id}',
        kind: NotifyKind.rationPending,
        severity: age >= 7 ? NotifySeverity.warning : NotifySeverity.info,
        title: 'طلبية معلّقة: ${o.refNo}',
        body: 'مضى ${_n(age)} يومًا وهي ${RationStatus.label(o.status)} — '
            '${o.requestingWarehouse} من ${o.supplyingWarehouse}',
      ));
    }
    return out;
  }

  Future<List<AppNotification>> _mealPlans() async {
    final plans = await MealPlanRepo(db).plans(status: MealPlanStatus.active);
    final today = DateSpan.ymd(DateTime.now());
    final out = <AppNotification>[];
    for (final p in plans) {
      final end = DateTime.tryParse(p.endDate);
      if (end == null) continue;
      final left = end.difference(DateTime.parse(today)).inDays;
      if (left < 0) {
        out.add(AppNotification(
          id: 'mealplan.ended.${p.id}',
          kind: NotifyKind.mealPlanEnding,
          severity: NotifySeverity.warning,
          title: 'انتهت خطة: ${p.name}',
          body: 'انتهى مداها ولم تُؤرشف ولم تُستنسخ — لا خطة نشطة لما بعدها',
        ));
      } else if (left <= 3) {
        out.add(AppNotification(
          id: 'mealplan.ending.${p.id}',
          kind: NotifyKind.mealPlanEnding,
          severity: NotifySeverity.info,
          title: 'توشك خطة على الانتهاء: ${p.name}',
          body: 'تنتهي خلال ${_n(left)} يوم — استنسخها للمدة التالية',
        ));
      }
    }
    return out;
  }

  /// شهرٌ انتهى ولم يُصفَّ — والتأخير يراكم أرصدة لا تُرحَّل.
  Future<List<AppNotification>> _settlement() async {
    final repo = CampLedgerRepo(db);
    final now = DateTime.now();
    final year = now.month == 1 ? now.year - 1 : now.year;
    final month = now.month == 1 ? 12 : now.month - 1;

    final done = await repo.settlements();
    if (done.any((s) => s.year == year && s.month == month)) return const [];

    final open = await repo.ledgers(year: year, month: month, status: 'OPEN');
    if (open.isEmpty) return const [];

    final t = CampLedgerCalc.totals([for (final r in open) r.amounts]);
    return [
      AppNotification(
        id: 'settlement.$year.$month',
        kind: NotifyKind.settlementDue,
        severity: now.day >= 7 ? NotifySeverity.warning : NotifySeverity.info,
        title: 'تصفية شهر $month/$year لم تُنفَّذ',
        body: '${_n(open.length)} سطرًا مفتوحًا — متبقٍ لهم ${_n(t.credit)} '
            'وعليهم ${_n(t.debit)}. الأرصدة لا تُرحَّل قبل التصفية',
      ),
    ];
  }

  // ───────────────────────── حالة القراءة

  Future<Set<String>> _readIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_readKey) ?? const <String>[]).toSet();
  }

  Future<void> markRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_readKey) ?? <String>[]).toSet()..add(id);
    await prefs.setStringList(_readKey, ids.toList());
  }

  Future<void> markAllRead(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final all = (prefs.getStringList(_readKey) ?? <String>[]).toSet()..addAll(ids);
    await prefs.setStringList(_readKey, all.toList());
  }

  /// يمسح حالة القراءة، فتعود التنبيهات القائمة كلها غير مقروءة.
  Future<void> resetRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_readKey);
  }

  /// ينظّف معرّفات لحالات لم تعد قائمة، فلا تنمو القائمة بلا حدّ.
  Future<void> prune(Iterable<String> liveIds) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = (prefs.getStringList(_readKey) ?? const <String>[]).toSet();
    final live = liveIds.toSet();
    final kept = stored.intersection(live);
    if (kept.length != stored.length) {
      await prefs.setStringList(_readKey, kept.toList());
    }
  }

  static String _n(num v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? '${r.round()}' : '$r';
  }
}
