/// حساب الاستحقاق الفعلي: ما يستحقه المستفيدون على مدى، مقابل ما صُرف لهم فعلًا.
///
/// **مصدران للاستحقاق لا واحد** ([EntitlementSource]):
/// • **نسب المقرر** — الحصة الشهرية الثابتة للفرد من كل صنف. تُجيب عن السؤال
///   المحاسبي: «كم يستحق اللواء هذا الشهر؟».
/// • **خطة الوجبات** — قائمة الطعام يومًا بيوم. تُجيب عن السؤال التشغيلي:
///   «كم كان يلزم فعلًا لما طُبخ؟».
///
/// والفرق بينهما ليس أكاديميًا: وحدةٌ تطبخ أقل مما تستحق يظهر لها فائضٌ بمقياس
/// المقرر وتوازنٌ بمقياس الخطة. الأول يقول «لم يأخذوا حقهم»، والثاني يقول
/// «طُبخ ما خُطط له». وكلاهما صحيح ويُسأل عنه.
library;

import 'entitlements.dart';

class EntitlementSource {
  /// من نسب المقرر الشهرية (`Entitlements`).
  static const String scale = 'SCALE';

  /// من خطة وجبات نشطة (`MealPlans`).
  static const String plan = 'PLAN';

  static const List<String> all = [scale, plan];

  static const Map<String, String> labels = {
    scale: 'من نسب المقرر',
    plan: 'من خطة الوجبات',
  };

  static String label(String v) => labels[v] ?? v;
}

/// حركة مبسّطة كما يحتاجها الحساب — تُبنى من `MoveRow` في طبقة التقارير.
class ConsumptionMove {
  const ConsumptionMove({
    required this.itemId,
    required this.type,
    required this.baseQty,
    this.active = true,
  });

  final String itemId;

  /// `IN` | `OUT` | `RETURN_IN` | `RETURN_OUT` | `TRANSFER` | `OPENING`
  final String type;
  final double baseQty;

  /// سند مسودة أو ملغى ⇒ لا يدخل الحساب.
  final bool active;
}

/// سطر المقارنة لصنف واحد.
class ActualRow {
  const ActualRow({
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.entitled,
    required this.issued,
    required this.returned,
  });

  final String itemId;
  final String itemName;
  final String unitName;

  /// المستحق بوحدة الأساس.
  final double entitled;

  /// المصروف لهم.
  final double issued;

  /// ما ردّوه — يُخصم من المصروف لأنهم لم يستهلكوه.
  final double returned;

  double get consumed => issued - returned;

  /// موجب ⇒ لهم، وسالب ⇒ عليهم.
  double get balance => entitled - consumed;

  /// نسبة الاستهلاك إلى الاستحقاق. استحقاق صفر ⇒ صفر، لا قسمة على صفر.
  double get ratio => entitled <= 0 ? 0 : consumed / entitled;

  /// صُرف لهم صنفٌ لا يستحقونه أصلًا — يستحق انتباه المراجع.
  bool get unentitled => entitled <= 0 && consumed > 0;
}

class ActualEntitlement {
  const ActualEntitlement._();

  /// يبني سطور المقارنة.
  ///
  /// [entitled] معرّف الصنف ⇦ المستحق بوحدة الأساس، أيًّا كان مصدره.
  /// [moves] الحركات المرشَّحة مسبقًا بالمدى والمستودع والوحدة.
  ///
  /// **المرتجع يُخصم من المصروف.** حصرُ الاستهلاك في سندات الصرف وحدها — كما
  /// يفعل أكثر ما يُكتب في هذا الباب — يُظهر وحدةً ردّت نصف ما أخذت وكأنها
  /// استهلكته، فتُحرم من استحقاقها في الشهر التالي.
  static List<ActualRow> compute({
    required Map<String, double> entitled,
    required List<ConsumptionMove> moves,
    Map<String, String> names = const {},
    Map<String, String> units = const {},
  }) {
    final issued = <String, double>{};
    final returned = <String, double>{};
    for (final m in moves) {
      if (!m.active) continue;
      switch (m.type) {
        case 'OUT':
          issued.update(m.itemId, (v) => v + m.baseQty, ifAbsent: () => m.baseQty);
        case 'RETURN_IN':
          returned.update(m.itemId, (v) => v + m.baseQty, ifAbsent: () => m.baseQty);
        default:
          // الوارد والتحويل والرصيد الافتتاحي حركات مستودع لا استهلاك مستفيد.
          break;
      }
    }

    final ids = <String>{...entitled.keys, ...issued.keys, ...returned.keys};
    final out = [
      for (final id in ids)
        ActualRow(
          itemId: id,
          itemName: names[id] ?? '',
          unitName: units[id] ?? '',
          entitled: _round3(entitled[id] ?? 0),
          issued: _round3(issued[id] ?? 0),
          returned: _round3(returned[id] ?? 0),
        ),
    ];
    // الأبعد عن التوازن أولًا: من يقرأ التقرير يبحث عن الخلل لا عن الاتزان.
    out.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
    return out;
  }

  /// المستحق من نسب المقرر: المعدل اليومي للفرد × متوسط القوة × عدد الأيام.
  ///
  /// المتوسط هنا صحيح — بخلاف خطة الوجبات: المقرر حصة شهرية لا ترتبط بيوم
  /// بعينه، فتوزيعها على أيام الفترة بمتوسط القوة هو معناها نفسه.
  ///
  /// و[personsByDay] تُهمَل أيامها الخالية من التسجيل عمدًا: يومٌ لا تفريدة له
  /// ليس يومًا بقوة صفر، بل يوم لم يُسجَّل. اعتباره صفرًا يخفض الاستحقاق
  /// بسبب إهمال إداري.
  static Map<String, double> fromScale({
    required List<Entitlement> scales,
    required Map<String, int> personsByDay,
    required int days,
  }) {
    final recorded = personsByDay.values.where((v) => v > 0).toList();
    final avg = recorded.isEmpty
        ? 0
        : (recorded.reduce((a, b) => a + b) / recorded.length).round();
    return {
      for (final s in scales)
        s.itemId: _round3(
          EntitlementEngine.compute(entitlement: s, persons: avg, days: days).totalBaseQty,
        ),
    };
  }

  /// إجماليات التقرير.
  static ({double entitled, double consumed, double balance}) totals(List<ActualRow> rows) {
    var e = 0.0;
    var c = 0.0;
    for (final r in rows) {
      e += r.entitled;
      c += r.consumed;
    }
    return (entitled: _round3(e), consumed: _round3(c), balance: _round3(e - c));
  }

  static double _round3(double v) => (v * 1000).round() / 1000;
}
