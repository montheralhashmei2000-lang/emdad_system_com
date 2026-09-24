import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/users_repo.dart';
import '../../domain/access_control.dart';

/// مركز المستخدمين والصلاحيات — نقل `renderUsersAccess()`:
/// قائمة الحسابات مع الدور والحالة، وإنشاء حساب محلي جديد،
/// ومصفوفة صلاحيات دقيقة لكل شاشة (مشاهدة/إضافة/تعديل/حذف/اعتماد/طباعة/تصدير)،
/// وإدارة الوصول (اعتماد، تفعيل، إيقاف) والدور ونطاق المستودعات.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

/// `PERM_CATALOG` — الشاشة وأفعالها المتاحة.
const _permCatalog = <String, (String, List<String>)>{
  'dashboard': ('الرئيسية', ['view']),
  'items': ('الأصناف', ['view', 'create', 'edit', 'delete', 'print', 'export']),
  'suppliers': ('الموردون', ['view', 'create', 'edit', 'delete', 'export']),
  'units': ('الوحدات المستفيدة', ['view', 'create', 'edit', 'delete', 'print', 'export']),
  'stores': ('المستودعات', ['view', 'create', 'edit', 'delete', 'export']),
  'kitchens': ('المطابخ والأفران', ['view', 'create', 'edit', 'delete']),
  'receive': ('الاستلام', ['view', 'create', 'edit', 'delete', 'approve', 'print']),
  'issue': ('الصرف', ['view', 'create', 'edit', 'delete', 'approve', 'print']),
  'transfer': ('التحويل المخزني', ['view', 'create', 'edit', 'delete', 'approve', 'print']),
  'returns': ('المرتجعات', ['view', 'create', 'edit', 'delete', 'approve', 'print']),
  'pendingOrders': ('أوامر التوريد المعلقة', ['view', 'approve', 'delete', 'print']),
  'documents': ('سجل المستندات', ['view', 'print', 'edit', 'delete']),
  'feeding': ('التغذية / القوة', ['view', 'create', 'edit', 'delete', 'print', 'export']),
  'kitchenLog': ('سجل التشغيل والطهي', ['view', 'create', 'edit', 'delete', 'print', 'export']),
  'ratios': ('نسب الاستهلاك والاستحقاقات', ['view', 'edit', 'print', 'export']),
  'balances': ('الأرصدة الحالية', ['view', 'export', 'print']),
  'stocktake': ('الجرد', ['view', 'create', 'edit', 'delete', 'approve', 'print', 'export']),
  'reports': ('التقارير', ['view', 'export', 'print']),
  'auditTrail': ('سجل التدقيق', ['view', 'export', 'print']),
  'activityIntel': ('ذكاء النشاط', ['view', 'export']),
  'executiveCmd': ('القيادة التنفيذية', ['view', 'export', 'print']),
  'sensitiveOps': ('المراجعة الحساسة', ['view', 'approve']),
  'opening': ('الأرصدة الافتتاحية', ['view', 'create', 'edit', 'approve', 'print']),
  'settings': ('الإعدادات والهوية', ['view', 'edit']),
  'usersAccess': ('المستخدمون والصلاحيات', ['view', 'edit', 'approve']),
};

const _actionLabels = <String, String>{
  'view': 'مشاهدة',
  'create': 'إضافة',
  'edit': 'تعديل',
  'delete': 'حذف',
  'approve': 'اعتماد',
  'print': 'طباعة',
  'export': 'تصدير',
};

