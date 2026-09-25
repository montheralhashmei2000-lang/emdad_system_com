import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/stock_alerts.dart';
import 'home_shell.dart';

/// الرئيسية — نقل مطابق لـ `renderDash()` في نسخة الويب:
/// Dashboard + Admin Operations Center بمؤشراته ومؤشر الصحة والإجراءات السريعة والرسوم والقوائم.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _Feed {
  const _Feed(this.label, this.ref, this.party, this.date, this.createdAt, this.status);
  final String label, ref, party, date, status;
  final int createdAt;
}

class _DashData {
  int items = 0, warehouses = 0, todayOps = 0, interventions = 0, low = 0, zero = 0, openStk = 0;
  int score = 0;
  List<(bool, String)> healthChips = const [];
  String healthNote = '';
  List<(String, String, String)> actions = const []; // (dot, title, desc)
  List<(String, String, String)> ready = const [];
  List<(Item, double)> urgent = const [];
  List<_Feed> feed = const [];
  List<String> trendLabels = const [];
  List<int> rcv = const [], iss = const [], trf = const [];
  List<String> whLabels = const [];
  List<int> whValues = const [];
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  _DashData? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final can = auth.currentUser?.role == 'admin';
    final db = _db;
    final items = await db.select(db.items).get();
    final units = await db.select(db.beneficiaryUnits).get();
    final receipts = await db.select(db.receipts).get();
    final issues = await db.select(db.issues).get();
    final transfers = await db.select(db.transfers).get();
    final returns = await db.select(db.returns).get();
    final stocktakes = await db.select(db.stocktakes).get();
    final facilities = await db.select(db.facilities).get();
    final warehouses = await db.select(db.warehouses).get();
    final suppliers = await db.select(db.suppliers).get();
    final users = can ? await db.select(db.users).get() : <User>[];
    final totals = await MovementsRepo(db).balances();

    double q(Item i) => totals[i.id] ?? 0;
    double mn(Item i) => i.minQty;
    final lowItems = items.where((i) => mn(i) > 0 && q(i) <= mn(i)).toList();
    final zeroItems = items.where((i) => q(i) <= 0).toList();
    final pendingReceipts = receipts.where((x) => x.status == 'DRAFT').length;
    final pendingIssues = issues.where((x) => x.status == 'ORDER').length;
    final pendingTransfers = transfers.where((x) => x.status == 'PENDING').length;
    final rejectedTransfers = transfers.where((x) => x.status == 'REJECTED').length;
    final openStocktakes = stocktakes.where((x) => x.status == 'COUNTING').length;
    final pendingUsers = users.where((u) => !u.approved).length;
    final inactiveUsers = users.where((u) => u.approved && !u.active).length;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    int timeOf(DateTime createdAt, String date) {
      final t = createdAt.millisecondsSinceEpoch;
      if (t > 0) return t;
      return DateTime.tryParse(date)?.millisecondsSinceEpoch ?? 0;
    }

    final times = [
      ...receipts.map((x) => timeOf(x.createdAt, x.date)),
      ...issues.map((x) => timeOf(x.createdAt, x.date)),
      ...transfers.map((x) => timeOf(x.createdAt, x.date)),
      ...returns.map((x) => timeOf(x.createdAt, x.date)),
    ];
    final todayOps = times.where((t) => t >= todayStart).length;
    final interventions = pendingReceipts +
        pendingIssues +
        pendingTransfers +
        lowItems.length +
        zeroItems.length +
        openStocktakes +
        pendingUsers +
        inactiveUsers;

    final checks = <(bool, int)>[
      (items.isNotEmpty && units.isNotEmpty, 20),
      (suppliers.isNotEmpty && warehouses.isNotEmpty, 15),
      (facilities.isNotEmpty, 10),
      (pendingReceipts == 0, 10),
      (pendingIssues == 0, 10),
      (pendingTransfers == 0, 10),
      (openStocktakes <= 1, 10),
      (lowItems.length <= 5, 8),
      (zeroItems.isEmpty, 7),
      if (can) (pendingUsers == 0 && inactiveUsers == 0, 10),
    ];
    final totalW = checks.fold<int>(0, (a, x) => a + x.$2);
    final okW = checks.where((x) => x.$1).fold<int>(0, (a, x) => a + x.$2);
    final score = ((okW / (totalW == 0 ? 100 : totalW)) * 100).round();

