import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/stock_ledger.dart';
import '../home/home_shell.dart';
import '../inventory/doc_kit.dart';

/// مركز القيادة التنفيذية — نقل `renderExecutiveCmd()`:
/// ماذا يجب فعله الآن (مهام مرتّبة بالأولوية)، وما الذي سينفجر خلال ٧٢ ساعة
/// (تنبيهات استباقية من معدل الاستهلاك)، مع الأسباب التنفيذية وخلاصة مختصرة.
class ExecutiveCmdScreen extends StatefulWidget {
  const ExecutiveCmdScreen({super.key});

  @override
  State<ExecutiveCmdScreen> createState() => _ExecutiveCmdScreenState();
}

/// مهمة تنفيذية بأولوية ووجهة.
class _Task {
  const _Task(this.score, this.title, this.desc, this.page, [this.tag = '']);
  final int score;
  final String title;
  final String desc;
  final String page;
  final String tag;
}

/// تنبيه استباقي: critical | high | medium.
class _Alert {
  const _Alert(this.level, this.title, this.text);
  final String level;
  final String title;
  final String text;
}

/// توقّع ضغط صنف خلال ٧٢ ساعة.
class _Forecast {
  _Forecast({
    required this.code,
    required this.name,
    required this.current,
    required this.min,
    required this.dailyUse,
    required this.dailyIn,
  });

  final String code;
  final String name;
  final double current;
  final double min;
  final double dailyUse;
  final double dailyIn;

  /// الرصيد المتوقع بعد ٧٢ ساعة (استهلاك ٣ أيام مقابل توريد متوقع).
  double get projected72 => ((current - dailyUse * 3 + dailyIn * 1.2) * 100).round() / 100;

  /// عدد الأيام المتبقية بمعدل الاستهلاك الحالي (٩٩٩ = بلا استهلاك).
  double get runway => dailyUse > 0 ? (current / dailyUse * 10).round() / 10 : 999;

  int get severity =>
      (current <= 0 ? 120 : 0) +
      (projected72 <= 0 ? 80 : 0) +
      (projected72 <= min ? 45 : 0) +
      (runway <= 3 ? 35 : 0) +
      (dailyUse >= 5 ? 10 : 0);
}

