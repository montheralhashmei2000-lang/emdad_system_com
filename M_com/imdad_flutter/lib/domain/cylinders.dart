/// الأسطوانات (والأصناف القابلة للتعبئة عمومًا): أين كل أسطوانة، وهل هي ممتلئة أم فارغة.
///
/// الأسطوانة **صنف** يُعدّ بالكمية، لا أصل ثابت برقم تسلسلي: تُشترى بالعشرات،
/// وتتنقل بين المستودعات، وتُصرف عهدةً وتُسترجع، وتذهب للتعبئة وتعود. هذا كله
/// عمل سندات الحركة. لكنها **ليست مادة تُستهلك**: ما يُستهلك هو الغاز، والأسطوانة
/// تبقى — ممتلئة أو فارغة، في مستودع أو عند مورد أو عهدةً لدى مطبخ أو وحدة.
///
/// عدد أسطوانات المستودع يحسبه دفتر الأرصدة (`StockLedger`) كأي صنف. هذا الملف
/// يقسّم ذلك العدد على حالاته، ويتتبع ما خرج منه عهدةً، من السندات نفسها.
library;

/// عمليات الأسطوانات كما تُحفظ في `cylinder_action` لكل سطر سند.
class CylAction {
  const CylAction._();

  // ── الوارد
  /// شراء أسطوانات جديدة ممتلئة.
  static const receiveFull = 'RECEIVE_FULL';

  /// شراء أسطوانات جديدة فارغة.
  static const receiveEmpty = 'RECEIVE_EMPTY';

  /// عودة أسطوانات المستودع من التعبئة ممتلئة — العدد لا يتغير.
  static const refill = 'REFILL';

  // ── الصرف
  /// تسليم أسطوانات ممتلئة عهدةً (لوحدة أو مطبخ) — تخرج من عدد المستودع إلى عهدته.
  static const issueFull = 'ISSUE_FULL';

  /// تسليم أسطوانات فارغة عهدةً.
  static const issueEmpty = 'ISSUE_EMPTY';

  /// استبدال: المستلم يعيد فارغة ويأخذ ممتلئة — العدد لا يتغير في الطرفين.
  static const exchange = 'EXCHANGE';

  /// إرسال الفارغة إلى المورد لتعبئتها — تبقى ملك المستودع حتى تعود.
  static const sendRefill = 'SEND_REFILL';

  /// استهلاك داخلي (صرف نهائي): تخرج الأسطوانة من رصيد المستودع دون عهدة.
  static const consume = 'CONSUME';

  // ── التحويل والمرتجع
  static const transferFull = 'TRANSFER_FULL';
  static const transferEmpty = 'TRANSFER_EMPTY';
  static const returnFull = 'RETURN_FULL';
  static const returnEmpty = 'RETURN_EMPTY';

  /// عمليات لا تغيّر **عدد** أسطوانات المستودع (تغيّر حالتها أو مكانها المؤقت فقط).
  static const countNeutral = {refill, exchange, sendRefill};

  static const receiveOptions = [
    (receiveFull, 'شراء جديد — ممتلئة'),
    (receiveEmpty, 'شراء جديد — فارغة'),
    (refill, 'عودة من التعبئة (فارغة ← ممتلئة)'),
  ];

  static const issueOptions = [
    (exchange, 'استبدال: يعيد فارغة ويأخذ ممتلئة'),
    (issueFull, 'تسليم عهدة — ممتلئة'),
    (issueEmpty, 'تسليم عهدة — فارغة'),
    (sendRefill, 'إرسال الفارغة للمورد للتعبئة'),
    (consume, 'استهلاك داخلي — صرف نهائي'),
  ];

  static const transferOptions = [(transferFull, 'ممتلئة'), (transferEmpty, 'فارغة')];
  static const returnOptions = [(returnEmpty, 'فارغة'), (returnFull, 'ممتلئة')];

  static const Map<String, String> labels = {
    receiveFull: 'شراء ممتلئة',
    receiveEmpty: 'شراء فارغة',
    refill: 'عودة من التعبئة',
    issueFull: 'عهدة ممتلئة',
    issueEmpty: 'عهدة فارغة',
    exchange: 'استبدال',
    sendRefill: 'إرسال للتعبئة',
    consume: 'استهلاك داخلي',
    transferFull: 'تحويل ممتلئة',
    transferEmpty: 'تحويل فارغة',
    returnFull: 'إرجاع ممتلئة',
    returnEmpty: 'إرجاع فارغة',
  };

  static String label(String v) => labels[v] ?? v;
}