    final actions = <(String, String, String)>[
      (
        pendingIssues > 0 ? 'warn' : '',
        'أوامر صرف معلقة',
        'يوجد ${nf(pendingIssues)} أمر صرف بانتظار اعتماد أو رفض من أمين المستودع.'
      ),
      (
        pendingTransfers > 0 ? 'warn' : '',
        'تحويلات بانتظار الاستلام',
        'عدد التحويلات المعلقة حاليًا: ${nf(pendingTransfers)}${pendingTransfers > 0 ? ' — راجعها قبل تراكم الفروقات.' : '.'}'
      ),
      (
        pendingReceipts > 0 ? 'warn' : '',
        'مسودات وارد غير منتهية',
        'عدد المسودات المفتوحة: ${nf(pendingReceipts)}${pendingReceipts > 0 ? ' — راجعها أو اقفلها لتقليل اللخبطة.' : '.'}'
      ),
      (
        (lowItems.isNotEmpty || zeroItems.isNotEmpty) ? 'err' : '',
        'ضغط المخزون',
        'تحت الحد: ${nf(lowItems.length)} • صفرية: ${nf(zeroItems.length)}${lowItems.isNotEmpty || zeroItems.isNotEmpty ? ' — ده أهم تدخل يومي للمدير.' : '.'}'
      ),
      (
        openStocktakes > 0 ? 'warn' : '',
        'الجرد المفتوح',
        'جلسات الجرد المفتوحة: ${nf(openStocktakes)}${openStocktakes > 0 ? ' — الأفضل غلق القديم قبل فتح جديد.' : '.'}'
      ),
      if (can)
        (
          (pendingUsers > 0 || inactiveUsers > 0) ? 'warn' : '',
          'وضع المستخدمين',
          'طلبات انضمام جديدة: ${nf(pendingUsers)} • حسابات غير مفعلة: ${nf(inactiveUsers)}${pendingUsers > 0 || inactiveUsers > 0 ? ' — راجعها من شاشة المستخدمين.' : '.'}'
        ),
      if (rejectedTransfers > 0)
        (
          'warn',
          'تحويلات مرفوضة مؤخرًا',
          'يوجد ${nf(rejectedTransfers)} تحويل مرفوض يحتاج مراجعة السبب ومعالجة الإعادة أو التعديل.'
        ),
    ];

    final basicOk = items.isNotEmpty && units.isNotEmpty;
    final supplyOk = suppliers.isNotEmpty && warehouses.isNotEmpty;
    final dailyOk = facilities.isNotEmpty;
    final stkOk = openStocktakes <= 1;
    final ready = <(String, String, String)>[
      (
        basicOk ? '' : 'warn',
        'البيانات الأساسية',
        basicOk ? 'الأصناف والوحدات جاهزة ويُمكن الاعتماد عليها.' : 'لازم الأصناف والوحدات تكون مكتملة قبل أي تشغيل جاد.'
      ),
      (
        supplyOk ? '' : 'warn',
        'سلسلة التوريد',
        supplyOk ? 'الموردون والمستودعات متاحون لتشغيل الوارد والتحويل.' : 'أضف الموردين والمستودعات لتأمين دورة استلام محترمة.'
      ),
      (
        dailyOk ? '' : 'warn',
        'التشغيل اليومي',
        dailyOk
            ? 'المطابخ/الأفران موجودة ويمكن متابعة التغذية اليومية.'
            : 'التشغيل اليومي ناقص لأن المطابخ/الأفران غير مكتملة.'
      ),
      (
        stkOk ? '' : 'warn',
        'الرقابة والجرد',
        stkOk ? 'الجرد تحت السيطرة بدون تكدس جلسات مفتوحة.' : 'فيه أكثر من جلسة جرد مفتوحة — ده يربك التسويات والمتابعة.'
      ),
      ('', 'وضع الأمان', 'وضع الأمان الحالي محافظ: بعض عمليات الإدارة الحساسة ما زالت مقصودة خارج الواجهة لتقليل المخاطر.'),
    ];

