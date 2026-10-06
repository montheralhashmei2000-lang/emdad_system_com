import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../imd_icon.dart';
import '../imd_tokens.dart';
import 'imd_buttons.dart';
import 'imd_fields.dart';

/// رسالة سوداء عائمة.
void showImdToast(BuildContext context, String message, {bool error = false}) {
  final c = context.imd;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  // أقصى عرض 420 يتقلّص على الشاشة الضيقة: الهامش الجانبي يُحسب من العرض المتاح
  // (`SnackBar` لا يقبل `width` و`margin` معًا، ولا يقبل قيدًا أقصى مباشرًا).
  final side = ((MediaQuery.sizeOf(context).width - 420) / 2).clamp(16.0, double.infinity);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(side, 0, side, 12),
      backgroundColor: c.inverse,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(milliseconds: 3200),
      content: ImdEmojiText(
        error && !message.startsWith('✖') ? '✖ $message' : message,
        // الإشعار يُعرض في طبقة فوق الشاشة فلا يرث خط التطبيق تلقائيًا،
        // فيُؤخذ من القالب صراحةً ليتبع الخط المختار في الإعدادات.
        style: TextStyle(
          color: c.onInverse,
          fontWeight: FontWeight.w500,
          fontSize: 14,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
      ),
    ));
}

/// نافذة بزوايا 16.
Future<T?> showImdModal<T>(
  BuildContext context, {
  required String title,
  String? icon,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? actions,
  double maxWidth = 560,

  /// يُبنى بسياق الحوار الداخلي (كـ[actions]) ويُستدعى عند Enter/Numpad Enter
  /// — لحوارات التأكيد البسيطة ذات إجراءٍ أساسيٍّ واحد لا لبس فيه. يُترك
  /// `null` (الافتراضي) لحوارات النماذج التي قد تحوي حقول نصٍّ متعددة
  /// الأسطر، فلا يُصادَر Enter منها.
  VoidCallback Function(BuildContext)? onEnter,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: context.imd.scrim,
    builder: (ctx) {
      final c = ctx.imd;
      Widget dialog = Dialog(
        backgroundColor: c.surface,
        elevation: 10,
        shadowColor: c.shadowBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (icon != null) ...[ImdIcon(icon, size: 18, color: c.accent), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  ImdIconButton(icon: 'x', onPressed: () => Navigator.of(ctx).pop()),
                ]),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: builder(ctx))),
                if (actions != null) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions(ctx)),
                ],
              ],
            ),
          ),
        ),
      );
      if (onEnter != null) {
        final enterAction = onEnter(ctx);
        dialog = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): enterAction,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): enterAction,
          },
          child: Focus(autofocus: true, child: dialog),
        );
      }
      return dialog;
    },
  );
}

/// حوار تأكيدٍ بسؤالٍ وزرَّي موافقة وإلغاء.
Future<bool> imdConfirm(
  BuildContext context,
  String message, {
  String ok = 'تأكيد',
  String cancel = 'إلغاء',
  bool danger = false,
}) async {
  final r = await showImdModal<bool>(
    context,
    title: 'تأكيد',
    icon: danger ? 'alert' : 'info',
    maxWidth: 440,
    builder: (ctx) => Text(message, style: TextStyle(fontSize: 14, color: ctx.imd.text, height: 1.7)),
    actions: (ctx) => [
      ImdButton.outline(label: cancel, onPressed: () => Navigator.of(ctx).pop(false)),
      ImdButton(
        label: ok,
        kind: danger ? ImdBtnKind.danger : ImdBtnKind.primary,
        onPressed: () => Navigator.of(ctx).pop(true),
      ),
    ],
    onEnter: (ctx) => () => Navigator.of(ctx).pop(true),
  );
  return r ?? false;
}

/// حوار إدخال نصٍّ واحد.
Future<String?> imdPrompt(BuildContext context, String message, {String ok = 'تأكيد', String initial = ''}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showImdModal<String>(
    context,
    title: message,
    icon: 'edit',
    maxWidth: 460,
    builder: (ctx) => TextField(
      controller: ctrl,
      autofocus: true,
      maxLines: 3,
      minLines: 1,
      style: TextStyle(fontSize: 14, color: ctx.imd.text),
      decoration: imdFieldDecoration(ctx),
      onSubmitted: (v) => Navigator.of(ctx).pop(v),
    ),
    actions: (ctx) => [
      ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
      ImdButton(label: ok, onPressed: () => Navigator.of(ctx).pop(ctrl.text)),
    ],
  );
  ctrl.dispose();
  return r;
}
