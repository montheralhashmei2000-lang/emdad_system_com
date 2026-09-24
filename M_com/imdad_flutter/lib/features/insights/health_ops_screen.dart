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
import '../home/home_shell.dart';
import '../inventory/doc_kit.dart';
import '../settings/audit_screen.dart';

/// صحة النظام والعمليات — نقل `renderHealthOps()`:
/// مؤشر جاهزية من تسعة فحوص، ضغط تشغيلي، حالة أمنية، إشارات خطر،
/// وآخر الأحداث الحرجة غير المُراجعة، مع ملاحظات صحة ذكية.
class HealthOpsScreen extends StatefulWidget {
  const HealthOpsScreen({super.key});

  @override
  State<HealthOpsScreen> createState() => _HealthOpsScreenState();
}

class _HealthOpsScreenState extends State<HealthOpsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final Perm _perm = Perm.of(context);

  bool _loading = true;

  int _low = 0;
  int _zero = 0;
  int _draftReceipts = 0;
  int _pendingOrders = 0;
  int _pendingTransfers = 0;
  int _rejectedRecent = 0;
  int _openStocktakes = 0;
  int _pendingUsers = 0;
  int _inactiveUsers = 0;
  int _todayOps = 0;
  int _sensitiveTotal = 0;
  int _suppliers = 0;
  int _warehouses = 0;
  int _facilities = 0;
  int _score = 100;
  List<AuditLog> _criticalUnreviewed = const [];
  int _sensitiveUnreviewed = 0;

  /// قنوات الانضمام الحساسة (Bootstrap/Join/Activate) مقفلة في هذا التطبيق.
  static const bool _authLocked = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _pressure =>
      _draftReceipts +
      _pendingOrders +
      _pendingTransfers +
      _criticalUnreviewed.length * 3 +
      _sensitiveUnreviewed +
      _pendingUsers +
      _inactiveUsers +
      _openStocktakes +
      _low +
      _zero;

  String get _pressureLabel =>
      _pressure >= 35 ? 'مرتفع جدًا' : (_pressure >= 18 ? 'متوسط' : 'منخفض');
  String get _pressureTone => _pressure >= 35 ? 'err' : (_pressure >= 18 ? 'warn' : '');

  Future<void> _load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final today = iso(todayStart);
    final weekAgo = iso(todayStart.subtract(const Duration(days: 7)));

    final catalog = CatalogRepo(_db);
    final items = await catalog.items();
    final receipts = await _db.select(_db.receipts).get();
    final issues = await _db.select(_db.issues).get();
    final transfers = await _db.select(_db.transfers).get();
    final returns = await _db.select(_db.returns).get();
    final stocktakes = await _db.select(_db.stocktakes).get();
    final audits = await _db.select(_db.auditLogs).get();
    final reviews = await _db.select(_db.sensitiveReviews).get();
    final users = _perm.admin ? await _db.select(_db.users).get() : <User>[];
    final balances = await MovementsRepo(_db).balances(scope: _perm.scope);

    final suppliers = (await catalog.suppliers()).length;
    final warehouses = (await catalog.warehouses(scope: _perm.scope)).length;
    final facilities = (await catalog.facilities()).length;

    final low = items.where((x) => x.minQty > 0 && (balances[x.id] ?? 0) <= x.minQty).length;
    final zero = items.where((x) => (balances[x.id] ?? 0) <= 0).length;

    Set<String> refs(Iterable<dynamic> rows, bool Function(dynamic) test) =>
        {for (final r in rows) if (test(r)) r.refNo as String};

    final draftReceipts = refs(receipts, (x) => x.status == 'DRAFT').length;
    final pendingOrders = refs(issues, (x) => x.status == 'ORDER').length;
    final pendingTransfers = refs(transfers, (x) => x.status == 'PENDING').length;
    final rejectedRecent =
        refs(transfers, (x) => x.status == 'REJECTED' && (x.date as String).compareTo(weekAgo) >= 0)
            .length;
    final openStocktakes = stocktakes.where((x) => x.status == 'COUNTING').length;

    final todayOps = [
      ...refs(receipts, (x) => x.date == today),
      ...refs(issues, (x) => x.date == today),
      ...refs(transfers, (x) => x.date == today),
      ...refs(returns, (x) => x.date == today),
    ].length;

    final reviewed = {for (final r in reviews) r.logId};
    final critical = audits.where((a) => a.risk.toLowerCase() == 'critical').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sensitive = audits.where((a) => a.risk.toLowerCase() == 'sensitive').toList();
    final criticalUnreviewed = critical.where((a) => !reviewed.contains(a.id)).toList();
    final sensitiveUnreviewed = sensitive.where((a) => !reviewed.contains(a.id)).length;

    // تسعة فحوص جاهزية — النسبة = عدد الناجح منها.
    final flags = [
      items.isNotEmpty && warehouses > 0,
      suppliers > 0,
      facilities > 0,
      _authLocked,
      criticalUnreviewed.isEmpty,
      openStocktakes <= 1,
      pendingOrders <= 5,
      pendingTransfers <= 5,
      zero <= 5,
    ];
    final score = (flags.where((x) => x).length / flags.length * 100).round();

    if (!mounted) return;
    setState(() {
      _low = low;
      _zero = zero;
      _draftReceipts = draftReceipts;
      _pendingOrders = pendingOrders;
      _pendingTransfers = pendingTransfers;
      _rejectedRecent = rejectedRecent;
      _openStocktakes = openStocktakes;
      _pendingUsers = users.where((u) => !u.approved).length;
      _inactiveUsers = users.where((u) => u.approved && !u.active).length;
      _todayOps = todayOps;
      _sensitiveTotal = critical.length + sensitive.length;
      _criticalUnreviewed = criticalUnreviewed;
      _sensitiveUnreviewed = sensitiveUnreviewed;
      _suppliers = suppliers;
      _warehouses = warehouses;
      _facilities = facilities;
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
          title: 'صحة النظام والعمليات',
          icon: 'shield',
          subtitle: 'جارٍ تحليل صحة المنظومة، الضغط التشغيلي، ومؤشرات المخاطر…',
        ),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final c = context.imd;

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'مركز صحة النظام والعمليات',
        icon: 'shield',
        subtitle: 'شاشة موحدة لقراءة صحة المنظومة: الجاهزية، الضغط، عناصر الخطر، '
            'والانحرافات التشغيلية قبل أن تتحول إلى أزمة.',
      ),
      ImdKpis(children: [
        ImdKpi(label: 'مؤشر الصحة العام', value: '${nf(_score)}%', color: c.accent),
        ImdKpi(
          label: 'ضغط التشغيل',
          value: _pressureLabel,
          color: _pressure >= 35 ? c.danger : null,
        ),
        ImdKpi(label: 'حرج غير مُراجع', value: nf(_criticalUnreviewed.length), color: c.danger),
        ImdKpi(label: 'حساس غير مُراجع', value: nf(_sensitiveUnreviewed)),
        ImdKpi(label: 'حركات اليوم', value: nf(_todayOps)),
        ImdKpi(label: 'أصناف منخفضة/صفرية', value: '${nf(_low)} / ${nf(_zero)}', color: c.danger),
        ImdKpi(
          label: 'أوامر/تحويلات معلقة',
          value: '${nf(_pendingOrders)} / ${nf(_pendingTransfers)}',
        ),
        ImdKpi(
          label: 'مستخدمون يحتاجون قرارًا',
          value: nf(_pendingUsers + _inactiveUsers),
          color: c.accent,
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
                Text('قراءة صحة المنظومة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdChip(
                    _criticalUnreviewed.isEmpty ? 'لا توجد حرجة مفتوحة' : 'توجد عناصر حرجة مفتوحة',
                    tone: _criticalUnreviewed.isEmpty ? ImdTone.ok : ImdTone.err,
                  ),
                  ImdChip('ضغط التشغيل: $_pressureLabel',
                      tone: _pressureTone == 'err'
                          ? ImdTone.err
                          : (_pressureTone == 'warn' ? ImdTone.pend : ImdTone.ok)),
                  const ImdChip('قنوات الانضمام الحساسة مقفلة', tone: ImdTone.ok),
                ]),
                const SizedBox(height: 8),
                Text(
                  _score >= 85
                      ? 'الوضع قوي جدًا ومناسب للتشغيل المنضبط.'
                      : (_score >= 65
                          ? 'الوضع جيد لكنه يحتاج متابعة لصيقة للعناصر المفتوحة.'
                          : 'الوضع يحتاج تدخلًا إداريًا وتقنيًا أسرع قبل توسّع الاستخدام.'),
                  style: TextStyle(fontSize: 13, height: 2, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
        ImdPanel(
          title: 'اختصارات التدخل السريع',
          icon: 'zap',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (page, label, icon) in const [
                ('sensitiveOps', 'طابور المراجعة', 'alert'),
                ('auditTrail', 'سجل النشاط', 'eye'),
                ('activityIntel', 'ذكاء النشاط', 'bulb'),
                ('executiveCmd', 'القيادة التنفيذية', 'target'),
                ('usersAccess', 'الصلاحيات والوصول', 'users'),
                ('pendingOrders', 'الأوامر المعلقة', 'bell'),
                ('balances', 'الأرصدة الحالية', 'calculator'),
                ('stocktake', 'الجرد', 'clipboard'),
              ])
                ImdButton.outline(label: label, icon: icon, small: true, onPressed: () => _go(page)),
            ]),
            const SizedBox(height: 10),
            const ImdNote('الفرق بين هذه الشاشة ولوحة المعلومات أن التركيز هنا ليس على المتابعة '
                'اليومية فقط، بل على صحة المنظومة نفسها: المخاطر والتراكمات والحوكمة.'),
          ]),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'الحالة الأمنية والتشغيلية',
          icon: 'shield',
          child: ImdStatusList(items: _stateItems()),
        ),
        ImdPanel(
          title: 'إشارات الخطر الحالية',
          icon: 'package',
          child: ImdStatusList(items: _riskItems()),
        ),
      ]),
      ImdGrid2(children: [
        ImdPanel(
          title: 'آخر الأحداث الحرجة',
          icon: 'file',
          child: _criticalUnreviewed.isEmpty
              ? ImdSoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    ImdEmojiText('✅ لا أحداث حرجة مفتوحة',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.accent)),
                    const SizedBox(height: 6),
                    Text('وهي أقوى علامة على أن الحوكمة تسير بشكل صحيح.',
                        style: TextStyle(fontSize: 12.5, color: c.muted)),
                  ]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final r in _criticalUnreviewed.take(12)) _criticalCard(r),
                ]),
        ),
        ImdPanel(
          title: 'ملاحظات الصحة الذكية',
          icon: 'bulb',
          child: ImdStatusList(items: _insights()),
        ),
      ]),
    ]);
  }

  Widget _criticalCard(AuditLog r) {
    final c = context.imd;
    return ImdDocCard(
      head: [
        const ImdChip('حرج', tone: ImdTone.err),
        ImdChip(auditActionLabel(r.action), tone: ImdTone.code),
        ImdChip(r.logDate.isEmpty ? '—' : r.logDate, tone: ImdTone.off),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(r.summary, style: TextStyle(fontSize: 12.8, height: 1.9, color: c.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (r.refNo.isNotEmpty) ImdChip(r.refNo, tone: ImdTone.code),
          if (r.warehouse.isNotEmpty) ImdChip(r.warehouse, tone: ImdTone.off, icon: 'warehouse'),
          if (r.target.isNotEmpty) ImdChip(r.target, tone: ImdTone.off, icon: 'target'),
        ]),
      ]),
      actions: [
        ImdButton.outline(
          label: 'فتح السجل',
          icon: 'arrow-down-right',
          small: true,
          onPressed: () => _go('auditTrail'),
        ),
        ImdButton.outline(
          label: 'فتح المراجعة',
          icon: 'alert',
          small: true,
          onPressed: () => _go('sensitiveOps'),
        ),
      ],
    );
  }

  List<(String, String, String)> _stateItems() => [
        (
          _authLocked ? '' : 'warn',
          'وضع الدخول والانضمام',
          'قنوات التهيئة والانضمام والتفعيل مقفلة حاليًا من الواجهة — '
              'وهو المناسب لمرحلة الحماية الحالية.',
        ),
        (
          _criticalUnreviewed.isEmpty ? '' : 'err',
          'التغييرات الحرجة',
          'العناصر الحرجة غير المراجَعة: ${nf(_criticalUnreviewed.length)}'
              '${_criticalUnreviewed.isEmpty ? '.' : ' — يجب ألّا تبقى مفتوحة.'}',
        ),
        (
          _openStocktakes > 1 ? 'warn' : '',
          'الجرد والتسويات',
          'أوامر الجرد المفتوحة: ${nf(_openStocktakes)}'
              '${_openStocktakes > 1 ? ' — الأفضل إغلاق القديم قبل فتح جديد.' : '.'}',
        ),
        (
          _pendingUsers + _inactiveUsers > 0 ? 'warn' : '',
          'إدارة الوصول',
          'طلبات وحسابات تحتاج قرارًا: ${nf(_pendingUsers + _inactiveUsers)}'
              '${_pendingUsers + _inactiveUsers > 0 ? ' — راجع مركز الصلاحيات.' : '.'}',
        ),
        (
          _draftReceipts + _pendingOrders + _pendingTransfers > 12 ? 'warn' : '',
          'الضغط التشغيلي',
          'مسودات وارد: ${nf(_draftReceipts)} • أوامر صرف: ${nf(_pendingOrders)} • '
              'تحويلات معلقة: ${nf(_pendingTransfers)}',
        ),
      ];

  List<(String, String, String)> _riskItems() => [
        (
          _zero > 0 ? 'err' : '',
          'الأصناف الصفرية',
          'عدد الأصناف صفرية الرصيد: ${nf(_zero)}'
              '${_zero > 0 ? ' — مؤشر خطر مباشر على الاستمرارية.' : '.'}',
        ),
        (
          _low > 0 ? 'warn' : '',
          'الأصناف تحت الحد',
          'عدد الأصناف تحت الحد: ${nf(_low)}'
              '${_low > 0 ? ' — راجع التوريد أو إعادة التوزيع.' : '.'}',
        ),
        (
          _rejectedRecent > 0 ? 'warn' : '',
          'التحويلات المرفوضة مؤخرًا',
          'خلال آخر ٧ أيام: ${nf(_rejectedRecent)}'
              '${_rejectedRecent > 0 ? ' — راجع أسباب الرفض فهي غالبًا تكشف خللًا تنسيقيًا.' : '.'}',
        ),
        (
          _sensitiveTotal > 40 ? 'warn' : '',
          'كثافة الأحداث الحساسة',
          'إجمالي الحساسة/الحرجة المقروءة: ${nf(_sensitiveTotal)}'
              '${_sensitiveTotal > 40 ? ' — طبيعي مع التوسع لكنه يحتاج مراجعة مستمرة.' : '.'}',
        ),
        (
          _warehouses > 0 && _suppliers > 0 && _facilities > 0 ? '' : 'warn',
          'اكتمال البيئة',
          'الموردون: ${nf(_suppliers)} • المستودعات: ${nf(_warehouses)} • '
              'المطابخ/الأفران: ${nf(_facilities)}',
        ),
      ];

  List<(String, String, String)> _insights() => [
        (
          _score >= 85 ? '' : 'warn',
          'الاستقرار العام',
          _score >= 85
              ? 'المنظومة مستقرة حاليًا ومناسبة للتشغيل بدرجة ثقة عالية.'
              : 'هناك عناصر كافية لتقليل الثقة، لكن الصورة ما زالت قابلة للسيطرة.',
        ),
        (
          _pressureTone,
          'ضغط المهام',
          _pressure >= 35
              ? 'الضغط عالٍ جدًا — إن تُرك هكذا سيؤثر على الجودة والقرار.'
              : (_pressure >= 18
                  ? 'هناك ضغط متوسط يحتاج توزيعًا ومراجعة يومية.'
                  : 'الضغط حاليًا منخفض ومُسيطَر عليه.'),
        ),
        (
          _criticalUnreviewed.isEmpty ? '' : 'err',
          'الحوكمة الحرجة',
          _criticalUnreviewed.isEmpty
              ? 'الطبقة الحرجة مغلقة جيدًا وهذا ممتاز.'
              : 'يجب إغلاق العناصر الحرجة أولًا قبل أي توسّع إضافي في الاستخدام.',
        ),
        (
          _pendingOrders + _pendingTransfers > 8 ? 'warn' : '',
          'اختناقات القرار',
          _pendingOrders + _pendingTransfers > 8
              ? 'هناك قرارات تشغيلية متأخرة — تحتاج مدة استجابة يومية أو مسؤولًا واضحًا.'
              : 'مستوى التأخير في القرارات التشغيلية مقبول.',
        ),
        (
          _pendingUsers + _inactiveUsers > 3 ? 'warn' : '',
          'الوصول والصلاحيات',
          _pendingUsers + _inactiveUsers > 3
              ? 'هناك حِمل إداري في إدارة الوصول — راقب الحسابات المتراكمة.'
              : 'الوصول تحت السيطرة حاليًا.',
        ),
      ];
}