/// حالات الأسطوانة داخل المستودع.
enum CylState {
  full,
  empty,

  /// أُرسلت للمورد لتعبئتها ولم تعد بعد — ما زالت ملك المستودع.
  atRefill,

  /// حالتها غير مسجلة: رصيد افتتاحي، أو تسوية جرد، أو سندات قبل تتبع الحالة.
  unknown,
}

/// حركة واحدة تمس أسطوانات، مجرّدة من جداولها.
class CylMove {
  const CylMove({
    required this.kind,
    required this.itemId,
    required this.warehouse,
    required this.qty,
    this.action = '',
    this.status = 'COMPLETED',
    this.destWarehouse = '',
    this.holderKey = '',
    this.holderName = '',
    this.holderKind = CylHolderKind.unit,
    this.damaged = false,
    this.date = '',
    this.at,
  });

  final CylMoveKind kind;
  final String itemId;
  final String warehouse;
  final double qty;
  final String action;
  final String status;
  final String destWarehouse;

  /// صاحب العهدة (للصرف والمرتجع من وحدة): مفتاح ثابت واسم للعرض.
  final String holderKey;
  final String holderName;
  final CylHolderKind holderKind;

  /// مرتجع تالف: يخرج من العهدة ولا يدخل رصيد المستودع.
  final bool damaged;

  /// تاريخ السند (yyyy-MM-dd) ولحظة إنشائه — بهما تُرتّب الحركات.
  final String date;
  final DateTime? at;
}

enum CylMoveKind { opening, adjustment, receipt, issue, transfer, returnFromUnit, returnToSupplier }

enum CylHolderKind { unit, facility, other }

/// أسطوانات صنف في مستودع، موزعة على حالاتها.
class CylStock {
  double full = 0, empty = 0, atRefill = 0, unknown = 0;

  /// محوَّلة من هذا المستودع ولم يؤكَّد استلامها بعد (خرجت من عدده).
  double inTransit = 0;

  /// ما يطابق رصيد المستودع في دفتر الأرصدة.
  double get total => full + empty + atRefill + unknown;

  double _get(CylState s) => switch (s) {
        CylState.full => full,
        CylState.empty => empty,
        CylState.atRefill => atRefill,
        CylState.unknown => unknown,
      };

  void _add(CylState s, double q) {
    switch (s) {
      case CylState.full:
        full += q;
      case CylState.empty:
        empty += q;
      case CylState.atRefill:
        atRefill += q;
      case CylState.unknown:
        unknown += q;
    }
  }

  /// يأخذ [q] من الحالة [s]، وما نقص منها يؤخذ من «غير المسجلة»: أسطوانات ما
  /// قبل تتبع الحالة تُستهلك أولًا دون أن يختل المجموع عن دفتر الأرصدة.
  void _take(CylState s, double q) {
    final have = _get(s);
    if (s == CylState.unknown || have >= q) {
      _add(s, -q);
      return;
    }
    final fromS = have > 0 ? have : 0.0;
    _add(s, -fromS);
    unknown -= q - fromS;
  }
}

/// عهدة لدى جهة (وحدة أو مطبخ): **عدد** الأسطوانات بيدها.
///
/// لا تُتتبع حالتها هناك: الغاز يُستهلك عند الجهة بلا سند، فالممتلئة تصير
/// فارغة ولا يعلم النظام متى. حالة ممتلئة/فارغة تُعرف حيث تمر الأسطوانة بسند —
/// في المستودعات. أما العهدة فعددٌ يُسلَّم ويُسترجع.
class CylCustody {
  CylCustody(this.kind, this.name);

  final CylHolderKind kind;
  final String name;
  double count = 0;
}

/// موقف الأسطوانات: لكل صنف، في كل مستودع وعند كل صاحب عهدة.
class CylinderPosition {
  CylinderPosition._();

  final Map<String, Map<String, CylStock>> stock = {};
  final Map<String, Map<String, CylCustody>> custody = {};

  static const _inactive = {'DRAFT', 'ORDER', 'CANCELLED', 'REJECTED'};

  CylStock _wh(String item, String wh) => stock.putIfAbsent(item, () => {}).putIfAbsent(wh, CylStock.new);

  CylCustody _holder(CylMove m) => custody
      .putIfAbsent(m.itemId, () => {})
      .putIfAbsent(m.holderKey, () => CylCustody(m.holderKind, m.holderName));

  static CylState _stateOf(String action) => switch (action) {
        CylAction.receiveFull || CylAction.issueFull || CylAction.transferFull || CylAction.returnFull =>
          CylState.full,
        CylAction.receiveEmpty || CylAction.issueEmpty || CylAction.transferEmpty || CylAction.returnEmpty =>
          CylState.empty,
        _ => CylState.unknown,
      };