class _ExecutiveCmdScreenState extends State<ExecutiveCmdScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final Perm _perm = Perm.of(context);

  bool _loading = true;
  int _execScore = 100;
  List<_Task> _tasks = const [];
  List<_Alert> _alerts = const [];
  List<_Forecast> _forecast = const [];

  int _draftReceipts = 0;
  int _pendingOrders = 0;
  int _pendingTransfers = 0;
  int _rejectedTransfers = 0;
  int _openStocktakes = 0;
  int _pendingUsers = 0;
  int _inactiveUsers = 0;
  int _criticalUnreviewed = 0;
  int _zeroItems = 0;
  int _suppliers = 0;
  int _warehouses = 0;
  int _facilities = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _backlog => _pendingOrders + _pendingTransfers + _draftReceipts;
  int get _urgentNow => _tasks.where((t) => t.score >= 80).length;

  Future<void> _load() async {
    final now = DateTime.now();
    final since14 = now.subtract(const Duration(days: 14));
    final since7 = now.subtract(const Duration(days: 7));
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final d14 = iso(since14);
    final d7 = iso(since7);

    final items = await CatalogRepo(_db).items();
    final receipts = await _db.select(_db.receipts).get();
    final issues = await _db.select(_db.issues).get();
    final transfers = await _db.select(_db.transfers).get();
    final returns = await _db.select(_db.returns).get();
    final stocktakes = await _db.select(_db.stocktakes).get();
    final audits = await _db.select(_db.auditLogs).get();
    final reviews = await _db.select(_db.sensitiveReviews).get();
    final users = _perm.admin ? await _db.select(_db.users).get() : <User>[];
    final balances = await MovementsRepo(_db).balances(scope: _perm.scope);

    _draftReceipts = receipts.where((x) => x.status == 'DRAFT').map((x) => x.refNo).toSet().length;
    _pendingOrders = issues.where((x) => x.status == 'ORDER').map((x) => x.refNo).toSet().length;
    _pendingTransfers =
        transfers.where((x) => x.status == 'PENDING').map((x) => x.refNo).toSet().length;
    _rejectedTransfers = transfers
        .where((x) => x.status == 'REJECTED' && x.date.compareTo(d7) >= 0)
        .map((x) => x.refNo)
        .toSet()
        .length;
    _openStocktakes = stocktakes.where((x) => x.status == 'COUNTING').length;
    _pendingUsers = users.where((u) => !u.approved).length;
    _inactiveUsers = users.where((u) => u.approved && !u.active).length;
    _zeroItems = items.where((i) => (balances[i.id] ?? 0) <= 0).length;
    _suppliers = (await CatalogRepo(_db).suppliers()).length;
    _warehouses = (await CatalogRepo(_db).warehouses(scope: _perm.scope)).length;
    _facilities = (await CatalogRepo(_db).facilities()).length;

    // الأحداث الحرجة التي لم تُراجع بعد.
    final reviewed = {for (final r in reviews) r.logId};
    _criticalUnreviewed = audits
        .where((a) => a.risk.toLowerCase() == 'critical' && !reviewed.contains(a.id))
        .length;

    // ───── توقّع ضغط المخزون من حركة آخر ١٤ يومًا
    // المعتمد وحده وضمن نطاق المستخدم: المسودة والأمر والملغى لم تمسّ الرصيد،
    // والرصيد المقارَن به هو رصيد مستودعات النطاق فقط.
    bool counts(String status, String warehouse, String date) =>
        !MovementRecord.inactiveStatuses.contains(status) &&
        (_perm.scope == null || _perm.scope!.contains(warehouse)) &&
        date.compareTo(d14) >= 0;
    final use = <String, double>{};
    final inflow = <String, double>{};
    for (final r in issues.where((r) => counts(r.status, r.warehouse, r.date))) {
      use[r.itemId] = (use[r.itemId] ?? 0) + r.baseQty;
    }
    for (final r in returns.where((r) => counts(r.status, r.warehouse, r.date))) {
      if (r.type == 'TO_SUPPLIER') {
        use[r.itemId] = (use[r.itemId] ?? 0) + r.baseQty;
      } else {
        inflow[r.itemId] = (inflow[r.itemId] ?? 0) + r.baseQty;
      }
    }
    for (final r in receipts.where((r) => counts(r.status, r.warehouse, r.date))) {
      inflow[r.itemId] = (inflow[r.itemId] ?? 0) + r.baseQty;
    }
    final byId = {for (final it in items) it.id: it};
    final forecast = <_Forecast>[];
    for (final id in {...use.keys, ...inflow.keys}) {
      final it = byId[id];
      if (it == null) continue;
      forecast.add(_Forecast(
        code: it.code,
        name: it.name,
        current: balances[id] ?? 0,
        min: it.minQty,
        dailyUse: math.max(0, (use[id] ?? 0) / 14),
        dailyIn: math.max(0, (inflow[id] ?? 0) / 14),
      ));
    }
    final flagged = forecast.where((x) => x.severity > 0).toList()
      ..sort((a, b) {
        final bySeverity = b.severity.compareTo(a.severity);
        return bySeverity != 0 ? bySeverity : a.runway.compareTo(b.runway);
      });
    final top = flagged.take(12).toList();

    // ───── التنبيهات الاستباقية
    final alerts = <_Alert>[
      for (final x in top.take(6))
        _Alert(
          (x.current <= 0 || x.projected72 <= 0) ? 'critical' : (x.runway <= 3 ? 'high' : 'medium'),
          'خطر نفاد محتمل للصنف',
          '${x.code.isEmpty ? '' : '${x.code} — '}${x.name} • رصيد: ${nf(x.current)} • '
              'حد: ${nf(x.min)} • متوقع خلال ٧٢ ساعة: ${nf(x.projected72)} • '
              'مدة الكفاية: ${x.runway >= 999 ? '∞' : '${nf(x.runway)} يوم'}',
        ),
      if (_backlog >= 12)
        const _Alert('high', 'تكدس قرارات تشغيلية',
            'الأوامر والتحويلات والمسودات المفتوحة بلغت مستوى يهدد سرعة التنفيذ خلال اليومين القادمين.'),
      if (_criticalUnreviewed >= 2)
        const _Alert('critical', 'تراكم حرِج غير مُراجع',
            'توجد عناصر حرجة مفتوحة، وهذا يرفع احتمال قرار خاطئ أو تأخير حرج إن تُركت لآخر اليوم.'),
      if (_pendingUsers + _inactiveUsers >= 4)
        const _Alert('medium', 'ضغط وصول وصلاحيات',
            'تراكم حسابات تحتاج قرارًا قد يعطّل الاستجابة أو يخلق فتحًا/غلقًا متأخرًا للصلاحيات.'),
      if (_openStocktakes >= 2)
        const _Alert('high', 'خطر تداخل جرد وتسويات',
            'أكثر من أمر جرد مفتوح يرفع احتمالية الارتباك في التسوية أو التأخر في الإغلاق.'),
    ];

    // ───── المهام مرتّبة بالأولوية
    final tasks = <_Task>[
      if (_criticalUnreviewed > 0)
        _Task(100, 'إقفال العناصر الحرجة المفتوحة',
            'عددها ${nf(_criticalUnreviewed)} — يجب مراجعتها قبل أي توسّع أو اعتماد جديد.',
            'sensitiveOps', 'حرج'),
      if (top.isNotEmpty)
        _Task(92, 'حماية الأصناف المهددة خلال ٧٢ ساعة',
            'هناك ${nf(top.length)} صنف بإشارات نفاد أو ضغط استهلاك واضح.',
            'balances', 'توريد/إعادة توزيع'),
      if (_pendingOrders + _pendingTransfers >= 8)
        _Task(88, 'تقليل تراكم القرار',
            'أوامر الصرف والتحويلات المعلقة بلغت ${nf(_pendingOrders + _pendingTransfers)}.',
            'pendingOrders', 'تشغيلي'),
      if (_draftReceipts >= 4)
        _Task(72, 'إغلاق مسودات الوارد المفتوحة',
            'المسودات المفتوحة: ${nf(_draftReceipts)} — تخلق ضبابية تشغيلية إن تُركت.',
            'receive', 'انضباط'),
      if (_openStocktakes >= 2)
        _Task(82, 'حسم الجرد المفتوح',
            'عدد أوامر الجرد المفتوحة: ${nf(_openStocktakes)} — الأفضل إغلاق القديم قبل الجديد.',
            'stocktake', 'رقابة'),
      if (_pendingUsers + _inactiveUsers > 0)
        _Task(68, 'تنظيف طابور الوصول والصلاحيات',
            'طلبات وحسابات تحتاج قرارًا: ${nf(_pendingUsers + _inactiveUsers)}.',
            'usersAccess', 'حوكمة'),
      if (_rejectedTransfers >= 2)
        _Task(60, 'مراجعة الرفض المتكرر للتحويلات',
            'خلال آخر ٧ أيام يوجد ${nf(_rejectedTransfers)} رفض — راجع السبب قبل تكراره.',
            'auditTrail', 'تنسيق'),
    ]..sort((a, b) => b.score - a.score);

    final score = math.max<int>(
      0,
      math.min<int>(
        100,
        100 -
            (_criticalUnreviewed * 12 +
                alerts.where((a) => a.level == 'critical').length * 10 +
                alerts.where((a) => a.level == 'high').length * 6 +
                math.min<int>(20, _pendingOrders + _pendingTransfers) +
                math.min<int>(10, _zeroItems)),
      ),
    );

    if (!mounted) return;
    setState(() {
      _forecast = top;
      _alerts = alerts;
      _tasks = tasks;
      _execScore = score;
      _loading = false;
    });
  }

  void _go(String page) => context.read<ImdNav>().go(page);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(
          title: 'مركز القيادة التنفيذية',
          icon: 'target',
          subtitle: 'جارٍ تجهيز الأولويات التنفيذية، والتنبيهات الاستباقية، وقائمة ما يجب فعله الآن…',
        ),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final tone = _execScore >= 85
        ? 'مسيطر'
        : (_execScore >= 65 ? 'تحت المتابعة' : 'يحتاج قيادة فورية');

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'مركز القيادة التنفيذية',
        icon: 'target',
        subtitle: 'شاشة المدير قبل بداية اليوم وأثناء الضغط: ما الذي يجب فعله الآن، '
            'وما الذي لو تُرك ساعات قليلة سيتحول إلى مشكلة حقيقية.',
      ),
      ImdKpis(children: [
        ImdKpi(
          label: 'درجة القيادة التنفيذية',
          value: '${nf(_execScore)}%',
          color: _execScore >= 65 ? c.accent : c.danger,
        ),
        ImdKpi(label: 'مهام يجب فعلها الآن', value: nf(_urgentNow), color: c.danger),
        ImdKpi(label: 'تنبيهات استباقية ٧٢ ساعة', value: nf(_alerts.length)),
        ImdKpi(label: 'حرِج غير مُراجع', value: nf(_criticalUnreviewed), color: c.danger),
        ImdKpi(label: 'تراكم القرار', value: nf(_backlog)),
        ImdKpi(label: 'أصناف متوقعة الضغط', value: nf(_forecast.length), color: c.danger),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          centerVertically: true,
          child: Wrap(spacing: 18, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ImdScoreRing(percent: _execScore),
            SizedBox(
              width: 260,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('قراءة القائد التنفيذي',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdChip(tone,
                      tone: _execScore >= 85
                          ? ImdTone.ok
                          : (_execScore >= 65 ? ImdTone.pend : ImdTone.err)),
                  ImdChip(
                    _urgentNow == 0 ? 'لا توجد أولويات حرجة الآن' : 'أولويات فورية: ${nf(_urgentNow)}',
                    tone: _urgentNow == 0 ? ImdTone.ok : ImdTone.err,
                  ),
                  ImdChip(
                    _alerts.isEmpty
                        ? 'لا يوجد إنذار استباقي قوي'
                        : 'إنذارات ٧٢ ساعة: ${nf(_alerts.length)}',
                    tone: _alerts.length >= 4 ? ImdTone.pend : ImdTone.ok,
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  _execScore >= 85
                      ? 'الوضع التنفيذي متماسك، والمشهد تحت السيطرة إن استمر الإيقاع الحالي.'
                      : (_execScore >= 65
                          ? 'هناك ضغط وتوقعات تستحق تدخلًا مركزًا، لكن ما زال يمكن تداركها بسهولة.'
                          : 'الصورة تقول بوضوح: مطلوب تدخل قيادي مباشر الآن، لا متابعة فقط.'),
                  style: TextStyle(fontSize: 13, height: 2, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
        ImdPanel(
          title: 'مركز التوجيه السريع',
          icon: 'zap',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (page, label, icon) in const [
                ('healthOps', 'صحة النظام', 'shield'),
                ('activityIntel', 'ذكاء النشاط', 'bulb'),
                ('sensitiveOps', 'المراجعة الحساسة', 'alert'),
                ('auditTrail', 'سجل النشاط', 'eye'),
                ('pendingOrders', 'الأوامر المعلقة', 'bell'),
                ('balances', 'الأرصدة الحالية', 'calculator'),
                ('reports', 'مركز التقارير', 'chart'),
              ])
                ImdButton.outline(label: label, icon: icon, small: true, onPressed: () => _go(page)),
            ]),
            const SizedBox(height: 10),
            const ImdNote('المنطق هنا بسيط: المدير لا يحتاج رؤية كل شيء بالعمق نفسه طوال الوقت — '
                'يحتاج أن يعرف ماذا يفعل الآن، وما الذي سينفجر لاحقًا إن تجاهله.'),
          ]),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'ما يجب فعله الآن',
          icon: 'alert',
          child: _tasks.isEmpty
              ? ImdSoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    ImdEmojiText('✅ لا توجد مهام حرجة فورية',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.accent)),
                    const SizedBox(height: 6),
                    Text('يمكنك العمل على التحسينات بدل الإطفاء السريع للحرائق.',
                        style: TextStyle(fontSize: 12.5, color: c.muted)),
                  ]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final t in _tasks.take(6)) _taskCard(t),
                ]),
        ),
        ImdPanel(
          title: 'التنبيهات الاستباقية خلال ٧٢ ساعة',
          icon: 'hourglass',
          child: ImdStatusList(
            items: _alerts.isEmpty
                ? const [
                    ('', 'لا توجد إشارات استباقية قوية',
                        'لا يوجد نمط واضح الآن يوحي بأزمة قريبة خلال ٧٢ ساعة.')
                  ]
                : [
                    for (final a in _alerts.take(8))
                      (a.level == 'critical' ? 'err' : (a.level == 'high' ? 'warn' : ''), a.title, a.text),
                  ],
          ),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'الأسباب التنفيذية الرئيسية',
          icon: 'pin',
          child: ImdStatusList(items: _drivers()),
        ),
        ImdPanel(
          title: 'خلاصة تنفيذية مختصرة',
          icon: 'bulb',
          child: ImdStatusList(items: _insights()),
        ),
      ]),
    ]);
  }

  /// `taskCard(t)`
  Widget _taskCard(_Task t) {
    final c = context.imd;
    return ImdDocCard(
      head: [
        ImdChip('أولوية ${nf(t.score)}',
            tone: t.score >= 90 ? ImdTone.err : (t.score >= 75 ? ImdTone.pend : ImdTone.off)),
        if (t.tag.isNotEmpty) ImdChip(t.tag, tone: ImdTone.code),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
        const SizedBox(height: 8),
        Text(t.desc, style: TextStyle(fontSize: 12.8, height: 1.9, color: c.muted)),
      ]),
      actions: [
        ImdButton.outline(
          label: 'افتح الآن',
          icon: 'arrow-down-right',
          small: true,
          onPressed: () => _go(t.page),
        ),
      ],
    );
  }

  List<(String, String, String)> _drivers() => [
        (
          _criticalUnreviewed > 0 ? 'err' : '',
          'الملفات الحرجة المفتوحة',
          'عددها ${nf(_criticalUnreviewed)}'
              '${_criticalUnreviewed > 0 ? ' — يجب أن تأخذ أول قرار اليوم.' : '.'}',
        ),
        (
          _forecast.isEmpty ? '' : 'warn',
          'الضغط القادم على المخزون',
          'أصناف تدخل منطقة الخطر خلال ٧٢ ساعة: ${nf(_forecast.length)}'
              '${_forecast.isEmpty ? '.' : ' — جهّز توريدًا أو إعادة توزيع.'}',
        ),
        (
          _pendingOrders + _pendingTransfers >= 8 ? 'warn' : '',
          'سرعة القرار التشغيلي',
          'الأوامر والتحويلات المفتوحة: ${nf(_pendingOrders + _pendingTransfers)}'
              '${_pendingOrders + _pendingTransfers >= 8 ? ' — هذا تراكم واضح.' : '.'}',
        ),
        (
          _openStocktakes >= 2 ? 'warn' : '',
          'تداخل الجرد والعمليات',
          'أوامر الجرد المفتوحة: ${nf(_openStocktakes)}'
              '${_openStocktakes >= 2 ? ' — هناك مخاطرة تضارب تسويات.' : '.'}',
        ),
        (
          _suppliers > 0 && _warehouses > 0 && _facilities > 0 ? '' : 'warn',
          'جاهزية البيئة',
          'موردون: ${nf(_suppliers)} • مستودعات: ${nf(_warehouses)} • '
              'مرافق تشغيل: ${nf(_facilities)}',
        ),
      ];

  List<(String, String, String)> _insights() {
    final top = _tasks.isEmpty ? null : _tasks.first;
    return [
      (
        _execScore >= 85 ? '' : 'warn',
        'الحكم التنفيذي',
        _execScore >= 85
            ? 'المنظومة لا تحتاج تدخلًا تصحيحيًا ثقيلًا الآن — فقط متابعة ذكية.'
            : (_execScore >= 65
                ? 'هناك ملفان أو ثلاثة تستحق تدخلًا مركزًا قبل نهاية اليوم.'
                : 'إن تُرك الوضع بلا قرار سريع، ستزيد المخاطر التشغيلية بوضوح.'),
      ),
      (
        top != null && top.score >= 90 ? 'err' : '',
        'أول حركة اليوم',
        top == null
            ? 'لا توجد مهمة تتقدم على غيرها بشكل حاد.'
            : 'ابدأ بـ: ${top.title} — لأنها صاحبة أعلى أثر حالي.',
      ),
      (
        _forecast.length >= 4 ? 'warn' : '',
        'الـ ٧٢ ساعة القادمة',
        _forecast.length >= 4
            ? 'هناك ضغط متوقع على المخزون، فالأفضل استباق الأزمة بدل إدارتها بعد وقوعها.'
            : 'المخزون لا يعطي إشارة أزمة قريبة واسعة النطاق.',
      ),
      (
        _pendingUsers + _inactiveUsers >= 4 ? 'warn' : '',
        'التفويض والوصول',
        _pendingUsers + _inactiveUsers >= 4
            ? 'إن تراكمت الحسابات ستتأثر سرعة الاستجابة حتى لو كان التشغيل نفسه جيدًا.'
            : 'طبقة الوصول والصلاحيات لا تبدو معطِّلة للتشغيل الآن.',
      ),
      (
        _rejectedTransfers >= 2 ? 'warn' : '',
        'احتكاك التنسيق',
        _rejectedTransfers >= 2
            ? 'الرفض المتكرر للتحويلات غالبًا يعني مشكلة تنسيق أو تحقق قبل الإرسال.'
            : 'لا يوجد نمط رفض مزعج في التحويلات مؤخرًا.',
      ),
    ];
  }
}