class _UsersScreenState extends State<UsersScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final UsersRepo _repo = UsersRepo(_db);
  late final AuthService _auth = context.read<AuthService>();
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();
  List<User> _users = const [];
  List<Warehouse> _warehouses = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// `uacLoad()`
  Future<void> _load() async {
    final users = await _repo.users();
    final whs = await CatalogRepo(_db).warehouses();
    if (!mounted) return;
    setState(() {
      _users = users;
      _warehouses = whs;
      _loading = false;
    });
  }

  List<User> _rows() {
    final q = _q.text.trim().toLowerCase();
    return _users
        .where((u) =>
            q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q))
        .toList();
  }

  /// `uacStatus(u)` — PENDING | INACTIVE | ACTIVE
  static String _status(User u) =>
      !u.approved ? 'PENDING' : (!u.active ? 'INACTIVE' : 'ACTIVE');

  static (String, ImdTone) _statusChip(User u) => switch (_status(u)) {
        'PENDING' => ('بانتظار الاعتماد', ImdTone.pend),
        'INACTIVE' => ('موقوف', ImdTone.err),
        _ => ('نشط', ImdTone.ok),
      };

  bool _isMe(User u) => _auth.currentUser?.id == u.id;

  Future<void> _toggleAccess(User u) async {
    if (!_perm.guard(context, 'usersAccess', PermAction.approve)) return;
    final st = _status(u);
    final enable = st != 'ACTIVE';
    final ok = await imdConfirm(
      context,
      enable
          ? 'تفعيل حساب «${u.username}» ومنحه الدخول إلى النظام؟'
          : 'إيقاف حساب «${u.username}» ومنعه من الدخول؟',
      ok: enable ? 'تفعيل' : 'إيقاف',
      danger: !enable,
    );
    if (!ok) return;
    await _repo.updateUser(id: u.id, active: enable, actorEmail: _perm.email);
    if (!u.approved) {
      await (_db.update(_db.users)..where((t) => t.id.equals(u.id)))
          .write(const UsersCompanion(approved: Value(true)));
    }
    await AuditRepo(_db).write(
      enable ? (st == 'PENDING' ? 'USER_APPROVED' : 'USER_REACTIVATED') : 'USER_DISABLED',
      'user_access',
      enable ? 'اعتماد وتفعيل مستخدم' : 'إيقاف مستخدم',
      actorEmail: _perm.email,
      details: {'target': u.username, 'risk': 'sensitive'},
    );
    if (!mounted) return;
    showImdToast(context, enable ? '✔ فُعِّل الحساب' : '✔ أُوقف الحساب');
    await _load();
  }

  Future<void> _toggleRole(User u) async {
    if (!_perm.guard(context, 'usersAccess', PermAction.edit)) return;
    final toAdmin = u.role != 'admin';
    final ok = await imdConfirm(
      context,
      toAdmin
          ? 'منح «${u.username}» صلاحيات مدير النظام الكاملة؟'
          : 'إرجاع «${u.username}» إلى مستخدم عادي؟',
      ok: toAdmin ? 'منح' : 'إرجاع',
      danger: toAdmin,
    );
    if (!ok) return;
    await _repo.updateUser(id: u.id, isAdmin: toAdmin, actorEmail: _perm.email);
    await AuditRepo(_db).write(
      'USER_ROLE_CHANGED',
      'user_access',
      'تغيير دور مستخدم',
      actorEmail: _perm.email,
      details: {'target': u.username, 'status': toAdmin ? 'admin' : 'user', 'risk': 'critical'},
    );
    if (!mounted) return;
    showImdToast(context, '✔ تم تغيير الدور');
    await _load();
  }

  /// `openAddLocalUser()`
  Future<void> _addUser() async {
    if (!_perm.guard(context, 'usersAccess', PermAction.edit)) return;
    final username = TextEditingController();
    final name = TextEditingController();
    final password = TextEditingController();
    var isAdmin = false;

    final saved = await showImdModal<bool>(
      context,
      title: 'مستخدم جديد',
      icon: 'user',
      maxWidth: 480,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdLabeled('الاسم الكامل', ImdFld(controller: name)),
          const SizedBox(height: 10),
          ImdLabeled(
            'اسم المستخدم لتسجيل الدخول',
            ImdFld(controller: username, hint: 'مثال: ahmed.ali'),
          ),
          const SizedBox(height: 10),
          ImdLabeled('كلمة المرور المبدئية', ImdFld(controller: password, hint: '٨ أحرف فأكثر')),
          const SizedBox(height: 10),
          ImdCheckbox(
            value: isAdmin,
            label: 'منحه صلاحيات مدير النظام الكاملة',
            onChanged: (v) => setLocal(() => isAdmin = v),
          ),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'إنشاء الحساب', icon: 'save', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );

    if (saved == true) {
      try {
        await _repo.createUser(
          username: username.text,
          password: password.text,
          name: name.text,
          isAdmin: isAdmin,
          actorEmail: _perm.email,
        );
        if (!mounted) return;
        showImdToast(context, '✔ أُنشئ الحساب — يمكنه الدخول باسم «${username.text.trim()}»');
        await _load();
      } catch (e) {
        if (mounted) {
          showImdToast(context, '✖ ${e is ArgumentError ? e.message : e}', error: true);
        }
      }
    }
    for (final c in [username, name, password]) {
      c.dispose();
    }
  }

  /// `openUserPermissions(id)` — مصفوفة الصلاحيات لكل شاشة.
  Future<void> _openPermissions(User u) async {
    if (_isMe(u)) {
      showImdToast(context, '✖ لا يمكن تعديل صلاحيات حسابك الحالي من نفس الجلسة', error: true);
      return;
    }
    final perms = <String, Map<String, bool>>{};
    _auth.permissionsOf(u).forEach((page, actions) {
      if (actions is Map) {
        perms[page] = {for (final e in actions.entries) '${e.key}': e.value == true};
      }
    });
    final scope = <String>{...(UsersRepo.scopeOf(u) ?? const [])};
    var allWarehouses = UsersRepo.scopeOf(u) == null;

    final saved = await showImdModal<bool>(
      context,
      title: 'صلاحيات: ${u.name.isNotEmpty ? u.name : u.username}',
      icon: 'lock',
      maxWidth: 1100,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ImdNote('مدير النظام يملك جميع الصلاحيات تلقائيًا. '
              'للمستخدم العادي يمكنك تحديد كل عملية بشكل مستقل.'),
          const SizedBox(height: 12),
          // نطاق المستودعات: كل المستودعات أو قائمة محددة.
          ImdICard(
            title: 'نطاق المستودعات',
            icon: 'warehouse',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ImdCheckbox(
                value: allWarehouses,
                label: 'كل المستودعات',
                onChanged: (v) => setLocal(() => allWarehouses = v),
              ),
              if (!allWarehouses)
                Wrap(spacing: 12, runSpacing: 8, children: [
                  for (final w in _warehouses)
                    SizedBox(
                      width: 220,
                      child: ImdCheckbox(
                        value: scope.contains(w.name),
                        label: w.name,
                        onChanged: (v) => setLocal(() {
                          if (v) {
                            scope.add(w.name);
                          } else {
                            scope.remove(w.name);
                          }
                        }),
                      ),
                    ),
                ]),
            ]),
          ),
          ImdGrid(columns: 3, minItemWidth: 240, children: [
            for (final e in _permCatalog.entries)
              _permCard(
                page: e.key,
                label: e.value.$1,
                actions: e.value.$2,
                perms: perms,
                onChanged: () => setLocal(() {}),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ImdButton.outline(
              label: 'تحديد الكل',
              icon: 'check',
              small: true,
              onPressed: () => setLocal(() {
                for (final e in _permCatalog.entries) {
                  perms[e.key] = {for (final a in e.value.$2) a: true};
                }
              }),
            ),
            ImdButton.outline(
              label: 'إلغاء الكل',
              icon: 'x',
              small: true,
              onPressed: () => setLocal(perms.clear),
            ),
          ]),
        ]),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop(false)),
        ImdButton(label: 'حفظ الصلاحيات', icon: 'save', onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );

    if (saved != true || !mounted) return;
    if (!_perm.guard(context, 'usersAccess', PermAction.edit)) return;
    await _repo.updateUser(
      id: u.id,
      permissions: perms,
      allWarehouses: allWarehouses,
      warehouseScope: allWarehouses ? null : scope.toList(),
      actorEmail: _perm.email,
    );
    await AuditRepo(_db).write(
      'USER_PERMISSIONS_CHANGED',
      'user_access',
      'تغيير صلاحيات مستخدم',
      actorEmail: _perm.email,
      details: {'target': u.username, 'risk': 'critical'},
    );
    if (!mounted) return;
    showImdToast(context, '✔ حُفظت الصلاحيات');
    await _load();
  }

  /// `.perm-card`
  Widget _permCard({
    required String page,
    required String label,
    required List<String> actions,
    required Map<String, Map<String, bool>> perms,
    required VoidCallback onChanged,
  }) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (final a in actions)
            ImdCheckbox(
              value: perms[page]?[a] == true,
              label: _actionLabels[a] ?? a,
              onChanged: (v) {
                (perms[page] ??= {})[a] = v;
                onChanged();
              },
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_perm.admin) {
      return const ImdPage(children: [
        ImdPageTitle(
          title: 'الصلاحيات والوصول',
          icon: 'users',
          subtitle: 'هذه الشاشة متاحة لمدير النظام فقط.',
        ),
        ImdICard(child: ImdLd('لا تملك صلاحية الوصول إلى مركز الصلاحيات.')),
      ]);
    }
    final rows = _rows();

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'مركز المستخدمين والصلاحيات',
        icon: 'users',
        subtitle: 'صلاحيات دقيقة لكل مستخدم: مشاهدة، إضافة، تعديل، حذف، اعتماد، '
            'طباعة وتصدير حسب الشاشة.',
      ),
      ImdPanel(
        child: ImdSearchBar(
          controller: _q,
          hint: 'بحث بالاسم أو اسم المستخدم',
          onChanged: (_) => setState(() {}),
          actions: [
            ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _load),
            ImdButton(label: 'إضافة مستخدم جديد', icon: 'plus', small: true, onPressed: _addUser),
            ImdChip('${nf(_users.length)} مستخدم', tone: ImdTone.code),
          ],
        ),
      ),
      if (_loading)
        const ImdLd('⏳ جارٍ التحميل…')
      else
        ImdTable(
          columns: const [
            ImdCol('المستخدم'),
            ImdCol('الدور'),
            ImdCol('الحالة'),
            ImdCol('النطاق'),
            ImdCol('إدارة الوصول'),
            ImdCol('إجراء'),
          ],
          empty: 'لا نتائج',
          rows: [for (final u in rows) _row(u)],
        ),
    ]);
  }

  List<Widget> _row(User u) {
    final c = context.imd;
    final (statusLabel, statusTone) = _statusChip(u);
    final scope = UsersRepo.scopeOf(u);
    final isMe = _isMe(u);
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(u.name.isEmpty ? '—' : u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(u.username, style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
      u.role == 'admin'
          ? const ImdChip('مدير النظام', tone: ImdTone.err, icon: 'award')
          : const ImdChip('مستخدم', tone: ImdTone.ok),
      ImdChip(statusLabel, tone: statusTone),
      Text(scope == null ? 'كل المستودعات' : scope.join('، ')),
      isMe
          ? const ImdChip('أنت', tone: ImdTone.ok)
          : Wrap(spacing: 6, runSpacing: 6, children: [
              ImdButton(
                label: _status(u) == 'ACTIVE'
                    ? 'إيقاف'
                    : (_status(u) == 'PENDING' ? 'اعتماد وتفعيل' : 'تفعيل'),
                icon: _status(u) == 'ACTIVE' ? 'ban' : 'unlock',
                small: true,
                kind: _status(u) == 'ACTIVE' ? ImdBtnKind.danger : ImdBtnKind.primary,
                onPressed: () => _toggleAccess(u),
              ),
              ImdButton.outline(
                label: u.role == 'admin' ? 'جعله مستخدمًا' : 'منحه مديرًا',
                icon: u.role == 'admin' ? 'arrow-down' : 'arrow-up',
                small: true,
                onPressed: () => _toggleRole(u),
              ),
            ]),
      ImdButton(
        label: 'ضبط الصلاحيات',
        icon: 'sliders',
        small: true,
        onPressed: isMe ? null : () => _openPermissions(u),
      ),
    ];
  }
}
