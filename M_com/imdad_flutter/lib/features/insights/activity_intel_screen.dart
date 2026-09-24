import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../home/home_shell.dart';

/// ذكاء النشاط والانحرافات — نقل `renderActivityIntel()`:
/// يقرأ سلوك آخر ١٤ يومًا (المستخدمون، المستودعات، الأصناف، ازدحام القرار)
/// ويستخرج الانحرافات ودرجة انضباط سلوكي مع توصيات قابلة للتنفيذ.
class ActivityIntelScreen extends StatefulWidget {
  const ActivityIntelScreen({super.key});

  @override
  State<ActivityIntelScreen> createState() => _ActivityIntelScreenState();
}

/// حِمل مستخدم خلال الفترة.
class _Actor {
  _Actor(this.name, this.role);
  final String name;
  final String role;
  int count = 0;
  int critical = 0;
  int sensitive = 0;
}

/// ضغط مستودع خلال الفترة.
class _Wh {
  _Wh(this.name);
  final String name;
  int count = 0;
  int pending = 0;
  int rejected = 0;
  int receipt = 0;
  int issue = 0;
  int transfer = 0;
}

/// نمط استهلاك صنف خلال الفترة.
class _ItemStress {
  _ItemStress(this.code, this.name);
  final String code;
  final String name;
  double issued = 0;
  double received = 0;
  double returnsOut = 0;
  double returnsIn = 0;
  int moves = 0;
  double current = 0;
  double min = 0;

  double get consumption => issued + returnsOut;
  double get inflow => received + returnsIn;
  double get stress => consumption - inflow;
}

