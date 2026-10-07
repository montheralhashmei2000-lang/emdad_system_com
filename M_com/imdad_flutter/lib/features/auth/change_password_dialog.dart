import 'package:flutter/material.dart';

import '../../core/print/print_preview.dart' show imdNavigatorKey;
import '../../core/security/auth_service.dart';
import '../../core/security/password_hash.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/users_repo.dart';

/// نافذة «تغيير كلمة المرور» للمستخدم نفسه: يُثبت كلمته الحالية ثم يضع جديدة
/// بـ ٨ أحرف فأكثر. تُفتح من تنبيه الترقية بعد الدخول.
///
/// تُفتح بسياق الملاحة العام ([imdNavigatorKey]) لأنها تُستدعى من SnackBar يبقى
/// بعد انتقال الواجهة من شاشة الدخول إلى الرئيسية.
Future<void> showChangePasswordDialog({
  required AppDatabase db,
  required String userId,
}) async {
  final context = imdNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;

  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final error = ValueNotifier<String>('');

  Future<bool> submit() async {
    if (next.text.length < AuthService.minPasswordLength) {
      error.value = '✖ كلمة المرور الجديدة ${AuthService.minPasswordLength} أحرف على الأقل';
      return false;
    }
    if (next.text != confirm.text) {
      error.value = '✖ كلمتا المرور غير متطابقتين';
      return false;
    }
    final user = await UsersRepo(db).byId(userId);
    if (user == null) {
      error.value = '✖ تعذّر العثور على الحساب';
      return false;
    }
    final ok = await PasswordHash.verify(current.text, user.saltHex, user.hashHex, user.iterations);
    if (!ok) {
      error.value = '✖ كلمة المرور الحالية غير صحيحة';
      return false;
    }
    try {
      await UsersRepo(db).resetPassword(id: userId, password: next.text);
      await AuditRepo(db).log(
        action: 'user.password_change',
        entityType: 'مستخدم',
        summary: 'غيّر المستخدم ${user.username} كلمة مروره بنفسه',
        actorEmail: user.email,
      );
    } catch (e) {
      error.value = '✖ ${e is ArgumentError ? e.message : e}';
      return false;
    }
    return true;
  }

  final saved = await showImdModal<bool>(
    context,
    title: 'تغيير كلمة المرور',
    icon: 'user',
    maxWidth: 440,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdLabeled('كلمة المرور الحالية', ImdFld(controller: current, obscure: true)),
      const SizedBox(height: 10),
      ImdLabeled(
        'كلمة المرور الجديدة',
        ImdFld(controller: next, obscure: true, hint: '٨ أحرف فأكثر'),
      ),
      const SizedBox(height: 10),
      ImdLabeled('تأكيد كلمة المرور الجديدة', ImdFld(controller: confirm, obscure: true)),
      ValueListenableBuilder<String>(
        valueListenable: error,
        builder: (_, msg, __) => msg.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(msg, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
      ),
    ]),
    actions: (ctx) => [
      ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop(false)),
      ImdButton(
        label: 'حفظ',
        icon: 'save',
        onPressed: () async {
          final ok = await submit();
          if (ok && ctx.mounted) Navigator.of(ctx).pop(true);
        },
      ),
    ],
  );

  if (saved == true && context.mounted) showImdToast(context, '✔ غُيّرت كلمة المرور');
  for (final c in [current, next, confirm]) {
    c.dispose();
  }
  error.dispose();
}