  /// الحركات تُرتّب زمنيًا أولًا: عدد المستودع لا يتأثر بالترتيب، أما توزيعه على
  /// الحالات فيتأثر — صرفٌ من مستودع فرعي قبل احتساب التحويل الذي أوصل إليه
  /// أسطواناته يأخذ من «غير المسجّلة» بدل الممتلئة.
  factory CylinderPosition.from(Iterable<CylMove> moves) {
    final p = CylinderPosition._();
    final ordered = moves.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0));
      });
    for (final m in ordered) {
      if (m.qty == 0 || m.itemId.isEmpty) continue;
      final q = m.qty;
      switch (m.kind) {
        case CylMoveKind.opening:
        case CylMoveKind.adjustment:
          if (m.kind == CylMoveKind.adjustment && _inactive.contains(m.status)) break;
          if (q >= 0) {
            p._wh(m.itemId, m.warehouse)._add(CylState.unknown, q);
          } else {
            p._wh(m.itemId, m.warehouse)._take(CylState.unknown, -q);
          }
        case CylMoveKind.receipt:
          if (_inactive.contains(m.status)) break;
          final s = p._wh(m.itemId, m.warehouse);
          if (m.action == CylAction.refill) {
            // تعود ممتلئة: من «عند المورد» أولًا، ثم من الفارغة (تعبئة لم يُسجَّل إرسالها).
            var left = q;
            final fromRefill = s.atRefill.clamp(0, left).toDouble();
            s.atRefill -= fromRefill;
            left -= fromRefill;
            if (left > 0) s._take(CylState.empty, left);
            s.full += q;
          } else {
            s._add(_stateOf(m.action), q);
          }
        case CylMoveKind.issue:
          if (_inactive.contains(m.status)) break;
          final s = p._wh(m.itemId, m.warehouse);
          switch (m.action) {
            case CylAction.exchange:
              // المستلم يعيد فارغة ويأخذ ممتلئة: عدد عهدته لا يتغير.
              s._take(CylState.full, q);
              s.empty += q;
            case CylAction.consume:
              // صرف نهائي: تخرج من المستودع ولا تصير عهدة لأحد.
              s._take(CylState.full, q);
            case CylAction.sendRefill:
              s._take(CylState.empty, q);
              s.atRefill += q;
            default:
              // تسليم عهدة (والسندات القديمة بلا عملية تُعدّ تسليمًا ممتلئًا).
              final st = m.action == CylAction.issueEmpty ? CylState.empty : CylState.full;
              s._take(st, q);
              if (m.holderKey.isNotEmpty) p._holder(m).count += q;
          }
        case CylMoveKind.transfer:
          if (m.status == 'REJECTED' || m.status == 'CANCELLED') break;
          final st = _stateOf(m.action);
          p._wh(m.itemId, m.warehouse)._take(st, q);
          if (m.status == 'RECEIVED') {
            p._wh(m.itemId, m.destWarehouse)._add(st, q);
          } else {
            p._wh(m.itemId, m.warehouse).inTransit += q;
          }
        case CylMoveKind.returnFromUnit:
          if (_inactive.contains(m.status)) break;
          // المرتجع يصل فارغًا ما لم يُذكر غير ذلك: هذا حال العهدة العائدة غالبًا.
          final st = m.action == CylAction.returnFull ? CylState.full : CylState.empty;
          if (!m.damaged) p._wh(m.itemId, m.warehouse)._add(st, q);
          if (m.holderKey.isNotEmpty) p._holder(m).count -= q;
        case CylMoveKind.returnToSupplier:
          if (_inactive.contains(m.status)) break;
          p._wh(m.itemId, m.warehouse)._take(
              m.action == CylAction.returnFull ? CylState.full : CylState.empty, q);
      }
    }
    return p;
  }

  /// إجمالي حالة في كل المستودعات لصنف.
  CylStock totalFor(String itemId) {
    final t = CylStock();
    for (final s in (stock[itemId] ?? const <String, CylStock>{}).values) {
      t.full += s.full;
      t.empty += s.empty;
      t.atRefill += s.atRefill;
      t.unknown += s.unknown;
      t.inTransit += s.inTransit;
    }
    return t;
  }

  /// إجمالي العهد لصنف.
  double custodyTotal(String itemId) =>
      (custody[itemId] ?? const <String, CylCustody>{}).values.fold(0.0, (a, c) => a + c.count);
}
