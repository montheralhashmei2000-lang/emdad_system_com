import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/owner_promotion.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';

/// تحديد مالك النظام — يظهر حين لا مالك وفي الجهاز أكثر من مدير (فلا ترقية
/// تلقائية). يختار المدير الحالي أحدهم ويؤكّد بكلمة مروره.
class OwnerSelectionCard extends StatefulWidget {
  const OwnerSelectionCard({super.key, required this.onAssigned});

  /// بعد التحديد الناجح — لتُعاد قراءة الشاشة.
  final VoidCallback onAssigned;

  @override
  State<OwnerSelectionCard> createState() => _OwnerSelectionCardState();
}

class _OwnerSelectionCardState extends State<OwnerSelectionCard> {
  late final AuthService _auth = context.read<AuthService>();
  late final AppDatabase _db = context.read<AppDatabase>();
  final _password = TextEditingController();

  List<User> _candidates = const [];
  String _picked = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // لا بطاقة على جهاز فرع ولا حين يوجد مالك أو مديرٌ واحد فقط.
    final list = await _auth.ownerSelectionNeeded() ? await OwnerPromotion.candidates(_db) : const <User>[];
    if (!mounted) return;
    setState(() {
      _candidates = list;
      if (_picked.isEmpty && list.isNotEmpty) _picked = list.first.id;
    });
  }

  String _label(User u) => u.name.isNotEmpty ? '${u.name} (${u.username})' : u.username;

  Future<void> _assign() async {
    if (_picked.isEmpty || _busy) return;
    final who = _candidates.firstWhere((u) => u.id == _picked);
    final ok = await imdConfirm(
      context,
      'تحديد «${_label(who)}» مالكًا للنظام؟\n\n'
      'المالك وحده يملك النسخ الاحتياطي وتفعيل الأجهزة والمزامنة وتعديل صلاحيات '
      'الآخرين، ولا يمكن تعطيله ولا حذفه من شاشة المستخدمين.',
      ok: 'تحديد المالك',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await _auth.assignOwner(userId: _picked, confirmPassword: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) {
      showImdToast(context, '✖ تعذّر التحديد — تحقق من كلمة المرور', error: true);
      return;
    }
    _password.clear();
    showImdToast(context, '✔ حُدِّد المالك');
    widget.onAssigned();
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.length < 2) return const SizedBox.shrink();
    return ImdPanel(
      title: 'تحديد مالك النظام',
      icon: 'shield',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ImdNote('يوجد أكثر من مدير ولم يُحدَّد مالك بعد. حدّد من يملك الصلاحيات الخاصة '
            '(النسخ الاحتياطي، تفعيل الأجهزة، المزامنة، تعديل الصلاحيات). لا يُعاد التحديد لاحقًا من هذه الشاشة.'),
        const SizedBox(height: 12),
        ImdLabeled(
          'المالك',
          ImdSelect<String>(
            items: [for (final u in _candidates) (u.id, _label(u))],
            value: _picked,
            onChanged: (v) => setState(() => _picked = v ?? _picked),
          ),
        ),
        const SizedBox(height: 10),
        ImdLabeled('كلمة مرورك للتأكيد', ImdFld(controller: _password, obscure: true)),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ImdButton(label: 'تحديد المالك', icon: 'check', busy: _busy, onPressed: _assign),
        ),
      ]),
    );
  }
}
