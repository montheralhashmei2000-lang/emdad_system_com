import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/idle_lock.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';

/// يلفّ التطبيق: يرصد نشاط المستخدم (لمس/فأرة) ويُظهر غطاء القفل فوق كل شيء
/// حين يقفل [IdleLock]. المحتوى يبقى مبنيًّا خلف الغطاء فلا تضيع حالته، لكنه
/// معزول عن اللمس والتركيز (لا تُكتب فيه مفاتيح ولا تعمل اختصاراته).
class IdleLockHost extends StatelessWidget {
  const IdleLockHost({
    super.key,
    required this.lock,
    required this.auth,
    required this.onSignOut,
    required this.child,
  });

  final IdleLock lock;
  final AuthService auth;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lock,
        builder: (context, _) => Stack(textDirection: TextDirection.rtl, children: [
          Positioned.fill(
            child: ExcludeFocus(
              excluding: lock.locked,
              child: IgnorePointer(
                ignoring: lock.locked,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => lock.touch(),
                  onPointerMove: (_) => lock.touch(),
                  onPointerHover: (_) => lock.touch(),
                  onPointerSignal: (_) => lock.touch(),
                  child: child,
                ),
              ),
            ),
          ),
          if (lock.locked)
            Positioned.fill(child: IdleLockScreen(lock: lock, auth: auth, onSignOut: onSignOut)),
        ]),
      );
}

/// غطاء القفل: كلمة المرور لفتح الشاشة، أو تسجيل الخروج.
class IdleLockScreen extends StatefulWidget {
  const IdleLockScreen({super.key, required this.lock, required this.auth, required this.onSignOut});

  final IdleLock lock;
  final AuthService auth;
  final Future<void> Function() onSignOut;

  @override
  State<IdleLockScreen> createState() => _IdleLockScreenState();
}

class _IdleLockScreenState extends State<IdleLockScreen> {
  final _pass = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final user = widget.auth.currentUser;
    if (user == null) {
      await widget.onSignOut();
      return;
    }
    if (_pass.text.isEmpty) {
      setState(() => _error = '✖ أدخل كلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    // نفس مسار الدخول: عدّاد المحاولات والقفل المؤقت بعد الإخفاق المتكرر.
    final res = await widget.auth.login(user.username, _pass.text);
    if (!mounted) return;
    if (res.isOk) {
      _pass.clear();
      widget.lock.unlock();
      return;
    }
    setState(() {
      _busy = false;
      _error = res.message;
      _pass.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final user = widget.auth.currentUser;
    final name = user == null ? '' : (user.name.isNotEmpty ? user.name : user.username);
    return Material(
      color: c.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): _unlock},
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: ImdIcon('lock', size: 36, color: c.accent)),
                  const SizedBox(height: 12),
                  Text('الشاشة مقفلة',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 6),
                  Text('قُفل النظام لخمولٍ طويل${name.isEmpty ? '' : ' — $name'}',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
                  const SizedBox(height: 18),
                  ImdLabeled('كلمة المرور', ImdFld(controller: _pass, obscure: true, enabled: !_busy)),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(_error, style: TextStyle(fontSize: 13, color: c.danger)),
                    ),
                  const SizedBox(height: 10),
                  ImdButton(label: 'فتح', icon: 'lock', busy: _busy, onPressed: _unlock),
                  const SizedBox(height: 8),
                  ImdButton.outline(label: 'تسجيل الخروج', onPressed: _busy ? null : widget.onSignOut),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