    double sev(Item i) => (q(i) <= 0 ? 100000 : 0) + (mn(i) > 0 ? (mn(i) - q(i)) : 0);
    final urgent = items.where((i) => mn(i) > 0 || q(i) <= 0).toList()
      ..sort((a, b) => sev(b).compareTo(sev(a)));

    final feed = <_Feed>[
      ...receipts.map((x) => _Feed('وارد', _or(x.refNo), _or(x.supplier), x.date, timeOf(x.createdAt, x.date), x.status)),
      ...issues.map((x) => _Feed(x.status == 'ORDER' ? 'أمر صرف' : 'صرف', _or(x.refNo),
          _or(x.recipientDisplay.isNotEmpty ? x.recipientDisplay : x.beneficiaryUnitName), x.date,
          timeOf(x.createdAt, x.date), x.status)),
      ...transfers.map((x) => _Feed('تحويل', _or(x.refNo), '${_or(x.warehouse)} ← ${_or(x.destWarehouse)}', x.date,
          timeOf(x.createdAt, x.date), x.status)),
      ...returns.map((x) => _Feed('مرتجع', _or(x.refNo), _or(x.party), x.date, timeOf(x.createdAt, x.date),
          x.type.isNotEmpty ? x.type : x.status)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final labels = <String>[];
    final rcv = <int>[], iss = <int>[], trf = <int>[];
    for (var i = 13; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final s = d.millisecondsSinceEpoch;
      final e = d.add(const Duration(days: 1)).millisecondsSinceEpoch;
      labels.add('${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      bool inDay(int t) => t >= s && t < e;
      rcv.add(receipts.where((x) => inDay(timeOf(x.createdAt, x.date))).length);
      iss.add(issues.where((x) => inDay(timeOf(x.createdAt, x.date))).length);
      trf.add(transfers.where((x) => inDay(timeOf(x.createdAt, x.date))).length);
    }

    final whMap = <String, int>{};
    void bump(String name) {
      final n = name.trim();
      if (n.isEmpty) return;
      whMap[n] = (whMap[n] ?? 0) + 1;
    }

    for (final x in receipts) {
      bump(x.warehouse);
    }
    for (final x in issues) {
      bump(x.warehouse);
    }
    for (final x in returns) {
      bump(x.warehouse);
    }
    for (final x in transfers) {
      bump(x.warehouse);
      bump(x.destWarehouse);
    }
    final topWh = (whMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(7).toList().reversed.toList();

    if (!mounted) return;
    setState(() {
      _d = _DashData()
        ..items = items.length
        ..warehouses = warehouses.length
        ..todayOps = todayOps
        ..interventions = interventions
        ..low = lowItems.length
        ..zero = zeroItems.length
        ..openStk = openStocktakes
        ..score = score
        ..healthChips = [
          (score >= 85, 'صحي جدًا'),
          (score >= 65, 'قابل للتشغيل بثقة'),
          (interventions <= 10, 'التدخلات ضمن السيطرة'),
          (lowItems.isEmpty, 'لا ضغط مخزون حرج'),
        ]
        ..healthNote = score >= 85
            ? 'الوضع ممتاز — المدير يقدر يدير التشغيل من الشاشة دي بدون لف كتير بين الصفحات.'
            : (score >= 65
                ? 'الوضع جيد لكن فيه نقاط تحتاج تدخل سريع لتقليل الاحتكاك اليومي والأخطاء البشرية.'
                : 'الوضع محتاج تدخل إداري واضح الآن — في عناصر تشغيلية أو مخزنية مؤثرة على الاستقرار اليومي.')
        ..actions = actions
        ..ready = ready
        ..urgent = urgent.take(10).map((i) => (i, q(i))).toList()
        ..feed = feed.take(12).toList()
        ..trendLabels = labels
        ..rcv = rcv
        ..iss = iss
        ..trf = trf
        ..whLabels = topWh.isEmpty ? ['لا بيانات'] : topWh.map((e) => e.key).toList()
        ..whValues = topWh.isEmpty ? [0] : topWh.map((e) => e.value).toList();
    });
  }

  static String _or(String s) => s.isEmpty ? '—' : s;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final d = _d;
    final can = context.read<AuthService>().currentUser?.role == 'admin';
    final nav = ImdNav.of(context);
    String v(int Function(_DashData) f) => d == null ? '…' : nf(f(d));

    return ImdPage(
      children: [
        const ImdPageTitle(
          title: 'Dashboard + Admin Operations Center',
          icon: 'compass',
          subtitle:
              'رؤية تشغيلية موحدة للمدير: المخزون، الإجراءات المعلقة، الجاهزية، والتنبيهات الحرجة — من شاشة واحدة بشكل production فعلي',
        ),
        ImdKpis(children: [
          ImdKpi(label: 'إجمالي الأصناف', value: v((d) => d.items)),
          ImdKpi(label: 'المستودعات الفعالة', value: v((d) => d.warehouses), color: c.accent),
          ImdKpi(label: 'حركات اليوم', value: v((d) => d.todayOps)),
          ImdKpi(label: 'إجراءات تحتاج تدخل', value: v((d) => d.interventions), color: c.danger),
          ImdKpi(
              label: 'أصناف تحت الحد / صفرية',
              value: d == null ? '…' : '${nf(d.low)} / ${nf(d.zero)}',
              color: c.danger),
          ImdKpi(label: 'جلسات جرد مفتوحة', value: v((d) => d.openStk), color: c.accent),
        ]),
        const SizedBox(height: 16),
        ImdGrid2(children: [
          ImdPanel(
            margin: EdgeInsets.zero,
            centerVertically: true,
            child: LayoutBuilder(builder: (context, cons) {
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      ImdIcon('target', size: 17, color: c.accent),
                      const SizedBox(width: 6),
                      Text('مؤشر الصحة التشغيلية',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final ch in d?.healthChips ?? const <(bool, String)>[])
                        ImdChip(ch.$2, tone: ch.$1 ? ImdTone.ok : ImdTone.pend),
                    ]),
                  ),
                  Text(d?.healthNote ?? 'جارٍ تحليل الجاهزية والتدخلات اليومية…',
                      style: TextStyle(fontSize: 13, height: 2, color: c.muted)),
                ],
              );
              final ring = ImdScoreRing(percent: d?.score ?? 0);
              // display:flex; align-items:center; gap:18; flex-wrap:wrap — النص flex:1 بحد أدنى 220.
              if (cons.maxWidth >= 112 + 18 + 220) {
                return Row(children: [ring, const SizedBox(width: 18), Expanded(child: info)]);
              }
              return Column(children: [ring, const SizedBox(height: 18), info]);
            }),
          ),
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'مركز الإجراءات السريعة',
            icon: 'zap',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ImdRbar(children: [
                  for (final a in [
                    ('bell', 'الأوامر المعلقة', 'pendingOrders'),
                    ('calculator', 'الأرصدة الحالية', 'balances'),
                    ('chart', 'مركز التقارير', 'reports'),
                    ('clipboard', 'الجرد', 'stocktake'),
                    ('warehouse', 'المستودعات', 'stores'),
                    ('truck', 'الموردون', 'suppliers'),
                    ('settings', 'الإعدادات', 'settings'),
                    ('shield', 'صحة النظام', 'healthOps'),
                    ('bulb', 'ذكاء النشاط', 'activityIntel'),
                    ('target', 'القيادة التنفيذية', 'executiveCmd'),
                    ('scan', 'سجل النشاط', 'auditTrail'),
                    ('alert', 'المراجعة الحساسة', 'sensitiveOps'),
                    ('utensils', 'التشغيل اليومي', 'kitchenLog'),
                    if (can) ('users', 'الصلاحيات والوصول', 'usersAccess'),
                  ])
                    ImdButton.outline(
                      label: a.$2,
                      icon: a.$1,
                      small: true,
                      onPressed: () => nav.go(a.$3),
                    ),
                ]),
                const SizedBox(height: 12),
                const ImdNote(
                  'الفكرة هنا مش مجرد Dashboard شكلي — دي شاشة تشغيل تنفيذية تساعد المدير يعرف فين الخطر، فين الزحمة، وإيه اللي محتاج تدخل فورًا.',
                ),
              ],
            ),
          ),
        ]),
        ImdGrid2(children: [
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'اتجاه الحركة التشغيلية (آخر 14 يومًا)',
            icon: 'trending',
            child: ImdLineChart(
              labels: d?.trendLabels ?? const [],
              series: [
                ImdSeries('وارد', d?.rcv ?? const [], const Color(0xFF159A58)),
                ImdSeries('صرف', d?.iss ?? const [], const Color(0xFFD97706)),
                ImdSeries('تحويل', d?.trf ?? const [], const Color(0xFF16527C)),
              ],
            ),
          ),
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'أكثر المستودعات نشاطًا',
            icon: 'warehouse',
            child: ImdHBarChart(labels: d?.whLabels ?? const [], values: d?.whValues ?? const []),
          ),
        ]),
        ImdGrid2(children: [
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'مركز تدخلات اليوم',
            icon: 'alert',
            child: ImdStatusList(items: d?.actions ?? const []),
          ),
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'أخطر الأصناف حاليًا',
            icon: 'alert',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    ImdChip('تحت الحد: ${nf(d?.low ?? 0)}', tone: ImdTone.pend),
                    ImdChip('صفرية: ${nf(d?.zero ?? 0)}', tone: ImdTone.err),
                    ImdChip('معروضة الآن: ${nf(d?.urgent.length ?? 0)}', tone: ImdTone.off),
                  ]),
                ),
                ImdTable(
                  columns: const [
                    ImdCol('الكود'),
                    ImdCol('الصنف', flex: 2),
                    ImdCol('الرصيد'),
                    ImdCol('الحد'),
                    ImdCol('الحالة'),
                  ],
                  empty: 'لا توجد تنبيهات مخزون حرجة الآن 👌',
                  rows: [
                    for (final (i, bal) in d?.urgent ?? const <(Item, double)>[])
                      [
                        Text(_or(i.code), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_or(i.name)),
                        Text(nf(bal),
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: bal <= 0 ? c.danger : const Color(0xFF915E06))),
                        Text(i.minQty > 0 ? nf(i.minQty) : '—'),
                        bal <= 0
                            ? const ImdChip('صفرية', tone: ImdTone.err)
                            : (StockAlerts.isLow(bal, i.minQty)
                                ? const ImdChip('تحت الحد', tone: ImdTone.pend)
                                : const ImdChip('مستقرة', tone: ImdTone.ok)),
                      ],
                  ],
                ),
              ],
            ),
          ),
        ]),
        ImdGrid2(children: [
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'حالة الجاهزية الأساسية',
            icon: 'flask',
            child: ImdStatusList(items: d?.ready ?? const []),
          ),
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'آخر الأحداث المهمة',
            icon: 'clock',
            child: ImdTable(
              columns: const [ImdCol('النوع'), ImdCol('المرجع'), ImdCol('الجهة', flex: 2), ImdCol('التاريخ'), ImdCol('الحالة')],
              empty: 'لا توجد حركة حديثة بعد',
              rows: [
                for (final r in d?.feed ?? const <_Feed>[])
                  [
                    Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(r.ref),
                    Text(r.party),
                    Text(r.date.isEmpty ? '—' : r.date),
                    ImdChip(
                      r.status.isEmpty ? 'ACTIVE' : r.status,
                      tone: const ['ORDER', 'DRAFT', 'PENDING'].contains(r.status)
                          ? ImdTone.pend
                          : (r.status == 'REJECTED' ? ImdTone.err : ImdTone.ok),
                    ),
                  ],
              ],
            ),
          ),
        ]),
      ],
    );
  }
}