class _ActivityIntelScreenState extends State<ActivityIntelScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final Perm _perm = Perm.of(context);

  bool _loading = true;

  // نتائج التحليل
  int _score = 100;
  int _anomalies = 0;
  List<_Actor> _actors = const [];
  List<_Actor> _actorFlags = const [];
  List<_Wh> _whs = const [];
  List<_Wh> _whFlags = const [];
  List<_ItemStress> _riskyItems = const [];
  int _risk7 = 0;
  int _draftReceipts = 0;
  int _pendingOrders = 0;
  int _pendingTransfers = 0;
  int _pendingUsers = 0;
  int _inactiveUsers = 0;
  double _actorAvg = 0;
  double _whAvg = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _decisionLoad =>
      _draftReceipts + _pendingOrders + _pendingTransfers + _pendingUsers + _inactiveUsers;
  bool get _backlogFlag => _decisionLoad >= 12;
  bool get _riskSpike => _risk7 >= 12;
  _Actor? get _topActor => _actors.isEmpty ? null : _actors.first;
  _Wh? get _topWh => _whs.isEmpty ? null : _whs.first;

  Future<void> _load() async {
    final now = DateTime.now();
    final since14 = now.subtract(const Duration(days: 14));
    final since7 = now.subtract(const Duration(days: 7));
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final d14 = iso(since14);

    final audits = await _db.select(_db.auditLogs).get();
    final receipts = await _db.select(_db.receipts).get();
    final issues = await _db.select(_db.issues).get();
    final transfers = await _db.select(_db.transfers).get();
    final returns = await _db.select(_db.returns).get();
    final users = _perm.admin ? await _db.select(_db.users).get() : <User>[];
    final items = await CatalogRepo(_db).items();
    final balances = await MovementsRepo(_db).balances(scope: _perm.scope);

    // ───── حِمل المستخدمين من سجل التدقيق (١٤ يومًا)
    final recent = audits.where((a) => a.createdAt.isAfter(since14)).toList();
    _risk7 = audits
        .where((a) =>
            a.createdAt.isAfter(since7) &&
            const {'critical', 'sensitive'}.contains(a.risk.toLowerCase()))
        .length;

    final actorMap = <String, _Actor>{};
    for (final r in recent) {
      final key = (r.actorEmail.isNotEmpty ? r.actorEmail : r.actorName).trim();
      final name = key.isEmpty ? 'غير معروف' : key;
      final a = actorMap.putIfAbsent(name, () => _Actor(name, r.actorRole));
      a.count++;
      if (r.risk.toLowerCase() == 'critical') a.critical++;
      if (r.risk.toLowerCase() == 'sensitive') a.sensitive++;
    }
    final actors = actorMap.values.toList()
      ..sort((a, b) => b.count != a.count ? b.count - a.count : b.critical - a.critical);
    _actorAvg = actors.isEmpty ? 0 : actors.fold<int>(0, (s, x) => s + x.count) / actors.length;
    final actorFlags = actors
        .where((x) => x.count >= math.max(8, (_actorAvg * 2).ceil()) || x.critical >= 2)
        .take(8)
        .toList();

    // ───── ضغط المستودعات
    final whMap = <String, _Wh>{};
    void addWh(String name, String type, String status) {
      final n = name.trim();
      if (n.isEmpty) return;
      final w = whMap.putIfAbsent(n, () => _Wh(n));
      w.count++;
      if (status == 'PENDING' || status == 'ORDER' || status == 'DRAFT') w.pending++;
      if (status == 'REJECTED') w.rejected++;
      if (type == 'receipt') w.receipt++;
      if (type == 'issue') w.issue++;
      if (type == 'transfer') w.transfer++;
    }

    for (final r in receipts.where((r) => r.date.compareTo(d14) >= 0)) {
      addWh(r.warehouse, 'receipt', r.status);
    }
    for (final r in issues.where((r) => r.date.compareTo(d14) >= 0)) {
      addWh(r.warehouse, 'issue', r.status);
    }
    for (final r in returns.where((r) => r.date.compareTo(d14) >= 0)) {
      addWh(r.warehouse, 'return', r.status);
    }
    for (final r in transfers.where((r) => r.date.compareTo(d14) >= 0)) {
      addWh(r.warehouse, 'transfer', r.status);
      addWh(r.destWarehouse, 'transfer', r.status);
    }
    final whs = whMap.values.toList()
      ..sort((a, b) => b.count != a.count ? b.count - a.count : b.rejected - a.rejected);
    _whAvg = whs.isEmpty ? 0 : whs.fold<int>(0, (s, x) => s + x.count) / whs.length;
    final whFlags = whs
        .where((x) =>
            x.count >= math.max(10, (_whAvg * 1.8).ceil()) || x.rejected >= 2 || x.pending >= 4)
        .take(8)
        .toList();

    // ───── نمط استهلاك الأصناف
    final byItem = <String, _ItemStress>{};
    final itemById = {for (final it in items) it.id: it};
    _ItemStress entry(String id, String fallback) {
      final it = itemById[id];
      return byItem.putIfAbsent(id.isEmpty ? fallback : id, () {
        final e = _ItemStress(it?.code ?? '', it?.name ?? fallback);
        e.current = balances[id] ?? 0;
        e.min = it?.minQty ?? 0;
        return e;
      });
    }

    for (final r in issues.where((r) => r.date.compareTo(d14) >= 0)) {
      final e = entry(r.itemId, r.itemName);
      e.issued += r.baseQty;
      e.moves++;
    }
    for (final r in receipts.where((r) => r.date.compareTo(d14) >= 0)) {
      final e = entry(r.itemId, r.itemName);
      e.received += r.baseQty;
      e.moves++;
    }
    for (final r in returns.where((r) => r.date.compareTo(d14) >= 0)) {
      final e = entry(r.itemId, r.itemName);
      e.moves++;
      if (r.type == 'TO_SUPPLIER') {
        e.returnsOut += r.baseQty;
      } else {
        e.returnsIn += r.baseQty;
      }
    }
    final itemRows = byItem.values.toList()
      ..sort((a, b) {
        final byStress = b.stress.compareTo(a.stress);
        return byStress != 0 ? byStress : b.consumption.compareTo(a.consumption);
      });
    final stressAvg = itemRows.isEmpty
        ? 0.0
        : itemRows.fold<double>(0, (s, x) => s + math.max(0.0, x.stress)) / itemRows.length;
    final risky = itemRows
        .where((x) =>
            (x.stress >= math.max(5, (stressAvg * 1.8).ceil()) || x.consumption >= 10) &&
            (x.current <= x.min || x.current <= 0))
        .take(10)
        .toList();

    // ───── ازدحام القرار
    _draftReceipts = receipts.where((r) => r.status == 'DRAFT').map((r) => r.refNo).toSet().length;
    _pendingOrders = issues.where((r) => r.status == 'ORDER').map((r) => r.refNo).toSet().length;
    _pendingTransfers =
        transfers.where((r) => r.status == 'PENDING').map((r) => r.refNo).toSet().length;
    _pendingUsers = users.where((u) => !u.approved).length;
    _inactiveUsers = users.where((u) => u.approved && !u.active).length;

    final anomalies = actorFlags.length +
        whFlags.length +
        risky.length +
        (_backlogFlag ? 1 : 0) +
        (_riskSpike ? 1 : 0);
    final score = math.max(
      0,
      math.min(
        100,
        100 -
            (actorFlags.length * 7 +
                whFlags.length * 6 +
                risky.length * 4 +
                (_backlogFlag ? 10 : 0) +
                (_riskSpike ? 10 : 0)),
      ),
    );

    if (!mounted) return;
    setState(() {
      _actors = actors;
      _actorFlags = actorFlags;
      _whs = whs;
      _whFlags = whFlags;
      _riskyItems = risky;
      _anomalies = anomalies;
      _score = score;
      _loading = false;
    });
  }


  void _go(String page) => context.read<ImdNav>().go(page);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(
          title: 'ذكاء النشاط والانحرافات',
          icon: 'bulb',
          subtitle: 'جارٍ تحليل السلوك التشغيلي، واستخراج الانحرافات والأنماط غير الطبيعية…',
        ),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;
    final scoreTone = _score >= 85 ? 'مسيطر' : (_score >= 65 ? 'تحت المراقبة' : 'محتاج تدخل');

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'ذكاء النشاط والانحرافات',
        icon: 'bulb',
        subtitle: 'شاشة تفهم سلوك التشغيل: مَن تحمّل فوق الطبيعي، أين الزحام، '
            'وما الأصناف التي بدأ نمطها يقلق، وهل هناك انحراف يجب إغلاقه مبكرًا.',
      ),
      ImdKpis(children: [
        ImdKpi(
          label: 'درجة الانضباط السلوكي',
          value: '${nf(_score)}%',
          color: _score >= 65 ? c.accent : c.danger,
        ),
        ImdKpi(label: 'عدد الانحرافات المرصودة', value: nf(_anomalies), color: c.danger),
        ImdKpi(label: 'أعلى حمل مستخدم', value: nf(_topActor?.count ?? 0)),
        ImdKpi(label: 'أعلى ضغط مستودع', value: nf(_topWh?.count ?? 0)),
        ImdKpi(label: 'أصناف حرجة سلوكيًا', value: nf(_riskyItems.length), color: c.danger),
        ImdKpi(
          label: 'إشارات مخاطر ٧ أيام',
          value: nf(_risk7),
          color: _riskSpike ? c.danger : c.accent,
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          centerVertically: true,
          child: Wrap(spacing: 18, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ImdScoreRing(percent: _score),
            SizedBox(
              width: 260,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('قراءة الانحرافات',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdChip(scoreTone,
                      tone: _score >= 85 ? ImdTone.ok : (_score >= 65 ? ImdTone.pend : ImdTone.err)),
                  ImdChip(
                    _actorFlags.isEmpty
                        ? 'لا شذوذ واضح للمستخدمين'
                        : 'شذوذ مستخدمين: ${nf(_actorFlags.length)}',
                    tone: _actorFlags.isEmpty ? ImdTone.ok : ImdTone.pend,
                  ),
                  ImdChip(
                    _riskyItems.isEmpty
                        ? 'الأصناف مستقرة نسبيًا'
                        : 'أصناف مقلقة: ${nf(_riskyItems.length)}',
                    tone: _riskyItems.isEmpty ? ImdTone.ok : ImdTone.err,
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  _score >= 85
                      ? 'السلوك التشغيلي متوازن والأنماط تحت السيطرة.'
                      : (_score >= 65
                          ? 'هناك إشارات يجب مراقبتها، لكنها قبل مرحلة الأزمة.'
                          : 'هناك انحرافات حقيقية تحتاج قرارات تشغيلية وإدارية أسرع.'),
                  style: TextStyle(fontSize: 13, height: 2, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
        ImdPanel(
          title: 'اختصارات التحليل السريع',
          icon: 'zap',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (page, label, icon) in const [
                ('healthOps', 'صحة النظام', 'shield'),
                ('executiveCmd', 'القيادة التنفيذية', 'target'),
                ('auditTrail', 'سجل النشاط', 'eye'),
                ('usersAccess', 'الصلاحيات والوصول', 'users'),
                ('pendingOrders', 'الأوامر المعلقة', 'bell'),
                ('balances', 'الأرصدة الحالية', 'calculator'),
                ('reports', 'مركز التقارير', 'chart'),
              ])
                ImdButton.outline(label: label, icon: icon, small: true, onPressed: () => _go(page)),
            ]),
            const SizedBox(height: 10),
            const ImdNote('هنا لا نعرض أعدادًا فقط — بل نحاول أن نفهم: هل ما يجري طبيعي، '
                'أم أن سلوكًا بدأ يخرج عن النمط الآمن؟'),
          ]),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'شذوذ سلوك المستخدمين',
          icon: 'user',
          child: ImdStatusList(items: _actorItems()),
        ),
        ImdPanel(
          title: 'المستودعات الأعلى ضغطًا',
          icon: 'warehouse',
          child: ImdStatusList(items: _whItems()),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'أصناف بنمط استهلاك لافت',
          icon: 'package',
          child: ImdTable(
            columns: const [
              ImdCol('الصنف'),
              ImdCol('الاستهلاك', numeric: true),
              ImdCol('التغذية العكسية', numeric: true),
              ImdCol('الضغط الصافي', numeric: true),
              ImdCol('الرصيد/الحد'),
            ],
            empty: 'لا توجد أصناف بسلوك استهلاك مقلق حاليًا',
            rows: [
              for (final x in _riskyItems)
                [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(x.code.isEmpty ? x.name : '${x.code} — ${x.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('حركات: ${nf(x.moves)}', style: TextStyle(fontSize: 11.5, color: c.muted)),
                  ]),
                  Text(nf(x.consumption), style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(nf(x.inflow)),
                  Text(nf(x.stress),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: x.stress > 0 ? c.danger : c.accent)),
                  ImdChip('${nf(x.current)} / ${nf(x.min)}',
                      tone: x.current <= x.min ? ImdTone.err : ImdTone.pend),
                ],
            ],
          ),
        ),
        ImdPanel(
          title: 'ازدحام القرار وإشارات الخطر',
          icon: 'alert',
          child: ImdStatusList(items: _riskItems()),
        ),
      ]),
      ImdPanel(
        title: 'توصيات ذكية قابلة للتنفيذ',
        icon: 'bulb',
        child: ImdStatusList(items: _insights()),
      ),
    ]);
  }

  List<(String, String, String)> _actorItems() {
    if (_actorFlags.isEmpty) {
      return const [
        ('', 'لا يوجد شذوذ واضح للمستخدمين',
            'توزيع النشاط بين المستخدمين يبدو متوازنًا خلال آخر ١٤ يومًا.')
      ];
    }
    const roles = {'admin': 'مدير النظام', 'user': 'مستخدم'};
    return [
      for (final a in _actorFlags)
        (
          a.critical >= 2 ? 'err' : 'warn',
          '${a.name}${a.role.isEmpty ? '' : ' • ${roles[a.role] ?? a.role}'}',
          'إجمالي نشاط ظاهر آخر ١٤ يومًا: ${nf(a.count)} • حساس: ${nf(a.sensitive)} • '
              'حرج: ${nf(a.critical)}'
              '${_topActor != null && a.name == _topActor!.name ? ' — الأعلى داخل الفترة.' : ''}',
        ),
    ];
  }

  List<(String, String, String)> _whItems() {
    if (_whFlags.isEmpty) {
      return const [
        ('', 'لا مستودعات خارجة عن النمط',
            'الضغط موزَّع بشكل مقبول بين المستودعات في آخر ١٤ يومًا.')
      ];
    }
    return [
      for (final w in _whFlags)
        (
          w.rejected >= 2 ? 'err' : 'warn',
          w.name,
          'إجمالي الحركات: ${nf(w.count)} • معلق: ${nf(w.pending)} • مرفوض: ${nf(w.rejected)} • '
              'وارد: ${nf(w.receipt)} • صرف: ${nf(w.issue)} • تحويل: ${nf(w.transfer)}',
        ),
    ];
  }

  List<(String, String, String)> _riskItems() => [
        (
          _backlogFlag ? 'warn' : '',
          'ازدحام القرار',
          'مسودات وارد: ${nf(_draftReceipts)} • أوامر صرف: ${nf(_pendingOrders)} • '
              'تحويلات معلقة: ${nf(_pendingTransfers)} • '
              'حسابات تحتاج قرارًا: ${nf(_pendingUsers + _inactiveUsers)}'
              '${_backlogFlag ? ' — هناك تراكم واضح يحتاج مسؤولًا ومدة استجابة.' : '.'}',
        ),
        (
          _riskSpike ? 'err' : '',
          'ارتفاع الأحداث الحساسة/الحرجة',
          'آخر ٧ أيام: ${nf(_risk7)}${_riskSpike ? ' — المعدل عالٍ ويستحق مراجعة يومية.' : '.'}',
        ),
        (
          _actorFlags.isEmpty ? '' : 'warn',
          'تركيز النشاط على أفراد بعينهم',
          _actorFlags.isEmpty
              ? 'النشاط البشري موزَّع بلا تمركز مقلق.'
              : 'عدد المستخدمين الخارجين عن المتوسط: ${nf(_actorFlags.length)} — '
                  'راجع توزيع الأعباء والصلاحيات.',
        ),
        (
          _whFlags.isEmpty ? '' : 'warn',
          'تمركز الضغط في مستودعات محددة',
          _whFlags.isEmpty
              ? 'لا يوجد تمركز ضغط غير طبيعي بالمستودعات.'
              : 'عدد المستودعات الخارجة عن النمط: ${nf(_whFlags.length)} — راقب الاختناق المحلي.',
        ),
        (
          _riskyItems.isEmpty ? '' : 'err',
          'ضغط على أصناف حساسة',
          _riskyItems.isEmpty
              ? 'لا توجد أصناف دخلت في نمط استهلاك خطر الآن.'
              : 'عدد الأصناف المقلقة: ${nf(_riskyItems.length)} — اربطها بالتوريد وإعادة التوزيع فورًا.',
        ),
      ];

  List<(String, String, String)> _insights() {
    final topActor = _topActor;
    final topWh = _topWh;
    return [
      (
        _score >= 85 ? '' : 'warn',
        'الخلاصة التنفيذية',
        _score >= 85
            ? 'السلوك التشغيلي متزن، ولا يوجد نمط واضح يتحول إلى خطر.'
            : 'هناك مؤشرات انحراف تستحق متابعة لصيقة قبل أن تصبح مشكلة تشغيلية كاملة.',
      ),
      (
        topActor != null && topActor.count >= math.max(12, (_actorAvg * 2).ceil()) ? 'warn' : '',
        'الحِمل البشري',
        topActor == null
            ? 'لا توجد بيانات كافية عن النشاط البشري.'
            : 'أعلى نشاط ظاهر على: ${topActor.name} بعدد ${nf(topActor.count)} حدث — '
                'تأكد أن هذا توزيع مقصود لا عبء زائد.',
      ),
      (
        topWh != null && topWh.count >= math.max(12, (_whAvg * 1.8).ceil()) ? 'warn' : '',
        'تمركز التشغيل',
        topWh == null
            ? 'لا توجد بيانات كافية عن المستودعات.'
            : 'المستودع الأعلى ضغطًا: ${topWh.name} بعدد ${nf(topWh.count)} حركة — '
                'راقب هل هذا طبيعي أم نتيجة اختناق في مواقع أخرى.',
      ),
      (
        _riskyItems.isEmpty ? '' : 'err',
        'توازن المخزون مع السلوك',
        _riskyItems.isEmpty
            ? 'الاستهلاك الحالي لا يولّد تهديدًا مباشرًا على الأصناف الحرجة.'
            : 'هناك أصناف استهلاكها يسبق التوريد أو الإرجاع — الأفضل تدخُّل تزويد أو إعادة توزيع '
                'بدل انتظار الصفر.',
      ),
      (
        _backlogFlag ? 'warn' : '',
        'سرعة اتخاذ القرار',
        _backlogFlag
            ? 'الطابور التشغيلي بدأ يتراكم، وغالبًا سيظهر لاحقًا في الرفض أو التأخير أو النقص.'
            : 'التراكم الإداري تحت السيطرة حاليًا.',
      ),
    ];
  }
}
