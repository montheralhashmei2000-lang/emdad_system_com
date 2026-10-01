import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/auth_service.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_shimmer.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/stock_alerts.dart';
import 'home_shell.dart';

/// الشاشة الرئيسية:
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
  int items = 0, warehouses = 0, units = 0, suppliers = 0, facilities = 0, todayOps = 0, interventions = 0, low = 0, zero = 0, openStk = 0;
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
  List<String> _quickActionIds = const [];

  /// بطاقات المؤشرات المعروضة بترتيبها — فارغةٌ تعني الترتيب الافتراضي.
  List<String> _kpiIds = const [];

  /// المؤشرات المتاحة بمعرّفاتها وأسمائها، بالترتيب الافتراضي.
  static const _kpiCatalog = <(String, String)>[
    ('items', 'إجمالي الأصناف'),
    ('warehouses', 'المستودعات الفعالة'),
    ('todayOps', 'حركات اليوم'),
    ('interventions', 'إجراءات تحتاج تدخل'),
    ('stock', 'أصناف تحت الحد / صفرية'),
    ('openStk', 'جلسات جرد مفتوحة'),
  ];

  static const _quickActions = <(String, String, String)>[
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
    ('users', 'الصلاحيات والوصول', 'usersAccess'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _restoreQuickActions();
  }

  Future<void> _restoreQuickActions() async {
    final userId = context.read<AuthService>().currentUser?.id ?? 'local';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('imdad.dashboard.shortcuts.$userId');
    final kpis = prefs.getStringList('imdad.dashboard.kpis.$userId');
    if (!mounted) return;
    setState(() {
      if (saved != null) _quickActionIds = saved;
      // معرّفٌ محفوظٌ لم يعد في الكتالوج (أُزيل مؤشر في إصدارٍ لاحق) يُسقَط
      // هنا لا عند العرض، وإلا بقي في التفضيل المحفوظ إلى الأبد.
      if (kpis != null) {
        _kpiIds = kpis.where((id) => _kpiCatalog.any((k) => k.$1 == id)).toList();
      }
    });
  }

  /// اختيار المؤشرات وترتيبها: السحب يرتّب، ومربع الاختيار يُظهر ويُخفي.
  Future<void> _configureKpis(BuildContext context) async {
    final userId = context.read<AuthService>().currentUser?.id ?? 'local';
    // المعروضة أولًا بترتيبها، ثم المخفيّة — فالسحب يرتّب ما يُرى دون أن
    // تختفي البقية عن متناول اليد.
    final shown = _kpiIds.isEmpty ? _kpiCatalog.map((k) => k.$1).toList() : List<String>.of(_kpiIds);
    final ordered = [...shown, for (final k in _kpiCatalog) if (!shown.contains(k.$1)) k.$1];
    final selected = Set<String>.of(shown);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        final c = context.imd;
        String labelOf(String id) => _kpiCatalog.firstWhere((k) => k.$1 == id).$2;
        return AlertDialog(
          title: const Text('تخصيص بطاقات المؤشرات'),
          content: SizedBox(
            width: 460,
            height: 380,
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              // `onReorderItem` لا `onReorder`: الأخير يُسلّم فهرسًا محسوبًا
              // قبل الحذف فيحتاج تصحيحًا يدويًا، وهذا يُسلّمه مضبوطًا.
              onReorderItem: (from, to) => setDialogState(() => ordered.insert(to, ordered.removeAt(from))),
              children: [
                for (final (i, id) in ordered.indexed)
                  ListTile(
                    key: ValueKey(id),
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: selected.contains(id),
                      activeColor: c.accent,
                      onChanged: (v) => setDialogState(() {
                        if (v == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    ),
                    title: Text(labelOf(id),
                        style: TextStyle(color: selected.contains(id) ? c.text : c.muted)),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: ImdIcon('menu', size: 18, color: c.muted),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, [for (final id in ordered) if (selected.contains(id)) id]),
              child: const Text('حفظ'),
            ),
          ],
        );
      }),
    );
    if (result == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('imdad.dashboard.kpis.$userId', result);
    if (mounted) setState(() => _kpiIds = result);
  }

  Future<void> _configureQuickActions(BuildContext context, List<(String, String, String)> available) async {
    final userId = context.read<AuthService>().currentUser?.id ?? 'local';
    final initial = _quickActionIds.isEmpty
        ? available.take(6).map((a) => a.$3).toList()
        : _quickActionIds.where((id) => available.any((a) => a.$3 == id)).toList();
    final selected = Set<String>.of(initial);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        final c = context.imd;
        return AlertDialog(
          title: const Text('تخصيص الإجراءات السريعة'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final action in available)
                  CheckboxListTile(
                    value: selected.contains(action.$3),
                    activeColor: c.accent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(action.$2),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(action.$3);
                      } else {
                        selected.remove(action.$3);
                      }
                    }),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('حفظ')),
          ],
        );
      }),
    );
    if (result == null || !mounted) return;
    final ordered = [for (final a in available) if (result.contains(a.$3)) a.$3];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('imdad.dashboard.shortcuts.$userId', ordered);
    if (mounted) setState(() => _quickActionIds = ordered);
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
        ..units = units.length
        ..suppliers = suppliers.length
        ..facilities = facilities.length
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

  /// إرشاد أول استخدام: ما الذي ينقص النظام ليصير صالحًا للتشغيل.
  ///
  /// يظهر ما دام شيءٌ ناقصًا ويختفي من تلقائه عند اكتمال الأربع — فلا يحتاج
  /// زرّ «لا تُظهر هذا ثانيةً»، ولا يزاحم من أتمّ التهيئة على مساحة لوحته.
  ///
  /// ولا بيانات تجريبية تُزرع هنا: بذرةٌ في قاعدةٍ تشغيلية لا يُعرف بعد شهرٍ
  /// أصنافُها من أصناف الوحدة الحقيقية، فالإرشاد يدلّ على الشاشة ويترك
  /// الإدخال لصاحبه.
  List<Widget> _setupGuide(BuildContext context, _DashData d, ImdNav nav) {
    final steps = <(bool, String, String, String)>[
      (d.warehouses > 0, 'عرّف مستودعًا', 'لا حركة بلا مستودعٍ تدخل إليه الكميات وتخرج منه.', 'stores'),
      (d.items > 0, 'أضف الأصناف', 'الصنف ووحداته أساس كل سند وكل رصيد.', 'items'),
      (d.units > 0, 'عرّف الوحدات المستفيدة', 'إليها يُصرف، وعليها تُحسب الاستحقاقات.', 'units'),
      (d.suppliers > 0, 'أضف الموردين', 'منهم يُستلم الوارد ويُربط بسنده.', 'suppliers'),
    ];
    final remaining = steps.where((s) => !s.$1).length;
    if (remaining == 0) return const [];

    final c = context.imd;
    return [
      ImdPanel(
        margin: const EdgeInsets.only(bottom: 16),
        title: 'خطوات التهيئة',
        icon: 'compass',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdAlert(
            'بقي ${nf(remaining)} من ${nf(steps.length)} لتجهيز النظام للتشغيل.',
            tone: ImdTone.info,
          ),
          for (final (done, title, why, page) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ImdIcon(done ? 'check' : 'dot', size: 16, color: done ? c.success : c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: done ? c.muted : c.text,
                            decoration: done ? TextDecoration.lineThrough : null)),
                    Text(why, style: TextStyle(fontSize: 12, color: c.muted, height: 1.6)),
                  ]),
                ),
                if (!done) ...[
                  const SizedBox(width: 8),
                  ImdButton.outline(label: 'افتح', small: true, onPressed: () => nav.go(page)),
                ],
              ]),
            ),
        ]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final d = _d;
    final nav = ImdNav.of(context);
    String v(int Function(_DashData) f) => d == null ? '…' : nf(f(d));

    return ImdPage(
      children: [
        ImdPageTitle(
          title: 'لوحة التشغيل الرئيسية',
          icon: 'compass',
          subtitle: 'ملخص المخزون والمهام والتنبيهات، مع اختصارات تناسب صلاحياتك',
          actions: [
            ImdIconButton(
              icon: 'sliders',
              tooltip: 'تخصيص بطاقات المؤشرات',
              onPressed: () => _configureKpis(context),
            ),
          ],
        ),
        if (d != null) ..._setupGuide(context, d, nav),
        if (d == null)
          const ImdShimmerKpis(count: 6)
        else
          Builder(builder: (context) {
            final byId = {
              'items': ImdKpi(label: 'إجمالي الأصناف', value: v((d) => d.items)),
              'warehouses': ImdKpi(label: 'المستودعات الفعالة', value: v((d) => d.warehouses), color: c.accent),
              'todayOps': ImdKpi(label: 'حركات اليوم', value: v((d) => d.todayOps)),
              'interventions':
                  ImdKpi(label: 'إجراءات تحتاج تدخل', value: v((d) => d.interventions), color: c.danger),
              'stock': ImdKpi(
                  label: 'أصناف تحت الحد / صفرية',
                  value: '${nf(d.low)} / ${nf(d.zero)}',
                  color: c.danger),
              'openStk': ImdKpi(label: 'جلسات جرد مفتوحة', value: v((d) => d.openStk), color: c.accent),
            };
            final order = _kpiIds.isEmpty ? _kpiCatalog.map((k) => k.$1).toList() : _kpiIds;
            return ImdKpis(children: [
              for (final id in order)
                if (byId[id] != null) byId[id]!,
            ]);
          }),
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
                    // العنوان يتقلّص ولا يفيض: الصف بجوار الحلقة يضيق على
                    // الشاشات المتوسطة، ونصٌّ بلا `Flexible` يرسم شريطًا أصفر.
                    child: Row(children: [
                      ImdIcon('target', size: 17, color: c.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('مؤشر الصحة التشغيلية',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                      ),
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
            actions: [
              IconButton(
                tooltip: 'تخصيص الإجراءات',
                onPressed: () {
                  final auth = context.read<AuthService>();
                  final user = auth.currentUser;
                  final available = _quickActions.where((a) => user != null && (user.role == 'admin' || auth.can(user, a.$3))).toList();
                  _configureQuickActions(context, available);
                },
                icon: Icon(Icons.tune, color: c.muted, size: 19),
                visualDensity: VisualDensity.compact,
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(builder: (context) {
                  final user = context.read<AuthService>().currentUser;
                  final auth = context.read<AuthService>();
                  final available = _quickActions.where((a) => user != null && (user.role == 'admin' || auth.can(user, a.$3))).toList();
                  final orderedIds = _quickActionIds.isEmpty
                      ? available.map((a) => a.$3).toList()
                      : _quickActionIds;
                  final actions = [
                    for (final id in orderedIds)
                      for (final action in available)
                        if (action.$3 == id) action,
                  ];
                  Widget button((String, String, String) a) => ImdButton.outline(
                        label: a.$2,
                        icon: a.$1,
                        small: true,
                        onPressed: () => nav.go(a.$3),
                      );
                  final primary = actions.take(6).toList();
                  final more = actions.skip(6).toList();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ImdRbar(children: [for (final a in primary) button(a)]),
                    if (more.isNotEmpty)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: c.line),
                        // ExpansionTile يبني ListTile، وهذا يرسم تموّجه على أقرب
                        // Material فوقه. وأقربُ ما فوقه هنا خلفية ImdPanel الملوّنة
                        // فتحجب التموّج — وMaterial شفافةٌ تعطيه سطحًا بلا أثرٍ بصري.
                        child: Material(
                          type: MaterialType.transparency,
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            title: Text('إجراءات إضافية (${nf(more.length)})',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text2)),
                            children: [ImdRbar(bottom: 0, children: [for (final a in more) button(a)])],
                          ),
                        ),
                      ),
                  ]);
                }),
                const SizedBox(height: 12),
                const ImdNote('رتّب اختصاراتك من زر التخصيص، وتظهر الإجراءات المتاحة لحسابك فقط.'),
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
                ImdSeries('وارد', d?.rcv ?? const [], c.success),
                ImdSeries('صرف', d?.iss ?? const [], c.warn),
                ImdSeries('تحويل', d?.trf ?? const [], c.info),
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
                if (d == null)
                  const ImdShimmerTable(rows: 5, columns: 5)
                else
                  ImdTable(
                    columns: const [
                      ImdCol('الكود'),
                      ImdCol('الصنف', flex: 2),
                      ImdCol('الرصيد'),
                      ImdCol('الحد'),
                      ImdCol('الحالة'),
                    ],
                    cards: true,
                    empty: 'لا توجد تنبيهات مخزون حرجة الآن 👌',
                    rows: [
                      for (final (i, bal) in d.urgent)
                        [
                          Text(_or(i.code), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(_or(i.name)),
                          Text(nf(bal),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: bal <= 0 ? c.danger : c.warn)),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ImdStatusList(items: d?.ready ?? const []),
              if (d != null && (d.items == 0 || d.warehouses == 0 || d.units == 0 || d.suppliers == 0 || d.facilities == 0)) ...[
                const SizedBox(height: 10),
                ImdRbar(bottom: 0, children: [
                  if (d.items == 0)
                    ImdButton.outline(label: 'إضافة أول صنف', icon: 'package', small: true, onPressed: () => nav.go('items')),
                  if (d.warehouses == 0)
                    ImdButton.outline(label: 'إضافة أول مستودع', icon: 'warehouse', small: true, onPressed: () => nav.go('stores')),
                  if (d.units == 0)
                    ImdButton.outline(label: 'إضافة أول وحدة', icon: 'users', small: true, onPressed: () => nav.go('units')),
                  if (d.suppliers == 0)
                    ImdButton.outline(label: 'إضافة أول مورد', icon: 'truck', small: true, onPressed: () => nav.go('suppliers')),
                  if (d.facilities == 0)
                    ImdButton.outline(label: 'إضافة مطبخ أو فرن', icon: 'utensils', small: true, onPressed: () => nav.go('kitchens')),
                ]),
              ],
            ]),
          ),
          ImdPanel(
            margin: EdgeInsets.zero,
            title: 'آخر الأحداث المهمة',
            icon: 'clock',
            child: d == null
                ? const ImdShimmerTable(rows: 5, columns: 5)
                : ImdTable(
                    columns: const [
                      ImdCol('النوع'),
                      ImdCol('المرجع'),
                      ImdCol('الجهة', flex: 2),
                      ImdCol('التاريخ'),
                      ImdCol('الحالة'),
                    ],
                    cards: true,
                    empty: 'لا توجد حركة حديثة بعد',
                    rows: [
                      for (final r in d.feed)
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
