import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';

/// خيار «الدخول بالبصمة» في الإعدادات: تفعيلٌ وإلغاءٌ لحساب المستخدم الحالي
/// على هذا الجهاز. يظهر على أندرويد وحده، وبشرط وجود بصمةٍ مسجَّلة في النظام
/// (أو تفعيلٍ سابق يحتاج صاحبه إلى إلغائه).
class BiometricSettingTile extends StatefulWidget {
  const BiometricSettingTile({super.key});

  @override
  State<BiometricSettingTile> createState() => _BiometricSettingTileState();
}

class _BiometricSettingTileState extends State<BiometricSettingTile> {
  late final AuthService _auth = context.read<AuthService>();
  late final BiometricService _bio = BiometricService(context.read<AppDatabase>(), _auth);

  bool _loading = true;
  bool _supported = false;
  String? _enrolledId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final avail = await _bio.availability();
    final id = await _bio.enrolledUserId();
    if (!mounted) return;
    setState(() {
      // الإلغاء متاحٌ دائمًا لمن فعّل، حتى لو أُزيلت بصماته من إعدادات الهاتف.
      _supported = avail == BiometricAvailability.available || id != null;
      _enrolledId = id;
      _loading = false;
    });
  }

  Future<void> _enable() async {
    final user = _auth.currentUser;
    if (user == null || _busy) return;
    setState(() => _busy = true);
    final ok = await _bio.enroll(user);
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, ok ? '✔ فُعِّل الدخول بالبصمة' : '✖ لم يُفعَّل الدخول بالبصمة', error: !ok);
    await _refresh();
  }

  Future<void> _disable() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _bio.disable();
    if (!mounted) return;
    setState(() => _busy = false);
    showImdToast(context, '✔ أُلغي الدخول بالبصمة — سيُطلب الدخول بكلمة المرور');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_supported) return const SizedBox.shrink();
    final c = context.imd;
    final me = _auth.currentUser?.id;
    final mine = _enrolledId != null && _enrolledId == me;
    final other = _enrolledId != null && !mine;
    final String status = mine
        ? 'مفعّل لحسابك على هذا الجهاز'
        : other
            ? 'مفعّل لحسابٍ آخر على هذا الجهاز — تفعيله لك سيستبدله'
            : 'غير مفعّل';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.subtle,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ImdIcon('fingerprint', size: 26, color: mine ? c.accent : c.muted),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 160, maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('الدخول بالبصمة',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(fontSize: 12, height: 1.6, color: c.muted)),
              ]),
            ),
            if (mine)
              ImdButton.outline(label: 'إلغاء البصمة', icon: 'x', small: true, onPressed: _busy ? null : _disable)
            else
              ImdButton.outline(
                  label: 'تفعيل البصمة', icon: 'fingerprint', small: true, onPressed: _busy ? null : _enable),
          ],
        ),
      ),
    );
  }
}
