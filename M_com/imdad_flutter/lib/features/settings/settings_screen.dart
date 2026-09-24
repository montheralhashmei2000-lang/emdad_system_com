import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/esign.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_charts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/migration/data_export.dart';
import '../../data/migration/excel_import.dart';
import '../../data/migration/web_import.dart';
import '../../data/repos/catalog_repo.dart';
import '../inventory/doc_kit.dart' show ImdReadonlyField;
import '../../data/repos/selfcheck_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/movements_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/rules_engine.dart';
import '../home/home_shell.dart';

/// إصدار التطبيق كما يظهر في «عن النظام».
const kAppVersionLabel = 'نظام الإمداد والتموين — الإصدار ٧.٤.٠';

/// الإعدادات — نقل `renderSettings()` و`imdSettingsShell()`:
/// قائمة أقسام جانبية (نظرة عامة، الجهة، المستخدمون، المخزون، الطباعة،
/// المزامنة، النسخ الاحتياطي، الصيانة، عن النظام) مع بحث داخل الإعدادات.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// قسم في القائمة الجانبية (`SETTINGS_SECTIONS`).
class _Section {
  const _Section(this.id, this.icon, this.name, this.desc);
  final String id;
  final String icon;
  final String name;
  final String desc;
}

const _sections = <_Section>[
  _Section('general', 'home', 'نظرة عامة', 'الجاهزية والجلسة الحالية ومؤشرات البيانات'),
  _Section('company', 'building', 'بيانات الجهة والمظهر', 'الشعار واسم الجهة والسمة ورأس النماذج'),
  _Section('users', 'users', 'المستخدمون والصلاحيات', 'الحسابات المحلية والأدوار والصلاحيات'),
  _Section('inventory', 'package', 'المخزون والاستحقاقات',
      'الأرصدة الافتتاحية ومعدلات الاستحقاق والقوانين'),
  _Section('print', 'printer', 'الطباعة والتصدير والاستيراد', 'النماذج المطبوعة وأدوات كل شاشة'),
  _Section('sync', 'swap', 'المزامنة والتوقيع', 'ربط الأجهزة وملفات المزامنة والتوقيع الإلكتروني'),
  _Section('devices', 'monitor', 'تفعيل الأجهزة',
      'رمز تفعيل كل جهاز ومفتاح الإصدار — لا يعمل جهاز بلا رمز'),
  _Section('backup', 'database', 'النسخ الاحتياطي', 'تصدير البيانات واستعادتها'),
  _Section('health', 'shield', 'الصيانة والفحص', 'فحص سلامة النظام والوصول السريع للشاشات'),
  _Section('about', 'info', 'عن النظام', 'الإصدار ووضع التشغيل'),
];

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final Perm _perm = Perm.of(context);

  final _search = TextEditingController();
  String _section = 'general';
  bool _loading = true;

  int _items = 0;
  int _units = 0;
  int _suppliers = 0;
  int _warehouses = 0;
  int _facilities = 0;
  int _receipts = 0;
  int _issues = 0;
  int _users = 0;

  /// نتائج آخر فحص سلامة (فارغة قبل التشغيل).
  List<SelfCheckResult>? _checks;
  bool _checking = false;
  bool _includeUsersInBackup = true;
  String _note = '';

  /// محرك القوانين (`IMDAD_RULES`): نص القواعد ونتيجة آخر حفظ أو تشغيل.
  final _rules = TextEditingController();
  String _rulesNote = '';

  /// التوقيع الإلكتروني (`IMDAD_ESIGN`) والإشعارات المحلية.
  bool _hasSignKey = false;
  String _signAt = '';
  String _signKeyId = '';
  bool _pushEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = CatalogRepo(_db);
    final items = await catalog.items();
    final units = await catalog.units();
    final suppliers = await catalog.suppliers();
    final warehouses = await catalog.warehouses();
    final facilities = await catalog.facilities();
    final receipts = (await _db.select(_db.receipts).get()).map((r) => r.refNo).toSet().length;
    final issues = (await _db.select(_db.issues).get()).map((r) => r.refNo).toSet().length;
    final users = _perm.admin ? (await _db.select(_db.users).get()).length : 0;
    final rules = await SettingsRepo(_db).read('rules');
    final esign = ESign(_db);
    final hasKey = await esign.hasKey();
    final signAt = await esign.createdAt();
    final prefs = await SettingsRepo(_db).read('prefs');
    if (!mounted) return;
    imdSetText(_rules, '${rules['text'] ?? ''}');
    _hasSignKey = hasKey;
    _signAt = signAt;
    _signKeyId = await esign.keyId();
    _pushEnabled = prefs['push'] == true;
    setState(() {
      _items = items.length;
      _units = units.length;
      _suppliers = suppliers.length;
      _warehouses = warehouses.length;
      _facilities = facilities.length;
      _receipts = receipts;
      _issues = issues;
      _users = users;
      _loading = false;
    });
  }

  bool get _readyBasic => _items > 0 && _units > 0;
  bool get _readyInbound => _suppliers > 0 && _warehouses > 0;
  bool get _readyKitchen => _facilities > 0;
  bool get _readyUsers => _perm.admin ? _users > 0 : true;

  int get _score {
    final flags = [_readyBasic, _readyInbound, _readyKitchen, _readyUsers];
    return (flags.where((x) => x).length / flags.length * 100).round();
  }

  bool get _editable => _perm.admin || _perm.has('settings', PermAction.edit);

  void _go(String page) => context.read<ImdNav>().go(page);
  void _toast(String m, {bool error = false}) => showImdToast(context, m, error: error);

  // ───────── النسخ الاحتياطي ─────────
  /// `IMDAD_BACKUP.exportToFile()`
  /// نافذة كلمة مرور النسخة الاحتياطية. تعيد `null` عند الإلغاء، وسلسلة فارغة
  /// إن اختار المستخدم صراحةً نسخة بلا تشفير.
  Future<String?> _askBackupPassword({required bool creating}) async {
    final pass = TextEditingController();
    final confirm = TextEditingController();
    var plain = false;
    final result = await showImdModal<String>(
      context,
      title: creating ? 'كلمة مرور النسخة الاحتياطية' : 'النسخة مشفّرة',
      icon: 'lock',
      maxWidth: 480,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ImdNote(creating
                ? '⚠ نسيان كلمة المرور يعني ضياع هذه النسخة نهائيًا — لا استعادة '
                    'ولا باب خلفي. احفظها في مكان آمن منفصل عن الملف.'
                : 'أدخل كلمة مرور النسخة لفكّ تشفيرها.'),
            const SizedBox(height: 12),
            ImdLabeled('كلمة المرور', ImdFld(controller: pass, obscure: true)),
            if (creating) ...[
              const SizedBox(height: 10),
              ImdLabeled('تأكيد كلمة المرور', ImdFld(controller: confirm, obscure: true)),
              const SizedBox(height: 10),
              ImdCheckbox(
                value: plain,
                label: 'تصدير بلا تشفير (ملف مقروء بالكامل لمن يفتحه)',
                onChanged: (v) => setInner(() => plain = v),
              ),
            ],
          ],
        ),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
        ImdButton(
          label: creating ? 'تصدير' : 'استعادة',
          icon: 'check',
          onPressed: () {
            if (creating && plain) return Navigator.of(ctx).pop('');
            if (pass.text.isEmpty) {
              showImdToast(ctx, '✖ أدخل كلمة المرور', error: true);
              return;
            }
            if (creating && pass.text != confirm.text) {
              showImdToast(ctx, '✖ كلمتا المرور غير متطابقتين', error: true);
              return;
            }
            Navigator.of(ctx).pop(pass.text);
          },
        ),
      ],
    );
    pass.dispose();
    confirm.dispose();
    return result;
  }

  Future<void> _exportBackup() async {
    final password = await _askBackupPassword(creating: true);
    if (password == null || !mounted) return;
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    // الامتداد يميّز المشفَّر عن المقروء فلا يلتبسان على المستخدم.
    final ext = password.isEmpty ? 'json' : 'imdbk';
    final path = '$dir${Platform.pathSeparator}imdad-backup-$stamp.$ext';
    final result = await DataExporter(_db)
        .writeToFile(path, includeUsers: _includeUsersInBackup, password: password);
    if (!mounted) return;
    setState(() => _note = 'حُفظت النسخة في ${result.path} (${nf(result.records)} سجلًا)'
        '${result.encrypted ? ' — مشفّرة' : ' — غير مشفّرة'}');
    _toast(result.encrypted
        ? '✔ تم تصدير نسخة مشفّرة — احفظها وكلمة مرورها منفصلتين'
        : '⚠ تم تصدير نسخة غير مشفّرة — احمِ الملف بنفسك');
  }

  /// `IMDAD_BACKUP.restore()` — الاستيراد يدمج فوق الموجود.
  Future<void> _restoreBackup() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['json', 'imdbk']);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    // الملف المشفَّر يُعرف من بادئته لا من امتداده، فلا يخدع الاسم.
    var password = '';
    if (await WebImporter.isEncryptedFile(File(path))) {
      if (!mounted) return;
      final entered = await _askBackupPassword(creating: false);
      if (entered == null || entered.isEmpty || !mounted) return;
      password = entered;
    }
    if (!mounted) return;
    final ok = await imdConfirm(
      context,
      'ستُضاف بيانات النسخة فوق البيانات الحالية على هذا الجهاز (دمج). '
      'يُنصح بأخذ نسخة احتياطية قبل المتابعة.',
      ok: 'استعادة',
      danger: true,
    );
    if (!ok) return;
    try {
      final result = await WebImporter(_db).importFile(File(path), password: password);
      if (!mounted) return;
      setState(() => _note = result.toString());
      _toast('✔ اكتملت الاستعادة: ${nf(result.total)} سجل');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'تعذّرت الاستعادة: $e');
      _toast('✖ فشلت الاستعادة', error: true);
    }
  }

  Future<void> _importExcel() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _note = 'جارٍ قراءة الملف…');
    try {
      final result = await ExcelImporter(_db).importFile(
        File(path),
        onProgress: (sheet, done, total) {
          if (mounted) setState(() => _note = 'ورقة «$sheet»: ${nf(done)} من ${nf(total)}');
        },
      );
      if (!mounted) return;
      setState(() => _note = [result.toString(), ...result.warnings.take(5)].join('\n'));
      _toast('✔ اكتمل الاستيراد: ${nf(result.total)} صف');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'تعذّر استيراد الملف: $e');
    }
  }

  Future<void> _excelTemplate() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final path = '$dir${Platform.pathSeparator}imdad-template.xlsx';
    await File(path).writeAsBytes(ExcelImporter.template(), flush: true);
    if (!mounted) return;
    setState(() => _note = 'حُفظ القالب في $path');
    _toast('✔ حُفظ القالب');
  }

  /// `IMDAD_RULES.save('main', text)`
  Future<void> _saveRules() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    final parsed = RulesEngine().parse(_rules.text);
    await SettingsRepo(_db).write('rules', {'text': _rules.text});
    if (!mounted) return;
    setState(() => _rulesNote = 'حُفظت ${nf(parsed.length)} قاعدة صالحة');
    _toast('✔ حُفظت القوانين');
  }

  /// `IMDAD_RULES.run(text, ctx)` — يشغّل القواعد على الأرصدة الحالية.
  Future<void> _runRules() async {
    final balances = await MovementsRepo(_db).balances(scope: _perm.scope);
    final res = RulesEngine().run(_rules.text, {'stockMap': balances, 'daysLeft': 30});
    if (!mounted) return;
    setState(() => _rulesNote = res.fired.isEmpty
        ? 'لم تتحقق أي قاعدة على الأرصدة الحالية'
        : 'تفعّلت ${nf(res.fired.length)} قاعدة'
            '${res.notifications.isEmpty ? '' : ' — ${res.notifications.join(' • ')}'}'
            '${res.blocked ? ' — يوجد إجراء منع (block)' : ''}');
  }

  /// `IMDAD_ESIGN.ensureKey('commander')`
  Future<void> _ensureSignKey() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    await ESign(_db).ensureKey();
    await _load();
    if (mounted) _toast('✔ جُهِّز مفتاح القائد على هذا الجهاز');
  }

  Future<void> _removeSignKey() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    final ok = await imdConfirm(
      context,
      'حذف مفتاح التوقيع يُبطل التحقق من كل الأختام السابقة على هذا الجهاز. متابعة؟',
      ok: 'حذف المفتاح',
      danger: true,
    );
    if (!ok) return;
    await ESign(_db).removeKey();
    await _load();
    if (mounted) _toast('✔ حُذف مفتاح التوقيع');
  }

  Future<void> _setPush(bool v) async {
    final settings = SettingsRepo(_db);
    final prefs = await settings.read('prefs');
    prefs['push'] = v;
    await settings.write('prefs', prefs);
    if (mounted) setState(() => _pushEnabled = v);
  }

  /// `IMDAD_SELFCHECK.runAll()`
  Future<void> _runChecks() async {
    setState(() => _checking = true);
    final res = await SelfCheckRepo(_db, appVersion: kAppVersionLabel).runAll();
    if (!mounted) return;
    setState(() {
      _checks = res;
      _checking = false;
    });
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(
          title: 'الإعدادات',
          icon: 'settings',
          subtitle: 'جارٍ تجهيز حالة النظام والإعدادات التشغيلية…',
        ),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }

    final q = _search.text.trim();
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final panels = _panels();
    final visible = q.isEmpty
        ? panels.where((p) => p.$1 == _section).toList()
        : panels.where((p) => p.$2.contains(q)).toList();
    final current = _sections.firstWhere((s) => s.id == _section, orElse: () => _sections.first);

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'الإعدادات',
        icon: 'settings',
        subtitle: 'إعدادات النظام مصنّفة حسب الأقسام — اختر القسم من القائمة أو ابحث عن الإعداد',
      ),
      if (narrow) ...[
        _nav(horizontal: true),
        const SizedBox(height: 12),
        _body(q, current, visible),
      ] else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 280, child: _nav(horizontal: false)),
          const SizedBox(width: 16),
          Expanded(child: _body(q, current, visible)),
        ]),
    ]);
  }

  Widget _body(String q, _Section current, List<(String, String, Widget)> visible) {
    final c = context.imd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ImdIcon(q.isEmpty ? current.icon : 'search', size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text(q.isEmpty ? current.name : 'نتائج البحث: $q',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
          ]),
          const SizedBox(height: 2),
          Text(
            q.isEmpty
                ? current.desc
                : (visible.isEmpty ? 'لا توجد نتائج' : '${nf(visible.length)} لوحة مطابقة'),
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
        ]),
      ),
      for (final p in visible) p.$3,
      if (_note.isNotEmpty)
        ImdNote(_note, margin: const EdgeInsets.only(bottom: 12)),
    ]);
  }

  /// `.set-nav`
  Widget _nav({required bool horizontal}) {
    final c = context.imd;
    final buttons = [for (final s in _sections) _navButton(s, horizontal: horizontal)];
    return Container(
      padding: EdgeInsets.all(horizontal ? 6 : 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ImdFld(
            controller: _search,
            hint: 'بحث في الإعدادات…',
            dense: true,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (horizontal)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final b in buttons) Padding(padding: const EdgeInsets.only(left: 4), child: b),
            ]),
          )
        else
          ...buttons,
      ]),
    );
  }

  Widget _navButton(_Section s, {required bool horizontal}) {
    final c = context.imd;
    final on = s.id == _section && _search.text.trim().isEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _section = s.id;
          _search.clear();
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: on ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ImdIcon(s.icon, size: 16, color: c.accent),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: horizontal ? 190 : 200),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.name,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? c.accentHover : c.text)),
                if (!horizontal)
                  Text(s.desc, style: TextStyle(fontSize: 11.5, color: c.muted, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// كل لوحة: (القسم، نصها للبحث، الودجة).
  List<(String, String, Widget)> _panels() {
    final c = context.imd;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final name = user == null ? '—' : (user.name.isNotEmpty ? user.name : user.email);
    final role = user?.role == 'admin' ? 'مدير النظام' : 'مستخدم';

    return [
      (
        'general',
        'درجة الجاهزية الحالية',
        ImdPanel(
          centerVertically: true,
          child: Wrap(spacing: 18, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ImdScoreRing(percent: _score),
            SizedBox(
              width: 260,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('درجة الجاهزية الحالية',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdChip('جاهزية جيدة', tone: _score >= 75 ? ImdTone.ok : ImdTone.pend),
                  ImdChip('يمكن التشغيل المرحلي', tone: _score >= 50 ? ImdTone.ok : ImdTone.pend),
                  ImdChip('ما زال هناك تحسين مطلوب',
                      tone: _score < 100 ? ImdTone.pend : ImdTone.ok),
                ]),
                const SizedBox(height: 8),
                Text(
                  'كلما اقتربت من ١٠٠٪ قلّ الاعتماد على الحلول اليدوية وزاد استقرار '
                  'التشغيل اليومي داخل النظام.',
                  style: TextStyle(fontSize: 13, height: 2, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
      ),
      (
        'general',
        'الجلسة الحالية المستخدم الدور',
        ImdPanel(
          title: 'الجلسة الحالية',
          icon: 'user',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ImdGrid(columns: 2, minItemWidth: 140, children: [
              ImdKpi(label: 'المستخدم', value: name),
              ImdKpi(label: 'الدور', value: role, color: c.accent),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton.outline(
                label: 'تحديث الشاشة',
                icon: 'refresh',
                small: true,
                onPressed: () async {
                  await _load();
                  if (mounted) _toast('✔ حُدِّثت بيانات الشاشة');
                },
              ),
            ]),
          ]),
        ),
      ),
      (
        'general',
        'مؤشرات البيانات الأساسية الأصناف الوحدات الموردون المستودعات',
        ImdICard(
          title: 'مؤشرات البيانات الأساسية',
          icon: 'package',
          child: ImdKpis(children: [
            ImdKpi(label: 'الأصناف', value: nf(_items)),
            ImdKpi(label: 'الوحدات', value: nf(_units), color: c.accent),
            ImdKpi(label: 'الموردون', value: nf(_suppliers)),
            ImdKpi(label: 'المستودعات', value: nf(_warehouses), color: c.accent),
            ImdKpi(label: 'الواردات', value: nf(_receipts)),
            ImdKpi(label: 'الصرف', value: nf(_issues), color: c.accent),
            ImdKpi(label: 'المطابخ / الأفران', value: nf(_facilities)),
            if (_perm.admin) ImdKpi(label: 'المستخدمون', value: nf(_users), color: c.accent),
          ]),
        ),
      ),
      (
        'general',
        'حالة الجاهزية الأساسيات التوريد التشغيل الوضع الأمني',
        ImdPanel(
          title: 'حالة الجاهزية',
          icon: 'check-circle',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdChip('البيانات الأساسية', tone: _readyBasic ? ImdTone.ok : ImdTone.pend),
              ImdChip('الاستلام والتوريد', tone: _readyInbound ? ImdTone.ok : ImdTone.pend),
              ImdChip('المطابخ والتشغيل', tone: _readyKitchen ? ImdTone.ok : ImdTone.pend),
              ImdChip('المستخدمون', tone: _readyUsers ? ImdTone.ok : ImdTone.pend),
            ]),
            const SizedBox(height: 12),
            ImdStatusList(items: [
              (
                _readyBasic ? '' : 'warn',
                'الأساسيات',
                _readyBasic
                    ? 'الأصناف والوحدات جاهزة للعمل.'
                    : 'ابدأ بإدخال الأصناف والوحدات قبل الاعتماد على العمليات اليومية.',
              ),
              (
                _readyInbound ? '' : 'warn',
                'التوريد والاستلام',
                _readyInbound
                    ? 'الموردون والمستودعات جاهزون للواردات والتحويلات.'
                    : 'أضف الموردين والمستودعات لتشغيل دورة الاستلام بشكل صحيح.',
              ),
              (
                _readyKitchen ? '' : 'warn',
                'التشغيل اليومي',
                _readyKitchen
                    ? 'المطابخ/الأفران موجودة ويمكن تشغيل السجل اليومي.'
                    : 'سجّل المطابخ أو الأفران إذا كان التشغيل اليومي جزءًا من الدورة الفعلية.',
              ),
              (
                '',
                'الوضع الأمني',
                'قنوات التهيئة والانضمام والتفعيل والفتح دون اتصال كلها مقفلة حاليًا، '
                    'وهو المناسب لمرحلة التشغيل الآمن.',
              ),
            ]),
          ]),
        ),
      ),
      (
        'company',
        'بيانات الجهة والهوية الشعار رأس النماذج',
        ImdPanel(
          title: 'بيانات الجهة والهوية',
          icon: 'building',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('اسم الجهة والشعار يظهران في رأس الشاشات وفي كل النماذج المطبوعة.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton(
                label: 'الهوية والشعار',
                icon: 'image',
                small: true,
                onPressed: () => _go('branding'),
              ),
              ImdButton.outline(
                label: 'رأس وتذييل النماذج',
                icon: 'tag',
                small: true,
                onPressed: () => _go('formsDesigner'),
              ),
            ]),
          ]),
        ),
      ),
      (
        'users',
        'المستخدمون والأدوار مصفوفة الصلاحيات',
        ImdPanel(
          title: 'المستخدمون والأدوار',
          icon: 'users',
          child: _perm.admin
              ? Wrap(spacing: 8, runSpacing: 8, children: [
                  ImdButton(
                    label: 'إدارة المستخدمين',
                    icon: 'users',
                    small: true,
                    onPressed: () => _go('usersAccess'),
                  ),
                  ImdButton.outline(
                    label: 'مصفوفة الصلاحيات',
                    icon: 'lock',
                    small: true,
                    onPressed: () => _go('usersAccess'),
                  ),
                ])
              : const ImdChip('إدارة المستخدمين متاحة للمدير فقط', tone: ImdTone.pend),
        ),
      ),
      (
        'inventory',
        'إعدادات المخزون الأرصدة الافتتاحية نسب الاستهلاك المستودعات',
        ImdPanel(
          title: 'إعدادات المخزون',
          icon: 'package',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ImdButton.outline(
              label: 'الأرصدة الافتتاحية',
              icon: 'clipboard',
              small: true,
              onPressed: () => _go('opening'),
            ),
            ImdButton.outline(
              label: 'المستودعات وربطها بالمعسكرات',
              icon: 'warehouse',
              small: true,
              onPressed: () => _go('stores'),
            ),
            ImdButton.outline(
              label: 'نسب الاستهلاك',
              icon: 'scale',
              small: true,
              onPressed: () => _go('ratios'),
            ),
          ]),
        ),
      ),
      (
        'inventory',
        'محرك القوانين القواعد تنبيه منع',
        ImdPanel(
          title: 'محرك القوانين',
          icon: 'bulb',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('قاعدة في كل سطر بالصيغة: '
                'IF stock(معرّف الصنف) < 50 THEN notify(نص التنبيه) — '
                'المصادر: stock و daysLeft، ويمكن ربط شرطين بـ AND، والإجراء notify أو block.'),
            const SizedBox(height: 10),
            ImdFld(controller: _rules, maxLines: 6, enabled: _editable, hint: 'IF stock(itm-1) < 50 THEN notify(الرصيد منخفض)'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton(
                label: 'حفظ القوانين',
                icon: 'save',
                small: true,
                onPressed: _editable ? _saveRules : null,
              ),
              ImdButton.outline(label: 'تشغيل الآن', icon: 'zap', small: true, onPressed: _runRules),
            ]),
            if (_rulesNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_rulesNote, style: TextStyle(fontSize: 12.5, color: c.muted)),
              ),
          ]),
        ),
      ),
      (
        'print',
        'النماذج المطبوعة مصمم النماذج مقاس الورق التوقيع',
        ImdPanel(
          title: 'النماذج المطبوعة',
          icon: 'printer',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('مقاس الورق والاتجاه والرأس والتذييل وخانات التوقيع لسندات الاستلام '
                'والصرف والتحويل والمرتجعات والتقارير.'),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(
                label: 'فتح مصمم النماذج',
                icon: 'printer',
                small: true,
                onPressed: () => _go('formsDesigner'),
              ),
            ),
          ]),
        ),
      ),
      (
        'print',
        'الاستيراد من إكسل قالب إكسل ترحيل بيانات النسخة السابقة',
        ImdPanel(
          title: 'الاستيراد والترحيل',
          icon: 'upload',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('استورد الأصناف والموردين والمستودعات والأرصدة من ملف Excel، '
                'أو رحّل بيانات نسخة الويب من ملف JSON.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton.outline(
                label: 'استيراد من Excel',
                icon: 'upload',
                small: true,
                onPressed: _editable ? _importExcel : null,
              ),
              ImdButton.outline(
                label: 'قالب Excel',
                icon: 'download',
                small: true,
                onPressed: _excelTemplate,
              ),
              ImdButton.outline(
                label: 'ترحيل ملف JSON من الويب',
                icon: 'swap',
                small: true,
                onPressed: _editable ? _restoreBackup : null,
              ),
            ]),
          ]),
        ),
      ),
      (
        'sync',
        'المزامنة بين الأجهزة الشبكة المحلية التوقيع الإلكتروني',
        ImdPanel(
          title: 'المزامنة بين الأجهزة',
          icon: 'swap',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('مزامنة البيانات بين أجهزة الشبكة المحلية دون إنترنت — '
                'جهاز يعمل مضيفًا والبقية تتصل به.'),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(
                label: 'فتح شاشة المزامنة',
                icon: 'swap',
                small: true,
                onPressed: () => _go('lanSync'),
              ),
            ),
          ]),
        ),
      ),
      (
        'sync',
        'التوقيع الإلكتروني مفتاح القائد ختم المستندات',
        ImdPanel(
          title: 'التوقيع الإلكتروني',
          icon: 'edit',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('زوج مفاتيح على هذا الجهاز (ECDSA P-256): الخاص يوقّع ولا '
                'يغادر الجهاز، والعام يتحقق به الآخرون. كل سند مطبوع يحمل رمز تحقق '
                'أسفله يكشف أي تعديل يطرأ عليه بعد الاعتماد.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ImdChip(
                _hasSignKey
                    ? 'مفتاح القائد جاهز${_signAt.isEmpty ? '' : ' — $_signAt'}'
                    : 'لم يُنشأ المفتاح بعد',
                tone: _hasSignKey ? ImdTone.ok : ImdTone.pend,
              ),
              ImdButton(
                label: 'تهيئة مفتاح القائد',
                icon: 'lock',
                small: true,
                onPressed: _hasSignKey || !_editable ? null : _ensureSignKey,
              ),
              if (_hasSignKey)
                ImdButton(
                  label: 'حذف المفتاح',
                  icon: 'trash',
                  small: true,
                  kind: ImdBtnKind.danger,
                  onPressed: _editable ? _removeSignKey : null,
                ),
              ImdButton.outline(
                label: 'التحقق من توقيع مستند',
                icon: 'shield',
                small: true,
                onPressed: () => _go('verifySign'),
              ),
              ImdButton.outline(
                label: 'تفعيل الأجهزة',
                icon: 'monitor',
                small: true,
                onPressed: () => _go('deviceActivation'),
              ),
            ]),
            if (_hasSignKey && _signKeyId.isNotEmpty) ...[
              const SizedBox(height: 10),
              // معرّف المفتاح يُطبع مع كل توقيع، ومنه يعرف المتحقِّق أيّ مفتاح يستعمل.
              ImdLabeled('معرّف المفتاح', ImdReadonlyField(text: _signKeyId)),
            ],
          ]),
        ),
      ),
      (
        'devices',
        'تفعيل الأجهزة رمز التفعيل مفتاح الإصدار معرّف الجهاز الفروع',
        ImdPanel(
          title: 'تفعيل الأجهزة',
          icon: 'monitor',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('لا يعمل أي جهاز في النظام إلا برمز تفعيل موقَّع منك. '
                'من هنا تستورد مفتاح الإصدار، وتُصدر رموز أجهزة الفروع، وترى حالة '
                'هذا الجهاز ومعرّفه.'),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton(
                label: 'فتح شاشة تفعيل الأجهزة',
                icon: 'monitor',
                onPressed: () => _go('deviceActivation'),
              ),
            ),
          ]),
        ),
      ),
      (
        'sync',
        'الإشعارات تنبيه محلي تجاوز الاستحقاق',
        ImdPanel(
          title: 'الإشعارات',
          icon: 'bell',
          child: ImdCheckbox(
            value: _pushEnabled,
            label: 'تنبيه محلي عند تجاوز الاستحقاق أو نفاد صنف',
            onChanged: _setPush,
          ),
        ),
      ),
      (
        'backup',
        'النسخ الاحتياطي والاستعادة تصدير نسخة كاملة',
        ImdPanel(
          title: 'النسخ الاحتياطي والاستعادة',
          icon: 'database',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('⚠️ مهم: كل بيانات النظام محفوظة على هذا الجهاز فقط. في حال تعطّل '
                'الجهاز أو مسح بيانات التطبيق ستفقد كل شيء نهائيًا ما لم تكن قد أخذت نسخة '
                'احتياطية. يُنصح بأخذ نسخة دوريًا وحفظها خارج الجهاز.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdChip('السجلات: ${nf(_items + _units + _suppliers + _warehouses)}', tone: ImdTone.ok),
              ImdChip('سندات الوارد: ${nf(_receipts)}', tone: ImdTone.code),
              ImdChip('سندات الصرف: ${nf(_issues)}', tone: ImdTone.code),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton(
                label: 'تصدير نسخة احتياطية كاملة',
                icon: 'download',
                small: true,
                onPressed: _exportBackup,
              ),
              if (_perm.admin)
                ImdButton.outline(
                  label: 'استعادة من ملف نسخة',
                  icon: 'upload',
                  small: true,
                  onPressed: _restoreBackup,
                ),
            ]),
            const SizedBox(height: 10),
            ImdCheckbox(
              value: _includeUsersInBackup,
              label: 'تضمين حسابات المستخدمين وبصمات كلمات مرورهم في النسخة',
              onChanged: (v) => setState(() => _includeUsersInBackup = v),
            ),
          ]),
        ),
      ),
      (
        'health',
        'فحص سلامة النظام اتساق البيانات السجلات اليتيمة',
        ImdPanel(
          title: 'فحص سلامة النظام',
          icon: 'shield',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdNote('يتحقق من عمل نقاط التكامل الحرجة ومن اتساق البيانات '
                '(وحدات القياس، الروابط، السجلات اليتيمة). شغّله بعد أي تحديث أو '
                'إذا لاحظت سلوكًا غريبًا.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ImdButton(
                label: 'تشغيل الفحص الشامل',
                icon: 'zap',
                small: true,
                busy: _checking,
                onPressed: _checking ? null : _runChecks,
              ),
              ImdButton.outline(
                label: 'صحة النظام والعمليات',
                icon: 'shield',
                small: true,
                onPressed: () => _go('healthOps'),
              ),
            ]),
            if (_checks != null) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ImdChip(
                  _checks!.any((r) => !r.ok)
                      ? '⚠ ${nf(_checks!.where((r) => !r.ok).length)} نقطة تحتاج انتباه'
                      : '✔ كل الفحوصات سليمة',
                  tone: _checks!.any((r) => !r.ok) ? ImdTone.off : ImdTone.ok,
                ),
                ImdChip('إجمالي الفحوصات: ${nf(_checks!.length)}', tone: ImdTone.code),
              ]),
              const SizedBox(height: 10),
              ImdTable(
                columns: const [ImdCol('الفحص'), ImdCol('الحالة'), ImdCol('التفاصيل')],
                rows: [
                  for (final r in _checks!)
                    [
                      Text(r.label),
                      ImdChip(r.ok ? 'سليم' : 'يحتاج انتباه', tone: r.ok ? ImdTone.ok : ImdTone.off),
                      Text(r.note),
                    ],
                ],
              ),
            ],
          ]),
        ),
      ),
      (
        'about',
        'عن النظام الإصدار وضع التشغيل',
        ImdPanel(
          title: 'عن النظام',
          icon: 'info',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            const ImdChip(kAppVersionLabel, tone: ImdTone.ok),
            const ImdChip('وضع التشغيل: محلي بالكامل (بدون إنترنت)', tone: ImdTone.code),
            ImdChip(
              kIsWeb ? 'المنصة: متصفح' : 'المنصة: ${Platform.operatingSystem}',
              tone: ImdTone.off,
            ),
          ]),
        ),
      ),
    ];
  }
}
