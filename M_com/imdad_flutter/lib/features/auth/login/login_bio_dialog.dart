part of '../login_screen.dart';

enum _BioChoice { enable, later, never }

/// عرض تفعيل البصمة بعد أول دخولٍ ناجح بكلمة المرور.
class _BioOfferDialog extends StatelessWidget {
  const _BioOfferDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accent.withValues(alpha: .12), shape: BoxShape.circle),
                child: ImdIcon('fingerprint', size: 34, color: c.accent),
              ),
            ),
            const SizedBox(height: 16),
            Text('الدخول بالبصمة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 8),
            Text('ادخل في المرات القادمة ببصمتك دون كتابة كلمة المرور. تبقى كلمة المرور مطلوبةً إن غيّرتها.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6, color: c.text2)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, _BioChoice.enable),
              child: const Text('تفعيل الآن'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _BioChoice.later),
                  child: Text('لاحقًا', style: TextStyle(color: c.text2)),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _BioChoice.never),
                  child: Text('لا تسألني مجددًا', style: TextStyle(color: c.muted)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
